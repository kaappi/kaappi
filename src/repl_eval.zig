//! The REPL's read → compile → execute → print driver.
//!
//! Split out of `repl.zig` (kaappi#2266): the main loop and the comma
//! commands both evaluate Scheme, and this is the single function family that
//! turns a submitted string into printed results. It is the REPL's copy of
//! the toplevel driver (`toplevel_driver.zig` owns the error reporting; this
//! loop owns the pretty-printing and the `_` binding).
//!
//! `EvalMode` distinguishes the three callers: plain evaluation (comma
//! commands like `,step`), evaluation that records the last result into `_`
//! (the main loop), and evaluation that prints only the result's type
//! (`,type`).

const std = @import("std");
const platform = @import("platform.zig");
const is_wasm = @import("builtin").os.tag == .wasi;
const types = @import("types.zig");
const vm_mod = @import("vm.zig");
const compiler = @import("compiler.zig");
const reader = @import("reader.zig");
const printer = @import("printer.zig");
const crash = @import("crash.zig");
const toplevel_driver = @import("toplevel_driver.zig");
const reporting = @import("reporting.zig");

const writeStdout = reporting.writeStdout;

/// Terminal width in columns, for pretty-printing results. Cached at REPL
/// start (`refreshTerminalWidth`) because it can be expensive to query; the
/// WASI fallback has no terminal and keeps the 80-column default.
var terminal_width: u16 = 80;

pub fn refreshTerminalWidth() void {
    if (comptime is_wasm) return;
    terminal_width = platform.terminalWidth() orelse 80;
}

pub const EvalMode = enum { normal, store_last, show_type };

// Multiple values print one per line, matching other Scheme REPLs
// (Chez, Guile, Racket, Chibi). Void values print nothing.
fn printValuesLines(allocator: std.mem.Allocator, values: []const types.Value) void {
    for (values) |val| {
        if (val == types.VOID) continue;
        const s = printer.prettyPrint(allocator, val, terminal_width) catch
            (printer.valueToString(allocator, val, .write) catch continue);
        defer allocator.free(s);
        writeStdout(s);
        writeStdout("\n");
    }
}

pub fn evalInputTyped(vm: *vm_mod.VM, allocator: std.mem.Allocator, input: []const u8, mode: EvalMode) void {
    evalInputInner(vm, allocator, input, mode);
}

pub fn evalInput(vm: *vm_mod.VM, allocator: std.mem.Allocator, input: []const u8) void {
    evalInputInner(vm, allocator, input, .normal);
}

/// Evaluate one already-read top-level expression with the same driver the
/// text path uses, skipping only the reader. `,load` builds `(load "path")`
/// as Values this way so a path is never round-tripped through the reader's
/// string escapes, which would mangle a path containing `"` or `\`
/// (kaappi#2273). The caller may pass an unrooted value; it is rooted here
/// across the compile and execute below.
pub fn evalInputValue(vm: *vm_mod.VM, allocator: std.mem.Allocator, expr: types.Value, mode: EvalMode) void {
    var expr_root = expr;
    vm.gc.pushRoot(&expr_root);
    defer vm.gc.popRoot();
    crash.note(.executing, "<repl>");
    defer crash.reset();
    _ = evalExpr(vm, allocator, expr_root, mode, 0, 0);
}

fn evalInputInner(vm: *vm_mod.VM, allocator: std.mem.Allocator, input: []const u8, mode: EvalMode) void {
    // Crash breadcrumb (kaappi#1514); reset on return so a crash at the idle
    // prompt is not mislabeled as this input's last stage.
    crash.note(.reading, "<repl>");
    defer crash.reset();

    var r = reader.Reader.initWithName(vm.gc, input, "<repl>");
    defer r.deinit();

    while (r.hasMore() catch |err| blk: {
        const lc = r.getLineCol();
        toplevel_driver.reportReadError("<repl>", lc.line, lc.col, err);
        break :blk false;
    }) {
        crash.noteStage(.reading);
        // Datum start position, for a compile error's fallback column when no
        // precise span was recorded (kaappi#1506).
        const datum_lc = r.getLineCol();
        var expr = r.readDatum() catch |err| {
            const lc = r.getLineCol();
            toplevel_driver.reportReadError("<repl>", lc.line, lc.col, err);
            break;
        };

        vm.gc.pushRoot(&expr);
        defer vm.gc.popRoot();

        // The reader loop stops at the first form that errors (a pasted
        // batch fails loud rather than limping on), so a false return from
        // evalExpr breaks out here.
        if (!evalExpr(vm, allocator, expr, mode, datum_lc.line, datum_lc.col)) break;
    }
}

/// The read-independent half of the REPL driver: classify, compile, execute
/// and print one top-level expression. Returns false when evaluation errored
/// (the reader loop treats that as fatal to the batch). Errors report exactly
/// as the reader-driven path does, including the stack trace for runtime
/// errors.
fn evalExpr(vm: *vm_mod.VM, allocator: std.mem.Allocator, expr: types.Value, mode: EvalMode, line: u32, col: u32) bool {
    crash.noteStage(.executing);
    if (vm.handleTopLevelForm(expr)) |top_result| {
        const result = top_result catch |err| {
            toplevel_driver.reportRuntimeError(vm, err, null);
            return false;
        };
        printResult(allocator, result, mode, vm);
        return true;
    }

    crash.noteStage(.compiling);
    const func = compiler.compileExpressionWithMacrosAt(vm.gc, expr, &vm.macros, vm.globals, line, "<repl>", false) catch |err| {
        toplevel_driver.reportCompileError("<repl>", line, col, err);
        return false;
    };

    var func_val = types.makePointer(&func.header);
    vm.gc.pushRoot(&func_val);

    crash.noteStage(.executing);
    const result = vm.execute(func) catch |err| {
        vm.gc.popRoot();
        toplevel_driver.reportRuntimeError(vm, err, null);
        toplevel_driver.printStackTrace(vm);
        return false;
    };
    vm.gc.popRoot();

    printResult(allocator, result, mode, vm);
    return true;
}

/// Print one evaluation result (or the first of a multiple-values result) the
/// way the interactive loop does, and record it into `_` in store-last mode.
fn printResult(allocator: std.mem.Allocator, result: types.Value, mode: EvalMode, vm: *vm_mod.VM) void {
    var dr = result;
    if (types.isMultipleValues(dr)) {
        const mv = types.toObject(dr).as(types.MultipleValues);
        dr = if (mv.values.len > 0) mv.values[0] else types.VOID;
        if (mode != .show_type) {
            printValuesLines(allocator, mv.values);
            if (mode == .store_last and dr != types.VOID) {
                vm.globalsPut("_", dr) catch {};
            }
            return;
        }
    }
    if (dr == types.VOID) return;
    if (mode == .show_type) {
        writeStdout("; ");
        writeStdout(types.typeName(dr));
        writeStdout("\n");
    } else {
        const s = printer.prettyPrint(allocator, dr, terminal_width) catch
            (printer.valueToString(allocator, dr, .write) catch return);
        defer allocator.free(s);
        writeStdout(s);
        writeStdout("\n");
    }
    if (mode == .store_last) {
        vm.globalsPut("_", dr) catch {};
    }
}
