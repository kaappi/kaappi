const std = @import("std");
const platform = @import("platform.zig");
const is_wasm = @import("builtin").os.tag == .wasi;
const types = @import("types.zig");
const memory = @import("memory.zig");
const compiler_mod = @import("compiler.zig");
const library_mod = @import("library.zig");
const diagnostics = @import("diagnostics.zig");
const file_utils = @import("file_utils.zig");
const Value = types.Value;

const macro = @import("compiler_macro.zig");
const ir = @import("ir.zig");
const vm_mod = @import("vm.zig");
const VM = vm_mod.VM;
const VMError = vm_mod.VMError;

/// Import a binding into the target environment, routing macros to vm.macros.
fn importBinding(vm: *VM, target: *std.StringHashMap(Value), name: []const u8, val: Value) !void {
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
        const tx = types.toObject(val).as(types.Transformer);
        var visited = std.AutoHashMap(*types.Transformer, void).init(vm.gc.allocator);
        defer visited.deinit();
        try copyTransformerFreeRefs(vm, target, tx, &visited, 0);
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
                const is_tx = types.isTransformer(fval);
                if (target == vm.globals) {
                    // Non-exported transformer free refs go into vm.macros
                    // only (below), not vm.globals — keeps non-exported
                    // library macros from leaking as bindings (#1332).
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
                    // An exported macro may expand into a library-internal
                    // helper macro (e.g. SRFI 64 test-assert → %test-comp1body).
                    // The helper lives in the source library's lib_env, not the
                    // importer's; register it in the importer's macro namespace
                    // so the compiler expands it at the use site. This is the
                    // only leg that reaches vm.macros, keeping importBinding the
                    // sole path into it (issue #877).
                    if (target == vm.globals and !vm.macros.contains(fname)) {
                        vm.macros.put(fname, fval) catch return error.OutOfMemory;
                    }
                    try copyTransformerFreeRefs(vm, target, types.toObject(fval).as(types.Transformer), visited, depth + 1);
                }
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

/// Handle (import import-set ...) into a specific target environment.
pub fn handleImportInto(vm: *VM, target: *std.StringHashMap(Value), args: Value) VMError!Value {
    var current = args;
    var had_error = false;
    while (current != types.NIL) {
        if (!types.isPair(current)) return VMError.CompileError;
        const import_set = types.car(current);
        processImportSet(vm, target, import_set) catch {
            had_error = true;
        };
        current = types.cdr(current);
    }
    if (had_error) return VMError.CompileError;
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
            importBinding(vm, target, entry.key_ptr.*, entry.value_ptr.*) catch return error.OutOfMemory;
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
        importBinding(vm, target, entry.key_ptr.*, entry.value_ptr.*) catch return error.OutOfMemory;
    }
}

/// Build the relative .sld path from a library name list.
/// (mylib util) -> "mylib/util.sld"
pub fn buildLibRelPath(name_list: Value, buf: *[512]u8) ![]const u8 {
    var pos: usize = 0;
    var current = name_list;
    var first = true;

    while (current != types.NIL) {
        if (!types.isPair(current)) return error.InvalidSyntax;
        const part = types.car(current);
        current = types.cdr(current);

        if (!first) {
            if (pos >= buf.len) return error.InvalidSyntax;
            buf[pos] = '/';
            pos += 1;
        }
        first = false;

        if (types.isSymbol(part)) {
            const name = types.symbolName(part);
            if (pos + name.len >= buf.len) return error.InvalidSyntax;
            @memcpy(buf[pos .. pos + name.len], name);
            pos += name.len;
        } else if (types.isFixnum(part)) {
            var num_buf: [20]u8 = undefined;
            const s = std.fmt.bufPrint(&num_buf, "{d}", .{types.toFixnum(part)}) catch return error.InvalidSyntax;
            if (pos + s.len >= buf.len) return error.InvalidSyntax;
            @memcpy(buf[pos .. pos + s.len], s);
            pos += s.len;
        } else {
            return error.InvalidSyntax;
        }
    }

    // Append .sld extension
    const ext = ".sld";
    if (pos + ext.len >= buf.len) return error.InvalidSyntax;
    @memcpy(buf[pos .. pos + ext.len], ext);
    pos += ext.len;

    return buf[0..pos];
}

/// SRFI 261 (#1645): the number carried by a `srfi-<n>` / `<mnemonic>-<n>`
/// library-name component, or null when `name` has no such suffix. The digits
/// after the LAST '-' are the SRFI number; the prefix is not validated — the
/// number alone is authoritative (the spec assigns colliding mnemonics, e.g.
/// vectors-43 and vectors-133).
pub fn srfi261Suffix(name: []const u8) ?i64 {
    const dash = std.mem.lastIndexOfScalar(u8, name, '-') orelse return null;
    if (dash == 0) return null; // "-1" has no mnemonic/srfi prefix
    return parseSrfiDigits(name[dash + 1 ..]);
}

/// Parse `digits` as a SRFI number: nonempty and ASCII digits only, within the
/// u31 range that rejects absurd values which would overflow the fixnum range.
/// Shared by srfi261Suffix (#1645) and srfiFeatureNumber (#1649).
fn parseSrfiDigits(digits: []const u8) ?i64 {
    if (digits.len == 0) return null; // "srfi-", "lists-"
    for (digits) |c| {
        if (c < '0' or c > '9') return null; // "lists-nope", "a-+5"
    }
    const n = std.fmt.parseInt(u31, digits, 10) catch return null;
    return @as(i64, n);
}

/// SRFI 0 (#1649): the number N of a `srfi-<n>` cond-expand *feature*
/// identifier (e.g. `srfi-1` → 1), or null when `name` is not one. Requires the
/// literal `srfi-` prefix followed by digits only — unlike srfi261Suffix, which
/// reads the trailing -<digits> of any *library-name* component: a feature id
/// is `srfi-1`, never a bare `lists-1`.
pub fn srfiFeatureNumber(name: []const u8) ?i64 {
    const prefix = "srfi-";
    if (!std.mem.startsWith(u8, name, prefix)) return null;
    return parseSrfiDigits(name[prefix.len..]);
}

