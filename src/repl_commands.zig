//! The REPL's comma commands: `,help`, `,load`, `,break`, `,time`, …
//!
//! Split out of `repl.zig` (kaappi#2266). The command-name completion the
//! editor offers after a leading `,` and the dispatch itself
//! (`handleCommand`) are the two entry points; both are independent of the
//! main loop, the completeness check, and the highlighter. `handleCommand`
//! returns tri-state so the caller can tell an ordinary handled command from
//! `,quit`/`,exit`, which must end the REPL rather than continue it.
//!
//! Under the WASI fallback (no tty layer) the editor does not exist, so the
//! `ic.*` references in the completion helpers are only ever analyzed when
//! `repl()` is — which `main.zig` never reaches on that target. The
//! `use_isocline` gate is the same one `repl.zig` uses.
//!
//! GC safety: the handlers that build or expand Scheme values through the VM
//! follow the rules in `.claude/rules/gc-safety.md` — `,import` barriers its
//! spine writes (old→young edges must reach the remembered set) and `,expand`
//! roots the datum and its expansion across the allocating calls.

const std = @import("std");
const is_wasm = @import("builtin").os.tag == .wasi;
const platform = @import("platform.zig");
const types = @import("types.zig");
const vm_mod = @import("vm.zig");
const reader = @import("reader.zig");
const printer = @import("printer.zig");
const vm_library = @import("vm_library.zig");
const reporting = @import("reporting.zig");
const expander = @import("expander.zig");
const repl_eval = @import("repl_eval.zig");

const use_isocline = !is_wasm;
const ic = if (use_isocline) @import("isocline.zig") else struct {};

const version = @import("main.zig").version;
const writeStdout = reporting.writeStdout;
const writeStderr = reporting.writeStderr;

const repl_commands = [_][*:0]const u8{
    ",time ",  ",type ",       ",describe ", ",apropos ",
    ",env ",   ",profile ",    ",expand ",   ",gc",
    ",break ", ",breakpoints", ",delete ",   ",step ",
    ",help",   ",quit",        ",exit",      ",version",
    ",load ",  ",import ",     ",dis ",      ",condition ",
};

/// Word-char rule for comma-command names: only a space ends the "word", so
/// the leading ',' is included and `ic.completeWord` deletes the whole typed
/// command (not just the part after it) before splicing in the replacement.
pub fn isCommandChar(s: [*c]const u8, len: c_long) callconv(.c) bool {
    if (len != 1) return true;
    return s[0] != ' ';
}

pub fn completeCommandNameCallback(cenv: ?*ic.CompletionEnv, prefix: [*c]const u8) callconv(.c) void {
    const word = if (prefix) |p| std.mem.span(@as([*:0]const u8, @ptrCast(p))) else return;
    for (&repl_commands) |cmd| {
        if (std.mem.startsWith(u8, std.mem.span(cmd), word)) {
            if (!ic.addCompletion(cenv, cmd)) return;
        }
    }
}

/// How `handleCommand` classified the submitted line.
pub const CommandResult = enum { not_command, handled, quit };

