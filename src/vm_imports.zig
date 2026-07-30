//! R7RS import-set algebra, split out of vm_library.zig (file size policy):
//! resolving `(import ...)` sets — only / except / prefix / rename and plain
//! library references — into bindings merged into a target environment, plus
//! the transformer free-reference copying that has to ride along with every
//! imported macro. vm_library.zig keeps library definition, .sld loading,
//! SRFI 261 name normalization, include handling, and cond-expand feature
//! evaluation, and re-exports this file's entry points so callers still say
//! `vm_library.handleImport(...)`.

const std = @import("std");
const types = @import("types.zig");
const printer = @import("printer.zig");
const ir = @import("ir.zig");
const macro = @import("compiler_macro.zig");
const library_mod = @import("library.zig");
const vm_library = @import("vm_library.zig");
const vm_mod = @import("vm.zig");
const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Value = types.Value;

const libraryIsAvailable = vm_library.libraryIsAvailable;
const srfi261FormNumber = vm_library.srfi261FormNumber;
const importSrfi261Normalized = vm_library.importSrfi261Normalized;
const tryLoadLibraryFromFile = vm_library.tryLoadLibraryFromFile;
const buildLibRelPath = vm_library.buildLibRelPath;

/// Import a binding into the target environment, routing macros to vm.macros.
///
/// `chase_transitive` controls whether a transformer's free references are
/// additionally chased into `target` (see `copyTransformerFreeRefs`). Pass
/// `false` when `target` is a private, throwaway map used only to answer
/// "what does this import-set resolve to" (e.g. `resolveImportBindings`,
/// used by only/except/prefix/rename and by the #1726 collision check) --
/// chasing free references there does not merely waste work, it actively
/// leaks non-exported helper macros as if they were real exports, because
/// `copyTransformerFreeRefs` has no way to tell "a throwaway resolution map"
/// apart from "a real scope like lib_env that legitimately needs a
/// transitively-referenced helper macro to stay resolvable" (issue #877) --
/// both are simply `target != vm.globals` to it. Pass `true` only for the
/// single, final merge into a real target (vm.globals, a library's lib_env,
/// or an `environment` object).
fn importBinding(vm: *VM, target: *std.StringHashMap(Value), name: []const u8, val: Value, chase_transitive: bool) !void {
    if (target == vm.globals) {
        // Structural put into the shared globals map — exclude concurrent
        // child-thread readers (#958). Held only around the put; the
        // transformer recursion below takes the lock again per insert.
        vm.globals_lock.lock();
        defer vm.globals_lock.unlock();
        target.put(name, val) catch return error.OutOfMemory;
    } else {
        target.put(name, val) catch return error.OutOfMemory;
    }
    if (types.isTransformer(val)) {
        if (target == vm.globals) {
            vm.macros.put(name, val) catch return error.OutOfMemory;
        }
        if (chase_transitive) {
            const tx = types.toObject(val).as(types.Transformer);
            var visited = std.AutoHashMap(*types.Transformer, void).init(vm.gc.allocator);
            defer visited.deinit();
            try copyTransformerFreeRefs(vm, target, tx, &visited, 0);
        }
        return;
    }
    if (target == vm.globals) {
        vm.global_version +%= 1;
    }
}