/// SRFI 261 (#1645): the SRFI number of a (srfi srfi-<n> …) or
/// (srfi <mnemonic>-<n> …) library name, or null when `name_list` isn't one.
/// Trailing components (sub-libraries) don't participate: (srfi srfi-146 hash)
/// carries 146.
pub fn srfi261FormNumber(name_list: Value) ?i64 {
    if (!types.isPair(name_list)) return null;
    const head = types.car(name_list);
    if (!types.isSymbol(head) or !std.mem.eql(u8, types.symbolName(head), "srfi")) return null;
    const rest = types.cdr(name_list);
    if (!types.isPair(rest)) return null;
    const second = types.car(rest);
    if (!types.isSymbol(second)) return null;
    return srfi261Suffix(types.symbolName(second));
}

/// SRFI 261 (#1645): fresh (srfi <n> rest…) name list for a matched form.
/// `n` is the number srfi261FormNumber returned for `name_list`.
fn normalizeSrfiLibName(gc: *memory.GC, name_list: Value, n: i64) !Value {
    var input = name_list;
    gc.pushRoot(&input);
    defer gc.popRoot();
    var srfi_sym = try gc.allocSymbol("srfi");
    gc.pushRoot(&srfi_sym);
    defer gc.popRoot();
    var tail = try gc.allocPair(types.makeFixnum(n), types.cdr(types.cdr(input)));
    gc.pushRoot(&tail);
    defer gc.popRoot();
    return gc.allocPair(srfi_sym, tail);
}

/// SRFI 261 (#1645): normalized relative path ("srfi/<n>[/…].sld") for a
/// (srfi srfi-<n> …) / (srfi <mnemonic>-<n> …) name, or null when the name
/// isn't a 261 form. Pure — no GC allocation — so graph builders
/// (test_selection's addImportDep) can mirror the resolver without a VM.
pub fn buildSrfi261RelPath(name_list: Value, buf: *[512]u8) ?[]const u8 {
    const n = srfi261FormNumber(name_list) orelse return null;
    var lit_buf: [512]u8 = undefined;
    const lit = buildLibRelPath(name_list, &lit_buf) catch return null;
    // Splice the number over the second path segment:
    // "srfi/lists-146/hash.sld" → "srfi/146/hash.sld".
    const seg_start = (std.mem.indexOfScalar(u8, lit, '/') orelse return null) + 1;
    const seg_end = std.mem.indexOfScalarPos(u8, lit, seg_start, '/') orelse (lit.len - ".sld".len);
    return std.fmt.bufPrint(buf, "{s}{d}{s}", .{ lit[0..seg_start], n, lit[seg_end..] }) catch null;
}

/// Import via the SRFI 261 rewrite of `import_set` (whose parsed number is
/// `n`). Split from processImportSet with an explicit error set so the mutual
/// recursion doesn't trip inferred-error-set resolution.
fn importSrfi261Normalized(vm: *VM, target: *std.StringHashMap(Value), import_set: Value, lib_name: []const u8, n: i64) VMError!void {
    var norm = normalizeSrfiLibName(vm.gc, import_set, n) catch return VMError.OutOfMemory;
    vm.gc.pushRoot(&norm);
    defer vm.gc.popRoot();
    processImportSet(vm, target, norm) catch |err| {
        // A miss on the rewritten name is reported under the name the user
        // actually wrote; deeper load errors keep their own detail (#1010).
        const detail = vm.last_error_detail[0..vm.last_error_detail_len];
        if (err == error.UndefinedVariable and
            (detail.len == 0 or std.mem.startsWith(u8, detail, "library not found:")))
        {
            vm.setErrorDetail("library not found: ({s}) (srfi 261 form of (srfi {d}))", .{ lib_name, n });
        }
        // processImportSet's recursion-inferred set is anyerror; keep every
        // real VM error's identity (Yielded in particular drives the fiber
        // retry protocol) and collapse the rest (e.g. InvalidSyntax) exactly
        // as handleImportInto's boundary does.
        return switch (err) {
            error.ArityMismatch, error.CompileError, error.ContinuationInvoked, error.DivisionByZero, error.ExceptionRaised, error.ExecutionTimeout, error.IndexOutOfBounds, error.InvalidArgument, error.InvalidBytecode, error.NotAProcedure, error.OutOfMemory, error.StackOverflow, error.Terminated, error.TypeError, error.UndefinedVariable, error.Yielded => |e| e,
            else => VMError.CompileError,
        };
    };
}

/// libraryIsAvailable plus the SRFI 261 rewrite — the check behind both
/// cond-expand (library …) entry points, so (library (srfi srfi-1)) answers
/// exactly what import can resolve. libraryIsAvailable itself stays literal:
/// import's literal-first shadowing and this check must not disagree.
pub fn libraryIsAvailableSrfi261(vm: *VM, lib_name: []const u8, lib_name_list: Value) bool {
    if (libraryIsAvailable(vm, lib_name, lib_name_list)) return true;
    const n = srfi261FormNumber(lib_name_list) orelse return false;
    var norm = normalizeSrfiLibName(vm.gc, lib_name_list, n) catch return false;
    vm.gc.pushRoot(&norm);
    defer vm.gc.popRoot();
    const norm_name = library_mod.libraryNameToString(vm.gc.allocator, norm) catch return false;
    defer vm.gc.allocator.free(norm_name);
    return libraryIsAvailable(vm, norm_name, norm);
}

/// Fresh `(srfi <n>)` library-name list.
fn buildSrfiNameList(gc: *memory.GC, n: i64) !Value {
    var srfi_sym = try gc.allocSymbol("srfi");
    gc.pushRoot(&srfi_sym);
    defer gc.popRoot();
    // allocPair auto-roots its Value args, so tail needs no separate root
    // before it is handed to the outer allocPair on the next line.
    const tail = try gc.allocPair(types.makeFixnum(n), types.NIL);
    return gc.allocPair(srfi_sym, tail);
}

