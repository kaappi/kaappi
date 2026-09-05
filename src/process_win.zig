//! The Windows backend for `(kaappi process)` — KEP-0022 Phase 3.
//!
//! Windows has neither fork/exec nor signals, so nothing here mirrors
//! `process_posix.zig` mechanism-for-mechanism. Three substitutions carry the
//! whole port:
//!
//! 1. **Spawn is `CreateProcessW` with an explicit inherit list.** The argv
//!    vector is joined into one command line by the documented
//!    `CommandLineToArgvW` quoting rules — `platform.buildCommandLineW`, the
//!    same encoder thottam already uses for git — and inheritance is confined
//!    to a `PROC_THREAD_ATTRIBUTE_HANDLE_LIST` naming exactly the three stdio
//!    handles. That is a *stronger* close-by-default guarantee than the POSIX
//!    side's enumerate-then-close scan: no descriptor Kaappi inherited from
//!    its launcher or acquired through FFI can reach the child, and there is
//!    no enumerate/spawn race to document.
//!
//! 2. **A process group is a Job Object.** `TerminateProcess` kills exactly
//!    one process, and `CREATE_NEW_PROCESS_GROUP` only re-routes console
//!    Ctrl+C — neither reaches a grandchild. A Job Object does, because a
//!    child of a job member joins the job automatically, so `new-group:`
//!    creates one and assigns the child to it *before its primary thread is
//!    resumed* (hence `CREATE_SUSPENDED`): a child that ran even briefly
//!    outside the job could spawn a grandchild the tree-kill would miss.
//!
//! 3. **Reaping is the process HANDLE.** It is the wait object the reactor
//!    polls, the source `GetExitCodeProcess` reads, and the target
//!    `TerminateProcess` kills — so the Process owns it for its whole
//!    lifetime and only `gc_sweep.freeObject` closes it. There are no
//!    zombies on Windows: an exited process lingers exactly as long as a
//!    handle to it does.
//!
//! **Signal mapping.** There is no signal delivery to map, so `signal:`
//! folds into the exit code `TerminateProcess` stamps on the victim:
//! `128 + signal`, the shell convention, so the default `'signal: 15`
//! surfaces as 143 and `'signal: 9` as 137. `'signal: 0` keeps its POSIX
//! meaning — an existence probe — and terminates nothing. The residual
//! ambiguity (a child that deliberately exits 143) is inherent: Windows has
//! one exit code and no second channel.

const std = @import("std");
const builtin = @import("builtin");
const types = @import("types.zig");
const types_process = @import("types_process.zig");
const memory = @import("memory.zig");
const platform = @import("platform.zig");
const vm_mod = @import("vm.zig");
const primitives = @import("primitives.zig");

const win = platform.win;
const Value = types.Value;
const PrimitiveError = primitives.PrimitiveError;
const GC = memory.GC;
const Redir = types_process.Redir;
const SpawnConfig = types_process.SpawnConfig;
const Spawned = types_process.Spawned;

// ---------------------------------------------------------------------------
// Backend interface (mirrored by process_posix.zig)
// ---------------------------------------------------------------------------

// `directory:` needs no capability flag on this backend: it is
// `CreateProcessW`'s own `lpCurrentDirectory` parameter, with no libc
// version gate. (The POSIX backend honors it everywhere too since
// kaappi#2517 — addchdir_np where its comptime link gate allows, a
// child-side chdir on the fork route otherwise.)

/// The exit code a `'signal: n` kill stamps on the victim. `128 + n` is the
/// shell convention for "died from signal n", which is what a portable
/// program comparing statuses across platforms is most likely to expect;
/// see the module header for the ambiguity it inherits.
pub fn terminateExitCode(sig: c_int) u32 {
    return @intCast(128 + sig);
}

/// The status stored for a child `killAndReapFresh`/`killAndReapChild`
/// destroyed, so a later sweep never re-reads a dead handle.
pub const kill_fresh_status: u32 = 128 + 9;

