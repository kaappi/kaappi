const std = @import("std");
const types = @import("types.zig");
const vm_mod = @import("vm.zig");
const primitives = @import("primitives.zig");
const reader_mod = @import("reader.zig");
const compiler_mod = @import("compiler.zig");
const printer = @import("printer.zig");
const Value = types.Value;
const NativeFn = types.NativeFn;
const PrimitiveError = primitives.PrimitiveError;

fn reg(vm: *vm_mod.VM, name: []const u8, func: types.NativeFnType, arity: NativeFn.Arity) !void {
    return primitives.reg(vm, name, func, arity);
}

pub fn registerR7RS(vm: *vm_mod.VM) !void {
    // (scheme time)
    try reg(vm, "current-second", &currentSecond, .{ .exact = 0 });
    try reg(vm, "current-jiffy", &currentJiffy, .{ .exact = 0 });
    try reg(vm, "jiffies-per-second", &jiffiesPerSecond, .{ .exact = 0 });

    // (scheme process-context)
    try reg(vm, "command-line", &commandLine, .{ .exact = 0 });
    try reg(vm, "exit", &exitFn, .{ .variadic = 0 });
    try reg(vm, "emergency-exit", &emergencyExitFn, .{ .variadic = 0 });
    try reg(vm, "get-environment-variable", &getEnvVar, .{ .exact = 1 });
    try reg(vm, "get-environment-variables", &getEnvVars, .{ .exact = 0 });

    // Parameters (R7RS 4.2.6)
    try reg(vm, "make-parameter", &makeParameterFn, .{ .variadic = 1 });
    try reg(vm, "%parameter-set!", &parameterSetDirectFn, .{ .exact = 2 });

    // (scheme eval)
    try reg(vm, "eval", &evalFn, .{ .variadic = 1 });
    try reg(vm, "environment", &environmentFn, .{ .variadic = 0 });
    try reg(vm, "interaction-environment", &interactionEnvironmentFn, .{ .exact = 0 });
    try reg(vm, "null-environment", &nullEnvironmentFn, .{ .exact = 1 });
    try reg(vm, "scheme-report-environment", &schemeReportEnvironmentFn, .{ .exact = 1 });

    // (scheme load)
    try reg(vm, "load", &loadFn, .{ .exact = 1 });

    // (kaappi debug)
    try reg(vm, "disassemble", &disassembleFn, .{ .exact = 1 });
}

pub fn registerR7RSSandboxed(vm: *vm_mod.VM) !void {
    try reg(vm, "current-second", &currentSecond, .{ .exact = 0 });
    try reg(vm, "current-jiffy", &currentJiffy, .{ .exact = 0 });
    try reg(vm, "jiffies-per-second", &jiffiesPerSecond, .{ .exact = 0 });
    try reg(vm, "make-parameter", &makeParameterFn, .{ .variadic = 1 });
    try reg(vm, "%parameter-set!", &parameterSetDirectFn, .{ .exact = 2 });
}

fn disassembleFn(args: []const Value) PrimitiveError!Value {
    if (!types.isClosure(args[0])) return primitives.typeError("disassemble", "procedure", args[0]);
    const closure = types.toObject(args[0]).as(types.Closure);
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const disasm = @import("disassembler.zig");
    disasm.disassemble(closure.func, gc.allocator);
    return types.VOID;
}

// ---------------------------------------------------------------------------
// (scheme time) — R7RS 6.14
// ---------------------------------------------------------------------------

fn currentSecond(args: []const Value) PrimitiveError!Value {
    _ = args;

    var ts: std.c.timespec = undefined;
    _ = std.c.clock_gettime(.REALTIME, &ts);
    const secs: f64 = @as(f64, @floatFromInt(ts.sec)) +
        @as(f64, @floatFromInt(ts.nsec)) / 1e9;
    return types.makeFlonum(secs);
}

fn currentJiffy(args: []const Value) PrimitiveError!Value {
    _ = args;
    var ts: std.c.timespec = undefined;
    _ = std.c.clock_gettime(.MONOTONIC, &ts);
    const us: i64 = @as(i64, @intCast(ts.sec)) * 1000000 + @divFloor(@as(i64, @intCast(ts.nsec)), 1000);
    return types.makeFixnum(us);
}

fn jiffiesPerSecond(args: []const Value) PrimitiveError!Value {
    _ = args;
    return types.makeFixnum(1000000); // microseconds per second
}

// ---------------------------------------------------------------------------
// (scheme process-context) — R7RS 6.14
// ---------------------------------------------------------------------------