/// SRFI 0 (#1649): whether the `srfi-<n>` cond-expand feature identifier `name`
/// is supported by this VM. False for any name that is not a `srfi-<n>` form.
///
/// For a real SRFI number the answer routes through the same availability check
/// as `(library (srfi <n>))` — so built-in SRFIs (registered), portable SRFIs
/// (their `.sld` loadable), and the `--sandbox`/WASM degradations all stay
/// consistent with what `(import (srfi <n>))` would actually do; nothing is
/// hardcoded (the #1517 derive-don't-list principle). SRFI 261 (#1645) is the
/// one supported SRFI with no library file — a pure naming convention — so it
/// answers true directly.
pub fn srfiFeatureAvailable(vm: *VM, name: []const u8) bool {
    const n = srfiFeatureNumber(name) orelse return false;
    if (n == 261) return true; // naming convention, no .sld to probe
    var list = buildSrfiNameList(vm.gc, n) catch return false;
    vm.gc.pushRoot(&list);
    defer vm.gc.popRoot();
    const canonical = library_mod.libraryNameToString(vm.gc.allocator, list) catch return false;
    defer vm.gc.allocator.free(canonical);
    return libraryIsAvailable(vm, canonical, list);
}

/// Load and evaluate a library source file from a resolved path.
fn loadLibrarySource(vm: *VM, source: []const u8) !void {
    const reader_mod = @import("reader.zig");
    var rdr = reader_mod.Reader.init(vm.gc, source);
    defer rdr.deinit();

    // Reader failures get their own error name so an unbalanced or
    // malformed .sld surfaces as a parse problem, not a vague
    // "InvalidSyntax while loading library".
    while (rdr.hasMore() catch return error.LibrarySourceReadError) {
        var expr = rdr.readDatum() catch return error.LibrarySourceReadError;
        vm.gc.pushRoot(&expr);
        defer vm.gc.popRoot();

        if (vm.handleTopLevelForm(expr)) |result| {
            _ = result catch |err| return err;
        } else {
            const func = compiler_mod.compileExpressionWithMacros(vm.gc, expr, &vm.macros, vm.globals) catch |err| {
                // OutOfMemory is a fatal runtime failure, not a malformed
                // library — let it propagate instead of being reported as
                // a missing/broken import.
                if (err == error.OutOfMemory) return err;
                if (vm.last_error_detail_len == 0) {
                    vm.setErrorDetail("{s} while compiling library body form", .{@errorName(err)});
                }
                return error.InvalidSyntax;
            };
            var func_val = types.makePointer(&func.header);
            vm.gc.pushRoot(&func_val);
            defer vm.gc.popRoot();
            compiler_mod.Compiler.unrootFunction(vm.gc, func);
            _ = try vm.execute(func);
        }
    }
}

/// Resolve the full path for a library .sld file.
/// Returns a heap-allocated path string, or null if not found.
pub fn resolveLibraryPath(allocator: std.mem.Allocator, rel_path: []const u8, lib_paths: []const []const u8) ?[]u8 {
    // Built-in search prefixes (relative to cwd)
    const builtin_prefixes = [_][]const u8{ "", "lib/" };

    const total_candidates = builtin_prefixes.len + lib_paths.len;
    var candidate_idx: usize = 0;

    while (candidate_idx < total_candidates) : (candidate_idx += 1) {
        var full_path_buf: [600]u8 = undefined;
        var full_len: usize = 0;

        if (candidate_idx < builtin_prefixes.len) {
            const prefix = builtin_prefixes[candidate_idx];
            full_len = prefix.len + rel_path.len;
            if (full_len >= full_path_buf.len) continue;
            @memcpy(full_path_buf[0..prefix.len], prefix);
            @memcpy(full_path_buf[prefix.len .. prefix.len + rel_path.len], rel_path);
        } else {
            const lp = lib_paths[candidate_idx - builtin_prefixes.len];
            const needs_sep: usize = if (lp.len > 0 and lp[lp.len - 1] != '/') 1 else 0;
            full_len = lp.len + needs_sep + rel_path.len;
            if (full_len >= full_path_buf.len) continue;
            @memcpy(full_path_buf[0..lp.len], lp);
            if (needs_sep == 1) {
                full_path_buf[lp.len] = '/';
            }
            @memcpy(full_path_buf[lp.len + needs_sep .. lp.len + needs_sep + rel_path.len], rel_path);
        }

        const full_path = full_path_buf[0..full_len];

        // Check if file exists by trying to open it
        const probe_z = allocator.dupeZ(u8, full_path) catch continue;
        defer allocator.free(probe_z);
        const probe_fd = platform.openRead(probe_z) catch continue;
        _ = platform.close(probe_fd);

        // File exists — return heap-allocated copy
        return allocator.dupe(u8, full_path) catch null;
    }

    return null;
}

/// Whether library `lib_name` (canonical dotted form) is loaded or loadable
/// from disk. The single implementation behind both cond-expand (library ...)
/// entry points: evalLibFeatureReq below (inside define-library, has *VM
/// directly) and vm.zig's checkLibraryExists (the callback the compiler uses
/// for top-level/expression-position cond-expand, which cannot import vm.zig
/// directly). (KEP-0004)
pub fn libraryIsAvailable(vm: *VM, lib_name: []const u8, lib_name_list: Value) bool {
    if (vm.libraries.get(lib_name) != null) return true;
    // tryLoadLibraryFromFile (below) rejects every file-backed load when
    // sandboxed; without this check cond-expand would report a disk-only
    // library as available while the matching import then fails, and would
    // let sandboxed code probe the host filesystem for .sld existence.
    // Embedded libraries (below) are the one exception -- their content is
    // fixed at compile time, not read from wherever sandboxed code points,
    // so reporting them available here doesn't reopen that hole.
    if (vm.sandbox_mode) {
        var path_buf: [512]u8 = undefined;
        const rel_path = buildLibRelPath(lib_name_list, &path_buf) catch return false;
        return findEmbeddedLibrary(rel_path) != null;
    }
    // WASM has no blanket block like sandbox's, but relies on whatever
    // preopened directory the host (browser shim, wasmtime --dir) happens to
    // mount at a given relative path -- unlike a normal install, there's no
    // guarantee lib/ is reachable there. Preferring the embedded copy when
    // there is one sidesteps that packaging dependency for exactly this
    // library; anything else still falls through to the normal disk check
    // (unaffected -- a host that does mount lib/ still serves those fine).
    if (is_wasm) {
        var path_buf: [512]u8 = undefined;
        if (buildLibRelPath(lib_name_list, &path_buf) catch null) |rel_path| {
            if (findEmbeddedLibrary(rel_path) != null) return true;
        }
    }
    return libraryFileExists(vm, lib_name_list);
}

