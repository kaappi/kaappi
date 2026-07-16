//! Affected-test selection for `kaappi test --changed` / `--list-affected`
//! (kaappi#1510, part of the machine-legibility epic kaappi#1503).
//!
//! R7RS makes file-level dependency tracking unusually cheap: `define-library`
//! and `import` declare a file's dependencies explicitly, so a test's
//! dependency closure is derivable by *reading library declarations* — no
//! build-system integration, no compiler instrumentation. This module exploits
//! that. For each discovered SRFI-64 suite it computes the transitive closure
//! of the Scheme source the suite depends on — imported `.sld` libraries and
//! `include`d files, followed recursively — then intersects that closure with
//! the set of files git reports changed since a revision. A suite is *affected*
//! (and runs) iff its own file or anything in its closure changed.
//!
//! **Safety over precision.** A test is skipped only when we are confident its
//! entire closure is unchanged. Whenever the graph can't be trusted we run
//! *more* tests, never fewer, and say why on stderr:
//!
//!   * git unavailable / not a repo / bad revision  → run everything;
//!   * a native FFI artifact changed (`csrc/`, `*.dylib`/`*.so`) — invisible to
//!     the static import graph because `ffi-open` binds at runtime → run
//!     everything (the package's tests are all treated as dirty);
//!   * a specific suite's closure hits an untrackable edge — a `(load …)` with a
//!     path we can't follow, or a dependency we can't read/parse → that suite is
//!     forced to run.
//!
//! What is *not* tracked, by construction: dependencies reached through
//! `(load <computed-path>)`, and behavioural changes in built-in libraries
//! implemented in Zig (those live in the binary, not in a `.sld`). See
//! `docs/dev/test-runner.md` for the full contract.

const std = @import("std");
const platform = @import("platform.zig");
const types = @import("types.zig");
const memory = @import("memory.zig");
const reader_mod = @import("reader.zig");
const file_utils = @import("file_utils.zig");
const vm_library = @import("vm_library.zig");

const Value = types.Value;

/// The result of a selection pass. `files` are the suites to run — a subset of
/// the input when selection succeeded, or the whole input when we fell back to
/// running everything. `note` is a human-readable line (or lines) for stderr,
/// always present, explaining what was selected or why we fell back. Both are
/// owned by the allocator passed to `select`.
pub const Selection = struct {
    files: [][]const u8,
    full_run: bool,
    note: []const u8,

    pub fn deinit(self: *Selection, allocator: std.mem.Allocator) void {
        for (self.files) |f| allocator.free(f);
        allocator.free(self.files);
        allocator.free(self.note);
    }
};

/// Compute the affected subset of `all_files` given the files changed since git
/// revision `since` (e.g. "HEAD", "main", a SHA). `lib_paths` mirrors the
/// runner's `--lib-path` so library imports resolve exactly as a real run would.
///
/// Never fails for an incomplete graph — it falls back to a full run and
/// records the reason. The only way to get fewer files back than the input is a
/// clean, fully-analyzable graph with a non-empty, fully-accounted-for change set.
pub fn select(
    allocator: std.mem.Allocator,
    all_files: []const []const u8,
    since: []const u8,
    lib_paths: []const []const u8,
) Selection {
    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    // ── Establish the change set from git ──────────────────────────────
    const repo_root = gitTopLevel(arena) orelse
        return fullRun(allocator, all_files, "not a git repository (or git unavailable)");

    var cwd_buf: [std.posix.PATH_MAX]u8 = undefined;
    const cwd_ptr = std.c.getcwd(&cwd_buf, cwd_buf.len) orelse
        return fullRun(allocator, all_files, "cannot determine working directory");
    const cwd = cwd_ptr[0 .. std.mem.indexOfScalar(u8, cwd_buf[0..], 0) orelse cwd_buf.len];

    var changed = std.StringHashMap(void).init(arena);
    collectChanged(arena, since, repo_root, &changed) catch
        return fullRun(allocator, all_files, gitDiffFailureNote(arena, since));

    // A native/FFI artifact changing is invisible to the static import graph:
    // the dependency runs through `ffi-open`, which binds a shared library by
    // name at runtime. Treat the whole package's suites as dirty (issue #1510's
    // documented approximation).
    if (firstNativeArtifact(&changed)) |art| {
        return fullRun(allocator, all_files, nativeArtifactNote(arena, art));
    }

    // ── Compute each suite's closure and test for intersection ─────────
    var ctx = Ctx{
        .arena = arena,
        .cwd = cwd,
        .lib_paths = lib_paths,
        .changed = &changed,
        .memo = std.StringHashMap(Analysis).init(arena),
    };
    var visited = std.StringHashMap(void).init(arena);

    var affected: std.ArrayList([]const u8) = .empty;
    var forced: std.ArrayList([]const u8) = .empty; // suites run because their graph was incomplete

    for (all_files) |file| {
        const start = toAbs(arena, cwd, file) orelse {
            // Can't even canonicalize the suite's own path — run it to be safe.
            affected.append(arena, file) catch return oom(allocator, all_files);
            forced.append(arena, file) catch return oom(allocator, all_files);
            continue;
        };
        visited.clearRetainingCapacity();
        const decision = shouldRun(&ctx, start, &visited) catch RunDecision{ .run = true, .incomplete = true };
        if (decision.run) {
            affected.append(arena, file) catch return oom(allocator, all_files);
            if (decision.incomplete and !decision.changed) {
                forced.append(arena, file) catch return oom(allocator, all_files);
            }
        }
    }

    const note = buildSelectionNote(arena, since, all_files.len, affected.items.len, forced.items) catch "";
    return makeSelection(allocator, affected.items, false, note);
}

