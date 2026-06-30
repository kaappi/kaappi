const std = @import("std");
const types = @import("types.zig");
const memory = @import("memory.zig");
const compiler_mod = @import("compiler.zig");
const library_mod = @import("library.zig");
const bytecode_file = @import("bytecode_file.zig");
const Value = types.Value;

const vm_mod = @import("vm.zig");
const VM = vm_mod.VM;
const VMError = vm_mod.VMError;

/// Import a binding into the target environment, routing macros to vm.macros.
fn importBinding(vm: *VM, target: *std.StringHashMap(Value), name: []const u8, val: Value) !void {
    target.put(name, val) catch return error.OutOfMemory;
    if (types.isTransformer(val)) {
        if (target == &vm.globals) {
            vm.macros.put(name, val) catch return error.OutOfMemory;
        }
        const tx = types.toObject(val).as(types.Transformer);
        if (tx.def_env) |env| {
            var it = env.iterator();
            while (it.next()) |entry| {
                if (!target.contains(entry.key_ptr.*)) {
                    target.put(entry.key_ptr.*, entry.value_ptr.*) catch return error.OutOfMemory;
                    if (target == &vm.globals) vm.global_version +%= 1;
                }
            }
        }
        return;
    }
    if (target == &vm.globals) {
        vm.global_version +%= 1;
    }
}

/// Handle (import import-set ...) into a specific target environment.
pub fn handleImportInto(vm: *VM, target: *std.StringHashMap(Value), args: Value) VMError!Value {
    var current = args;
    while (current != types.NIL) {
        if (!types.isPair(current)) return VMError.CompileError;
        const import_set = types.car(current);
        processImportSet(vm, target, import_set) catch return VMError.CompileError;
        current = types.cdr(current);
    }
    return types.VOID;
}

/// Handle (import import-set ...) — top-level variant that imports into vm.globals.
pub fn handleImport(vm: *VM, args: Value) VMError!Value {
    return handleImportInto(vm, &vm.globals, args);
}