/// The errno the last failing call left behind. Win32 reports through
/// `GetLastError`, whose codes share no numbering with errno, so they are
/// folded onto the errno names SRFI-170's `posix-error-name` can report —
/// the same discrimination a POSIX caller gets ("program not found" vs
/// "permission denied"), spelled in the vocabulary the condition object
/// already speaks. Anything unrecognized becomes EIO rather than 0, so
/// `posix-error?` stays true for a genuine syscall failure.
pub fn lastError() c_int {
    const E = std.c.E;
    return switch (win.GetLastError()) {
        win.ERROR_FILE_NOT_FOUND, win.ERROR_PATH_NOT_FOUND => @intFromEnum(E.NOENT),
        win.ERROR_TOO_MANY_OPEN_FILES => @intFromEnum(E.MFILE),
        win.ERROR_ACCESS_DENIED => @intFromEnum(E.ACCES),
        win.ERROR_INVALID_HANDLE => @intFromEnum(E.BADF),
        win.ERROR_NOT_ENOUGH_MEMORY, win.ERROR_OUTOFMEMORY => @intFromEnum(E.NOMEM),
        win.ERROR_BAD_FORMAT, win.ERROR_BAD_EXE_FORMAT => @intFromEnum(E.NOEXEC),
        win.ERROR_NOT_SUPPORTED => @intFromEnum(E.NOSYS),
        win.ERROR_INVALID_PARAMETER => @intFromEnum(E.INVAL),
        win.ERROR_BROKEN_PIPE => @intFromEnum(E.PIPE),
        win.ERROR_DIRECTORY => @intFromEnum(E.ISDIR),
        else => @intFromEnum(E.IO),
    };
}

// ---------------------------------------------------------------------------
// spawn
// ---------------------------------------------------------------------------

/// One stdio slot's child-side handle, plus whether this function owns it.
/// Every handle handed to the child is a *fresh inheritable duplicate* we
/// own and close right after `CreateProcessW`: a handle only inherits when it
/// is marked inheritable, and duplicating uniformly means no caller's port
/// handle, and no std handle, has its inheritance flag mutated behind its
/// back.
const SlotHandle = struct {
    handle: ?win.HANDLE = null,
    /// False only for the 'stdout merge, whose handle is slot 1's and must
    /// not be closed twice.
    owned: bool = true,
};