// ── Graph analysis ─────────────────────────────────────────────────────

/// One file's *direct* dependencies, plus whether analysing it left the graph
/// incomplete (an unreadable/unparseable file, or a `(load …)` we can't follow).
const Analysis = struct {
    deps: [][]const u8, // canonical absolute paths, arena-owned
    incomplete: bool,
};

const Ctx = struct {
    arena: std.mem.Allocator,
    cwd: []const u8,
    lib_paths: []const []const u8,
    changed: *std.StringHashMap(void),
    memo: std.StringHashMap(Analysis),
};

const RunDecision = struct {
    run: bool,
    /// A file in the closure was in the change set.
    changed: bool = false,
    /// The closure could not be fully computed (untrackable edge).
    incomplete: bool = false,
};

/// Breadth-first walk of `start`'s import/include closure. Runs the suite if any
/// reachable file changed, or if the closure hit an untrackable edge. `visited`
/// is a caller-owned scratch set, cleared between suites so its capacity is reused.
fn shouldRun(ctx: *Ctx, start: []const u8, visited: *std.StringHashMap(void)) !RunDecision {
    var queue: std.ArrayList([]const u8) = .empty;
    defer queue.deinit(ctx.arena);
    try queue.append(ctx.arena, start);
    try visited.put(start, {});

    var changed = false;
    var incomplete = false;
    var head: usize = 0;
    while (head < queue.items.len) : (head += 1) {
        const path = queue.items[head];
        if (ctx.changed.contains(path)) changed = true;

        const analysis = analyzeFile(ctx, path);
        if (analysis.incomplete) incomplete = true;
        for (analysis.deps) |dep| {
            if (visited.contains(dep)) continue;
            try visited.put(dep, {});
            try queue.append(ctx.arena, dep);
        }
    }
    return .{ .run = changed or incomplete, .changed = changed, .incomplete = incomplete };
}

/// Direct dependencies of the file at canonical `abs_path`, memoised. A file
/// that can't be read or parsed yields an empty dep set flagged incomplete, so
/// the suite that reached it runs rather than being silently trusted.
fn analyzeFile(ctx: *Ctx, abs_path: []const u8) Analysis {
    if (ctx.memo.get(abs_path)) |cached| return cached;

    const source = file_utils.readWholeFile(ctx.arena, abs_path, 8 * 1024 * 1024) catch {
        const a = Analysis{ .deps = &.{}, .incomplete = true };
        ctx.memo.put(abs_path, a) catch {};
        return a;
    };
    const a = analyzeSource(ctx, abs_path, source);
    ctx.memo.put(abs_path, a) catch {};
    return a;
}

