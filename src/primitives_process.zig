//! `(kaappi process)` — native subprocess support, Phase 1 (KEP-0022,
//! kaappi#2414). POSIX only: registered `.sandbox = false, .wasm = false`,
//! and the whole file is excluded from the WASM and Windows builds (see the
//! `all_specs` concatenation in `primitives.zig` — neither has `posix_spawn`;
//! Windows' CreateProcess backend is Phase 3).
//!
//! Phase 1 spawns via `posix_spawnp(3)` with `posix_spawn_file_actions_t`
//! redirections and offers a *blocking* `process-wait`. There is no reactor
//! reaping yet (Phase 2), so a fiber never parks on child exit; the child's
//! pipe ports, however, are ordinary reactor-integrated fd ports and a read
//! that would block already parks the calling fiber.
//!
//! A `Process` is thread-affine: every accessor checks the header
//! `Object.owner` against the current GC id (the channel precedent), and
//! `gc_deep_copy.zig` refuses to copy one across a channel.

const std = @import("std");
const builtin = @import("builtin");
const types = @import("types.zig");
const memory = @import("memory.zig");
const vm_mod = @import("vm.zig");
const primitives = @import("primitives.zig");
const platform = @import("platform.zig");
const primitives_io = @import("primitives_io.zig");

const Value = types.Value;
const GC = memory.GC;
const PrimitiveError = primitives.PrimitiveError;
const LS = primitives.LibSet;

// ---------------------------------------------------------------------------
// libc process surface
//
// Zig's `std.c` only exposes the posix_spawn family on Darwin, so declare it
// here (Kaappi links libc). `posix_spawn_file_actions_t` and
// `posix_spawnattr_t` are opaque objects whose size is platform-specific; the
// _init/_destroy pair manages their contents in place, so an over-allocated,
// suitably aligned byte buffer works on every target (glibc's spawnattr is
// the largest at ~336 bytes — 512 is a safe ceiling).
// ---------------------------------------------------------------------------

// Opaque posix_spawn objects — over-allocate a byte buffer large enough for
// any target's real struct (glibc's spawnattr is the largest at ~336 bytes),
// suitably aligned; _init/_destroy manage the contents in place. Both use the
// same 512-byte ceiling so an undersized buffer can never silently corrupt the
// stack in _init.
const FileActions = extern struct {
    buf: [512]u8 align(@alignOf(usize)) = [_]u8{0} ** 512,
};
const SpawnAttr = extern struct {
    buf: [512]u8 align(@alignOf(usize)) = [_]u8{0} ** 512,
};

/// Universal across glibc/musl/macOS/BSD.
const POSIX_SPAWN_SETPGROUP: c_short = 0x02;

const O_RDONLY: c_int = 0;
const O_WRONLY: c_int = 1;
const WNOHANG: c_int = 1;
const SIGTERM: i64 = 15;

/// `posix_spawn_file_actions_addchdir_np` exists on glibc (>=2.29), musl
/// (>=1.2.3), macOS and FreeBSD, but NOT on NetBSD or OpenBSD — their libc
/// has no chdir file action at all. Reference the symbol only where it links,
/// so `directory:` degrades to a clear error there rather than breaking the
/// build (kaappi#2414). A portable chdir for those two BSDs is a later phase.
const have_addchdir_np = switch (builtin.os.tag) {
    .linux, .macos, .freebsd => true,
    else => false,
};

extern "c" fn posix_spawnp(
    pid: *c_int,
    file: [*:0]const u8,
    file_actions: ?*const FileActions,
    attrp: ?*const SpawnAttr,
    argv: [*]const ?[*:0]const u8,
    envp: [*]const ?[*:0]const u8,
) c_int;
extern "c" fn posix_spawn_file_actions_init(fa: *FileActions) c_int;
extern "c" fn posix_spawn_file_actions_destroy(fa: *FileActions) c_int;
extern "c" fn posix_spawn_file_actions_adddup2(fa: *FileActions, fd: c_int, newfd: c_int) c_int;
extern "c" fn posix_spawn_file_actions_addopen(fa: *FileActions, fd: c_int, path: [*:0]const u8, oflag: c_int, mode: c_uint) c_int;
extern "c" fn posix_spawn_file_actions_addchdir_np(fa: *FileActions, path: [*:0]const u8) c_int;
extern "c" fn posix_spawnattr_init(attr: *SpawnAttr) c_int;
extern "c" fn posix_spawnattr_destroy(attr: *SpawnAttr) c_int;
extern "c" fn posix_spawnattr_setflags(attr: *SpawnAttr, flags: c_short) c_int;
extern "c" fn posix_spawnattr_setpgroup(attr: *SpawnAttr, pgroup: c_int) c_int;
extern "c" fn kill(pid: c_int, sig: c_int) c_int;
extern "c" fn killpg(pgrp: c_int, sig: c_int) c_int;