pub fn spawnChild(gc: *GC, cfg: SpawnConfig, redirs_in: [3]Redir) PrimitiveError!Spawned {
    var arena = std.heap.ArenaAllocator.init(gc.allocator);
    defer arena.deinit();
    const arena_al = arena.allocator();

    // -- command line, environment, working directory.
    const cmdline = try buildCmdline(gc, arena_al, cfg.argv);
    const env_block: ?[*]const u16 = if (cfg.env) |e| try buildEnvBlockW(arena_al, e) else null;
    var cwd_w: ?[*:0]const u16 = null;
    if (cfg.directory) |dir_val| {
        const dir = types.toObject(dir_val).as(types.SchemeString);
        cwd_w = (try widenChecked(arena_al, dir.data[0..dir.len], "directory: path")).ptr;
    }

    // -- pipes and the child's stdio handles. Two cleanup sets: the parent
    // ends we will hand back (blanked as ownership transfers), and the
    // inheritable child-side duplicates, which are always released here.
    var parent_handles = [3]?win.HANDLE{ null, null, null };
    var slots = [3]SlotHandle{ .{}, .{}, .{} };
    defer {
        for (&parent_handles) |*h| {
            if (h.*) |v| _ = win.CloseHandle(v);
            h.* = null;
        }
        for (&slots) |*s| {
            if (s.owned) {
                if (s.handle) |v| _ = win.CloseHandle(v);
            }
            s.handle = null;
        }
    }

    for (redirs_in, 0..) |redir, slot| {
        const writing = slot != 0;
        switch (redir) {
            .inherit => slots[slot] = .{ .handle = try inheritableStdHandle(gc, slot) },
            .pipe => {
                var read_h: win.HANDLE = undefined;
                var write_h: win.HANDLE = undefined;
                const sa = win.SecurityAttributes{ .length = @sizeOf(win.SecurityAttributes), .inherit_handle = 1 };
                if (win.CreatePipe(&read_h, &write_h, &sa, 0) == 0)
                    return raiseSpawnError(gc, "cannot create process pipe", types.FALSE, lastError());
                // stdin: the child reads, we keep the write end. stdout and
                // stderr: the child writes, we keep the read end.
                const child_h = if (writing) write_h else read_h;
                const parent_h = if (writing) read_h else write_h;
                // The parent end must never reach the child: clearing the
                // inherit flag is belt over the explicit handle list below.
                _ = win.SetHandleInformation(parent_h, win.HANDLE_FLAG_INHERIT, 0);
                parent_handles[slot] = parent_h;
                slots[slot] = .{ .handle = child_h };
            },
            .null_sink => slots[slot] = .{ .handle = try openNulHandle(gc, writing) },
            .fd => |fd| {
                const src = platform.pipeHandleFromFd(fd) orelse
                    return raiseSpawnError(gc, "redirection port has no usable OS handle", types.FALSE, @intFromEnum(std.c.E.BADF));
                slots[slot] = .{ .handle = try duplicateInheritable(gc, src) };
            },
            .merge_stdout => {
                // Rejected for slots 0 and 1 by the shared caller. Reusing
                // slot 1's handle (rather than duplicating it) is what makes
                // the merge a true merge: one file object, one shared file
                // position, exactly like POSIX's dup2(1, 2).
                slots[slot] = .{ .handle = slots[1].handle, .owned = false };
            },
        }
    }

    // -- the inherit list: the deduplicated set of handles the child may
    // have. `UpdateProcThreadAttribute` rejects a list with duplicates, and
    // the 'stdout merge always produces one.
    var handle_list: [3]win.HANDLE = undefined;
    var handle_count: usize = 0;
    for (slots) |s| {
        const h = s.handle orelse continue;
        var seen = false;
        for (handle_list[0..handle_count]) |existing| {
            if (existing == h) seen = true;
        }
        if (!seen) {
            handle_list[handle_count] = h;
            handle_count += 1;
        }
    }

    var attr_size: usize = 0;
    _ = win.InitializeProcThreadAttributeList(null, 1, 0, &attr_size);
    if (attr_size == 0) return raiseSpawnError(gc, "cannot size the process attribute list", types.FALSE, lastError());
    const attr_buf = arena_al.alignedAlloc(u8, .of(usize), attr_size) catch return PrimitiveError.OutOfMemory;
    const attr_list: *anyopaque = @ptrCast(attr_buf.ptr);
    if (win.InitializeProcThreadAttributeList(attr_list, 1, 0, &attr_size) == 0)
        return raiseSpawnError(gc, "cannot build the process attribute list", types.FALSE, lastError());
    defer win.DeleteProcThreadAttributeList(attr_list);
    if (win.UpdateProcThreadAttribute(
        attr_list,
        0,
        win.PROC_THREAD_ATTRIBUTE_HANDLE_LIST,
        @ptrCast(&handle_list),
        handle_count * @sizeOf(win.HANDLE),
        null,
        null,
    ) == 0) return raiseSpawnError(gc, "cannot restrict the child's inherited handles", types.FALSE, lastError());

    var si = win.StartupInfoExW{
        .startup_info = .{ .cb = @sizeOf(win.StartupInfoExW) },
        .attribute_list = attr_list,
    };
    si.startup_info.flags = win.STARTF_USESTDHANDLES;
    si.startup_info.std_input = slots[0].handle;
    si.startup_info.std_output = slots[1].handle;
    si.startup_info.std_error = slots[2].handle;

    // -- the Job Object, created BEFORE the child so a failure here never
    // leaves a suspended process behind. Deliberately without
    // JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE: an abandoned Process must leave its
    // group running, exactly as an abandoned POSIX process group does.
    var job: ?win.HANDLE = null;
    errdefer {
        if (job) |j| _ = win.CloseHandle(j);
    }
    if (cfg.new_group) {
        job = win.CreateJobObjectW(null, null) orelse
            return raiseSpawnError(gc, "cannot create process group (job object)", types.FALSE, lastError());
    }

    var flags: u32 = win.EXTENDED_STARTUPINFO_PRESENT;
    if (env_block != null) flags |= win.CREATE_UNICODE_ENVIRONMENT;
    // Suspended until the job assignment lands (see the module header).
    if (job != null) flags |= win.CREATE_SUSPENDED;

    var pi: win.ProcessInformation = undefined;
    const created = win.CreateProcessW(
        null,
        cmdline,
        null,
        null,
        1, // bInheritHandles: scoped to the handle list above
        flags,
        @ptrCast(@constCast(env_block)),
        cwd_w,
        @ptrCast(&si),
        &pi,
    );
    if (created == 0) {
        // ERROR_FILE_NOT_FOUND for a program that is not on PATH — the same
        // errno-carrying `.file` condition ENOENT raises on POSIX.
        return raiseSpawnError(gc, "cannot spawn process", cfg.argv[0], lastError());
    }

    if (job) |j| {
        if (win.AssignProcessToJobObject(j, pi.process) == 0) {
            const err = lastError();
            // The child exists but is not in its group and has never run;
            // destroying it is the only correct outcome — returning it would
            // silently give `process-kill 'group: #t` nothing to terminate.
            _ = win.TerminateProcess(pi.process, kill_fresh_status);
            _ = win.WaitForSingleObject(pi.process, 5_000);
            _ = win.CloseHandle(pi.thread);
            _ = win.CloseHandle(pi.process);
            return raiseSpawnError(gc, "cannot assign the child to its process group", types.FALSE, err);
        }
        _ = win.ResumeThread(pi.thread);
    }
    _ = win.CloseHandle(pi.thread);

    // -- hand the parent pipe ends over as CRT fds, the currency every port
    // in the runtime speaks (`primitives_io.makeFdPort`, the reactor's
    // polled-pipe readiness). `_open_osfhandle` transfers ownership of the
    // handle to the fd, so the slot is blanked on success and the fd becomes
    // what the caller must release.
    var out = Spawned{
        .pid = @bitCast(pi.process_id),
        .pgid = if (cfg.new_group) @as(i32, @bitCast(pi.process_id)) else 0,
        .win_handle = pi.process,
        .win_job = job,
    };
    for (&parent_handles, 0..) |*h, slot| {
        const handle = h.* orelse continue;
        const reading = slot != 0;
        const oflag: c_int = if (reading) win.O_RDONLY | win.O_BINARY else win.O_BINARY;
        const fd = win._open_osfhandle(@bitCast(@intFromPtr(handle)), oflag);
        if (fd < 0) {
            // This handle is still ours (the CRT took nothing), so the defer
            // releases it — but an *earlier* slot's handle already became a
            // CRT fd this loop owns and no caller will ever see, so close
            // those explicitly. Then destroy the child, since nothing could
            // reach its pipes anyway.
            for (out.parent_ends) |done| {
                if (done >= 0) _ = platform.close(done);
            }
            out.parent_ends = .{ -1, -1, -1 };
            _ = win.TerminateProcess(pi.process, kill_fresh_status);
            _ = win.WaitForSingleObject(pi.process, 5_000);
            _ = win.CloseHandle(pi.process);
            return raiseSpawnError(gc, "cannot wrap the process pipe as a descriptor", types.FALSE, lastError());
        }
        h.* = null; // the fd owns the handle now
        out.parent_ends[slot] = fd;
    }
    // Past the last failure point: the job now belongs to `out`.
    job = null;
    return out;
}