/// Copy the free references of a macro's templates from its definition
/// environment into the import target, so use-site expansions can resolve
/// library-internal bindings. Follows macro-to-macro references transitively:
/// an exported macro may expand into internal helper macros (which live in the
/// source library's lib_env) whose own free references must also be visible at
/// the use site (e.g. SRFI 64 test-assert → %test-comp1body →
/// %test-on-test-begin). Helper macros are additionally registered in the
/// importer's macro namespace so the compiler expands them there (issue #877).
fn copyTransformerFreeRefs(
    vm: *VM,
    target: *std.StringHashMap(Value),
    tx: *types.Transformer,
    visited: *std.AutoHashMap(*types.Transformer, void),
    depth: u32,
) !void {
    if (depth > 32) return;
    if (visited.contains(tx)) return;
    visited.put(tx, {}) catch return error.OutOfMemory;

    const env = tx.def_env orelse return;

    // SRFI 211: a procedural transformer's free references are computed by
    // running code — `(rename 'helper)` can name anything in its defining
    // library — so there are no templates to scan. Copy the WHOLE definition
    // environment under the same per-binding rules the template loop below
    // applies: the honest static over-approximation of "what could the
    // transformer reference", mirroring what template scanning approximates
    // for syntax-rules macros.
    if (tx.kind != .syntax_rules) {
        var env_it = env.iterator();
        while (env_it.next()) |entry| {
            try copyOneDefEnvBinding(vm, target, entry.key_ptr.*, entry.value_ptr.*, visited, depth);
        }
        return;
    }

    var pv_names: [64][]const u8 = undefined;
    var pv_count: usize = 0;
    for (tx.patterns[0..tx.num_rules]) |pat| {
        if (!macro.collectSymbols(pat, &pv_names, &pv_count)) break;
    }
    for (tx.templates[0..tx.num_rules]) |tmpl| {
        // Per-template array: bounds each template at 64 free refs instead
        // of 64 across all rules of the transformer.
        var free_names: [64][]const u8 = undefined;
        var free_count: usize = 0;
        _ = macro.collectFreeRefs(tmpl, pv_names[0..pv_count], tx.literals, &free_names, &free_count);
        for (free_names[0..free_count]) |fname| {
            if (env.get(fname)) |fval| {
                try copyOneDefEnvBinding(vm, target, fname, fval, visited, depth);
            } else if (vm.macros.get(fname)) |mval| {
                // Fallback: a helper already present in the global macro table
                // (e.g. imported at the REPL top level). Recurse so its own free
                // references resolve at the use site too.
                if (types.isTransformer(mval)) {
                    try copyTransformerFreeRefs(vm, target, types.toObject(mval).as(types.Transformer), visited, depth + 1);
                }
            }
        }
    }
}

/// One definition-environment binding a macro's expansion may reference,
/// copied to the import target (factored from copyTransformerFreeRefs so
/// the template-scan loop and the SRFI 211 whole-env procedural loop share
/// the exact same rules): non-transformer values become importer bindings
/// when missing — under the globals lock with a version bump when the
/// target is vm.globals; transformer values go into the importer's macro
/// namespace only, never vm.globals (#1332), and recurse for their own
/// free references (#877).
fn copyOneDefEnvBinding(
    vm: *VM,
    target: *std.StringHashMap(Value),
    fname: []const u8,
    fval: Value,
    visited: *std.AutoHashMap(*types.Transformer, void),
    depth: u32,
) error{OutOfMemory}!void {
    const is_tx = types.isTransformer(fval);
    if (target == vm.globals) {
        if (!is_tx) {
            vm.globals_lock.lock();
            const missing = !target.contains(fname);
            if (missing) {
                target.put(fname, fval) catch {
                    vm.globals_lock.unlock();
                    return error.OutOfMemory;
                };
            }
            vm.globals_lock.unlock();
            if (missing) vm.global_version +%= 1;
        }
    } else if (!target.contains(fname)) {
        target.put(fname, fval) catch return error.OutOfMemory;
    }
    if (is_tx) {
        if (target == vm.globals and !vm.macros.contains(fname)) {
            vm.macros.put(fname, fval) catch return error.OutOfMemory;
        }
        try copyTransformerFreeRefs(vm, target, types.toObject(fval).as(types.Transformer), visited, depth + 1);
    }
}

/// Where an already-tracked name in an `ImportTracker` came from: the value
/// it was bound to, and an owned, printed rendering of the import-set that
/// introduced it (e.g. "(srfi 28)"), used only for the #1726 collision
/// diagnostic below.
const ImportOrigin = struct {
    value: Value,
    label: []const u8,
};