// ---------------------------------------------------------------------------
// Error raising (KEP-0005 taxonomy)
// ---------------------------------------------------------------------------

/// A spawn failure raises a file-error-family condition carrying the errno,
/// so `(file-error? e)` fires and `posix-error-name` is meaningful — program
/// not found vs. permission denied, etc. Mirrors
/// `primitives_filesystem.raiseFileErrorCode`.
fn raiseSpawnErrorCode(gc: *GC, msg_text: []const u8, irritant: Value, errno_val: c_int) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.InvalidBytecode; // no VM: internal invariant
    var msg = gc.allocString(msg_text) catch return PrimitiveError.OutOfMemory;
    gc.pushRoot(&msg);
    defer gc.popRoot();
    const irritants = gc.allocPair(irritant, types.NIL) catch return PrimitiveError.OutOfMemory;
    var irritants_root = irritants;
    gc.pushRoot(&irritants_root);
    defer gc.popRoot();
    const err_obj = gc.allocErrorObject(msg, irritants_root) catch return PrimitiveError.OutOfMemory;
    const err = types.toObject(err_obj).as(types.ErrorObject);
    err.error_type = .file;
    err.posix_errno = errno_val;
    vm.current_exception = err_obj;
    return PrimitiveError.ExceptionRaised;
}

fn raiseSpawnError(gc: *GC, msg_text: []const u8, irritant: Value) PrimitiveError!Value {
    return raiseSpawnErrorCode(gc, msg_text, irritant, std.c._errno().*);
}

/// Check the return of a posix_spawn setup call (init/add*/setflags/setpgroup).
/// These APIs return the error number directly rather than setting the global
/// errno, so a nonzero return is raised with that exact code — unlike
/// `platform.pipe`, which does set errno and stays on `raiseSpawnError`.
fn spawnStep(rc: c_int, gc: *GC, msg_text: []const u8, irritant: Value) PrimitiveError!void {
    if (rc != 0) _ = try raiseSpawnErrorCode(gc, msg_text, irritant, rc);
}

/// A general (non-file) error, used for the cross-thread ownership guard.
fn raiseProcessError(gc: *GC, msg_text: []const u8) PrimitiveError {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.InvalidBytecode; // no VM: internal invariant
    var msg = gc.allocString(msg_text) catch return PrimitiveError.OutOfMemory;
    gc.pushRoot(&msg);
    defer gc.popRoot();
    const err_obj = gc.allocErrorObject(msg, types.NIL) catch return PrimitiveError.OutOfMemory;
    vm.current_exception = err_obj;
    return PrimitiveError.ExceptionRaised;
}

/// Validate a process argument and enforce thread affinity (channel
/// precedent): a Process created on one scheduler thread cannot be operated
/// on from another.
fn checkProcessOwner(val: Value, proc: []const u8) PrimitiveError!*types.Process {
    if (!types.isProcess(val)) return primitives.typeError(proc, "process", val);
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const obj = types.toObject(val);
    if (obj.owner != gc.id)
        return raiseProcessError(gc, "process belongs to another thread; it can only be used from the thread that spawned it");
    return obj.as(types.Process);
}

// ---------------------------------------------------------------------------
// Status encoding and reaping
// ---------------------------------------------------------------------------

/// Decode a raw `waitpid(2)` status into the Scheme representation: a fixnum
/// exit code for a normal exit, `(signaled . signo)` for death by signal.
fn decodeStatus(s: u32) PrimitiveError!Value {
    if (std.c.W.IFEXITED(s)) return types.makeFixnum(std.c.W.EXITSTATUS(s));
    if (std.c.W.IFSIGNALED(s)) {
        const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
        // WTERMSIG is the low 7 bits on every POSIX target.
        const signo: i64 = @intCast(s & 0x7f);
        const sym = gc.allocSymbol("signaled") catch return PrimitiveError.OutOfMemory;
        return gc.allocPair(sym, types.makeFixnum(signo)) catch return PrimitiveError.OutOfMemory;
    }
    // Stopped/continued are only reported with WUNTRACED/WCONTINUED, which we
    // never pass — treat as "still running" for the surface's purposes.
    return types.FALSE;
}

