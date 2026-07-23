//! SRFI-181 (Custom Ports, and now Transcoded Ports) tests.
//!
//! Port has never held a Scheme Value field before this SRFI -- these tests
//! exercise the GC-marking foundation directly against a bare GC (mirroring
//! tests_srfi254.zig's style), since that's the exact risk this feature was
//! deferred over. Behavioral tests (actual read!/write!/close invocation,
//! and transcoded-port decode/encode) are in tests/scheme/srfi/srfi181.scm,
//! against a real VM.
//!
//! The "raiseContinuable" test below is different in kind from the rest of
//! this file: it validates a Zig-level mechanism (not SRFI 181's own API
//! surface) in isolation, before the transcoding decode/encode loop is
//! built on top of it -- per the explicit recommendation in issue #1729's
//! design review, since this is the one piece where the *approach* itself
//! needed validating, not just its implementation.
//!
//! The "transcoded port: decodes/eol-style/replace/raise" tests below are
//! also Zig-level, for the same reason: they exercise readOneByte's
//! transcoded-port branch (via real read-char calls through ctx.vm.eval)
//! using gc.allocTranscodedPort + vm.defineGlobal directly, since
//! %transcoded-port/native-transcoder/transcoded-port don't exist yet at
//! this stage. Once the portable .sld layer lands, the full SRFI-64
//! behavioral suite in tests/scheme/srfi/srfi181.scm supersedes these as
//! the primary coverage; these stay as the from-first-principles proof the
//! decode loop itself is correct, independent of that layer.

const std = @import("std");
const types = @import("types.zig");
const memory = @import("memory.zig");
const th = @import("testing_helpers.zig");
const primitives_control = @import("primitives_control.zig");

const GC = memory.GC;
const fix = types.makeFixnum;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

test "custom port: callback closures survive collection while only the port is reachable" {
    var gc = GC.init(std.testing.allocator);
    defer gc.deinit();
    gc.enabled = false;

    // read_proc/close_proc are stand-in heap Values (any GC-tracked object
    // proves markPortValues traces custom_backend correctly; a real
    // invokable closure isn't needed for this GC-focused test).
    var port = blk: {
        var read_proc = try gc.allocPair(fix(1), types.NIL);
        gc.pushRoot(&read_proc);
        var close_proc = try gc.allocPair(fix(2), types.NIL);
        gc.pushRoot(&close_proc);
        const p = try gc.allocCustomPort(true, false, true, read_proc, types.FALSE, types.FALSE, types.FALSE, close_proc, types.FALSE);
        gc.popRoot(); // close_proc
        gc.popRoot(); // read_proc
        break :blk p;
    };
    gc.pushRoot(&port);
    defer gc.popRoot();

    // read_proc/close_proc are now reachable *only* through port.custom_backend.
    gc.collect();

    const cb = types.toObject(port).as(types.Port).custom_backend.?;
    try expect(types.isPair(cb.read_proc));
    try expectEqual(@as(i64, 1), types.toFixnum(types.car(cb.read_proc)));
    try expect(types.isPair(cb.close_proc));
    try expectEqual(@as(i64, 2), types.toFixnum(types.car(cb.close_proc)));
    // Slots that were never given a callback stay the "absent" sentinel.
    try expectEqual(types.FALSE, cb.write_proc);
    try expectEqual(types.FALSE, cb.get_position_proc);
    try expectEqual(types.FALSE, cb.set_position_proc);
    try expectEqual(types.FALSE, cb.flush_proc);
}

test "custom port: unreachable port and its callbacks are fully collected (no leak)" {
    var gc = GC.init(std.testing.allocator);
    defer gc.deinit();
    gc.enabled = false;

    {
        var read_proc = try gc.allocPair(fix(1), types.NIL);
        gc.pushRoot(&read_proc);
        var close_proc = try gc.allocPair(fix(2), types.NIL);
        gc.pushRoot(&close_proc);
        _ = try gc.allocCustomPort(true, false, true, read_proc, types.FALSE, types.FALSE, types.FALSE, close_proc, types.FALSE);
        gc.popRoot(); // close_proc
        gc.popRoot(); // read_proc
    }
    // Nothing roots the port or its callbacks now.
    try expectEqual(@as(usize, 3), gc.object_count); // port + 2 pairs

    gc.collect();

    // All three are unreachable and swept. freeObject's .port arm must
    // destroy custom_backend itself, or std.testing.allocator's leak check
    // at gc.deinit() above would fail this test with a real memory leak.
    try expectEqual(@as(usize, 0), gc.object_count);
}