/// Tracks which sibling import-set (within one batch -- one `(import ...)`
/// form or declaration, or one `(environment ...)` call) introduced each
/// name, so a later import-set in the SAME batch that would bind an
/// already-claimed name to a *different* value can be rejected per R7RS 5.2
/// ("it is an error to import the same identifier more than once with
/// different bindings") instead of silently overwriting it -- the "last
/// import wins" bug of kaappi#1726. Deliberately scoped to a single batch:
/// importing (or shadowing) the same name across two SEPARATE top-level
/// `(import ...)` forms stays legal, exactly like ordinary top-level
/// redefinition -- this tracker never looks at what was already in `target`
/// before the batch started.
pub const ImportTracker = struct {
    map: std.StringHashMap(ImportOrigin),

    pub fn init(allocator: std.mem.Allocator) ImportTracker {
        return .{ .map = std.StringHashMap(ImportOrigin).init(allocator) };
    }

    pub fn deinit(self: *ImportTracker, allocator: std.mem.Allocator) void {
        var it = self.map.valueIterator();
        while (it.next()) |origin| allocator.free(origin.label);
        self.map.deinit();
    }
};

/// Resolve one import-set (plain library name, or wrapped in only/except/
/// prefix/rename) and merge its bindings into `target`, atomically: every
/// name it would introduce is first checked against `tracker`, and if ANY
/// of them collides with a different value from an earlier import-set in
/// this batch, the whole import-set is rejected with no partial merge --
/// mirroring only/except/rename's own "validate all before importing any"
/// discipline. A name re-imported with the identical binding (e.g. two
/// import-sets that both bottom out at the same underlying library) is not
/// a collision and merges silently, since it is genuinely the same binding,
/// not two different ones (#1726).
pub fn importSetChecked(
    vm: *VM,
    target: *std.StringHashMap(Value),
    tracker: *ImportTracker,
    import_set: Value,
) !void {
    var bindings = try resolveImportBindings(vm, import_set);
    defer bindings.deinit();

    // A rendering of this import-set (e.g. "(srfi 28)"), used to attribute
    // every name it introduces for later collision diagnostics, and in the
    // diagnostic itself if this very import-set is the one that collides.
    // Rendered once regardless of how many names `bindings` holds.
    const label = printer.valueToString(vm.gc.allocator, import_set, .write) catch return error.OutOfMemory;
    defer vm.gc.allocator.free(label);

    // Validate first (atomic semantics, matching only/except/rename above):
    // reject the whole import-set if it would bind any name to a value
    // different from what an earlier import-set in this batch already
    // claimed for that name.
    var it = bindings.iterator();
    while (it.next()) |entry| {
        if (tracker.map.get(entry.key_ptr.*)) |existing| {
            if (existing.value != entry.value_ptr.*) {
                // When the colliding import declaration is a library's own,
                // the error location cites the top-level form that triggered
                // the load — so name the library early in the message (the
                // detail buffer truncates) or the reader hunts the wrong file
                // (found the hard way via kaappi-mpl's sin.sld).
                if (vm.loading_library_name) |loading| {
                    vm.setErrorDetail(
                        "identifier '{s}' is imported with different bindings inside library ({s})'s own import declaration, from both {s} and {s} -- R7RS 5.2: \"it is an error to import the same identifier more than once with different bindings\"; disambiguate with only/except/rename/prefix",
                        .{ entry.key_ptr.*, loading, existing.label, label },
                    );
                } else {
                    vm.setErrorDetail(
                        "identifier '{s}' is imported with different bindings from both {s} and {s} -- R7RS 5.2: \"it is an error to import the same identifier more than once with different bindings\"; disambiguate with only/except/rename/prefix",
                        .{ entry.key_ptr.*, existing.label, label },
                    );
                }
                return error.UndefinedVariable;
            }
        }
    }

    // All clear -- record any newly-claimed names (so a later sibling
    // import-set in this batch can be checked against them too) and merge
    // every binding into the real target.
    it = bindings.iterator();
    while (it.next()) |entry| {
        if (!tracker.map.contains(entry.key_ptr.*)) {
            const owned_label = vm.gc.allocator.dupe(u8, label) catch return error.OutOfMemory;
            tracker.map.put(entry.key_ptr.*, .{ .value = entry.value_ptr.*, .label = owned_label }) catch {
                vm.gc.allocator.free(owned_label);
                return error.OutOfMemory;
            };
        }
        // This is the batch's real target (never a resolveImportBindings
        // scratch map -- see importSetChecked's own doc comment), so the
        // transitive macro closure must run here.
        importBinding(vm, target, entry.key_ptr.*, entry.value_ptr.*, true) catch return error.OutOfMemory;
    }
}

