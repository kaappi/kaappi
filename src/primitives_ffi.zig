const std = @import("std");
const platform = @import("platform.zig");
const types = @import("types.zig");
const primitives = @import("primitives.zig");
const memory = @import("memory.zig");
const vm_mod = @import("vm.zig");
const Value = types.Value;
const PrimitiveError = primitives.PrimitiveError;
const LS = primitives.LibSet;

const ffi_callback = @import("ffi_callback.zig");

pub const specs = [_]primitives.PrimSpec{
    .{ .name = "ffi-open", .func = &ffiOpen, .arity = .{ .exact = 1 }, .libs = LS.initOne(.kaappi_ffi), .sandbox = false, .wasm = false },
    .{ .name = "ffi-fn", .func = &ffiFn, .arity = .{ .exact = 4 }, .libs = LS.initOne(.kaappi_ffi), .sandbox = false, .wasm = false },
    .{ .name = "ffi-close", .func = &ffiClose, .arity = .{ .exact = 1 }, .libs = LS.initOne(.kaappi_ffi), .sandbox = false, .wasm = false },
    .{ .name = "ffi-callback", .func = &ffiCallbackFn, .arity = .{ .exact = 3 }, .libs = LS.initOne(.kaappi_ffi), .sandbox = false, .wasm = false },
    .{ .name = "ffi-callback-release", .func = &ffiCallbackRelease, .arity = .{ .exact = 1 }, .libs = LS.initOne(.kaappi_ffi), .sandbox = false, .wasm = false },
    .{ .name = "ffi-callback?", .func = &ffiCallbackPred, .arity = .{ .exact = 1 }, .libs = LS.initOne(.kaappi_ffi), .sandbox = false, .wasm = false },
    .{ .name = "ffi-bytevector-ptr", .func = &ffiBytevectorPtr, .arity = .{ .exact = 1 }, .libs = LS.initOne(.kaappi_ffi), .sandbox = false, .wasm = false },
};

fn checkSandbox(comptime name: []const u8) PrimitiveError!void {
    const vm = vm_mod.vm_instance orelse return;
    if (vm.sandbox_mode) {
        vm.setErrorDetail(name ++ ": not allowed in sandbox mode", .{});
        return PrimitiveError.TypeError; // bare-ok: sandbox guard with detail
    }
}

/// dlopen(3) treats a name containing a slash as a pathname (relative or
/// absolute) rather than a search key. The <home>/lib/ fallback in ffiOpen
/// mirrors that distinction: prepending the fallback dir to a path would
/// probe nonsense like "<home>/lib//opt/foo/libbar.dylib.so".
fn hasPathSeparator(name: []const u8) bool {
    if (std.mem.indexOfScalar(u8, name, '/') != null) return true;
    return platform.is_windows and std.mem.indexOfScalar(u8, name, '\\') != null;
}

/// platform.dl_suffixes joined with "/" (e.g. ".dylib/.so/.so.6"), for the
/// "also tried" note in ffiOpen's not-found diagnostic.
const dl_suffix_list = blk: {
    var s: []const u8 = "";
    for (platform.dl_suffixes, 0..) |suffix, i| {
        if (i > 0) s = s ++ "/";
        s = s ++ suffix;
    }
    break :blk s;
};

