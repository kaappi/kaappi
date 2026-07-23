//! SRFI 181 — Custom Ports (this pass: the 5 port constructors only).
//!
//! Lets Scheme code build a port backed by its own read!/write!/
//! get-position/set-position!/close/flush procedures instead of an fd,
//! string buffer, or random source. `id` is documented by the spec as "an
//! arbitrary object" with no accessor defined anywhere -- accepted for
//! arity/signature compliance and discarded, not stored.
//!
//! Transcoded ports (make-transcoder, codecs, eol-styles, the `raise`
//! error-handling mode's continuable-condition semantics) are a separable
//! follow-up (see the tracking issue filed alongside this) -- they need
//! their own substantial machinery (vm.callHandler-based continuable
//! conditions, a codec/eol-style representation) independent of the
//! GC-marking and reentrant-call work this file's constructors are built
//! on.
//!
//! **Blocking limitation**: every callback here runs through
//! vm.callWithArgs, which always executes with vm.dispatched_from_scheduler
//! forced false (see fiber.zig's raiseCustomPortCallbackBlocked and the
//! in_custom_port_callback guard) -- a callback that blocks on another
//! port's fd or calls thread-sleep! is rejected with a catchable error
//! rather than risking the native-stack-overflow a silent recursive
//! scheduler drive would otherwise allow. Callbacks must be effectively
//! synchronous, non-blocking Scheme code.
//!
//! Sandbox/WASM availability: unlike SRFI 192 (real OS lseek) or SRFI 18/
//! 170/FFI (real threads/OS info/native code), nothing here touches
//! platform.zig or any OS syscall at all -- every operation is a Scheme-
//! level vm.callWithArgs call, exactly as privileged as calling any other
//! user-defined procedure. So this library needs no sandboxAllowed/
//! wasmAvailable exclusion; it falls into Lib's `else => true` default for
//! both.

const std = @import("std");
const types = @import("types.zig");
const primitives = @import("primitives.zig");
const memory = @import("memory.zig");
const vm_mod = @import("vm.zig");
const Value = types.Value;
const PrimitiveError = primitives.PrimitiveError;
const LS = primitives.LibSet;

const SRFI181 = LS.initOne(.srfi_181);

pub const specs = [_]primitives.PrimSpec{
    .{ .name = "make-custom-binary-input-port", .func = &makeCustomBinaryInputPort, .arity = .{ .exact = 5 }, .libs = SRFI181 },
    .{ .name = "make-custom-binary-output-port", .func = &makeCustomBinaryOutputPort, .arity = .{ .variadic = 5 }, .libs = SRFI181 },
    .{ .name = "make-custom-textual-input-port", .func = &makeCustomTextualInputPort, .arity = .{ .exact = 5 }, .libs = SRFI181 },
    .{ .name = "make-custom-textual-output-port", .func = &makeCustomTextualOutputPort, .arity = .{ .variadic = 5 }, .libs = SRFI181 },
    .{ .name = "make-custom-binary-input/output-port", .func = &makeCustomBinaryInputOutputPort, .arity = .{ .variadic = 6 }, .libs = SRFI181 },
    .{ .name = "make-file-error", .func = &makeFileError, .arity = .{ .variadic = 0 }, .libs = SRFI181 },
};

/// Must be a procedure -- used for the mandatory read!/write! argument,
/// which (unlike get-position/set-position!/close/flush) has no "absent"
/// convention in the spec.
fn expectRequiredProc(proc: []const u8, v: Value) PrimitiveError!Value {
    if (!types.isProcedure(v)) return primitives.typeError(proc, "procedure", v);
    return v;
}

/// Either #f ("absent") or a procedure -- used for get-position/
/// set-position!/close/flush.
fn expectOptionalProc(proc: []const u8, v: Value) PrimitiveError!Value {
    if (v == types.FALSE or types.isProcedure(v)) return v;
    return primitives.typeError(proc, "procedure or #f", v);
}

fn overApplied(proc: []const u8, max: usize, got: usize) PrimitiveError {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.ArityMismatch;
    vm.setErrorDetail("'{s}': expected at most {d} arguments, got {d}", .{ proc, max, got });
    return PrimitiveError.ArityMismatch;
}

