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

        crash.noteStage(.executing);
        if (vm.handleTopLevelForm(expr)) |top_result| {
            const result = top_result catch |err| {
                toplevel_driver.reportRuntimeError(vm, err, null);
                break;
            };
            var dr = result;
            if (types.isMultipleValues(dr)) {
                const mv = types.toObject(dr).as(types.MultipleValues);
                dr = if (mv.values.len > 0) mv.values[0] else types.VOID;
                if (mode != .show_type) {
                    printValuesLines(allocator, mv.values);
                    if (mode == .store_last and dr != types.VOID) {
                        vm.globalsPut("_", dr) catch {};
                    }
                    continue;
                }
            }
            if (dr != types.VOID) {
                if (mode == .show_type) {
                    writeStdout("; ");
                    writeStdout(types.typeName(dr));
                    writeStdout("\n");
                } else {
                    const s = printer.prettyPrint(allocator, dr, terminal_width) catch
                        (printer.valueToString(allocator, dr, .write) catch continue);
                    defer allocator.free(s);
                    writeStdout(s);
                    writeStdout("\n");
                }
                if (mode == .store_last) {
                    vm.globalsPut("_", dr) catch {};
                }
            }
            continue;
        }

        crash.noteStage(.compiling);
        const func = compiler.compileExpressionWithMacrosAt(vm.gc, expr, &vm.macros, vm.globals, datum_lc.line, "<repl>", false) catch |err| {
            toplevel_driver.reportCompileError("<repl>", datum_lc.line, datum_lc.col, err);
            break;
        };

        var func_val = types.makePointer(&func.header);
        vm.gc.pushRoot(&func_val);

        crash.noteStage(.executing);
        const result = vm.execute(func) catch |err| {
            vm.gc.popRoot();
            toplevel_driver.reportRuntimeError(vm, err, null);
            toplevel_driver.printStackTrace(vm);
            break;
        };
        vm.gc.popRoot();

        var display_result = result;
        if (types.isMultipleValues(display_result)) {
            const mv = types.toObject(display_result).as(types.MultipleValues);
            display_result = if (mv.values.len > 0) mv.values[0] else types.VOID;
            if (mode != .show_type) {
                printValuesLines(allocator, mv.values);
                if (mode == .store_last and display_result != types.VOID) {
                    vm.globalsPut("_", display_result) catch {};
                }
                continue;
            }
        }
        if (display_result != types.VOID) {
            if (mode == .show_type) {
                writeStdout("; ");
                writeStdout(types.typeName(display_result));
                writeStdout("\n");
            } else {
                const s = printer.prettyPrint(allocator, display_result, terminal_width) catch
                    (printer.valueToString(allocator, display_result, .write) catch continue);
                defer allocator.free(s);
                writeStdout(s);
                writeStdout("\n");
            }
            if (mode == .store_last) {
                vm.globalsPut("_", display_result) catch {};
            }
        }
    }
}