/// Parse `source` (the contents of the file at `abs_path`) and extract its
/// direct dependencies. Split from `analyzeFile` so the parsing/resolution logic
/// is unit-testable from an in-memory string without touching the memo or disk.
fn analyzeSource(ctx: *Ctx, abs_path: []const u8, source: []const u8) Analysis {
    var builder = DepBuilder{ .ctx = ctx, .file_dir = vm_library.extractDir(abs_path) };

    // A dedicated GC for parsing only. `no_collect` keeps every datum alive for
    // the duration of the walk (we extract what we need into the arena before
    // moving on), and means the GC's root marker — which reaches for a VM that
    // does not exist here — is never invoked.
    var gc = memory.GC.init(ctx.arena);
    defer gc.deinit();
    gc.no_collect += 1;

    var rdr = reader_mod.Reader.init(&gc, source);
    defer rdr.deinit();

    while (rdr.hasMore() catch false) {
        const form = rdr.readDatum() catch {
            // A malformed file we can't finish reading is an incomplete edge:
            // run the suite that depends on it (its worker surfaces the real
            // parse error) rather than trusting a partial dep list.
            builder.incomplete = true;
            break;
        };
        analyzeForm(&builder, form, 0);
    }

    return .{ .deps = builder.deps.toOwnedSlice(ctx.arena) catch &.{}, .incomplete = builder.incomplete };
}

const DepBuilder = struct {
    ctx: *Ctx,
    file_dir: []const u8, // directory of the analysed file, with trailing '/'
    deps: std.ArrayList([]const u8) = .empty,
    incomplete: bool = false,

    fn addDep(self: *DepBuilder, abs: []const u8) void {
        for (self.deps.items) |existing| {
            if (std.mem.eql(u8, existing, abs)) return;
        }
        self.deps.append(self.ctx.arena, abs) catch {};
    }
};

/// Recursion depth cap for pathological nesting of `begin`/`cond-expand`.
const max_form_depth = 64;

/// Walk one top-level form (or library declaration) collecting dependencies.
/// Handles the container forms that can nest more declarations — `define-library`,
/// `begin`, `cond-expand` — by recursing, over-approximating `cond-expand` by
/// visiting *every* clause body (running a test that a feature would have
/// excluded is safe; skipping one is not).
fn analyzeForm(b: *DepBuilder, form: Value, depth: usize) void {
    if (depth > max_form_depth) {
        // Pathological nesting: stop descending, but never silently — mark the
        // closure incomplete so the suite runs rather than trusting a truncated
        // dep list.
        b.incomplete = true;
        return;
    }
    if (!types.isPair(form)) return;
    const head = types.car(form);
    if (!types.isSymbol(head)) return;
    const name = types.symbolName(head);

    if (std.mem.eql(u8, name, "import")) {
        var specs = types.cdr(form);
        while (types.isPair(specs)) : (specs = types.cdr(specs)) {
            addImportDep(b, types.car(specs));
        }
    } else if (std.mem.eql(u8, name, "include") or
        std.mem.eql(u8, name, "include-ci") or
        std.mem.eql(u8, name, "include-library-declarations"))
    {
        var files = types.cdr(form);
        while (types.isPair(files)) : (files = types.cdr(files)) {
            addIncludeDep(b, types.car(files));
        }
    } else if (std.mem.eql(u8, name, "define-library")) {
        // (define-library <name> <decl>...) — skip the name, walk declarations.
        var decls = types.cdr(form);
        if (types.isPair(decls)) decls = types.cdr(decls);
        while (types.isPair(decls)) : (decls = types.cdr(decls)) {
            analyzeForm(b, types.car(decls), depth + 1);
        }
    } else if (std.mem.eql(u8, name, "cond-expand")) {
        // (cond-expand (<feature-req> <body>...) ...) — walk every clause body.
        var clauses = types.cdr(form);
        while (types.isPair(clauses)) : (clauses = types.cdr(clauses)) {
            const clause = types.car(clauses);
            if (!types.isPair(clause)) continue;
            var body = types.cdr(clause); // skip the feature requirement
            while (types.isPair(body)) : (body = types.cdr(body)) {
                analyzeForm(b, types.car(body), depth + 1);
            }
        }
    } else if (std.mem.eql(u8, name, "begin")) {
        var body = types.cdr(form);
        while (types.isPair(body)) : (body = types.cdr(body)) {
            analyzeForm(b, types.car(body), depth + 1);
        }
    } else if (std.mem.eql(u8, name, "load")) {
        // `(load …)` reaches a file the static graph can't follow (the path may
        // be computed). Documented escape hatch: flag the closure incomplete.
        b.incomplete = true;
    }
}

