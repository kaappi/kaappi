const std = @import("std");
const types = @import("types.zig");
const vm_mod = @import("vm.zig");
const primitives = @import("primitives.zig");
const memory = @import("memory.zig");
const printer = @import("printer.zig");
const primitives_io = @import("primitives_io.zig");
const diagnostics = @import("diagnostics.zig");
const Value = types.Value;
const NativeFn = types.NativeFn;
const PrimitiveError = primitives.PrimitiveError;
const LS = primitives.LibSet;

pub const specs = [_]primitives.PrimSpec{
    .{ .name = "raise", .func = &raiseFn, .arity = .{ .exact = 1 }, .libs = LS.initMany(&.{ .scheme_base, .srfi_18 }) },
    .{ .name = "raise-continuable", .func = &raiseContinuableFn, .arity = .{ .exact = 1 }, .libs = LS.initOne(.scheme_base) },
    .{ .name = "with-exception-handler", .func = &withExceptionHandlerFn, .arity = .{ .exact = 2 }, .libs = LS.initMany(&.{ .scheme_base, .srfi_18 }) },
    .{ .name = "error", .func = &errorFn, .arity = .{ .variadic = 1 }, .libs = LS.initOne(.scheme_base) },
    .{ .name = "error-object?", .func = &errorObjectP, .arity = .{ .exact = 1 }, .libs = LS.initOne(.scheme_base) },
    .{ .name = "error-object-message", .func = &errorObjectMessage, .arity = .{ .exact = 1 }, .libs = LS.initOne(.scheme_base) },
    .{ .name = "error-object-irritants", .func = &errorObjectIrritants, .arity = .{ .exact = 1 }, .libs = LS.initOne(.scheme_base) },
    // KEP-0005 §4 (#1508): the stable diagnostic code is additive metadata in
    // its own (kaappi diagnostics) library, never an extension of scheme.base.
    .{ .name = "error-object-code", .func = &errorObjectCode, .arity = .{ .exact = 1 }, .libs = LS.initOne(.kaappi_diagnostics) },
    .{ .name = "file-error?", .func = &fileErrorP, .arity = .{ .exact = 1 }, .libs = LS.initOne(.scheme_base) },
    .{ .name = "read-error?", .func = &readErrorP, .arity = .{ .exact = 1 }, .libs = LS.initOne(.scheme_base) },
    .{ .name = "call-with-current-continuation", .func = &callWithCurrentContinuation, .arity = .{ .exact = 1 }, .libs = LS.initMany(&.{ .scheme_base, .scheme_r5rs }) },
    .{ .name = "call/cc", .func = &callWithCurrentContinuation, .arity = .{ .exact = 1 }, .libs = LS.initOne(.scheme_base) },
    .{ .name = "call-with-escape-continuation", .func = &callWithEscapeContinuation, .arity = .{ .exact = 1 }, .libs = LS.initOne(.scheme_base) },
    .{ .name = "call/ec", .func = &callWithEscapeContinuation, .arity = .{ .exact = 1 }, .libs = LS.initOne(.scheme_base) },
    // dynamic-wind is implemented in Scheme (src/vm_bootstrap.zig); this
    // entry keeps the arity metadata and library exports.
    .{ .name = "dynamic-wind", .func = primitives.bootstrapStub("dynamic-wind"), .arity = .{ .exact = 3 }, .libs = LS.initMany(&.{ .scheme_base, .scheme_r5rs }) },
    .{ .name = "values", .func = &valuesFn, .arity = .{ .variadic = 0 }, .libs = LS.initMany(&.{ .scheme_base, .scheme_r5rs }) },
    .{ .name = "call-with-values", .func = &callWithValuesFn, .arity = .{ .exact = 2 }, .libs = LS.initMany(&.{ .scheme_base, .scheme_r5rs }) },
    .{ .name = "%push-wind", .func = &pushWindFn, .arity = .{ .exact = 2 }, .libs = LS.initOne(.internal) },
    .{ .name = "%pop-wind", .func = &popWindFn, .arity = .{ .exact = 0 }, .libs = LS.initOne(.internal) },
    // SRFI 248 (minimal delimited continuations): building blocks for the
    // portable (srfi 248) library. Not for direct use — see lib/srfi/248.sld.
    .{ .name = "%call-with-unwind-handler", .func = &callWithUnwindHandlerFn, .arity = .{ .exact = 2 }, .libs = LS.initOne(.srfi_248_primitives) },
    .{ .name = "%unwind-raise-empty?", .func = &unwindRaiseEmptyFn, .arity = .{ .exact = 0 }, .libs = LS.initOne(.srfi_248_primitives) },
    .{ .name = "%pop-unwind-handler!", .func = &popUnwindHandlerFn, .arity = .{ .exact = 0 }, .libs = LS.initOne(.srfi_248_primitives) },
};

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
    // SRFI 248: a sticky (unwind) handler catches raise the same way it
    // catches raise-continuable — invoked in place so the handler can capture
    // the delimited continuation before the stack unwinds.
    if (vm.handler_count > 0 and vm.handler_stack[vm.handler_count - 1].sticky) {
        return dispatchStickyUnwind(vm, args[0], false);
    }
    vm.current_exception = args[0];
    return PrimitiveError.ExceptionRaised;
}

