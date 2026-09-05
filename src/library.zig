const std = @import("std");
const is_wasm = @import("builtin").os.tag == .wasi;
const is_windows = @import("builtin").os.tag == .windows;
const types = @import("types.zig");
const Value = types.Value;

/// A Scheme library: a named set of exported bindings.
pub const Library = struct {
    name: []const u8, // canonical name like "scheme.base"
    owned_name: ?[]const u8, // if non-null, this is a heap-allocated name to free
    exports: std.StringHashMap(Value),
    lib_env: ?*std.StringHashMap(Value) = null, // per-library environment (heap-allocated)
    /// Provenance for file-backed libraries (kaappi#1888 review): the
    /// resolved .sld this library was loaded from, and its content hash.
    /// Lets an importer that finds the library already in the registry still
    /// record it as a cache dependency — without this, `(a)` loaded by an
    /// earlier import and `(b)` importing `(a)` later would leave `(b)`'s
    /// entry with no record of `(a)`, and editing `(a)`'s macros would serve
    /// `(b)`'s stale expansions. Null for built-in/registered-in-code
    /// libraries.
    source_path: ?[]const u8 = null,
    source_hash: u64 = 0,
    allocator: std.mem.Allocator,

    /// Create a library with a borrowed name (string literal or other static string).
    pub fn init(allocator: std.mem.Allocator, name: []const u8) Library {
        return .{
            .name = name,
            .owned_name = null,
            .exports = std.StringHashMap(Value).init(allocator),
            .allocator = allocator,
        };
    }

    /// Create a library with an owned (heap-allocated) name.
    pub fn initOwned(allocator: std.mem.Allocator, name: []const u8) Library {
        return .{
            .name = name,
            .owned_name = name,
            .exports = std.StringHashMap(Value).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Library) void {
        self.exports.deinit();
        if (self.lib_env) |env| {
            env.deinit();
            self.allocator.destroy(env);
        }
        if (self.source_path) |sp| {
            self.allocator.free(sp);
        }
        if (self.owned_name) |owned| {
            self.allocator.free(owned);
        }
    }

    pub fn addExport(self: *Library, name: []const u8, value: Value) !void {
        try self.exports.put(name, value);
    }
};

/// Registry mapping canonical library name strings to Library instances.
pub const LibraryRegistry = struct {
    allocator: std.mem.Allocator,
    libraries: std.StringHashMap(Library),
    /// Environments of replaced libraries. Closures compiled in a library's
    /// begin block hold `Function.env` pointers to its lib_env and can
    /// outlive the library (escaping via import into vm.globals), so a
    /// replaced env must stay alive until the registry is torn down (#820).
    retired_envs: std.ArrayList(*std.StringHashMap(Value)) = .empty,
    /// Pristine values of the `.internal` primitives (`primitives.Lib.internal`),
    /// captured at startup from vm.globals and never written again — the same
    /// "snapshot before any user code runs" role `scheme.base`'s export table
    /// plays for `lookupBaseBinding` (#1715). Compiler-synthesized references
    /// resolve through it via `Compiler.trueBuiltinRefOrSymbol`, so
    /// `define-record-type`, `case-lambda`, `parameterize`, and `delay` keep
    /// working in a scope that binds `%record-ref` (or any other helper name)
    /// to something of its own (#1856).
    ///
    /// A separate table rather than one more `Library` because the two answer
    /// different questions: a `Library` is what `import` hands to a program,
    /// this is what the compiler resolves against. Some of these names *are*
    /// also exported, by `(kaappi primitives)`, for the portable `.sld`s that
    /// call them from Scheme source — that export is the program-facing half
    /// and has nothing to do with this snapshot.
    internal_bindings: std.StringHashMap(Value),
    /// The pristine `(scheme base)` primitive behind each name in
    /// `fast_path_builtins`, snapshotted at registration (kaappi#2469). The
    /// `guard_builtin` opcode and the native tier's
    /// `kaappi_builtin_is_pristine` compare a call site's *current* global
    /// binding against this entry at run time — which is what lets a
    /// top-level redefinition from a later form, `load`, `eval`, the REPL, or
    /// a macro-materialized `set!` reach bodies compiled before it ran. VOID
    /// when the primitive was never registered (a sandbox that excludes it);
    /// a guard then never takes its fast path. Root-marked by `markVmRoots`,
    /// since a redefinition drops the object from `globals`.
    fast_path_pristine: [fast_path_builtins.len]Value = [_]Value{types.VOID} ** fast_path_builtins.len,

    pub fn init(allocator: std.mem.Allocator) LibraryRegistry {
        return .{
            .allocator = allocator,
            .libraries = std.StringHashMap(Library).init(allocator),
            .internal_bindings = std.StringHashMap(Value).init(allocator),
        };
    }

    pub fn deinit(self: *LibraryRegistry) void {
        var it = self.libraries.valueIterator();
        while (it.next()) |lib| {
            lib.deinit();
        }
        self.libraries.deinit();
        self.internal_bindings.deinit();
        for (self.retired_envs.items) |env| {
            env.deinit();
            self.allocator.destroy(env);
        }
        self.retired_envs.deinit(self.allocator);
    }

    /// Register a new library (or replace an existing one).
    pub fn register(self: *LibraryRegistry, lib: Library) !void {
        const gop = try self.libraries.getOrPut(lib.name);
        if (gop.found_existing) {
            if (gop.value_ptr.lib_env) |env| {
                try self.retired_envs.append(self.allocator, env);
                gop.value_ptr.lib_env = null;
            }
            gop.value_ptr.deinit();
            gop.key_ptr.* = lib.name;
        }
        gop.value_ptr.* = lib;
    }

    /// Detach the entry registered under `name` without retiring or freeing
    /// anything (#2518 review of #2510): ownership of the whole `Library`
    /// (exports table, `lib_env`, name) moves to the caller, who must
    /// eventually re-register it (`restore`) or release it
    /// (`releaseDetached`). The map entry is removed, so a subsequent
    /// `register` of the same name is a plain insert — its replacement
    /// branch never sees, and never destroys, the detached entry. Null when
    /// `name` is not registered.
    ///
    /// Same cross-thread hazard as `unregister` (see below): this mutates
    /// the shared `libraries` map while another thread may hold a `*Library`
    /// from `get`/`processImportSet`.
    pub fn take(self: *LibraryRegistry, name: []const u8) ?Library {
        const entry = self.libraries.getEntry(name) orelse return null;
        const lib = entry.value_ptr.*;
        _ = self.libraries.remove(name);
        return lib;
    }

    /// Put back a library a failed load displaced (#2518 review of #2510).
    /// When the displaced name still holds the load's replacement — the
    /// rollback journal's LIFO order guarantees it does — the slot is
    /// reclaimed in place: the key already exists, so no map growth (and no
    /// allocation) can fail there, and the prior is back in the registry
    /// *before* anything is freed. The replacement is then released exactly
    /// as `unregister` releases an entry: `lib_env` retired per #820
    /// (closures from the failed load's begin blocks can escape and keep
    /// `Function.env` pointers into it), exports and owned name freed. If
    /// the name is somehow not registered (an insert would have to grow the
    /// map), the prior is released instead — the name stays unregistered,
    /// the same re-loadable state a plain rollback leaves, never a
    /// half-restored entry.
    pub fn restore(self: *LibraryRegistry, prior: Library) void {
        const p = prior;
        if (self.libraries.getEntry(p.name)) |entry| {
            var repl = entry.value_ptr.*;
            // Swap the key before freeing anything: it aliases the
            // replacement's owned name, the value slot before that holds
            // the replacement itself.
            entry.key_ptr.* = p.name;
            entry.value_ptr.* = p;
            if (repl.lib_env) |env| {
                repl.lib_env = null;
                self.retired_envs.append(self.allocator, env) catch {};
            }
            repl.deinit();
            return;
        }
        self.libraries.put(p.name, p) catch self.releaseDetached(p);
    }

    /// Release a detached `Library` (a displaced prior whose replacement
    /// committed, or one that cannot be put back): `lib_env` is retired per
    /// #820 — closures compiled in its begin blocks may still hold
    /// `Function.env` pointers into it — and everything else is freed.
    /// Exactly what `register`'s replacement branch does to a displaced
    /// entry, split out so the rollback journal can do it at commit time.
    pub fn releaseDetached(self: *LibraryRegistry, lib: Library) void {
        var l = lib;
        if (l.lib_env) |env| {
            l.lib_env = null;
            self.retired_envs.append(self.allocator, env) catch {};
        }
        l.deinit();
    }

    /// Remove a library the loader registered during a load that then failed
    /// (kaappi#2510). Dispatching a well-formed `define-library` registers the
    /// library before the reader reaches a later read error in the same .sld;
    /// without removal, the next import's registry short-circuit would serve
    /// that half-loaded library as a success. The `Library` is deinit'd the
    /// same way a replaced one is, with one #820 accommodation: `lib_env` is
    /// retired rather than destroyed, because closures compiled in the failed
    /// load's begin blocks can escape into live structures and keep raw
    /// `Function.env` pointers into it. The exports table dies with the entry
    /// — on a failed load nothing was imported from it yet (importing happens
    /// only after the load reports success). A name that is no longer
    /// registered is a no-op. This is the right undo only for a load that
    /// created the entry; a load that REPLACED an existing registration must
    /// `restore` the displaced prior instead, or the previously-good entry
    /// would be destroyed with the replacement (#2518 review).
    ///
    /// Cross-thread hazard (#2518 review): `VM.initForThread` struct-copies
    /// the registry into SRFI-18 child VMs, so `libraries` and `retired_envs`
    /// are shared across threads. A failed load in one thread invoking this
    /// races another thread holding a `*Library` from `get` or
    /// `processImportSet`'s registry short-circuit: the map removal, the
    /// `retired_envs` append (which can realloc), and the `deinit` all mutate
    /// storage that thread may be reading or pointing into.
    /// `register`-replacement already carried this hazard class; `unregister`
    /// (and `take`/`restore`, which additionally hold a detached entry
    /// outside the map — invisible to the owning GC's root walk) are the
    /// first shared mutators that deinit a Library another thread can hold.
    /// See docs/dev/thread-value-sharing.md, "Library registry mutation
    /// across threads".
    pub fn unregister(self: *LibraryRegistry, name: []const u8) void {
        const entry = self.libraries.getEntry(name) orelse return;
        var lib = entry.value_ptr.*;
        // Retire before removing: the append can collect, and until the map
        // entry is gone it keeps the env (and exports) marked; after the
        // append, retired_envs does. An append failure (OOM) leaks the env
        // deliberately — freeing it would dangle the Function.env pointers
        // above.
        if (lib.lib_env) |env| {
            lib.lib_env = null;
            self.retired_envs.append(self.allocator, env) catch {};
        }
        // Remove before deinit: the map key aliases lib.owned_name, so once
        // deinit frees it nothing (not even remove's key comparison) may read
        // the entry again.
        _ = self.libraries.remove(name);
        lib.deinit();
    }

    /// Look up a library by canonical name.
    pub fn get(self: *LibraryRegistry, name: []const u8) ?*Library {
        return self.libraries.getPtr(name);
    }

    /// Check if a library with the given name exists.
    pub fn contains(self: *LibraryRegistry, name: []const u8) bool {
        return self.libraries.contains(name);
    }
};

const primitives_mod = @import("primitives.zig");
const Lib = primitives_mod.Lib;
const LS = primitives_mod.LibSet;

const ExtraExport = struct { name: []const u8, libs: LS };

const extra_exports = [_]ExtraExport{
    .{ .name = "current-input-port", .libs = LS.initMany(&.{ .scheme_base, .scheme_r5rs }) },
    .{ .name = "current-output-port", .libs = LS.initMany(&.{ .scheme_base, .scheme_r5rs }) },
    .{ .name = "current-error-port", .libs = LS.initOne(.scheme_base) },
    .{ .name = "owner/unchanged", .libs = LS.initOne(.srfi_170) },
    .{ .name = "group/unchanged", .libs = LS.initOne(.srfi_170) },
};

fn addExportsForLib(library: *Library, lib: Lib, globals: *std.StringHashMap(Value), sandboxed: bool) !void {
    for (&primitives_mod.all_specs) |spec| {
        if (spec.libs.contains(lib) and (!sandboxed or spec.sandbox)) {
            if (globals.get(spec.name)) |val| {
                try library.addExport(spec.name, val);
            }
        }
    }
    for (&extra_exports) |extra| {
        if (extra.libs.contains(lib)) {
            if (globals.get(extra.name)) |val| {
                try library.addExport(extra.name, val);
            }
        }
    }
}

/// Standard libraries registered by name but with no Zig-primitive exports of
/// their own: their bindings are syntax already present in scheme.base
/// (`define-record-type` for srfi.9, `case-lambda` for scheme.case-lambda), so
/// the library object is just an importable handle. Kept as one list so the
/// normal and sandboxed registrars can't drift, and so `kaappi features` can
/// enumerate the built-in SRFIs (the `srfi.*` entries here plus the `srfi_*`
/// tags of `Lib`) without a second hardcoded list. All entries are pure syntax,
/// hence safe under `--sandbox` and on WASM.
pub const extra_std_libraries = [_][]const u8{ "scheme.case-lambda", "srfi.9" };

/// The names whose calls the compiler lowers to a superinstruction —
/// `apply` and `call-with-values` in any position, `call/cc`,
/// `call-with-current-continuation` and `eval` in tail position — and the
/// `kind` operand of the `guard_builtin` opcode that gates each one
/// (kaappi#2469). The index is part of the bytecode encoding and of the
/// native tier's `kaappi_builtin_is_pristine` ABI: append, never reorder.
pub const fast_path_builtins = [_][]const u8{ "apply", "call-with-values", "call/cc", "call-with-current-continuation", "eval" };

/// `name`'s index in `fast_path_builtins`, or null for any other name.
pub fn fastPathKind(name: []const u8) ?u8 {
    for (fast_path_builtins, 0..) |candidate, i| {
        if (std.mem.eql(u8, candidate, name)) return @intCast(i);
    }
    return null;
}

/// Snapshot the `.internal` primitives into `registry.internal_bindings` —
/// see that field for why they live outside `libraries` (#1856). Runs from
/// both registrars, since compiler-synthesized code needs these under
/// `--sandbox` too; `registerSandboxed` only puts `spec.sandbox` primitives
/// in globals, so a sandbox-excluded one is simply absent here as well.
fn snapshotInternalBindings(registry: *LibraryRegistry, globals: *std.StringHashMap(Value)) !void {
    for (&primitives_mod.all_specs) |spec| {
        if (!spec.libs.contains(.internal)) continue;
        if (globals.get(spec.name)) |val| {
            try registry.internal_bindings.put(spec.name, val);
        }
    }
    // The run-time gate's reference values (kaappi#2469): whatever the
    // registrar just bound each fast-path name to is, by definition, the
    // pristine primitive a guard compares against.
    for (fast_path_builtins, 0..) |name, i| {
        if (globals.get(name)) |val| registry.fast_path_pristine[i] = val;
    }
}

/// Register the standard R7RS libraries by deriving exports from spec tables.
pub fn registerStandardLibraries(registry: *LibraryRegistry, globals: *std.StringHashMap(Value)) !void {
    const allocator = registry.allocator;

    for (std.enums.values(Lib)) |lib| {
        if (!lib.isRegisterable()) continue;
        if ((!is_wasm or lib.wasmAvailable()) and (!is_windows or lib.windowsAvailable())) {
            var library = Library.init(allocator, lib.canonicalName());
            try addExportsForLib(&library, lib, globals, false);
            try registry.register(library);
        }
    }

    for (extra_std_libraries) |name| {
        try registry.register(Library.init(allocator, name));
    }

    try snapshotInternalBindings(registry, globals);
}

pub fn registerSandboxedLibraries(registry: *LibraryRegistry, globals: *std.StringHashMap(Value)) !void {
    const allocator = registry.allocator;

    for (std.enums.values(Lib)) |lib| {
        if (!lib.isRegisterable()) continue;
        if (!lib.sandboxAllowed()) continue;
        if ((!is_wasm or lib.wasmAvailable()) and (!is_windows or lib.windowsAvailable())) {
            var library = Library.init(allocator, lib.canonicalName());
            try addExportsForLib(&library, lib, globals, true);
            try registry.register(library);
        }
    }

    for (extra_std_libraries) |name| {
        try registry.register(Library.init(allocator, name));
    }

    try snapshotInternalBindings(registry, globals);
}

/// Convert a library name from an S-expression list like (scheme base) to
/// a canonical dot-separated string like "scheme.base".
///
/// The caller owns the returned slice and must free it with `allocator.free`.
pub fn libraryNameToString(allocator: std.mem.Allocator, name_list: Value) ![]const u8 {
    // First pass: calculate total length
    var total_len: usize = 0;
    var part_count: usize = 0;
    var current = name_list;
    while (current != types.NIL) {
        if (!types.isPair(current)) return error.InvalidSyntax;
        const part = types.car(current);
        if (types.isSymbol(part)) {
            total_len += types.symbolName(part).len;
        } else if (types.isFixnum(part)) {
            // Count digits needed for the number
            var buf: [20]u8 = undefined;
            const s = std.fmt.bufPrint(&buf, "{d}", .{types.toFixnum(part)}) catch return error.InvalidSyntax;
            total_len += s.len;
        } else {
            return error.InvalidSyntax;
        }
        part_count += 1;
        current = types.cdr(current);
    }

    if (part_count == 0) return error.InvalidSyntax;
    total_len += part_count - 1; // dots between parts

    // Second pass: build the string
    var result = try allocator.alloc(u8, total_len);
    var pos: usize = 0;
    var first = true;
    current = name_list;
    while (current != types.NIL) {
        if (!first) {
            result[pos] = '.';
            pos += 1;
        }
        first = false;
        const part = types.car(current);
        if (types.isSymbol(part)) {
            const name = types.symbolName(part);
            @memcpy(result[pos .. pos + name.len], name);
            pos += name.len;
        } else if (types.isFixnum(part)) {
            var buf: [20]u8 = undefined;
            const s = std.fmt.bufPrint(&buf, "{d}", .{types.toFixnum(part)}) catch return error.InvalidSyntax;
            @memcpy(result[pos .. pos + s.len], s);
            pos += s.len;
        }
        current = types.cdr(current);
    }

    return result;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "library name to string" {
    const memory = @import("memory.zig");
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();

    // (scheme base) -> "scheme.base"
    const base_sym = try gc.allocSymbol("base");
    const scheme_sym = try gc.allocSymbol("scheme");
    const name_list = try gc.allocPair(scheme_sym, try gc.allocPair(base_sym, types.NIL));

    const result = try libraryNameToString(std.testing.allocator, name_list);
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("scheme.base", result);
}

test "library registry basic" {
    var reg = LibraryRegistry.init(std.testing.allocator);
    defer reg.deinit();

    var lib = Library.init(std.testing.allocator, "test.lib");
    try lib.addExport("foo", types.makeFixnum(42));
    try reg.register(lib);

    const found = reg.get("test.lib");
    try std.testing.expect(found != null);
    const val = found.?.exports.get("foo");
    try std.testing.expect(val != null);
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(val.?));
}

// #2518 review of #2510: the primitives behind restore-on-rollback. A load
// that re-registers an existing library detaches the prior (`take`), lets the
// replacement register on the vacated key, and must put the prior back with
// its lib_env LIVE (back in the map, not retired) when the load fails —
// while a committed replacement releases the prior with its env retired
// (#820). Fixnum exports only; no GC, so the test exercises the ownership
// moves, not the marking.
test "registry take/restore/releaseDetached ownership (#2510 review)" {
    var reg = LibraryRegistry.init(std.testing.allocator);
    defer reg.deinit();

    // A prior with an env, like every define-library-built library has.
    var prior = Library.init(std.testing.allocator, "test.lib");
    try prior.addExport("old", types.makeFixnum(1));
    const prior_env = try std.testing.allocator.create(std.StringHashMap(Value));
    prior_env.* = std.StringHashMap(Value).init(std.testing.allocator);
    prior.lib_env = prior_env;
    try reg.register(prior);

    // Detach: the name is vacated, ownership moves to the caller.
    const detached = reg.take("test.lib").?;
    try std.testing.expect(reg.get("test.lib") == null);
    try std.testing.expect(detached.lib_env == prior_env);

    // The load's replacement registers on the vacated key.
    var repl = Library.init(std.testing.allocator, "test.lib");
    try repl.addExport("new", types.makeFixnum(2));
    try reg.register(repl);

    // Failed load: restore puts the prior back — old exports, env live in
    // the map (not retired), the replacement's exports gone.
    reg.restore(detached);
    const back = reg.get("test.lib").?;
    try std.testing.expect(back.exports.get("old") != null);
    try std.testing.expect(back.exports.get("new") == null);
    try std.testing.expect(back.lib_env == prior_env);
    try std.testing.expectEqual(@as(usize, 0), reg.retired_envs.items.len);

    // Committed replacement (the other fate): a detached prior is released
    // with its env retired, never freed live.
    const detached2 = reg.take("test.lib").?;
    reg.releaseDetached(detached2);
    try std.testing.expect(reg.get("test.lib") == null);
    try std.testing.expectEqual(@as(usize, 1), reg.retired_envs.items.len);
    try std.testing.expect(reg.retired_envs.items[0] == prior_env);
}

test "library name with number" {
    const memory = @import("memory.zig");
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();

    // (srfi 1) -> "srfi.1"
    const one_val = types.makeFixnum(1);
    const srfi_sym = try gc.allocSymbol("srfi");
    const name_list = try gc.allocPair(srfi_sym, try gc.allocPair(one_val, types.NIL));

    const result = try libraryNameToString(std.testing.allocator, name_list);
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("srfi.1", result);
}
