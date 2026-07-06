const std = @import("std");
const types = @import("types.zig");
const compiler_mod = @import("compiler.zig");
const memory = @import("memory.zig");
const Value = types.Value;
const GC = memory.GC;
const CompileError = compiler_mod.CompileError;

const vm_mod = @import("vm.zig");
const VM = vm_mod.VM;
const VMError = vm_mod.VMError;

/// Handle (define-record-type name (ctor field ...) pred (field accessor [mutator]) ...)
/// Desugars into define forms using internal record primitives.
/// Used for top-level and library-body contexts (VM interpreter path).
pub fn handleDefineRecordType(vm: *VM, args: Value) VMError!Value {
    const spec = parseRecordSpec(args) orelse return VMError.CompileError;

    const type_name = spec.type_name;
    const ctor_name = spec.ctor_name;
    const pred_name = spec.pred_name;
    const all_field_count = spec.field_count;
    const ctor_field_count = spec.ctor_field_count;

    const num_fields: u8 = @intCast(all_field_count);

    // Create the RecordType value
    var rt_val = vm.gc.allocRecordType(type_name, num_fields) catch return VMError.OutOfMemory;
    vm.gc.pushRoot(&rt_val);
    defer vm.gc.popRoot();

    // Store in a global with an internal name (space prefix prevents user access)
    const internal_name_buf = std.fmt.allocPrint(vm.gc.allocator, " __record_type_{s}", .{type_name}) catch return VMError.OutOfMemory;
    defer vm.gc.allocator.free(internal_name_buf);
    const internal_sym = vm.gc.allocSymbol(internal_name_buf) catch return VMError.OutOfMemory;
    const internal_name = types.symbolName(internal_sym);
    if (vm.current_lib_env) |lib_env| {
        lib_env.put(internal_name, rt_val) catch return VMError.OutOfMemory;
    } else {
        vm.defineGlobal(internal_name, rt_val) catch return VMError.OutOfMemory;
    }

    // Generate constructor:
    // (define (make-point x y) (%make-record __record_type_point x y))
    // But we need to handle field ordering: constructor args may be in a different order
    // than the field specs. The constructor always creates fields in the field_spec order.
    {
        vm.gc.no_collect += 1;
        errdefer vm.gc.no_collect -= 1;
        // Build the body: (%make-record <type> <fields-in-field-order>)
        // For each field in all_fields order, find it in the constructor args
        // Actually: %make-record takes type + field values in order.
        // The constructor needs to map its parameters to field positions.
        // We'll generate:
        //   (define (ctor p1 p2 ...) (%make-record type p_for_field0 p_for_field1 ...))
        // where p_for_fieldN is the constructor param corresponding to field N.

        var body_args: [258]Value = undefined;
        // body_args[0] = %make-record symbol
        body_args[0] = vm.gc.allocSymbol("%make-record") catch return VMError.OutOfMemory;
        // body_args[1] = internal_name (the record type reference)
        body_args[1] = vm.gc.allocSymbol(internal_name) catch return VMError.OutOfMemory;

        // For each field in order, find its constructor param
        for (0..all_field_count) |fi| {
            var found_in_ctor = false;
            for (0..ctor_field_count) |ci| {
                if (spec.ctor_field_indices[ci] == fi) {
                    body_args[2 + fi] = vm.gc.allocSymbol(spec.ctor_fields[ci]) catch return VMError.OutOfMemory;
                    found_in_ctor = true;
                    break;
                }
            }
            if (!found_in_ctor) {
                // (if #f #f) evaluates to void/undefined without polluting the namespace
                const if_sym = vm.gc.allocSymbol("if") catch return VMError.OutOfMemory;
                body_args[2 + fi] = vm.gc.makeList(&[_]Value{ if_sym, types.FALSE, types.FALSE }) catch return VMError.OutOfMemory;
            }
        }

        var body_list = vm.gc.makeList(body_args[0 .. 2 + all_field_count]) catch return VMError.OutOfMemory;
        vm.gc.pushRoot(&body_list);
        defer vm.gc.popRoot();

        // Build parameter list
        var param_syms: [256]Value = undefined;
        for (0..ctor_field_count) |ci| {
            param_syms[ci] = vm.gc.allocSymbol(spec.ctor_fields[ci]) catch return VMError.OutOfMemory;
        }
        const params = vm.gc.makeList(param_syms[0..ctor_field_count]) catch return VMError.OutOfMemory;

        // Build: (define (ctor-name params...) body)
        const define_sym = vm.gc.allocSymbol("define") catch return VMError.OutOfMemory;
        const name_and_params = vm.gc.allocPair(
            vm.gc.allocSymbol(ctor_name) catch return VMError.OutOfMemory,
            params,
        ) catch return VMError.OutOfMemory;
        const define_expr = vm.gc.makeList(&[_]Value{ define_sym, name_and_params, body_list }) catch return VMError.OutOfMemory;
        vm.gc.no_collect -= 1;

        body_list = define_expr;

        const func = if (vm.current_lib_env) |env|
            compiler_mod.compileExpressionInEnv(vm.gc, define_expr, &vm.macros, env, types.NIL, false) catch return VMError.CompileError
        else
            compiler_mod.compileExpressionWithMacros(vm.gc, define_expr, &vm.macros, vm.globals) catch return VMError.CompileError;
        const func_val = types.makePointer(@ptrCast(func));
        body_list = func_val;
        compiler_mod.Compiler.unrootFunction(vm.gc, func);
        _ = vm.execute(func) catch |err| return err;
    }

    // Generate predicate: (define (pred? v) (%record? v __record_type_point))
    {
        vm.gc.no_collect += 1;
        errdefer vm.gc.no_collect -= 1;
        const define_sym = vm.gc.allocSymbol("define") catch return VMError.OutOfMemory;
        const v_sym = vm.gc.allocSymbol("v") catch return VMError.OutOfMemory;
        const pred_sym = vm.gc.allocSymbol(pred_name) catch return VMError.OutOfMemory;
        const record_check_sym = vm.gc.allocSymbol("%record?") catch return VMError.OutOfMemory;
        const type_ref = vm.gc.allocSymbol(internal_name) catch return VMError.OutOfMemory;

        const body = vm.gc.makeList(&[_]Value{ record_check_sym, v_sym, type_ref }) catch return VMError.OutOfMemory;
        const name_and_params = vm.gc.makeList(&[_]Value{ pred_sym, v_sym }) catch return VMError.OutOfMemory;
        var define_expr = vm.gc.makeList(&[_]Value{ define_sym, name_and_params, body }) catch return VMError.OutOfMemory;
        vm.gc.no_collect -= 1;
        vm.gc.pushRoot(&define_expr);
        defer vm.gc.popRoot();

        const func = if (vm.current_lib_env) |env|
            compiler_mod.compileExpressionInEnv(vm.gc, define_expr, &vm.macros, env, types.NIL, false) catch return VMError.CompileError
        else
            compiler_mod.compileExpressionWithMacros(vm.gc, define_expr, &vm.macros, vm.globals) catch return VMError.CompileError;
        define_expr = types.makePointer(@ptrCast(func));
        compiler_mod.Compiler.unrootFunction(vm.gc, func);
        _ = vm.execute(func) catch |err| return err;
    }

    // Generate accessors and mutators for each field
    for (0..all_field_count) |fi| {
        // Accessor: (define (accessor p) (%record-ref p <index>))
        {
            vm.gc.no_collect += 1;
            errdefer vm.gc.no_collect -= 1;
            const define_sym = vm.gc.allocSymbol("define") catch return VMError.OutOfMemory;
            const p_sym = vm.gc.allocSymbol("p") catch return VMError.OutOfMemory;
            const acc_sym = vm.gc.allocSymbol(spec.accessor_names[fi]) catch return VMError.OutOfMemory;
            const record_ref_sym = vm.gc.allocSymbol("%record-ref") catch return VMError.OutOfMemory;
            const idx_val = types.makeFixnum(@intCast(fi));

            const body = vm.gc.makeList(&[_]Value{ record_ref_sym, p_sym, idx_val }) catch return VMError.OutOfMemory;
            const name_and_params = vm.gc.makeList(&[_]Value{ acc_sym, p_sym }) catch return VMError.OutOfMemory;
            var define_expr = vm.gc.makeList(&[_]Value{ define_sym, name_and_params, body }) catch return VMError.OutOfMemory;
            vm.gc.no_collect -= 1;
            vm.gc.pushRoot(&define_expr);
            defer vm.gc.popRoot();

            const func = if (vm.current_lib_env) |env|
                compiler_mod.compileExpressionInEnv(vm.gc, define_expr, &vm.macros, env, types.NIL, false) catch return VMError.CompileError
            else
                compiler_mod.compileExpressionWithMacros(vm.gc, define_expr, &vm.macros, vm.globals) catch return VMError.CompileError;
            define_expr = types.makePointer(@ptrCast(func));
            compiler_mod.Compiler.unrootFunction(vm.gc, func);
            _ = vm.execute(func) catch |err| return err;
        }

        // Mutator (if specified): (define (mutator p v) (%record-set! p <index> v))
        if (spec.mutator_names[fi]) |mut_name| {
            vm.gc.no_collect += 1;
            errdefer vm.gc.no_collect -= 1;
            const define_sym = vm.gc.allocSymbol("define") catch return VMError.OutOfMemory;
            const p_sym = vm.gc.allocSymbol("p") catch return VMError.OutOfMemory;
            const v_sym = vm.gc.allocSymbol("v") catch return VMError.OutOfMemory;
            const mut_sym = vm.gc.allocSymbol(mut_name) catch return VMError.OutOfMemory;
            const record_set_sym = vm.gc.allocSymbol("%record-set!") catch return VMError.OutOfMemory;
            const idx_val = types.makeFixnum(@intCast(fi));

            const body = vm.gc.makeList(&[_]Value{ record_set_sym, p_sym, idx_val, v_sym }) catch return VMError.OutOfMemory;
            const name_and_params = vm.gc.makeList(&[_]Value{ mut_sym, p_sym, v_sym }) catch return VMError.OutOfMemory;
            var define_expr = vm.gc.makeList(&[_]Value{ define_sym, name_and_params, body }) catch return VMError.OutOfMemory;
            vm.gc.no_collect -= 1;
            vm.gc.pushRoot(&define_expr);
            defer vm.gc.popRoot();

            const func = if (vm.current_lib_env) |env|
                compiler_mod.compileExpressionInEnv(vm.gc, define_expr, &vm.macros, env, types.NIL, false) catch return VMError.CompileError
            else
                compiler_mod.compileExpressionWithMacros(vm.gc, define_expr, &vm.macros, vm.globals) catch return VMError.CompileError;
            define_expr = types.makePointer(@ptrCast(func));
            compiler_mod.Compiler.unrootFunction(vm.gc, func);
            _ = vm.execute(func) catch |err| return err;
        }
    }

    return types.VOID;
}

