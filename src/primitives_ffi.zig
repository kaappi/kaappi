const std = @import("std");
const types = @import("types.zig");
const primitives = @import("primitives.zig");
const vm_mod = @import("vm.zig");
const Value = types.Value;
const PrimitiveError = primitives.PrimitiveError;

const ffi_callback = @import("ffi_callback.zig");

pub fn registerFfi(vm: *vm_mod.VM) !void {
    try primitives.reg(vm, "ffi-open", &ffiOpen, .{ .exact = 1 });
    try primitives.reg(vm, "ffi-fn", &ffiFn, .{ .exact = 4 });
    try primitives.reg(vm, "ffi-close", &ffiClose, .{ .exact = 1 });
    try primitives.reg(vm, "ffi-callback", &ffiCallbackFn, .{ .exact = 3 });
    try primitives.reg(vm, "ffi-callback-release", &ffiCallbackRelease, .{ .exact = 1 });
    try primitives.reg(vm, "ffi-callback?", &ffiCallbackPred, .{ .exact = 1 });
    try primitives.reg(vm, "ffi-bytevector-ptr", &ffiBytevectorPtr, .{ .exact = 1 });
}

fn checkSandbox(comptime name: []const u8) PrimitiveError!void {
    const vm = vm_mod.vm_instance orelse return;
    if (vm.sandbox_mode) {
        vm.setErrorDetail(name ++ ": not allowed in sandbox mode", .{});
        return PrimitiveError.TypeError; // bare-ok: sandbox guard with detail
    }
}

/// (ffi-open path-or-#f)
/// Opens a shared library. Pass #f for the default process (all linked symbols).
fn ffiOpen(args: []const Value) PrimitiveError!Value {
    try checkSandbox("ffi-open");
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;

    if (args[0] == types.FALSE) {
        // Open default process (all linked symbols including libc)
        const handle = std.c.dlopen(null, std.c.RTLD{ .LAZY = true }) orelse return PrimitiveError.TypeError;
        return gc.allocFfiLibrary(handle, "default") catch return PrimitiveError.OutOfMemory;
    }

    if (!types.isString(args[0])) return PrimitiveError.TypeError;
    const str = types.toObject(args[0]).as(types.SchemeString);

    // Build null-terminated name
    var buf: [256]u8 = undefined;
    if (str.len >= buf.len) return PrimitiveError.TypeError;
    @memcpy(buf[0..str.len], str.data[0..str.len]);
    buf[str.len] = 0;
    const cname: [*:0]const u8 = @ptrCast(buf[0..str.len :0]);

    // Try the name as-is
    if (std.c.dlopen(cname, std.c.RTLD{ .LAZY = true })) |handle| {
        return gc.allocFfiLibrary(handle, str.data[0..str.len]) catch return PrimitiveError.OutOfMemory;
    }

    // Try platform library suffixes. ".so.6" covers glibc's core libraries
    // (libm, libc), where the unversioned .so is a linker script that
    // dlopen cannot load.
    const platform_suffixes = [_][]const u8{ ".dylib", ".so", ".so.6" };
    for (platform_suffixes) |suffix| {
        if (str.len + suffix.len < buf.len) {
            @memcpy(buf[str.len..][0..suffix.len], suffix);
            buf[str.len + suffix.len] = 0;
            const cname2: [*:0]const u8 = @ptrCast(buf[0 .. str.len + suffix.len :0]);
            if (std.c.dlopen(cname2, std.c.RTLD{ .LAZY = true })) |handle| {
                return gc.allocFfiLibrary(handle, str.data[0..str.len]) catch return PrimitiveError.OutOfMemory;
            }
        }
    }

    // Try ~/.kaappi/lib/ as a fallback for installed packages
    const home = std.c.getenv("HOME");
    if (home) |h| {
        const hlen = std.mem.len(h);
        const prefix = "/.kaappi/lib/";
        const suffixes = [_][]const u8{ "", ".dylib", ".so" };
        for (suffixes) |suffix| {
            if (hlen + prefix.len + str.len + suffix.len < 512) {
                var pbuf: [512]u8 = undefined;
                @memcpy(pbuf[0..hlen], h[0..hlen]);
                @memcpy(pbuf[hlen..][0..prefix.len], prefix);
                @memcpy(pbuf[hlen + prefix.len ..][0..str.len], str.data[0..str.len]);
                @memcpy(pbuf[hlen + prefix.len + str.len ..][0..suffix.len], suffix);
                const total = hlen + prefix.len + str.len + suffix.len;
                pbuf[total] = 0;
                const pname: [*:0]const u8 = @ptrCast(pbuf[0..total :0]);
                if (std.c.dlopen(pname, std.c.RTLD{ .LAZY = true })) |handle| {
                    return gc.allocFfiLibrary(handle, str.data[0..str.len]) catch return PrimitiveError.OutOfMemory;
                }
            }
        }
    }

    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError; // bare-ok: no VM
    if (std.c.dlerror()) |err_msg| {
        const msg = std.mem.span(err_msg);
        vm.setErrorDetail("ffi-open: {s}", .{msg});
    } else {
        vm.setErrorDetail("ffi-open: cannot open '{s}'", .{str.data[0..str.len]});
    }
    return PrimitiveError.TypeError;
}