test "custom port: allocCustomPort roots its own callback arguments during allocation-time collection" {
    // The two tests above pre-root read_proc/close_proc with gc.pushRoot
    // before calling allocCustomPort, same as any ordinary caller would --
    // but that means they can't tell whether allocCustomPort's OWN
    // slice_roots protection (the thing that actually matters, since a
    // real caller's args come from VM registers already rooted by a
    // different mechanism) is present or missing. This test passes the
    // callbacks in deliberately UNROOTED (from this test's own
    // perspective) and forces a collection via gc.stress -- a runtime
    // field independent of the -Dgc-stress build flag -- during
    // allocCustomPort's own maybeCollect() call, so only its internal
    // slice_roots usage can keep them alive.
    var gc = GC.init(std.testing.allocator);
    defer gc.deinit();
    gc.enabled = false;
    const read_proc = try gc.allocPair(fix(1), types.NIL);
    const close_proc = try gc.allocPair(fix(2), types.NIL);

    gc.enabled = true;
    gc.stress = true;
    var port = try gc.allocCustomPort(true, false, true, read_proc, types.FALSE, types.FALSE, types.FALSE, close_proc, types.FALSE);
    gc.pushRoot(&port);
    defer gc.popRoot();

    const cb = types.toObject(port).as(types.Port).custom_backend.?;
    try expect(types.isPair(cb.read_proc));
    try expectEqual(@as(i64, 1), types.toFixnum(types.car(cb.read_proc)));
    try expect(types.isPair(cb.close_proc));
    try expectEqual(@as(i64, 2), types.toFixnum(types.car(cb.close_proc)));
}

test "raiseContinuable: a handler's return value flows back to the call site, not an unwind" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    // A handler that returns a tagged marker -- if raiseContinuable were to
    // unwind instead of continue, this value would never reach our result
    // (it would propagate as ExceptionRaised instead of a normal return).
    const handler = try ctx.vm.eval("(lambda (obj) (list 'handled obj))");

    const saved_handler_count = ctx.vm.handler_count;
    try ctx.vm.pushHandler(handler);

    const condition = types.makeFixnum(42);
    const result = try primitives_control.raiseContinuable(ctx.vm, condition);

    try expect(types.isPair(result));
    try expect(types.isSymbol(types.car(result)));
    try expectEqual(@as(i64, 42), types.toFixnum(types.car(types.cdr(result))));

    // The handler was popped for the call and re-pushed afterward -- the
    // handler stack must be exactly as this test left it, not permanently
    // altered by a single raiseContinuable call.
    try expectEqual(saved_handler_count + 1, ctx.vm.handler_count);
    ctx.vm.popHandler();
    try expectEqual(saved_handler_count, ctx.vm.handler_count);
}

test "raiseContinuable: with no handler installed, it unwinds via ExceptionRaised" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    try expectEqual(@as(usize, 0), ctx.vm.handler_count);
    const condition = types.makeFixnum(7);
    const result = primitives_control.raiseContinuable(ctx.vm, condition);
    try std.testing.expectError(error.ExceptionRaised, result);
    try expectEqual(condition, ctx.vm.current_exception);
}

test "transcoded port: wrapped_port survives collection while only the transcoded port is reachable" {
    var gc = GC.init(std.testing.allocator);
    defer gc.deinit();
    gc.enabled = false;

    // A stand-in heap Value for wrapped_port (any GC-tracked object proves
    // markPortValues/markValueInner/referencesYoung trace port.transcode
    // correctly; a real binary port isn't needed for this GC-focused test).
    var port = blk: {
        var wrapped = try gc.allocPair(fix(99), types.NIL);
        gc.pushRoot(&wrapped);
        const p = try gc.allocTranscodedPort(wrapped, true, false, .utf8, .none, .replace);
        gc.popRoot(); // wrapped
        break :blk p;
    };
    gc.pushRoot(&port);
    defer gc.popRoot();

    // wrapped is now reachable *only* through port.transcode.wrapped_port.
    gc.collect();

    const ts = types.toObject(port).as(types.Port).transcode.?;
    try expect(types.isPair(ts.wrapped_port));
    try expectEqual(@as(i64, 99), types.toFixnum(types.car(ts.wrapped_port)));
    try expectEqual(types.Codec.utf8, ts.codec);
    try expectEqual(types.EolStyle.none, ts.eol_style);
    try expectEqual(types.ErrorMode.replace, ts.error_mode);
}

