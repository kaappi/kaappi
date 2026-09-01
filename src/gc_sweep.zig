//! GC sweep phase, split out of gc_collect.zig (file size policy):
//! sweepYoung / sweepOld / sweep, the per-tag objectSize accounting switch,
//! and freeObject's per-tag destructor switch (with its poison/quarantine
//! plumbing, #1687). gc_collect.zig keeps collection orchestration, the
//! remembered set, marking, and SRFI 254 weak-reference processing, and
//! re-exports freeObject so existing `gc_collect.freeObject` callers are
//! unchanged. Adding a heap type means updating the switches in BOTH files
//! (see "How to add a new heap type" in CLAUDE.md).

const std = @import("std");
const platform = @import("platform.zig");
const types_process = @import("types_process.zig");
const builtin = @import("builtin");
const types = @import("types.zig");
const types_port = @import("types_port.zig");
const memory_mod = @import("memory.zig");
const gc_collect = @import("gc_collect.zig");
const shared_channel = @import("shared_channel.zig");
const shared_buffer = @import("shared_buffer.zig");
const instrument = @import("channel_instrument.zig");
const GC = memory_mod.GC;

const Value = types.Value;
const Object = types.Object;
const Pair = types.Pair;
const Vector = types.Vector;
const Closure = types.Closure;
const Function = types.Function;
const Symbol = types.Symbol;
const SchemeString = types.SchemeString;
const NativeFn = types.NativeFn;
const Flonum = types.Flonum;
const Bytevector = types.Bytevector;
const NumericVector = types.NumericVector;
const Transformer = types.Transformer;
const RecordType = types.RecordType;
const RecordInstance = types.RecordInstance;
const Port = types.Port;
const Continuation = types.Continuation;
const MultipleValues = types.MultipleValues;
const Promise = types.Promise;
const HashTable = types.HashTable;
const HashEntry = types.HashEntry;
const CallFrame = types.CallFrame;
const FfiLibrary = types.FfiLibrary;
const FfiFunction = types.FfiFunction;
const FfiCallback = types.FfiCallback;
const Bignum = types.Bignum;
const Rational = types.Rational;
const RandomSource = types.RandomSource;
const Ephemeron = types.Ephemeron;
const Guardian = types.Guardian;
const TransportCell = types.TransportCell;

pub fn sweepYoung(gc: *GC) void {
    var prev: ?*Object = null;
    var obj = gc.objects;
    while (obj) |o| {
        if (o.flags.marked) {
            o.flags.marked = false;
            o.flags.survive_count +|= 1;
            if (o.flags.survive_count >= 2) {
                const next = o.next;
                if (prev) |p| {
                    p.next = next;
                } else {
                    gc.objects = next;
                }
                o.flags.generation = 1;
                o.flags.survive_count = 0;
                o.next = gc.old_objects;
                gc.old_objects = o;
                // #1961 promotion scan: the write barrier only fires for a
                // container that is *already* old, so an old→young edge
                // created while the container was young (a barrier there is
                // a correct no-op) would go unrecorded at promotion — and
                // since the minor mark stopped tracing through old objects,
                // that edge is the referent's only route to survival. Scan
                // at promotion and remember the container. The dedup flag is
                // provably clear here: this object was young a moment ago,
                // and writeBarrier only ever enqueues old containers.
                if (gc_collect.referencesYoung(gc, o)) {
                    gc.rememberObject(o);
                }
                obj = next;
            } else {
                prev = o;
                obj = o.next;
            }
        } else {
            const next = o.next;
            if (prev) |p| {
                p.next = next;
            } else {
                gc.objects = next;
            }
            const freed = objectSize(o);
            gc.stats.objects_freed += 1;
            gc.stats.bytes_freed += freed;
            if (gc.bytes_allocated >= freed)
                gc.bytes_allocated -= freed;
            freeObject(gc, o);
            gc.object_count -= 1;
            obj = next;
        }
    }
}

