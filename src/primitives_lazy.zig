const std = @import("std");
const types = @import("types.zig");
const vm_mod = @import("vm.zig");
const primitives = @import("primitives.zig");
const Value = types.Value;
const NativeFn = types.NativeFn;
const PrimitiveError = primitives.PrimitiveError;

fn reg(vm: *vm_mod.VM, name: []const u8, func: types.NativeFnType, arity: NativeFn.Arity) !void {
    return primitives.reg(vm, name, func, arity);
}

pub fn registerLazy(vm: *vm_mod.VM) !void {
    try reg(vm, "promise?", &promiseP, .{ .exact = 1 });
    try reg(vm, "make-promise", &makePromiseFn, .{ .exact = 1 });
    try reg(vm, "force", &forceFn, .{ .exact = 1 });
    try reg(vm, "%make-promise-lazy", &makePromiseLazy, .{ .exact = 1 });
}

fn promiseP(args: []const Value) PrimitiveError!Value {
    return if (types.isPromise(args[0])) types.TRUE else types.FALSE;
}

fn makePromiseFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    // If already a promise, return it
    if (types.isPromise(args[0])) return args[0];
    // Otherwise wrap as already-forced promise
    return gc.allocPromise(true, args[0]) catch return PrimitiveError.OutOfMemory;
}

fn makePromiseLazy(args: []const Value) PrimitiveError!Value {
    // Internal: create an unforced promise with the given thunk
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    return gc.allocPromise(false, args[0]) catch return PrimitiveError.OutOfMemory;
}

fn forceFn(args: []const Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError;
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;

    var current = args[0];

    // If not a promise, return as-is (R7RS: force on non-promise returns the value)
    if (!types.isPromise(current)) return current;

    // Iterative forcing (handles delay-force chains)
    var iterations: usize = 0;
    while (iterations < 10000) : (iterations += 1) {
        if (!types.isPromise(current)) return current;
        const promise = types.toPromise(current);

        if (promise.forced) return promise.value;

        // Force: call the thunk
        const thunk = promise.value;
        if (!types.isProcedure(thunk)) {
            // Not a thunk, treat as already forced
            promise.forced = true;
            return thunk;
        }

        const result = vm.callWithArgs(thunk, &[_]Value{}) catch |err| {
            return switch (err) {
                vm_mod.VMError.ContinuationInvoked => PrimitiveError.ContinuationInvoked,
                vm_mod.VMError.ExceptionRaised => PrimitiveError.ExceptionRaised,
                vm_mod.VMError.OutOfMemory => PrimitiveError.OutOfMemory,
                else => PrimitiveError.TypeError,
            };
        };

        // If the result is a promise (from delay-force), iterate
        if (types.isPromise(result)) {
            const inner = types.toPromise(result);
            // Transfer the inner promise's state to this promise
            promise.forced = inner.forced;
            promise.value = inner.value;
            // Also update inner to point here (for sharing)
            inner.forced = promise.forced;
            inner.value = promise.value;
            current = types.makePointer(@ptrCast(promise));
            continue;
        }

        // Cache the result
        promise.forced = true;
        promise.value = result;
        // Root the result to protect from GC
        _ = gc;
        return result;
    }

    return PrimitiveError.TypeError; // infinite loop
}