/// A fresh inheritable duplicate of this process's own handle for `slot`.
/// A missing standard handle (a GUI-subsystem parent, or a launcher that
/// closed one) becomes NUL rather than an invalid handle: under
/// STARTF_USESTDHANDLES an invalid entry is what the child *gets*, which
/// turns "the parent had no stdin" into "every read fails weirdly".
fn inheritableStdHandle(gc: *GC, slot: usize) PrimitiveError!win.HANDLE {
    const which = switch (slot) {
        0 => win.STD_INPUT_HANDLE,
        1 => win.STD_OUTPUT_HANDLE,
        else => win.STD_ERROR_HANDLE,
    };
    const h = win.GetStdHandle(which);
    if (h == null or h.? == win.INVALID_HANDLE_VALUE) return openNulHandle(gc, slot != 0);
    return duplicateInheritable(gc, h.?);
}

fn duplicateInheritable(gc: *GC, src: win.HANDLE) PrimitiveError!win.HANDLE {
    var dup: win.HANDLE = undefined;
    const me = win.GetCurrentProcess();
    if (win.DuplicateHandle(me, src, me, &dup, 0, 1, win.DUPLICATE_SAME_ACCESS) == 0) {
        _ = try raiseProcessErrorVoid(gc, "cannot duplicate a redirection handle for the child", lastError());
        unreachable;
    }
    return dup;
}