/// Failure diagnostics for ffiOpen's candidate probing. dlerror(3) only
/// remembers the most recent failure, so without snapshots the fallback
/// probes would bury the interesting error under a "no such file" for a
/// candidate path the user never asked for. Two snapshots are kept: the
/// as-is attempt's error (the name the user actually passed), and the
/// error of the first candidate that exists on disk but still failed to
/// load — a code-signing, architecture, or file-format rejection is the
/// failure that matters, wherever it fell in the probe order.
const DlOpenDiag = struct {
    first_buf: [256]u8 = undefined,
    first_len: usize = 0,
    real_buf: [256]u8 = undefined,
    real_len: usize = 0,
    real_cand_buf: [512]u8 = undefined,
    real_cand_len: usize = 0,

    fn noteFailure(self: *DlOpenDiag, candidate: [:0]const u8, is_first: bool) void {
        // Read dlerror before the existence probe: reading consumes the
        // pending error, and on Windows the text is rendered from
        // GetLastError() at read time, which the probe's own syscalls
        // would overwrite.
        const err_msg = platform.dlError() orelse return;
        const text = std.mem.span(err_msg);
        if (is_first) self.first_len = copyInto(&self.first_buf, text);
        if (self.real_len == 0 and platform.pathExists(candidate)) {
            self.real_len = copyInto(&self.real_buf, text);
            self.real_cand_len = copyInto(&self.real_cand_buf, candidate);
        }
    }

    fn firstErr(self: *const DlOpenDiag) ?[]const u8 {
        return if (self.first_len > 0) self.first_buf[0..self.first_len] else null;
    }

    fn realErr(self: *const DlOpenDiag) ?[]const u8 {
        return if (self.real_len > 0) self.real_buf[0..self.real_len] else null;
    }

    fn realCand(self: *const DlOpenDiag) []const u8 {
        return self.real_cand_buf[0..self.real_cand_len];
    }

    fn copyInto(dst: []u8, src: []const u8) usize {
        const n = @min(dst.len, src.len);
        @memcpy(dst[0..n], src[0..n]);
        return n;
    }
};