/// SRFI 248: invoke the current sticky (unwind) handler in place, WITHOUT
/// popping it. Because it stays on the handler stack, a delimited continuation
/// captured while it runs snapshots it, so resuming that continuation re-arms
/// the prompt (reset0 semantics). Latches emptiness for empty-continuation?.
/// `continuable` distinguishes raise-continuable (a normal handler return is
/// its value) from raise (a normal return is a secondary error per R7RS — the
/// SRFI 248 handler always escapes via shift, so this only fires on misuse).
fn dispatchStickyUnwind(vm: *vm_mod.VM, obj: Value, continuable: bool) PrimitiveError!Value {
    const entry = vm.handler_stack[vm.handler_count - 1];
    // The delimited continuation is empty iff the raise is in tail context of
    // the guarded thunk: the raise itself is a tail call (native_call_was_tail)
    // AND no non-tail frame sits between the prompt and the raise. The sticky
    // handler was installed one frame below the thunk (%call-with-unwind-handler
    // pushes it, then calls the thunk via callThunk), so a pure tail chain keeps
    // frame_count at entry.frame_count + 1; any intervening non-tail call adds a
    // frame. The immediate tail bit alone is not enough — a raise in tail
    // position of a helper that was itself called non-tail is not empty.
    vm.pending_raise_empty = vm.native_call_was_tail and
        (vm.frame_count == entry.frame_count + 1);
    const handler = entry.handler;
    const result = vm.callHandler(handler, obj, 0) catch |err| {
        return err;
    };
    if (continuable) return result;
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    var msg = gc.allocString("exception handler returned from non-continuable exception") catch
        return PrimitiveError.OutOfMemory;
    gc.pushRoot(&msg);
    defer gc.popRoot();
    const err_obj = gc.allocErrorObject(msg, types.NIL) catch return PrimitiveError.OutOfMemory;
    vm.current_exception = err_obj;
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
    // SRFI 248: sticky handler — invoke in place without popping.
    if (vm.handler_stack[vm.handler_count - 1].sticky) {
        return dispatchStickyUnwind(vm, args[0], true);
    }
    const handler = vm.handler_stack[vm.handler_count - 1].handler;
    vm.popHandler();
    const result = vm.callHandler(handler, args[0], 0) catch |err| {
        vm.pushHandler(handler) catch {};
        return err;
    };
    vm.pushHandler(handler) catch return PrimitiveError.OutOfMemory;
    return result;
}