/// Handle (import import-set ...) into a specific target environment.
///
/// Stops at the first import-set that fails, rather than attempting the
/// rest: `vm.last_error_detail` is a single shared buffer, and continuing
/// past a failure risks a later, unrelated (and successful) library load
/// clobbering it with fresh detail from its own native calls -- turning a
/// specific, useful message (e.g. a #1726 collision naming both libraries)
/// into a bare, generic "invalid syntax" by the time it's reported. This
/// matches the `environment` procedure's own precedent (primitives_r7rs.zig),
/// which has always stopped at the first failing import-set.
pub fn handleImportInto(vm: *VM, target: *std.StringHashMap(Value), args: Value) VMError!Value {
    var current = args;
    var tracker = ImportTracker.init(vm.gc.allocator);
    defer tracker.deinit(vm.gc.allocator);
    while (current != types.NIL) {
        if (!types.isPair(current)) return VMError.CompileError;
        const import_set = types.car(current);
        importSetChecked(vm, target, &tracker, import_set) catch return VMError.CompileError;
        current = types.cdr(current);
    }
    return types.VOID;
}

/// Handle (import import-set ...) — top-level variant that imports into vm.globals.
pub fn handleImport(vm: *VM, args: Value) VMError!Value {
    return handleImportInto(vm, vm.globals, args);
}

/// Ensure a library is loaded and registered. If already in vm.libraries, no-op.
/// Otherwise tries to load from an .sld file. Used by `environment` procedure.
pub fn ensureLibraryLoaded(vm: *VM, import_set: Value, lib_name: []const u8) !void {
    if (vm.libraries.get(lib_name) != null) return;
    tryLoadLibraryFromFile(vm, import_set) catch return error.CompileError;
}

pub fn processImportSet(vm: *VM, target: *std.StringHashMap(Value), import_set: Value) !void {
    if (!types.isPair(import_set)) return error.InvalidSyntax;

    const first = types.car(import_set);

    // Check for import modifiers
    if (types.isSymbol(first)) {
        const modifier = types.symbolName(first);

        if (std.mem.eql(u8, modifier, "only")) {
            return processImportOnly(vm, target, types.cdr(import_set));
        }
        if (std.mem.eql(u8, modifier, "except")) {
            return processImportExcept(vm, target, types.cdr(import_set));
        }
        if (std.mem.eql(u8, modifier, "prefix")) {
            return processImportPrefix(vm, target, types.cdr(import_set));
        }
        if (std.mem.eql(u8, modifier, "rename")) {
            return processImportRename(vm, target, types.cdr(import_set));
        }
    }

    // Plain library name: (scheme base) etc.
    const lib_name = library_mod.libraryNameToString(vm.gc.allocator, import_set) catch return error.InvalidSyntax;
    defer vm.gc.allocator.free(lib_name);

    // Try built-in registry first
    if (vm.libraries.get(lib_name)) |lib| {
        var it = lib.exports.iterator();
        while (it.next()) |entry| {
            // `target` here is always a resolveImportBindings scratch map
            // (see importSetChecked's doc comment) -- never chase transitive
            // macro free refs into it.
            importBinding(vm, target, entry.key_ptr.*, entry.value_ptr.*, false) catch return error.OutOfMemory;
        }
        return;
    }

    // SRFI 261 (#1645): (srfi srfi-<n>) and (srfi <mnemonic>-<n>) refer to
    // (srfi <n>). Literal name first — a user library registered or shipped
    // under the hyphenated name keeps winning — so the rewrite only fires
    // when the literal name resolves to nothing at all (registry above,
    // disk/bundled/embedded here).
    if (srfi261FormNumber(import_set)) |n| {
        if (!libraryIsAvailable(vm, lib_name, import_set)) {
            return importSrfi261Normalized(vm, target, import_set, lib_name, n);
        }
    }

    // Circular import detection
    if (vm.loading_libs.contains(lib_name)) {
        vm.setErrorDetail("circular import: ({s})", .{lib_name});
        return error.UndefinedVariable;
    }
    vm.loading_libs.put(lib_name, {}) catch return error.OutOfMemory;
    defer _ = vm.loading_libs.remove(lib_name);

    // Not found in registry — try loading from .sld file
    tryLoadLibraryFromFile(vm, import_set) catch {
        if (vm.last_error_detail_len == 0) {
            vm.setErrorDetail("library not found: ({s})", .{lib_name});
        }
        return error.UndefinedVariable;
    };

    // Now try again
    const lib = vm.libraries.get(lib_name) orelse {
        if (vm.last_error_detail_len == 0) {
            vm.setErrorDetail("library not found: ({s})", .{lib_name});
        }
        return error.UndefinedVariable;
    };
    var it = lib.exports.iterator();
    while (it.next()) |entry| {
        // Same scratch-map reasoning as the registry-hit branch above.
        importBinding(vm, target, entry.key_ptr.*, entry.value_ptr.*, false) catch return error.OutOfMemory;
    }
}