/// Resolve one import spec to its `.sld` file (if any) and add it as a dep. A
/// spec may be wrapped in `only`/`except`/`prefix`/`rename`; the library name is
/// the innermost list. A name with no `.sld` on disk is a built-in library
/// (implemented in Zig) — it contributes nothing to the source graph.
fn addImportDep(b: *DepBuilder, spec: Value) void {
    const lib_name = unwrapImportSpec(spec) orelse return;
    var rel_buf: [512]u8 = undefined;
    const rel = vm_library.buildLibRelPath(lib_name, &rel_buf) catch return;
    const resolved = vm_library.resolveLibraryPath(b.ctx.arena, rel, b.ctx.lib_paths) orelse return;
    if (toAbs(b.ctx.arena, b.ctx.cwd, resolved)) |abs| b.addDep(abs);
}

/// Add an `include`d file, resolved relative to the including file's directory —
/// exactly as the loader's `openIncludeFile` does (`current_lib_dir` + path).
fn addIncludeDep(b: *DepBuilder, file_val: Value) void {
    const path = stringBytes(file_val) orelse return;
    if (path.len == 0) return;
    const base: []const u8 = if (path[0] == '/') "" else b.file_dir;
    const joined = std.fmt.allocPrint(b.ctx.arena, "{s}{s}", .{ base, path }) catch return;
    if (toAbs(b.ctx.arena, b.ctx.cwd, joined)) |abs| b.addDep(abs);
}

/// Strip `only`/`except`/`prefix`/`rename` wrappers to the bare library name.
/// Returns null for a malformed spec.
fn unwrapImportSpec(spec: Value) ?Value {
    var cur = spec;
    var guard: usize = 0;
    while (types.isPair(cur)) {
        guard += 1;
        if (guard > 32) return null;
        const head = types.car(cur);
        if (!types.isSymbol(head)) return cur;
        const n = types.symbolName(head);
        const wrapped = std.mem.eql(u8, n, "only") or
            std.mem.eql(u8, n, "except") or
            std.mem.eql(u8, n, "prefix") or
            std.mem.eql(u8, n, "rename");
        if (!wrapped) return cur; // a plain library name, e.g. (scheme base)
        const rest = types.cdr(cur);
        if (!types.isPair(rest)) return null;
        cur = types.car(rest);
    }
    return null;
}

// ── git front end ──────────────────────────────────────────────────────

/// Absolute path of the enclosing git work-tree root, or null if `git
/// rev-parse` fails (not a repo, or git not on PATH).
fn gitTopLevel(arena: std.mem.Allocator) ?[]const u8 {
    const out = runCapture(arena, &.{ "git", "rev-parse", "--show-toplevel" }) orelse return null;
    if (!out.ok) return null;
    const trimmed = std.mem.trim(u8, out.stdout, " \t\r\n");
    if (trimmed.len == 0) return null;
    return trimmed;
}

/// Fill `changed` with the absolute paths of files that differ from `since`
/// (tracked, via `git diff`) plus untracked files (`git ls-files --others`). A
/// brand-new, uncommitted test file counts as changed. Errors if the diff fails
/// (a bad revision), so the caller can fall back loudly.
fn collectChanged(arena: std.mem.Allocator, since: []const u8, repo_root: []const u8, changed: *std.StringHashMap(void)) !void {
    const diff = runCapture(arena, &.{ "git", "diff", "--name-only", "-z", since }) orelse return error.GitUnavailable;
    if (!diff.ok) return error.GitDiffFailed;
    try addNulPaths(arena, diff.stdout, repo_root, changed);

    // Untracked files won't show in `git diff`; a new suite or new library must
    // still count. Best-effort: a failure here shouldn't defeat the diff.
    if (runCapture(arena, &.{ "git", "ls-files", "--others", "--exclude-standard", "-z" })) |others| {
        if (others.ok) try addNulPaths(arena, others.stdout, repo_root, changed);
    }
}