/// Portable libraries embedded directly into the binary so they stay
/// importable under `--sandbox` (which otherwise blocks every file-backed
/// library load -- tryLoadLibraryFromFile, below -- to keep sandboxed code
/// from probing the host filesystem via crafted import paths, Motivation
/// Path 2 of KEP-0002's sibling concern) and on WASM (which has no
/// filesystem-independent way to guarantee lib/ is mounted at a reachable
/// path). The embedded text is fixed at compile time -- sandboxed code
/// cannot influence or read anything beyond exactly this content -- so
/// serving it here doesn't reopen the sandbox hole. The .sld file on disk
/// remains the actual source of truth (readable, editable, and what every
/// native non-sandboxed load still uses via the normal path below); this
/// table only changes how a sandboxed or WASM VM loads the identical text.
/// Keyed by the same relative path buildLibRelPath produces.
const embedded_libraries = [_]struct { rel_path: []const u8, source: []const u8 }{
    .{ .rel_path = "kaappi/parallel.sld", .source = @import("kaappi_parallel_sld").source },
};

fn findEmbeddedLibrary(rel_path: []const u8) ?[]const u8 {
    for (embedded_libraries) |lib| {
        if (std.mem.eql(u8, lib.rel_path, rel_path)) return lib.source;
    }
    return null;
}

/// Check whether a library could be loaded from disk (or the bundled files of
/// a standalone binary), using the same search order as import. Used by the
/// cond-expand (library ...) feature checks so they agree with what import
/// can actually resolve.
pub fn libraryFileExists(vm: *VM, name_list: Value) bool {
    var path_buf: [512]u8 = undefined;
    const rel_path = buildLibRelPath(name_list, &path_buf) catch return false;
    if (vm.bundled_files) |bf| {
        if (findBundledSource(bf, rel_path, vm.lib_paths) != null) return true;
    }
    if (resolveLibraryPath(vm.gc.allocator, rel_path, vm.lib_paths)) |p| {
        vm.gc.allocator.free(p);
        return true;
    }
    return false;
}

/// Try to find a library's .sld source in bundled files, using the same
/// search order as resolveLibraryPath.
fn findBundledSource(bf: *std.StringHashMap([]const u8), rel_path: []const u8, lib_paths: []const []const u8) ?struct { path: []const u8, source: []const u8 } {
    const prefixes = [_][]const u8{ "", "lib/" };
    for (prefixes) |prefix| {
        var buf: [600]u8 = undefined;
        const full = std.fmt.bufPrint(&buf, "{s}{s}", .{ prefix, rel_path }) catch continue;
        if (bf.get(full)) |src| {
            const key = bf.getKey(full) orelse continue;
            return .{ .path = key, .source = src };
        }
    }
    for (lib_paths) |lp| {
        var buf: [600]u8 = undefined;
        const needs_sep: usize = if (lp.len > 0 and lp[lp.len - 1] != '/') 1 else 0;
        const full = std.fmt.bufPrint(&buf, "{s}{s}{s}", .{
            lp,
            if (needs_sep == 1) "/" else "",
            rel_path,
        }) catch continue;
        if (bf.get(full)) |src| {
            const key = bf.getKey(full) orelse continue;
            return .{ .path = key, .source = src };
        }
    }
    return null;
}

/// Read file contents, checking bundled files first if available.
fn readFileOrBundled(allocator: std.mem.Allocator, path: []const u8, bundled: ?*std.StringHashMap([]const u8)) ![]u8 {
    if (bundled) |bf| {
        if (bf.get(path)) |src| {
            return allocator.dupe(u8, src) catch return error.OutOfMemory;
        }
    }
    return file_utils.readWholeFile(allocator, path, 1024 * 1024);
}

/// Record a file read for bundle collection during --compile.
fn recordFileForBundle(vm: *VM, path: []const u8, content: []const u8) void {
    if (vm.compile_collect_files) |collect| {
        if (!collect.contains(path)) {
            const key = vm.gc.allocator.dupe(u8, path) catch return;
            const val = vm.gc.allocator.dupe(u8, content) catch {
                vm.gc.allocator.free(key);
                return;
            };
            collect.put(key, val) catch {
                vm.gc.allocator.free(key);
                vm.gc.allocator.free(val);
            };
        }
    }
}

/// Try to load a library from a .sld file on disk.
/// Search order: ./rel_path, ./lib/rel_path, then each vm.lib_paths entry
/// (--lib-path flags, the script's directory, ~/.kaappi/lib).
fn loadEmbeddedLibrary(vm: *VM, rel_path: []const u8, source: []const u8) !void {
    loadLibrarySource(vm, source) catch |err| {
        if (vm.last_error_detail_len == 0) {
            vm.setErrorDetail("{s} while loading embedded library {s}", .{ @errorName(err), rel_path });
        }
        return error.UndefinedVariable;
    };
}

