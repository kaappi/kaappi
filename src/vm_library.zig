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

/// Handle (import import-set ...)
/// Each import-set is one of:
///   (lib-name ...)          — import all exports
///   (only (lib) id ...)     — import only named ids
///   (except (lib) id ...)   — import all except named ids
///   (prefix (lib) prefix)   — prefix all imported names
///   (rename (lib) (old new) ...) — rename on import
pub fn handleImport(vm: *VM, args: Value) VMError!Value {
    var current = args;
    while (current != types.NIL) {
        if (!types.isPair(current)) return VMError.CompileError;
        const import_set = types.car(current);
        processImportSet(vm, import_set) catch return VMError.CompileError;
        current = types.cdr(current);
    }
    return types.VOID;
}

fn processImportSet(vm: *VM, import_set: Value) !void {
    if (!types.isPair(import_set)) return error.InvalidSyntax;

    const first = types.car(import_set);

    // Check for import modifiers
    if (types.isSymbol(first)) {
        const modifier = types.symbolName(first);

        if (std.mem.eql(u8, modifier, "only")) {
            return processImportOnly(vm, types.cdr(import_set));
        }
        if (std.mem.eql(u8, modifier, "except")) {
            return processImportExcept(vm, types.cdr(import_set));
        }
        if (std.mem.eql(u8, modifier, "prefix")) {
            return processImportPrefix(vm, types.cdr(import_set));
        }
        if (std.mem.eql(u8, modifier, "rename")) {
            return processImportRename(vm, types.cdr(import_set));
        }
    }

    // Plain library name: (scheme base) etc.
    const lib_name = library_mod.libraryNameToString(vm.gc.allocator, import_set) catch return error.InvalidSyntax;
    defer vm.gc.allocator.free(lib_name);

    // Try built-in registry first
    if (vm.libraries.get(lib_name)) |lib| {
        var it = lib.exports.iterator();
        while (it.next()) |entry| {
            vm.globals.put(entry.key_ptr.*, entry.value_ptr.*) catch return error.OutOfMemory;
        }
        return;
    }

    // Not found in registry — try loading from .sld file
    tryLoadLibraryFromFile(vm, import_set) catch return error.UndefinedVariable;

    // Now try again
    const lib = vm.libraries.get(lib_name) orelse return error.UndefinedVariable;
    var it = lib.exports.iterator();
    while (it.next()) |entry| {
        vm.globals.put(entry.key_ptr.*, entry.value_ptr.*) catch return error.OutOfMemory;
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

    while (rdr.hasMore()) {
        const expr = rdr.readDatum() catch return error.InvalidSyntax;

        if (vm.handleTopLevelForm(expr)) |result| {
            _ = result catch return error.OutOfMemory;
        } else {
            const func = compiler_mod.compileExpressionWithMacros(vm.gc, expr, &vm.macros, &vm.globals) catch return error.InvalidSyntax;
            var func_val = types.makePointer(@ptrCast(func));
            vm.gc.pushRoot(&func_val);
            _ = vm.execute(func) catch |err| {
                vm.gc.popRoot();
                return err;
            };
            vm.gc.popRoot();
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
        const fd = std.posix.openat(std.posix.AT.FDCWD, full_path, .{}, 0) catch continue;
        _ = std.posix.system.close(fd);

        // File exists — return heap-allocated copy
        return allocator.dupe(u8, full_path) catch null;
    }

    return null;
}

const LibraryMeta = struct {
    export_names: [128][]const u8,
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
        .export_count = 0,
        .lib_name = "",
    };

    while (rdr.hasMore()) {
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
                        result.export_count += 1;
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
fn tryLoadLibraryFromFile(vm: *VM, name_list: Value) !void {
    const allocator = vm.gc.allocator;

    var path_buf: [512]u8 = undefined;
    const rel_path = buildLibRelPath(name_list, &path_buf) catch return error.InvalidSyntax;

    // Resolve the .sld file path
    const sld_path = resolveLibraryPath(allocator, rel_path, vm.lib_paths) orelse
        return error.UndefinedVariable;
    defer allocator.free(sld_path);

    // Read the source file
    const source = readFileContents(allocator, sld_path) catch return error.UndefinedVariable;
    defer allocator.free(source);

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
                vm.gc.pushRoot(&func_val);
                _ = vm.execute(func) catch {
                    vm.gc.popRoot();
                    continue;
                };
                vm.gc.popRoot();
            }

            // Register the library with its exports
            var lib = library_mod.Library.initOwned(allocator, meta.lib_name);
            for (meta.export_names[0..meta.export_count]) |exp_name| {
                if (vm.globals.get(exp_name)) |val| {
                    lib.addExport(exp_name, val) catch {
                        lib.deinit();
                        return error.OutOfMemory;
                    };
                }
            }
            vm.libraries.register(lib) catch {
                lib.deinit();
                return error.OutOfMemory;
            };
            return;
        }
    }

    // No cache — compile from source and collect functions for caching
    var compiled_funcs: std.ArrayList(*types.Function) = .empty;
    defer compiled_funcs.deinit(allocator);

    vm.lib_compile_collect = &compiled_funcs;
    loadLibrarySource(vm, source) catch {
        vm.lib_compile_collect = null;
        return error.UndefinedVariable;
    };
    vm.lib_compile_collect = null;

    // Save .sbc cache (best effort)
    if (compiled_funcs.items.len > 0) {
        if (sbc_path) |sp| {
            bytecode_file.writeFileWithTopLevel(allocator, compiled_funcs.items, source_hash, sp) catch {};
        }
    }
}

