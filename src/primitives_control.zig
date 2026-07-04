const std = @import("std");
const types = @import("types.zig");
const vm_mod = @import("vm.zig");
const primitives = @import("primitives.zig");
const memory = @import("memory.zig");
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
        const gc = memory.gc_instance orelse return PrimitiveError.TypeError; // bare-ok: no GC
        primitives_io.writeStderr("Error: unhandled exception: ");
        const s = printer.valueToString(gc.allocator, args[0], .write) catch return PrimitiveError.TypeError; // bare-ok: print failed
        defer gc.allocator.free(s);
        primitives_io.writeStderr(s);
        primitives_io.writeStderr("\n");
        return PrimitiveError.TypeError; // bare-ok: no VM for raise
    };
    vm.current_exception = args[0];
    return PrimitiveError.ExceptionRaised;
}

fn raiseContinuableFn(args: []const Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse {
        const gc = memory.gc_instance orelse return PrimitiveError.TypeError; // bare-ok: no GC
        primitives_io.writeStderr("Error: unhandled exception: ");
        const s = printer.valueToString(gc.allocator, args[0], .write) catch return PrimitiveError.TypeError; // bare-ok: print failed
        defer gc.allocator.free(s);
        primitives_io.writeStderr(s);
        primitives_io.writeStderr("\n");
        return PrimitiveError.TypeError; // bare-ok: no VM for raise
    };
    if (vm.handler_count == 0) {
        vm.current_exception = args[0];
        return PrimitiveError.ExceptionRaised;
    }
    const handler = vm.handler_stack[vm.handler_count - 1].handler;
    vm.popHandler();
    const result = vm.callHandler(handler, args[0], 0) catch |err| {
        vm.pushHandler(handler) catch {};
        return primitives.mapVMError(err);
    };
    vm.pushHandler(handler) catch return PrimitiveError.OutOfMemory;
    return result;
}

fn withExceptionHandlerFn(args: []const Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError; // bare-ok: no VM
    const handler = args[0];
    const thunk = args[1];

    if (!types.isProcedure(handler)) return primitives.typeError("with-exception-handler", "procedure", args[0]);
    if (!types.isProcedure(thunk)) return primitives.typeError("with-exception-handler", "procedure", args[1]);

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
            const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
            gc.pushRoot(&handler_root) catch return PrimitiveError.OutOfMemory;
            defer gc.popRoot();
            var exc = vm.current_exception orelse types.FALSE;
            vm.current_exception = null;
            gc.pushRoot(&exc) catch return PrimitiveError.OutOfMemory;
            defer gc.popRoot();
            _ = vm.callHandler(handler_root, exc, 0) catch |herr| {
                return primitives.mapVMError(herr);
            };
            // Handler returned from non-continuable raise — re-raise per R7RS
            var reraise_msg = gc.allocString("handler returned") catch return PrimitiveError.OutOfMemory;
            gc.pushRoot(&reraise_msg) catch return PrimitiveError.OutOfMemory;
            defer gc.popRoot();
            const reraise_err = gc.allocErrorObject(reraise_msg, types.NIL) catch return PrimitiveError.OutOfMemory;
            vm.current_exception = reraise_err;
            return PrimitiveError.ExceptionRaised;
        }
        vm.popHandler();
        // Convert VM-level errors into Scheme exceptions so guard can catch them
        const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
        const detail = vm.getErrorDetail();
        var msg_str = if (detail.len > 0)
            gc.allocString(detail) catch return PrimitiveError.OutOfMemory
        else
            gc.allocString("error") catch return PrimitiveError.OutOfMemory;
        gc.pushRoot(&msg_str) catch return PrimitiveError.OutOfMemory;
        defer gc.popRoot();
        const err_obj = gc.allocErrorObject(msg_str, types.NIL) catch return PrimitiveError.OutOfMemory;
        var handler_root = handler;
        gc.pushRoot(&handler_root) catch return PrimitiveError.OutOfMemory;
        defer gc.popRoot();
        var err_root = err_obj;
        gc.pushRoot(&err_root) catch return PrimitiveError.OutOfMemory;
        defer gc.popRoot();
        const handler_result = vm.callHandler(handler_root, err_root, 0) catch |herr| {
            return primitives.mapVMError(herr);
        };
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
    if (!types.isErrorObject(args[0])) return primitives.typeError("error-object-message", "error object", args[0]);
    const err = types.toObject(args[0]).as(types.ErrorObject);
    return err.message;
}