fn tryLoadLibraryFromFile(vm: *VM, name_list: Value) !void {
    var path_buf: [512]u8 = undefined;
    const rel_path = buildLibRelPath(name_list, &path_buf) catch return error.InvalidSyntax;

    if (vm.sandbox_mode) {
        if (findEmbeddedLibrary(rel_path)) |source| return loadEmbeddedLibrary(vm, rel_path, source);
        vm.setErrorDetail("sandbox: cannot load library from file", .{});
        return error.UndefinedVariable;
    }

    // WASM: prefer the embedded copy when there is one (no guarantee lib/ is
    // reachable at any given relative path under whatever the host mounted),
    // otherwise fall through to the normal disk/bundled search below exactly
    // as a native build would.
    if (is_wasm) {
        if (findEmbeddedLibrary(rel_path)) |source| return loadEmbeddedLibrary(vm, rel_path, source);
    }

    const allocator = vm.gc.allocator;

    // Check bundled files first (standalone binary support)
    if (vm.bundled_files) |bf| {
        if (findBundledSource(bf, rel_path, vm.lib_paths)) |found| {
            const sld_dir = extractDir(found.path);
            const saved_lib_dir = vm.current_lib_dir;
            vm.current_lib_dir = sld_dir;
            defer vm.current_lib_dir = saved_lib_dir;
            loadLibrarySource(vm, found.source) catch |err| {
                // The library exists — don't let this surface as "library
                // not found" (#1010).
                if (vm.last_error_detail_len == 0) {
                    vm.setErrorDetail("{s} while loading bundled library {s}", .{ @errorName(err), found.path });
                }
                return error.UndefinedVariable;
            };
            return;
        }
    }

    // Resolve the .sld file path
    const sld_path = resolveLibraryPath(allocator, rel_path, vm.lib_paths) orelse
        return error.UndefinedVariable;
    defer allocator.free(sld_path);

    // Extract the directory of the .sld file for include path resolution
    const sld_dir = extractDir(sld_path);
    const saved_lib_dir = vm.current_lib_dir;
    vm.current_lib_dir = sld_dir;
    defer vm.current_lib_dir = saved_lib_dir;

    // Read the source file
    const source = file_utils.readWholeFile(allocator, sld_path, 1024 * 1024) catch return error.UndefinedVariable;
    defer allocator.free(source);

    // Record for bundling (use rel_path so findBundledSource can locate it
    // without the compile-time --lib-path prefix)
    recordFileForBundle(vm, rel_path, source);

    // No .sbc caching for .sld files, in either direction. Writing was
    // disabled because collected function pointers can be freed by GC during
    // library loading (use-after-free in the serializer). The old cache-read
    // path reconstructed the export table by re-parsing the .sld top level,
    // silently dropping exports from include-library-declarations and
    // cond-expand — if caching is ever reintroduced, serialize the export
    // table into the .sbc instead of re-deriving it from source.
    loadLibrarySource(vm, source) catch |err| {
        // The .sld file was found and read — a failure here is a load error,
        // not a missing library. Say so instead of letting processImportSet
        // report "library not found" (#1010).
        if (vm.last_error_detail_len == 0) {
            vm.setErrorDetail("{s} while loading library from {s}", .{ @errorName(err), sld_path });
        }
        return error.UndefinedVariable;
    };
}

/// Evaluate a feature requirement for cond-expand in define-library.
/// Unlike the compiler's evalFeatureReq, this has access to the VM's live library registry.
fn evalLibFeatureReq(vm: *VM, req: Value) bool {
    if (types.isSymbol(req)) {
        const name = types.symbolName(req);
        for (types.platform_features) |f| {
            if (std.mem.eql(u8, name, f)) return true;
        }
        // #1649: srfi-<n> feature identifiers, routed through the same
        // availability check as (library (srfi <n>)).
        return srfiFeatureAvailable(vm, name);
    }

    if (types.isPair(req)) {
        const head = types.car(req);
        if (!types.isSymbol(head)) return false;
        const op = types.symbolName(head);

        if (std.mem.eql(u8, op, "and")) {
            var rest = types.cdr(req);
            while (rest != types.NIL) {
                if (!types.isPair(rest)) return false;
                if (!evalLibFeatureReq(vm, types.car(rest))) return false;
                rest = types.cdr(rest);
            }
            return true;
        }
        if (std.mem.eql(u8, op, "or")) {
            var rest = types.cdr(req);
            while (rest != types.NIL) {
                if (!types.isPair(rest)) return false;
                if (evalLibFeatureReq(vm, types.car(rest))) return true;
                rest = types.cdr(rest);
            }
            return false;
        }
        if (std.mem.eql(u8, op, "not")) {
            const rest = types.cdr(req);
            if (!types.isPair(rest)) return false;
            return !evalLibFeatureReq(vm, types.car(rest));
        }
        if (std.mem.eql(u8, op, "library")) {
            const rest = types.cdr(req);
            if (!types.isPair(rest)) return false;
            const lib_name_list = types.car(rest);
            const lib_name = library_mod.libraryNameToString(vm.gc.allocator, lib_name_list) catch return false;
            defer vm.gc.allocator.free(lib_name);
            return libraryIsAvailableSrfi261(vm, lib_name, lib_name_list);
        }
    }
    return false;
}

const IncludeFile = struct {
    source: []const u8,
    resolved_path: ?[]u8,

    fn deinit(self: IncludeFile, allocator: std.mem.Allocator) void {
        allocator.free(self.source);
        if (self.resolved_path) |rp| allocator.free(rp);
    }
};

fn openIncludeFile(vm: *VM, file_path: []const u8) VMError!IncludeFile {
    var resolved_path: ?[]u8 = null;
    if (vm.current_lib_dir) |dir| {
        if (dir.len > 0 and file_path.len > 0 and file_path[0] != '/') {
            resolved_path = std.fmt.allocPrint(vm.gc.allocator, "{s}{s}", .{ dir, file_path }) catch null;
        }
    }
    const source = blk: {
        if (resolved_path) |rp| {
            if (readFileOrBundled(vm.gc.allocator, rp, vm.bundled_files)) |src| break :blk src else |_| {}
        }
        break :blk readFileOrBundled(vm.gc.allocator, file_path, vm.bundled_files) catch {
            if (resolved_path) |rp| vm.gc.allocator.free(rp);
            return VMError.CompileError;
        };
    };
    return .{ .source = source, .resolved_path = resolved_path };
}