fn resolveImportBindings(vm: *VM, import_set: Value) anyerror!std.StringHashMap(Value) {
    var bindings = std.StringHashMap(Value).init(vm.gc.allocator);
    errdefer bindings.deinit();
    try processImportSet(vm, &bindings, import_set);
    return bindings;
}

fn processImportOnly(vm: *VM, target: *std.StringHashMap(Value), args: Value) !void {
    // (only <import-set> id ...)
    if (!types.isPair(args)) return error.InvalidSyntax;
    const inner_set = types.car(args);
    const ids = types.cdr(args);

    var source = try resolveImportBindings(vm, inner_set);
    defer source.deinit();

    // Validate all identifiers before importing any (atomic semantics).
    var id_list = ids;
    while (id_list != types.NIL) {
        if (!types.isPair(id_list)) return error.InvalidSyntax;
        const id = types.car(id_list);
        if (!types.isSymbol(id)) return error.InvalidSyntax;
        const id_name = types.symbolName(id);
        if (!source.contains(id_name) and !ir.isSpecialForm(id_name)) {
            vm.setErrorDetail("import only: identifier '{s}' not found in import set", .{id_name});
            return error.UndefinedVariable;
        }
        id_list = types.cdr(id_list);
    }

    // All names validated — now import.
    id_list = ids;
    while (id_list != types.NIL) {
        const id = types.car(id_list);
        const id_name = types.symbolName(id);
        if (source.get(id_name)) |val| {
            // `target` here is always a resolveImportBindings scratch map
            // too (see importSetChecked's doc comment).
            importBinding(vm, target, id_name, val, false) catch return error.OutOfMemory;
        }
        id_list = types.cdr(id_list);
    }
}

fn processImportExcept(vm: *VM, target: *std.StringHashMap(Value), args: Value) !void {
    // (except <import-set> id ...)
    if (!types.isPair(args)) return error.InvalidSyntax;
    const inner_set = types.car(args);
    const ids = types.cdr(args);

    var source = try resolveImportBindings(vm, inner_set);
    defer source.deinit();

    // Validate and remove each excluded name in one pass.
    var id_list = ids;
    while (id_list != types.NIL) {
        if (!types.isPair(id_list)) return error.InvalidSyntax;
        const id = types.car(id_list);
        if (!types.isSymbol(id)) return error.InvalidSyntax;
        const exc_name = types.symbolName(id);
        if (!source.remove(exc_name) and !ir.isSpecialForm(exc_name)) {
            vm.setErrorDetail("import except: identifier '{s}' not found in import set", .{exc_name});
            return error.UndefinedVariable;
        }
        id_list = types.cdr(id_list);
    }

    // Import everything remaining. `target` is always a resolveImportBindings
    // scratch map (see importSetChecked's doc comment).
    var it = source.iterator();
    while (it.next()) |entry| {
        importBinding(vm, target, entry.key_ptr.*, entry.value_ptr.*, false) catch return error.OutOfMemory;
    }
}