fn commandLine(args: []const Value) PrimitiveError!Value {
    _ = args;
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError; // bare-ok: no VM

    var result: Value = types.NIL;
    gc.pushRoot(&result) catch return PrimitiveError.OutOfMemory;
    defer gc.popRoot();

    var str_val: Value = types.NIL;
    gc.pushRoot(&str_val) catch return PrimitiveError.OutOfMemory;
    defer gc.popRoot();

    var i = vm.command_line_args.len;
    while (i > 0) {
        i -= 1;
        str_val = gc.allocString(vm.command_line_args[i]) catch return PrimitiveError.OutOfMemory;
        result = gc.allocPair(str_val, result) catch return PrimitiveError.OutOfMemory;
    }
    return result;
}

fn exitCode(args: []const Value) u8 {
    if (args.len > 0 and types.isFixnum(args[0]))
        return @intCast(@as(u64, @bitCast(@as(i64, @intCast(types.toFixnum(args[0]) & 0xFF)))));
    if (args.len > 0 and args[0] == types.FALSE)
        return 1;
    return 0;
}

fn exitFn(args: []const Value) PrimitiveError!Value {
    const code = exitCode(args);
    if (vm_mod.vm_instance) |vm| {
        var i = vm.wind_count;
        while (i > 0) {
            i -= 1;
            _ = vm.callWithArgs(vm.wind_stack[i].after, &[_]Value{}) catch {};
        }
    }
    std.process.exit(code);
}

fn emergencyExitFn(args: []const Value) PrimitiveError!Value {
    std.process.exit(exitCode(args));
}

fn getEnvVar(args: []const Value) PrimitiveError!Value {
    if (!types.isString(args[0])) return primitives.typeError("get-environment-variable", "string", args[0]);
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const str = types.toObject(args[0]).as(types.SchemeString);
    const name = str.data[0..str.len];

    const name_z = gc.allocator.dupeZ(u8, name) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(name_z);

    const env = std.c.getenv(name_z);
    if (env) |val| {
        const val_slice = std.mem.span(val);
        return gc.allocString(val_slice) catch return PrimitiveError.OutOfMemory;
    }
    return types.FALSE;
}

extern var environ: [*:null]?[*:0]const u8;

fn getEnvVars(args: []const Value) PrimitiveError!Value {
    _ = args;
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;

    var result: Value = types.NIL;
    gc.pushRoot(&result) catch return PrimitiveError.OutOfMemory;
    defer gc.popRoot();

    var pair_val: Value = types.NIL;
    gc.pushRoot(&pair_val) catch return PrimitiveError.OutOfMemory;
    defer gc.popRoot();

    var key_val: Value = types.NIL;
    gc.pushRoot(&key_val) catch return PrimitiveError.OutOfMemory;
    defer gc.popRoot();

    var i: usize = 0;
    while (environ[i]) |entry| : (i += 1) {
        const s = std.mem.span(entry);
        if (std.mem.indexOfScalar(u8, s, '=')) |eq_pos| {
            key_val = gc.allocString(s[0..eq_pos]) catch return PrimitiveError.OutOfMemory;
            const val_str = gc.allocString(s[eq_pos + 1 ..]) catch return PrimitiveError.OutOfMemory;
            pair_val = gc.allocPair(key_val, val_str) catch return PrimitiveError.OutOfMemory;
            result = gc.allocPair(pair_val, result) catch return PrimitiveError.OutOfMemory;
        }
    }
    return result;
}

// ---------------------------------------------------------------------------
// (scheme eval) — R7RS 6.5
// ---------------------------------------------------------------------------