/// Dispatch one submitted form. `input` is the line with surrounding
/// whitespace stripped, matching the main loop's `debug_trimmed`. Returns
/// `.handled` for a recognized comma command (or an unrecognized one, which is
/// reported as an error here), `.quit` for `,quit`/`,exit`, and
/// `.not_command` when `input` is Scheme for the main loop to evaluate.
pub fn handleCommand(vm: *vm_mod.VM, allocator: std.mem.Allocator, input: []const u8) CommandResult {
    const debug_trimmed = input;

    // Debug commands (comma-prefixed)
    if (std.mem.startsWith(u8, debug_trimmed, ",break ")) {
        const bp_name_src = std.mem.trim(u8, debug_trimmed[7..], " ");
        if (vm.breakpoint_count >= 16) {
            writeStdout("Too many breakpoints (max 16)\n");
            return .handled;
        }
        const bp_name = allocator.dupe(u8, bp_name_src) catch return .handled;
        vm.breakpoints[vm.breakpoint_count] = .{ .name = bp_name };
        vm.breakpoint_count += 1;
        vm.debug_mode = true;
        vm.step_mode = .continue_to_break;
        writeStdout("Breakpoint set on ");
        writeStdout(bp_name);
        writeStdout("\n");
        return .handled;
    }
    if (std.mem.startsWith(u8, debug_trimmed, ",condition ")) {
        const rest = std.mem.trim(u8, debug_trimmed[11..], " ");
        if (std.mem.indexOfScalar(u8, rest, ' ')) |space| {
            const id_str = rest[0..space];
            const expr = std.mem.trim(u8, rest[space + 1 ..], " ");
            const id = std.fmt.parseInt(usize, id_str, 10) catch {
                writeStdout("Usage: ,condition <id> <expr>\n");
                return .handled;
            };
            if (id < vm.breakpoint_count) {
                const owned_expr = allocator.dupe(u8, expr) catch return .handled;
                if (vm.breakpoints[id].condition) |old_cond| allocator.free(old_cond);
                vm.breakpoints[id].condition = owned_expr;
                writeStdout("Condition set\n");
            } else {
                writeStdout("Invalid breakpoint ID\n");
            }
        } else {
            writeStdout("Usage: ,condition <id> <expr>\n");
        }
        return .handled;
    }
    if (std.mem.eql(u8, debug_trimmed, ",breakpoints")) {
        for (vm.breakpoints[0..vm.breakpoint_count], 0..) |bp, idx| {
            var dbuf: [64]u8 = undefined;
            const s = std.fmt.bufPrint(&dbuf, "  [{d}] {s}", .{ idx, bp.name }) catch "";
            writeStdout(s);
            if (bp.condition) |cond| {
                writeStdout(" if ");
                writeStdout(cond);
            }
            writeStdout("\n");
        }
        if (vm.breakpoint_count == 0) {
            writeStdout("  (no breakpoints)\n");
        }
        return .handled;
    }
    if (std.mem.eql(u8, debug_trimmed, ",delete all")) {
        for (vm.breakpoints[0..vm.breakpoint_count]) |bp| {
            allocator.free(bp.name);
            if (bp.condition) |cond| allocator.free(cond);
        }
        vm.breakpoint_count = 0;
        vm.debug_mode = false;
        vm.step_mode = .none;
        writeStdout("All breakpoints deleted\n");
        return .handled;
    }
    if (std.mem.startsWith(u8, debug_trimmed, ",step ")) {
        const step_expr = debug_trimmed[6..];
        const saved_debug = vm.debug_mode;
        const saved_step = vm.step_mode;
        vm.debug_mode = true;
        vm.step_mode = .step;
        repl_eval.evalInput(vm, allocator, step_expr);
        vm.debug_mode = saved_debug;
        vm.step_mode = saved_step;
        return .handled;
    }
    if (std.mem.startsWith(u8, debug_trimmed, ",time ")) {
        const time_expr = debug_trimmed[6..];
        const t0 = platform.monotonicNs();
        repl_eval.evalInput(vm, allocator, time_expr);
        const t1 = platform.monotonicNs();
        const secs = @as(f64, @floatFromInt(t1 - t0)) / 1_000_000_000.0;
        var tbuf: [64]u8 = undefined;
        const ts_str = std.fmt.bufPrint(&tbuf, "; {d:.3} seconds\n", .{secs}) catch "; ? seconds\n";
        writeStdout(ts_str);
        return .handled;
    }
    if (std.mem.startsWith(u8, debug_trimmed, ",profile ")) {
        const profile_expr = debug_trimmed[9..];
        reporting.resetProfileCounters(vm.gc);
        vm.profile_mode = true;
        repl_eval.evalInput(vm, allocator, profile_expr);
        vm.profile_mode = false;
        reporting.printProfileReport(vm.gc);
        return .handled;
    }
    if (std.mem.eql(u8, debug_trimmed, ",gc")) {
        reporting.printGcStats(vm.gc);
        return .handled;
    }
    if (std.mem.eql(u8, debug_trimmed, ",quit") or std.mem.eql(u8, debug_trimmed, ",exit")) {
        return .quit;
    }
    if (std.mem.eql(u8, debug_trimmed, ",version")) {
        writeStdout("Kaappi Scheme v" ++ version ++ "\n");
        return .handled;
    }
    if (std.mem.startsWith(u8, debug_trimmed, ",load ")) {
        const load_path = std.mem.trim(u8, debug_trimmed[6..], " ");
        if (load_path.len == 0) {
            writeStderr(",load requires a file path\n");
        } else {
            // Build `(load "path")` as Values instead of splicing the path
            // into a string literal: the reader's escapes (`\"`, `\\`,
            // `\t`, ...) would mangle a path containing a quote or a
            // backslash — on Windows every path does (kaappi#2273).
            // evalInputValue evaluates the form with the same driver as the
            // text path, errors included.
            //
            // Assign before rooting (matching `,expand`/`,import` below): the
            // slot must hold a valid value before any later call can collect
            // — allocString/allocSymbol copy their bytes, then maybeCollect()
            // *before* returning, and markRoots dereferences every rooted
            // slot, so rooting an undefined slot would let garbage bits that
            // happen to look like a pointer corrupt the heap (kaappi#2274
            // review). path_val is rooted before allocSymbol (the next
            // allocation) and sym_val before the allocPair calls; allocPair
            // roots its Value arguments internally.
            var path_val = vm.gc.allocString(load_path) catch {
                writeStderr("out of memory\n");
                return .handled;
            };
            vm.gc.pushRoot(&path_val);
            defer vm.gc.popRoot();
            var sym_val = vm.gc.allocSymbol("load") catch {
                writeStderr("out of memory\n");
                return .handled;
            };
            vm.gc.pushRoot(&sym_val);
            defer vm.gc.popRoot();
            const args = vm.gc.allocPair(path_val, types.NIL) catch {
                writeStderr("out of memory\n");
                return .handled;
            };
            const form = vm.gc.allocPair(sym_val, args) catch {
                writeStderr("out of memory\n");
                return .handled;
            };
            repl_eval.evalInputValue(vm, allocator, form, .normal);
        }
        return .handled;
    }
    if (std.mem.startsWith(u8, debug_trimmed, ",import ")) {
        const import_expr = debug_trimmed[8..];
        var ir = reader.Reader.init(vm.gc, import_expr);
        defer ir.deinit();
        var import_list = types.NIL;
        var import_root = import_list;
        vm.gc.pushRoot(&import_root);
        var read_ok = true;
        while (ir.hasMore() catch false) {
            var datum = ir.readDatum() catch {
                writeStderr("read error in import spec\n");
                read_ok = false;
                break;
            };
            vm.gc.pushRoot(&datum);
            const pair = vm.gc.allocPair(datum, types.NIL) catch {
                vm.gc.popRoot();
                writeStderr("out of memory\n");
                read_ok = false;
                break;
            };
            vm.gc.popRoot();
            if (import_root == types.NIL) {
                import_root = pair;
                import_list = pair;
            } else {
                // Old→young edge once a collection promotes the spine: barrier
                // it or a minor GC can free the fresh pair while the list
                // still references it (see .claude/rules/gc-safety.md).
                const tail_obj = types.toObject(import_list);
                tail_obj.as(types.Pair).cdr = pair;
                vm.gc.writeBarrier(tail_obj, pair);
                import_list = pair;
            }
        }
        if (read_ok and import_root != types.NIL) {
            _ = vm_library.handleImport(vm, import_root) catch {
                const detail = vm.getErrorDetail();
                if (detail.len > 0) {
                    writeStderr("import error: ");
                    writeStderr(detail);
                    writeStderr("\n");
                } else {
                    writeStderr("import error\n");
                }
            };
        }
        vm.gc.popRoot();
        return .handled;
    }
    if (std.mem.startsWith(u8, debug_trimmed, ",dis ")) {
        const dis_expr = debug_trimmed[5..];
        var dis_buf: [1024]u8 = undefined;
        const dis_call = std.fmt.bufPrint(&dis_buf, "(disassemble {s})", .{dis_expr}) catch {
            writeStderr("expression too long\n");
            return .handled;
        };
        repl_eval.evalInput(vm, allocator, dis_call);
        return .handled;
    }
    if (std.mem.eql(u8, debug_trimmed, ",help")) {
        writeStdout(
            \\Commands:
            \\  ,help             Show this message
            \\  ,quit             Exit the REPL
            \\
            \\ -- Evaluation:
            \\  ,time <expr>      Measure execution time
            \\  ,type <expr>      Show result type
            \\  ,expand <expr>    Show macro expansion
            \\  ,profile <expr>   Profile timing, calls, and allocations
            \\  ,dis <expr>       Disassemble a procedure
            \\
            \\ -- Inspection:
            \\  ,describe <sym>   Show procedure arity and type
            \\  ,apropos <str>    Search bindings by substring
            \\  ,env [prefix]     List bindings (optionally filtered by prefix)
            \\
            \\ -- Debugging:
            \\  ,break <name>     Set breakpoint on function
            \\  ,breakpoints      List active breakpoints
            \\  ,delete all       Clear all breakpoints
            \\  ,step <expr>      Evaluate with single-stepping
            \\  ,condition <id> <expr>  Set breakpoint condition
            \\
            \\ -- Structural editing (moves a paren, not a character):
            \\  alt-shift-S       Slurp: pull the next datum into the form
            \\  alt-shift-B       Barf: push the last datum out of the form
            \\  alt-shift-R       Raise: replace the form with the datum at point
            \\  alt-y             Rotate the form's arguments
            \\  F1                All editor keys
            \\
            \\ -- System:
            \\  ,gc               Show GC statistics
            \\  ,version          Show Kaappi version
            \\  ,load <file>      Load and run a Scheme file
            \\  ,import <lib>     Import a library (e.g. ,import (srfi 1))
            \\
            \\The variable _ holds the last result.
            \\
        );
        return .handled;
    }
    if (std.mem.startsWith(u8, debug_trimmed, ",type ")) {
        const type_expr = debug_trimmed[6..];
        repl_eval.evalInputTyped(vm, allocator, type_expr, .show_type);
        return .handled;
    }
    if (std.mem.startsWith(u8, debug_trimmed, ",describe ")) {
        const sym_name = std.mem.trim(u8, debug_trimmed[10..], " ");
        describeSymbol(vm, sym_name);
        return .handled;
    }
    if (std.mem.startsWith(u8, debug_trimmed, ",apropos ")) {
        const needle = std.mem.trim(u8, debug_trimmed[9..], " ");
        var env_count: usize = 0;
        var git3 = vm.globals.keyIterator();
        while (git3.next()) |key| {
            if (needle.len == 0 or std.mem.indexOf(u8, key.*, needle) != null) {
                writeStdout("  ");
                writeStdout(key.*);
                writeStdout("\n");
                env_count += 1;
            }
        }
        var cbuf2: [64]u8 = undefined;
        const cs2 = std.fmt.bufPrint(&cbuf2, "; {d} matches\n", .{env_count}) catch "\n";
        writeStdout(cs2);
        return .handled;
    }
    if (std.mem.startsWith(u8, debug_trimmed, ",expand ")) {
        const expand_src = debug_trimmed[8..];
        var er = reader.Reader.init(vm.gc, expand_src);
        defer er.deinit();
        // The datum and its expansion outlive allocating calls below
        // (expandMacro, stripUsertextMarkers), so root them per
        // .claude/rules/gc-safety.md — a collection in between would free
        // them while the expander or printer still holds the pointers.
        var expr = er.readDatum() catch {
            writeStderr("read error\n");
            return .handled;
        };
        vm.gc.pushRoot(&expr);
        defer vm.gc.popRoot();
        if (types.isPair(expr) and types.isSymbol(types.car(expr))) {
            const ename = types.symbolName(types.car(expr));
            if (vm.macros.get(ename)) |transformer| {
                var expanded = expander.expandMacro(vm.gc, expr, transformer, vm.globals, &vm.macros, .{}) catch {
                    writeStderr("expansion error\n");
                    return .handled;
                };
                vm.gc.pushRoot(&expanded);
                defer vm.gc.popRoot();
                var expanded_stripped = expanded;
                if (expander.isUsertextPair(expanded_stripped)) expanded_stripped = expander.unwrapUsertext(expanded_stripped);
                if (types.isPair(expanded_stripped) or types.isVector(expanded_stripped)) expander.stripUsertextMarkers(vm.gc, expanded_stripped);
                const s = printer.valueToString(allocator, expanded_stripped, .write) catch "";
                defer if (s.len > 0) allocator.free(s);
                writeStdout(s);
                writeStdout("\n");
            } else {
                writeStderr("not a macro: ");
                writeStderr(ename);
                writeStderr("\n");
            }
        } else {
            writeStderr("not a macro invocation\n");
        }
        return .handled;
    }
    if (std.mem.eql(u8, debug_trimmed, ",env") or std.mem.startsWith(u8, debug_trimmed, ",env ")) {
        const prefix = if (debug_trimmed.len > 5) std.mem.trim(u8, debug_trimmed[5..], " ") else "";
        var env_count: usize = 0;
        var git2 = vm.globals.keyIterator();
        while (git2.next()) |key| {
            if (prefix.len == 0 or std.mem.startsWith(u8, key.*, prefix)) {
                writeStdout("  ");
                writeStdout(key.*);
                writeStdout("\n");
                env_count += 1;
            }
        }
        var cbuf: [64]u8 = undefined;
        const cs = std.fmt.bufPrint(&cbuf, "; {d} bindings\n", .{env_count}) catch "\n";
        writeStdout(cs);
        return .handled;
    }

    // Catch-all for unrecognized or incomplete comma commands
    if (debug_trimmed.len > 0 and debug_trimmed[0] == ',') {
        const usage = getCommandUsage(debug_trimmed);
        if (usage) |msg| {
            writeStderr(msg);
        } else {
            writeStderr("unknown command: ");
            const end = std.mem.indexOfScalar(u8, debug_trimmed, ' ') orelse debug_trimmed.len;
            writeStderr(debug_trimmed[0..end]);
            writeStderr("\nType ,help for available commands.\n");
        }
        return .handled;
    }
    return .not_command;
}