/// Split NUL-separated, repo-root-relative git paths, canonicalise each against
/// `repo_root`, and insert into `set`.
fn addNulPaths(arena: std.mem.Allocator, data: []const u8, repo_root: []const u8, set: *std.StringHashMap(void)) !void {
    var it = std.mem.splitScalar(u8, data, 0);
    while (it.next()) |rel| {
        if (rel.len == 0) continue;
        const abs = toAbs(arena, repo_root, rel) orelse continue;
        try set.put(abs, {});
    }
}

// ── native-artifact detection ──────────────────────────────────────────

/// The first changed path that is a native/FFI build input or output, or null.
/// These can't be traced through the import graph (`ffi-open` binds at runtime),
/// so any such change dirties the whole package.
fn firstNativeArtifact(changed: *std.StringHashMap(void)) ?[]const u8 {
    var it = changed.keyIterator();
    while (it.next()) |key| {
        if (isNativeArtifact(key.*)) return key.*;
    }
    return null;
}

/// True if `path` is a C source under a `csrc/` directory or a built shared
/// library (`.dylib`/`.so`/`.dll`). Deliberately narrow: a false positive costs
/// a full run, a false negative would silently skip an FFI-dependent suite.
fn isNativeArtifact(path: []const u8) bool {
    if (std.mem.endsWith(u8, path, ".dylib") or
        std.mem.endsWith(u8, path, ".so") or
        std.mem.endsWith(u8, path, ".dll")) return true;
    // A ".so" with a version suffix (libfoo.so.1). Match "/…/x.so." mid-path.
    if (std.mem.indexOf(u8, path, ".so.") != null) return true;
    // A path component named exactly "csrc".
    var it = std.mem.splitScalar(u8, path, '/');
    while (it.next()) |comp| {
        if (std.mem.eql(u8, comp, "csrc")) return true;
    }
    return false;
}

// ── subprocess capture ─────────────────────────────────────────────────

const CaptureResult = struct { stdout: []u8, ok: bool };

/// Run `argv` (argv[0] resolved via PATH), capturing stdout; stderr is
/// discarded. Returns null if the program can't be found or launched, and
/// `.ok = false` if it exited nonzero or by signal. Modelled on the raw
/// fork/exec used elsewhere in the tree (test_runner, native_compiler).
fn runCapture(arena: std.mem.Allocator, argv: []const []const u8) ?CaptureResult {
    if (argv.len == 0) return null;
    const exe = findInPath(arena, argv[0]) orelse return null;

    const argv_z = arena.alloc(?[*:0]const u8, argv.len + 1) catch return null;
    argv_z[0] = (arena.dupeZ(u8, exe) catch return null).ptr;
    for (argv[1..], 1..) |arg, i| {
        argv_z[i] = (arena.dupeZ(u8, arg) catch return null).ptr;
    }
    argv_z[argv.len] = null;

    if (comptime platform.is_windows) {
        var argv_slices_buf: [32][]const u8 = undefined;
        if (argv.len > argv_slices_buf.len) return null;
        argv_slices_buf[0] = exe;
        for (argv[1..], 1..) |arg, i| argv_slices_buf[i] = arg;
        const res = platform.winSpawnCaptureMerged(arena, argv_slices_buf[0..argv.len], null) catch return null;
        return .{ .stdout = res.output, .ok = res.exit_code == 0 };
    }

    var pipe: [2]c_int = undefined;
    if (std.c.pipe(&pipe) != 0) return null;

    const pid = std.posix.system.fork();
    if (pid < 0) {
        _ = std.c.close(pipe[0]);
        _ = std.c.close(pipe[1]);
        return null;
    }
    if (pid == 0) {
        _ = std.c.close(pipe[0]);
        _ = std.c.dup2(pipe[1], 1);
        const devnull = std.c.open("/dev/null", .{ .ACCMODE = .WRONLY });
        if (devnull >= 0) _ = std.c.dup2(devnull, 2);
        _ = std.c.close(pipe[1]);
        _ = std.posix.system.execve(
            @ptrCast(argv_z[0].?),
            @ptrCast(argv_z.ptr),
            @ptrCast(std.c.environ),
        );
        std.process.exit(127);
    }

    _ = std.c.close(pipe[1]);
    const cap: usize = 4 * 1024 * 1024;
    var output: std.ArrayList(u8) = .empty;
    var tmp: [4096]u8 = undefined;
    while (true) {
        const n = std.posix.read(pipe[0], &tmp) catch break;
        if (n == 0) break;
        if (output.items.len < cap) {
            const room = cap - output.items.len;
            output.appendSlice(arena, tmp[0..@min(n, room)]) catch break;
        }
    }
    _ = std.c.close(pipe[0]);

    var status: c_int = 0;
    _ = std.c.waitpid(pid, &status, 0);
    const raw: c_uint = @bitCast(status);
    const exited = (raw & 0x7f) == 0;
    const code: u8 = @intCast((raw >> 8) & 0xff);

    return .{
        .stdout = output.toOwnedSlice(arena) catch return null,
        .ok = exited and code == 0,
    };
}