fn evalFn(args: []const Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError; // bare-ok: no VM
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const expr = args[0];

    // If an environment specifier is provided, compile in that environment
    if (args.len > 1 and types.isEnvironment(args[1])) {
        const se = types.toEnvironment(args[1]);
        const func = compiler_mod.compileExpressionInEnv(gc, expr, &vm.macros, se.env, args[1]) catch return PrimitiveError.TypeError; // bare-ok: compile error
        var closure_val = gc.allocClosure(func) catch return PrimitiveError.OutOfMemory;
        compiler_mod.Compiler.unrootFunction(gc, func);
        gc.pushRoot(&closure_val) catch return PrimitiveError.OutOfMemory;
        defer gc.popRoot();

        const result = vm.callWithArgs(closure_val, &[_]Value{}) catch |err| {
            return switch (err) {
                vm_mod.VMError.ContinuationInvoked => PrimitiveError.ContinuationInvoked,
                vm_mod.VMError.ExceptionRaised => PrimitiveError.ExceptionRaised,
                vm_mod.VMError.OutOfMemory => PrimitiveError.OutOfMemory,
                else => PrimitiveError.TypeError, // bare-ok: catch fallback
            };
        };
        return result;
    }

    const func = compiler_mod.compileExpressionWithMacros(gc, expr, &vm.macros, &vm.globals) catch return PrimitiveError.TypeError;
    var closure_val = gc.allocClosure(func) catch return PrimitiveError.OutOfMemory;
    compiler_mod.Compiler.unrootFunction(gc, func);
    gc.pushRoot(&closure_val) catch return PrimitiveError.OutOfMemory;
    defer gc.popRoot();

    const result = vm.callWithArgs(closure_val, &[_]Value{}) catch |err| {
        return switch (err) {
            vm_mod.VMError.ContinuationInvoked => PrimitiveError.ContinuationInvoked,
            vm_mod.VMError.ExceptionRaised => PrimitiveError.ExceptionRaised,
            vm_mod.VMError.OutOfMemory => PrimitiveError.OutOfMemory,
            else => PrimitiveError.TypeError, // bare-ok: catch fallback
        };
    };
    return result;
}

fn environmentFn(args: []const Value) PrimitiveError!Value {
    // (environment import-set ...) — R7RS 6.12
    // Create a new environment containing bindings from the given import sets.
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError; // bare-ok: no VM
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const library_mod = @import("library.zig");

    const env_map = gc.allocator.create(std.StringHashMap(Value)) catch return PrimitiveError.OutOfMemory;
    env_map.* = std.StringHashMap(Value).init(gc.allocator);

    for (args) |import_set| {
        const lib_name = library_mod.libraryNameToString(gc.allocator, import_set) catch return PrimitiveError.TypeError; // bare-ok: invalid import set
        defer gc.allocator.free(lib_name);

        const vm_library = @import("vm_library.zig");
        vm_library.ensureLibraryLoaded(vm, import_set, lib_name) catch return PrimitiveError.TypeError; // bare-ok: library load failure
        const lib = vm.libraries.get(lib_name) orelse return PrimitiveError.TypeError; // bare-ok: library not found
        var it = lib.exports.iterator();
        while (it.next()) |entry| {
            env_map.put(entry.key_ptr.*, entry.value_ptr.*) catch return PrimitiveError.OutOfMemory;
        }
    }

    return gc.allocEnvironment(env_map, true) catch return PrimitiveError.OutOfMemory;
}

// ---------------------------------------------------------------------------
// (scheme load) — R7RS 6.14
// ---------------------------------------------------------------------------

fn loadFn(args: []const Value) PrimitiveError!Value {
    if (!types.isString(args[0])) return primitives.typeError("load", "string", args[0]);
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError; // bare-ok: no VM
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const str = types.toObject(args[0]).as(types.SchemeString);
    const path = str.data[0..str.len];

    const path_z = gc.allocator.dupeZ(u8, path) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(path_z);

    // Open and read the file
    const fd = std.c.open(path_z, .{});
    if (fd < 0) {
        var msg = gc.allocString("cannot open file") catch return PrimitiveError.OutOfMemory;
        gc.pushRoot(&msg) catch return PrimitiveError.OutOfMemory;
        defer gc.popRoot();
        const irritant = args[0];
        const irritants = gc.allocPair(irritant, types.NIL) catch return PrimitiveError.OutOfMemory;
        var irritants_root = irritants;
        gc.pushRoot(&irritants_root) catch return PrimitiveError.OutOfMemory;
        defer gc.popRoot();
        const err_obj = gc.allocErrorObject(msg, irritants_root) catch return PrimitiveError.OutOfMemory;
        types.toObject(err_obj).as(types.ErrorObject).error_type = .file;
        vm.current_exception = err_obj;
        return PrimitiveError.ExceptionRaised;
    }
    defer _ = std.c.close(fd);

    var contents: std.ArrayList(u8) = .empty;
    defer contents.deinit(gc.allocator);

    var tmp: [4096]u8 = undefined;
    while (true) {
        const raw = std.c.read(fd, &tmp, tmp.len);
        if (raw <= 0) break;
        const n: usize = @intCast(raw);
        contents.appendSlice(gc.allocator, tmp[0..n]) catch return PrimitiveError.OutOfMemory;
    }

    // Parse and eval each expression
    var reader = reader_mod.Reader.init(gc, contents.items);
    defer reader.deinit();

    var last_result: Value = types.VOID;
    while (reader.hasMore() catch return PrimitiveError.TypeError) { // bare-ok: reader error in load
        const expr = reader.readDatum() catch return PrimitiveError.TypeError;

        const func = compiler_mod.compileExpressionWithMacros(gc, expr, &vm.macros, &vm.globals) catch return PrimitiveError.TypeError;
        {
            var func_val = types.makePointer(@ptrCast(func));
            gc.pushRoot(&func_val) catch return PrimitiveError.OutOfMemory;
            defer gc.popRoot();
            compiler_mod.Compiler.unrootFunction(gc, func);

            last_result = vm.execute(func) catch |err| {
                return switch (err) {
                    vm_mod.VMError.ContinuationInvoked => PrimitiveError.ContinuationInvoked,
                    vm_mod.VMError.ExceptionRaised => PrimitiveError.ExceptionRaised,
                    vm_mod.VMError.OutOfMemory => PrimitiveError.OutOfMemory,
                    else => PrimitiveError.TypeError, // bare-ok: catch fallback
                };
            };
        }
    }

    return last_result;
}