pub fn sweepOld(gc: *GC) void {
    var prev: ?*Object = null;
    var obj = gc.old_objects;
    while (obj) |o| {
        if (o.flags.marked) {
            o.flags.marked = false;
            // #1961 full-collect re-scan: the drain at the top of this
            // collection emptied the remembered set, and a full collection
            // never promotes (young survivors stay generation 0), so an old
            // container whose young referent just survived this full would
            // otherwise face the next minor with no remembered-set entry —
            // and the generational minor mark would sweep the referent.
            // Re-record every surviving old→young edge here, where the old
            // heap is already being walked. Objects freed below never had a
            // live referent to protect. All owned flags were cleared by the
            // drain, so rememberObject's dedup guard is exact.
            if (gc_collect.referencesYoung(gc, o)) {
                gc.rememberObject(o);
            }
            prev = o;
            obj = o.next;
        } else {
            const next = o.next;
            if (prev) |p| {
                p.next = next;
            } else {
                gc.old_objects = next;
            }
            const freed = objectSize(o);
            gc.stats.objects_freed += 1;
            gc.stats.bytes_freed += freed;
            if (gc.bytes_allocated >= freed)
                gc.bytes_allocated -= freed;
            freeObject(gc, o);
            gc.object_count -= 1;
            obj = next;
        }
    }
}

pub fn sweep(gc: *GC) void {
    var prev: ?*Object = null;
    var obj = gc.objects;
    while (obj) |o| {
        if (o.flags.marked) {
            o.flags.marked = false;
            prev = o;
            obj = o.next;
        } else {
            const next = o.next;
            if (prev) |p| {
                p.next = next;
            } else {
                gc.objects = next;
            }
            const freed = objectSize(o);
            gc.stats.objects_freed += 1;
            gc.stats.bytes_freed += freed;
            if (gc.bytes_allocated >= freed)
                gc.bytes_allocated -= freed;
            freeObject(gc, o);
            gc.object_count -= 1;
            obj = next;
        }
    }
}