// --- Body-context define-record-type expansion ---

pub const RecordSpec = struct {
    type_name: []const u8,
    ctor_name: []const u8,
    ctor_fields: [256][]const u8,
    ctor_field_count: usize,
    pred_name: []const u8,
    field_names: [256][]const u8,
    field_count: usize,
    accessor_names: [256][]const u8,
    mutator_names: [256]?[]const u8,
    ctor_field_indices: [256]usize,
};

/// Parse (define-record-type name (ctor field...) pred (field acc [mut])...)
/// args is the cdr of the full form (everything after 'define-record-type').
/// Returns null on malformed input.
pub fn parseRecordSpec(args: Value) ?RecordSpec {
    if (!types.isPair(args)) return null;
    const type_name_sym = types.car(args);
    if (!types.isSymbol(type_name_sym)) return null;

    var spec: RecordSpec = undefined;
    spec.type_name = types.symbolName(type_name_sym);

    const rest1 = types.cdr(args);
    if (!types.isPair(rest1)) return null;
    const ctor_spec = types.car(rest1);
    if (!types.isPair(ctor_spec)) return null;
    const ctor_name_sym = types.car(ctor_spec);
    if (!types.isSymbol(ctor_name_sym)) return null;
    spec.ctor_name = types.symbolName(ctor_name_sym);

    spec.ctor_field_count = 0;
    var cf = types.cdr(ctor_spec);
    while (cf != types.NIL) {
        if (!types.isPair(cf)) return null;
        const fsym = types.car(cf);
        if (!types.isSymbol(fsym)) return null;
        if (spec.ctor_field_count >= 256) return null;
        spec.ctor_fields[spec.ctor_field_count] = types.symbolName(fsym);
        spec.ctor_field_count += 1;
        cf = types.cdr(cf);
    }

    const rest2 = types.cdr(rest1);
    if (!types.isPair(rest2)) return null;
    const pred_sym = types.car(rest2);
    if (!types.isSymbol(pred_sym)) return null;
    spec.pred_name = types.symbolName(pred_sym);

    spec.field_count = 0;
    var fs = types.cdr(rest2);
    while (fs != types.NIL) {
        if (!types.isPair(fs)) return null;
        const fspec = types.car(fs);
        if (!types.isPair(fspec)) return null;
        const fname_sym = types.car(fspec);
        if (!types.isSymbol(fname_sym)) return null;
        if (spec.field_count >= 256) return null;
        const fname = types.symbolName(fname_sym);
        for (spec.field_names[0..spec.field_count]) |existing| {
            if (std.mem.eql(u8, existing, fname)) return null;
        }
        spec.field_names[spec.field_count] = fname;

        const spec_rest = types.cdr(fspec);
        if (!types.isPair(spec_rest)) return null;
        const acc_sym = types.car(spec_rest);
        if (!types.isSymbol(acc_sym)) return null;
        spec.accessor_names[spec.field_count] = types.symbolName(acc_sym);

        const spec_rest2 = types.cdr(spec_rest);
        if (spec_rest2 != types.NIL and types.isPair(spec_rest2)) {
            const mut_sym = types.car(spec_rest2);
            if (!types.isSymbol(mut_sym)) return null;
            spec.mutator_names[spec.field_count] = types.symbolName(mut_sym);
            if (types.cdr(spec_rest2) != types.NIL) return null;
        } else {
            spec.mutator_names[spec.field_count] = null;
        }

        spec.field_count += 1;
        fs = types.cdr(fs);
    }

    for (0..spec.ctor_field_count) |ci| {
        var found = false;
        for (0..spec.field_count) |fi| {
            if (std.mem.eql(u8, spec.ctor_fields[ci], spec.field_names[fi])) {
                spec.ctor_field_indices[ci] = fi;
                found = true;
                break;
            }
        }
        if (!found) return null;
    }

    return spec;
}

