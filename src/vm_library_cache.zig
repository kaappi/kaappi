//! `.sld` bytecode-cache machinery (kaappi#1888).
//!
//! A file-backed library load recompiles its whole body on every process
//! start, because nothing about a library was ever cacheable: the export table
//! is closures over a live environment plus macro transformers, none of which
//! the `.sbc` codec could represent. This module closes that gap with a
//! "structure from source, code from cache" split:
//!
//!   * The COLD path records an ordered event log while it compiles: which
//!     functions the body produced (with their env kind), which transformers
//!     each form's compilation registered into lib_env, the content hash of
//!     every include-family file opened, and the resolved identity + hash of
//!     every dependency .sld loaded transitively. Those records serialize into
//!     a library-kind `.sbc` entry (`bytecode_file.writeFileWithLibrary`).
//!
//!   * The WARM path re-reads and re-parses the (hash-validated) .sld source
//!     and walks its declarations through the ordinary loader — imports
//!     actually load (dependencies hit their own entries), export lists are
//!     re-derived, cond-expand re-selects, define-record-type runs as data —
//!     but every point where the cold path *compiled* a body form instead
//!     registers a deserialized transformer or runs a deserialized function.
//!     Running the body is what makes this safe where value-serialization
//!     cannot be: closures capture the reconstructed lib_env, record types and
//!     hash tables and every other runtime value are created exactly as cold,
//!     and the export table is derived from the live lib_env by the normal
//!     name lookup — so an export that came from
//!     include-library-declarations or cond-expand is present warm for the
//!     same reason it is present cold.
//!
//! Invalidation is layered on the existing key (resolved .sld path in the
//! filename, source hash and compiler hash in the header): the entry also
//! stores the include files (path + content hash) and dependencies (relative
//! path, resolved path, content hash) the cold load used, all re-validated
//! before a warm replay starts. A library whose cond-expand consulted
//! *library availability* is never cached at all — that answer depends on the
//! live registry and lib-path, not on anything a key can hash (platform
//! features are compile-time constants already covered by the compiler hash).
//!
//! GC safety, the hazard that disabled the original attempt: every function
//! the collector records is rooted in `gc.extra_roots` for the duration of the
//! load (today the compiled top-level wrappers are unrooted the moment
//! compileLibExpr returns, which is exactly the use-after-free the old comment
//! described), and the roots are dropped again — by pointer identity, never by
//! truncation, so `rootedSlot`'s permanent eval-cache entries interleaved into
//! the same list survive — once the entry is written.

const std = @import("std");
const types = @import("types.zig");
const memory = @import("memory.zig");
const ir = @import("ir.zig");
const cache = @import("cache.zig");
const bytecode_file = @import("bytecode_file.zig");
const vm_mod = @import("vm.zig");
const vm_library = @import("vm_library.zig");
const timings = @import("timings.zig");

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Value = types.Value;
const Function = types.Function;
const bf = bytecode_file;

/// A (name, transformer) pair as it sits in lib_env — the snapshot unit for
/// diffing compile-time registrations. `name` borrows lib_env's key slice,
/// valid for as long as the map entry does (the whole load).
const TxSnapshotEntry = struct { name: []const u8, tx: *types.Transformer };

/// One in-flight file-backed library load. The innermost stack frame is the
/// one compileLibExpr/evalIncludedForm/openIncludeFile/evalLibFeatureReq
/// record into (or replay from, when `warm` is set).
pub const LibCollector = struct {
    /// False for loads we never intend to cache (record nothing, replay
    /// nothing): embedded/bundled sources, or a disabled cache.
    armed: bool = false,
    /// Non-null while REPLAYING a cache entry: compileLibExpr consumes events
    /// from here instead of compiling.
    warm: ?WarmCursor = null,
    /// The deserialized entry a warm replay works from. Owned here so every
    /// pop path frees it; the WarmCursor's slices point into it.
    warm_result: ?bf.DeserializeResult = null,
    /// Compiled body functions in event order. Only meaningful cold; the
    /// pointers double as the root-removal set at load end.
    funcs: std.ArrayList(*Function) = .empty,
    /// The ordered replay log being recorded (cold).
    events: std.ArrayList(bf.LibEventRecord) = .empty,
    /// Every include-family file opened during the load (path + content hash).
    includes: std.ArrayList(bf.IncludeRecord) = .empty,
    /// Every file-backed dependency library this load resolved and read
    /// (including transitively, via the enclosing-frame recording below).
    deps: std.ArrayList(bf.DepRecord) = .empty,
    /// Set when something made this library uncacheable: a compile-time
    /// registration the event log cannot replay (vm.macros / syntax
    /// properties growth), or an availability-dependent cond-expand feature.
    bail: bool = false,
    /// Set when a warm replay hit an event-log desync: every further replay
    /// on this load becomes a no-op and endWarmLoad fails loudly. The
    /// validated hashes make a desync near-impossible, so it indicates a
    /// loader/serializer bug and must never pass silently.
    replay_desync: bool = false,
    /// lib_env transformer registrations as of the last snapshot — the diff
    /// base for attributing new registrations to the form being compiled.
    tx_before: std.ArrayList(TxSnapshotEntry) = .empty,
    /// Names of `tx_before`, for O(1) lookup while diffing.
    tx_before_lookup: std.StringHashMap(void) = undefined,
    tx_before_lookup_init: bool = false,

    fn deinit(self: *LibCollector, allocator: std.mem.Allocator) void {
        self.funcs.deinit(allocator);
        for (self.events.items) |ev| {
            if (ev == .register_tx) allocator.free(@constCast(ev.register_tx.name));
        }
        self.events.deinit(allocator);
        for (self.includes.items) |inc| allocator.free(@constCast(inc.path));
        self.includes.deinit(allocator);
        for (self.deps.items) |dep| {
            allocator.free(@constCast(dep.rel_path));
            allocator.free(@constCast(dep.resolved_path));
            allocator.free(@constCast(dep.lib_name));
        }
        self.deps.deinit(allocator);
        self.tx_before.deinit(allocator);
        if (self.tx_before_lookup_init) {
            self.tx_before_lookup.deinit();
            self.tx_before_lookup_init = false;
        }
        if (self.warm_result) |*wr| bf.freeDeserializeResult(allocator, wr);
        self.* = .{};
    }
};