/// Handle a top-level `(include "file" ...)` / `(include-ci "file" ...)` form.
///
/// Reads each named file, parses it, and evaluates every datum as a top-level
/// form. Relative paths resolve against the directory of the including file
/// (`vm.current_lib_dir`), falling back to the current working directory. While
/// a file is being processed, `current_lib_dir` points at that file's directory
/// so nested includes resolve relative to it.
///
/// Errors in an included form are reported to stderr and processing continues
/// with the next form, matching the per-form error isolation of the top-level
/// file runner in `main.zig`.
pub fn handleTopLevelInclude(vm: *VM, args: Value, ci: bool) VMError!Value {
    const reader_mod = @import("reader.zig");

    // Root the argument spine: evaluating included forms allocates and may
    // trigger GC, which would otherwise reclaim the pair list and filename
    // strings we are still walking.
    var file_list = args;
    vm.gc.pushRoot(&file_list);
    defer vm.gc.popRoot();

    while (file_list != types.NIL) {
        if (!types.isPair(file_list)) return VMError.CompileError;
        const file_val = types.car(file_list);
        if (!types.isString(file_val)) return VMError.CompileError;
        const file_str = types.toObject(file_val).as(types.SchemeString);
        const file_path = file_str.data[0..file_str.len];

        const inc = try openIncludeFile(vm, file_path);
        defer inc.deinit(vm.gc.allocator);

        const used_path: []const u8 = inc.resolved_path orelse file_path;
        recordFileForBundle(vm, used_path, inc.source);
        if (!std.mem.eql(u8, used_path, file_path)) {
            recordFileForBundle(vm, file_path, inc.source);
        }

        // Own a copy of the path: error reporting and current_lib_dir slice into
        // it across operations that may free `resolved_path` or GC `file_path`.
        const owned_path = vm.gc.allocator.dupe(u8, used_path) catch return VMError.OutOfMemory;
        defer vm.gc.allocator.free(owned_path);

        // Nested includes within this file resolve relative to this file's dir.
        const saved_lib_dir = vm.current_lib_dir;
        vm.current_lib_dir = extractDir(owned_path);
        defer vm.current_lib_dir = saved_lib_dir;

        var file_reader = reader_mod.Reader.initWithName(vm.gc, inc.source, owned_path);
        file_reader.fold_case = ci;
        defer file_reader.deinit();

        while (file_reader.hasMore() catch false) {
            const lc = file_reader.getLineCol();
            const inc_expr = file_reader.readDatum() catch {
                reportIncludeError(vm, owned_path, lc.line, null, error.CompileError);
                break; // reader position is unreliable after a read error
            };
            evalIncludedForm(vm, inc_expr, owned_path, lc.line);
        }

        file_list = types.cdr(file_list);
    }
    return types.VOID;
}

/// Evaluate a single datum read from an included file, isolating errors so one
/// bad form does not abort the rest of the include.
fn evalIncludedForm(vm: *VM, expr: Value, path: []const u8, line: u32) void {
    if (vm.handleTopLevelForm(expr)) |result| {
        _ = result catch |err| reportIncludeError(vm, path, line, vm.getErrorDetail(), err);
        vm.last_error_detail_len = 0;
        return;
    }

    const func = compiler_mod.compileExpressionWithMacros(vm.gc, expr, &vm.macros, vm.globals) catch |err| {
        reportIncludeError(vm, path, line, null, err);
        return;
    };
    if (vm.lib_compile_collect) |collect| {
        collect.append(vm.gc.allocator, func) catch {};
    }
    var func_val = types.makePointer(&func.header);
    vm.gc.pushRoot(&func_val);
    defer vm.gc.popRoot();
    compiler_mod.Compiler.unrootFunction(vm.gc, func);
    _ = vm.execute(func) catch |err| {
        reportIncludeError(vm, path, line, vm.getErrorDetail(), err);
        vm.last_error_detail_len = 0;
        return;
    };
}

fn reportIncludeError(vm: *VM, path: []const u8, line: u32, detail: ?[]const u8, err: anyerror) void {
    // Prefer a code carried on the raised error object; else derive from the
    // escaping Zig error (KEP-0005).
    const code = if (vm.last_error_code != .uncategorized)
        vm.last_error_code
    else
        diagnostics.runtimeErrorCode(err);
    const msg = if (detail) |d| (if (d.len > 0) d else code.message()) else code.message();
    var cbuf: [diagnostics.Code.render_width]u8 = undefined;
    var buf: [320]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, "{s}:{d}: error[{s}]: {s}\n", .{ path, line, code.render(&cbuf), msg }) catch "include error\n";
    vm_mod.writeStderr(s);
}