/// Read file contents (duplicated from main.zig since we can't import it)
fn readFileContents(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const fd = std.posix.openat(std.posix.AT.FDCWD, path, .{}, 0) catch return error.InvalidSyntax;
    defer _ = std.posix.system.close(fd);

    var result: std.ArrayList(u8) = .empty;
    defer result.deinit(allocator);

    var tmp: [4096]u8 = undefined;
    while (true) {
        const bytes_read = std.posix.read(fd, &tmp) catch return error.InvalidSyntax;
        if (bytes_read == 0) break;
        result.appendSlice(allocator, tmp[0..bytes_read]) catch return error.OutOfMemory;
    }

    return result.toOwnedSlice(allocator);
}

fn processImportOnly(vm: *VM, args: Value) !void {
    // (only (lib-name) id ...)
    if (!types.isPair(args)) return error.InvalidSyntax;
    const lib_spec = types.car(args);
    const ids = types.cdr(args);

    const lib_name = library_mod.libraryNameToString(vm.gc.allocator, lib_spec) catch return error.InvalidSyntax;
    defer vm.gc.allocator.free(lib_name);

    const lib = vm.libraries.get(lib_name) orelse return error.UndefinedVariable;

    var id_list = ids;
    while (id_list != types.NIL) {
        if (!types.isPair(id_list)) return error.InvalidSyntax;
        const id = types.car(id_list);
        if (!types.isSymbol(id)) return error.InvalidSyntax;
        const id_name = types.symbolName(id);
        if (lib.exports.get(id_name)) |val| {
            vm.globals.put(id_name, val) catch return error.OutOfMemory;
        }
        id_list = types.cdr(id_list);
    }
}

fn processImportExcept(vm: *VM, args: Value) !void {
    // (except (lib-name) id ...)
    if (!types.isPair(args)) return error.InvalidSyntax;
    const lib_spec = types.car(args);
    const ids = types.cdr(args);

    const lib_name = library_mod.libraryNameToString(vm.gc.allocator, lib_spec) catch return error.InvalidSyntax;
    defer vm.gc.allocator.free(lib_name);

    const lib = vm.libraries.get(lib_name) orelse return error.UndefinedVariable;

    // Collect excluded names
    var excluded: [64][]const u8 = undefined;
    var excluded_count: usize = 0;
    var id_list = ids;
    while (id_list != types.NIL) {
        if (!types.isPair(id_list)) return error.InvalidSyntax;
        const id = types.car(id_list);
        if (!types.isSymbol(id)) return error.InvalidSyntax;
        if (excluded_count < 64) {
            excluded[excluded_count] = types.symbolName(id);
            excluded_count += 1;
        }
        id_list = types.cdr(id_list);
    }

    // Import all except excluded
    var it = lib.exports.iterator();
    while (it.next()) |entry| {
        var is_excluded = false;
        for (excluded[0..excluded_count]) |exc| {
            if (std.mem.eql(u8, entry.key_ptr.*, exc)) {
                is_excluded = true;
                break;
            }
        }
        if (!is_excluded) {
            vm.globals.put(entry.key_ptr.*, entry.value_ptr.*) catch return error.OutOfMemory;
        }
    }
}