/// (ffi-open path-or-#f)
/// Opens a shared library. Pass #f for the default process (all linked symbols).
fn ffiOpen(args: []const Value) PrimitiveError!Value {
    try checkSandbox("ffi-open");
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;

    if (args[0] == types.FALSE) {
        // Open default process (all linked symbols including libc)
        const handle = platform.dlOpen(null) orelse return primitives.typeError("ffi-open", "openable library", args[0]);
        return gc.allocFfiLibrary(handle, "default") catch return PrimitiveError.OutOfMemory;
    }

    if (!types.isString(args[0])) return primitives.typeError("ffi-open", "string", args[0]);
    const str = types.toObject(args[0]).as(types.SchemeString);
    const name = str.data[0..str.len];

    // Build null-terminated name
    var buf: [256]u8 = undefined;
    if (str.len >= buf.len) return primitives.typeError("ffi-open", "string shorter than 256 bytes", args[0]);
    @memcpy(buf[0..str.len], name);
    buf[str.len] = 0;
    const cname: [*:0]const u8 = @ptrCast(buf[0..str.len :0]);

    var diag: DlOpenDiag = .{};

    // Try the name as-is
    if (platform.dlOpen(cname)) |handle| {
        return gc.allocFfiLibrary(handle, name) catch return PrimitiveError.OutOfMemory;
    }
    diag.noteFailure(buf[0..str.len :0], true);

    // Try platform library suffixes. ".so.6" covers glibc's core libraries
    // (libm, libc), where the unversioned .so is a linker script that
    // dlopen cannot load.
    for (platform.dl_suffixes) |suffix| {
        if (str.len + suffix.len < buf.len) {
            @memcpy(buf[str.len..][0..suffix.len], suffix);
            buf[str.len + suffix.len] = 0;
            const cname2: [*:0]const u8 = @ptrCast(buf[0 .. str.len + suffix.len :0]);
            if (platform.dlOpen(cname2)) |handle| {
                return gc.allocFfiLibrary(handle, name) catch return PrimitiveError.OutOfMemory;
            }
            diag.noteFailure(buf[0 .. str.len + suffix.len :0], false);
        }
    }

    // Try $KAAPPI_HOME/lib/ (or ~/.kaappi/lib/) as a fallback for installed
    // packages — but only for bare names: dlopen(3) treats a name with a
    // path separator as a pathname, not something to re-search elsewhere.
    const kaappi_paths = @import("kaappi_paths.zig");
    var home_buf: [256]u8 = undefined;
    var searched_home: ?[]const u8 = null;
    if (!hasPathSeparator(name)) {
        if (kaappi_paths.getHome(&home_buf)) |kaappi_home| {
            searched_home = kaappi_home;
            const lib_prefix = "/lib/";
            const home_suffixes: []const []const u8 =
                if (comptime platform.is_windows) &.{ "", ".dll" } else &.{ "", ".dylib", ".so" };
            for (home_suffixes) |suffix| {
                if (kaappi_home.len + lib_prefix.len + str.len + suffix.len < 512) {
                    var pbuf: [512]u8 = undefined;
                    @memcpy(pbuf[0..kaappi_home.len], kaappi_home);
                    @memcpy(pbuf[kaappi_home.len..][0..lib_prefix.len], lib_prefix);
                    @memcpy(pbuf[kaappi_home.len + lib_prefix.len ..][0..str.len], name);
                    @memcpy(pbuf[kaappi_home.len + lib_prefix.len + str.len ..][0..suffix.len], suffix);
                    const total = kaappi_home.len + lib_prefix.len + str.len + suffix.len;
                    pbuf[total] = 0;
                    const pname: [*:0]const u8 = @ptrCast(pbuf[0..total :0]);
                    if (platform.dlOpen(pname)) |handle| {
                        return gc.allocFfiLibrary(handle, name) catch return PrimitiveError.OutOfMemory;
                    }
                    diag.noteFailure(pbuf[0..total :0], false);
                }
            }
        }
    }

    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError; // bare-ok: no VM
    if (diag.realErr()) |err| {
        // A candidate exists on disk but refused to load — report its
        // error, prefixed with the path when the platform's dlerror text
        // (e.g. Windows' bare "Win32 error N") doesn't already name it.
        const cand = diag.realCand();
        if (std.mem.indexOf(u8, err, cand) == null) {
            vm.setErrorDetail("ffi-open: {s}: {s}", .{ cand, err });
        } else {
            vm.setErrorDetail("ffi-open: {s}", .{err});
        }
    } else if (diag.firstErr()) |err| {
        // No candidate existed anywhere: report the as-is attempt's error
        // — it is about the name the user actually asked for — plus a
        // note about the other candidates probed.
        const plain_note = " (also tried " ++ dl_suffix_list ++ " suffixes)";
        var note_buf: [384]u8 = undefined;
        const note: []const u8 = if (searched_home) |home|
            std.fmt.bufPrint(&note_buf, " (also tried {s} suffixes and {s}/lib/)", .{ dl_suffix_list, home }) catch plain_note
        else
            plain_note;
        // Clamp the dlerror text so the note survives the detail buffer:
        // dyld's multi-path "tried:" list alone can overflow it, and the
        // tail of that list is the least useful part of the message.
        const overhead = "ffi-open: ".len + note.len + "cannot open '': ".len + name.len;
        const room = vm.last_error_detail.len -| overhead;
        const err_clamped = err[0..@min(err.len, room)];
        if (std.mem.indexOf(u8, err_clamped, name) == null) {
            vm.setErrorDetail("ffi-open: cannot open '{s}': {s}{s}", .{ name, err_clamped, note });
        } else {
            vm.setErrorDetail("ffi-open: {s}{s}", .{ err_clamped, note });
        }
    } else if (platform.dlError()) |err_msg| {
        const msg = std.mem.span(err_msg);
        vm.setErrorDetail("ffi-open: {s}", .{msg});
    } else {
        vm.setErrorDetail("ffi-open: cannot open '{s}'", .{name});
    }
    return PrimitiveError.TypeError; // bare-ok: detail set above
}

