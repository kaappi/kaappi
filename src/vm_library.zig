const std = @import("std");
const types = @import("types.zig");
const memory = @import("memory.zig");
const compiler_mod = @import("compiler.zig");
const library_mod = @import("library.zig");
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

    const lib = vm.libraries.get(lib_name) orelse return error.UndefinedVariable;
    var it = lib.exports.iterator();
    while (it.next()) |entry| {
        vm.globals.put(entry.key_ptr.*, entry.value_ptr.*) catch return error.OutOfMemory;
    }
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
                    const func = compiler_mod.compileExpressionWithMacros(vm.gc, body_expr, &vm.macros) catch {
                        vm.gc.allocator.free(lib_name);
                        return VMError.CompileError;
                    };
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
        // Ignore unknown declarations (include, include-ci, cond-expand, etc.)

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