fn processImportPrefix(vm: *VM, args: Value) !void {
    // (prefix (lib-name) prefix-id)
    if (!types.isPair(args)) return error.InvalidSyntax;
    const lib_spec = types.car(args);
    const rest = types.cdr(args);
    if (!types.isPair(rest)) return error.InvalidSyntax;
    const prefix_sym = types.car(rest);
    if (!types.isSymbol(prefix_sym)) return error.InvalidSyntax;
    const prefix = types.symbolName(prefix_sym);

    const lib_name = library_mod.libraryNameToString(vm.gc.allocator, lib_spec) catch return error.InvalidSyntax;
    defer vm.gc.allocator.free(lib_name);

    const lib = vm.libraries.get(lib_name) orelse return error.UndefinedVariable;

    var it = lib.exports.iterator();
    while (it.next()) |entry| {
        // Create prefixed name by interning a symbol through the GC.
        // This ensures the name string is owned by the GC and won't leak.
        const prefixed_buf = std.fmt.allocPrint(vm.gc.allocator, "{s}{s}", .{ prefix, entry.key_ptr.* }) catch return error.OutOfMemory;
        defer vm.gc.allocator.free(prefixed_buf);
        // Intern via allocSymbol so the name persists in the symbol table
        const sym = vm.gc.allocSymbol(prefixed_buf) catch return error.OutOfMemory;
        const interned_name = types.symbolName(sym);
        vm.globals.put(interned_name, entry.value_ptr.*) catch return error.OutOfMemory;
    }
}