fn errorObjectIrritants(args: []const Value) PrimitiveError!Value {
    if (!types.isErrorObject(args[0])) return primitives.typeError("error-object-irritants", "error object", args[0]);
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
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;

    // First arg is the message
    const message = args[0];

    // Build irritants list from remaining args
    var irritants: Value = types.NIL;
    gc.pushRoot(&irritants) catch return PrimitiveError.OutOfMemory;
    defer gc.popRoot();
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
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError; // bare-ok: no VM
    const proc = args[0];
    if (!types.isProcedure(proc)) return primitives.typeError("call/cc", "procedure", args[0]);

    const caller = &vm.frames[vm.frame_count - 1];
    const call_ip = caller.ip;
    if (call_ip < 2) return PrimitiveError.TypeError; // bare-ok: internal state
    // The call opcode is: [opcode:1][base_reg:1][nargs:1]
    // So caller.ip points past nargs, and base_reg is at caller.ip - 2
    const base_reg = caller.code[call_ip - 2];
    const abs_base = caller.base + base_reg;

    // Capture continuation. When invoked, it will place the value at abs_base.
    const cont = vm.captureContinuation(@intCast(base_reg), caller.base) catch return PrimitiveError.OutOfMemory;

    // Root the continuation so it survives GC during the proc call
    var cont_val = cont;
    vm.gc.pushRoot(&cont_val) catch return PrimitiveError.OutOfMemory;
    defer vm.gc.popRoot();

    // Call proc(continuation)
    const result = vm.callHandler(proc, cont_val, base_reg) catch |err| {
        return primitives.mapVMError(err);
    };

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
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError; // bare-ok: no VM
    const proc = args[0];
    if (!types.isProcedure(proc)) return primitives.typeError("call/ec", "procedure", args[0]);

    const caller = &vm.frames[vm.frame_count - 1];
    const call_ip = caller.ip;
    if (call_ip < 2) return PrimitiveError.TypeError; // bare-ok: internal state
    // The call opcode is [opcode:1][base_reg:1][nargs:1]; caller.ip points past
    // nargs, so base_reg is at caller.ip - 2.
    const base_reg = caller.code[call_ip - 2];

    const cont = vm.captureEscape(@intCast(base_reg), caller.base) catch return PrimitiveError.OutOfMemory;

    // Root the continuation so it survives GC during the proc call.
    var cont_val = cont;
    vm.gc.pushRoot(&cont_val) catch return PrimitiveError.OutOfMemory;
    defer vm.gc.popRoot();
    const cont_obj = types.toObject(cont_val).as(types.Continuation);

    const result = vm.callHandler(proc, cont_val, base_reg) catch |err| {
        // The extent has ended (escape unwound through here, or proc errored).
        cont_obj.valid = false;
        return primitives.mapVMError(err);
    };

    // proc returned normally without escaping; the extent is over.
    cont_obj.valid = false;
    return result;
}

fn dynamicWindFn(args: []const Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError; // bare-ok: no VM
    const before = args[0];
    const thunk = args[1];
    const after = args[2];

    if (!types.isProcedure(before)) return primitives.typeError("dynamic-wind", "procedure", args[0]);
    if (!types.isProcedure(thunk)) return primitives.typeError("dynamic-wind", "procedure", args[1]);
    if (!types.isProcedure(after)) return primitives.typeError("dynamic-wind", "procedure", args[2]);

    // Call before thunk
    _ = vm.callThunk(before) catch |err| {
        return primitives.mapVMError(err);
    };

    // Push wind record
    if (vm.wind_count >= vm_mod.MAX_WINDS) return PrimitiveError.OutOfMemory;
    vm.wind_stack[vm.wind_count] = .{ .before = before, .after = after };
    vm.wind_count += 1;

    // Call thunk
    const result = vm.callThunk(thunk) catch |err| {
        // If continuation was invoked, the wind stack has been replaced
        // so we shouldn't try to pop/call after
        if (err == vm_mod.VMError.ContinuationInvoked) return PrimitiveError.ContinuationInvoked;

        // On other errors, pop wind record and call after
        vm.wind_count -= 1;
        _ = vm.callThunk(after) catch |after_err| {
            if (after_err == vm_mod.VMError.ContinuationInvoked)
                return PrimitiveError.ContinuationInvoked;
        };
        return primitives.mapVMError(err);
    };

    // Pop wind record
    vm.wind_count -= 1;

    // Call after thunk
    _ = vm.callThunk(after) catch |err| {
        return primitives.mapVMError(err);
    };

    return result;
}

fn valuesFn(args: []const Value) PrimitiveError!Value {
    if (args.len == 1) return args[0];
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    return gc.allocMultipleValues(args) catch return PrimitiveError.OutOfMemory;
}

fn callWithValuesFn(args: []const Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError; // bare-ok: no VM
    const producer = args[0];
    const consumer = args[1];

    if (!types.isProcedure(producer)) return primitives.typeError("call-with-values", "procedure", args[0]);
    if (!types.isProcedure(consumer)) return primitives.typeError("call-with-values", "procedure", args[1]);

    // Call producer
    const produced = vm.callThunk(producer) catch |err| {
        return primitives.mapVMError(err);
    };

    // Call consumer with the produced values
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    var produced_root = produced;
    gc.pushRoot(&produced_root) catch return PrimitiveError.OutOfMemory;
    defer gc.popRoot();
    if (types.isMultipleValues(produced_root)) {
        const mv = types.toObject(produced_root).as(types.MultipleValues);
        const result = vm.callWithArgs(consumer, mv.values) catch |err| {
            return primitives.mapVMError(err);
        };
        return result;
    } else {
        // Single value -- call consumer with one argument (use callWithArgs
        // so arity is validated, matching the multi-value path)
        const result = vm.callWithArgs(consumer, &[_]Value{produced}) catch |err| {
            return primitives.mapVMError(err);
        };
        return result;
    }
}