fn getCommandUsage(input: []const u8) ?[]const u8 {
    const cmd = blk: {
        const end = std.mem.indexOfScalar(u8, input, ' ') orelse input.len;
        break :blk input[0..end];
    };
    const commands = [_]struct { name: []const u8, usage: []const u8 }{
        .{ .name = ",time", .usage = "usage: ,time <expr>\n" },
        .{ .name = ",type", .usage = "usage: ,type <expr>\n" },
        .{ .name = ",describe", .usage = "usage: ,describe <symbol>\n" },
        .{ .name = ",apropos", .usage = "usage: ,apropos <string>\n" },
        .{ .name = ",expand", .usage = "usage: ,expand <expr>\n" },
        .{ .name = ",profile", .usage = "usage: ,profile <expr>\n" },
        .{ .name = ",step", .usage = "usage: ,step <expr>\n" },
        .{ .name = ",break", .usage = "usage: ,break <name>\n" },
        .{ .name = ",load", .usage = "usage: ,load <file>\n" },
        .{ .name = ",import", .usage = "usage: ,import <lib>  (e.g. ,import (srfi 1))\n" },
        .{ .name = ",dis", .usage = "usage: ,dis <expr>\n" },
        .{ .name = ",delete", .usage = "usage: ,delete all\n" },
        .{ .name = ",condition", .usage = "usage: ,condition <id> <expr>\n" },
    };
    for (&commands) |entry| {
        if (std.mem.eql(u8, cmd, entry.name)) return entry.usage;
    }
    return null;
}