fn findInPath(arena: std.mem.Allocator, name: []const u8) ?[]const u8 {
    // An explicit path (contains '/') is used as-is.
    if (std.mem.indexOfScalar(u8, name, '/') != null) return name;
    const path_env = platform.getenv("PATH") orelse return null;
    const path_str = std.mem.span(path_env);
    var iter = std.mem.splitScalar(u8, path_str, platform.path_list_sep);
    while (iter.next()) |dir| {
        if (dir.len == 0) continue;
        const full = std.fmt.allocPrint(arena, "{s}/{s}{s}", .{ dir, name, platform.exe_suffix }) catch continue;
        const full_z = arena.dupeZ(u8, full) catch continue;
        const fd = platform.openRead(full_z) catch continue;
        _ = platform.close(fd);
        return full;
    }
    return null;
}

// ── small helpers ──────────────────────────────────────────────────────

/// Canonicalise `path` to a normalised absolute path (lexically — no disk
/// access, so it works for deleted files too). Relative paths resolve against
/// `base`, which must itself be absolute.
fn toAbs(arena: std.mem.Allocator, base: []const u8, path: []const u8) ?[]const u8 {
    const resolved = if (path.len > 0 and path[0] == '/')
        std.fs.path.resolve(arena, &.{path}) catch return null
    else
        std.fs.path.resolve(arena, &.{ base, path }) catch return null;
    // std.fs.path.resolve emits backslashes on Windows; the import graph
    // (and every path the runtime builds) uses '/', so normalize to keep
    // graph keys and git-diff paths comparable.
    if (comptime platform.is_windows) {
        const mutable = @constCast(resolved);
        for (mutable) |*ch| {
            if (ch.* == '\\') ch.* = '/';
        }
    }
    return resolved;
}

fn stringBytes(v: Value) ?[]const u8 {
    if (!types.isString(v)) return null;
    const s = types.toObject(v).as(types.SchemeString);
    return s.data[0..s.len];
}

/// Build a full-run Selection with a formatted reason. `reason` may be any
/// slice (stack, arena, or literal); `makeSelection` copies everything it keeps
/// into `allocator`, so no ownership juggling is needed.
fn fullRun(allocator: std.mem.Allocator, all_files: []const []const u8, reason: []const u8) Selection {
    var buf: [4096]u8 = undefined;
    const note = std.fmt.bufPrint(&buf, "kaappi test: {s}; running all {d} tests", .{ reason, all_files.len }) catch
        "kaappi test: running all tests";
    return makeSelection(allocator, all_files, true, note);
}

fn gitDiffFailureNote(arena: std.mem.Allocator, since: []const u8) []const u8 {
    return std.fmt.allocPrint(arena, "git diff against '{s}' failed (unknown revision?)", .{since}) catch
        "git diff failed";
}

fn nativeArtifactNote(arena: std.mem.Allocator, artifact: []const u8) []const u8 {
    return std.fmt.allocPrint(
        arena,
        "native/FFI artifact changed ({s}) — the import graph can't trace ffi-open",
        .{artifact},
    ) catch "native/FFI artifact changed";
}

