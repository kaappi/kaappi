const std = @import("std");
const types = @import("types.zig");
const primitives = @import("primitives.zig");
const memory = @import("memory.zig");
const vm_mod = @import("vm.zig");
const Value = types.Value;
const PrimitiveError = primitives.PrimitiveError;
const LS = primitives.LibSet;
const NativeFn = types.NativeFn;

pub const specs = [_]primitives.PrimSpec{
    .{ .name = "force", .func = &forceFn, .arity = .{ .exact = 1 }, .libs = LS.initMany(&.{ .scheme_lazy, .scheme_r5rs }) },
    .{ .name = "promise?", .func = &promiseP, .arity = .{ .exact = 1 }, .libs = LS.initMany(&.{ .scheme_base, .scheme_lazy }) },
    .{ .name = "make-promise", .func = &makePromiseFn, .arity = .{ .exact = 1 }, .libs = LS.initMany(&.{ .scheme_base, .scheme_lazy }) },
    .{ .name = "%make-promise-lazy", .func = &makePromiseLazy, .arity = .{ .exact = 1 }, .libs = LS.initOne(.scheme_base) },
};

fn promiseP(args: []const Value) PrimitiveError!Value {
    return if (types.isPromise(args[0])) types.TRUE else types.FALSE;
}

fn makePromiseFn(args: []const Value) PrimitiveError!Value {
    if (types.isPromise(args[0])) return args[0];
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    return gc.allocPromise(true, args[0]) catch return PrimitiveError.OutOfMemory;
}

fn makePromiseLazy(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    return gc.allocPromise(false, args[0]) catch return PrimitiveError.OutOfMemory;
}

fn forceFn(args: []const Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError; // bare-ok: no VM
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;

    var current = args[0];
    gc.pushRoot(&current);
    defer gc.popRoot();

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

        promise.forcing = true;

        const result = vm.callWithArgs(thunk, &[_]Value{}) catch |err| {
            promise.forcing = false;
            return err;
        };

        // SRFI-45 §8: after the thunk returns, check if another force
        // has already completed this promise (re-entrant force).
        if (promise.forced) {
            promise.forcing = false;
            return promise.value;
        }

        if (types.isPromise(result)) {
            const inner = types.toPromise(result);
            // SRFI-45 §8: detect cyclic promise chains where a thunk
            // returns a promise that is already being forced.
            if (inner.forcing) {
                promise.forcing = false;
                vm.setErrorDetail("re-entrant forcing of promise", .{});
                return PrimitiveError.TypeError; // bare-ok: detail set above
            }
            if (inner.forced) {
                promise.forcing = false;
                promise.forced = true;
                promise.value = inner.value;
                gc.writeBarrier(&promise.header, inner.value);
                return inner.value;
            }
            promise.value = inner.value;
            gc.writeBarrier(&promise.header, inner.value);
            inner.forced = true;
            inner.value = types.makePointer(@ptrCast(promise));
            gc.writeBarrier(&inner.header, types.makePointer(@ptrCast(promise)));
            current = types.makePointer(@ptrCast(promise));
            continue;
        }

        promise.forcing = false;
        promise.forced = true;
        promise.value = result;
        gc.writeBarrier(&promise.header, result);
        return result;
    }

    return primitives.typeError("force", "non-circular promise chain", args[0]);
}
