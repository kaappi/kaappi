const std = @import("std");
const types = @import("types.zig");
const vm_mod = @import("vm.zig");
const primitives = @import("primitives.zig");
const printer = @import("printer.zig");
const primitives_io = @import("primitives_io.zig");
const Value = types.Value;
const NativeFn = types.NativeFn;
const PrimitiveError = primitives.PrimitiveError;

fn reg(vm: *vm_mod.VM, name: []const u8, func: types.NativeFnType, arity: NativeFn.Arity) !void {
    return primitives.reg(vm, name, func, arity);
}

pub fn registerControl(vm: *vm_mod.VM) !void {
    // Exception system (R7RS 6.11)
    try reg(vm, "raise", &raiseFn, .{ .exact = 1 });
    try reg(vm, "raise-continuable", &raiseContinuableFn, .{ .exact = 1 });
    try reg(vm, "with-exception-handler", &withExceptionHandlerFn, .{ .exact = 2 });
    try reg(vm, "error", &errorFn, .{ .variadic = 1 });
    try reg(vm, "error-object?", &errorObjectP, .{ .exact = 1 });
    try reg(vm, "error-object-message", &errorObjectMessage, .{ .exact = 1 });
    try reg(vm, "error-object-irritants", &errorObjectIrritants, .{ .exact = 1 });
    try reg(vm, "file-error?", &fileErrorP, .{ .exact = 1 });
    try reg(vm, "read-error?", &readErrorP, .{ .exact = 1 });

    // Continuations (R7RS 6.10)
    try reg(vm, "call-with-current-continuation", &callWithCurrentContinuation, .{ .exact = 1 });
    try reg(vm, "call/cc", &callWithCurrentContinuation, .{ .exact = 1 });
    try reg(vm, "call-with-escape-continuation", &callWithEscapeContinuation, .{ .exact = 1 });
    try reg(vm, "call/ec", &callWithEscapeContinuation, .{ .exact = 1 });
    try reg(vm, "dynamic-wind", &dynamicWindFn, .{ .exact = 3 });
    try reg(vm, "values", &valuesFn, .{ .variadic = 0 });
    try reg(vm, "call-with-values", &callWithValuesFn, .{ .exact = 2 });
}

// ---------------------------------------------------------------------------
// Exception system (R7RS 6.11)
// ---------------------------------------------------------------------------

pub fn raiseFn(args: []const Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse {
        const gc = primitives.gc_instance orelse return PrimitiveError.TypeError;
        primitives_io.writeStderr("Error: unhandled exception: ");
        const s = printer.valueToString(gc.allocator, args[0], .write) catch return PrimitiveError.TypeError;
        defer gc.allocator.free(s);
        primitives_io.writeStderr(s);
        primitives_io.writeStderr("\n");
        return PrimitiveError.TypeError;
    };
    vm.current_exception = args[0];
    return PrimitiveError.ExceptionRaised;
}

fn raiseContinuableFn(args: []const Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse {
        const gc = primitives.gc_instance orelse return PrimitiveError.TypeError;
        primitives_io.writeStderr("Error: unhandled exception: ");
        const s = printer.valueToString(gc.allocator, args[0], .write) catch return PrimitiveError.TypeError;
        defer gc.allocator.free(s);
        primitives_io.writeStderr(s);
        primitives_io.writeStderr("\n");
        return PrimitiveError.TypeError;
    };
    if (vm.handler_count == 0) {
        vm.current_exception = args[0];
        return PrimitiveError.ExceptionRaised;
    }
    const handler = vm.handler_stack[vm.handler_count - 1].handler;
    vm.popHandler();
    const result = vm.callHandler(handler, args[0], 0) catch |err| {
        vm.pushHandler(handler) catch {};
        return switch (err) {
            vm_mod.VMError.ContinuationInvoked => PrimitiveError.ContinuationInvoked,
            vm_mod.VMError.ExceptionRaised => PrimitiveError.ExceptionRaised,
            vm_mod.VMError.OutOfMemory => PrimitiveError.OutOfMemory,
            else => PrimitiveError.TypeError,
        };
    };
    vm.pushHandler(handler) catch {};
    return result;
}