/// Replay state over a deserialized library entry.
pub const WarmCursor = struct {
    events: []bf.LibEvent,
    funcs: []*Function,
    /// Function indices in events are < top_level_count (the form functions).
    top_level_count: u32,
    pos: usize = 0,

    fn peek(self: *WarmCursor) ?bf.LibEvent {
        if (self.pos >= self.events.len) return null;
        return self.events[self.pos];
    }
};

/// Whether the .sld cache participates in this process at all — mirrors the
/// program cache's own gates (runFile): `--sandbox` (no filesystem side
/// effects) and `--no-ir-opt` (cache keys don't include the flag). WASM and a
/// missing home directory surface later as `cache.pathForSource` returning
/// null, which the load hooks treat as "no cache". `kaappi check` / the LSP
/// are also excluded: analysis mode accepts placeholder transformers for
/// unresolvable macro specs (#2007), and one of those must never be recorded
/// into an entry a normal run would later hit.
pub fn libCacheEnabled(vm: *VM) bool {
    if (@import("check_lint.zig").active != null) return false;
    return !vm.sandbox_mode and ir.optimize_enabled;
}

/// The innermost collector, or null when no file-backed library load is in
/// flight. `armed_only` further requires that it is recording (cold), not
/// replaying.
pub fn top(vm: *VM) ?*LibCollector {
    if (vm.lib_cache_depth == 0) return null;
    if (vm.lib_cache_depth > vm.lib_cache_stack.len) return null; // overflow frame: inert
    return &vm.lib_cache_stack[vm.lib_cache_depth - 1];
}

/// Overflow guard for pathological import chains deeper than the stack: loads
/// beyond the 8th nested frame simply don't cache (the frame is not pushed,
/// and `top` returns null while the overflow persists via depth > len).
fn push(vm: *VM, collector: LibCollector) bool {
    if (vm.lib_cache_depth >= vm.lib_cache_stack.len) {
        vm.lib_cache_depth += 1; // mark overflow; pops must still balance
        return false;
    }
    vm.lib_cache_stack[vm.lib_cache_depth] = collector;
    vm.lib_cache_depth += 1;
    return true;
}

fn pop(vm: *VM) void {
    if (vm.lib_cache_depth == 0) return;
    vm.lib_cache_depth -= 1;
    if (vm.lib_cache_depth < vm.lib_cache_stack.len) {
        vm.lib_cache_stack[vm.lib_cache_depth].deinit(vm.gc.allocator);
    }
}

/// Free any collectors left on the stack (VM teardown after a mid-load error).
pub fn deinitStack(vm: *VM) void {
    while (vm.lib_cache_depth > 0) pop(vm);
}

// ---------------------------------------------------------------------------
// Cold-path recording (called from vm_library.zig)
// ---------------------------------------------------------------------------

/// Whether a requirement tree's answer could depend on library *availability*
/// (the live registry / lib-path), rather than on compile-time platform
/// features covered by the compiler hash. Such libraries stay uncached: the
/// selected cond-expand branch is not a function of anything a cache key can
/// hash, and replaying the cold branch warm would silently diverge.
pub fn featureReqTouchesAvailability(req: Value) bool {
    if (types.isSymbol(req)) {
        return vm_library.srfiFeatureNumber(types.symbolName(req)) != null;
    }
    if (!types.isPair(req)) return false;
    const head = types.car(req);
    if (!types.isSymbol(head)) return false;
    const op = types.symbolName(head);
    if (std.mem.eql(u8, op, "library")) return true;
    var rest = types.cdr(req);
    while (types.isPair(rest)) {
        if (featureReqTouchesAvailability(types.car(rest))) return true;
        rest = types.cdr(rest);
    }
    return false;
}

