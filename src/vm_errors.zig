//! Error reporting and stack traces inside the VM: the last-error-detail
//! buffer and its location capture, the nearest-defined-name suggestion
//! (`findSimilarName`), the uncaught-exception formatting
//! (`noteUncaughtException`), and the stack-trace snapshot. The `VM` struct
//! keeps thin delegate methods over these (vm.zig), so callers keep using
//! `vm.setErrorDetail(...)` etc.

const std = @import("std");
const types = @import("types.zig");
const Value = types.Value;

const vm_mod = @import("vm.zig");
const VM = vm_mod.VM;

pub fn setErrorDetail(vm: *VM, comptime fmt: []const u8, args: anytype) void {
    const s = std.fmt.bufPrint(&vm.last_error_detail, fmt, args) catch |err| switch (err) {
        error.NoSpaceLeft => {
            vm.last_error_detail_len = vm.last_error_detail.len;
            return;
        },
    };
    vm.last_error_detail_len = s.len;
    captureErrorLocation(vm);
}

pub fn findSimilarName(vm: *VM, name: []const u8) ?[]const u8 {
    var best: ?[]const u8 = null;
    var best_dist: usize = 4;
    // Locks internally — callers (dispatch error paths) must not hold
    // the globals lock when calling this.
    vm.lockGlobalsShared();
    defer vm.unlockGlobalsShared();
    var iter = vm.globals.keyIterator();
    while (iter.next()) |key| {
        const candidate = key.*;
        if (candidate.len == 0 or candidate[0] == '%') continue;
        const dist = editDistance(name, candidate);
        if (dist > 0 and dist < best_dist) {
            best_dist = dist;
            best = candidate;
        }
    }
    return best;
}

fn editDistance(a: []const u8, b: []const u8) usize {
    if (a.len > 32 or b.len > 32) return 99;
    var prev: [33]usize = undefined;
    var curr: [33]usize = undefined;
    for (0..b.len + 1) |j| prev[j] = j;
    for (a, 0..) |ca, i| {
        curr[0] = i + 1;
        for (b, 0..) |cb, j| {
            const cost: usize = if (ca == cb) 0 else 1;
            curr[j + 1] = @min(@min(curr[j] + 1, prev[j + 1] + 1), prev[j] + cost);
        }
        @memcpy(prev[0 .. b.len + 1], curr[0 .. b.len + 1]);
    }
    return prev[b.len];
}

fn captureErrorLocation(vm: *VM) void {
    vm.last_error_line = 0;
    vm.last_error_col = 0;
    vm.last_error_source = null;
    if (vm.frame_count == 0) return;
    var i = vm.frame_count;
    while (i > 0) {
        i -= 1;
        if (vm.frames[i].closure) |cls| {
            const func = cls.func;
            if (func.line_table.items.len > 0) {
                const ip = if (vm.frames[i].ip > 0) vm.frames[i].ip - 1 else 0;
                const loc = func.locForOffset(ip);
                if (loc.line > 0) {
                    vm.last_error_line = loc.line;
                    vm.last_error_col = loc.col;
                    vm.last_error_source = func.source_name;
                    return;
                }
            }
            if (func.source_line > 0) {
                vm.last_error_line = func.source_line;
                vm.last_error_col = 0;
                vm.last_error_source = func.source_name;
                return;
            }
        }
    }
}

pub fn getErrorDetail(vm: *VM) []const u8 {
    return vm.last_error_detail[0..vm.last_error_detail_len];
}

/// Writes `eo`'s own `message` + `irritants` (display mode for the
/// message, write mode for each irritant, matching R7RS `error`'s
/// display convention) to `w`. Shared by `noteUncaughtException`'s
/// top-level object and its `uncaught_reason` unwrap loop below.
fn writeErrorObjectMessage(w: *std.Io.Writer, allocator: std.mem.Allocator, eo: *types.ErrorObject) void {
    const printer = @import("printer.zig");
    if (printer.valueToString(allocator, eo.message, .display)) |msg| {
        defer allocator.free(msg);
        w.writeAll(msg) catch {};
    } else |_| {}
    var it = eo.irritants;
    while (types.isPair(it)) {
        const pair = types.toObject(it).as(types.Pair);
        if (printer.valueToString(allocator, pair.car, .write)) |s| {
            defer allocator.free(s);
            w.writeAll(" ") catch {};
            w.writeAll(s) catch {};
        } else |_| {}
        it = pair.cdr;
    }
}