fn processImportPrefix(vm: *VM, target: *std.StringHashMap(Value), args: Value) !void {
    // (prefix <import-set> prefix-id)
    if (!types.isPair(args)) return error.InvalidSyntax;
    const inner_set = types.car(args);
    const rest = types.cdr(args);
    if (!types.isPair(rest)) return error.InvalidSyntax;
    const prefix_sym = types.car(rest);
    if (!types.isSymbol(prefix_sym)) return error.InvalidSyntax;
    const prefix = types.symbolName(prefix_sym);

    var source = try resolveImportBindings(vm, inner_set);
    defer source.deinit();

    var it = source.iterator();
    while (it.next()) |entry| {
        const prefixed_buf = std.fmt.allocPrint(vm.gc.allocator, "{s}{s}", .{ prefix, entry.key_ptr.* }) catch return error.OutOfMemory;
        defer vm.gc.allocator.free(prefixed_buf);
        const sym = vm.gc.allocSymbol(prefixed_buf) catch return error.OutOfMemory;
        const interned_name = types.symbolName(sym);
        // `target` is always a resolveImportBindings scratch map here too.
        importBinding(vm, target, interned_name, entry.value_ptr.*, false) catch return error.OutOfMemory;
    }
}

fn processImportRename(vm: *VM, target: *std.StringHashMap(Value), args: Value) !void {
    // (rename <import-set> (old new) ...)
    if (!types.isPair(args)) return error.InvalidSyntax;
    const inner_set = types.car(args);
    const renames = types.cdr(args);

    var source = try resolveImportBindings(vm, inner_set);
    defer source.deinit();

    // Validate all old names, then apply renames via fetchRemove.
    // First pass: validate that all old names exist.
    var rename_list = renames;
    while (rename_list != types.NIL) {
        if (!types.isPair(rename_list)) return error.InvalidSyntax;
        const pair = types.car(rename_list);
        if (!types.isPair(pair)) return error.InvalidSyntax;
        const old_sym = types.car(pair);
        const new_rest = types.cdr(pair);
        if (!types.isPair(new_rest)) return error.InvalidSyntax;
        const new_sym = types.car(new_rest);
        if (!types.isSymbol(old_sym) or !types.isSymbol(new_sym)) return error.InvalidSyntax;
        const old_name = types.symbolName(old_sym);
        if (!source.contains(old_name)) {
            // Special forms (lambda, let*, define, ...) have no runtime
            // value -- they were never a real entry in `source` to begin
            // with, so silently "passing" this check (the old behavior)
            // left the new name bound to nothing: using it later fell
            // through every special-form check and became a confusing
            // "undefined variable" at the use site instead of a clear
            // error here, at the actual mistake (#1718).
            if (ir.isSpecialForm(old_name)) {
                vm.setErrorDetail("import rename: cannot rename special form '{s}' -- special forms are not first-class bindings and cannot be rebound under a new name", .{old_name});
                return error.UndefinedVariable;
            }
            vm.setErrorDetail("import rename: identifier '{s}' not found in import set", .{old_name});
            return error.UndefinedVariable;
        }
        rename_list = types.cdr(rename_list);
    }

    // Second pass: remove all old entries first, then insert under new names.
    // Renames refer to the original set (parallel semantics), so interleaving
    // remove/put corrupts colliding renames like (rename lib (a b) (b c)).
    const PendingRename = struct { new_name: []const u8, value: Value };
    var pending: std.ArrayList(PendingRename) = .empty;
    defer pending.deinit(vm.gc.allocator);
    rename_list = renames;
    while (rename_list != types.NIL) {
        const pair = types.car(rename_list);
        const old_name = types.symbolName(types.car(pair));
        const new_name = types.symbolName(types.car(types.cdr(pair)));
        if (source.fetchRemove(old_name)) |kv| {
            pending.append(vm.gc.allocator, .{ .new_name = new_name, .value = kv.value }) catch return error.OutOfMemory;
        }
        rename_list = types.cdr(rename_list);
    }
    for (pending.items) |p| {
        source.put(p.new_name, p.value) catch return error.OutOfMemory;
    }

    // Import everything (with renames applied). `target` is always a
    // resolveImportBindings scratch map here too.
    var it = source.iterator();
    while (it.next()) |entry| {
        importBinding(vm, target, entry.key_ptr.*, entry.value_ptr.*, false) catch return error.OutOfMemory;
    }
}