/// Convert a natively-propagating VM error (undefined variable, type error,
/// arity, ...) into the Scheme error object a handler or guard clause sees.
/// This is the single boundary where the error's stable diagnostic code gets
/// stamped onto the object — that is what makes `error-object-code` able to
/// recover it (KEP-0005 §4, #1508). `runtimeErrorCode` maps the Zig error to
/// its curated code and yields `.uncategorized` (→ #f) for anything without
/// one. Shared by with-exception-handler and %call-with-unwind-handler so the
/// two error-coding boundaries cannot drift apart.
///
/// The returned object is *unrooted* — root it before allocating again.
fn nativeErrorToErrorObject(vm: *vm_mod.VM, gc: *memory.GC, err: anyerror) PrimitiveError!Value {
    const detail = vm.getErrorDetail();
    var msg_str = if (detail.len > 0)
        gc.allocString(detail) catch return PrimitiveError.OutOfMemory
    else
        gc.allocString("error") catch return PrimitiveError.OutOfMemory;
    gc.pushRoot(&msg_str);
    defer gc.popRoot();
    return gc.allocErrorObjectCoded(msg_str, types.NIL, diagnostics.runtimeErrorCode(err)) catch
        return PrimitiveError.OutOfMemory;
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
            gc.pushRoot(&handler_root);
            defer gc.popRoot();
            var exc = vm.current_exception orelse types.FALSE;
            vm.current_exception = null;
            gc.pushRoot(&exc);
            defer gc.popRoot();
            _ = vm.callHandler(handler_root, exc, 0) catch |herr| {
                return herr;
            };
            // Handler returned from non-continuable raise — re-raise per R7RS
            var reraise_msg = gc.allocString("handler returned") catch return PrimitiveError.OutOfMemory;
            gc.pushRoot(&reraise_msg);
            defer gc.popRoot();
            const reraise_err = gc.allocErrorObject(reraise_msg, types.NIL) catch return PrimitiveError.OutOfMemory;
            vm.current_exception = reraise_err;
            return PrimitiveError.ExceptionRaised;
        }
        vm.popHandler();
        // Convert VM-level errors into Scheme exceptions so guard can catch them.
        const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
        const err_obj = try nativeErrorToErrorObject(vm, gc, err);
        var handler_root = handler;
        gc.pushRoot(&handler_root);
        defer gc.popRoot();
        var err_root = err_obj;
        gc.pushRoot(&err_root);
        defer gc.popRoot();
        const handler_result = vm.callHandler(handler_root, err_root, 0) catch |herr| {
            return herr;
        };
        return handler_result;
    };

    // Normal return -- pop the handler
    vm.popHandler();
    return result;
}

/// SRFI 248 %call-with-unwind-handler: like with-exception-handler, but installs
/// a *sticky* handler (raise/raise-continuable invoke it in place without
/// popping). The portable (srfi 248) library wraps this in a Filinski
/// shift/reset delimiter so the handler receives a delimited continuation.
///
/// The thunk's raise/raise-continuable are dispatched to `handler` in place by
/// dispatchStickyUnwind (the handler shifts away, surfacing here as
/// ContinuationInvoked, which we propagate). A native runtime error (car of a
/// non-pair, unbound variable, ...) is not routed through the handler stack, so
/// we catch it here, turn it into a coded error object, and hand it to the
/// handler with an empty delimited continuation (the stack has already unwound).
fn callWithUnwindHandlerFn(args: []const Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError; // bare-ok: no VM
    const handler = args[0];
    const thunk = args[1];

    if (!types.isProcedure(handler)) return primitives.typeError("%call-with-unwind-handler", "procedure", args[0]);
    if (!types.isProcedure(thunk)) return primitives.typeError("%call-with-unwind-handler", "procedure", args[1]);

    vm.pushHandlerSticky(handler) catch return PrimitiveError.OutOfMemory;

    const result = vm.callThunk(thunk) catch |err| {
        if (err == vm_mod.VMError.ContinuationInvoked) {
            // The handler shifted away to the enclosing reset*, whose
            // continuation restore already re-set the handler stack (and the
            // library popped the sticky handler via %pop-unwind-handler!), so
            // popping here would corrupt the restored state.
            return PrimitiveError.ContinuationInvoked;
        }
        vm.popHandler();
        const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
        var handler_root = handler;
        gc.pushRoot(&handler_root);
        defer gc.popRoot();

        var exc: Value = undefined;
        if (err == vm_mod.VMError.ExceptionRaised) {
            exc = vm.current_exception orelse types.FALSE;
            vm.current_exception = null;
        } else {
            exc = try nativeErrorToErrorObject(vm, gc, err);
        }
        gc.pushRoot(&exc);
        defer gc.popRoot();
        // The guarded computation has unwound, so the delimited continuation the
        // handler will capture is empty.
        vm.pending_raise_empty = true;
        return vm.callHandler(handler_root, exc, 0) catch |herr| {
            return herr;
        };
    };

    vm.popHandler();
    return result;
}

/// SRFI 248 %unwind-raise-empty?: #t when the delimited continuation captured
/// for the raise/raise-continuable that most recently reached a sticky handler
/// is empty (the raise was in tail context of the guarded thunk). Backs
/// empty-continuation?.
fn unwindRaiseEmptyFn(_: []const Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError; // bare-ok: no VM
    return if (vm.pending_raise_empty) types.TRUE else types.FALSE;
}