fn buildSelectionNote(arena: std.mem.Allocator, since: []const u8, total: usize, affected: usize, forced: []const []const u8) ![]const u8 {
    var aw: std.Io.Writer.Allocating = .init(arena);
    const w = &aw.writer;
    try w.print("kaappi test: {d} of {d} tests affected since {s}", .{ affected, total, since });
    if (forced.len > 0) {
        try w.print("\nkaappi test: {d} run because their dependency graph is incomplete (load / unreadable dep):", .{forced.len});
        for (forced) |f| {
            try w.writeAll("\n  - ");
            try w.writeAll(f);
        }
    }
    return aw.written();
}

/// Copy `files` and `note` into a Selection owned by `allocator`. The inputs may
/// live in the internal arena (freed when `select` returns); this is the single
/// point where the result is lifted into caller-owned memory.
fn makeSelection(allocator: std.mem.Allocator, files: []const []const u8, full_run_flag: bool, note: []const u8) Selection {
    const owned_note = allocator.dupe(u8, note) catch "";
    const owned_files = allocator.alloc([]const u8, files.len) catch
        return .{ .files = &.{}, .full_run = full_run_flag, .note = owned_note };
    var filled: usize = 0;
    for (files) |f| {
        owned_files[filled] = allocator.dupe(u8, f) catch break;
        filled += 1;
    }
    return .{ .files = owned_files[0..filled], .full_run = full_run_flag, .note = owned_note };
}

fn oom(allocator: std.mem.Allocator, all_files: []const []const u8) Selection {
    return fullRun(allocator, all_files, "out of memory during selection");
}

// ── tests ──────────────────────────────────────────────────────────────

const testing = std.testing;

test "unwrapImportSpec strips only/except/prefix/rename to the library name" {
    var gc = memory.GC.init(testing.allocator);
    defer gc.deinit();
    gc.no_collect += 1;

    // (only (scheme base) car cdr) → (scheme base)
    var rdr = reader_mod.Reader.init(&gc, "(only (scheme base) car cdr)");
    defer rdr.deinit();
    const spec = try rdr.readDatum();
    const name = unwrapImportSpec(spec).?;
    // name should be (scheme base): a pair whose car is the symbol 'scheme'.
    try testing.expect(types.isPair(name));
    try testing.expectEqualStrings("scheme", types.symbolName(types.car(name)));

    // A plain name passes through unchanged.
    var rdr2 = reader_mod.Reader.init(&gc, "(srfi 64)");
    defer rdr2.deinit();
    const plain = try rdr2.readDatum();
    const plain_name = unwrapImportSpec(plain).?;
    try testing.expectEqualStrings("srfi", types.symbolName(types.car(plain_name)));

    // Nested wrappers: (prefix (rename (foo bar) (a b)) p:) → (foo bar)
    var rdr3 = reader_mod.Reader.init(&gc, "(prefix (rename (foo bar) (a b)) p:)");
    defer rdr3.deinit();
    const nested = try rdr3.readDatum();
    const nn = unwrapImportSpec(nested).?;
    try testing.expectEqualStrings("foo", types.symbolName(types.car(nn)));
}

test "isNativeArtifact matches csrc and shared libraries only" {
    try testing.expect(isNativeArtifact("kaappi-net/csrc/net.c"));
    try testing.expect(isNativeArtifact("csrc/helper.h"));
    try testing.expect(isNativeArtifact("lib/kaappi/libnet.dylib"));
    try testing.expect(isNativeArtifact("build/libfoo.so"));
    try testing.expect(isNativeArtifact("build/libfoo.so.1"));
    try testing.expect(isNativeArtifact("build/foo.dll"));

    try testing.expect(!isNativeArtifact("tests/scheme/smoke/basic.scm"));
    try testing.expect(!isNativeArtifact("lib/kaappi/net.sld"));
    try testing.expect(!isNativeArtifact("src/main.zig"));
    // "csrc" only as a full path component, not a substring.
    try testing.expect(!isNativeArtifact("mycsrcfile.scm"));
}

test "toAbs normalises relative and absolute paths lexically" {
    // Relative resolves against base.
    const r = toAbs(testing.allocator, "/repo/root", "tests/a.scm").?;
    defer testing.allocator.free(r);
    try testing.expectEqualStrings("/repo/root/tests/a.scm", r);

    // Absolute ignores base and normalises '..'.
    const a = toAbs(testing.allocator, "/repo/root", "/repo/root/x/../y.scm").?;
    defer testing.allocator.free(a);
    try testing.expectEqualStrings("/repo/root/y.scm", a);
}