fn openNulHandle(gc: *GC, writing: bool) PrimitiveError!win.HANDLE {
    const sa = win.SecurityAttributes{ .length = @sizeOf(win.SecurityAttributes), .inherit_handle = 1 };
    const nul = std.unicode.wtf8ToWtf16LeStringLiteral("NUL");
    const access: u32 = if (writing) win.GENERIC_WRITE else win.GENERIC_READ;
    const h = win.CreateFileW(nul, access, win.FILE_SHARE_READ | win.FILE_SHARE_WRITE, &sa, win.OPEN_EXISTING, win.FILE_ATTRIBUTE_NORMAL, null);
    if (h == win.INVALID_HANDLE_VALUE) {
        _ = try raiseProcessErrorVoid(gc, "cannot open the null device for the child", lastError());
        unreachable;
    }
    return h;
}

// ---------------------------------------------------------------------------
// reap / signal / teardown
// ---------------------------------------------------------------------------

/// Block until the child exits, storing its status. Returns 0, or an errno
/// describing the failure.
pub fn blockingReap(proc: *types.Process) c_int {
    const h = proc.win_handle orelse return @intFromEnum(std.c.E.CHILD);
    {
        // Same markable-in-native protocol as the POSIX blocking waitpid: a
        // child-thread VM blocked here never reaches the dispatch-loop
        // safepoint, so a concurrent parent collection would otherwise spin
        // in markLiveChildRoots (#1933 shape).
        const wait_vm: ?*vm_mod.VM = if (vm_mod.vm_instance) |vm|
            (if (!vm.owns_globals) vm else null)
        else
            null;
        if (wait_vm) |vm| vm.setCollectionInNative();
        defer if (wait_vm) |vm| vm.setCollectionRunning();
        if (win.WaitForSingleObject(h, win.INFINITE) != win.WAIT_OBJECT_0)
            return lastError();
    }
    var code: u32 = 0;
    if (win.GetExitCodeProcess(h, &code) == 0) return lastError();
    proc.status = code;
    return 0;
}

/// `process-kill` on one process. `sig` 0 keeps its POSIX meaning — probe
/// for existence, deliver nothing — which on Windows is trivially true for a
/// child whose handle we still hold and whose status is still unreaped (the
/// shared caller has already returned for a reaped one).
pub fn signalOne(proc: *types.Process, sig: c_int) c_int {
    if (sig == 0) return 0;
    const h = proc.win_handle orelse return @intFromEnum(std.c.E.SRCH);
    if (win.TerminateProcess(h, terminateExitCode(sig)) == 0) return lastError();
    return 0;
}

/// `process-kill 'group: #t` — `TerminateJobObject`, which reaches every
/// process in the job including grandchildren, the whole reason `new-group:`
/// creates a job at all.
pub fn signalGroup(proc: *types.Process, sig: c_int) c_int {
    if (sig == 0) return 0;
    const j = proc.win_job orelse return @intFromEnum(std.c.E.SRCH);
    if (win.TerminateJobObject(j, terminateExitCode(sig)) == 0) return lastError();
    return 0;
}

/// Destroy and reap a child the caller could not finish constructing, when
/// no Process owns its handles yet — so this closes them. Returns true when
/// the child was actually reaped.
pub fn killAndReapFresh(spawned: Spawned) bool {
    const h = spawned.win_handle orelse return false;
    const reaped = terminateAndWait(h);
    _ = win.CloseHandle(h);
    if (spawned.win_job) |j| _ = win.CloseHandle(j);
    return reaped;
}