fn waitpidRetry(pid: i32, status: *c_int, options: c_int) i32 {
    while (true) {
        const r = std.c.waitpid(pid, status, options);
        if (r < 0 and std.c._errno().* == @intFromEnum(std.c.E.INTR)) continue;
        return r;
    }
}

/// Non-blocking reap: store the status if the child has already exited.
fn reapIfExited(p: *types.Process) void {
    if (p.status != null) return;
    var status: c_int = 0;
    const r = waitpidRetry(p.pid, &status, WNOHANG);
    if (r == p.pid) p.status = @as(u32, @bitCast(status));
}

// ---------------------------------------------------------------------------
// Redirection specs and argv/envp construction
// ---------------------------------------------------------------------------

const Which = enum { stdin, stdout, stderr };

const Spec = union(enum) {
    inherit,
    pipe,
    null_dev,
    caller_fd: platform.fd_t,
    merge, // stderr only: 'stdout
};

fn parseSpec(v: Value, which: Which, proc: []const u8) PrimitiveError!Spec {
    if (types.isSymbol(v)) {
        const name = types.symbolName(v);
        if (std.mem.eql(u8, name, "inherit")) return .inherit;
        if (std.mem.eql(u8, name, "pipe")) return .pipe;
        if (std.mem.eql(u8, name, "null")) return .null_dev;
        if (which == .stderr and std.mem.eql(u8, name, "stdout")) return .merge;
        return primitives.argError(proc, "unknown redirection spec '{s}'", .{name});
    }
    if (types.isPort(v)) {
        const port = types.toObject(v).as(types.Port);
        if (port.is_string_port or !port.is_open or port.fd < 0)
            return primitives.argError(proc, "a redirection port must be an open fd-backed port", .{});
        // The child reads its stdin and writes its stdout/stderr, so the port
        // must have the matching direction — otherwise the child's I/O fails
        // with EBADF inside the child rather than as a Scheme error here.
        switch (which) {
            .stdin => if (!port.is_input)
                return primitives.argError(proc, "stdin: port must be an input port", .{}),
            .stdout, .stderr => if (!port.is_output)
                return primitives.argError(proc, "stdout:/stderr: port must be an output port", .{}),
        }
        // The child inherits the fd's open-file-description flags. A port
        // Kaappi flipped to non-blocking for reactor integration would hand
        // the child an O_NONBLOCK stdio stream, on which an ordinary read or
        // write fails spuriously with EAGAIN — reject it rather than surprise
        // the child (clearing the flag is not an option: the description, and
        // thus the flag, is shared with the parent's still-live port).
        if (port.nonblocking)
            return primitives.argError(proc, "a non-blocking port cannot back a child's stdio (its O_NONBLOCK flag is shared with the child)", .{});
        // Flush any buffered output before the child writes to the same fd, or
        // the parent's still-buffered bytes would land *after* the child's.
        // A no-op for input ports and for fd<=2 (which are unbuffered).
        if (port.is_output) try primitives_io.flushPortObj(port);
        return .{ .caller_fd = port.fd };
    }
    return primitives.typeError(proc, "redirection spec (a symbol or an fd-backed port)", v);
}

/// Build a null-terminated C `argv` from a Scheme list of strings, owned by
/// `arena`. The argv the OS receives must be Zig-owned memory, never an alias
/// into the GC heap (which a collection could move data out from under).
fn buildCArgv(arena: std.mem.Allocator, list: Value, proc: []const u8) PrimitiveError![]?[*:0]const u8 {
    const n = types.listLength(list) orelse return primitives.typeError(proc, "proper list of strings", list);
    if (n == 0) return primitives.argError(proc, "argv must have at least one element (the program to run)", .{});
    const arr = arena.alloc(?[*:0]const u8, n + 1) catch return PrimitiveError.OutOfMemory;
    var cur = list;
    var i: usize = 0;
    while (cur != types.NIL) : (i += 1) {
        const elem = types.car(cur);
        if (!types.isString(elem)) return primitives.typeError(proc, "string", elem);
        const s = types.toObject(elem).as(types.SchemeString);
        const z = arena.dupeZ(u8, s.data[0..s.len]) catch return PrimitiveError.OutOfMemory;
        arr[i] = z.ptr;
        cur = types.cdr(cur);
    }
    arr[n] = null;
    return arr;
}