/// Record that a cond-expand requirement was consulted during this load (the
/// single choke point is evalLibFeatureReq). Availability-dependent
/// requirements bail the cache.
pub fn noteFeatureReq(vm: *VM, req: Value) void {
    const c = top(vm) orelse return;
    if (!c.armed or c.warm != null) return;
    if (featureReqTouchesAvailability(req)) c.bail = true;
}

/// Record an include-family file opened during the load: `path` is the path
/// actually opened (already resolved), `content` its bytes as read.
pub fn noteIncludeFile(vm: *VM, path: []const u8, content: []const u8) void {
    const c = top(vm) orelse return;
    if (!c.armed or c.warm != null) return;
    if (c.includes.items.len >= bf.MAX_LIBRARY_INCLUDES) {
        c.bail = true;
        return;
    }
    const owned = vm.gc.allocator.dupe(u8, path) catch {
        c.bail = true;
        return;
    };
    c.includes.append(vm.gc.allocator, .{ .path = owned, .hash = bf.sourceHash(content) }) catch {
        vm.gc.allocator.free(owned);
        c.bail = true;
    };
}

/// The registry short-circuit variant: the dependency was loaded by an
/// EARLIER import, so every frame that imports it now — including the
/// innermost in-flight load, which is exactly the one whose entry needs the
/// record — plus the main run's recorder get the dependency.
pub fn noteDepLoadedAllFrames(vm: *VM, rel_path: []const u8, resolved_path: []const u8, source_hash: u64, lib_name: []const u8) void {
    noteRunDep(vm, rel_path, resolved_path, source_hash, lib_name);
    var d: u8 = 0;
    const max = @min(vm.lib_cache_depth, @as(u8, vm.lib_cache_stack.len));
    while (d < max) : (d += 1) {
        noteDepInto(&vm.lib_cache_stack[d], vm, rel_path, resolved_path, source_hash, lib_name);
    }
}

/// Record a dependency .sld resolved and read by a (nested) load, into every
/// armed enclosing frame except the load's own — the enclosing libraries'
/// compiled bodies embed expansions of the dependency's macros, so their
/// entries must miss when it changes. Deduplicated per frame by canonical
/// library name.
pub fn noteDepLoaded(vm: *VM, rel_path: []const u8, resolved_path: []const u8, source_hash: u64, lib_name: []const u8, own_depth: u8) void {
    var d: u8 = 0;
    while (d < own_depth and d < vm.lib_cache_stack.len) : (d += 1) {
        noteDepInto(&vm.lib_cache_stack[d], vm, rel_path, resolved_path, source_hash, lib_name);
    }
}

fn noteDepInto(c: *LibCollector, vm: *VM, rel_path: []const u8, resolved_path: []const u8, source_hash: u64, lib_name: []const u8) void {
    const allocator = vm.gc.allocator;
    if (!c.armed or c.warm != null) return;
    var dup = false;
    for (c.deps.items) |dep| {
        if (std.mem.eql(u8, dep.lib_name, lib_name)) {
            dup = true;
            break;
        }
    }
    if (dup) return;
    if (c.deps.items.len >= bf.MAX_LIBRARY_DEPS) {
        c.bail = true;
        return;
    }
    const rel = allocator.dupe(u8, rel_path) catch return;
    const res = allocator.dupe(u8, resolved_path) catch {
        allocator.free(rel);
        return;
    };
    const name = allocator.dupe(u8, lib_name) catch {
        allocator.free(rel);
        allocator.free(res);
        return;
    };
    c.deps.append(allocator, .{ .rel_path = rel, .resolved_path = res, .source_hash = source_hash, .lib_name = name }) catch {
        allocator.free(rel);
        allocator.free(res);
        allocator.free(name);
    };
}

/// Snapshot lib_env's transformer registrations before compiling a form, so
/// the post-compile diff can attribute new/changed ones to that form.
pub fn snapshotTransformers(vm: *VM, lib_env: *std.StringHashMap(Value)) void {
    const c = top(vm) orelse return;
    if (!c.armed or c.warm != null) return;
    const allocator = vm.gc.allocator;
    c.tx_before.clearRetainingCapacity();
    if (!c.tx_before_lookup_init) {
        c.tx_before_lookup = std.StringHashMap(void).init(allocator);
        c.tx_before_lookup_init = true;
    }
    c.tx_before_lookup.clearRetainingCapacity();
    var it = lib_env.iterator();
    while (it.next()) |entry| {
        const v = entry.value_ptr.*;
        if (!types.isTransformer(v)) continue;
        const tx = types.toObject(v).as(types.Transformer);
        c.tx_before.append(allocator, .{ .name = entry.key_ptr.*, .tx = tx }) catch {
            c.bail = true;
            return;
        };
        c.tx_before_lookup.put(entry.key_ptr.*, {}) catch {
            c.bail = true;
            return;
        };
    }
}