/// The same, for a child whose Process object already exists: the handles
/// stay with the Process (freeObject closes them).
pub fn killAndReapChild(proc: *types.Process) bool {
    const h = proc.win_handle orelse return false;
    return terminateAndWait(h);
}

fn terminateAndWait(h: win.HANDLE) bool {
    if (win.TerminateProcess(h, kill_fresh_status) == 0) {
        // Already dead is the only realistic reason; confirm rather than
        // wait on a process nothing signaled.
        return win.WaitForSingleObject(h, 0) == win.WAIT_OBJECT_0;
    }
    const wait_vm: ?*vm_mod.VM = if (vm_mod.vm_instance) |vm|
        (if (!vm.owns_globals) vm else null)
    else
        null;
    if (wait_vm) |vm| vm.setCollectionInNative();
    defer if (wait_vm) |vm| vm.setCollectionRunning();
    return win.WaitForSingleObject(h, win.INFINITE) == win.WAIT_OBJECT_0;
}

// ---------------------------------------------------------------------------
// argv / env / path encoding
// ---------------------------------------------------------------------------

/// Join argv into one command line under the `CommandLineToArgvW` rules
/// (`platform.appendQuotedArg`, shared with thottam's git invocations), then
/// widen. `lpApplicationName` is deliberately null so `CreateProcessW`
/// performs the PATH search and the implied `.exe` suffixing that
/// `posix_spawnp` gives the POSIX side; the classic
/// "unquoted path with spaces" ambiguity cannot arise because argv[0] is
/// quoted by the same encoder whenever it needs to be.
fn buildCmdline(gc: *GC, arena: std.mem.Allocator, argv_list: []const Value) PrimitiveError![*:0]u16 {
    if (argv_list.len == 0)
        return primitives.argError("spawn-process", "argv must contain at least the program name", .{});
    var parts = std.ArrayList([]const u8).empty;
    defer parts.deinit(arena);
    for (argv_list) |arg| {
        if (!types.isString(arg)) return primitives.typeError("spawn-process", "string (argv element)", arg);
        const str = types.toObject(arg).as(types.SchemeString);
        const bytes = str.data[0..str.len];
        // A command line is NUL-terminated, so an embedded NUL would hand
        // the child something other than what the program wrote — the same
        // CWE-626 truncation the POSIX side rejects with dupeZChecked.
        if (std.mem.indexOfScalar(u8, bytes, 0) != null)
            return primitives.argError("spawn-process", "argv element contains an embedded NUL byte", .{});
        parts.append(arena, bytes) catch return PrimitiveError.OutOfMemory;
    }
    const line = platform.buildCommandLineW(arena, parts.items) catch |err| switch (err) {
        error.OutOfMemory => return PrimitiveError.OutOfMemory,
        else => return raiseArgEncodingError(gc, "argv is not encodable as a Windows command line"),
    };
    return line.ptr;
}