/// Build a null-terminated C `envp` ("name=value") from an alist of
/// `(name . value)` string pairs, owned by `arena`.
fn buildCEnvp(arena: std.mem.Allocator, alist: Value, proc: []const u8) PrimitiveError![]?[*:0]const u8 {
    const n = types.listLength(alist) orelse return primitives.typeError(proc, "alist of (name . value) string pairs for env:", alist);
    const arr = arena.alloc(?[*:0]const u8, n + 1) catch return PrimitiveError.OutOfMemory;
    var cur = alist;
    var i: usize = 0;
    while (cur != types.NIL) : (i += 1) {
        const entry = types.car(cur);
        if (!types.isPair(entry)) return primitives.typeError(proc, "(name . value) pair in env:", entry);
        const name_v = types.car(entry);
        const val_v = types.cdr(entry);
        if (!types.isString(name_v) or !types.isString(val_v))
            return primitives.typeError(proc, "string name and value in env:", entry);
        const name_s = types.toObject(name_v).as(types.SchemeString);
        const val_s = types.toObject(val_v).as(types.SchemeString);
        const joined = std.fmt.allocPrintSentinel(arena, "{s}={s}", .{ name_s.data[0..name_s.len], val_s.data[0..val_s.len] }, 0) catch return PrimitiveError.OutOfMemory;
        arr[i] = joined.ptr;
        cur = types.cdr(cur);
    }
    arr[n] = null;
    return arr;
}

// ---------------------------------------------------------------------------
// spawn-process
// ---------------------------------------------------------------------------

