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
    .{ .name = "%promise-forced?", .func = &promiseForcedP, .arity = .{ .exact = 1 }, .libs = LS.initOne(.scheme_lazy) },
    .{ .name = "%promise-forcing?", .func = &promiseForcingP, .arity = .{ .exact = 1 }, .libs = LS.initOne(.scheme_lazy) },
    .{ .name = "%promise-value", .func = &promiseValue, .arity = .{ .exact = 1 }, .libs = LS.initOne(.scheme_lazy) },
    .{ .name = "%promise-complete!", .func = &promiseComplete, .arity = .{ .exact = 2 }, .libs = LS.initOne(.scheme_lazy) },
    .{ .name = "%promise-set-forcing!", .func = &promiseSetForcing, .arity = .{ .exact = 2 }, .libs = LS.initOne(.scheme_lazy) },
    .{ .name = "%promise-merge!", .func = &promiseMerge, .arity = .{ .exact = 2 }, .libs = LS.initOne(.scheme_lazy) },
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

fn promiseForcedP(args: []const Value) PrimitiveError!Value {
    if (!types.isPromise(args[0])) return primitives.typeError("%promise-forced?", "promise", args[0]);
    return if (types.toPromise(args[0]).forced) types.TRUE else types.FALSE;
}

fn promiseForcingP(args: []const Value) PrimitiveError!Value {
    if (!types.isPromise(args[0])) return primitives.typeError("%promise-forcing?", "promise", args[0]);
    return if (types.toPromise(args[0]).forcing) types.TRUE else types.FALSE;
}

fn promiseValue(args: []const Value) PrimitiveError!Value {
    if (!types.isPromise(args[0])) return primitives.typeError("%promise-value", "promise", args[0]);
    return types.toPromise(args[0]).value;
}

fn promiseComplete(args: []const Value) PrimitiveError!Value {
    if (!types.isPromise(args[0])) return primitives.typeError("%promise-complete!", "promise", args[0]);
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const promise = types.toPromise(args[0]);
    promise.forced = true;
    promise.forcing = false;
    promise.value = args[1];
    gc.writeBarrier(&promise.header, args[1]);
    return types.VOID;
}

fn promiseSetForcing(args: []const Value) PrimitiveError!Value {
    if (!types.isPromise(args[0])) return primitives.typeError("%promise-set-forcing!", "promise", args[0]);
    types.toPromise(args[0]).forcing = args[1] == types.TRUE;
    return types.VOID;
}

fn promiseMerge(args: []const Value) PrimitiveError!Value {
    if (!types.isPromise(args[0])) return primitives.typeError("%promise-merge!", "promise", args[0]);
    if (!types.isPromise(args[1])) return primitives.typeError("%promise-merge!", "promise", args[1]);
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const outer = types.toPromise(args[0]);
    const inner = types.toPromise(args[1]);
    outer.value = inner.value;
    gc.writeBarrier(&outer.header, inner.value);
    inner.forced = true;
    inner.value = types.makePointer(@ptrCast(outer));
    gc.writeBarrier(&inner.header, types.makePointer(@ptrCast(outer)));
    outer.forcing = false;
    return types.VOID;
}

fn forceFn(args: []const Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError; // bare-ok: no VM
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;

    var current = args[0];
    gc.pushRoot(&current);
    defer gc.popRoot();

    if (!types.isPromise(current)) return current;

    while (true) {
        if (!types.isPromise(current)) return current;
        const promise = types.toPromise(current);

        if (promise.forced) {
            // Follow redirect: forced value is a promise only via SRFI-45 merge (inner → head), never a cycle.
            current = promise.value;
            continue;
        }

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
            current = promise.value;
            continue;
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
                current = inner.value;
                continue;
            }
            promise.value = inner.value;
            gc.writeBarrier(&promise.header, inner.value);
            inner.forced = true;
            inner.value = types.makePointer(@ptrCast(promise));
            gc.writeBarrier(&inner.header, types.makePointer(@ptrCast(promise)));
            promise.forcing = false;
            current = types.makePointer(@ptrCast(promise));
            continue;
        }

        promise.forcing = false;
        promise.forced = true;
        promise.value = result;
        gc.writeBarrier(&promise.header, result);
        return result;
    }
}