test "transcoded port: unreachable port and its wrapped_port are fully collected (no leak)" {
    var gc = GC.init(std.testing.allocator);
    defer gc.deinit();
    gc.enabled = false;

    {
        var wrapped = try gc.allocPair(fix(1), types.NIL);
        gc.pushRoot(&wrapped);
        _ = try gc.allocTranscodedPort(wrapped, true, false, .utf8, .none, .replace);
        gc.popRoot(); // wrapped
    }
    // Nothing roots the transcoded port or its wrapped_port now.
    try expectEqual(@as(usize, 2), gc.object_count); // transcoded port + the wrapped-port stand-in pair

    gc.collect();

    // Both are unreachable and swept. freeObject's .port arm must destroy
    // the TranscodeState struct itself, or std.testing.allocator's leak
    // check at gc.deinit() above would fail this test with a real leak.
    try expectEqual(@as(usize, 0), gc.object_count);
}

/// Drives `(read-char <port_name>)` to EOF via real Scheme evaluation and
/// returns the collected characters as an owned byte slice (freed by the
/// caller) -- exercises readOneByte's transcoded-port branch exactly as a
/// real program would, through read-char/eof-object?, not by poking
/// decodeOneChar directly.
fn readAllCharsAlloc(ctx: *th.TestContext, port_name: []const u8) ![]u8 {
    var src_buf: [256]u8 = undefined;
    const src = std.fmt.bufPrint(&src_buf,
        \\(let loop ((acc '()))
        \\  (let ((c (read-char {s})))
        \\    (if (eof-object? c)
        \\        (list->string (reverse acc))
        \\        (loop (cons c acc)))))
    , .{port_name}) catch unreachable;
    const result = try ctx.vm.eval(src);
    const s = types.toObject(result).as(types.SchemeString);
    return std.testing.allocator.dupe(u8, s.data[0..s.len]);
}

test "transcoded port: decodes plain ASCII bytes one character at a time" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    var wrapped = try ctx.gc.allocStringInputPort("hello");
    ctx.gc.pushRoot(&wrapped);
    const tp = try ctx.gc.allocTranscodedPort(wrapped, true, false, .utf8, .none, .replace);
    ctx.gc.popRoot();
    try ctx.vm.defineGlobal("tp", tp);

    const out = try readAllCharsAlloc(&ctx, "tp");
    defer std.testing.allocator.free(out);
    try expect(std.mem.eql(u8, "hello", out));
}

test "transcoded port: decodes multi-byte UTF-8 sequences" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    var wrapped = try ctx.gc.allocStringInputPort("caf\xC3\xA9"); // "café"
    ctx.gc.pushRoot(&wrapped);
    const tp = try ctx.gc.allocTranscodedPort(wrapped, true, false, .utf8, .none, .replace);
    ctx.gc.popRoot();
    try ctx.vm.defineGlobal("tp", tp);

    const out = try readAllCharsAlloc(&ctx, "tp");
    defer std.testing.allocator.free(out);
    try expect(std.mem.eql(u8, "caf\xC3\xA9", out));
}

test "transcoded port: eol-style crlf collapses CR, LF, and CRLF to a single newline" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    // CRLF, then a bare CR, then a bare LF between letters.
    var wrapped = try ctx.gc.allocStringInputPort("a\r\nb\rc\nd");
    ctx.gc.pushRoot(&wrapped);
    const tp = try ctx.gc.allocTranscodedPort(wrapped, true, false, .utf8, .crlf, .replace);
    ctx.gc.popRoot();
    try ctx.vm.defineGlobal("tp", tp);

    const out = try readAllCharsAlloc(&ctx, "tp");
    defer std.testing.allocator.free(out);
    try expect(std.mem.eql(u8, "a\nb\nc\nd", out));
}

