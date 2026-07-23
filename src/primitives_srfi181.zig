//! SRFI 181 — Custom Ports and Transcoded Ports.
//!
//! Custom ports let Scheme code build a port backed by its own read!/
//! write!/get-position/set-position!/close/flush procedures instead of an
//! fd, string buffer, or random source. `id` is documented by the spec as
//! "an arbitrary object" with no accessor defined anywhere -- accepted for
//! arity/signature compliance and discarded, not stored.
//!
//! Transcoded ports are almost entirely portable Scheme (lib/srfi/181.sld):
//! codecs are plain interned symbols, transcoders are a define-record-type,
//! and make-codec/native-eol-style/native-transcoder/bytevector->string/
//! string->bytevector need no native code at all. This file supplies only
//! the four pieces that must be native:
//!   - %transcoded-port: allocates the actual transcoded Port (via
//!     memory.GC.allocTranscodedPort), and is the one place codec/
//!     eol-style/error-mode symbols get validated -- make-transcoder
//!     itself does not eagerly validate (the spec says nothing about
//!     rejecting unrecognized values at construction time, and since
//!     codecs are untyped symbols there is no way to enforce it any
//!     earlier than first use regardless).
//!   - i/o-decoding-error?/i/o-encoding-error?/i/o-encoding-error-char:
//!     accessors for primitives_io.zig's decode/encode loop's `raise`-mode
//!     conditions, which are native ErrorObjects (error_type .io_decoding/
//!     .io_encoding) because the raise *site* is native code deep in
//!     readOneByte/portWriteBytes. unknown-encoding-error? is the mirror
//!     case the other way: make-codec's raise site is portable Scheme, so
//!     that condition is a plain portable record in the .sld instead.
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
//!
//! This file registers under `.srfi_181_primitives` ("srfi.181.primitives"),
//! not a bare `.srfi_181`: the public `(srfi 181)` is `lib/srfi/181.sld`,
//! which imports this sub-library and re-exports its full surface --
//! `vm.libraries`'s startup registration otherwise shadows a same-named
//! `.sld` outright (see `.srfi_248_primitives` for the identical, already-
//! solved problem). Because `(srfi 181)` now loads via the normal
//! `.sld`-file path, it depends on `lib/srfi/181.sld` being present in
//! `vm_library.zig`'s sandbox-embedded table for `--sandbox` availability
//! (see that file) -- unlike this file's own primitives, which remain
//! available under sandbox/WASM regardless.

const std = @import("std");
const types = @import("types.zig");
const primitives = @import("primitives.zig");
const memory = @import("memory.zig");
const vm_mod = @import("vm.zig");
const Value = types.Value;
const PrimitiveError = primitives.PrimitiveError;
const LS = primitives.LibSet;

const SRFI181 = LS.initOne(.srfi_181_primitives);

