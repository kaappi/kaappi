const std = @import("std");
const types = @import("types.zig");
const compiler_mod = @import("compiler.zig");
const Value = types.Value;

const vm_mod = @import("vm.zig");
const VM = vm_mod.VM;
const VMError = vm_mod.VMError;

/// Handle (define-record-type name (ctor field ...) pred (field accessor [mutator]) ...)
/// Desugars into define forms using internal record primitives.
pub fn handleDefineRecordType(vm: *VM, args: Value) VMError!Value {
    // Parse: name
    if (!types.isPair(args)) return VMError.CompileError;
    const type_name_sym = types.car(args);
    if (!types.isSymbol(type_name_sym)) return VMError.CompileError;
    const type_name = types.symbolName(type_name_sym);

    // Parse: (constructor field ...)
    const rest1 = types.cdr(args);
    if (!types.isPair(rest1)) return VMError.CompileError;
    const ctor_spec = types.car(rest1);
    if (!types.isPair(ctor_spec)) return VMError.CompileError;
    const ctor_name_sym = types.car(ctor_spec);
    if (!types.isSymbol(ctor_name_sym)) return VMError.CompileError;
    const ctor_name = types.symbolName(ctor_name_sym);

    // Collect constructor field names (order matters: these are the args to the constructor)
    var ctor_fields: [32][]const u8 = undefined;
    var ctor_field_count: usize = 0;
    var cf = types.cdr(ctor_spec);
    while (cf != types.NIL) {
        if (!types.isPair(cf)) return VMError.CompileError;
        const field_sym = types.car(cf);
        if (!types.isSymbol(field_sym)) return VMError.CompileError;
        if (ctor_field_count >= 32) return VMError.CompileError;
        ctor_fields[ctor_field_count] = types.symbolName(field_sym);
        ctor_field_count += 1;
        cf = types.cdr(cf);
    }

    // Parse: predicate name
    const rest2 = types.cdr(rest1);
    if (!types.isPair(rest2)) return VMError.CompileError;
    const pred_name_sym = types.car(rest2);
    if (!types.isSymbol(pred_name_sym)) return VMError.CompileError;
    const pred_name = types.symbolName(pred_name_sym);

    // Collect all field specs to determine field_names and total field count
    // Field specs: (field-name accessor [mutator])
    var all_field_names: [32][]const u8 = undefined;
    var all_field_count: usize = 0;
    var accessor_names: [32][]const u8 = undefined;
    var mutator_names: [32]?[]const u8 = undefined;

    var field_specs = types.cdr(rest2);
    while (field_specs != types.NIL) {
        if (!types.isPair(field_specs)) return VMError.CompileError;
        const spec = types.car(field_specs);
        if (!types.isPair(spec)) return VMError.CompileError;

        // (field-name accessor [mutator])
        const fname_sym = types.car(spec);
        if (!types.isSymbol(fname_sym)) return VMError.CompileError;
        if (all_field_count >= 32) return VMError.CompileError;
        all_field_names[all_field_count] = types.symbolName(fname_sym);

        const spec_rest = types.cdr(spec);
        if (!types.isPair(spec_rest)) return VMError.CompileError;
        const acc_sym = types.car(spec_rest);
        if (!types.isSymbol(acc_sym)) return VMError.CompileError;
        accessor_names[all_field_count] = types.symbolName(acc_sym);

        // Optional mutator
        const spec_rest2 = types.cdr(spec_rest);
        if (spec_rest2 != types.NIL and types.isPair(spec_rest2)) {
            const mut_sym = types.car(spec_rest2);
            if (!types.isSymbol(mut_sym)) return VMError.CompileError;
            mutator_names[all_field_count] = types.symbolName(mut_sym);
        } else {
            mutator_names[all_field_count] = null;
        }

        all_field_count += 1;
        field_specs = types.cdr(field_specs);
    }

    const num_fields: u8 = @intCast(all_field_count);

    // Create the RecordType value
    var rt_val = vm.gc.allocRecordType(type_name, num_fields) catch return VMError.OutOfMemory;
    vm.gc.pushRoot(&rt_val);
    defer vm.gc.popRoot();

    // Store in a global with an internal name
    const internal_name_buf = std.fmt.allocPrint(vm.gc.allocator, "__record_type_{s}", .{type_name}) catch return VMError.OutOfMemory;
    defer vm.gc.allocator.free(internal_name_buf);
    // Intern the name via allocSymbol so it persists
    const internal_sym = vm.gc.allocSymbol(internal_name_buf) catch return VMError.OutOfMemory;
    const internal_name = types.symbolName(internal_sym);
    vm.globals.put(internal_name, rt_val) catch return VMError.OutOfMemory;

    // Map constructor field names to their indices in the all_fields array
    var ctor_field_indices: [32]usize = undefined;
    for (0..ctor_field_count) |ci| {
        var found = false;
        for (0..all_field_count) |fi| {
            if (std.mem.eql(u8, ctor_fields[ci], all_field_names[fi])) {
                ctor_field_indices[ci] = fi;
                found = true;
                break;
            }
        }
        if (!found) return VMError.CompileError;
    }

    // Generate constructor:
    // (define (make-point x y) (%make-record __record_type_point x y))
    // But we need to handle field ordering: constructor args may be in a different order
    // than the field specs. The constructor always creates fields in the field_spec order.
    {
        // Build the body: (%make-record <type> <fields-in-field-order>)
        // For each field in all_fields order, find it in the constructor args
        // Actually: %make-record takes type + field values in order.
        // The constructor needs to map its parameters to field positions.
        // We'll generate:
        //   (define (ctor p1 p2 ...) (%make-record type p_for_field0 p_for_field1 ...))
        // where p_for_fieldN is the constructor param corresponding to field N.

        var body_args: [34]Value = undefined;
        // body_args[0] = %make-record symbol
        body_args[0] = vm.gc.allocSymbol("%make-record") catch return VMError.OutOfMemory;
        // body_args[1] = internal_name (the record type reference)
        body_args[1] = vm.gc.allocSymbol(internal_name) catch return VMError.OutOfMemory;

        // For each field in order, find its constructor param
        for (0..all_field_count) |fi| {
            var found_in_ctor = false;
            for (0..ctor_field_count) |ci| {
                if (ctor_field_indices[ci] == fi) {
                    body_args[2 + fi] = vm.gc.allocSymbol(ctor_fields[ci]) catch return VMError.OutOfMemory;
                    found_in_ctor = true;
                    break;
                }
            }
            if (!found_in_ctor) {
                if (!vm.globals.contains("__undefined__")) {
                    vm.globals.put("__undefined__", types.UNDEFINED) catch return VMError.OutOfMemory;
                }
                body_args[2 + fi] = vm.gc.allocSymbol("__undefined__") catch return VMError.OutOfMemory;
            }
        }

        const body_list = vm.gc.makeList(body_args[0 .. 2 + all_field_count]) catch return VMError.OutOfMemory;

        // Build parameter list
        var param_syms: [32]Value = undefined;
        for (0..ctor_field_count) |ci| {
            param_syms[ci] = vm.gc.allocSymbol(ctor_fields[ci]) catch return VMError.OutOfMemory;
        }
        const params = vm.gc.makeList(param_syms[0..ctor_field_count]) catch return VMError.OutOfMemory;

        // Build: (define (ctor-name params...) body)
        const define_sym = vm.gc.allocSymbol("define") catch return VMError.OutOfMemory;
        const name_and_params = vm.gc.allocPair(
            vm.gc.allocSymbol(ctor_name) catch return VMError.OutOfMemory,
            params,
        ) catch return VMError.OutOfMemory;
        const define_expr = vm.gc.makeList(&[_]Value{ define_sym, name_and_params, body_list }) catch return VMError.OutOfMemory;

        const func = compiler_mod.compileExpressionWithMacros(vm.gc, define_expr, &vm.macros) catch return VMError.CompileError;
        var func_val = types.makePointer(@ptrCast(func));
        vm.gc.pushRoot(&func_val);
        _ = vm.execute(func) catch |err| {
            vm.gc.popRoot();
            return err;
        };
        vm.gc.popRoot();
    }

    // Generate predicate: (define (pred? v) (%record? v __record_type_point))
    {
        const define_sym = vm.gc.allocSymbol("define") catch return VMError.OutOfMemory;
        const v_sym = vm.gc.allocSymbol("v") catch return VMError.OutOfMemory;
        const pred_sym = vm.gc.allocSymbol(pred_name) catch return VMError.OutOfMemory;
        const record_check_sym = vm.gc.allocSymbol("%record?") catch return VMError.OutOfMemory;
        const type_ref = vm.gc.allocSymbol(internal_name) catch return VMError.OutOfMemory;

        const body = vm.gc.makeList(&[_]Value{ record_check_sym, v_sym, type_ref }) catch return VMError.OutOfMemory;
        const name_and_params = vm.gc.makeList(&[_]Value{ pred_sym, v_sym }) catch return VMError.OutOfMemory;
        const define_expr = vm.gc.makeList(&[_]Value{ define_sym, name_and_params, body }) catch return VMError.OutOfMemory;

        const func = compiler_mod.compileExpressionWithMacros(vm.gc, define_expr, &vm.macros) catch return VMError.CompileError;
        var func_val = types.makePointer(@ptrCast(func));
        vm.gc.pushRoot(&func_val);
        _ = vm.execute(func) catch |err| {
            vm.gc.popRoot();
            return err;
        };
        vm.gc.popRoot();
    }

    // Generate accessors and mutators for each field
    for (0..all_field_count) |fi| {
        // Accessor: (define (accessor p) (%record-ref p <index>))
        {
            const define_sym = vm.gc.allocSymbol("define") catch return VMError.OutOfMemory;
            const p_sym = vm.gc.allocSymbol("p") catch return VMError.OutOfMemory;
            const acc_sym = vm.gc.allocSymbol(accessor_names[fi]) catch return VMError.OutOfMemory;
            const record_ref_sym = vm.gc.allocSymbol("%record-ref") catch return VMError.OutOfMemory;
            const idx_val = types.makeFixnum(@intCast(fi));

            const body = vm.gc.makeList(&[_]Value{ record_ref_sym, p_sym, idx_val }) catch return VMError.OutOfMemory;
            const name_and_params = vm.gc.makeList(&[_]Value{ acc_sym, p_sym }) catch return VMError.OutOfMemory;
            const define_expr = vm.gc.makeList(&[_]Value{ define_sym, name_and_params, body }) catch return VMError.OutOfMemory;

            const func = compiler_mod.compileExpressionWithMacros(vm.gc, define_expr, &vm.macros) catch return VMError.CompileError;
            var func_val = types.makePointer(@ptrCast(func));
            vm.gc.pushRoot(&func_val);
            _ = vm.execute(func) catch |err| {
                vm.gc.popRoot();
                return err;
            };
            vm.gc.popRoot();
        }

        // Mutator (if specified): (define (mutator p v) (%record-set! p <index> v))
        if (mutator_names[fi]) |mut_name| {
            const define_sym = vm.gc.allocSymbol("define") catch return VMError.OutOfMemory;
            const p_sym = vm.gc.allocSymbol("p") catch return VMError.OutOfMemory;
            const v_sym = vm.gc.allocSymbol("v") catch return VMError.OutOfMemory;
            const mut_sym = vm.gc.allocSymbol(mut_name) catch return VMError.OutOfMemory;
            const record_set_sym = vm.gc.allocSymbol("%record-set!") catch return VMError.OutOfMemory;
            const idx_val = types.makeFixnum(@intCast(fi));

            const body = vm.gc.makeList(&[_]Value{ record_set_sym, p_sym, idx_val, v_sym }) catch return VMError.OutOfMemory;
            const name_and_params = vm.gc.makeList(&[_]Value{ mut_sym, p_sym, v_sym }) catch return VMError.OutOfMemory;
            const define_expr = vm.gc.makeList(&[_]Value{ define_sym, name_and_params, body }) catch return VMError.OutOfMemory;

            const func = compiler_mod.compileExpressionWithMacros(vm.gc, define_expr, &vm.macros) catch return VMError.CompileError;
            var func_val = types.makePointer(@ptrCast(func));
            vm.gc.pushRoot(&func_val);
            _ = vm.execute(func) catch |err| {
                vm.gc.popRoot();
                return err;
            };
            vm.gc.popRoot();
        }
    }

    return types.VOID;
}