/// Diff lib_env against the snapshot: every transformer that is new, or whose
/// object changed under an existing name, becomes a register_tx event — sorted
/// by name so the serialized entry is byte-stable across runs.
pub fn diffTransformers(vm: *VM, lib_env: *std.StringHashMap(Value)) void {
    const c = top(vm) orelse return;
    if (!c.armed or c.warm != null) return;
    const allocator = vm.gc.allocator;

    var fresh: std.ArrayList([]const u8) = .empty;
    defer fresh.deinit(allocator);
    var it = lib_env.iterator();
    while (it.next()) |entry| {
        const v = entry.value_ptr.*;
        if (!types.isTransformer(v)) continue;
        const tx = types.toObject(v).as(types.Transformer);
        const before = c.tx_before_lookup.contains(entry.key_ptr.*);
        var changed = !before;
        if (before) {
            // Name existed: only a *different* transformer object counts —
            // a redefinition replaced the binding.
            for (c.tx_before.items) |e| {
                if (std.mem.eql(u8, e.name, entry.key_ptr.*)) {
                    if (e.tx != tx) changed = true;
                    break;
                }
            }
        }
        if (changed) fresh.append(allocator, entry.key_ptr.*) catch {
            c.bail = true;
            return;
        };
    }
    if (fresh.items.len == 0) return;
    std.mem.sort([]const u8, fresh.items, {}, lessThanStr);

    for (fresh.items) |name| {
        const v = lib_env.get(name) orelse continue;
        const tx = types.toObject(v).as(types.Transformer);
        if (c.events.items.len >= bf.MAX_LIBRARY_EVENTS) {
            c.bail = true;
            return;
        }
        const owned_name = allocator.dupe(u8, name) catch {
            c.bail = true;
            return;
        };
        c.events.append(allocator, .{ .register_tx = .{ .name = owned_name, .tx = tx } }) catch {
            allocator.free(owned_name);
            c.bail = true;
            return;
        };
    }
}

fn lessThanStr(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}

/// Record one compiled body form: append the function (rooting it for the
/// rest of the load) and its run event. `env_is_lib` distinguishes functions
/// compiled against lib_env (compileLibExpr) from those compiled against
/// vm.globals (evalIncludedForm, the include-in-begin path).
pub fn noteCompiledForm(vm: *VM, func: *Function, env_is_lib: bool) void {
    const c = top(vm) orelse return;
    if (!c.armed or c.warm != null) return;
    const allocator = vm.gc.allocator;
    if (c.funcs.items.len >= bf.MAX_TOP_LEVEL_FUNCTIONS or c.events.items.len >= bf.MAX_LIBRARY_EVENTS) {
        c.bail = true;
        return;
    }
    // Root for the load's duration: the compile's own extra_roots entry was
    // shrunk away when compileExpressionInEnv returned, and an unrooted
    // collected function is exactly the GC use-after-free that disabled the
    // original cache attempt (kaappi#1888's hazard 1).
    vm.gc.extra_roots.append(allocator, types.makePointer(&func.header)) catch {
        c.bail = true;
        return;
    };
    c.funcs.append(allocator, func) catch {
        c.bail = true;
        return;
    };
    const idx: u32 = @intCast(c.funcs.items.len - 1);
    c.events.append(allocator, if (env_is_lib) .{ .run_lib = idx } else .{ .run_global = idx }) catch {
        c.bail = true;
    };
}

/// Note that compiling a form grew a compile-time registration table the event
/// log cannot replay (vm.macros / vm.syntax_properties — the #2112 class).
pub fn noteCompileSideEffect(c: *LibCollector) void {
    c.bail = true;
}

// ---------------------------------------------------------------------------
// Warm replay
// ---------------------------------------------------------------------------

/// Point a deserialized form function — and every nested function reachable
/// through its constants — at the environment it was compiled against. The
/// cold path bakes `env` onto every nested function via Compiler.initChild;
/// the codec does not carry it, so replay restores it for the whole tree.
/// `env == null` (globals-compiled include forms) clears it the same way.
fn applyEnvToTree(gc: *memory.GC, func: *Function, env: ?*std.StringHashMap(Value)) VMError!void {
    var seen = std.AutoHashMap(usize, void).init(gc.allocator);
    defer seen.deinit();
    applyEnvToTreeInner(gc, func, env, &seen) catch return VMError.OutOfMemory;
}

fn applyEnvToTreeInner(gc: *memory.GC, func: *Function, env: ?*std.StringHashMap(Value), seen: *std.AutoHashMap(usize, void)) !void {
    // A function reached twice (shared constant) is only walked once; the
    // guard also terminates constant cycles.
    try seen.put(@intFromPtr(func), {});
    func.env = env;
    func.env_val = types.NIL;
    if (env != null) func.restricted_globals = false;
    for (func.constants.items) |c| {
        if (types.isPointer(c) and types.toObject(c).tag == .function) {
            const child = types.toObject(c).as(Function);
            if (seen.contains(@intFromPtr(child))) continue;
            try applyEnvToTreeInner(gc, child, env, seen);
        }
    }
}