fn processImportSet(vm: *VM, target: *std.StringHashMap(Value), import_set: Value) !void {
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
fn buildLibRelPath(name_list: Value, buf: *[512]u8) ![]const u8 {
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

/// Load and evaluate a library source file from a resolved path.
fn loadLibrarySource(vm: *VM, source: []const u8) !void {
    const reader_mod = @import("reader.zig");
    var rdr = reader_mod.Reader.init(vm.gc, source);
    defer rdr.deinit();

    while (rdr.hasMore() catch return error.InvalidSyntax) {
        const expr = rdr.readDatum() catch return error.InvalidSyntax;

        if (vm.handleTopLevelForm(expr)) |result| {
            _ = result catch |err| return err;
        } else {
            const func = compiler_mod.compileExpressionWithMacros(vm.gc, expr, &vm.macros, &vm.globals) catch return error.InvalidSyntax;
            var func_val = types.makePointer(@ptrCast(func));
            try vm.gc.pushRoot(&func_val);
            defer vm.gc.popRoot();
            compiler_mod.Compiler.unrootFunction(vm.gc, func);
            _ = try vm.execute(func);
        }
    }
}

/// Resolve the full path for a library .sld file.
/// Returns a heap-allocated path string, or null if not found.
fn resolveLibraryPath(allocator: std.mem.Allocator, rel_path: []const u8, lib_paths: []const []const u8) ?[]u8 {
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
        const probe_fd = std.c.open(probe_z, .{});
        if (probe_fd < 0) continue;
        _ = std.c.close(probe_fd);

        // File exists — return heap-allocated copy
        return allocator.dupe(u8, full_path) catch null;
    }

    return null;
}

const LibraryMeta = struct {
    export_names: [128][]const u8,
    export_renames: [128]?[]const u8,
    export_count: usize,
    lib_name: []const u8,
};

/// Parse a .sld file and extract only the export names and process imports,
/// without compiling or evaluating begin blocks.
/// Used on cache hit to reconstruct the library's export table.
fn extractExportsAndImports(vm: *VM, source: []const u8) !LibraryMeta {
    const reader_mod = @import("reader.zig");
    var rdr = reader_mod.Reader.init(vm.gc, source);
    defer rdr.deinit();

    var result: LibraryMeta = .{
        .export_names = undefined,
        .export_renames = undefined,
        .export_count = 0,
        .lib_name = "",
    };

    while (rdr.hasMore() catch return error.InvalidSyntax) {
        const expr = rdr.readDatum() catch return error.InvalidSyntax;

        if (!types.isPair(expr)) continue;
        const head = types.car(expr);
        if (!types.isSymbol(head)) continue;
        if (!std.mem.eql(u8, types.symbolName(head), "define-library")) continue;

        const args = types.cdr(expr);
        if (!types.isPair(args)) continue;
        const name_list = types.car(args);
        result.lib_name = library_mod.libraryNameToString(vm.gc.allocator, name_list) catch return error.InvalidSyntax;

        var decl = types.cdr(args);
        while (decl != types.NIL) {
            if (!types.isPair(decl)) break;
            const declaration = types.car(decl);
            decl = types.cdr(decl);

            if (!types.isPair(declaration)) continue;
            const decl_head = types.car(declaration);
            if (!types.isSymbol(decl_head)) continue;
            const decl_name = types.symbolName(decl_head);

            if (std.mem.eql(u8, decl_name, "export")) {
                var id_list = types.cdr(declaration);
                while (id_list != types.NIL) {
                    if (!types.isPair(id_list)) break;
                    const id = types.car(id_list);
                    if (types.isSymbol(id) and result.export_count < 128) {
                        result.export_names[result.export_count] = types.symbolName(id);
                        result.export_renames[result.export_count] = null;
                        result.export_count += 1;
                    } else if (types.isPair(id)) {
                        const eh = types.car(id);
                        if (types.isSymbol(eh) and std.mem.eql(u8, types.symbolName(eh), "rename")) {
                            const rename_args = types.cdr(id);
                            if (types.isPair(rename_args)) {
                                const os = types.car(rename_args);
                                const nr = types.cdr(rename_args);
                                if (types.isPair(nr) and types.isSymbol(os)) {
                                    const ns = types.car(nr);
                                    if (types.isSymbol(ns) and result.export_count < 128) {
                                        result.export_names[result.export_count] = types.symbolName(os);
                                        result.export_renames[result.export_count] = types.symbolName(ns);
                                        result.export_count += 1;
                                    }
                                }
                            }
                        }
                    }
                    id_list = types.cdr(id_list);
                }
            } else if (std.mem.eql(u8, decl_name, "import")) {
                // Process imports so dependencies are available for cached code
                _ = handleImport(vm, types.cdr(declaration)) catch {};
            }
        }
        break; // Only process the first define-library form
    }

    return result;
}

/// Try to load a library from a .sld file on disk.
/// Search order: ./rel_path, ./lib/rel_path, then each --lib-path entry.
/// Uses .sbc caching: on cache hit, executes cached bytecode and re-parses
/// the .sld for export/import declarations. On cache miss, compiles normally
/// and saves the .sbc file.
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
    return readFileContents(allocator, path);
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

fn tryLoadLibraryFromFile(vm: *VM, name_list: Value) !void {
    if (vm.sandbox_mode) {
        vm.setErrorDetail("sandbox: cannot load library from file", .{});
        return error.UndefinedVariable;
    }

    const allocator = vm.gc.allocator;

    var path_buf: [512]u8 = undefined;
    const rel_path = buildLibRelPath(name_list, &path_buf) catch return error.InvalidSyntax;

    // Check bundled files first (standalone binary support)
    if (vm.bundled_files) |bf| {
        if (findBundledSource(bf, rel_path, vm.lib_paths)) |found| {
            const sld_dir = extractDir(found.path);
            const saved_lib_dir = vm.current_lib_dir;
            vm.current_lib_dir = sld_dir;
            defer vm.current_lib_dir = saved_lib_dir;
            loadLibrarySource(vm, found.source) catch return error.UndefinedVariable;
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
    const source = readFileContents(allocator, sld_path) catch return error.UndefinedVariable;
    defer allocator.free(source);

    // Record for bundling
    recordFileForBundle(vm, sld_path, source);

    const source_hash = bytecode_file.sourceHash(source);

    // Try .sbc cache
    const sbc_path = bytecode_file.getSbcPath(allocator, sld_path) catch null;
    defer if (sbc_path) |p| allocator.free(p);

    if (sbc_path) |sp| {
        if (bytecode_file.readFileWithTopLevel(vm.gc, source_hash, sp) catch null) |loaded| {
            defer allocator.free(loaded.funcs);

            // Cache hit — re-parse .sld for export/import declarations
            const meta = extractExportsAndImports(vm, source) catch {
                // Fall through to source compilation on parse error
                loadLibrarySource(vm, source) catch return error.UndefinedVariable;
                return;
            };

            if (meta.lib_name.len == 0) {
                // No define-library found — fall through to source compilation
                loadLibrarySource(vm, source) catch return error.UndefinedVariable;
                return;
            }

            // Execute cached functions (they define globals)
            const top_count = @min(loaded.top_level_count, @as(u32, @intCast(loaded.funcs.len)));
            for (loaded.funcs[0..top_count]) |func| {
                var func_val = types.makePointer(@ptrCast(func));
                vm.gc.pushRoot(&func_val) catch return error.OutOfMemory;
                _ = vm.execute(func) catch {
                    vm.gc.popRoot();
                    continue;
                };
                vm.gc.popRoot();
            }

            // Register the library with its exports
            var lib = library_mod.Library.initOwned(allocator, meta.lib_name);
            var all_exports_found = true;
            for (0..meta.export_count) |ei| {
                const internal = meta.export_names[ei];
                const exported = meta.export_renames[ei] orelse internal;
                if (vm.globals.get(internal)) |val| {
                    lib.addExport(exported, val) catch {
                        lib.deinit();
                        return error.OutOfMemory;
                    };
                } else {
                    // Macro exports can't be restored from cached bytecode
                    all_exports_found = false;
                    break;
                }
            }
            if (all_exports_found) {
                vm.libraries.register(lib) catch {
                    lib.deinit();
                    return error.OutOfMemory;
                };
                return;
            }
            // Cache didn't restore all exports (macros) — fall through to source compilation
            lib.deinit();
        }
    }

    // Compile from source (skip .sbc caching for .sld files — collected function
    // pointers can be freed by GC during library loading, causing use-after-free
    // in the serializer)
    loadLibrarySource(vm, source) catch {
        return error.UndefinedVariable;
    };
}

/// Evaluate a feature requirement for cond-expand in define-library.
/// Unlike the compiler's evalFeatureReq, this has access to the VM's live library registry.
fn evalLibFeatureReq(vm: *VM, req: Value) bool {
    if (types.isSymbol(req)) {
        const name = types.symbolName(req);
        const known = [_][]const u8{ "r7rs", "kaappi", "ieee-float", "posix", "exact-closed", "exact-complex" };
        for (known) |f| {
            if (std.mem.eql(u8, name, f)) return true;
        }
        return false;
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
            return vm.libraries.get(lib_name) != null;
        }
    }
    return false;
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
    // include-ci should fold case while reading; the reader currently only
    // honors inline `#!fold-case` directives, so the two behave identically.
    _ = ci;

    const reader_mod = @import("reader.zig");

    // Root the argument spine: evaluating included forms allocates and may
    // trigger GC, which would otherwise reclaim the pair list and filename
    // strings we are still walking.
    var file_list = args;
    vm.gc.pushRoot(&file_list) catch return VMError.OutOfMemory;
    defer vm.gc.popRoot();

    while (file_list != types.NIL) {
        if (!types.isPair(file_list)) return VMError.CompileError;
        const file_val = types.car(file_list);
        if (!types.isString(file_val)) return VMError.CompileError;
        const file_str = types.toObject(file_val).as(types.SchemeString);
        const file_path = file_str.data[0..file_str.len];

        // Resolve include path: relative to the including file's dir, then cwd.
        var resolved_path: ?[]u8 = null;
        if (vm.current_lib_dir) |dir| {
            if (dir.len > 0 and file_path.len > 0 and file_path[0] != '/') {
                resolved_path = std.fmt.allocPrint(vm.gc.allocator, "{s}{s}", .{ dir, file_path }) catch null;
            }
        }
        defer if (resolved_path) |rp| vm.gc.allocator.free(rp);

        var used_path: []const u8 = file_path;
        const file_source = blk: {
            if (resolved_path) |rp| {
                if (readFileOrBundled(vm.gc.allocator, rp, vm.bundled_files)) |src| {
                    used_path = rp;
                    break :blk src;
                } else |_| {}
            }
            break :blk readFileOrBundled(vm.gc.allocator, file_path, vm.bundled_files) catch return VMError.CompileError;
        };
        defer vm.gc.allocator.free(file_source);

        // Record for bundling (both resolved and original paths, so lookups
        // succeed regardless of current_lib_dir at runtime)
        recordFileForBundle(vm, used_path, file_source);
        if (!std.mem.eql(u8, used_path, file_path)) {
            recordFileForBundle(vm, file_path, file_source);
        }

        // Own a copy of the path: error reporting and current_lib_dir slice into
        // it across operations that may free `resolved_path` or GC `file_path`.
        const owned_path = vm.gc.allocator.dupe(u8, used_path) catch return VMError.OutOfMemory;
        defer vm.gc.allocator.free(owned_path);

        // Nested includes within this file resolve relative to this file's dir.
        const saved_lib_dir = vm.current_lib_dir;
        vm.current_lib_dir = extractDir(owned_path);
        defer vm.current_lib_dir = saved_lib_dir;

        var file_reader = reader_mod.Reader.initWithName(vm.gc, file_source, owned_path);
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

    const func = compiler_mod.compileExpressionWithMacros(vm.gc, expr, &vm.macros, &vm.globals) catch |err| {
        reportIncludeError(vm, path, line, null, err);
        return;
    };
    if (vm.lib_compile_collect) |collect| {
        collect.append(vm.gc.allocator, func) catch {};
    }
    var func_val = types.makePointer(@ptrCast(func));
    vm.gc.pushRoot(&func_val) catch {
        reportIncludeError(vm, path, line, null, error.OutOfMemory);
        return;
    };
    defer vm.gc.popRoot();
    compiler_mod.Compiler.unrootFunction(vm.gc, func);
    _ = vm.execute(func) catch |err| {
        reportIncludeError(vm, path, line, vm.getErrorDetail(), err);
        vm.last_error_detail_len = 0;
        return;
    };
}

fn reportIncludeError(vm: *VM, path: []const u8, line: u32, detail: ?[]const u8, err: anyerror) void {
    _ = vm;
    var buf: [320]u8 = undefined;
    const s = if (detail) |d| (if (d.len > 0)
        std.fmt.bufPrint(&buf, "{s}:{d}: error: {s}\n", .{ path, line, d }) catch "include error\n"
    else
        std.fmt.bufPrint(&buf, "{s}:{d}: runtime error: {}\n", .{ path, line, err }) catch "include error\n") else std.fmt.bufPrint(&buf, "{s}:{d}: error: {}\n", .{ path, line, err }) catch "include error\n";
    vm_mod.writeStderr(s);
}

fn extractDir(path: []const u8) []const u8 {
    if (std.mem.lastIndexOfScalar(u8, path, '/')) |pos| {
        return path[0 .. pos + 1];
    }
    return "";
}

/// Read file contents (duplicated from main.zig since we can't import it)
fn readFileContents(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const path_z = allocator.dupeZ(u8, path) catch return error.OutOfMemory;
    defer allocator.free(path_z);

    const fd = std.c.open(path_z, .{});
    if (fd < 0) return error.InvalidSyntax;
    defer _ = std.c.close(fd);

    const max_size: usize = 1024 * 1024;
    var result: std.ArrayList(u8) = .empty;
    defer result.deinit(allocator);

    var tmp: [4096]u8 = undefined;
    while (true) {
        const raw = std.c.read(fd, &tmp, tmp.len);
        if (raw <= 0) break;
        const bytes_read: usize = @intCast(raw);
        if (result.items.len + bytes_read > max_size) return error.InvalidSyntax;
        result.appendSlice(allocator, tmp[0..bytes_read]) catch return error.OutOfMemory;
    }

    return result.toOwnedSlice(allocator);
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

    var id_list = ids;
    while (id_list != types.NIL) {
        if (!types.isPair(id_list)) return error.InvalidSyntax;
        const id = types.car(id_list);
        if (!types.isSymbol(id)) return error.InvalidSyntax;
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

    var excluded_list: std.ArrayList([]const u8) = .empty;
    defer excluded_list.deinit(vm.gc.allocator);
    var id_list = ids;
    while (id_list != types.NIL) {
        if (!types.isPair(id_list)) return error.InvalidSyntax;
        const id = types.car(id_list);
        if (!types.isSymbol(id)) return error.InvalidSyntax;
        excluded_list.append(vm.gc.allocator, types.symbolName(id)) catch return error.OutOfMemory;
        id_list = types.cdr(id_list);
    }

    var it = source.iterator();
    while (it.next()) |entry| {
        var is_excluded = false;
        for (excluded_list.items) |exc| {
            if (std.mem.eql(u8, entry.key_ptr.*, exc)) {
                is_excluded = true;
                break;
            }
        }
        if (!is_excluded) {
            importBinding(vm, target, entry.key_ptr.*, entry.value_ptr.*) catch return error.OutOfMemory;
        }
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

    var rename_old_list: std.ArrayList([]const u8) = .empty;
    defer rename_old_list.deinit(vm.gc.allocator);
    var rename_new_list: std.ArrayList([]const u8) = .empty;
    defer rename_new_list.deinit(vm.gc.allocator);
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
        rename_old_list.append(vm.gc.allocator, types.symbolName(old_sym)) catch return error.OutOfMemory;
        rename_new_list.append(vm.gc.allocator, types.symbolName(new_sym)) catch return error.OutOfMemory;
        rename_list = types.cdr(rename_list);
    }

    var it = source.iterator();
    while (it.next()) |entry| {
        var imported_name = entry.key_ptr.*;
        for (0..rename_old_list.items.len) |i| {
            if (std.mem.eql(u8, entry.key_ptr.*, rename_old_list.items[i])) {
                imported_name = rename_new_list.items[i];
                break;
            }
        }
        importBinding(vm, target, imported_name, entry.value_ptr.*) catch return error.OutOfMemory;
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
    vm.gc.pushRoot(&decls) catch return VMError.OutOfMemory;
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

    var export_names: [128][]const u8 = undefined;
    var export_renames: [128]?[]const u8 = undefined;
    var export_count: usize = 0;

    var decl = decls;
    while (decl != types.NIL) {
        if (!types.isPair(decl)) return VMError.CompileError;
        const declaration = types.car(decl);
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
                    if (export_count < 128) {
                        export_names[export_count] = types.symbolName(id);
                        export_renames[export_count] = null;
                        export_count += 1;
                    }
                } else if (types.isPair(id)) {
                    const head = types.car(id);
                    if (types.isSymbol(head) and std.mem.eql(u8, types.symbolName(head), "rename")) {
                        const rename_args = types.cdr(id);
                        if (types.isPair(rename_args)) {
                            const old_sym = types.car(rename_args);
                            const rest = types.cdr(rename_args);
                            if (types.isPair(rest) and types.isSymbol(old_sym)) {
                                const new_sym = types.car(rest);
                                if (types.isSymbol(new_sym) and export_count < 128) {
                                    export_names[export_count] = types.symbolName(old_sym);
                                    export_renames[export_count] = types.symbolName(new_sym);
                                    export_count += 1;
                                }
                            }
                        }
                    }
                }
                id_list = types.cdr(id_list);
            }
        } else if (std.mem.eql(u8, decl_name, "import")) {
            _ = handleImportInto(vm, lib_env, types.cdr(declaration)) catch return VMError.CompileError;
        } else if (std.mem.eql(u8, decl_name, "begin")) {
            try compileLibBeginBlock(vm, lib_env, types.cdr(declaration));
        } else if (std.mem.eql(u8, decl_name, "include") or std.mem.eql(u8, decl_name, "include-ci")) {
            try compileLibInclude(vm, lib_env, types.cdr(declaration));
        } else if (std.mem.eql(u8, decl_name, "include-library-declarations")) {
            try includeLibraryDeclarations(vm, lib_env, types.cdr(declaration), &export_names, &export_renames, &export_count);
        } else if (std.mem.eql(u8, decl_name, "cond-expand")) {
            var clauses = types.cdr(declaration);
            var matched = false;
            while (clauses != types.NIL and !matched) {
                if (!types.isPair(clauses)) break;
                const clause = types.car(clauses);
                clauses = types.cdr(clauses);

                if (!types.isPair(clause)) continue;
                const feature_req = types.car(clause);
                const clause_decls = types.cdr(clause);

                const is_else = types.isSymbol(feature_req) and std.mem.eql(u8, types.symbolName(feature_req), "else");
                const feature_match = is_else or evalLibFeatureReq(vm, feature_req);

                if (feature_match) {
                    matched = true;
                    const spliced = clause_decls;
                    var last_pair: Value = types.NIL;
                    var scan = spliced;
                    while (scan != types.NIL and types.isPair(scan)) {
                        last_pair = scan;
                        scan = types.cdr(scan);
                    }
                    if (last_pair != types.NIL) {
                        const remaining = types.cdr(decl);
                        types.setCdr(last_pair, remaining);
                        decl = spliced;
                        continue;
                    } else {
                        decl = types.cdr(decl);
                        continue;
                    }
                }
            }
            if (matched) continue;
        }

        decl = types.cdr(decl);
    }

    var lib = library_mod.Library.initOwned(vm.gc.allocator, lib_name);
    lib.lib_env = lib_env;
    lib_env_owned = false; // library now owns both lib_env and lib_name
    for (0..export_count) |i| {
        const internal_name = export_names[i];
        const exported_name = export_renames[i] orelse internal_name;
        if (lib_env.get(internal_name)) |val| {
            lib.addExport(exported_name, val) catch {
                lib.deinit();
                return VMError.OutOfMemory;
            };
        } else if (vm.macros.get(internal_name)) |val| {
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

    const func = compiler_mod.compileExpressionInEnv(vm.gc, expr, &vm.macros, lib_env) catch return VMError.CompileError;
    if (vm.lib_compile_collect) |collect| {
        collect.append(vm.gc.allocator, func) catch return VMError.OutOfMemory;
    }
    var func_val = types.makePointer(@ptrCast(func));
    vm.gc.pushRoot(&func_val) catch return VMError.OutOfMemory;
    compiler_mod.Compiler.unrootFunction(vm.gc, func);
    defer vm.gc.popRoot();
    _ = try vm.execute(func);
}

/// Compile and evaluate included files in a library context.
fn compileLibInclude(vm: *VM, lib_env: *std.StringHashMap(Value), file_list_val: Value) VMError!void {
    var file_list = file_list_val;
    while (file_list != types.NIL) {
        if (!types.isPair(file_list)) return VMError.CompileError;
        const file_val = types.car(file_list);
        if (!types.isString(file_val)) return VMError.CompileError;
        const file_str = types.toObject(file_val).as(types.SchemeString);
        const file_path = file_str.data[0..file_str.len];

        var resolved_path: ?[]u8 = null;
        if (vm.current_lib_dir) |dir| {
            if (dir.len > 0 and file_path.len > 0 and file_path[0] != '/') {
                resolved_path = std.fmt.allocPrint(vm.gc.allocator, "{s}{s}", .{ dir, file_path }) catch null;
            }
        }
        defer if (resolved_path) |rp| vm.gc.allocator.free(rp);

        const file_source = blk: {
            if (resolved_path) |rp| {
                if (readFileOrBundled(vm.gc.allocator, rp, vm.bundled_files)) |src| break :blk src else |_| {}
            }
            break :blk readFileOrBundled(vm.gc.allocator, file_path, vm.bundled_files) catch return VMError.CompileError;
        };
        defer vm.gc.allocator.free(file_source);

        // Record for bundling (both resolved and original paths)
        if (resolved_path) |rp| {
            recordFileForBundle(vm, rp, file_source);
            if (!std.mem.eql(u8, rp, file_path)) {
                recordFileForBundle(vm, file_path, file_source);
            }
        } else {
            recordFileForBundle(vm, file_path, file_source);
        }

        const reader_mod = @import("reader.zig");
        var file_reader = reader_mod.Reader.init(vm.gc, file_source);
        defer file_reader.deinit();

        while (file_reader.hasMore() catch return VMError.CompileError) {
            const inc_expr = file_reader.readDatum() catch return VMError.CompileError;
            try compileLibExpr(vm, lib_env, inc_expr);
        }

        file_list = types.cdr(file_list);
    }
}

fn includeLibraryDeclarations(
    vm: *VM,
    lib_env: *std.StringHashMap(Value),
    file_list_val: Value,
    export_names: *[128][]const u8,
    export_renames: *[128]?[]const u8,
    export_count: *usize,
) VMError!void {
    var file_list = file_list_val;
    while (file_list != types.NIL) {
        if (!types.isPair(file_list)) return VMError.CompileError;
        const file_val = types.car(file_list);
        if (!types.isString(file_val)) return VMError.CompileError;
        const file_str = types.toObject(file_val).as(types.SchemeString);
        const file_path = file_str.data[0..file_str.len];

        var resolved_path: ?[]u8 = null;
        if (vm.current_lib_dir) |dir| {
            if (dir.len > 0 and file_path.len > 0 and file_path[0] != '/') {
                resolved_path = std.fmt.allocPrint(vm.gc.allocator, "{s}{s}", .{ dir, file_path }) catch null;
            }
        }
        defer if (resolved_path) |rp| vm.gc.allocator.free(rp);

        const file_source = blk: {
            if (resolved_path) |rp| {
                if (readFileOrBundled(vm.gc.allocator, rp, vm.bundled_files)) |src| break :blk src else |_| {}
            }
            break :blk readFileOrBundled(vm.gc.allocator, file_path, vm.bundled_files) catch return VMError.CompileError;
        };
        defer vm.gc.allocator.free(file_source);

        const reader_mod = @import("reader.zig");
        var file_reader = reader_mod.Reader.init(vm.gc, file_source);
        defer file_reader.deinit();

        while (file_reader.hasMore() catch return VMError.CompileError) {
            const declaration = file_reader.readDatum() catch return VMError.CompileError;
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
                        if (export_count.* < 128) {
                            export_names[export_count.*] = types.symbolName(id);
                            export_renames[export_count.*] = null;
                            export_count.* += 1;
                        }
                    } else if (types.isPair(id)) {
                        const rename_head = types.car(id);
                        if (types.isSymbol(rename_head) and std.mem.eql(u8, types.symbolName(rename_head), "rename")) {
                            const rename_args = types.cdr(id);
                            if (types.isPair(rename_args)) {
                                const internal = types.car(rename_args);
                                const rest = types.cdr(rename_args);
                                if (types.isPair(rest) and types.isSymbol(internal)) {
                                    const external = types.car(rest);
                                    if (types.isSymbol(external) and export_count.* < 128) {
                                        export_names[export_count.*] = types.symbolName(internal);
                                        export_renames[export_count.*] = types.symbolName(external);
                                        export_count.* += 1;
                                    }
                                }
                            }
                        }
                    }
                    id_list = types.cdr(id_list);
                }
            } else if (std.mem.eql(u8, decl_name, "import")) {
                _ = handleImportInto(vm, lib_env, types.cdr(declaration)) catch return VMError.CompileError;
            } else if (std.mem.eql(u8, decl_name, "begin")) {
                try compileLibBeginBlock(vm, lib_env, types.cdr(declaration));
            } else if (std.mem.eql(u8, decl_name, "include") or std.mem.eql(u8, decl_name, "include-ci")) {
                try compileLibInclude(vm, lib_env, types.cdr(declaration));
            }
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
    return false;
}