fn describeSymbol(vm: *vm_mod.VM, name: []const u8) void {
    const val_opt = vm.globals.get(name);
    if (val_opt == null) {
        writeStdout("  not found: ");
        writeStdout(name);
        writeStdout("\n");
        return;
    }
    const val = val_opt.?;
    writeStdout("  ");
    writeStdout(name);
    writeStdout("\n    type: ");
    writeStdout(types.typeName(val));
    writeStdout("\n");

    if (types.isPointer(val)) {
        const obj = types.toObject(val);
        if (obj.tag == .native_fn) {
            const nfn = obj.as(types.NativeFn);
            var abuf: [64]u8 = undefined;
            switch (nfn.arity) {
                .exact => |n| {
                    const s = std.fmt.bufPrint(&abuf, "    arity: {d}\n", .{n}) catch "";
                    writeStdout(s);
                },
                .variadic => |min| {
                    const s = std.fmt.bufPrint(&abuf, "    arity: {d}+\n", .{min}) catch "";
                    writeStdout(s);
                },
            }
        } else if (obj.tag == .closure) {
            const cls = obj.as(types.Closure);
            const func = cls.func;
            var abuf: [128]u8 = undefined;
            const s = std.fmt.bufPrint(&abuf, "    arity: {d}, locals: {d}\n", .{ func.arity, func.locals_count }) catch "";
            writeStdout(s);
            if (func.source_name) |src| {
                writeStdout("    source: ");
                writeStdout(src);
                var lbuf: [32]u8 = undefined;
                const ls = std.fmt.bufPrint(&lbuf, ":{d}\n", .{func.source_line}) catch "\n";
                writeStdout(ls);
            }
        } else if (obj.tag == .transformer) {
            writeStdout("    (syntax transformer)\n");
        }
    }
}