pub fn internRecordTypeName(gc: *GC, type_name: []const u8) CompileError![]const u8 {
    const buf = std.fmt.allocPrint(gc.allocator, " __record_type_{s}", .{type_name}) catch
        return CompileError.OutOfMemory;
    defer gc.allocator.free(buf);
    const sym = gc.allocSymbol(buf) catch return CompileError.OutOfMemory;
    return types.symbolName(sym);
}

/// Collect all names that a define-record-type form defines.
/// Used in the first pass of body scanning for macro visibility.
pub fn collectRecordTypeDefNames(
    gc: *GC,
    form_args: Value,
    names: [][]const u8,
    count: *usize,
) CompileError!void {
    const spec = parseRecordSpec(form_args) orelse return CompileError.InvalidSyntax;
    const internal_name = try internRecordTypeName(gc, spec.type_name);

    var needed: usize = 3 + spec.field_count;
    for (0..spec.field_count) |fi| {
        if (spec.mutator_names[fi] != null) needed += 1;
    }
    if (count.* + needed > names.len) return CompileError.TooManyLocals;

    names[count.*] = internal_name;
    count.* += 1;
    names[count.*] = spec.ctor_name;
    count.* += 1;
    names[count.*] = spec.pred_name;
    count.* += 1;
    for (0..spec.field_count) |fi| {
        names[count.*] = spec.accessor_names[fi];
        count.* += 1;
        if (spec.mutator_names[fi]) |mn| {
            names[count.*] = mn;
            count.* += 1;
        }
    }
}