/// Consume the events belonging to one body form — the registrations its
/// compilation performed, then its run — from the cursor. Called by
/// compileLibExpr where the cold path compiles.
pub fn replayForm(vm: *VM, lib_env: *std.StringHashMap(Value), c: *LibCollector) VMError!void {
    if (c.replay_desync) return;
    const cur = &(c.warm orelse return VMError.CompileError);

    // Registrations first, matching the cold compile-then-run order.
    while (true) {
        const ev = cur.peek() orelse break;
        if (ev != .register_tx) break;
        const reg = ev.register_tx;
        var tx_val = types.makePointer(&reg.tx.header);
        vm.gc.pushRoot(&tx_val);
        defer vm.gc.popRoot();
        // The reconstructed lib_env is exactly what def_env must point at
        // (#1962: registry-rooted, so def_env_val stays NIL like the cold
        // path's own library transformers).
        reg.tx.def_env = lib_env;
        reg.tx.def_env_val = types.NIL;
        // The map key's bytes must outlive the entry's event records (freed
        // when the collector pops): intern the name so the slice points into
        // the GC-owned symbol table, exactly like every cold-path lib_env key.
        const interned_name = types.symbolName(vm.gc.allocSymbol(reg.name) catch return VMError.OutOfMemory);
        lib_env.put(interned_name, tx_val) catch return VMError.OutOfMemory;
        cur.pos += 1;
    }

    const ev = cur.peek() orelse {
        c.replay_desync = true;
        vm.setErrorDetail("library cache: event log exhausted before a compiled form", .{});
        return VMError.CompileError;
    };
    if (ev != .run_lib and ev != .run_global) {
        c.replay_desync = true;
        vm.setErrorDetail("library cache: event log desync (expected a compiled-form event)", .{});
        return VMError.CompileError;
    }
    const idx = if (ev == .run_lib) ev.run_lib else ev.run_global;
    if (idx >= cur.top_level_count or idx >= cur.funcs.len) {
        c.replay_desync = true;
        vm.setErrorDetail("library cache: event references a function outside the table", .{});
        return VMError.CompileError;
    }
    const func = cur.funcs[idx];
    if (ev == .run_lib) {
        try applyEnvToTree(vm.gc, func, lib_env);
    } else {
        try applyEnvToTree(vm.gc, func, null);
    }
    cur.pos += 1;
    _ = try vm.runTopLevelFunction(func);
}

/// The evalIncludedForm half of replay: an include-contributed form compiled
/// against vm.globals. No transformer registrations can precede these events
/// (a define-syntax there grows vm.macros, which bails the entry), so exactly
/// one run_global event is expected.
pub fn replayGlobalForm(vm: *VM, c: *LibCollector) VMError!void {
    if (c.replay_desync) return;
    const cur = &(c.warm orelse return VMError.CompileError);
    const ev = cur.peek() orelse {
        c.replay_desync = true;
        vm.setErrorDetail("library cache: event log exhausted before an included form", .{});
        return VMError.CompileError;
    };
    if (ev != .run_global) {
        c.replay_desync = true;
        vm.setErrorDetail("library cache: event log desync (expected an included-form event)", .{});
        return VMError.CompileError;
    }
    const idx = ev.run_global;
    if (idx >= cur.top_level_count or idx >= cur.funcs.len) {
        c.replay_desync = true;
        vm.setErrorDetail("library cache: event references a function outside the table", .{});
        return VMError.CompileError;
    }
    const func = cur.funcs[idx];
    try applyEnvToTree(vm.gc, func, null);
    cur.pos += 1;
    _ = try vm.runTopLevelFunction(func);
}

/// Validate an entry's include and dependency records against the live
/// filesystem. Pure reads — no loading, no VM state touched — so a mismatch
/// is an ordinary miss that falls back to a cold load with nothing partial
/// having happened. Shared by the library and program entry kinds.
pub fn recordsValid(vm: *VM, includes: []const bf.IncludeRecord, deps: []const bf.DepRecord) bool {
    const file_utils = @import("file_utils.zig");
    const allocator = vm.gc.allocator;

    for (includes) |inc| {
        const content = file_utils.readWholeFile(allocator, inc.path, 4 * 1024 * 1024) catch return false;
        defer allocator.free(content);
        if (bf.sourceHash(content) != inc.hash) return false;
    }
    for (deps) |dep| {
        // Re-resolve through the CURRENT lib-path: a --lib-path change that
        // now resolves the same library name elsewhere must miss, even if the
        // old file is still sitting there unchanged.
        const resolved = vm_library.resolveLibraryPath(allocator, dep.rel_path, vm.lib_paths) orelse return false;
        defer allocator.free(resolved);
        if (!std.mem.eql(u8, resolved, dep.resolved_path)) return false;
        const content = file_utils.readWholeFile(allocator, resolved, 4 * 1024 * 1024) catch return false;
        defer allocator.free(content);
        if (bf.sourceHash(content) != dep.source_hash) return false;
    }
    return true;
}