/// (ffi-fn lib "name" '(param-types...) 'return-type)
/// Looks up a symbol in the library and creates an FfiFunction.
fn ffiFn(args: []const Value) PrimitiveError!Value {
    try checkSandbox("ffi-fn");
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;

    // arg0: library
    if (!types.isFfiLibrary(args[0])) return primitives.typeError("ffi-fn", "ffi-library", args[0]);
    const lib = types.toObject(args[0]).as(types.FfiLibrary);
    const handle = lib.handle orelse return primitives.typeError("ffi-fn", "open ffi-library", args[0]);

    // arg1: symbol name (string)
    if (!types.isString(args[1])) return primitives.typeError("ffi-fn", "string", args[1]);
    const name_str = types.toObject(args[1]).as(types.SchemeString);

    // Build null-terminated name for dlsym
    var name_buf: [256]u8 = undefined;
    if (name_str.len >= name_buf.len) return primitives.typeError("ffi-fn", "string shorter than 256 bytes", args[1]);
    @memcpy(name_buf[0..name_str.len], name_str.data[0..name_str.len]);
    name_buf[name_str.len] = 0;
    const cname: [*:0]const u8 = @ptrCast(name_buf[0..name_str.len :0]);

    const symbol = platform.dlSym(handle, cname) orelse {
        const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError; // bare-ok: no VM
        if (platform.dlError()) |err_msg| {
            const msg = std.mem.span(err_msg);
            vm.setErrorDetail("ffi-fn: {s}", .{msg});
        } else {
            vm.setErrorDetail("ffi-fn: symbol '{s}' not found", .{name_str.data[0..name_str.len]});
        }
        return PrimitiveError.TypeError; // bare-ok: detail set above
    };

    // arg2: parameter type list (a Scheme list of symbols)
    var param_types_buf: [16]types.FfiType = undefined;
    var param_count: u8 = 0;
    var param_list = args[2];
    while (param_list != types.NIL) {
        if (!types.isPair(param_list)) return primitives.typeError("ffi-fn", "proper list of types", args[2]);
        if (param_count >= 16) {
            const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError; // bare-ok: no VM
            vm.setErrorDetail("ffi-fn: too many parameters (max 16)", .{});
            return PrimitiveError.TypeError; // bare-ok: detail set above
        }
        const type_sym = types.car(param_list);
        param_types_buf[param_count] = parseType(type_sym) orelse return primitives.typeError("ffi-fn", "valid FFI type symbol", type_sym);
        param_count += 1;
        param_list = types.cdr(param_list);
    }

    // arg3: return type (a symbol)
    const return_type = parseType(args[3]) orelse return primitives.typeError("ffi-fn", "valid FFI type symbol", args[3]);

    return gc.allocFfiFunction(
        symbol,
        args[0],
        name_str.data[0..name_str.len],
        param_types_buf[0..param_count],
        return_type,
    ) catch return PrimitiveError.OutOfMemory;
}

/// (ffi-close lib)
/// Closes a previously opened FFI library.
fn ffiClose(args: []const Value) PrimitiveError!Value {
    try checkSandbox("ffi-close");
    if (!types.isFfiLibrary(args[0])) return primitives.typeError("ffi-close", "ffi-library", args[0]);
    const lib = types.toObject(args[0]).as(types.FfiLibrary);
    if (lib.handle) |handle| {
        _ = platform.dlClose(handle);
        lib.handle = null;
    }
    return types.VOID;
}

/// (ffi-callback proc '(param-types) 'return-type)
fn ffiCallbackFn(args: []const Value) PrimitiveError!Value {
    try checkSandbox("ffi-callback");
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const proc = args[0];
    if (!types.isClosure(proc) and !types.isNativeFn(proc))
        return primitives.typeError("ffi-callback", "procedure", proc);

    // Parse and validate callback signature
    var param_types: [8]types.FfiType = undefined;
    var param_count: u8 = 0;
    var param_list = args[1];
    while (param_list != types.NIL) {
        if (!types.isPair(param_list)) return primitives.typeError("ffi-callback", "proper list of types", args[1]);
        if (param_count >= 8) return primitives.typeError("ffi-callback", "at most 8 parameter types", args[1]);
        param_types[param_count] = parseType(types.car(param_list)) orelse return primitives.typeError("ffi-callback", "valid FFI type symbol", types.car(param_list));
        param_count += 1;
        param_list = types.cdr(param_list);
    }
    const ret_type = parseType(args[2]) orelse return primitives.typeError("ffi-callback", "valid FFI type symbol", args[2]);

    const sig = matchCallbackSig(param_types[0..param_count], ret_type) orelse {
        const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError; // bare-ok: no VM
        vm.setErrorDetail("ffi-callback: unsupported callback signature", .{});
        return PrimitiveError.TypeError; // bare-ok: detail set above
    };

    const slot = ffi_callback.allocSlot(proc, sig) orelse {
        const vm = vm_mod.vm_instance orelse return PrimitiveError.OutOfMemory;
        vm.setErrorDetail("ffi-callback: no free callback slots (max 32)", .{});
        return PrimitiveError.OutOfMemory;
    };

    return gc.allocFfiCallback(proc, slot.index, slot.fn_ptr) catch {
        ffi_callback.releaseSlot(slot.index);
        return PrimitiveError.OutOfMemory;
    };
}