/// Expand a define-record-type form into equivalent define entries.
/// Appends names and init S-expressions to the provided arrays.
pub fn expandRecordTypeDefines(
    gc: *GC,
    form_args: Value,
    def_names: [][]const u8,
    def_inits: []Value,
    count: *usize,
    extra_roots: *std.ArrayList(Value),
) CompileError!void {
    const spec = parseRecordSpec(form_args) orelse return CompileError.InvalidSyntax;
    const internal_name = try internRecordTypeName(gc, spec.type_name);

    var needed: usize = 3 + spec.field_count;
    for (0..spec.field_count) |fi| {
        if (spec.mutator_names[fi] != null) needed += 1;
    }
    if (count.* + needed > def_names.len) return CompileError.TooManyLocals;

    const saved_count = count.*;
    errdefer count.* = saved_count;

    gc.no_collect += 1;
    errdefer gc.no_collect -= 1;

    // 1. (define __rt (%make-record-type "name" num_fields))
    {
        const mrt_sym = gc.allocSymbol("%make-record-type") catch return CompileError.OutOfMemory;
        const name_str = gc.allocString(spec.type_name) catch return CompileError.OutOfMemory;
        const nf_val = types.makeFixnum(@intCast(spec.field_count));
        def_inits[count.*] = gc.makeList(&[_]Value{ mrt_sym, name_str, nf_val }) catch return CompileError.OutOfMemory;
        def_names[count.*] = internal_name;
        extra_roots.append(gc.allocator, def_inits[count.*]) catch return CompileError.OutOfMemory;
        count.* += 1;
    }

    // 2. (define (ctor f1 f2) (%make-record __rt f_for_0 f_for_1 ...))
    {
        const lambda_sym = gc.allocSymbol("lambda") catch return CompileError.OutOfMemory;
        const mr_sym = gc.allocSymbol("%make-record") catch return CompileError.OutOfMemory;
        const rt_ref = gc.allocSymbol(internal_name) catch return CompileError.OutOfMemory;

        var body_elems: [258]Value = undefined;
        body_elems[0] = mr_sym;
        body_elems[1] = rt_ref;
        for (0..spec.field_count) |fi| {
            var found = false;
            for (0..spec.ctor_field_count) |ci| {
                if (spec.ctor_field_indices[ci] == fi) {
                    body_elems[2 + fi] = gc.allocSymbol(spec.ctor_fields[ci]) catch return CompileError.OutOfMemory;
                    found = true;
                    break;
                }
            }
            if (!found) {
                const if_sym = gc.allocSymbol("if") catch return CompileError.OutOfMemory;
                body_elems[2 + fi] = gc.makeList(&[_]Value{ if_sym, types.FALSE, types.FALSE }) catch return CompileError.OutOfMemory;
            }
        }
        const body = gc.makeList(body_elems[0 .. 2 + spec.field_count]) catch return CompileError.OutOfMemory;

        var param_syms: [256]Value = undefined;
        for (0..spec.ctor_field_count) |ci| {
            param_syms[ci] = gc.allocSymbol(spec.ctor_fields[ci]) catch return CompileError.OutOfMemory;
        }
        const params = gc.makeList(param_syms[0..spec.ctor_field_count]) catch return CompileError.OutOfMemory;

        def_inits[count.*] = gc.makeList(&[_]Value{ lambda_sym, params, body }) catch return CompileError.OutOfMemory;
        def_names[count.*] = spec.ctor_name;
        extra_roots.append(gc.allocator, def_inits[count.*]) catch return CompileError.OutOfMemory;
        count.* += 1;
    }

    // 3. (define (pred? v) (%record? v __rt))
    {
        const lambda_sym = gc.allocSymbol("lambda") catch return CompileError.OutOfMemory;
        const rc_sym = gc.allocSymbol("%record?") catch return CompileError.OutOfMemory;
        const v_sym = gc.allocSymbol("v") catch return CompileError.OutOfMemory;
        const rt_ref = gc.allocSymbol(internal_name) catch return CompileError.OutOfMemory;

        const body = gc.makeList(&[_]Value{ rc_sym, v_sym, rt_ref }) catch return CompileError.OutOfMemory;
        const params = gc.makeList(&[_]Value{v_sym}) catch return CompileError.OutOfMemory;
        def_inits[count.*] = gc.makeList(&[_]Value{ lambda_sym, params, body }) catch return CompileError.OutOfMemory;
        def_names[count.*] = spec.pred_name;
        extra_roots.append(gc.allocator, def_inits[count.*]) catch return CompileError.OutOfMemory;
        count.* += 1;
    }

    // 4. Accessors: (define (acc p) (%record-ref p idx))
    for (0..spec.field_count) |fi| {
        const lambda_sym = gc.allocSymbol("lambda") catch return CompileError.OutOfMemory;
        const rr_sym = gc.allocSymbol("%record-ref") catch return CompileError.OutOfMemory;
        const p_sym = gc.allocSymbol("p") catch return CompileError.OutOfMemory;
        const idx = types.makeFixnum(@intCast(fi));

        const body = gc.makeList(&[_]Value{ rr_sym, p_sym, idx }) catch return CompileError.OutOfMemory;
        const params = gc.makeList(&[_]Value{p_sym}) catch return CompileError.OutOfMemory;
        def_inits[count.*] = gc.makeList(&[_]Value{ lambda_sym, params, body }) catch return CompileError.OutOfMemory;
        def_names[count.*] = spec.accessor_names[fi];
        extra_roots.append(gc.allocator, def_inits[count.*]) catch return CompileError.OutOfMemory;
        count.* += 1;
    }

    // 5. Mutators: (define (mut! p v) (%record-set! p idx v))
    for (0..spec.field_count) |fi| {
        if (spec.mutator_names[fi]) |mname| {
            const lambda_sym = gc.allocSymbol("lambda") catch return CompileError.OutOfMemory;
            const rs_sym = gc.allocSymbol("%record-set!") catch return CompileError.OutOfMemory;
            const p_sym = gc.allocSymbol("p") catch return CompileError.OutOfMemory;
            const v_sym = gc.allocSymbol("v") catch return CompileError.OutOfMemory;
            const idx = types.makeFixnum(@intCast(fi));

            const body = gc.makeList(&[_]Value{ rs_sym, p_sym, idx, v_sym }) catch return CompileError.OutOfMemory;
            const params = gc.makeList(&[_]Value{ p_sym, v_sym }) catch return CompileError.OutOfMemory;
            def_inits[count.*] = gc.makeList(&[_]Value{ lambda_sym, params, body }) catch return CompileError.OutOfMemory;
            def_names[count.*] = mname;
            extra_roots.append(gc.allocator, def_inits[count.*]) catch return CompileError.OutOfMemory;
            count.* += 1;
        }
    }

    gc.no_collect -= 1;
}