/// Remove the GC roots of exactly the objects a deserialized entry introduced
/// — its functions and transformers — BY POINTER, never by truncation: the
/// load's own body execution may have appended longer-lived roots above them
/// (a fiber kept alive until thread-join!, a rootedSlot eval-cache entry),
/// and endColdLoad's own rule is the same. Live objects stay reachable
/// through the registered library (lib_env values, transformers and their
/// procs); the executed top-level form wrappers are garbage now, exactly like
/// the cold path's collected functions after endColdLoad (#1888 review).
pub fn dropDeserializeRoots(gc: *memory.GC, result: *const bf.DeserializeResult) void {
    const allocator = gc.allocator;
    var remove = std.AutoHashMap(usize, void).init(allocator);
    defer remove.deinit();
    for (result.funcs) |f| remove.put(@intFromPtr(f), {}) catch return;
    if (result.library) |lib| {
        for (lib.events) |ev| {
            if (ev == .register_tx) remove.put(@intFromPtr(ev.register_tx.tx), {}) catch return;
        }
    }
    if (remove.count() == 0) return;
    var out_i: usize = 0;
    for (gc.extra_roots.items) |root| {
        if (types.isPointer(root) and remove.contains(@intFromPtr(types.toObject(root)))) continue;
        gc.extra_roots.items[out_i] = root;
        out_i += 1;
    }
    gc.extra_roots.shrinkRetainingCapacity(out_i);
}

/// Begin serving a library load from the cache: read the entry, validate its
/// include/dependency records, and push a replay cursor. Returns true when the
/// caller should proceed by running `loadLibrarySource` unchanged (the cursor
/// makes compileLibExpr replay instead of compile) and then `endWarmLoad`.
/// False is an ordinary miss — nothing has happened yet, cold load away.
pub fn beginWarmLoad(vm: *VM, source_hash: u64, sld_path: []const u8) bool {
    if (!libCacheEnabled(vm)) return false;
    const allocator = vm.gc.allocator;
    const sbc_path = cache.pathForLibrary(allocator, sld_path) orelse return false;
    defer allocator.free(sbc_path);

    const loaded = (bf.readFileWithTopLevel(vm.gc, source_hash, sbc_path) catch null) orelse {
        timings.libCacheMiss();
        return false;
    };
    var result = loaded;
    // Every fall-through below is a miss: free the host-side sections and drop
    // the deserialize roots by pointer (the deserializer rooted the functions
    // and transformers; leaving them pinned would collect garbage for the
    // process lifetime, one stale body per stale entry — #1888 review).
    const miss = struct {
        fn f(vm2: *VM, res: *bf.DeserializeResult, stale: bool) bool {
            // Roots first: freeDeserializeResult resets the pointer fields
            // dropDeserializeRoots walks.
            dropDeserializeRoots(vm2.gc, res);
            bf.freeDeserializeResult(vm2.gc.allocator, res);
            if (stale) timings.libCacheStale() else timings.libCacheMiss();
            return false;
        }
    };

    // Kind check both ways: a LIBRARY entry shares its cache key with running
    // the .sld directly, and a PROGRAM entry cannot be replayed as a library.
    if (result.library == null or result.entry_kind != bf.ENTRY_LIBRARY) {
        return miss.f(vm, &result, false);
    }
    const lib = &result.library.?;

    if (!recordsValid(vm, result.includes orelse &.{}, result.deps orelse &.{})) {
        return miss.f(vm, &result, true);
    }

    // No source_name assignment: the cold path's library functions carry none
    // (compileLibExpr compiles without one), and the `sld_path` slice here is
    // freed long before the closures this replay creates stop running.

    const pushed = push(vm, .{ .armed = false, .warm = .{
        .events = lib.events,
        .funcs = result.funcs,
        .top_level_count = result.top_level_count,
    }, .warm_result = result });
    if (!pushed) {
        // pop() balances the overflow depth marker push() left behind —
        // without it every enclosing load's collector shifts by one frame
        // and their endColdLoad early-returns skip both the cache write and
        // the by-pointer root removal (#1888 review).
        pop(vm);
        return miss.f(vm, &result, false); // nesting too deep: cold path
    }
    return true;
}

/// Finish a warm replay after `loadLibrarySource` succeeded. Errors loudly on
/// an unconsumed event log — the hashes validated by beginWarmLoad make a
/// desync near-impossible, so it indicates a loader/serializer bug and must
/// never pass silently. Every path out of here pops the collector frame
/// (#1888 review: a leaked frame shifts every enclosing load's collector).
pub fn endWarmLoad(vm: *VM, sld_path: []const u8, rel_path: []const u8, source_hash: u64, lib_name: []const u8) VMError!void {
    const depth = vm.lib_cache_depth;
    if (depth == 0 or depth > vm.lib_cache_stack.len) return; // overflowed frame
    const c = &vm.lib_cache_stack[depth - 1];
    const desync = c.replay_desync or (c.warm != null and c.warm.?.pos != c.warm.?.events.len);
    const result_ptr: ?*bf.DeserializeResult = if (c.warm_result) |*wr| wr else null;

    // Roots before pop: the collector's deinit frees (and resets) the result
    // the root walk reads.
    if (result_ptr) |rp| dropDeserializeRoots(vm.gc, rp);

    if (desync) {
        // Structure and log disagree. The validated source/include/dep
        // equality makes this near-impossible, so it indicates a
        // loader/serializer bug — loud, never silent.
        pop(vm);
        vm.setErrorDetail("library cache: replay event log desync for {s}", .{sld_path});
        return VMError.CompileError;
    }

    timings.libCacheHit();
    // Record the dependency for the MAIN run's entry, inheriting the entry's
    // own include/dependency records (#1888 review): a program's slots embed
    // this library's macro expansions, and those can change through an edit
    // to any file in the library's transitive closure, not just its .sld.
    noteRunDep(vm, rel_path, sld_path, source_hash, lib_name);
    if (result_ptr) |rp| {
        inheritRunIncludes(vm, rp.includes orelse &.{});
        inheritRunDeps(vm, rp.deps orelse &.{});
    }
    pop(vm);
}