/// SRFI 248 %pop-unwind-handler!: remove the current sticky (unwind) handler
/// from the *live* handler stack. The library calls this from inside the shift,
/// after the delimited continuation has been captured (so the snapshot still
/// carries the handler and a resume re-arms the prompt), but before running the
/// user handler body — otherwise that body's own raise/raise-continuable would
/// re-enter the same sticky handler and loop. No-op if the top handler is not
/// sticky, so it can never disturb an ordinary handler.
fn popUnwindHandlerFn(_: []const Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError; // bare-ok: no VM
    if (vm.handler_count > 0 and vm.handler_stack[vm.handler_count - 1].sticky) {
        vm.handler_count -= 1;
    }
    return types.VOID;
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

/// (error-object-code obj) — KEP-0005 §4 (#1508). Returns the interned symbol
/// for the stable diagnostic code the implementation stamped on `obj` (e.g.
/// `KP3004` for a division-by-zero error), or #f when there is none.
///
/// Deliberately a *total* function that never raises, unlike the R7RS
/// error-object-message/-irritants accessors: it is meant to be the first
/// dispatch check inside a `guard`, where R7RS `raise` may have delivered any
/// value at all. A non-error object and an uncoded error object (a user
/// `(error ...)`, whose code stays `.uncategorized`) both answer #f, so a
/// program can `(eq? (error-object-code e) 'KP3001)` without first proving `e`
/// is even an error object. `eq?` works because the symbol is interned.
fn errorObjectCode(args: []const Value) PrimitiveError!Value {
    if (!types.isErrorObject(args[0])) return types.FALSE;
    const err = types.toObject(args[0]).as(types.ErrorObject);
    // `.uncategorized` is the "no code assigned" sentinel — the KP namespace is
    // reserved to the implementation, so uncoded errors surface as #f.
    if (err.code == .uncategorized) return types.FALSE;
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    var buf: [diagnostics.Code.render_width]u8 = undefined;
    // `render` writes into the stack buffer and allocSymbol interns from it
    // (never collecting), so nothing here needs rooting.
    return gc.allocSymbol(err.code.render(&buf)) catch return PrimitiveError.OutOfMemory;
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
    gc.pushRoot(&irritants);
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
    vm.gc.pushRoot(&cont_val);
    defer vm.gc.popRoot();

    // Call proc(continuation)
    const result = vm.callHandler(proc, cont_val, base_reg) catch |err| {
        return err;
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
    vm.gc.pushRoot(&cont_val);
    defer vm.gc.popRoot();
    const cont_obj = types.toObject(cont_val).as(types.Continuation);

    const result = vm.callHandler(proc, cont_val, base_reg) catch |err| {
        // The extent has ended (escape unwound through here, or proc errored).
        cont_obj.valid = false;
        return err;
    };

    // proc returned normally without escaping; the extent is over.
    cont_obj.valid = false;
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
        return err;
    };

    // Call consumer with the produced values
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    var produced_root = produced;
    gc.pushRoot(&produced_root);
    defer gc.popRoot();
    if (types.isMultipleValues(produced_root)) {
        const mv = types.toObject(produced_root).as(types.MultipleValues);
        const result = vm.callWithArgs(consumer, mv.values) catch |err| {
            return err;
        };
        return result;
    } else {
        // Single value -- call consumer with one argument (use callWithArgs
        // so arity is validated, matching the multi-value path)
        const result = vm.callWithArgs(consumer, &[_]Value{produced}) catch |err| {
            return err;
        };
        return result;
    }
}

fn pushWindFn(args: []const Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError; // bare-ok: no VM
    if (!types.isProcedure(args[0])) return primitives.typeError("%push-wind", "procedure", args[0]);
    if (!types.isProcedure(args[1])) return primitives.typeError("%push-wind", "procedure", args[1]);
    if (vm.wind_count >= vm_mod.MAX_WINDS) return PrimitiveError.OutOfMemory;
    vm.wind_stack[vm.wind_count] = .{ .before = args[0], .after = args[1] };
    vm.wind_count += 1;
    return types.VOID;
}

fn popWindFn(_: []const Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError; // bare-ok: no VM
    if (vm.wind_count == 0) return PrimitiveError.TypeError; // bare-ok: underflow
    vm.wind_count -= 1;
    return types.VOID;
}