// ---------------------------------------------------------------------------
// Parameters (R7RS 4.2.6)
// ---------------------------------------------------------------------------

fn makeParameterFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const init = args[0];
    const converter: Value = if (args.len > 1) args[1] else types.NIL;
    // If converter provided, apply it to initial value
    var val = init;
    gc.pushRoot(&val) catch return PrimitiveError.OutOfMemory;
    defer gc.popRoot();
    if (converter != types.NIL) {
        const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError; // bare-ok: no VM
        val = vm.callWithArgs(converter, &[_]Value{init}) catch |err| {
            return switch (err) {
                vm_mod.VMError.ContinuationInvoked => PrimitiveError.ContinuationInvoked,
                vm_mod.VMError.ExceptionRaised => PrimitiveError.ExceptionRaised,
                vm_mod.VMError.OutOfMemory => PrimitiveError.OutOfMemory,
                else => PrimitiveError.TypeError, // bare-ok: catch fallback
            };
        };
    }
    return gc.allocParameter(val, converter) catch return PrimitiveError.OutOfMemory;
}

fn parameterSetDirectFn(args: []const Value) PrimitiveError!Value {
    if (!types.isParameter(args[0])) return primitives.typeError("%parameter-set!", "parameter", args[0]);
    const param = types.toObject(args[0]).as(types.ParameterObject);
    if (vm_mod.vm_instance) |vm| {
        vm.setParameterValue(param, args[1]) catch return PrimitiveError.OutOfMemory;
    } else {
        param.value = args[1];
        if (primitives.gc_instance) |gc| gc.writeBarrier(types.toObject(args[0]), args[1]);
    }
    return types.VOID;
}

// ---------------------------------------------------------------------------
// interaction-environment (R7RS 6.12)
// ---------------------------------------------------------------------------

fn interactionEnvironmentFn(args: []const Value) PrimitiveError!Value {
    _ = args;
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError; // bare-ok: no VM
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    return gc.allocEnvironment(&vm.globals, false) catch return PrimitiveError.OutOfMemory;
}

fn nullEnvironmentFn(args: []const Value) PrimitiveError!Value {
    if (!types.isFixnum(args[0])) return primitives.typeError("null-environment", "integer", args[0]);
    const version = types.toFixnum(args[0]);
    if (version != 5 and version != 7) return primitives.typeError("null-environment", "5 or 7", args[0]);
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;

    const env_map = gc.allocator.create(std.StringHashMap(Value)) catch return PrimitiveError.OutOfMemory;
    env_map.* = std.StringHashMap(Value).init(gc.allocator);
    return gc.allocEnvironment(env_map, true) catch return PrimitiveError.OutOfMemory;
}

fn schemeReportEnvironmentFn(args: []const Value) PrimitiveError!Value {
    if (!types.isFixnum(args[0])) return primitives.typeError("scheme-report-environment", "integer", args[0]);
    const version = types.toFixnum(args[0]);
    if (version != 5 and version != 7) return primitives.typeError("scheme-report-environment", "5 or 7", args[0]);
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError; // bare-ok: no VM
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;

    const env_map = gc.allocator.create(std.StringHashMap(Value)) catch return PrimitiveError.OutOfMemory;
    env_map.* = std.StringHashMap(Value).init(gc.allocator);

    // Import (scheme base) bindings
    if (vm.libraries.get("scheme.base")) |lib| {
        var it = lib.exports.iterator();
        while (it.next()) |entry| {
            env_map.put(entry.key_ptr.*, entry.value_ptr.*) catch return PrimitiveError.OutOfMemory;
        }
    }
    return gc.allocEnvironment(env_map, true) catch return PrimitiveError.OutOfMemory;
}