fn withExceptionHandlerFn(args: []const Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError;
    const handler = args[0];
    const thunk = args[1];

    if (!types.isProcedure(handler)) return PrimitiveError.TypeError;
    if (!types.isProcedure(thunk)) return PrimitiveError.TypeError;

    // Push the handler onto the handler stack
    vm.pushHandler(handler) catch return PrimitiveError.OutOfMemory;

    // Call the thunk
    const result = vm.callThunk(thunk) catch |err| {
        if (err == vm_mod.VMError.ContinuationInvoked) {
            return PrimitiveError.ContinuationInvoked;
        }
        if (err == vm_mod.VMError.ExceptionRaised) {
            vm.popHandler();
            var handler_root = handler;
            const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
            gc.pushRoot(&handler_root);
            const exc = vm.current_exception orelse types.FALSE;
            vm.current_exception = null;
            const handler_result = vm.callHandler(handler_root, exc, 0) catch |herr| {
                gc.popRoot();
                return switch (herr) {
                    vm_mod.VMError.ContinuationInvoked => PrimitiveError.ContinuationInvoked,
                    vm_mod.VMError.ExceptionRaised => PrimitiveError.ExceptionRaised,
                    vm_mod.VMError.OutOfMemory => PrimitiveError.OutOfMemory,
                    else => PrimitiveError.TypeError,
                };
            };
            gc.popRoot();
            return handler_result;
        }
        vm.popHandler();
        // Convert VM-level errors into Scheme exceptions so guard can catch them
        const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
        const detail = vm.getErrorDetail();
        const msg_str = if (detail.len > 0)
            gc.allocString(detail) catch return PrimitiveError.OutOfMemory
        else
            gc.allocString("error") catch return PrimitiveError.OutOfMemory;
        const err_obj = gc.allocErrorObject(msg_str, types.NIL) catch return PrimitiveError.OutOfMemory;
        var handler_root = handler;
        gc.pushRoot(&handler_root);
        var err_root = err_obj;
        gc.pushRoot(&err_root);
        const handler_result = vm.callHandler(handler_root, err_root, 0) catch |herr| {
            gc.popRoot();
            gc.popRoot();
            return switch (herr) {
                vm_mod.VMError.ContinuationInvoked => PrimitiveError.ContinuationInvoked,
                vm_mod.VMError.ExceptionRaised => PrimitiveError.ExceptionRaised,
                vm_mod.VMError.OutOfMemory => PrimitiveError.OutOfMemory,
                else => PrimitiveError.TypeError,
            };
        };
        gc.popRoot();
        gc.popRoot();
        return handler_result;
    };

    // Normal return -- pop the handler
    vm.popHandler();
    return result;
}

fn errorObjectP(args: []const Value) PrimitiveError!Value {
    return if (types.isErrorObject(args[0])) types.TRUE else types.FALSE;
}

fn errorObjectMessage(args: []const Value) PrimitiveError!Value {
    if (!types.isErrorObject(args[0])) return PrimitiveError.TypeError;
    const err = types.toObject(args[0]).as(types.ErrorObject);
    return err.message;
}

fn errorObjectIrritants(args: []const Value) PrimitiveError!Value {
    if (!types.isErrorObject(args[0])) return PrimitiveError.TypeError;
    const err = types.toObject(args[0]).as(types.ErrorObject);
    return err.irritants;
}

fn fileErrorP(args: []const Value) PrimitiveError!Value {
    if (!types.isErrorObject(args[0])) return types.FALSE;
    const err = types.toObject(args[0]).as(types.ErrorObject);
    return if (err.error_type == .file) types.TRUE else types.FALSE;
}

fn readErrorP(args: []const Value) PrimitiveError!Value {
    if (!types.isErrorObject(args[0])) return types.FALSE;
    const err = types.toObject(args[0]).as(types.ErrorObject);
    return if (err.error_type == .read) types.TRUE else types.FALSE;
}