/// `(spawn-process argv opt...)` — spawn a child via `posix_spawnp` and return
/// a `Process`. `argv` is a non-empty list of strings; options are keyword/
/// value pairs: `stdin:`/`stdout:`/`stderr:` (`inherit`/`pipe`/`null`/an
/// fd-backed port, or `stdout` to merge stderr), `directory:`, `env:` (an
/// alist replacing the environment wholesale), and `new-group:`. Pipe ends
/// become reactor-integrated ports on the returned handle; every other spec
/// leaves the corresponding accessor `#f`.
fn spawnProcess(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;

    // --- parse keyword options (argv is args[0], then keyword/value pairs) ---
    var stdin_spec: Spec = .inherit;
    var stdout_spec: Spec = .inherit;
    var stderr_spec: Spec = .inherit;
    var dir_opt: ?Value = null;
    var env_opt: ?Value = null;
    var new_group = false;

    var oi: usize = 1;
    while (oi < args.len) : (oi += 2) {
        if (!types.isSymbol(args[oi]))
            return primitives.argError("spawn-process", "expected a keyword symbol (like 'stdout:) in option position", .{});
        if (oi + 1 >= args.len)
            return primitives.argError("spawn-process", "option '{s}' is missing its value", .{types.symbolName(args[oi])});
        const kw = types.symbolName(args[oi]);
        const val = args[oi + 1];
        if (std.mem.eql(u8, kw, "stdin:")) {
            stdin_spec = try parseSpec(val, .stdin, "spawn-process");
        } else if (std.mem.eql(u8, kw, "stdout:")) {
            stdout_spec = try parseSpec(val, .stdout, "spawn-process");
        } else if (std.mem.eql(u8, kw, "stderr:")) {
            stderr_spec = try parseSpec(val, .stderr, "spawn-process");
        } else if (std.mem.eql(u8, kw, "directory:")) {
            if (!types.isString(val)) return primitives.typeError("spawn-process", "string for directory:", val);
            dir_opt = val;
        } else if (std.mem.eql(u8, kw, "env:")) {
            env_opt = val;
        } else if (std.mem.eql(u8, kw, "new-group:")) {
            new_group = val != types.FALSE;
        } else if (std.mem.eql(u8, kw, "pass-fds:")) {
            if (val != types.NIL)
                return primitives.argError("spawn-process", "pass-fds: is not supported yet (a later phase)", .{});
        } else {
            return primitives.argError("spawn-process", "unknown option '{s}'", .{kw});
        }
    }

    // --- build argv / envp in an arena (freed on return) ---
    var arena_state = std.heap.ArenaAllocator.init(gc.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const argv = try buildCArgv(arena, args[0], "spawn-process");
    const file = argv[0].?; // buildCArgv guarantees at least one element

    const envp: [*]const ?[*:0]const u8 = if (env_opt) |e|
        (try buildCEnvp(arena, e, "spawn-process")).ptr
    else
        @ptrCast(std.c.environ);

    // --- file actions + attributes ---
    var fa: FileActions = .{};
    try spawnStep(posix_spawn_file_actions_init(&fa), gc, "posix_spawn_file_actions_init failed", args[0]);
    defer _ = posix_spawn_file_actions_destroy(&fa);

    var attr: SpawnAttr = .{};
    try spawnStep(posix_spawnattr_init(&attr), gc, "posix_spawnattr_init failed", args[0]);
    defer _ = posix_spawnattr_destroy(&attr);

    // Pipe fds we created; closed by errdefer on any failure before the
    // child is running. After a successful spawn we hand the parent ends to
    // ports and close the child ends explicitly, so the errdefer is disarmed.
    var made: [6]platform.fd_t = .{ -1, -1, -1, -1, -1, -1 };
    var n_made: usize = 0;
    var spawned = false;
    errdefer if (!spawned) {
        for (made[0..n_made]) |fd| {
            if (fd >= 0) _ = platform.close(fd);
        }
    };

    var parent_stdin_fd: platform.fd_t = -1;
    var parent_stdout_fd: platform.fd_t = -1;
    var parent_stderr_fd: platform.fd_t = -1;
    var child_stdin_fd: platform.fd_t = -1;
    var child_stdout_fd: platform.fd_t = -1;
    var child_stderr_fd: platform.fd_t = -1;

    // directory: — change cwd first so a relative program/paths resolve
    // against it. addchdir_np needs no pre-exec hook (glibc ≥2.29, musl
    // ≥1.2.3, macOS, BSD).
    if (dir_opt != null) {
        if (comptime have_addchdir_np) {
            const d = dir_opt.?;
            const ds = types.toObject(d).as(types.SchemeString);
            const dz = arena.dupeZ(u8, ds.data[0..ds.len]) catch return PrimitiveError.OutOfMemory;
            try spawnStep(posix_spawn_file_actions_addchdir_np(&fa, dz.ptr), gc, "cannot set directory: for spawn", d);
        } else {
            // NetBSD/OpenBSD: no addchdir file action. Reject rather than
            // silently ignoring the requested directory.
            return primitives.argError("spawn-process", "directory: is not supported on this platform (posix_spawn lacks a chdir file action)", .{});
        }
    }

    // stdin
    switch (stdin_spec) {
        .inherit => {},
        .pipe => {
            var fds: [2]platform.fd_t = undefined;
            if (platform.pipe(&fds) != 0) return raiseSpawnError(gc, "pipe failed", args[0]);
            made[n_made] = fds[0];
            n_made += 1;
            made[n_made] = fds[1];
            n_made += 1;
            child_stdin_fd = fds[0]; // child reads
            parent_stdin_fd = fds[1]; // parent writes
            try spawnStep(posix_spawn_file_actions_adddup2(&fa, fds[0], 0), gc, "file action for stdin failed", args[0]);
        },
        .null_dev => try spawnStep(posix_spawn_file_actions_addopen(&fa, 0, "/dev/null", O_RDONLY, 0), gc, "cannot open /dev/null for stdin", args[0]),
        .caller_fd => |fd| try spawnStep(posix_spawn_file_actions_adddup2(&fa, fd, 0), gc, "file action for stdin failed", args[0]),
        .merge => unreachable, // parseSpec only yields .merge for stderr
    }

    // stdout
    switch (stdout_spec) {
        .inherit => {},
        .pipe => {
            var fds: [2]platform.fd_t = undefined;
            if (platform.pipe(&fds) != 0) return raiseSpawnError(gc, "pipe failed", args[0]);
            made[n_made] = fds[0];
            n_made += 1;
            made[n_made] = fds[1];
            n_made += 1;
            parent_stdout_fd = fds[0]; // parent reads
            child_stdout_fd = fds[1]; // child writes
            try spawnStep(posix_spawn_file_actions_adddup2(&fa, fds[1], 1), gc, "file action for stdout failed", args[0]);
        },
        .null_dev => try spawnStep(posix_spawn_file_actions_addopen(&fa, 1, "/dev/null", O_WRONLY, 0), gc, "cannot open /dev/null for stdout", args[0]),
        .caller_fd => |fd| try spawnStep(posix_spawn_file_actions_adddup2(&fa, fd, 1), gc, "file action for stdout failed", args[0]),
        .merge => unreachable,
    }

    // stderr (handled last so 'stdout merge sees the final fd 1)
    switch (stderr_spec) {
        .inherit => {},
        .pipe => {
            var fds: [2]platform.fd_t = undefined;
            if (platform.pipe(&fds) != 0) return raiseSpawnError(gc, "pipe failed", args[0]);
            made[n_made] = fds[0];
            n_made += 1;
            made[n_made] = fds[1];
            n_made += 1;
            parent_stderr_fd = fds[0]; // parent reads
            child_stderr_fd = fds[1]; // child writes
            try spawnStep(posix_spawn_file_actions_adddup2(&fa, fds[1], 2), gc, "file action for stderr failed", args[0]);
        },
        .null_dev => try spawnStep(posix_spawn_file_actions_addopen(&fa, 2, "/dev/null", O_WRONLY, 0), gc, "cannot open /dev/null for stderr", args[0]),
        .caller_fd => |fd| try spawnStep(posix_spawn_file_actions_adddup2(&fa, fd, 2), gc, "file action for stderr failed", args[0]),
        .merge => try spawnStep(posix_spawn_file_actions_adddup2(&fa, 1, 2), gc, "file action for stderr merge failed", args[0]),
    }

    // Process group: SETPGROUP + setpgroup(0) makes the child its own group
    // leader. fd hygiene is handled entirely by the CLOEXEC audit (every fd
    // Kaappi opens is close-on-exec) — we deliberately do NOT set
    // POSIX_SPAWN_CLOEXEC_DEFAULT on macOS: it would also close inherited
    // stdio (0/1/2, which carry no file action), breaking 'inherit
    // (kaappi#2414 review).
    if (new_group) {
        try spawnStep(posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETPGROUP), gc, "posix_spawnattr_setflags failed", args[0]);
        try spawnStep(posix_spawnattr_setpgroup(&attr, 0), gc, "posix_spawnattr_setpgroup failed", args[0]);
    }

    // --- spawn ---
    var pid: c_int = -1;
    const rc = posix_spawnp(&pid, file, &fa, &attr, argv.ptr, envp);
    if (rc != 0)
        // posix_spawn returns the error number directly (it does not set errno).
        return raiseSpawnErrorCode(gc, "cannot spawn process", args[0], rc);
    spawned = true;

    // The child is running now. If building its ports or the Process handle
    // fails below (only OutOfMemory can), don't orphan it — kill and reap it
    // before propagating the error. errdefer fires only on an error return,
    // so a successful spawn hands the live child off to its Process handle
    // untouched. (kaappi#2414 review.)
    errdefer {
        _ = deliverKill(pid, 9);
        var reap_status: c_int = 0;
        _ = waitpidRetry(pid, &reap_status, 0);
    }

    const pgid: i32 = if (new_group) @intCast(pid) else 0;

    // The child owns its ends now; close the parent's copies.
    if (child_stdin_fd >= 0) _ = platform.close(child_stdin_fd);
    if (child_stdout_fd >= 0) _ = platform.close(child_stdout_fd);
    if (child_stderr_fd >= 0) _ = platform.close(child_stderr_fd);

    // Wrap the parent ends as ports (stdin write-only, stdout/stderr
    // read-only). Root the slots across the allocations that follow. The
    // accessor for any non-'pipe spec must be #f (not '(), which is truthy).
    var stdin_port: Value = types.FALSE;
    var stdout_port: Value = types.FALSE;
    var stderr_port: Value = types.FALSE;
    gc.pushRoot(&stdin_port);
    gc.pushRoot(&stdout_port);
    gc.pushRoot(&stderr_port);
    defer {
        gc.popRoot();
        gc.popRoot();
        gc.popRoot();
    }

    if (parent_stdin_fd >= 0) {
        stdin_port = primitives_io.rawFdToPort(parent_stdin_fd, false, true, "process-stdin") catch {
            _ = platform.close(parent_stdin_fd);
            return PrimitiveError.OutOfMemory;
        };
    }
    if (parent_stdout_fd >= 0) {
        stdout_port = primitives_io.rawFdToPort(parent_stdout_fd, true, false, "process-stdout") catch {
            _ = platform.close(parent_stdout_fd);
            return PrimitiveError.OutOfMemory;
        };
    }
    if (parent_stderr_fd >= 0) {
        stderr_port = primitives_io.rawFdToPort(parent_stderr_fd, true, false, "process-stderr") catch {
            _ = platform.close(parent_stderr_fd);
            return PrimitiveError.OutOfMemory;
        };
    }

    return gc.allocProcess(@intCast(pid), pgid, stdin_port, stdout_port, stderr_port) catch return PrimitiveError.OutOfMemory;
}

