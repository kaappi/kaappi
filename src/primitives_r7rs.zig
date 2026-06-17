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
    try reg(vm, "emergency-exit", &exitFn, .{ .variadic = 0 });
    try reg(vm, "get-environment-variable", &getEnvVar, .{ .exact = 1 });
    try reg(vm, "get-environment-variables", &getEnvVars, .{ .exact = 0 });

    // Parameters (R7RS 4.2.6)
    try reg(vm, "make-parameter", &makeParameterFn, .{ .variadic = 1 });
    try reg(vm, "%parameter-set!", &parameterSetDirectFn, .{ .exact = 2 });

    // (scheme eval)
    try reg(vm, "eval", &evalFn, .{ .variadic = 1 });
    try reg(vm, "environment", &environmentFn, .{ .variadic = 0 });
    try reg(vm, "interaction-environment", &interactionEnvironmentFn, .{ .exact = 0 });

    // (scheme load)
    try reg(vm, "load", &loadFn, .{ .exact = 1 });
}

// ---------------------------------------------------------------------------
// (scheme time) — R7RS 6.14
// ---------------------------------------------------------------------------

fn currentSecond(args: []const Value) PrimitiveError!Value {
    _ = args;
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    var ts: std.c.timespec = undefined;
    _ = std.c.clock_gettime(.REALTIME, &ts);
    const secs: f64 = @as(f64, @floatFromInt(ts.sec)) +
        @as(f64, @floatFromInt(ts.nsec)) / 1e9;
    return gc.allocFlonum(secs) catch return PrimitiveError.OutOfMemory;
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
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError;

    var result: Value = types.NIL;
    gc.pushRoot(&result);
    defer gc.popRoot();

    // Build list in reverse: script args then program name at the front.
    var i = vm.command_line_args.len;
    while (i > 0) {
        i -= 1;
        const s = gc.allocString(vm.command_line_args[i]) catch return PrimitiveError.OutOfMemory;
        result = gc.allocPair(s, result) catch return PrimitiveError.OutOfMemory;
    }

    // Prepend program name.
    const name = gc.allocString("kaappi") catch return PrimitiveError.OutOfMemory;
    result = gc.allocPair(name, result) catch return PrimitiveError.OutOfMemory;
    return result;
}

fn exitFn(args: []const Value) PrimitiveError!Value {
    const code: u8 = if (args.len > 0 and types.isFixnum(args[0]))
        @intCast(@as(u64, @bitCast(@as(i64, @intCast(types.toFixnum(args[0]) & 0xFF)))))
    else if (args.len > 0 and args[0] == types.FALSE)
        1
    else
        0;
    std.process.exit(code);
}

fn getEnvVar(args: []const Value) PrimitiveError!Value {
    if (!types.isString(args[0])) return PrimitiveError.TypeError;
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

fn getEnvVars(args: []const Value) PrimitiveError!Value {
    _ = args;
    // Return empty list for simplicity — full implementation would iterate environ
    return types.NIL;
}

// ---------------------------------------------------------------------------
// (scheme eval) — R7RS 6.5
// ---------------------------------------------------------------------------

fn evalFn(args: []const Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError;
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    // args[0] = expression, args[1] = environment (optional, ignored)
    const expr = args[0];

    // Compile the expression
    const func = compiler_mod.compileExpressionWithMacros(gc, expr, &vm.macros, &vm.globals) catch return PrimitiveError.TypeError;

    // Create a closure from the compiled function
    var closure_val = gc.allocClosure(func) catch return PrimitiveError.OutOfMemory;
    gc.pushRoot(&closure_val);
    defer gc.popRoot();

    // Use callWithArgs to properly nest within the current execution
    const result = vm.callWithArgs(closure_val, &[_]Value{}) catch |err| {
        return switch (err) {
            vm_mod.VMError.ContinuationInvoked => PrimitiveError.ContinuationInvoked,
            vm_mod.VMError.ExceptionRaised => PrimitiveError.ExceptionRaised,
            vm_mod.VMError.OutOfMemory => PrimitiveError.OutOfMemory,
            else => PrimitiveError.TypeError,
        };
    };
    return result;
}

fn environmentFn(args: []const Value) PrimitiveError!Value {
    // (environment import-set ...) — return a value representing an environment
    // Simplified: return a dummy value, eval ignores the environment arg
    _ = args;
    return types.VOID;
}

// ---------------------------------------------------------------------------
// (scheme load) — R7RS 6.14
// ---------------------------------------------------------------------------

fn loadFn(args: []const Value) PrimitiveError!Value {
    if (!types.isString(args[0])) return PrimitiveError.TypeError;
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError;
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const str = types.toObject(args[0]).as(types.SchemeString);
    const path = str.data[0..str.len];

    const path_z = gc.allocator.dupeZ(u8, path) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(path_z);

    // Open and read the file
    const fd = std.posix.openat(std.posix.AT.FDCWD, path_z, .{}, 0) catch {
        return PrimitiveError.TypeError;
    };
    defer _ = std.posix.system.close(fd);

    var contents: std.ArrayList(u8) = .empty;
    defer contents.deinit(gc.allocator);

    var tmp: [4096]u8 = undefined;
    while (true) {
        const n = std.posix.read(fd, &tmp) catch break;
        if (n == 0) break;
        contents.appendSlice(gc.allocator, tmp[0..n]) catch return PrimitiveError.OutOfMemory;
    }

    // Parse and eval each expression
    var reader = reader_mod.Reader.init(gc, contents.items);
    defer reader.deinit();

    var last_result: Value = types.VOID;
    while (reader.hasMore()) {
        const expr = reader.readDatum() catch return PrimitiveError.TypeError;

        const func = compiler_mod.compileExpressionWithMacros(gc, expr, &vm.macros, &vm.globals) catch return PrimitiveError.TypeError;
        var func_val = types.makePointer(@ptrCast(func));
        gc.pushRoot(&func_val);

        last_result = vm.execute(func) catch |err| {
            gc.popRoot();
            return switch (err) {
                vm_mod.VMError.ContinuationInvoked => PrimitiveError.ContinuationInvoked,
                vm_mod.VMError.ExceptionRaised => PrimitiveError.ExceptionRaised,
                vm_mod.VMError.OutOfMemory => PrimitiveError.OutOfMemory,
                else => PrimitiveError.TypeError,
            };
        };
        gc.popRoot();
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
    if (converter != types.NIL) {
        const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError;
        val = vm.callWithArgs(converter, &[_]Value{init}) catch |err| {
            return switch (err) {
                vm_mod.VMError.ContinuationInvoked => PrimitiveError.ContinuationInvoked,
                vm_mod.VMError.ExceptionRaised => PrimitiveError.ExceptionRaised,
                vm_mod.VMError.OutOfMemory => PrimitiveError.OutOfMemory,
                else => PrimitiveError.TypeError,
            };
        };
    }
    return gc.allocParameter(val, converter) catch return PrimitiveError.OutOfMemory;
}

fn parameterSetDirectFn(args: []const Value) PrimitiveError!Value {
    if (!types.isParameter(args[0])) return PrimitiveError.TypeError;
    const param = types.toObject(args[0]).as(types.ParameterObject);
    param.value = args[1];
    return types.VOID;
}

// ---------------------------------------------------------------------------
// interaction-environment (R7RS 6.12)
// ---------------------------------------------------------------------------

fn interactionEnvironmentFn(args: []const Value) PrimitiveError!Value {
    _ = args;
    return types.TRUE; // We always eval in the global environment
}