pub fn objectSize(obj: *Object) usize {
    return switch (obj.tag) {
        .pair => @sizeOf(Pair),
        .symbol => @sizeOf(Symbol) + obj.as(Symbol).name.len,
        .string => @sizeOf(SchemeString) + obj.as(SchemeString).data.len,
        .closure => @sizeOf(Closure) + obj.as(Closure).upvalues.len * @sizeOf(Value),
        .function => blk: {
            const f = obj.as(Function);
            var s: usize = @sizeOf(Function);
            s += f.code.capacity;
            s += f.constants.capacity * @sizeOf(Value);
            if (f.global_cache) |c| s += c.len * @sizeOf(Value);
            break :blk s;
        },
        .native_fn => @sizeOf(NativeFn),
        .native_closure => @sizeOf(types.NativeClosure) + obj.as(types.NativeClosure).upvalues.len * @sizeOf(Value),
        .flonum => @sizeOf(Flonum),
        .vector => @sizeOf(Vector) + obj.as(Vector).data.len * @sizeOf(Value),
        // A backed bytevector (lever D) borrows its bytes from a SharedBuffer,
        // so only the struct counts against this heap. Comptime-pruned in the
        // shipped build (kaappi#1794): `shared` is always null there, so this
        // always takes the "count the full data" branch.
        .bytevector => blk: {
            const bv = obj.as(Bytevector);
            if (comptime instrument.enabled) {
                break :blk @sizeOf(Bytevector) + (if (bv.shared == null) bv.data.len else 0);
            }
            break :blk @sizeOf(Bytevector) + bv.data.len;
        },
        .numeric_vector => @sizeOf(NumericVector) + obj.as(NumericVector).data.len,
        .transformer => blk: {
            const t = obj.as(Transformer);
            break :blk @sizeOf(Transformer) + t.literals.len * @sizeOf(Value) +
                t.patterns.len * @sizeOf(Value) + t.templates.len * @sizeOf(Value) +
                t.let_syntax_peer_vals.len * @sizeOf(Value);
        },
        .error_object => @sizeOf(types.ErrorObject),
        .record_type => blk: {
            const rt = obj.as(RecordType);
            var size: usize = @sizeOf(RecordType) + rt.name.len;
            size += rt.own_field_names.len * @sizeOf([]const u8);
            for (rt.own_field_names) |s| size += s.len;
            size += rt.own_field_mutable.len * @sizeOf(bool);
            if (rt.uid) |u| size += u.len;
            break :blk size;
        },
        .record_instance => @sizeOf(RecordInstance) + obj.as(RecordInstance).fields.len * @sizeOf(Value),
        .port => blk: {
            const port = obj.as(Port);
            var s: usize = @sizeOf(Port);
            if (port.owns_name) s += port.name.len;
            if (port.string_data) |sd| s += sd.len;
            if (port.string_out_buf) |_| s += port.string_out_cap;
            if (port.read_buf) |rb| s += rb.len;
            if (port.write_buf) |wb| s += wb.len;
            // Owned satellites (random_gen, custom_backend, transcode) are
            // derived from types_port.satellites, so a new one is counted
            // without editing this arm (audit v2, 7A).
            s += types_port.satelliteBytes(port);
            break :blk s;
        },
        .continuation => @sizeOf(Continuation) + obj.as(Continuation).backing.len * @sizeOf(Value),
        .multiple_values => @sizeOf(MultipleValues) + obj.as(MultipleValues).values.len * @sizeOf(Value),
        .complex => @sizeOf(types.Complex),
        .promise => @sizeOf(Promise),
        .parameter => @sizeOf(types.ParameterObject),
        .hash_table => @sizeOf(HashTable) + obj.as(HashTable).entries.len * @sizeOf(types.HashEntry),
        .ffi_library => @sizeOf(FfiLibrary) + obj.as(FfiLibrary).name.len,
        .ffi_function => blk: {
            const f = obj.as(FfiFunction);
            break :blk @sizeOf(FfiFunction) + f.name.len + f.param_types.len * @sizeOf(types.FfiType);
        },
        .ffi_callback => @sizeOf(FfiCallback),
        .bignum => @sizeOf(Bignum) + obj.as(Bignum).limbs.len * @sizeOf(u64),
        .rational => @sizeOf(Rational),
        .file_info => @sizeOf(types.FileInfo),
        .user_info => blk: {
            const ui = obj.as(types.UserInfo);
            break :blk @sizeOf(types.UserInfo) + ui.name.len + ui.home_dir.len + ui.shell.len + ui.full_name.len;
        },
        .group_info => @sizeOf(types.GroupInfo) + obj.as(types.GroupInfo).name.len,
        .directory_object => @sizeOf(types.DirectoryObject),
        .random_source => @sizeOf(RandomSource),
        .fiber => blk: {
            const fiber = obj.as(@import("fiber.zig").Fiber);
            break :blk @sizeOf(@import("fiber.zig").Fiber) +
                fiber.registers.len * @sizeOf(Value) +
                fiber.frames.len * @sizeOf(types.CallFrame) +
                fiber.handler_stack.len * @sizeOf(types.ExceptionHandler) +
                fiber.wind_stack.len * @sizeOf(types.WindRecord);
        },
        .channel => @sizeOf(types.Channel),
        .process => @sizeOf(types.Process),
        .mutex => @sizeOf(types.Mutex),
        .condition_variable => @sizeOf(types.ConditionVariable),
        .srfi18_time => @sizeOf(types.Srfi18Time),
        .scheme_environment => @sizeOf(types.SchemeEnvironment),
        .ephemeron => @sizeOf(Ephemeron),
        .guardian => blk: {
            const g = obj.as(Guardian);
            break :blk @sizeOf(Guardian) +
                (g.registered.capacity + g.ready.capacity) * @sizeOf(types.GuardEntry);
        },
        .transport_cell => @sizeOf(TransportCell),
    };
}