// ---------------------------------------------------------------------------
// Accessors and control
// ---------------------------------------------------------------------------

fn processP(args: []const Value) PrimitiveError!Value {
    return if (types.isProcess(args[0])) types.TRUE else types.FALSE;
}

fn processPid(args: []const Value) PrimitiveError!Value {
    const p = try checkProcessOwner(args[0], "process-pid");
    return types.makeFixnum(p.pid);
}

fn processGroup(args: []const Value) PrimitiveError!Value {
    const p = try checkProcessOwner(args[0], "process-group");
    return types.makeFixnum(p.pgid);
}

fn processStdin(args: []const Value) PrimitiveError!Value {
    const p = try checkProcessOwner(args[0], "process-stdin");
    return p.stdin_port;
}

fn processStdout(args: []const Value) PrimitiveError!Value {
    const p = try checkProcessOwner(args[0], "process-stdout");
    return p.stdout_port;
}

fn processStderr(args: []const Value) PrimitiveError!Value {
    const p = try checkProcessOwner(args[0], "process-stderr");
    return p.stderr_port;
}

fn processStatus(args: []const Value) PrimitiveError!Value {
    const p = try checkProcessOwner(args[0], "process-status");
    reapIfExited(p);
    if (p.status) |s| return decodeStatus(s);
    return types.FALSE;
}