pub fn extractDir(path: []const u8) []const u8 {
    if (std.mem.lastIndexOfScalar(u8, path, '/')) |pos| {
        return path[0 .. pos + 1];
    }
    return "";
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
            importBinding(vm, target, id_name, val) catch return error.OutOfMemory;
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

    // Import everything remaining.
    var it = source.iterator();
    while (it.next()) |entry| {
        importBinding(vm, target, entry.key_ptr.*, entry.value_ptr.*) catch return error.OutOfMemory;
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
        importBinding(vm, target, interned_name, entry.value_ptr.*) catch return error.OutOfMemory;
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
        if (!source.contains(old_name) and !ir.isSpecialForm(old_name)) {
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

    // Import everything (with renames applied).
    var it = source.iterator();
    while (it.next()) |entry| {
        importBinding(vm, target, entry.key_ptr.*, entry.value_ptr.*) catch return error.OutOfMemory;
    }
}

/// Handle (define-library (name ...) decl ...)
/// Declarations can be:
///   (export id ...)
///   (import import-set ...)
///   (begin expr ...)
pub fn handleDefineLibrary(vm: *VM, args: Value) VMError!Value {
    if (!types.isPair(args)) return VMError.CompileError;
    const name_list = types.car(args);
    var decls = types.cdr(args);

    // Root the AST so it survives GC during nested library loading
    // (e.g. when (import (srfi 35)) triggers loading a .sld file).
    vm.gc.pushRoot(&decls);
    defer vm.gc.popRoot();

    const lib_name = library_mod.libraryNameToString(vm.gc.allocator, name_list) catch return VMError.CompileError;

    const lib_env = vm.gc.allocator.create(std.StringHashMap(Value)) catch {
        vm.gc.allocator.free(lib_name);
        return VMError.OutOfMemory;
    };
    lib_env.* = std.StringHashMap(Value).init(vm.gc.allocator);
    var lib_env_owned = true;

    defer if (lib_env_owned) {
        lib_env.deinit();
        vm.gc.allocator.destroy(lib_env);
        vm.gc.allocator.free(lib_name);
    };

    // Root the library environment so GC can trace closures defined in
    // begin blocks before the library is registered. Push/pop for
    // nested library loading (e.g. SRFI 64 importing SRFI 35).
    const pushed_lib_env = vm.pending_lib_env_count < vm.pending_lib_envs.len;
    if (pushed_lib_env) {
        vm.pending_lib_envs[vm.pending_lib_env_count] = lib_env;
        vm.pending_lib_env_count += 1;
    }
    defer if (pushed_lib_env) {
        vm.pending_lib_env_count -= 1;
    };

    var export_names: std.ArrayList([]const u8) = .empty;
    defer export_names.deinit(vm.gc.allocator);
    var export_renames: std.ArrayList(?[]const u8) = .empty;
    defer export_renames.deinit(vm.gc.allocator);

    var decl = decls;
    while (decl != types.NIL) {
        if (!types.isPair(decl)) return VMError.CompileError;
        try processLibDeclaration(vm, lib_env, types.car(decl), &export_names, &export_renames);
        decl = types.cdr(decl);
    }

    var lib = library_mod.Library.initOwned(vm.gc.allocator, lib_name);
    lib.lib_env = lib_env;
    lib_env_owned = false; // library now owns both lib_env and lib_name
    for (0..export_names.items.len) |i| {
        const internal_name = export_names.items[i];
        const exported_name = export_renames.items[i] orelse internal_name;
        // Both value definitions and library-body macros live in lib_env
        // (issue #877), so a single lookup resolves every export. Macros are
        // no longer sourced from the global vm.macros — that fallback only
        // worked because define-syntax used to leak process-globally.
        if (lib_env.get(internal_name)) |val| {
            lib.addExport(exported_name, val) catch {
                lib.deinit();
                return VMError.OutOfMemory;
            };
        }
    }

    vm.libraries.register(lib) catch {
        lib.deinit();
        return VMError.OutOfMemory;
    };

    return types.VOID;
}

/// Compile and evaluate a library begin block against a per-library env.
fn compileLibBeginBlock(vm: *VM, lib_env: *std.StringHashMap(Value), body_list: Value) VMError!void {
    var body = body_list;
    while (body != types.NIL) {
        if (!types.isPair(body)) return VMError.CompileError;
        const body_expr = types.car(body);
        try compileLibExpr(vm, lib_env, body_expr);
        body = types.cdr(body);
    }
}

/// Compile and evaluate a single expression in a library context.
fn compileLibExpr(vm: *VM, lib_env: *std.StringHashMap(Value), expr: Value) VMError!void {
    if (isLibTopLevelForm(expr)) {
        // Set the library env so handleDefineRecordType etc. use it
        const saved_env = vm.current_lib_env;
        vm.current_lib_env = lib_env;
        defer vm.current_lib_env = saved_env;
        if (vm.handleTopLevelForm(expr)) |result| {
            _ = try result;
        }
        return;
    }

    // Compile against a per-library macro table seeded from lib_env rather
    // than the global vm.macros, so define-syntax in this library's body does
    // not leak into (nor read from) the process-global macro namespace
    // (issue #877). The library's own macros are stored in lib_env by
    // compileDefineSyntax; imported macros already live there too. Seeding
    // from lib_env's transformer entries makes both visible to the macro
    // expander for this form without touching vm.macros.
    var lib_macros = std.StringHashMap(Value).init(vm.gc.allocator);
    defer lib_macros.deinit();
    var env_it = lib_env.iterator();
    while (env_it.next()) |entry| {
        if (types.isTransformer(entry.value_ptr.*)) {
            lib_macros.put(entry.key_ptr.*, entry.value_ptr.*) catch return VMError.OutOfMemory;
        }
    }
    const func = compiler_mod.compileExpressionInEnv(vm.gc, expr, &lib_macros, lib_env, types.NIL, false) catch |err| {
        // Name the failing form so a broken library body surfaces as itself
        // instead of being masked as "library not found" upstream (#1010).
        if (vm.last_error_detail_len == 0) {
            var def_name: []const u8 = "";
            if (types.isPair(expr) and types.isPair(types.cdr(expr))) {
                var target = types.car(types.cdr(expr));
                if (types.isPair(target)) target = types.car(target);
                if (types.isSymbol(target)) def_name = types.symbolName(target);
            }
            if (def_name.len > 0) {
                vm.setErrorDetail("{s} while compiling library definition '{s}'", .{ @errorName(err), def_name });
            } else {
                vm.setErrorDetail("{s} while compiling library body form", .{@errorName(err)});
            }
        }
        return VMError.CompileError;
    };
    if (vm.lib_compile_collect) |collect| {
        collect.append(vm.gc.allocator, func) catch return VMError.OutOfMemory;
    }
    var func_val = types.makePointer(&func.header);
    vm.gc.pushRoot(&func_val);
    compiler_mod.Compiler.unrootFunction(vm.gc, func);
    defer vm.gc.popRoot();
    _ = try vm.execute(func);
}

/// Compile and evaluate included files in a library context.
fn compileLibInclude(vm: *VM, lib_env: *std.StringHashMap(Value), file_list_val: Value, ci: bool) VMError!void {
    var file_list = file_list_val;
    while (file_list != types.NIL) {
        if (!types.isPair(file_list)) return VMError.CompileError;
        const file_val = types.car(file_list);
        if (!types.isString(file_val)) return VMError.CompileError;
        const file_str = types.toObject(file_val).as(types.SchemeString);
        const file_path = file_str.data[0..file_str.len];

        const inc = try openIncludeFile(vm, file_path);
        defer inc.deinit(vm.gc.allocator);

        const used_path: []const u8 = inc.resolved_path orelse file_path;
        recordFileForBundle(vm, used_path, inc.source);
        if (!std.mem.eql(u8, used_path, file_path)) {
            recordFileForBundle(vm, file_path, inc.source);
        }

        const reader_mod = @import("reader.zig");
        var file_reader = reader_mod.Reader.init(vm.gc, inc.source);
        file_reader.fold_case = ci;
        defer file_reader.deinit();

        while (file_reader.hasMore() catch return VMError.CompileError) {
            const inc_expr = file_reader.readDatum() catch return VMError.CompileError;
            try compileLibExpr(vm, lib_env, inc_expr);
        }

        file_list = types.cdr(file_list);
    }
}

fn processLibDeclaration(
    vm: *VM,
    lib_env: *std.StringHashMap(Value),
    declaration: Value,
    export_names: *std.ArrayList([]const u8),
    export_renames: *std.ArrayList(?[]const u8),
) VMError!void {
    if (!types.isPair(declaration)) return VMError.CompileError;
    const decl_head = types.car(declaration);
    if (!types.isSymbol(decl_head)) return VMError.CompileError;
    const decl_name = types.symbolName(decl_head);

    if (std.mem.eql(u8, decl_name, "export")) {
        var id_list = types.cdr(declaration);
        while (id_list != types.NIL) {
            if (!types.isPair(id_list)) return VMError.CompileError;
            const id = types.car(id_list);
            if (types.isSymbol(id)) {
                export_names.append(vm.gc.allocator, types.symbolName(id)) catch return VMError.OutOfMemory;
                export_renames.append(vm.gc.allocator, null) catch return VMError.OutOfMemory;
            } else if (types.isPair(id)) {
                const rename_head = types.car(id);
                if (types.isSymbol(rename_head) and std.mem.eql(u8, types.symbolName(rename_head), "rename")) {
                    const rename_args = types.cdr(id);
                    if (types.isPair(rename_args)) {
                        const internal = types.car(rename_args);
                        const rest = types.cdr(rename_args);
                        if (types.isPair(rest) and types.isSymbol(internal)) {
                            const external = types.car(rest);
                            if (types.isSymbol(external)) {
                                export_names.append(vm.gc.allocator, types.symbolName(internal)) catch return VMError.OutOfMemory;
                                export_renames.append(vm.gc.allocator, types.symbolName(external)) catch return VMError.OutOfMemory;
                            }
                        }
                    }
                }
            }
            id_list = types.cdr(id_list);
        }
    } else if (std.mem.eql(u8, decl_name, "import")) {
        _ = try handleImportInto(vm, lib_env, types.cdr(declaration));
    } else if (std.mem.eql(u8, decl_name, "begin")) {
        try compileLibBeginBlock(vm, lib_env, types.cdr(declaration));
    } else if (std.mem.eql(u8, decl_name, "include") or std.mem.eql(u8, decl_name, "include-ci")) {
        try compileLibInclude(vm, lib_env, types.cdr(declaration), std.mem.eql(u8, decl_name, "include-ci"));
    } else if (std.mem.eql(u8, decl_name, "include-library-declarations")) {
        try includeLibraryDeclarations(vm, lib_env, types.cdr(declaration), export_names, export_renames);
    } else if (std.mem.eql(u8, decl_name, "cond-expand")) {
        var clauses = types.cdr(declaration);
        while (clauses != types.NIL) {
            if (!types.isPair(clauses)) break;
            const clause = types.car(clauses);
            clauses = types.cdr(clauses);
            if (!types.isPair(clause)) continue;
            const feature_req = types.car(clause);
            var clause_decls = types.cdr(clause);
            const is_else = types.isSymbol(feature_req) and std.mem.eql(u8, types.symbolName(feature_req), "else");
            if (is_else or evalLibFeatureReq(vm, feature_req)) {
                while (clause_decls != types.NIL) {
                    if (!types.isPair(clause_decls)) break;
                    try processLibDeclaration(vm, lib_env, types.car(clause_decls), export_names, export_renames);
                    clause_decls = types.cdr(clause_decls);
                }
                break;
            }
        }
    }
}

fn includeLibraryDeclarations(
    vm: *VM,
    lib_env: *std.StringHashMap(Value),
    file_list_val: Value,
    export_names: *std.ArrayList([]const u8),
    export_renames: *std.ArrayList(?[]const u8),
) VMError!void {
    var file_list = file_list_val;
    while (file_list != types.NIL) {
        if (!types.isPair(file_list)) return VMError.CompileError;
        const file_val = types.car(file_list);
        if (!types.isString(file_val)) return VMError.CompileError;
        const file_str = types.toObject(file_val).as(types.SchemeString);
        const file_path = file_str.data[0..file_str.len];

        const inc = try openIncludeFile(vm, file_path);
        defer inc.deinit(vm.gc.allocator);

        const reader_mod = @import("reader.zig");
        var file_reader = reader_mod.Reader.init(vm.gc, inc.source);
        defer file_reader.deinit();

        while (file_reader.hasMore() catch return VMError.CompileError) {
            var declaration = file_reader.readDatum() catch return VMError.CompileError;
            vm.gc.pushRoot(&declaration);
            defer vm.gc.popRoot();
            try processLibDeclaration(vm, lib_env, declaration, export_names, export_renames);
        }

        file_list = types.cdr(file_list);
    }
}

fn isLibTopLevelForm(expr: Value) bool {
    if (!types.isPair(expr)) return false;
    const head = types.car(expr);
    if (!types.isSymbol(head)) return false;
    const name = types.symbolName(head);
    if (std.mem.eql(u8, name, "define-record-type")) return true;
    if (std.mem.eql(u8, name, "define-values")) return true;
    if (std.mem.eql(u8, name, "include")) return true;
    return false;
}