inline fn poisonAndDestroy(gc: *GC, comptime T: type, ptr: *T) void {
    if (builtin.mode == .Debug) {
        @memset(@as([*]u8, @ptrCast(ptr))[0..@sizeOf(T)], 0xAA);
    }
    if (comptime memory_mod.uaf_detection) {
        // Stamp AFTER the poison so the sentinel survives it. A later mark
        // of this dead header then panics deterministically in
        // markValueInner instead of being absorbed by the foreign-owner
        // skip (#1687). Every heap type places its Object header in a
        // `header` field.
        ptr.header.owner = memory_mod.FREED_OWNER;
    }
    if (comptime memory_mod.free_quarantine) {
        // Withhold the slot from the allocator so a dangling value marked
        // after this sweep still reads the sentinel instead of a recycled
        // live object. Released by quarantineReleaseToCap after a later
        // mark phase.
        gc.quarantinePut(@ptrCast(ptr), @sizeOf(T), .of(T));
    } else {
        gc.allocator.destroy(ptr);
    }
}

pub fn freeObject(gc: *GC, obj: *Object) void {
    switch (obj.tag) {
        .pair => {
            const pair = obj.as(Pair);
            poisonAndDestroy(gc, Pair, pair);
        },
        .symbol => {
            const sym = obj.as(Symbol);
            gc.allocator.free(sym.name);
            poisonAndDestroy(gc, Symbol, sym);
        },
        .string => {
            const str = obj.as(SchemeString);
            memory_mod.freeSliceNoFill(gc.allocator, u8, str.data);
            poisonAndDestroy(gc, SchemeString, str);
        },
        .closure => {
            const cls = obj.as(Closure);
            memory_mod.freeSliceNoFill(gc.allocator, Value, cls.upvalues);
            poisonAndDestroy(gc, Closure, cls);
        },
        .function => {
            const func = obj.as(Function);
            func.code.deinit(gc.allocator);
            func.constants.deinit(gc.allocator);
            func.line_table.deinit(gc.allocator);
            if (func.global_cache) |cache| {
                gc.allocator.free(cache);
            }
            if (func.debug_locals.len > 0) {
                gc.allocator.free(func.debug_locals);
            }
            if (func.owns_name) {
                if (func.name) |n| gc.allocator.free(n);
            }
            poisonAndDestroy(gc, Function, func);
        },
        .native_fn => {
            const nf = obj.as(NativeFn);
            poisonAndDestroy(gc, NativeFn, nf);
        },
        .native_closure => {
            const nc = obj.as(types.NativeClosure);
            memory_mod.freeSliceNoFill(gc.allocator, Value, nc.upvalues);
            poisonAndDestroy(gc, types.NativeClosure, nc);
        },
        .flonum => {
            const flo = obj.as(Flonum);
            poisonAndDestroy(gc, Flonum, flo);
        },
        .vector => {
            const vec = obj.as(Vector);
            memory_mod.freeSliceNoFill(gc.allocator, Value, vec.data);
            poisonAndDestroy(gc, Vector, vec);
        },
        .transformer => {
            const tx = obj.as(Transformer);
            gc.allocator.free(tx.literals);
            gc.allocator.free(tx.patterns);
            gc.allocator.free(tx.templates);
            if (tx.captured_locals.len > 0) gc.allocator.free(tx.captured_locals);
            if (tx.literal_bound.len > 0) gc.allocator.free(tx.literal_bound);
            if (tx.let_syntax_peer_names.len > 0) gc.allocator.free(tx.let_syntax_peer_names);
            if (tx.let_syntax_peer_vals.len > 0) gc.allocator.free(tx.let_syntax_peer_vals);
            if (tx.bound_free_refs.len > 0) gc.allocator.free(tx.bound_free_refs);
            if (tx.def_site_local_refs.len > 0) gc.allocator.free(tx.def_site_local_refs);
            poisonAndDestroy(gc, Transformer, tx);
        },
        .error_object => {
            const err = obj.as(types.ErrorObject);
            poisonAndDestroy(gc, types.ErrorObject, err);
        },
        .record_type => {
            const rt = obj.as(RecordType);
            // `parent` is a live heap object owned by the GC's own sweep,
            // not memory this RecordType owns -- never freed here.
            for (rt.own_field_names) |s| gc.allocator.free(s);
            gc.allocator.free(rt.own_field_names);
            gc.allocator.free(rt.own_field_mutable);
            if (rt.uid) |u| gc.allocator.free(u);
            gc.allocator.free(rt.name);
            poisonAndDestroy(gc, RecordType, rt);
        },
        .record_instance => {
            const ri = obj.as(RecordInstance);
            memory_mod.freeSliceNoFill(gc.allocator, Value, ri.fields);
            poisonAndDestroy(gc, RecordInstance, ri);
        },
        .bytevector => {
            const bv = obj.as(Bytevector);
            // Lever D (kaappi#1472): a backed bytevector borrows its bytes from
            // a SharedBuffer -- release the reference (freeing the buffer at
            // zero) instead of freeing bytes this heap never owned. Comptime-
            // pruned in the shipped build (kaappi#1794): `shared` is always
            // null there, so a shipped binary never loads the field at all.
            if (comptime instrument.enabled) {
                if (bv.shared) |raw| {
                    const sb: *shared_buffer.SharedBuffer = @ptrCast(@alignCast(raw));
                    sb.release();
                } else {
                    memory_mod.freeSliceNoFill(gc.allocator, u8, bv.data);
                }
            } else {
                memory_mod.freeSliceNoFill(gc.allocator, u8, bv.data);
            }
            poisonAndDestroy(gc, Bytevector, bv);
        },
        .numeric_vector => {
            const nv = obj.as(NumericVector);
            memory_mod.freeSliceNoFill(gc.allocator, u8, nv.data);
            poisonAndDestroy(gc, NumericVector, nv);
        },
        .promise => {
            const p = obj.as(Promise);
            poisonAndDestroy(gc, Promise, p);
        },
        .port => {
            const port = obj.as(Port);
            // Close the fd if still open and not stdin/stdout/stderr
            if (port.is_open and port.fd > 2 and !port.is_string_port) {
                // Best-effort flush of buffered output before the fd is lost.
                // No parking is possible during a sweep, so a would-block
                // (EAGAIN) or any other failure just drops the remainder —
                // programs that need the data call flush-output-port or
                // close-port instead of leaking the port to the collector.
                //
                // For that promise to hold, the drain must be unable to
                // block. A port the scheduler never touched (a fresh
                // process pipe, KEP-0022) is still in BLOCKING mode, and a
                // blocking write into a full pipe whose reader never drains
                // would wedge the collector itself — while toggling
                // O_NONBLOCK for the drain is no better: the flag lives on
                // the SHARED open-file description, so every dup/dup2
                // alias (a child's stdio, an fd->port twin) transiently —
                // or, on a failed restore, permanently — turns non-blocking
                // (kaappi#2442 review, twice). So no flag is ever touched;
                // instead the drain is gated on seekability: a seekable fd
                // is a regular file, whose blocking write completes without
                // waiting on a peer (the flush-on-collect file ports have
                // always had), while an unseekable one (pipe, socket, FIFO,
                // tty — everything with a peer or flow control) simply
                // drops its remainder, exactly the best-effort contract.
                const drain_ok = if (comptime platform.is_windows or platform.is_wasm)
                    true // the Windows arms below have their own non-blocking gates
                else
                    port.nonblocking or port.write_buf == null or
                        platform.seek(port.fd, 0, platform.SEEK_CUR) >= 0;
                if (drain_ok) {
                    if (port.write_buf) |wb| {
                        var start = port.write_buf_start;
                        while (start < port.write_buf_len) {
                            // A Windows socket port must send() — CRT _write
                            // cannot operate on a SOCKET handle — and a pipe
                            // port in emulated non-blocking mode must keep its
                            // quota gate: plain _write on a full pipe would
                            // block this sweep forever, exactly the would-block
                            // this loop promises to drop (#1608).
                            const remaining = port.write_buf_len - start;
                            const rc = if (platform.is_windows and port.fd_state.is_socket)
                                platform.sockSend(port.fd, wb.ptr + start, remaining)
                            else if (platform.is_windows and port.fd_state.is_pipe and port.nonblocking)
                                platform.pipeWrite(port.fd, wb.ptr + start, remaining)
                            else
                                platform.write(port.fd, wb.ptr + start, remaining);
                            if (rc < 0 and platform.errno(rc) == .INTR) continue;
                            if (rc <= 0) break;
                            start += @as(usize, @intCast(rc));
                        }
                    }
                }
                _ = platform.close(port.fd);
            }
            if (port.write_buf) |wb| {
                gc.allocator.free(wb);
            }
            if (port.owns_name) {
                gc.allocator.free(port.name);
            }
            if (port.read_buf) |rb| {
                gc.allocator.free(rb);
            }
            // Free string port buffers
            if (port.string_data) |sd| {
                gc.allocator.free(sd);
            }
            if (port.string_out_buf) |sb| {
                gc.allocator.free(sb);
            }
            // Owned satellites (random_gen, custom_backend, transcode).
            // Derived from types_port.satellites, so a new one is freed
            // without editing this arm (audit v2, 7A); see
            // destroySatellites for why a sweep frees only the structs and
            // never calls close_proc or touches a wrapped port.
            types_port.destroySatellites(port, gc.allocator);
            poisonAndDestroy(gc, Port, port);
        },
        .continuation => {
            const cont = obj.as(Continuation);
            // registers/frames/handlers/wind_records are all views into
            // the single backing allocation; free it once. Escape
            // continuations have no backing (empty slice).
            if (cont.backing.len > 0) memory_mod.freeSliceNoFill(gc.allocator, Value, cont.backing);
            poisonAndDestroy(gc, Continuation, cont);
        },
        .multiple_values => {
            const mv = obj.as(MultipleValues);
            memory_mod.freeSliceNoFill(gc.allocator, Value, mv.values);
            poisonAndDestroy(gc, MultipleValues, mv);
        },
        .complex => {
            const c = obj.as(types.Complex);
            poisonAndDestroy(gc, types.Complex, c);
        },
        .parameter => {
            const p = obj.as(types.ParameterObject);
            poisonAndDestroy(gc, types.ParameterObject, p);
        },
        .hash_table => {
            const ht = obj.as(HashTable);
            memory_mod.freeSliceNoFill(gc.allocator, HashEntry, ht.entries);
            poisonAndDestroy(gc, HashTable, ht);
        },
        .ffi_library => {
            const lib = obj.as(FfiLibrary);
            // Do NOT dlclose here -- let ffi-close handle that explicitly
            gc.allocator.free(lib.name);
            poisonAndDestroy(gc, FfiLibrary, lib);
        },
        .ffi_function => {
            const ffi_fn = obj.as(FfiFunction);
            gc.allocator.free(ffi_fn.name);
            gc.allocator.free(ffi_fn.param_types);
            poisonAndDestroy(gc, FfiFunction, ffi_fn);
        },
        .ffi_callback => {
            const cb = obj.as(FfiCallback);
            if (cb.active) {
                const ffi_cb = @import("ffi_callback.zig");
                ffi_cb.releaseSlot(cb.slot_index);
            }
            poisonAndDestroy(gc, FfiCallback, cb);
        },
        .bignum => {
            const bn = obj.as(Bignum);
            memory_mod.freeSliceNoFill(gc.allocator, u64, bn.limbs);
            poisonAndDestroy(gc, Bignum, bn);
        },
        .rational => {
            const rat = obj.as(Rational);
            poisonAndDestroy(gc, Rational, rat);
        },
        .file_info => {
            const fi = obj.as(types.FileInfo);
            poisonAndDestroy(gc, types.FileInfo, fi);
        },
        .user_info => {
            const ui = obj.as(types.UserInfo);
            gc.allocator.free(ui.name);
            gc.allocator.free(ui.home_dir);
            gc.allocator.free(ui.shell);
            gc.allocator.free(ui.full_name);
            poisonAndDestroy(gc, types.UserInfo, ui);
        },
        .group_info => {
            const gi = obj.as(types.GroupInfo);
            gc.allocator.free(gi.name);
            poisonAndDestroy(gc, types.GroupInfo, gi);
        },
        .directory_object => {
            const d = obj.as(types.DirectoryObject);
            if (d.dir) |dir| {
                platform.dirIterDestroy(@ptrCast(@alignCast(dir)));
                d.dir = null;
            }
            poisonAndDestroy(gc, types.DirectoryObject, d);
        },
        .random_source => {
            poisonAndDestroy(gc, RandomSource, obj.as(RandomSource));
        },
        .fiber => {
            const fiber = obj.as(@import("fiber.zig").Fiber);
            fiber.param_overrides.deinit();
            fiber.owned_mutexes.deinit(gc.allocator);
            memory_mod.freeSliceNoFill(gc.allocator, CallFrame, fiber.frames);
            memory_mod.freeSliceNoFill(gc.allocator, Value, fiber.registers);
            memory_mod.freeSliceNoFill(gc.allocator, types.ExceptionHandler, fiber.handler_stack);
            memory_mod.freeSliceNoFill(gc.allocator, types.WindRecord, fiber.wind_stack);
            poisonAndDestroy(gc, @import("fiber.zig").Fiber, fiber);
        },
        .channel => {
            const ch = obj.as(types.Channel);
            // KEP-0002 §1 rule 3: stubs are released by freeObject, from
            // ANY path -- a real GC sweep, a test's GC.deinit(), or an
            // envelope's own mini-GC tearing itself down through this same
            // function. No separate envelope-specific bookkeeping exists.
            if (ch.shared) |s| {
                const sc: *shared_channel.SharedChannel = @ptrCast(@alignCast(s));
                sc.release();
            }
            poisonAndDestroy(gc, types.Channel, ch);
        },
        .process => {
            const proc = obj.as(types.Process);
            // Zombie discipline (KEP-0022 Phase 1): drop the collected
            // Process from the heap's unreaped list first -- after
            // poisonAndDestroy the pointer is invalid -- then make one
            // last-resort non-blocking reap attempt so an already-exited
            // child of an abandoned Process does not linger as a zombie.
            // Still-running children are simply no longer tracked; their
            // zombies (if any) are reparented to init when this process
            // exits. A BLOCKING wait is never acceptable inside a sweep.
            for (gc.unreaped_processes.items, 0..) |p, i| {
                if (p == proc) {
                    _ = gc.unreaped_processes.swapRemove(i);
                    break;
                }
            }
            if (proc.status == null) {
                if (comptime !platform.is_wasm) _ = types_process.reapNonBlocking(proc);
            }
            // Belt: a live reactor registration roots the Process
            // (Reactor.markRoots), so a collected one is unregistered and
            // its pidfd already closed — but a stray OS object must never
            // outlive the object. On Windows this is also the *only* place
            // the process and Job Object handles are closed: they are the
            // reactor's wait object and the kill target for the Process's
            // whole lifetime, so no reap may release them (KEP-0022
            // Phases 2-3).
            types_process.releaseHandles(proc);
            poisonAndDestroy(gc, types.Process, proc);
        },
        .mutex => {
            poisonAndDestroy(gc, types.Mutex, obj.as(types.Mutex));
        },
        .condition_variable => {
            poisonAndDestroy(gc, types.ConditionVariable, obj.as(types.ConditionVariable));
        },
        .srfi18_time => {
            poisonAndDestroy(gc, types.Srfi18Time, obj.as(types.Srfi18Time));
        },
        .scheme_environment => {
            const se = obj.as(types.SchemeEnvironment);
            if (se.owned) {
                se.env.deinit();
                gc.allocator.destroy(se.env);
            }
            poisonAndDestroy(gc, types.SchemeEnvironment, se);
        },
        .ephemeron => {
            poisonAndDestroy(gc, Ephemeron, obj.as(Ephemeron));
        },
        .guardian => {
            const g = obj.as(Guardian);
            g.registered.deinit(gc.allocator);
            g.ready.deinit(gc.allocator);
            poisonAndDestroy(gc, Guardian, g);
        },
        .transport_cell => {
            poisonAndDestroy(gc, TransportCell, obj.as(TransportCell));
        },
    }
}