fn processWait(args: []const Value) PrimitiveError!Value {
    const p = try checkProcessOwner(args[0], "process-wait");
    if (args.len > 1) {
        const kw = if (types.isSymbol(args[1])) types.symbolName(args[1]) else "";
        if (std.mem.eql(u8, kw, "timeout:"))
            return primitives.argError("process-wait", "timeout: needs the reactor-driven wait (a later phase); this build only supports a blocking wait", .{});
        return primitives.argError("process-wait", "unknown option '{s}'", .{kw});
    }
    if (p.status == null) {
        var status: c_int = 0;
        const r = waitpidRetry(p.pid, &status, 0);
        // On success store the status; on ECHILD (already reaped elsewhere)
        // leave it null and fall through to #f.
        if (r == p.pid) p.status = @as(u32, @bitCast(status));
    }
    if (p.status) |s| return decodeStatus(s);
    return types.FALSE;
}

// NetBSD only: its libc `kill` wrapper does not deliver a signal to a positive
// pid for a posix_spawn child in this build — it returns 0 while the child is
// never signalled, even for the uncatchable SIGKILL (kaappi#2414, confirmed by
// a CI probe that saw rc=0 yet the child ran to completion). `killpg` and the
// raw kill(2) syscall both reach the child through the same in-kernel sys_kill,
// so route a single-process kill through the syscall on NetBSD; every other
// target keeps the libc wrapper.
extern "c" fn syscall(number: c_int, ...) c_int; // NetBSD raw syscall(2)
const SYS_kill_netbsd: c_int = 37; // NetBSD sys/syscall.h

fn deliverKill(pid: c_int, sig: c_int) c_int {
    if (comptime builtin.os.tag == .netbsd) return syscall(SYS_kill_netbsd, pid, sig);
    return kill(pid, sig);
}

/// `(process-kill p [signal: n] [group: bool])` — send a signal (SIGTERM by
/// default) to the child, or to its whole process group with `group: #t`
/// (requires `new-group:` at spawn). A no-op once the child has been reaped:
/// the pid must never be re-signalled, as the OS may have reused it.
fn processKill(args: []const Value) PrimitiveError!Value {
    const p = try checkProcessOwner(args[0], "process-kill");
    var sig: i64 = SIGTERM;
    var group = false;
    var ki: usize = 1;
    while (ki < args.len) : (ki += 2) {
        if (!types.isSymbol(args[ki]))
            return primitives.argError("process-kill", "expected a keyword symbol (like 'signal:) in option position", .{});
        if (ki + 1 >= args.len)
            return primitives.argError("process-kill", "option '{s}' is missing its value", .{types.symbolName(args[ki])});
        const kw = types.symbolName(args[ki]);
        const val = args[ki + 1];
        if (std.mem.eql(u8, kw, "signal:")) {
            sig = try primitives.expectFixnum("process-kill", val);
            // Bound the value before the cast to c_int below: an out-of-range
            // fixnum would otherwise trip @intCast's ReleaseSafe overflow
            // check and abort the VM uncatchably. 0 is the POSIX
            // liveness-probe signal; real signals are small positive ints.
            if (sig < 0 or sig > 255)
                return primitives.argError("process-kill", "signal {d} is out of range (expected 0-255)", .{sig});
        } else if (std.mem.eql(u8, kw, "group:")) {
            group = val != types.FALSE;
        } else {
            return primitives.argError("process-kill", "unknown option '{s}'", .{kw});
        }
    }
    // Never re-signal a reaped pid — it may have been reused (Python's
    // Popen.kill contract). A child that exited but was not yet reaped is
    // still a valid, harmless target (the signal hits the zombie).
    if (p.status != null) return types.VOID;
    const target_sig: c_int = @intCast(sig);
    // Report a delivery failure rather than swallowing it (Python's os.kill
    // raises too): a caller that asked to signal a live process needs to know
    // the signal did not land. The already-reaped case is a documented no-op,
    // handled by the p.status guard above, so a failure here is genuine.
    if (group) {
        if (p.pgid == 0)
            return primitives.argError("process-kill", "group: #t requires spawning with new-group: #t", .{});
        if (killpg(@intCast(p.pgid), target_sig) != 0) {
            const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
            return raiseSpawnError(gc, "cannot signal process group", args[0]);
        }
    } else {
        if (deliverKill(@intCast(p.pid), target_sig) != 0) {
            const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
            return raiseSpawnError(gc, "cannot signal process", args[0]);
        }
    }
    return types.VOID;
}