/// (ffi-fn lib "name" '(param-types...) 'return-type)
/// Looks up a symbol in the library and creates an FfiFunction.
fn ffiFn(args: []const Value) PrimitiveError!Value {
    try checkSandbox("ffi-fn");
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;

    // arg0: library
    if (!types.isFfiLibrary(args[0])) return PrimitiveError.TypeError;
    const lib = types.toObject(args[0]).as(types.FfiLibrary);
    const handle = lib.handle orelse return PrimitiveError.TypeError; // library closed

    // arg1: symbol name (string)
    if (!types.isString(args[1])) return PrimitiveError.TypeError;
    const name_str = types.toObject(args[1]).as(types.SchemeString);

    // Build null-terminated name for dlsym
    var name_buf: [256]u8 = undefined;
    if (name_str.len >= name_buf.len) return PrimitiveError.TypeError;
    @memcpy(name_buf[0..name_str.len], name_str.data[0..name_str.len]);
    name_buf[name_str.len] = 0;
    const cname: [*:0]const u8 = @ptrCast(name_buf[0..name_str.len :0]);

    const symbol = std.c.dlsym(handle, cname) orelse {
        const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError; // bare-ok: no VM
        if (std.c.dlerror()) |err_msg| {
            const msg = std.mem.span(err_msg);
            vm.setErrorDetail("ffi-fn: {s}", .{msg});
        } else {
            vm.setErrorDetail("ffi-fn: symbol '{s}' not found", .{name_str.data[0..name_str.len]});
        }
        return PrimitiveError.TypeError;
    };

    // arg2: parameter type list (a Scheme list of symbols)
    var param_types_buf: [16]types.FfiType = undefined;
    var param_count: u8 = 0;
    var param_list = args[2];
    while (param_list != types.NIL) {
        if (!types.isPair(param_list)) return PrimitiveError.TypeError;
        if (param_count >= 16) {
            const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError; // bare-ok: no VM
            vm.setErrorDetail("ffi-fn: too many parameters (max 16)", .{});
            return PrimitiveError.TypeError;
        }
        const type_sym = types.car(param_list);
        param_types_buf[param_count] = parseType(type_sym) orelse return PrimitiveError.TypeError;
        param_count += 1;
        param_list = types.cdr(param_list);
    }

    // arg3: return type (a symbol)
    const return_type = parseType(args[3]) orelse return PrimitiveError.TypeError;

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
    if (!types.isFfiLibrary(args[0])) return PrimitiveError.TypeError;
    const lib = types.toObject(args[0]).as(types.FfiLibrary);
    if (lib.handle) |handle| {
        _ = std.c.dlclose(handle);
        lib.handle = null;
    }
    return types.VOID;
}

/// (ffi-callback proc '(param-types) 'return-type)
fn ffiCallbackFn(args: []const Value) PrimitiveError!Value {
    try checkSandbox("ffi-callback");
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const proc = args[0];
    if (!types.isClosure(proc) and !types.isNativeFn(proc))
        return primitives.typeError("ffi-callback", "procedure", proc);

    // Parse and validate callback signature
    var param_types: [8]types.FfiType = undefined;
    var param_count: u8 = 0;
    var param_list = args[1];
    while (param_list != types.NIL) {
        if (!types.isPair(param_list)) return PrimitiveError.TypeError;
        if (param_count >= 8) return PrimitiveError.TypeError;
        param_types[param_count] = parseType(types.car(param_list)) orelse return PrimitiveError.TypeError;
        param_count += 1;
        param_list = types.cdr(param_list);
    }
    const ret_type = parseType(args[2]) orelse return PrimitiveError.TypeError;

    const sig = matchCallbackSig(param_types[0..param_count], ret_type) orelse {
        const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError; // bare-ok: no VM
        vm.setErrorDetail("ffi-callback: unsupported callback signature", .{});
        return PrimitiveError.TypeError;
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
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
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