fn makeCustomBinaryInputPort(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const read_proc = try expectRequiredProc("make-custom-binary-input-port", args[1]);
    const get_position_proc = try expectOptionalProc("make-custom-binary-input-port", args[2]);
    const set_position_proc = try expectOptionalProc("make-custom-binary-input-port", args[3]);
    const close_proc = try expectOptionalProc("make-custom-binary-input-port", args[4]);
    return gc.allocCustomPort(true, false, true, read_proc, types.FALSE, get_position_proc, set_position_proc, close_proc, types.FALSE) catch PrimitiveError.OutOfMemory;
}

fn makeCustomBinaryOutputPort(args: []const Value) PrimitiveError!Value {
    if (args.len > 6) return overApplied("make-custom-binary-output-port", 6, args.len);
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const write_proc = try expectRequiredProc("make-custom-binary-output-port", args[1]);
    const get_position_proc = try expectOptionalProc("make-custom-binary-output-port", args[2]);
    const set_position_proc = try expectOptionalProc("make-custom-binary-output-port", args[3]);
    const close_proc = try expectOptionalProc("make-custom-binary-output-port", args[4]);
    const flush_proc = if (args.len == 6) try expectOptionalProc("make-custom-binary-output-port", args[5]) else types.FALSE;
    return gc.allocCustomPort(false, true, true, types.FALSE, write_proc, get_position_proc, set_position_proc, close_proc, flush_proc) catch PrimitiveError.OutOfMemory;
}

fn makeCustomTextualInputPort(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const read_proc = try expectRequiredProc("make-custom-textual-input-port", args[1]);
    const get_position_proc = try expectOptionalProc("make-custom-textual-input-port", args[2]);
    const set_position_proc = try expectOptionalProc("make-custom-textual-input-port", args[3]);
    const close_proc = try expectOptionalProc("make-custom-textual-input-port", args[4]);
    return gc.allocCustomPort(true, false, false, read_proc, types.FALSE, get_position_proc, set_position_proc, close_proc, types.FALSE) catch PrimitiveError.OutOfMemory;
}

fn makeCustomTextualOutputPort(args: []const Value) PrimitiveError!Value {
    if (args.len > 6) return overApplied("make-custom-textual-output-port", 6, args.len);
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const write_proc = try expectRequiredProc("make-custom-textual-output-port", args[1]);
    const get_position_proc = try expectOptionalProc("make-custom-textual-output-port", args[2]);
    const set_position_proc = try expectOptionalProc("make-custom-textual-output-port", args[3]);
    const close_proc = try expectOptionalProc("make-custom-textual-output-port", args[4]);
    const flush_proc = if (args.len == 6) try expectOptionalProc("make-custom-textual-output-port", args[5]) else types.FALSE;
    return gc.allocCustomPort(false, true, false, types.FALSE, write_proc, get_position_proc, set_position_proc, close_proc, flush_proc) catch PrimitiveError.OutOfMemory;
}

fn makeCustomBinaryInputOutputPort(args: []const Value) PrimitiveError!Value {
    if (args.len > 7) return overApplied("make-custom-binary-input/output-port", 7, args.len);
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const read_proc = try expectRequiredProc("make-custom-binary-input/output-port", args[1]);
    const write_proc = try expectRequiredProc("make-custom-binary-input/output-port", args[2]);
    const get_position_proc = try expectOptionalProc("make-custom-binary-input/output-port", args[3]);
    const set_position_proc = try expectOptionalProc("make-custom-binary-input/output-port", args[4]);
    const close_proc = try expectOptionalProc("make-custom-binary-input/output-port", args[5]);
    const flush_proc = if (args.len == 7) try expectOptionalProc("make-custom-binary-input/output-port", args[6]) else types.FALSE;
    return gc.allocCustomPort(true, true, true, read_proc, write_proc, get_position_proc, set_position_proc, close_proc, flush_proc) catch PrimitiveError.OutOfMemory;
}

/// (make-file-error obj ...) -- an object satisfying R7RS file-error?.
/// ErrorObject already has a .file error_type (used by file-error? in
/// primitives_control.zig); this just constructs one, treating the first
/// argument (if any) as the message and the rest as irritants, mirroring
/// how (error message . irritants) itself is shaped.
fn makeFileError(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    var message: Value = types.FALSE;
    if (args.len > 0) {
        message = args[0];
        gc.pushRoot(&message);
    }
    defer if (args.len > 0) gc.popRoot();
    const irritants = if (args.len > 1) gc.makeList(args[1..]) catch return PrimitiveError.OutOfMemory else types.NIL;
    const err = gc.allocErrorObjectCoded(message, irritants, .uncategorized) catch return PrimitiveError.OutOfMemory;
    types.toObject(err).as(types.ErrorObject).error_type = .file;
    return err;
}