pub const specs = [_]primitives.PrimSpec{
    .{ .name = "make-custom-binary-input-port", .func = &makeCustomBinaryInputPort, .arity = .{ .exact = 5 }, .libs = SRFI181 },
    .{ .name = "make-custom-binary-output-port", .func = &makeCustomBinaryOutputPort, .arity = .{ .variadic = 5 }, .libs = SRFI181 },
    .{ .name = "make-custom-textual-input-port", .func = &makeCustomTextualInputPort, .arity = .{ .exact = 5 }, .libs = SRFI181 },
    .{ .name = "make-custom-textual-output-port", .func = &makeCustomTextualOutputPort, .arity = .{ .variadic = 5 }, .libs = SRFI181 },
    .{ .name = "make-custom-binary-input/output-port", .func = &makeCustomBinaryInputOutputPort, .arity = .{ .variadic = 6 }, .libs = SRFI181 },
    .{ .name = "make-file-error", .func = &makeFileError, .arity = .{ .variadic = 0 }, .libs = SRFI181 },
    .{ .name = "%transcoded-port", .func = &transcodedPortPrim, .arity = .{ .exact = 4 }, .libs = SRFI181 },
    .{ .name = "i/o-decoding-error?", .func = &ioDecodingErrorP, .arity = .{ .exact = 1 }, .libs = SRFI181 },
    .{ .name = "i/o-encoding-error?", .func = &ioEncodingErrorP, .arity = .{ .exact = 1 }, .libs = SRFI181 },
    .{ .name = "i/o-encoding-error-char", .func = &ioEncodingErrorCharFn, .arity = .{ .exact = 1 }, .libs = SRFI181 },
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

fn symbolNameOrNull(v: Value) ?[]const u8 {
    if (!types.isSymbol(v)) return null;
    return types.symbolName(v);
}

fn symbolToCodec(v: Value) ?types.Codec {
    const name = symbolNameOrNull(v) orelse return null;
    if (std.mem.eql(u8, name, "utf-8")) return .utf8;
    return null;
}

fn symbolToEolStyle(v: Value) ?types.EolStyle {
    const name = symbolNameOrNull(v) orelse return null;
    if (std.mem.eql(u8, name, "none")) return .none;
    if (std.mem.eql(u8, name, "lf")) return .lf;
    if (std.mem.eql(u8, name, "crlf")) return .crlf;
    return null;
}

fn symbolToErrorMode(v: Value) ?types.ErrorMode {
    const name = symbolNameOrNull(v) orelse return null;
    if (std.mem.eql(u8, name, "replace")) return .replace;
    if (std.mem.eql(u8, name, "raise")) return .raise;
    return null;
}

/// (%transcoded-port binary-port codec eol-style error-mode) -- the native
/// core of SRFI 181's (transcoded-port binary-port transcoder); the
/// portable wrapper in lib/srfi/181.sld destructures the transcoder
/// record into these four plain arguments so this code never needs to
/// know records exist. is_input/is_output are inherited from
/// binary-port's own directions, per the spec ("a new textual port ...
/// from binary-port"), not passed separately.
fn transcodedPortPrim(args: []const Value) PrimitiveError!Value {
    if (!types.isPort(args[0])) return primitives.typeError("transcoded-port", "port", args[0]);
    const binary_port = types.toObject(args[0]).as(types.Port);
    if (!binary_port.is_binary) return primitives.typeError("transcoded-port", "binary port", args[0]);

    const codec = symbolToCodec(args[1]) orelse return primitives.typeError("transcoded-port", "recognized codec", args[1]);
    const eol_style = symbolToEolStyle(args[2]) orelse return primitives.typeError("transcoded-port", "recognized eol-style", args[2]);
    const error_mode = symbolToErrorMode(args[3]) orelse return primitives.typeError("transcoded-port", "recognized error-handling-mode", args[3]);

    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    return gc.allocTranscodedPort(args[0], binary_port.is_input, binary_port.is_output, codec, eol_style, error_mode) catch PrimitiveError.OutOfMemory;
}

fn ioDecodingErrorP(args: []const Value) PrimitiveError!Value {
    const srfi18 = @import("primitives_srfi18.zig");
    return if (srfi18.isErrorOfType(args[0], .io_decoding)) types.TRUE else types.FALSE;
}

fn ioEncodingErrorP(args: []const Value) PrimitiveError!Value {
    const srfi18 = @import("primitives_srfi18.zig");
    return if (srfi18.isErrorOfType(args[0], .io_encoding)) types.TRUE else types.FALSE;
}

fn ioEncodingErrorCharFn(args: []const Value) PrimitiveError!Value {
    const srfi18 = @import("primitives_srfi18.zig");
    if (!srfi18.isErrorOfType(args[0], .io_encoding))
        return primitives.typeError("i/o-encoding-error-char", "i/o-encoding-error", args[0]);
    return types.toObject(args[0]).as(types.ErrorObject).uncaught_reason;
}