/// Abort a warm replay that failed mid-load (body error etc.). The entry's
/// working state is freed; the deserialize roots are dropped by pointer (the
/// partially built library is unreachable garbage, same as a failed cold
/// load).
pub fn abortWarmLoad(vm: *VM) void {
    const depth = vm.lib_cache_depth;
    if (depth == 0) return;
    if (depth <= vm.lib_cache_stack.len) {
        const c = &vm.lib_cache_stack[depth - 1];
        const result_ptr: ?*bf.DeserializeResult = if (c.warm_result) |*wr| wr else null;
        if (result_ptr) |rp| dropDeserializeRoots(vm.gc, rp);
        pop(vm);
    } else {
        pop(vm);
    }
}

// ---------------------------------------------------------------------------
// Program-run dependency recording (called from runFile via the load hooks)
// ---------------------------------------------------------------------------

/// A program's compiled slots embed imported-macro expansions, exactly like a
/// library body's — so its cache entry must carry the same include/dependency
/// records and stale on the same edits (#1888 review). The recorder is
/// VM-level rather than collector-stack-level because the "run" whose deps we
/// want is the main file's, not whichever .sld happens to be loading.
pub fn beginRunRecording(vm: *VM) void {
    clearRunRecords(vm);
    vm.run_cache_ok = true;
}

/// The program run can no longer be cached correctly: some dependency is
/// unrecordable (a library that declined or could not write its entry), so a
/// program entry would serve stale compiled slots forever. runFile declines.
pub fn runCacheOk(vm: *VM) bool {
    return vm.run_cache_ok;
}

pub fn noteRunPoison(vm: *VM) void {
    vm.run_cache_ok = false;
}

/// Fold a loaded library's own include records into the run's — the program's
/// slots transitively depend on every file in the library's closure, and the
/// library's records already validated exactly that set (#1888 review).
fn inheritRunIncludes(vm: *VM, includes: []const bf.IncludeRecord) void {
    const allocator = vm.gc.allocator;
    for (includes) |inc| {
        var dup = false;
        for (vm.run_cache_includes.items) |existing| {
            if (std.mem.eql(u8, existing.path, inc.path)) {
                dup = true;
                break;
            }
        }
        if (dup) continue;
        if (vm.run_cache_includes.items.len >= bf.MAX_LIBRARY_INCLUDES) continue;
        const owned = allocator.dupe(u8, inc.path) catch return;
        vm.run_cache_includes.append(allocator, .{ .path = owned, .hash = inc.hash }) catch {
            allocator.free(owned);
        };
    }
}

/// Fold a loaded library's own dependency records into the run's (dedup by
/// canonical library name, as everywhere else).
fn inheritRunDeps(vm: *VM, deps: []const bf.DepRecord) void {
    for (deps) |dep| {
        noteRunDep(vm, dep.rel_path, dep.resolved_path, dep.source_hash, dep.lib_name);
    }
}

/// Free whatever the run recorder holds (end of runFile either way).
pub fn clearRunRecords(vm: *VM) void {
    const allocator = vm.gc.allocator;
    for (vm.run_cache_deps.items) |dep| {
        allocator.free(@constCast(dep.rel_path));
        allocator.free(@constCast(dep.resolved_path));
        allocator.free(@constCast(dep.lib_name));
    }
    vm.run_cache_deps.clearRetainingCapacity();
    for (vm.run_cache_includes.items) |inc| allocator.free(@constCast(inc.path));
    vm.run_cache_includes.clearRetainingCapacity();
}

pub fn deinitRunRecords(vm: *VM) void {
    clearRunRecords(vm);
    const allocator = vm.gc.allocator;
    vm.run_cache_deps.deinit(allocator);
    vm.run_cache_includes.deinit(allocator);
}