fn errorFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;

    // First arg is the message
    const message = args[0];

    // Build irritants list from remaining args
    var irritants: Value = types.NIL;
    if (args.len > 1) {
        var i = args.len;
        while (i > 1) {
            i -= 1;
            irritants = gc.allocPair(args[i], irritants) catch return PrimitiveError.OutOfMemory;
        }
    }

    // Create the error object
    const err_obj = gc.allocErrorObject(message, irritants) catch return PrimitiveError.OutOfMemory;

    // Raise it through the exception system
    const raise_args = [1]Value{err_obj};
    return raiseFn(&raise_args);
}

// ---------------------------------------------------------------------------
// Continuations (R7RS 6.10)
// ---------------------------------------------------------------------------

fn callWithCurrentContinuation(args: []const Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError;
    const proc = args[0];
    if (!types.isProcedure(proc)) return PrimitiveError.TypeError;

    const caller = &vm.frames[vm.frame_count - 1];
    const call_ip = caller.ip;
    // The call opcode is: [opcode:1][base_reg:1][nargs:1]
    // So caller.ip points past nargs, and base_reg is at caller.ip - 2
    const base_reg = caller.code[call_ip - 2];
    const abs_base = caller.base + base_reg;

    // Capture continuation. When invoked, it will place the value at abs_base.
    const cont = vm.captureContinuation(@intCast(base_reg), caller.base) catch return PrimitiveError.OutOfMemory;

    // Root the continuation so it survives GC during the proc call
    var cont_val = cont;
    vm.gc.pushRoot(&cont_val);

    // Call proc(continuation)
    const result = vm.callHandler(proc, cont_val, base_reg) catch |err| {
        vm.gc.popRoot();
        return switch (err) {
            vm_mod.VMError.ContinuationInvoked => PrimitiveError.ContinuationInvoked,
            vm_mod.VMError.ExceptionRaised => PrimitiveError.ExceptionRaised,
            vm_mod.VMError.OutOfMemory => PrimitiveError.OutOfMemory,
            vm_mod.VMError.ArityMismatch => PrimitiveError.TypeError,
            else => PrimitiveError.TypeError,
        };
    };

    vm.gc.popRoot();

    // If proc returned normally (without invoking the continuation),
    // store the result where call/cc's result goes.
    _ = abs_base;
    return result;
}

/// call-with-escape-continuation / call/ec — like call/cc but the continuation
/// is escape-only (valid only within the dynamic extent of this call). Capture
/// is O(1): no register/frame snapshot is taken. Invoking the continuation
/// outside its extent raises an error.
fn callWithEscapeContinuation(args: []const Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError;
    const proc = args[0];
    if (!types.isProcedure(proc)) return PrimitiveError.TypeError;

    const caller = &vm.frames[vm.frame_count - 1];
    const call_ip = caller.ip;
    // The call opcode is [opcode:1][base_reg:1][nargs:1]; caller.ip points past
    // nargs, so base_reg is at caller.ip - 2.
    const base_reg = caller.code[call_ip - 2];

    const cont = vm.captureEscape(@intCast(base_reg), caller.base) catch return PrimitiveError.OutOfMemory;

    // Root the continuation so it survives GC during the proc call.
    var cont_val = cont;
    vm.gc.pushRoot(&cont_val);
    const cont_obj = types.toObject(cont_val).as(types.Continuation);

    const result = vm.callHandler(proc, cont_val, base_reg) catch |err| {
        // The extent has ended (escape unwound through here, or proc errored).
        cont_obj.valid = false;
        vm.gc.popRoot();
        return switch (err) {
            vm_mod.VMError.ContinuationInvoked => PrimitiveError.ContinuationInvoked,
            vm_mod.VMError.ExceptionRaised => PrimitiveError.ExceptionRaised,
            vm_mod.VMError.OutOfMemory => PrimitiveError.OutOfMemory,
            vm_mod.VMError.ArityMismatch => PrimitiveError.TypeError,
            else => PrimitiveError.TypeError,
        };
    };

    // proc returned normally without escaping; the extent is over.
    cont_obj.valid = false;
    vm.gc.popRoot();
    return result;
}