test "transcoded port: eol-style none performs no line-ending translation" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    var wrapped = try ctx.gc.allocStringInputPort("a\r\nb");
    ctx.gc.pushRoot(&wrapped);
    const tp = try ctx.gc.allocTranscodedPort(wrapped, true, false, .utf8, .none, .replace);
    ctx.gc.popRoot();
    try ctx.vm.defineGlobal("tp", tp);

    const out = try readAllCharsAlloc(&ctx, "tp");
    defer std.testing.allocator.free(out);
    try expect(std.mem.eql(u8, "a\r\nb", out));
}

test "transcoded port: replace mode substitutes U+FFFD for a bad lead byte and continues" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    var wrapped = try ctx.gc.allocStringInputPort("A\xFFB");
    ctx.gc.pushRoot(&wrapped);
    const tp = try ctx.gc.allocTranscodedPort(wrapped, true, false, .utf8, .none, .replace);
    ctx.gc.popRoot();
    try ctx.vm.defineGlobal("tp", tp);

    const out = try readAllCharsAlloc(&ctx, "tp");
    defer std.testing.allocator.free(out);
    try expect(std.mem.eql(u8, "A\u{FFFD}B", out));
}

test "transcoded port: replace mode substitutes U+FFFD for a sequence truncated at EOF" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    // 'A', then a 2-byte lead with nothing following.
    var wrapped = try ctx.gc.allocStringInputPort("A\xC3");
    ctx.gc.pushRoot(&wrapped);
    const tp = try ctx.gc.allocTranscodedPort(wrapped, true, false, .utf8, .none, .replace);
    ctx.gc.popRoot();
    try ctx.vm.defineGlobal("tp", tp);

    const out = try readAllCharsAlloc(&ctx, "tp");
    defer std.testing.allocator.free(out);
    try expect(std.mem.eql(u8, "A\u{FFFD}", out));
}

test "transcoded port: replace mode substitutes U+FFFD for a bad continuation byte" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    // 0xE2 promises a 3-byte sequence; 0x28 ('(') is not a valid
    // continuation byte. This implementation treats the whole attempted
    // 3-byte span as one invalid unit rather than resyncing at the byte
    // level -- see decodeOneChar's doc comment -- so '(' does not survive
    // as its own character.
    var wrapped = try ctx.gc.allocStringInputPort("\xE2\x28\xA1B");
    ctx.gc.pushRoot(&wrapped);
    const tp = try ctx.gc.allocTranscodedPort(wrapped, true, false, .utf8, .none, .replace);
    ctx.gc.popRoot();
    try ctx.vm.defineGlobal("tp", tp);

    const out = try readAllCharsAlloc(&ctx, "tp");
    defer std.testing.allocator.free(out);
    try expect(std.mem.eql(u8, "\u{FFFD}B", out));
}