/// The current environment as an alist of `(name . value)` string pairs — the
/// copy-and-extend source for the `env:` option.
fn processEnvironment(args: []const Value) PrimitiveError!Value {
    _ = args;
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    var result: Value = types.NIL;
    gc.pushRoot(&result);
    defer gc.popRoot();
    var key_val: Value = types.NIL;
    gc.pushRoot(&key_val);
    defer gc.popRoot();

    var env_it = platform.EnvIter.init();
    defer env_it.deinit();
    while (env_it.next()) |s| {
        if (std.mem.indexOfScalar(u8, s, '=')) |eq| {
            key_val = gc.allocString(s[0..eq]) catch return PrimitiveError.OutOfMemory;
            const val_str = gc.allocString(s[eq + 1 ..]) catch return PrimitiveError.OutOfMemory;
            const pair = gc.allocPair(key_val, val_str) catch return PrimitiveError.OutOfMemory;
            result = gc.allocPair(pair, result) catch return PrimitiveError.OutOfMemory;
        }
    }
    return result;
}

// ---------------------------------------------------------------------------

pub const specs = [_]primitives.PrimSpec{
    .{ .name = "spawn-process", .func = &spawnProcess, .arity = .{ .variadic = 1 }, .libs = LS.initOne(.kaappi_process), .sandbox = false, .wasm = false },
    .{ .name = "process?", .func = &processP, .arity = .{ .exact = 1 }, .libs = LS.initOne(.kaappi_process), .sandbox = false, .wasm = false },
    .{ .name = "process-pid", .func = &processPid, .arity = .{ .exact = 1 }, .libs = LS.initOne(.kaappi_process), .sandbox = false, .wasm = false },
    .{ .name = "process-group", .func = &processGroup, .arity = .{ .exact = 1 }, .libs = LS.initOne(.kaappi_process), .sandbox = false, .wasm = false },
    .{ .name = "process-stdin", .func = &processStdin, .arity = .{ .exact = 1 }, .libs = LS.initOne(.kaappi_process), .sandbox = false, .wasm = false },
    .{ .name = "process-stdout", .func = &processStdout, .arity = .{ .exact = 1 }, .libs = LS.initOne(.kaappi_process), .sandbox = false, .wasm = false },
    .{ .name = "process-stderr", .func = &processStderr, .arity = .{ .exact = 1 }, .libs = LS.initOne(.kaappi_process), .sandbox = false, .wasm = false },
    .{ .name = "process-status", .func = &processStatus, .arity = .{ .exact = 1 }, .libs = LS.initOne(.kaappi_process), .sandbox = false, .wasm = false },
    .{ .name = "process-wait", .func = &processWait, .arity = .{ .variadic = 1 }, .libs = LS.initOne(.kaappi_process), .sandbox = false, .wasm = false },
    .{ .name = "process-kill", .func = &processKill, .arity = .{ .variadic = 1 }, .libs = LS.initOne(.kaappi_process), .sandbox = false, .wasm = false },
    .{ .name = "process-environment", .func = &processEnvironment, .arity = .{ .exact = 0 }, .libs = LS.initOne(.kaappi_process), .sandbox = false, .wasm = false },
};