/// Called from execute()'s error path, before resetExecutionState()
/// discards the pending exception. If the escaping error is an uncaught
/// Scheme exception and no native error detail was recorded, format the
/// exception payload (message + irritants for error objects) into the
/// detail buffer so top-level error printers show the message instead of
/// the raw Zig error name. Consumes the pending exception.
pub fn noteUncaughtException(vm: *VM, err: anyerror) void {
    if (err != error.ExceptionRaised) return;
    const exc = vm.current_exception orelse return;
    vm.current_exception = null;
    // Carry the raised object's stable diagnostic code to the reporting
    // layer (KEP-0005), whether or not a native detail was already recorded.
    // `.uncategorized` here means "uncoded raise" and the reporter falls
    // back to the generic KP3000 uncaught-exception code.
    if (types.isErrorObject(exc)) {
        vm.last_error_code = types.toObject(exc).as(types.ErrorObject).code;
    }
    if (vm.last_error_detail_len != 0) return;

    const printer = @import("printer.zig");
    const allocator = vm.gc.allocator;
    var w: std.Io.Writer = .fixed(&vm.last_error_detail);
    if (types.isErrorObject(exc)) {
        var eo = types.toObject(exc).as(types.ErrorObject);
        writeErrorObjectMessage(&w, allocator, eo);
        // kaappi#1742: thread-join! wraps a child thread's failure in a
        // generic "uncaught exception in thread" ErrorObject and
        // stashes the real cause in uncaught_reason (see
        // primitives_srfi18.zig's threadJoinResult) -- a field the
        // message+irritants walk above never reaches, so the default
        // report used to stop at that uninformative wrapper text and
        // hide the one sentence that actually explains the failure,
        // otherwise reachable only via `(error-object-message
        // (uncaught-exception-reason e))` inside a guard. Unwrap it
        // here instead. Bounded: a chain of nested thread-join!s can
        // wrap this arbitrarily deep. Gated on this exact error_type --
        // the only production site that ever sets it is
        // threadJoinResult, so this never fires for the io_decoding/
        // io_encoding error types that reuse the same uncaught_reason
        // field slot for unrelated data (see types.ErrorObject's doc
        // comment).
        var depth: u8 = 0;
        while (eo.error_type == .uncaught_exception and eo.uncaught_reason != types.VOID and depth < 8) : (depth += 1) {
            w.writeAll(": ") catch {};
            if (types.isErrorObject(eo.uncaught_reason)) {
                eo = types.toObject(eo.uncaught_reason).as(types.ErrorObject);
                writeErrorObjectMessage(&w, allocator, eo);
            } else {
                if (printer.valueToString(allocator, eo.uncaught_reason, .write)) |s| {
                    defer allocator.free(s);
                    w.writeAll(s) catch {};
                } else |_| {}
                break;
            }
        }
    } else {
        w.writeAll("uncaught exception: ") catch {};
        if (printer.valueToString(allocator, exc, .write)) |s| {
            defer allocator.free(s);
            w.writeAll(s) catch {};
        } else |_| {}
    }
    vm.last_error_detail_len = w.buffered().len;
}

pub const StackFrame = struct {
    name: ?[]const u8,
    source: ?[]const u8,
    line: u32,
};

pub fn getStackTrace(vm: *VM, buf: []StackFrame) usize {
    var count: usize = 0;
    if (vm.frame_count == 0) return 0;
    var i = vm.frame_count;
    while (i > 0 and count < buf.len) {
        i -= 1;
        if (vm.frames[i].closure) |cls| {
            const func = cls.func;
            // Use instruction-level line number when available
            var line = func.source_line;
            if (func.line_table.items.len > 0) {
                const ip = if (vm.frames[i].ip > 0) vm.frames[i].ip - 1 else 0;
                const precise = func.lineForOffset(ip);
                if (precise > 0) line = precise;
            }
            if (line > 0 or func.name != null) {
                if (count > 0) {
                    const prev = buf[count - 1];
                    if (prev.line == line and
                        std.mem.eql(u8, prev.source orelse "", func.source_name orelse ""))
                        continue;
                }
                buf[count] = .{
                    .name = func.name,
                    .source = func.source_name,
                    .line = line,
                };
                count += 1;
            }
        }
    }
    return count;
}

pub fn getLastStackTrace(vm: *VM) []const StackFrame {
    return vm.last_stack_trace[0..vm.last_stack_trace_len];
}