test "transcoded port: raise mode signals an io_decoding condition once and decoding continues" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    var wrapped = try ctx.gc.allocStringInputPort("A\xFFB");
    ctx.gc.pushRoot(&wrapped);
    const tp = try ctx.gc.allocTranscodedPort(wrapped, true, false, .utf8, .none, .raise);
    ctx.gc.popRoot();
    try ctx.vm.defineGlobal("tp", tp);

    // Installs the handler and makes both read-char calls within a single
    // top-level eval: vm.execute resets handler_count at the start of
    // *every* top-level eval call (each is an independent Scheme
    // evaluation, same as separate REPL entries), so a handler pushed in
    // one eval and relied on from a later, separate eval call would
    // already be gone -- with-exception-handler must bracket the reads in
    // the same evaluation to correctly demonstrate the effect.
    const saved_handler_count = ctx.vm.handler_count;
    const result = try ctx.vm.eval(
        \\(let ((handler-calls 0) (last-condition #f))
        \\  (with-exception-handler
        \\    (lambda (obj)
        \\      (set! handler-calls (+ handler-calls 1))
        \\      (set! last-condition obj)
        \\      'ignored)
        \\    (lambda ()
        \\      ;; First read-char: 'A', no error. Second: hits the bad
        \\      ;; byte, signals (the handler runs once and returns
        \\      ;; normally), then continues and decodes 'B' as this same
        \\      ;; call's result -- not just that the condition fired, but
        \\      ;; that decoding actually resumes afterward.
        \\      (let* ((c1 (read-char tp))
        \\             (c2 (read-char tp)))
        \\        (list c1 c2 handler-calls last-condition)))))
    );
    try expectEqual(saved_handler_count, ctx.vm.handler_count);

    const c1 = types.car(result);
    const c2 = types.car(types.cdr(result));
    const calls = types.car(types.cdr(types.cdr(result)));
    const cond = types.car(types.cdr(types.cdr(types.cdr(result))));

    try expectEqual(types.makeChar('A'), c1);
    try expectEqual(types.makeChar('B'), c2);
    try expectEqual(@as(i64, 1), types.toFixnum(calls));
    try expect(types.isErrorObject(cond));
    try expectEqual(types.ErrorObject.ErrorType.io_decoding, types.toObject(cond).as(types.ErrorObject).error_type);
}

test "transcoded port: reading after the wrapped port is closed underneath it raises" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    var wrapped = try ctx.gc.allocStringInputPort("hello");
    ctx.gc.pushRoot(&wrapped);
    const tp = try ctx.gc.allocTranscodedPort(wrapped, true, false, .utf8, .none, .replace);
    ctx.gc.popRoot();
    try ctx.vm.defineGlobal("wrapped", wrapped);
    try ctx.vm.defineGlobal("tp", tp);

    _ = try ctx.vm.eval("(close-port wrapped)");
    const result = ctx.vm.eval("(read-char tp)");
    try std.testing.expectError(th.VMError.ExceptionRaised, result);
}

/// Returns the wrapped output port's accumulated bytes as an owned slice
/// (freed by the caller) after evaluating `write_src` (Scheme source that
/// writes to a global named `tp`) -- exercises portWriteBytes's
/// transcoded-port branch through real write-char/write-string calls, not
/// by poking writeBytesToTranscodedPort directly.
fn writeThenReadWrappedAlloc(ctx: *th.TestContext, write_src: []const u8) ![]u8 {
    _ = try ctx.vm.eval(write_src);
    const result = try ctx.vm.eval("(get-output-string wrapped)");
    const s = types.toObject(result).as(types.SchemeString);
    return std.testing.allocator.dupe(u8, s.data[0..s.len]);
}

test "transcoded port: encodes write-string and forwards ASCII to the wrapped port unchanged" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    var wrapped = try ctx.gc.allocStringOutputPort();
    ctx.gc.pushRoot(&wrapped);
    const tp = try ctx.gc.allocTranscodedPort(wrapped, false, true, .utf8, .none, .replace);
    ctx.gc.popRoot();
    try ctx.vm.defineGlobal("wrapped", wrapped);
    try ctx.vm.defineGlobal("tp", tp);

    const out = try writeThenReadWrappedAlloc(&ctx, "(write-string \"hello\" tp)");
    defer std.testing.allocator.free(out);
    try expect(std.mem.eql(u8, "hello", out));
}

test "transcoded port: encodes multi-byte characters via write-char" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    var wrapped = try ctx.gc.allocStringOutputPort();
    ctx.gc.pushRoot(&wrapped);
    const tp = try ctx.gc.allocTranscodedPort(wrapped, false, true, .utf8, .none, .replace);
    ctx.gc.popRoot();
    try ctx.vm.defineGlobal("wrapped", wrapped);
    try ctx.vm.defineGlobal("tp", tp);

    // #\xE9 is U+00E9 (é), 0xC3 0xA9 in UTF-8.
    const out = try writeThenReadWrappedAlloc(&ctx, "(write-char #\\xE9 tp)");
    defer std.testing.allocator.free(out);
    try expect(std.mem.eql(u8, "\xC3\xA9", out));
}

test "transcoded port: eol-style crlf expands newline characters to CRLF on write" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    var wrapped = try ctx.gc.allocStringOutputPort();
    ctx.gc.pushRoot(&wrapped);
    const tp = try ctx.gc.allocTranscodedPort(wrapped, false, true, .utf8, .crlf, .replace);
    ctx.gc.popRoot();
    try ctx.vm.defineGlobal("wrapped", wrapped);
    try ctx.vm.defineGlobal("tp", tp);

    const out = try writeThenReadWrappedAlloc(&ctx, "(write-string \"a\\nb\\nc\" tp)");
    defer std.testing.allocator.free(out);
    try expect(std.mem.eql(u8, "a\r\nb\r\nc", out));
}