test "shouldRun: BFS over a synthetic graph — diamond deps, changed, and clean" {
    const alloc = testing.allocator;
    var arena_state = std.heap.ArenaAllocator.init(alloc);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    // Diamond: t → a, t → b, a → d, b → d.  Only d changed.
    var changed = std.StringHashMap(void).init(arena);
    try changed.put("/r/d.sld", {});

    var ctx = Ctx{
        .arena = arena,
        .cwd = "/r",
        .lib_paths = &.{},
        .changed = &changed,
        .memo = std.StringHashMap(Analysis).init(arena),
    };
    try ctx.memo.put("/r/t.scm", .{ .deps = try dupDeps(arena, &.{ "/r/a.sld", "/r/b.sld" }), .incomplete = false });
    try ctx.memo.put("/r/a.sld", .{ .deps = try dupDeps(arena, &.{"/r/d.sld"}), .incomplete = false });
    try ctx.memo.put("/r/b.sld", .{ .deps = try dupDeps(arena, &.{"/r/d.sld"}), .incomplete = false });
    try ctx.memo.put("/r/d.sld", .{ .deps = &.{}, .incomplete = false });
    // An unrelated suite whose closure doesn't reach d.
    try ctx.memo.put("/r/u.scm", .{ .deps = try dupDeps(arena, &.{"/r/e.sld"}), .incomplete = false });
    try ctx.memo.put("/r/e.sld", .{ .deps = &.{}, .incomplete = false });

    var visited = std.StringHashMap(void).init(arena);

    const d1 = try shouldRun(&ctx, "/r/t.scm", &visited);
    try testing.expect(d1.run and d1.changed and !d1.incomplete);

    visited.clearRetainingCapacity();
    const d2 = try shouldRun(&ctx, "/r/u.scm", &visited);
    try testing.expect(!d2.run);
}

test "shouldRun: an incomplete closure forces the suite to run" {
    const alloc = testing.allocator;
    var arena_state = std.heap.ArenaAllocator.init(alloc);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var changed = std.StringHashMap(void).init(arena); // nothing changed
    var ctx = Ctx{
        .arena = arena,
        .cwd = "/r",
        .lib_paths = &.{},
        .changed = &changed,
        .memo = std.StringHashMap(Analysis).init(arena),
    };
    // t → a, and a uses (load …) → incomplete.
    try ctx.memo.put("/r/t.scm", .{ .deps = try dupDeps(arena, &.{"/r/a.sld"}), .incomplete = false });
    try ctx.memo.put("/r/a.sld", .{ .deps = &.{}, .incomplete = true });

    var visited = std.StringHashMap(void).init(arena);
    const d = try shouldRun(&ctx, "/r/t.scm", &visited);
    try testing.expect(d.run and d.incomplete and !d.changed);
}

test "shouldRun: cycles terminate" {
    const alloc = testing.allocator;
    var arena_state = std.heap.ArenaAllocator.init(alloc);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var changed = std.StringHashMap(void).init(arena);
    var ctx = Ctx{
        .arena = arena,
        .cwd = "/r",
        .lib_paths = &.{},
        .changed = &changed,
        .memo = std.StringHashMap(Analysis).init(arena),
    };
    // a → b → a
    try ctx.memo.put("/r/a.sld", .{ .deps = try dupDeps(arena, &.{"/r/b.sld"}), .incomplete = false });
    try ctx.memo.put("/r/b.sld", .{ .deps = try dupDeps(arena, &.{"/r/a.sld"}), .incomplete = false });

    var visited = std.StringHashMap(void).init(arena);
    const d = try shouldRun(&ctx, "/r/a.sld", &visited);
    try testing.expect(!d.run); // terminates, nothing changed
}

fn dupDeps(arena: std.mem.Allocator, deps: []const []const u8) ![][]const u8 {
    const out = try arena.alloc([]const u8, deps.len);
    for (deps, 0..) |d, i| out[i] = d;
    return out;
}
