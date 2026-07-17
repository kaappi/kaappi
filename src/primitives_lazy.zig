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
    // force is implemented in Scheme (src/vm_bootstrap.zig); this entry keeps
    // the arity metadata and library exports.
    .{ .name = "force", .func = primitives.bootstrapStub("force"), .arity = .{ .exact = 1 }, .libs = LS.initMany(&.{ .scheme_lazy, .scheme_r5rs }) },
    .{ .name = "promise?", .func = &promiseP, .arity = .{ .exact = 1 }, .libs = LS.initMany(&.{ .scheme_base, .scheme_lazy }) },
    .{ .name = "make-promise", .func = &makePromiseFn, .arity = .{ .exact = 1 }, .libs = LS.initMany(&.{ .scheme_base, .scheme_lazy }) },
    .{ .name = "%make-promise-lazy", .func = &makePromiseLazy, .arity = .{ .exact = 1 }, .libs = LS.initOne(.scheme_base) },
    .{ .name = "%promise-forced?", .func = &promiseForcedP, .arity = .{ .exact = 1 }, .libs = LS.initOne(.internal) },
    .{ .name = "%promise-forcing?", .func = &promiseForcingP, .arity = .{ .exact = 1 }, .libs = LS.initOne(.internal) },
    .{ .name = "%promise-value", .func = &promiseValue, .arity = .{ .exact = 1 }, .libs = LS.initOne(.internal) },
    .{ .name = "%promise-complete!", .func = &promiseComplete, .arity = .{ .exact = 2 }, .libs = LS.initOne(.internal) },
    .{ .name = "%promise-set-forcing!", .func = &promiseSetForcing, .arity = .{ .exact = 2 }, .libs = LS.initOne(.internal) },
    .{ .name = "%promise-merge!", .func = &promiseMerge, .arity = .{ .exact = 2 }, .libs = LS.initOne(.internal) },
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
    inner.value = types.makePointer(&outer.header);
    gc.writeBarrier(&inner.header, types.makePointer(&outer.header));
    outer.forcing = false;
    return types.VOID;
}