/// `env:` as a `CREATE_UNICODE_ENVIRONMENT` block: NUL-separated
/// `NAME=VALUE` strings, double-NUL terminated, sorted case-insensitively by
/// name (the ordering the loader documents and some CRTs assume). Validation
/// mirrors the POSIX `buildEnvp` exactly — same cycle guard, same rejections,
/// same messages — so a program that runs on both platforms fails the same
/// way on both.
fn buildEnvBlockW(arena: std.mem.Allocator, env_val: Value) PrimitiveError![*]const u16 {
    var entries = std.ArrayList([]const u8).empty;
    defer entries.deinit(arena);

    var cur = env_val;
    var slow = env_val;
    var step = false;
    while (cur != types.NIL) : (step = !step) {
        if (!types.isPair(cur))
            return primitives.typeError("spawn-process", "environment alist", env_val);
        const entry = types.car(cur);
        if (!types.isPair(entry))
            return primitives.typeError("spawn-process", "environment alist entry (name . value) pair", entry);
        const name = types.car(entry);
        const value = types.cdr(entry);
        if (!types.isString(name) or !types.isString(value))
            return primitives.typeError("spawn-process", "environment entry of two strings", entry);
        const name_str = types.toObject(name).as(types.SchemeString);
        const value_str = types.toObject(value).as(types.SchemeString);
        const name_bytes = name_str.data[0..name_str.len];
        const value_bytes = value_str.data[0..value_str.len];
        if (name_bytes.len == 0)
            return primitives.argError("spawn-process", "environment variable name is empty", .{});
        if (std.mem.indexOfScalar(u8, name_bytes, '=') != null)
            return primitives.argError("spawn-process", "environment variable name contains '='", .{});
        if (std.mem.indexOfScalar(u8, name_bytes, 0) != null or
            std.mem.indexOfScalar(u8, value_bytes, 0) != null)
            return primitives.argError("spawn-process", "environment entry contains an embedded NUL byte", .{});
        const joined = std.fmt.allocPrint(arena, "{s}={s}", .{ name_bytes, value_bytes }) catch return PrimitiveError.OutOfMemory;
        entries.append(arena, joined) catch return PrimitiveError.OutOfMemory;
        cur = types.cdr(cur);
        if (step) {
            slow = types.cdr(slow);
            if (cur == slow)
                return primitives.argError("spawn-process", "environment alist is cyclic", .{});
        }
    }
    std.mem.sort([]const u8, entries.items, {}, lessThanIgnoreCase);

    var block = std.ArrayList(u16).empty;
    defer block.deinit(arena);
    for (entries.items) |e| {
        const wlen = std.unicode.calcWtf16LeLen(e) catch
            return primitives.argError("spawn-process", "environment entry is not encodable as UTF-16", .{});
        const start = block.items.len;
        block.resize(arena, start + wlen) catch return PrimitiveError.OutOfMemory;
        _ = std.unicode.wtf8ToWtf16Le(block.items[start..], e) catch
            return primitives.argError("spawn-process", "environment entry is not encodable as UTF-16", .{});
        block.append(arena, 0) catch return PrimitiveError.OutOfMemory;
    }
    // An empty environment is still a valid block: two NULs, nothing else.
    block.append(arena, 0) catch return PrimitiveError.OutOfMemory;
    const owned = block.toOwnedSlice(arena) catch return PrimitiveError.OutOfMemory;
    return owned.ptr;
}

fn lessThanIgnoreCase(_: void, a: []const u8, b: []const u8) bool {
    return std.ascii.orderIgnoreCase(a, b) == .lt;
}

fn widenChecked(arena: std.mem.Allocator, bytes: []const u8, comptime what: []const u8) PrimitiveError![:0]u16 {
    if (std.mem.indexOfScalar(u8, bytes, 0) != null)
        return primitives.argError("spawn-process", what ++ " contains an embedded NUL byte", .{});
    const wlen = std.unicode.calcWtf16LeLen(bytes) catch
        return primitives.argError("spawn-process", what ++ " is not encodable as UTF-16", .{});
    const out = arena.allocSentinel(u16, wlen, 0) catch return PrimitiveError.OutOfMemory;
    _ = std.unicode.wtf8ToWtf16Le(out, bytes) catch
        return primitives.argError("spawn-process", what ++ " is not encodable as UTF-16", .{});
    return out;
}

// ---------------------------------------------------------------------------
// error forwarding (see process_posix.zig for the same shape)
// ---------------------------------------------------------------------------

fn raiseSpawnError(gc: *GC, msg_text: []const u8, irritant: Value, errno_val: c_int) PrimitiveError!Spawned {
    _ = try @import("primitives_process.zig").raiseProcessError(gc, msg_text, irritant, errno_val);
    unreachable;
}

fn raiseProcessErrorVoid(gc: *GC, msg_text: []const u8, errno_val: c_int) PrimitiveError!Value {
    return @import("primitives_process.zig").raiseProcessError(gc, msg_text, types.FALSE, errno_val);
}

fn raiseArgEncodingError(gc: *GC, comptime msg: []const u8) PrimitiveError![*:0]u16 {
    _ = try @import("primitives_process.zig").raiseProcessError(gc, msg, types.FALSE, @intFromEnum(std.c.E.INVAL));
    unreachable;
}