fn processImportRename(vm: *VM, args: Value) !void {
    // (rename (lib-name) (old new) ...)
    if (!types.isPair(args)) return error.InvalidSyntax;
    const lib_spec = types.car(args);
    const renames = types.cdr(args);

    const lib_name = library_mod.libraryNameToString(vm.gc.allocator, lib_spec) catch return error.InvalidSyntax;
    defer vm.gc.allocator.free(lib_name);

    const lib = vm.libraries.get(lib_name) orelse return error.UndefinedVariable;

    // Collect rename mappings
    var rename_old: [32][]const u8 = undefined;
    var rename_new: [32][]const u8 = undefined;
    var rename_count: usize = 0;
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
        if (rename_count < 32) {
            rename_old[rename_count] = types.symbolName(old_sym);
            rename_new[rename_count] = types.symbolName(new_sym);
            rename_count += 1;
        }
        rename_list = types.cdr(rename_list);
    }

    // Import all exports, applying renames
    var it = lib.exports.iterator();
    while (it.next()) |entry| {
        var imported_name = entry.key_ptr.*;
        for (0..rename_count) |i| {
            if (std.mem.eql(u8, entry.key_ptr.*, rename_old[i])) {
                imported_name = rename_new[i];
                break;
            }
        }
        vm.globals.put(imported_name, entry.value_ptr.*) catch return error.OutOfMemory;
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
    const decls = types.cdr(args);

    // Convert library name list to canonical string
    const lib_name = library_mod.libraryNameToString(vm.gc.allocator, name_list) catch return VMError.CompileError;
    // lib_name is owned by allocator; we need it to persist in the registry.
    // The registry key will reference this string.

    // Collect export names and process declarations
    var export_names: [128][]const u8 = undefined;
    var export_count: usize = 0;

    // First pass: collect exports and process imports/begin
    var decl = decls;
    while (decl != types.NIL) {
        if (!types.isPair(decl)) {
            vm.gc.allocator.free(lib_name);
            return VMError.CompileError;
        }
        const declaration = types.car(decl);
        if (!types.isPair(declaration)) {
            vm.gc.allocator.free(lib_name);
            return VMError.CompileError;
        }

        const decl_head = types.car(declaration);
        if (!types.isSymbol(decl_head)) {
            vm.gc.allocator.free(lib_name);
            return VMError.CompileError;
        }
        const decl_name = types.symbolName(decl_head);

        if (std.mem.eql(u8, decl_name, "export")) {
            // (export id ...)
            var id_list = types.cdr(declaration);
            while (id_list != types.NIL) {
                if (!types.isPair(id_list)) {
                    vm.gc.allocator.free(lib_name);
                    return VMError.CompileError;
                }
                const id = types.car(id_list);
                if (!types.isSymbol(id)) {
                    vm.gc.allocator.free(lib_name);
                    return VMError.CompileError;
                }
                if (export_count < 128) {
                    export_names[export_count] = types.symbolName(id);
                    export_count += 1;
                }
                id_list = types.cdr(id_list);
            }
        } else if (std.mem.eql(u8, decl_name, "import")) {
            // (import import-set ...)
            // Process imports into the current globals (which the begin body will use)
            _ = handleImport(vm, types.cdr(declaration)) catch {
                vm.gc.allocator.free(lib_name);
                return VMError.CompileError;
            };
        } else if (std.mem.eql(u8, decl_name, "begin")) {
            // (begin expr ...)
            // Evaluate expressions in the current environment
            var body = types.cdr(declaration);
            while (body != types.NIL) {
                if (!types.isPair(body)) {
                    vm.gc.allocator.free(lib_name);
                    return VMError.CompileError;
                }
                const body_expr = types.car(body);

                // Check for top-level forms in begin body
                if (vm.handleTopLevelForm(body_expr)) |result| {
                    _ = result catch {
                        vm.gc.allocator.free(lib_name);
                        return VMError.CompileError;
                    };
                } else {
                    const func = compiler_mod.compileExpressionWithMacros(vm.gc, body_expr, &vm.macros, &vm.globals) catch {
                        vm.gc.allocator.free(lib_name);
                        return VMError.CompileError;
                    };
                    // Collect compiled function for .sbc caching
                    if (vm.lib_compile_collect) |collect| {
                        collect.append(vm.gc.allocator, func) catch {};
                    }
                    var func_val = types.makePointer(@ptrCast(func));
                    vm.gc.pushRoot(&func_val);
                    _ = vm.execute(func) catch |err| {
                        vm.gc.popRoot();
                        vm.gc.allocator.free(lib_name);
                        return err;
                    };
                    vm.gc.popRoot();
                }

                body = types.cdr(body);
            }
        }
        else if (std.mem.eql(u8, decl_name, "include") or std.mem.eql(u8, decl_name, "include-ci")) {
            // (include "file.scm" ...)
            var file_list = types.cdr(declaration);
            while (file_list != types.NIL) {
                if (!types.isPair(file_list)) {
                    vm.gc.allocator.free(lib_name);
                    return VMError.CompileError;
                }
                const file_val = types.car(file_list);
                if (!types.isString(file_val)) {
                    vm.gc.allocator.free(lib_name);
                    return VMError.CompileError;
                }
                const file_str = types.toObject(file_val).as(types.SchemeString);
                const file_path = file_str.data[0..file_str.len];

                const file_source = readFileContents(vm.gc.allocator, file_path) catch {
                    vm.gc.allocator.free(lib_name);
                    return VMError.CompileError;
                };
                defer vm.gc.allocator.free(file_source);

                // Parse and evaluate the included file
                const reader_mod = @import("reader.zig");
                var file_reader = reader_mod.Reader.init(vm.gc, file_source);
                defer file_reader.deinit();

                while (file_reader.hasMore()) {
                    const inc_expr = file_reader.readDatum() catch {
                        vm.gc.allocator.free(lib_name);
                        return VMError.CompileError;
                    };

                    if (vm.handleTopLevelForm(inc_expr)) |inc_result| {
                        _ = inc_result catch {
                            vm.gc.allocator.free(lib_name);
                            return VMError.CompileError;
                        };
                    } else {
                        const func = compiler_mod.compileExpressionWithMacros(vm.gc, inc_expr, &vm.macros, &vm.globals) catch {
                            vm.gc.allocator.free(lib_name);
                            return VMError.CompileError;
                        };
                        // Collect compiled function for .sbc caching
                        if (vm.lib_compile_collect) |collect| {
                            collect.append(vm.gc.allocator, func) catch {};
                        }
                        var func_val = types.makePointer(@ptrCast(func));
                        vm.gc.pushRoot(&func_val);
                        _ = vm.execute(func) catch |err| {
                            vm.gc.popRoot();
                            vm.gc.allocator.free(lib_name);
                            return err;
                        };
                        vm.gc.popRoot();
                    }
                }

                file_list = types.cdr(file_list);
            }
        }
        // Ignore unknown declarations (cond-expand, include-ci, etc.)

        decl = types.cdr(decl);
    }

    // Create the library with exported bindings.
    // Use initOwned so the library takes ownership of lib_name.
    var lib = library_mod.Library.initOwned(vm.gc.allocator, lib_name);
    for (export_names[0..export_count]) |exp_name| {
        if (vm.globals.get(exp_name)) |val| {
            lib.addExport(exp_name, val) catch {
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