fn dynamicWindFn(args: []const Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError;
    const before = args[0];
    const thunk = args[1];
    const after = args[2];

    if (!types.isProcedure(before)) return PrimitiveError.TypeError;
    if (!types.isProcedure(thunk)) return PrimitiveError.TypeError;
    if (!types.isProcedure(after)) return PrimitiveError.TypeError;

    // Call before thunk
    _ = vm.callThunk(before) catch |err| {
        return switch (err) {
            vm_mod.VMError.ContinuationInvoked => PrimitiveError.ContinuationInvoked,
            vm_mod.VMError.ExceptionRaised => PrimitiveError.ExceptionRaised,
            vm_mod.VMError.OutOfMemory => PrimitiveError.OutOfMemory,
            else => PrimitiveError.TypeError,
        };
    };

    // Push wind record
    if (vm.wind_count >= 64) return PrimitiveError.OutOfMemory;
    vm.wind_stack[vm.wind_count] = .{ .before = before, .after = after };
    vm.wind_count += 1;

    // Call thunk
    const result = vm.callThunk(thunk) catch |err| {
        // If continuation was invoked, the wind stack has been replaced
        // so we shouldn't try to pop/call after
        if (err == vm_mod.VMError.ContinuationInvoked) return PrimitiveError.ContinuationInvoked;

        // On other errors, pop wind record and call after
        vm.wind_count -= 1;
        _ = vm.callThunk(after) catch {};
        return switch (err) {
            vm_mod.VMError.ExceptionRaised => PrimitiveError.ExceptionRaised,
            vm_mod.VMError.OutOfMemory => PrimitiveError.OutOfMemory,
            else => PrimitiveError.TypeError,
        };
    };

    // Pop wind record
    vm.wind_count -= 1;

    // Call after thunk
    _ = vm.callThunk(after) catch |err| {
        return switch (err) {
            vm_mod.VMError.ContinuationInvoked => PrimitiveError.ContinuationInvoked,
            vm_mod.VMError.ExceptionRaised => PrimitiveError.ExceptionRaised,
            vm_mod.VMError.OutOfMemory => PrimitiveError.OutOfMemory,
            else => PrimitiveError.TypeError,
        };
    };

    return result;
}

fn valuesFn(args: []const Value) PrimitiveError!Value {
    if (args.len == 1) return args[0];
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    return gc.allocMultipleValues(args) catch return PrimitiveError.OutOfMemory;
}

fn callWithValuesFn(args: []const Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError;
    const producer = args[0];
    const consumer = args[1];

    if (!types.isProcedure(producer)) return PrimitiveError.TypeError;
    if (!types.isProcedure(consumer)) return PrimitiveError.TypeError;

    // Call producer
    const produced = vm.callThunk(producer) catch |err| {
        return switch (err) {
            vm_mod.VMError.ContinuationInvoked => PrimitiveError.ContinuationInvoked,
            vm_mod.VMError.ExceptionRaised => PrimitiveError.ExceptionRaised,
            vm_mod.VMError.OutOfMemory => PrimitiveError.OutOfMemory,
            else => PrimitiveError.TypeError,
        };
    };

    // Call consumer with the produced values
    if (types.isMultipleValues(produced)) {
        const mv = types.toObject(produced).as(types.MultipleValues);
        const result = vm.callWithArgs(consumer, mv.values) catch |err| {
            return switch (err) {
                vm_mod.VMError.ContinuationInvoked => PrimitiveError.ContinuationInvoked,
                vm_mod.VMError.ExceptionRaised => PrimitiveError.ExceptionRaised,
                vm_mod.VMError.OutOfMemory => PrimitiveError.OutOfMemory,
                else => PrimitiveError.TypeError,
            };
        };
        return result;
    } else {
        // Single value -- call consumer with one argument
        const result = vm.callHandler(consumer, produced, 0) catch |err| {
            return switch (err) {
                vm_mod.VMError.ContinuationInvoked => PrimitiveError.ContinuationInvoked,
                vm_mod.VMError.ExceptionRaised => PrimitiveError.ExceptionRaised,
                vm_mod.VMError.OutOfMemory => PrimitiveError.OutOfMemory,
                else => PrimitiveError.TypeError,
            };
        };
        return result;
    }
}