/// (ffi-callback-release cb)
fn ffiCallbackRelease(args: []const Value) PrimitiveError!Value {
    if (!types.isFfiCallback(args[0]))
        return primitives.typeError("ffi-callback-release", "ffi-callback", args[0]);
    const cb = types.toObject(args[0]).as(types.FfiCallback);
    if (cb.active) {
        ffi_callback.releaseSlot(cb.slot_index);
        cb.active = false;
    }
    return types.VOID;
}

/// (ffi-callback? obj)
fn ffiCallbackPred(args: []const Value) PrimitiveError!Value {
    return if (types.isFfiCallback(args[0])) types.TRUE else types.FALSE;
}

/// (ffi-bytevector-ptr bv) — returns data pointer as fixnum or bignum
fn ffiBytevectorPtr(args: []const Value) PrimitiveError!Value {
    try checkSandbox("ffi-bytevector-ptr");
    if (!types.isBytevector(args[0]))
        return primitives.typeError("ffi-bytevector-ptr", "bytevector", args[0]);
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const bv = types.toObject(args[0]).as(types.Bytevector);
    if (bv.data.len == 0) return types.makeFixnum(0);
    const addr: usize = @intFromPtr(bv.data.ptr);
    const signed: i64 = @bitCast(@as(u64, addr));
    const max_fixnum: i64 = 0x7FFF_FFFF_FFFF;
    if (signed >= 0 and signed <= max_fixnum)
        return types.makeFixnum(signed);
    const limbs_buf = [1]u64{addr};
    return gc.allocBignumFromLimbs(&limbs_buf, 1, true) catch return PrimitiveError.OutOfMemory;
}

fn matchCallbackSig(params: []const types.FfiType, ret: types.FfiType) ?ffi_callback.CallbackSig {
    if (params.len == 2 and params[0] == .pointer and params[1] == .pointer and ret == .int)
        return .pp_int;
    if (params.len == 1 and params[0] == .pointer and ret == .void_type)
        return .p_void;
    if (params.len == 0 and ret == .void_type)
        return .v_void;
    if (params.len == 1 and params[0] == .pointer and ret == .int)
        return .p_int;
    if (params.len == 2 and params[0] == .int and params[1] == .pointer and ret == .int)
        return .ip_int;
    if (params.len == 1 and params[0] == .int and ret == .void_type)
        return .i_void;
    if (params.len == 2 and params[0] == .pointer and params[1] == .pointer and ret == .void_type)
        return .pp_void;
    return null;
}

fn parseType(v: Value) ?types.FfiType {
    if (!types.isSymbol(v)) return null;
    const name = types.symbolName(v);
    if (std.mem.eql(u8, name, "int")) return .int;
    if (std.mem.eql(u8, name, "long")) return .long;
    if (std.mem.eql(u8, name, "double")) return .double;
    if (std.mem.eql(u8, name, "float")) return .float;
    if (std.mem.eql(u8, name, "string")) return .string;
    if (std.mem.eql(u8, name, "pointer")) return .pointer;
    if (std.mem.eql(u8, name, "void")) return .void_type;
    if (std.mem.eql(u8, name, "bool")) return .bool_type;
    if (std.mem.eql(u8, name, "uint8")) return .uint8;
    if (std.mem.eql(u8, name, "int8")) return .int8;
    if (std.mem.eql(u8, name, "int16")) return .int16;
    if (std.mem.eql(u8, name, "int32")) return .int32;
    if (std.mem.eql(u8, name, "int64")) return .int64;
    if (std.mem.eql(u8, name, "uint16")) return .uint16;
    if (std.mem.eql(u8, name, "uint32")) return .uint32;
    if (std.mem.eql(u8, name, "uint64")) return .uint64;
    if (std.mem.eql(u8, name, "size_t")) return .size_type;
    if (std.mem.eql(u8, name, "char")) return .char_type;
    return null;
}