test "transcoded port: eol-style lf leaves newline characters as bare LF on write" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    var wrapped = try ctx.gc.allocStringOutputPort();
    ctx.gc.pushRoot(&wrapped);
    const tp = try ctx.gc.allocTranscodedPort(wrapped, false, true, .utf8, .lf, .replace);
    ctx.gc.popRoot();
    try ctx.vm.defineGlobal("wrapped", wrapped);
    try ctx.vm.defineGlobal("tp", tp);

    const out = try writeThenReadWrappedAlloc(&ctx, "(write-string \"a\\nb\" tp)");
    defer std.testing.allocator.free(out);
    try expect(std.mem.eql(u8, "a\nb", out));
}

test "transcoded port: writing after the wrapped port is closed underneath it raises" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    var wrapped = try ctx.gc.allocStringOutputPort();
    ctx.gc.pushRoot(&wrapped);
    const tp = try ctx.gc.allocTranscodedPort(wrapped, false, true, .utf8, .none, .replace);
    ctx.gc.popRoot();
    try ctx.vm.defineGlobal("wrapped", wrapped);
    try ctx.vm.defineGlobal("tp", tp);

    _ = try ctx.vm.eval("(close-port wrapped)");
    const result = ctx.vm.eval("(write-char #\\a tp)");
    try std.testing.expectError(th.VMError.ExceptionRaised, result);
}

test "transcoded port: port-position and set-port-position! are unsupported" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    var wrapped = try ctx.gc.allocStringInputPort("hello");
    ctx.gc.pushRoot(&wrapped);
    const tp = try ctx.gc.allocTranscodedPort(wrapped, true, false, .utf8, .none, .replace);
    ctx.gc.popRoot();
    try ctx.vm.defineGlobal("tp", tp);

    // fd = -1 with no is_string_port/custom_backend already falls through
    // to platform.seek(-1, ...) failing -- these three primitives need no
    // transcode-specific code at all, but that "free by construction"
    // claim is exactly the kind of thing worth pinning down with a test
    // rather than trusting by inspection alone.
    const has_position = try ctx.vm.eval("(port-has-port-position? tp)");
    try expectEqual(types.FALSE, has_position);

    const get_result = ctx.vm.eval("(port-position tp)");
    try std.testing.expectError(th.VMError.InvalidArgument, get_result);

    const set_result = ctx.vm.eval("(set-port-position! tp 0)");
    try std.testing.expectError(th.VMError.InvalidArgument, set_result);
}

test "transcoded port: closing it also closes the wrapped port" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    var wrapped = try ctx.gc.allocStringInputPort("hello");
    ctx.gc.pushRoot(&wrapped);
    const tp = try ctx.gc.allocTranscodedPort(wrapped, true, false, .utf8, .none, .replace);
    ctx.gc.popRoot();
    try ctx.vm.defineGlobal("wrapped", wrapped);
    try ctx.vm.defineGlobal("tp", tp);

    _ = try ctx.vm.eval("(close-port tp)");

    const tp_open = try ctx.vm.eval("(input-port-open? tp)");
    try expectEqual(types.FALSE, tp_open);
    const wrapped_open = try ctx.vm.eval("(input-port-open? wrapped)");
    try expectEqual(types.FALSE, wrapped_open);
}

test "transcoded port: double-closing (either order) is idempotent" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    var wrapped = try ctx.gc.allocStringInputPort("hello");
    ctx.gc.pushRoot(&wrapped);
    const tp = try ctx.gc.allocTranscodedPort(wrapped, true, false, .utf8, .none, .replace);
    ctx.gc.popRoot();
    try ctx.vm.defineGlobal("wrapped", wrapped);
    try ctx.vm.defineGlobal("tp", tp);

    // Close the wrapped port first, then the transcoded port on top of
    // it -- must not error just because the cascade's own close finds the
    // wrapped port already closed.
    _ = try ctx.vm.eval("(close-port wrapped)");
    _ = try ctx.vm.eval("(close-port tp)");
    // And closing the same port twice outright.
    _ = try ctx.vm.eval("(close-port tp)");
}