/// Record a file-backed library the program's run resolved and read — every
/// load, cold or warm, registry short-circuit or disk (the hook sites).
/// Deduplicated by canonical library name.
pub fn noteRunDep(vm: *VM, rel_path: []const u8, resolved_path: []const u8, source_hash: u64, lib_name: []const u8) void {
    const allocator = vm.gc.allocator;
    for (vm.run_cache_deps.items) |dep| {
        if (std.mem.eql(u8, dep.lib_name, lib_name)) return;
    }
    if (vm.run_cache_deps.items.len >= bf.MAX_LIBRARY_DEPS) return;
    const rel = allocator.dupe(u8, rel_path) catch return;
    const res = allocator.dupe(u8, resolved_path) catch {
        allocator.free(rel);
        return;
    };
    const name = allocator.dupe(u8, lib_name) catch {
        allocator.free(rel);
        allocator.free(res);
        return;
    };
    vm.run_cache_deps.append(allocator, .{ .rel_path = rel, .resolved_path = res, .source_hash = source_hash, .lib_name = name }) catch {
        allocator.free(rel);
        allocator.free(res);
        allocator.free(name);
    };
}

/// Record an include-family file the MAIN file's structure opened (top-level
/// include/include-ci — the ones whose macros a later compiled form can
/// embed). Library-load includes are covered by that library's own entry.
pub fn noteRunInclude(vm: *VM, path: []const u8, content: []const u8) void {
    const allocator = vm.gc.allocator;
    for (vm.run_cache_includes.items) |inc| {
        if (std.mem.eql(u8, inc.path, path)) return;
    }
    if (vm.run_cache_includes.items.len >= bf.MAX_LIBRARY_INCLUDES) return;
    const owned = allocator.dupe(u8, path) catch return;
    vm.run_cache_includes.append(allocator, .{ .path = owned, .hash = bf.sourceHash(content) }) catch {
        allocator.free(owned);
    };
}

// ---------------------------------------------------------------------------
// Cold-load orchestration (called from tryLoadLibraryFromFile)
// ---------------------------------------------------------------------------

/// Arm a collector for a cold load about to start.
pub fn beginColdLoad(vm: *VM) void {
    if (!libCacheEnabled(vm)) return;
    _ = push(vm, .{ .armed = true });
}

/// Finish a cold load: serialize and write the entry (unless the load failed,
/// bailed, or there is nowhere to put it), then drop the roots the collector
/// added. `ok` is whether `loadLibrarySource` succeeded — a failed load
/// writes nothing (a HIT would otherwise run a partial library).
pub fn endColdLoad(vm: *VM, ok: bool, source_hash: u64, sld_path: []const u8, rel_path: []const u8, lib_name: []const u8) void {
    const allocator = vm.gc.allocator;
    const depth = vm.lib_cache_depth;
    if (depth == 0 or depth > vm.lib_cache_stack.len) {
        if (depth > 0) pop(vm); // balance an overflowed frame
        return;
    }
    const c = &vm.lib_cache_stack[depth - 1];
    const armed = c.armed and c.warm == null;

    if (armed and ok and !c.bail) {
        if (cache.pathForLibrary(allocator, sld_path)) |sbc_path| {
            defer allocator.free(sbc_path);
            cache.ensureDir();
            if (bf.writeFileWithLibrary(allocator, c.funcs.items, c.events.items, c.includes.items, c.deps.items, source_hash, sld_path, sbc_path)) |_| {
                timings.libCacheWrote();
                // Record the dependency for the MAIN run's entry, inheriting
                // this library's own include/dependency records (#1888
                // review): a program's slots embed this library's macro
                // expansions, which can change through an edit to any file
                // in the transitive closure.
                noteRunDep(vm, rel_path, sld_path, source_hash, lib_name);
                inheritRunIncludes(vm, c.includes.items);
                inheritRunDeps(vm, c.deps.items);
            } else |err| switch (err) {
                error.LimitExceeded => timings.libCacheReason("library exceeds .sbc limits"),
                error.UnsupportedConstant => timings.libCacheReason("library constant unrepresentable"),
                else => {},
            }
        } else {
            // Nowhere to put the entry: the program entry cannot record this
            // dependency, so it must decline rather than serve stale slots.
            noteRunPoison(vm);
        }
    } else if (armed and ok) {
        timings.libCacheReason("library not cacheable");
        // The library is deliberately uncached (a compile-time side effect or
        // an availability-dependent cond-expand): no entry will ever validate
        // its content, so a program entry that embedded its expansions would
        // be permanently stale — the program run must decline too.
        noteRunPoison(vm);
    } else if (armed and !ok) {
        // The load failed; the caller reports the error. No run records.
    }

    // Remove exactly this load's function roots (by pointer), never by
    // truncation: rootedSlot's permanent entries interleave in the same list.
    if (c.funcs.items.len > 0) {
        var remove = std.AutoHashMap(usize, void).init(allocator);
        defer remove.deinit();
        for (c.funcs.items) |f| {
            remove.put(@intFromPtr(f), {}) catch break;
        }
        var out_i: usize = 0;
        for (vm.gc.extra_roots.items) |root| {
            if (types.isPointer(root) and types.toObject(root).tag == .function) {
                if (remove.contains(@intFromPtr(types.toObject(root).as(Function)))) continue;
            }
            vm.gc.extra_roots.items[out_i] = root;
            out_i += 1;
        }
        vm.gc.extra_roots.shrinkRetainingCapacity(out_i);
    }

    pop(vm);
}
