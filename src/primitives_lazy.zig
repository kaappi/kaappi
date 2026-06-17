const std = @import("std");
const types = @import("types.zig");
const primitives = @import("primitives.zig");
const vm_mod = @import("vm.zig");
const Value = types.Value;
const PrimitiveError = primitives.PrimitiveError;
const NativeFn = types.NativeFn;

fn reg(vm: *vm_mod.VM, name: []const u8, func: types.NativeFnType, arity: NativeFn.Arity) !void {
    return primitives.reg(vm, name, func, arity);
}

pub fn registerLazy(vm: *vm_mod.VM) !void {
    try reg(vm, "force", &forceFn, .{ .exact = 1 });
    try reg(vm, "promise?", &promiseP, .{ .exact = 1 });
    try reg(vm, "make-promise", &makePromiseFn, .{ .exact = 1 });
    try reg(vm, "%make-promise-lazy", &makePromiseLazy, .{ .exact = 1 });
}

fn promiseP(args: []const Value) PrimitiveError!Value {
    return if (types.isPromise(args[0])) types.TRUE else types.FALSE;
}

fn makePromiseFn(args: []const Value) PrimitiveError!Value {
    if (types.isPromise(args[0])) return args[0];
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    return gc.allocPromise(true, args[0]) catch return PrimitiveError.OutOfMemory;
}

fn makePromiseLazy(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    return gc.allocPromise(false, args[0]) catch return PrimitiveError.OutOfMemory;
}

fn forceFn(args: []const Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError;

    var current = args[0];

    if (!types.isPromise(current)) return current;

    var iterations: usize = 0;
    while (iterations < 100000) : (iterations += 1) {
        if (!types.isPromise(current)) return current;
        const promise = types.toPromise(current);

        if (promise.forced) return promise.value;

        const thunk = promise.value;
        if (!types.isProcedure(thunk)) {
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

        // SRFI-45 §8: after the thunk returns, check if another force
        // has already completed this promise (re-entrant force).
        if (promise.forced) return promise.value;

        if (types.isPromise(result)) {
            const inner = types.toPromise(result);
            if (inner.forced) {
                promise.forced = true;
                promise.value = inner.value;
                return inner.value;
            }
            promise.value = inner.value;
            inner.forced = true;
            inner.value = types.makePointer(@ptrCast(promise));
            current = types.makePointer(@ptrCast(promise));
            continue;
        }

        promise.forced = true;
        promise.value = result;
        return result;
    }

    return PrimitiveError.TypeError;
}
