const std = @import("std");
const types = @import("types.zig");
const compiler_mod = @import("compiler.zig");
const vm_mod = @import("vm.zig");
const vm_library = @import("vm_library.zig");
const vm_records = @import("vm_records.zig");
const Value = types.Value;
const VM = vm_mod.VM;
const VMError = vm_mod.VMError;

pub fn eval(vm: *VM, source: []const u8) VMError!Value {
    const reader_mod = @import("reader.zig");
    var reader = reader_mod.Reader.init(vm.gc, source);
    defer reader.deinit();

    var last_result: Value = types.VOID;
    while (reader.hasMore() catch return VMError.CompileError) {
        const expr = reader.readDatum() catch return VMError.CompileError;
        if (handleTopLevelForm(vm, expr)) |result| {
            last_result = result catch |err| return err;
            continue;
        }
        const func = compiler_mod.compileExpressionWithMacros(vm.gc, expr, &vm.macros, &vm.globals) catch return VMError.CompileError;
        {
            var func_val = types.makePointer(@ptrCast(func));
            vm.gc.pushRoot(&func_val) catch return VMError.OutOfMemory;
            defer vm.gc.popRoot();
            compiler_mod.Compiler.unrootFunction(vm.gc, func);
            last_result = vm.execute(func) catch |err| return err;
        }
    }
    return last_result;
}

pub fn handleTopLevelForm(vm: *VM, expr: Value) ?VMError!Value {
    if (!types.isPair(expr)) return null;
    const head = types.car(expr);
    if (!types.isSymbol(head)) return null;
    const name = types.symbolName(head);

    if (std.mem.eql(u8, name, "import")) return vm_library.handleImport(vm, types.cdr(expr));
    if (std.mem.eql(u8, name, "define-library")) return vm_library.handleDefineLibrary(vm, types.cdr(expr));
    if (std.mem.eql(u8, name, "define-record-type")) return vm_records.handleDefineRecordType(vm, types.cdr(expr));
    if (std.mem.eql(u8, name, "define-values")) return handleDefineValues(vm, types.cdr(expr));
    if (std.mem.eql(u8, name, "include")) return vm_library.handleTopLevelInclude(vm, types.cdr(expr), false);
    if (std.mem.eql(u8, name, "include-ci")) return vm_library.handleTopLevelInclude(vm, types.cdr(expr), true);
    return null;
}

fn handleDefineValues(vm: *VM, args: Value) VMError!Value {
    if (!types.isPair(args)) return VMError.CompileError;
    var formals = types.car(args);
    vm.gc.pushRoot(&formals) catch return VMError.OutOfMemory;
    defer vm.gc.popRoot();
    const rest = types.cdr(args);
    if (!types.isPair(rest)) return VMError.CompileError;
    const expr = types.car(rest);

    const func = compiler_mod.compileExpressionWithMacros(vm.gc, expr, &vm.macros, &vm.globals) catch return VMError.CompileError;
    var func_val = types.makePointer(@ptrCast(func));
    vm.gc.pushRoot(&func_val) catch return VMError.OutOfMemory;
    defer vm.gc.popRoot();
    compiler_mod.Compiler.unrootFunction(vm.gc, func);
    const result = vm.execute(func) catch |err| return err;

    if (types.isMultipleValues(result)) {
        const mv = types.toObject(result).as(types.MultipleValues);
        if (types.isSymbol(formals)) {
            // (define-values x (values 1 2 3)) → x = (1 2 3)
            var result_root = result;
            vm.gc.pushRoot(&result_root) catch return VMError.OutOfMemory;
            defer vm.gc.popRoot();
            var list: Value = types.NIL;
            vm.gc.pushRoot(&list) catch return VMError.OutOfMemory;
            defer vm.gc.popRoot();
            const mv2 = types.toObject(result_root).as(types.MultipleValues);
            var j: usize = mv2.values.len;
            while (j > 0) {
                j -= 1;
                list = vm.gc.allocPair(mv2.values[j], list) catch return VMError.OutOfMemory;
            }
            vm.globals.put(types.symbolName(formals), list) catch return VMError.OutOfMemory;
            vm.global_version +%= 1;
        } else {
            var formal = formals;
            var i: usize = 0;
            var has_rest = false;
            while (formal != types.NIL and i < mv.values.len) {
                if (types.isSymbol(formal)) {
                    // Rest parameter: (define-values (a b . rest) ...)
                    has_rest = true;
                    var result_root = result;
                    vm.gc.pushRoot(&result_root) catch return VMError.OutOfMemory;
                    defer vm.gc.popRoot();
                    var rest_list: Value = types.NIL;
                    vm.gc.pushRoot(&rest_list) catch return VMError.OutOfMemory;
                    defer vm.gc.popRoot();
                    const mv2 = types.toObject(result_root).as(types.MultipleValues);
                    var j: usize = mv2.values.len;
                    while (j > i) {
                        j -= 1;
                        rest_list = vm.gc.allocPair(mv2.values[j], rest_list) catch return VMError.OutOfMemory;
                    }
                    vm.globals.put(types.symbolName(formal), rest_list) catch return VMError.OutOfMemory;
                    vm.global_version +%= 1;
                    formal = types.NIL;
                    i = mv.values.len;
                    break;
                }
                if (!types.isPair(formal)) return VMError.CompileError;
                const var_sym = types.car(formal);
                if (!types.isSymbol(var_sym)) return VMError.CompileError;
                vm.globals.put(types.symbolName(var_sym), mv.values[i]) catch return VMError.OutOfMemory;
                vm.global_version +%= 1;
                formal = types.cdr(formal);
                i += 1;
            }
            if (!has_rest) {
                if (types.isPair(formal)) return VMError.CompileError;
                if (i < mv.values.len and formal == types.NIL) return VMError.CompileError;
            }
        }
    } else {
        if (types.isSymbol(formals)) {
            // (define-values x expr) → x = (result)
            var result_root = result;
            vm.gc.pushRoot(&result_root) catch return VMError.OutOfMemory;
            defer vm.gc.popRoot();
            const list = vm.gc.allocPair(result_root, types.NIL) catch return VMError.OutOfMemory;
            vm.globals.put(types.symbolName(formals), list) catch return VMError.OutOfMemory;
            vm.global_version +%= 1;
        } else if (types.isPair(formals)) {
            const var_sym = types.car(formals);
            if (types.isSymbol(var_sym)) {
                vm.globals.put(types.symbolName(var_sym), result) catch return VMError.OutOfMemory;
                vm.global_version +%= 1;
                const next = types.cdr(formals);
                if (types.isSymbol(next)) {
                    vm.globals.put(types.symbolName(next), types.NIL) catch return VMError.OutOfMemory;
                    vm.global_version +%= 1;
                }
            }
        }
    }
    return types.VOID;
}
