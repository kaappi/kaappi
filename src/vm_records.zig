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

const srfi237_prims = @import("primitives_srfi237.zig");

/// Handle (define-record-type name (ctor field ...) pred (field accessor [mutator]) ...)
/// Desugars into define forms using internal record primitives.
/// Used for top-level and library-body contexts (VM interpreter path).
pub fn handleDefineRecordType(vm: *VM, args: Value) VMError!Value {
    if (looksLikeR6RSClauseSyntax(args)) return handleDefineRecordTypeR6RS(vm, args);
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

    // Generate constructor — close over the record type so redefinition
    // does not retarget previously created constructors (#1203):
    // (define ctor (let (( __rt __record_type_X))
    //               (lambda (f1 f2) (%make-record  __rt f_for_0 ...))))
    {
        vm.gc.no_collect += 1;
        defer vm.gc.no_collect -= 1;
        const rt_local = vm.gc.allocSymbol(" __rt") catch return VMError.OutOfMemory;

        var body_args: [258]Value = undefined;
        body_args[0] = vm.gc.allocSymbol("%make-record") catch return VMError.OutOfMemory;
        body_args[1] = rt_local;

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
                const if_sym = vm.gc.allocSymbol("if") catch return VMError.OutOfMemory;
                body_args[2 + fi] = vm.gc.makeList(&[_]Value{ if_sym, types.FALSE, types.FALSE }) catch return VMError.OutOfMemory;
            }
        }

        const body = vm.gc.makeList(body_args[0 .. 2 + all_field_count]) catch return VMError.OutOfMemory;

        var param_syms: [256]Value = undefined;
        for (0..ctor_field_count) |ci| {
            param_syms[ci] = vm.gc.allocSymbol(spec.ctor_fields[ci]) catch return VMError.OutOfMemory;
        }
        const params = vm.gc.makeList(param_syms[0..ctor_field_count]) catch return VMError.OutOfMemory;

        const lambda_sym = vm.gc.allocSymbol("lambda") catch return VMError.OutOfMemory;
        const lambda_expr = vm.gc.makeList(&[_]Value{ lambda_sym, params, body }) catch return VMError.OutOfMemory;
        const let_sym = vm.gc.allocSymbol("let") catch return VMError.OutOfMemory;
        const type_ref = vm.gc.allocSymbol(internal_name) catch return VMError.OutOfMemory;
        const let_binding = vm.gc.makeList(&[_]Value{ rt_local, type_ref }) catch return VMError.OutOfMemory;
        const let_bindings = vm.gc.makeList(&[_]Value{let_binding}) catch return VMError.OutOfMemory;
        const let_expr = vm.gc.makeList(&[_]Value{ let_sym, let_bindings, lambda_expr }) catch return VMError.OutOfMemory;

        const define_sym = vm.gc.allocSymbol("define") catch return VMError.OutOfMemory;
        const ctor_sym = vm.gc.allocSymbol(ctor_name) catch return VMError.OutOfMemory;
        var define_expr = vm.gc.makeList(&[_]Value{ define_sym, ctor_sym, let_expr }) catch return VMError.OutOfMemory;
        vm.gc.pushRoot(&define_expr);
        defer vm.gc.popRoot();

        const func = if (vm.current_lib_env) |env|
            compiler_mod.compileExpressionInEnv(vm.gc, define_expr, &vm.macros, env, types.NIL, false) catch return VMError.CompileError
        else
            compiler_mod.compileExpressionWithMacros(vm.gc, define_expr, &vm.macros, vm.globals) catch return VMError.CompileError;
        define_expr = types.makePointer(&func.header);
        compiler_mod.Compiler.unrootFunction(vm.gc, func);
        _ = vm.execute(func) catch |err| return err;
    }

    // Generate predicate — close over record type (#1203):
    // (define pred? (let (( __rt __record_type_X)) (lambda (v) (%record? v  __rt))))
    {
        vm.gc.no_collect += 1;
        defer vm.gc.no_collect -= 1;
        const rt_local = vm.gc.allocSymbol(" __rt") catch return VMError.OutOfMemory;
        const define_sym = vm.gc.allocSymbol("define") catch return VMError.OutOfMemory;
        const v_sym = vm.gc.allocSymbol("v") catch return VMError.OutOfMemory;
        const pred_sym = vm.gc.allocSymbol(pred_name) catch return VMError.OutOfMemory;
        const record_check_sym = vm.gc.allocSymbol("%record?") catch return VMError.OutOfMemory;

        const body = vm.gc.makeList(&[_]Value{ record_check_sym, v_sym, rt_local }) catch return VMError.OutOfMemory;
        const params = vm.gc.makeList(&[_]Value{v_sym}) catch return VMError.OutOfMemory;
        const lambda_sym = vm.gc.allocSymbol("lambda") catch return VMError.OutOfMemory;
        const lambda_expr = vm.gc.makeList(&[_]Value{ lambda_sym, params, body }) catch return VMError.OutOfMemory;
        const let_sym = vm.gc.allocSymbol("let") catch return VMError.OutOfMemory;
        const type_ref = vm.gc.allocSymbol(internal_name) catch return VMError.OutOfMemory;
        const let_binding = vm.gc.makeList(&[_]Value{ rt_local, type_ref }) catch return VMError.OutOfMemory;
        const let_bindings = vm.gc.makeList(&[_]Value{let_binding}) catch return VMError.OutOfMemory;
        const let_expr = vm.gc.makeList(&[_]Value{ let_sym, let_bindings, lambda_expr }) catch return VMError.OutOfMemory;

        var define_expr = vm.gc.makeList(&[_]Value{ define_sym, pred_sym, let_expr }) catch return VMError.OutOfMemory;
        vm.gc.pushRoot(&define_expr);
        defer vm.gc.popRoot();

        const func = if (vm.current_lib_env) |env|
            compiler_mod.compileExpressionInEnv(vm.gc, define_expr, &vm.macros, env, types.NIL, false) catch return VMError.CompileError
        else
            compiler_mod.compileExpressionWithMacros(vm.gc, define_expr, &vm.macros, vm.globals) catch return VMError.CompileError;
        define_expr = types.makePointer(&func.header);
        compiler_mod.Compiler.unrootFunction(vm.gc, func);
        _ = vm.execute(func) catch |err| return err;
    }

    // Generate accessors and mutators — close over record type (#1203)
    for (0..all_field_count) |fi| {
        // Accessor: (define acc (let (( __rt ...)) (lambda (p) (%record-ref p idx  __rt))))
        {
            vm.gc.no_collect += 1;
            defer vm.gc.no_collect -= 1;
            const rt_local = vm.gc.allocSymbol(" __rt") catch return VMError.OutOfMemory;
            const define_sym = vm.gc.allocSymbol("define") catch return VMError.OutOfMemory;
            const p_sym = vm.gc.allocSymbol("p") catch return VMError.OutOfMemory;
            const acc_sym = vm.gc.allocSymbol(spec.accessor_names[fi]) catch return VMError.OutOfMemory;
            const record_ref_sym = vm.gc.allocSymbol("%record-ref") catch return VMError.OutOfMemory;
            const idx_val = types.makeFixnum(@intCast(fi));

            const body = vm.gc.makeList(&[_]Value{ record_ref_sym, p_sym, idx_val, rt_local }) catch return VMError.OutOfMemory;
            const params = vm.gc.makeList(&[_]Value{p_sym}) catch return VMError.OutOfMemory;
            const lambda_sym = vm.gc.allocSymbol("lambda") catch return VMError.OutOfMemory;
            const lambda_expr = vm.gc.makeList(&[_]Value{ lambda_sym, params, body }) catch return VMError.OutOfMemory;
            const let_sym = vm.gc.allocSymbol("let") catch return VMError.OutOfMemory;
            const type_ref = vm.gc.allocSymbol(internal_name) catch return VMError.OutOfMemory;
            const let_binding = vm.gc.makeList(&[_]Value{ rt_local, type_ref }) catch return VMError.OutOfMemory;
            const let_bindings = vm.gc.makeList(&[_]Value{let_binding}) catch return VMError.OutOfMemory;
            const let_expr = vm.gc.makeList(&[_]Value{ let_sym, let_bindings, lambda_expr }) catch return VMError.OutOfMemory;

            var define_expr = vm.gc.makeList(&[_]Value{ define_sym, acc_sym, let_expr }) catch return VMError.OutOfMemory;
            vm.gc.pushRoot(&define_expr);
            defer vm.gc.popRoot();

            const func = if (vm.current_lib_env) |env|
                compiler_mod.compileExpressionInEnv(vm.gc, define_expr, &vm.macros, env, types.NIL, false) catch return VMError.CompileError
            else
                compiler_mod.compileExpressionWithMacros(vm.gc, define_expr, &vm.macros, vm.globals) catch return VMError.CompileError;
            define_expr = types.makePointer(&func.header);
            compiler_mod.Compiler.unrootFunction(vm.gc, func);
            _ = vm.execute(func) catch |err| return err;
        }

        // Mutator: (define mut! (let (( __rt ...)) (lambda (p v) (%record-set! p idx v  __rt))))
        if (spec.mutator_names[fi]) |mut_name| {
            vm.gc.no_collect += 1;
            defer vm.gc.no_collect -= 1;
            const rt_local = vm.gc.allocSymbol(" __rt") catch return VMError.OutOfMemory;
            const define_sym = vm.gc.allocSymbol("define") catch return VMError.OutOfMemory;
            const p_sym = vm.gc.allocSymbol("p") catch return VMError.OutOfMemory;
            const v_sym = vm.gc.allocSymbol("v") catch return VMError.OutOfMemory;
            const mut_sym = vm.gc.allocSymbol(mut_name) catch return VMError.OutOfMemory;
            const record_set_sym = vm.gc.allocSymbol("%record-set!") catch return VMError.OutOfMemory;
            const idx_val = types.makeFixnum(@intCast(fi));

            const body = vm.gc.makeList(&[_]Value{ record_set_sym, p_sym, idx_val, v_sym, rt_local }) catch return VMError.OutOfMemory;
            const params = vm.gc.makeList(&[_]Value{ p_sym, v_sym }) catch return VMError.OutOfMemory;
            const lambda_sym = vm.gc.allocSymbol("lambda") catch return VMError.OutOfMemory;
            const lambda_expr = vm.gc.makeList(&[_]Value{ lambda_sym, params, body }) catch return VMError.OutOfMemory;
            const let_sym = vm.gc.allocSymbol("let") catch return VMError.OutOfMemory;
            const type_ref = vm.gc.allocSymbol(internal_name) catch return VMError.OutOfMemory;
            const let_binding = vm.gc.makeList(&[_]Value{ rt_local, type_ref }) catch return VMError.OutOfMemory;
            const let_bindings = vm.gc.makeList(&[_]Value{let_binding}) catch return VMError.OutOfMemory;
            const let_expr = vm.gc.makeList(&[_]Value{ let_sym, let_bindings, lambda_expr }) catch return VMError.OutOfMemory;

            var define_expr = vm.gc.makeList(&[_]Value{ define_sym, mut_sym, let_expr }) catch return VMError.OutOfMemory;
            vm.gc.pushRoot(&define_expr);
            defer vm.gc.popRoot();

            const func = if (vm.current_lib_env) |env|
                compiler_mod.compileExpressionInEnv(vm.gc, define_expr, &vm.macros, env, types.NIL, false) catch return VMError.CompileError
            else
                compiler_mod.compileExpressionWithMacros(vm.gc, define_expr, &vm.macros, vm.globals) catch return VMError.CompileError;
            define_expr = types.makePointer(&func.header);
            compiler_mod.Compiler.unrootFunction(vm.gc, func);
            _ = vm.execute(func) catch |err| return err;
        }
    }

    return types.VOID;
}

// --- SRFI 237/240: R6RS clause-syntax define-record-type ---
//
// (define-record-type <name spec> <record clause>*), where <name spec> is
// a bare symbol or (<name> <ctor> <pred>), and each <record clause> is one
// of (fields <field spec>*) (parent <name>) (protocol <expr>) (sealed #t/#f)
// (opaque #t/#f) (nongenerative [<uid>]) -- the R6RS grammar as fetched from
// r6rs.org's records-syntactic chapter. `parent-rtd` and SRFI 237's own
// 4-/2-element <rtd name> name-spec extension are deliberately not
// supported (documented gap, like the omitted port-read-rtd/port-write-rtd
// procedures) -- both are rare refinements, not core functionality.
//
// Protocol/inheritance desugaring uses a "materialize the parent instance,
// then re-extract its fields via %record-ref" strategy rather than R6RS's
// own CPS-style n/p threading: calling the parent's ALREADY-WORKING exposed
// constructor (via `apply`, so its own arity/protocol/parentage is opaque
// to this code) and reading its fields back out via `%record-ref` is
// behaviorally identical to threading through parent construction directly
// (the parent constructor's protocol runs exactly once either way, so no
// user-observable side effect changes), and it works uniformly for ANY
// combination of protocols across ANY depth of inheritance -- no special
// casing, no need to track "did an ancestor have a protocol" at all. The
// cost is one extra ephemeral RecordInstance per construction, immediately
// garbage -- negligible for what SRFI 237 is used for.
//
// LIMITATION: only supported at the top level (handleDefineRecordTypeR6RS,
// dispatched from vm_eval.zig same as the R7RS path) -- NOT yet inside a
// library body (collectRecordTypeDefNames/expandRecordTypeDefines below
// explicitly reject it with a clear error rather than mis-parsing it as
// malformed R7RS syntax). lib/srfi/237.sld and lib/srfi/240.sld don't need
// this themselves (their own RCD representation is plain R7RS syntax), so
// this only affects a THIRD-PARTY library wanting to use R6RS-clause
// define-record-type inside its own .sld body -- a real but narrower gap
// than the top-level case this session's test suite exercises.

fn isR6RSClauseKeyword(name: []const u8) bool {
    const keywords = [_][]const u8{ "fields", "parent", "protocol", "sealed", "opaque", "nongenerative", "parent-rtd" };
    for (keywords) |kw| {
        if (std.mem.eql(u8, name, kw)) return true;
    }
    return false;
}

/// R7RS syntax's 2nd element is always (ctor-name field...) where ctor-name
/// is a plain symbol naming the constructor -- never one of the R6RS clause
/// keywords above, so checking the head of the 2nd element disambiguates
/// the two syntaxes (a constructor literally named e.g. "parent" would
/// misdetect, but that's an extreme, self-inflicted edge case).
fn looksLikeR6RSClauseSyntax(args: Value) bool {
    if (!types.isPair(args)) return false;
    const rest = types.cdr(args);
    if (!types.isPair(rest)) return false;
    const second = types.car(rest);
    if (!types.isPair(second)) return false;
    const head = types.car(second);
    if (!types.isSymbol(head)) return false;
    return isR6RSClauseKeyword(types.symbolName(head));
}

fn lookupInternalGlobal(vm: *VM, name: []const u8) ?Value {
    if (vm.current_lib_env) |env| return env.get(name);
    return vm.globals.get(name);
}

/// (let (( __rt <internal_name>)) body) -- the closure-over-record-type
/// wrapper every generated define below needs (matching handleDefineRecordType's
/// own #1203 rationale: closing over the type keeps redefinition from
/// retargeting previously created constructors/accessors).
fn wrapInRtLet(gc: *GC, internal_name: []const u8, body: Value) CompileError!Value {
    const rt_local = gc.allocSymbol(" __rt") catch return CompileError.OutOfMemory;
    const let_sym = gc.allocSymbol("let") catch return CompileError.OutOfMemory;
    const type_ref = gc.allocSymbol(internal_name) catch return CompileError.OutOfMemory;
    const let_binding = gc.makeList(&[_]Value{ rt_local, type_ref }) catch return CompileError.OutOfMemory;
    const let_bindings = gc.makeList(&[_]Value{let_binding}) catch return CompileError.OutOfMemory;
    return gc.makeList(&[_]Value{ let_sym, let_bindings, body }) catch return CompileError.OutOfMemory;
}

/// Roots, compiles, and immediately executes a single (define name value)
/// form -- the common tail of every generated definition in
/// handleDefineRecordType/handleDefineRecordTypeR6RS.
fn compileAndRunDefine(vm: *VM, define_expr_in: Value) VMError!void {
    var define_expr = define_expr_in;
    vm.gc.pushRoot(&define_expr);
    defer vm.gc.popRoot();

    const func = if (vm.current_lib_env) |env|
        compiler_mod.compileExpressionInEnv(vm.gc, define_expr, &vm.macros, env, types.NIL, false) catch return VMError.CompileError
    else
        compiler_mod.compileExpressionWithMacros(vm.gc, define_expr, &vm.macros, vm.globals) catch return VMError.CompileError;
    define_expr = types.makePointer(&func.header);
    compiler_mod.Compiler.unrootFunction(vm.gc, func);
    _ = vm.execute(func) catch |err| return err;
}

pub const R6RSFieldSpec = struct {
    name: []const u8,
    mutable: bool,
    accessor_name: []const u8,
    /// null iff immutable -- R6RS field specs have no way to suppress an
    /// accessor (unlike SRFI 237's constructor/predicate, which this
    /// implementation also does not support suppressing -- see the file
    /// header comment; the fetched R6RS grammar has no #f form for either).
    mutator_name: ?[]const u8,
};

pub const R6RSRecordSpec = struct {
    type_name: []const u8,
    ctor_name: []const u8,
    pred_name: []const u8,
    parent_name: ?[]const u8 = null,
    protocol_expr: ?Value = null,
    uid: ?[]const u8 = null,
    has_nongenerative: bool = false,
    sealed: bool = false,
    is_opaque: bool = false,
    fields: [256]R6RSFieldSpec = undefined,
    field_count: usize = 0,
};

fn parseFieldSpec(field_spec: Value, type_name: []const u8, gc: *GC) CompileError!?R6RSFieldSpec {
    if (types.isSymbol(field_spec)) {
        const fname = types.symbolName(field_spec);
        const acc_buf = std.fmt.allocPrint(gc.allocator, "{s}-{s}", .{ type_name, fname }) catch return CompileError.OutOfMemory;
        defer gc.allocator.free(acc_buf);
        const acc_sym = gc.allocSymbol(acc_buf) catch return CompileError.OutOfMemory;
        return R6RSFieldSpec{ .name = fname, .mutable = false, .accessor_name = types.symbolName(acc_sym), .mutator_name = null };
    }
    if (!types.isPair(field_spec)) return null;
    const kind_sym = types.car(field_spec);
    if (!types.isSymbol(kind_sym)) return null;
    const kind = types.symbolName(kind_sym);
    const is_mutable = std.mem.eql(u8, kind, "mutable");
    if (!is_mutable and !std.mem.eql(u8, kind, "immutable")) return null;

    const r1 = types.cdr(field_spec);
    if (!types.isPair(r1)) return null;
    const fname_sym = types.car(r1);
    if (!types.isSymbol(fname_sym)) return null;
    const fname = types.symbolName(fname_sym);

    const r2 = types.cdr(r1);
    var accessor_name: []const u8 = undefined;
    if (r2 == types.NIL) {
        const acc_buf = std.fmt.allocPrint(gc.allocator, "{s}-{s}", .{ type_name, fname }) catch return CompileError.OutOfMemory;
        defer gc.allocator.free(acc_buf);
        accessor_name = types.symbolName(gc.allocSymbol(acc_buf) catch return CompileError.OutOfMemory);
    } else {
        if (!types.isPair(r2)) return null;
        const acc_sym = types.car(r2);
        if (!types.isSymbol(acc_sym)) return null;
        accessor_name = types.symbolName(acc_sym);
    }

    var mutator_name: ?[]const u8 = null;
    if (is_mutable) {
        const r3 = if (r2 == types.NIL) types.NIL else types.cdr(r2);
        if (r3 == types.NIL) {
            const mut_buf = std.fmt.allocPrint(gc.allocator, "{s}-set!", .{accessor_name}) catch return CompileError.OutOfMemory;
            defer gc.allocator.free(mut_buf);
            mutator_name = types.symbolName(gc.allocSymbol(mut_buf) catch return CompileError.OutOfMemory);
        } else {
            if (!types.isPair(r3)) return null;
            const mut_sym = types.car(r3);
            if (!types.isSymbol(mut_sym)) return null;
            mutator_name = types.symbolName(mut_sym);
            if (types.cdr(r3) != types.NIL) return null;
        }
    } else if (r2 != types.NIL and types.cdr(r2) != types.NIL) {
        return null; // immutable: nothing may follow the accessor name
    }

    return R6RSFieldSpec{ .name = fname, .mutable = is_mutable, .accessor_name = accessor_name, .mutator_name = mutator_name };
}

threadlocal var nongenerative_anon_counter: u64 = 0;

pub fn parseRecordSpecR6RS(args: Value, gc: *GC) CompileError!?R6RSRecordSpec {
    if (!types.isPair(args)) return null;
    const name_spec = types.car(args);

    var spec: R6RSRecordSpec = .{ .type_name = undefined, .ctor_name = undefined, .pred_name = undefined };

    if (types.isSymbol(name_spec)) {
        const n = types.symbolName(name_spec);
        spec.type_name = n;
        const ctor_buf = std.fmt.allocPrint(gc.allocator, "make-{s}", .{n}) catch return CompileError.OutOfMemory;
        defer gc.allocator.free(ctor_buf);
        spec.ctor_name = types.symbolName(gc.allocSymbol(ctor_buf) catch return CompileError.OutOfMemory);
        const pred_buf = std.fmt.allocPrint(gc.allocator, "{s}?", .{n}) catch return CompileError.OutOfMemory;
        defer gc.allocator.free(pred_buf);
        spec.pred_name = types.symbolName(gc.allocSymbol(pred_buf) catch return CompileError.OutOfMemory);
    } else if (types.isPair(name_spec)) {
        const n_sym = types.car(name_spec);
        if (!types.isSymbol(n_sym)) return null;
        spec.type_name = types.symbolName(n_sym);
        const r1 = types.cdr(name_spec);
        if (!types.isPair(r1)) return null;
        const ctor_sym = types.car(r1);
        if (!types.isSymbol(ctor_sym)) return null;
        spec.ctor_name = types.symbolName(ctor_sym);
        const r2 = types.cdr(r1);
        if (!types.isPair(r2)) return null;
        const pred_sym = types.car(r2);
        if (!types.isSymbol(pred_sym)) return null;
        spec.pred_name = types.symbolName(pred_sym);
        if (types.cdr(r2) != types.NIL) return null;
    } else return null;

    var clauses = types.cdr(args);
    while (clauses != types.NIL) {
        if (!types.isPair(clauses)) return null;
        const clause = types.car(clauses);
        if (!types.isPair(clause)) return null;
        const kw_sym = types.car(clause);
        if (!types.isSymbol(kw_sym)) return null;
        const kw = types.symbolName(kw_sym);
        const clause_rest = types.cdr(clause);

        if (std.mem.eql(u8, kw, "fields")) {
            var fs = clause_rest;
            while (fs != types.NIL) {
                if (!types.isPair(fs)) return null;
                if (spec.field_count >= 255) return null; // own_field_count is u8
                const fspec = (try parseFieldSpec(types.car(fs), spec.type_name, gc)) orelse return null;
                spec.fields[spec.field_count] = fspec;
                spec.field_count += 1;
                fs = types.cdr(fs);
            }
        } else if (std.mem.eql(u8, kw, "parent")) {
            if (!types.isPair(clause_rest)) return null;
            const p_sym = types.car(clause_rest);
            if (!types.isSymbol(p_sym)) return null;
            spec.parent_name = types.symbolName(p_sym);
            if (types.cdr(clause_rest) != types.NIL) return null;
        } else if (std.mem.eql(u8, kw, "protocol")) {
            if (!types.isPair(clause_rest)) return null;
            spec.protocol_expr = types.car(clause_rest);
            if (types.cdr(clause_rest) != types.NIL) return null;
        } else if (std.mem.eql(u8, kw, "sealed")) {
            if (!types.isPair(clause_rest)) return null;
            spec.sealed = types.car(clause_rest) != types.FALSE;
            if (types.cdr(clause_rest) != types.NIL) return null;
        } else if (std.mem.eql(u8, kw, "opaque")) {
            if (!types.isPair(clause_rest)) return null;
            spec.is_opaque = types.car(clause_rest) != types.FALSE;
            if (types.cdr(clause_rest) != types.NIL) return null;
        } else if (std.mem.eql(u8, kw, "nongenerative")) {
            spec.has_nongenerative = true;
            if (clause_rest != types.NIL) {
                if (!types.isPair(clause_rest)) return null;
                const uid_sym = types.car(clause_rest);
                if (!types.isSymbol(uid_sym)) return null;
                spec.uid = types.symbolName(uid_sym);
                if (types.cdr(clause_rest) != types.NIL) return null;
            }
        } else {
            // parent-rtd, or anything else -- see the section header comment.
            return null;
        }
        clauses = types.cdr(clauses);
    }

    // (nongenerative) with no explicit uid: still non-generative (matters
    // for record-type-generative?), but with nothing meant to compare equal
    // to across separate evaluations -- synthesize a uid that can't collide
    // with a real user-chosen one (leading space, like this file's other
    // internal-only names).
    if (spec.has_nongenerative and spec.uid == null) {
        nongenerative_anon_counter += 1;
        const buf = std.fmt.allocPrint(gc.allocator, " __nongenerative_{d}", .{nongenerative_anon_counter}) catch return CompileError.OutOfMemory;
        defer gc.allocator.free(buf);
        spec.uid = types.symbolName(gc.allocSymbol(buf) catch return CompileError.OutOfMemory);
    }

    return spec;
}

pub fn handleDefineRecordTypeR6RS(vm: *VM, args: Value) VMError!Value {
    const spec = (parseRecordSpecR6RS(args, vm.gc) catch return VMError.CompileError) orelse return VMError.CompileError;

    const parent_rt: ?*types.RecordType = if (spec.parent_name) |pname| blk: {
        const parent_internal = internRecordTypeName(vm.gc, pname) catch return VMError.OutOfMemory;
        const parent_val = lookupInternalGlobal(vm, parent_internal) orelse return VMError.CompileError;
        if (!types.isRecordType(parent_val)) return VMError.CompileError;
        break :blk types.toObject(parent_val).as(types.RecordType);
    } else null;
    // R6RS: "An exception ... is raised if parent is sealed" -- a sealed
    // type must never become an ancestor of another record type.
    if (parent_rt) |p| if (p.sealed) return VMError.TypeError;
    const parent_total_fields: usize = if (parent_rt) |p| p.num_fields else 0;

    var field_names_buf: [256][]const u8 = undefined;
    var field_mutable_buf: [256]bool = undefined;
    for (0..spec.field_count) |i| {
        field_names_buf[i] = spec.fields[i].name;
        field_mutable_buf[i] = spec.fields[i].mutable;
    }

    // nongenerative: reuse an existing RTD registered under this uid, but
    // only when it's actually equivalent (same check as
    // %make-record-type-descriptor in primitives_srfi237.zig -- R6RS:
    // "the record-type definitions should be equivalent").
    var rt_val: Value = undefined;
    if (spec.uid) |u| {
        if (vm.record_uid_registry.get(u)) |existing| {
            const existing_rt = types.toObject(existing).as(types.RecordType);
            if (existing_rt.parent != parent_rt or
                existing_rt.sealed != spec.sealed or
                existing_rt.is_opaque != spec.is_opaque or
                !srfi237_prims.fieldsEquivalent(existing_rt, field_names_buf[0..spec.field_count], field_mutable_buf[0..spec.field_count]))
            {
                return VMError.TypeError;
            }
            rt_val = existing;
        } else {
            rt_val = vm.gc.allocRecordTypeExtended(
                spec.type_name,
                parent_rt,
                field_names_buf[0..spec.field_count],
                field_mutable_buf[0..spec.field_count],
                u,
                spec.sealed,
                spec.is_opaque,
            ) catch |err| return switch (err) {
                error.TooManyFields => VMError.TypeError,
                else => VMError.OutOfMemory,
            };
            vm.gc.pushRoot(&rt_val);
            vm.record_uid_registry.put(u, rt_val) catch return VMError.OutOfMemory;
            vm.gc.popRoot();
        }
    } else {
        rt_val = vm.gc.allocRecordTypeExtended(
            spec.type_name,
            parent_rt,
            field_names_buf[0..spec.field_count],
            field_mutable_buf[0..spec.field_count],
            null,
            spec.sealed,
            spec.is_opaque,
        ) catch |err| return switch (err) {
            error.TooManyFields => VMError.TypeError,
            else => VMError.OutOfMemory,
        };
    }
    vm.gc.pushRoot(&rt_val);
    defer vm.gc.popRoot();

    const internal_name = internRecordTypeName(vm.gc, spec.type_name) catch return VMError.OutOfMemory;
    if (vm.current_lib_env) |lib_env| {
        lib_env.put(internal_name, rt_val) catch return VMError.OutOfMemory;
    } else {
        vm.defineGlobal(internal_name, rt_val) catch return VMError.OutOfMemory;
    }

    // --- constructor ---
    {
        vm.gc.no_collect += 1;
        defer vm.gc.no_collect -= 1;
        const gc = vm.gc;

        var ctor_body: Value = undefined;
        if (parent_rt != null) {
            const parent_internal = internRecordTypeName(gc, spec.parent_name.?) catch return VMError.OutOfMemory;
            const parent_rt_ref = gc.allocSymbol(parent_internal) catch return VMError.OutOfMemory;
            var extract_elems: [257]Value = undefined;
            extract_elems[0] = gc.allocSymbol("list") catch return VMError.OutOfMemory;
            const parent_inst_sym = gc.allocSymbol(" __parent-inst") catch return VMError.OutOfMemory;
            for (0..parent_total_fields) |fi| {
                const rr_sym = gc.allocSymbol("%record-ref") catch return VMError.OutOfMemory;
                extract_elems[1 + fi] = gc.makeList(&[_]Value{ rr_sym, parent_inst_sym, types.makeFixnum(@intCast(fi)), parent_rt_ref }) catch return VMError.OutOfMemory;
            }
            const parent_fields_list = gc.makeList(extract_elems[0 .. 1 + parent_total_fields]) catch return VMError.OutOfMemory;

            if (spec.protocol_expr) |protocol_expr| {
                // (protocol (lambda n-args (let ((__parent-inst (apply parent-ctor n-args))) (lambda own-args (apply %make-record __rt (append (list ...parent fields...) own-args))))))
                const own_args_sym = gc.allocSymbol(" __own-args") catch return VMError.OutOfMemory;
                const apply_sym = gc.allocSymbol("apply") catch return VMError.OutOfMemory;
                const append_sym = gc.allocSymbol("append") catch return VMError.OutOfMemory;
                const mr_sym = gc.allocSymbol("%make-record") catch return VMError.OutOfMemory;
                const rt_local = gc.allocSymbol(" __rt") catch return VMError.OutOfMemory;
                const appended = gc.makeList(&[_]Value{ append_sym, parent_fields_list, own_args_sym }) catch return VMError.OutOfMemory;
                const inner_body = gc.makeList(&[_]Value{ apply_sym, mr_sym, rt_local, appended }) catch return VMError.OutOfMemory;
                const p_params = own_args_sym; // rest-arg lambda: (lambda own-args ...)
                const lambda_sym = gc.allocSymbol("lambda") catch return VMError.OutOfMemory;
                const p_lambda = gc.makeList(&[_]Value{ lambda_sym, p_params, inner_body }) catch return VMError.OutOfMemory;

                const n_args_sym = gc.allocSymbol(" __n-args") catch return VMError.OutOfMemory;
                const parent_ctor_internal = internCtorName(gc, spec.parent_name.?) catch return VMError.OutOfMemory;
                const parent_ctor_sym = gc.allocSymbol(parent_ctor_internal) catch return VMError.OutOfMemory;
                const apply_parent = gc.makeList(&[_]Value{ apply_sym, parent_ctor_sym, n_args_sym }) catch return VMError.OutOfMemory;
                const let_binding = gc.makeList(&[_]Value{ parent_inst_sym, apply_parent }) catch return VMError.OutOfMemory;
                const let_bindings = gc.makeList(&[_]Value{let_binding}) catch return VMError.OutOfMemory;
                const let_sym = gc.allocSymbol("let") catch return VMError.OutOfMemory;
                const let_expr = gc.makeList(&[_]Value{ let_sym, let_bindings, p_lambda }) catch return VMError.OutOfMemory;
                const n_lambda = gc.makeList(&[_]Value{ lambda_sym, n_args_sym, let_expr }) catch return VMError.OutOfMemory;

                ctor_body = gc.makeList(&[_]Value{ protocol_expr, n_lambda }) catch return VMError.OutOfMemory;
            } else {
                // (lambda call-args (let* ((__split (%record-split-args call-args own-count)) (__parent-inst (apply parent-ctor (car __split)))) (apply %make-record __rt (append (list ...parent fields...) (cdr __split)))))
                const call_args_sym = gc.allocSymbol(" __call-args") catch return VMError.OutOfMemory;
                const split_sym = gc.allocSymbol(" __split") catch return VMError.OutOfMemory;
                const rss_sym = gc.allocSymbol("%record-split-args") catch return VMError.OutOfMemory;
                const own_count_val = types.makeFixnum(@intCast(spec.field_count));
                const split_call = gc.makeList(&[_]Value{ rss_sym, call_args_sym, own_count_val }) catch return VMError.OutOfMemory;

                const car_sym = gc.allocSymbol("car") catch return VMError.OutOfMemory;
                const cdr_sym = gc.allocSymbol("cdr") catch return VMError.OutOfMemory;
                const parent_args_expr = gc.makeList(&[_]Value{ car_sym, split_sym }) catch return VMError.OutOfMemory;
                const own_args_expr = gc.makeList(&[_]Value{ cdr_sym, split_sym }) catch return VMError.OutOfMemory;

                const parent_ctor_internal = internCtorName(gc, spec.parent_name.?) catch return VMError.OutOfMemory;
                const parent_ctor_sym = gc.allocSymbol(parent_ctor_internal) catch return VMError.OutOfMemory;
                const apply_sym = gc.allocSymbol("apply") catch return VMError.OutOfMemory;
                const apply_parent = gc.makeList(&[_]Value{ apply_sym, parent_ctor_sym, parent_args_expr }) catch return VMError.OutOfMemory;

                const append_sym = gc.allocSymbol("append") catch return VMError.OutOfMemory;
                const appended = gc.makeList(&[_]Value{ append_sym, parent_fields_list, own_args_expr }) catch return VMError.OutOfMemory;
                const mr_sym = gc.allocSymbol("%make-record") catch return VMError.OutOfMemory;
                const rt_local = gc.allocSymbol(" __rt") catch return VMError.OutOfMemory;
                const final_body = gc.makeList(&[_]Value{ apply_sym, mr_sym, rt_local, appended }) catch return VMError.OutOfMemory;

                const b1 = gc.makeList(&[_]Value{ split_sym, split_call }) catch return VMError.OutOfMemory;
                const b2 = gc.makeList(&[_]Value{ parent_inst_sym, apply_parent }) catch return VMError.OutOfMemory;
                const let_star_bindings = gc.makeList(&[_]Value{ b1, b2 }) catch return VMError.OutOfMemory;
                const let_star_sym = gc.allocSymbol("let*") catch return VMError.OutOfMemory;
                const let_star_expr = gc.makeList(&[_]Value{ let_star_sym, let_star_bindings, final_body }) catch return VMError.OutOfMemory;

                const lambda_sym = gc.allocSymbol("lambda") catch return VMError.OutOfMemory;
                ctor_body = gc.makeList(&[_]Value{ lambda_sym, call_args_sym, let_star_expr }) catch return VMError.OutOfMemory;
            }
        } else {
            // No parent: (lambda (f1 ... fn) (%make-record __rt f1 ... fn)), optionally wrapped in the protocol.
            var body_elems: [258]Value = undefined;
            body_elems[0] = gc.allocSymbol("%make-record") catch return VMError.OutOfMemory;
            body_elems[1] = gc.allocSymbol(" __rt") catch return VMError.OutOfMemory;
            var param_syms: [256]Value = undefined;
            for (0..spec.field_count) |fi| {
                const fsym = gc.allocSymbol(spec.fields[fi].name) catch return VMError.OutOfMemory;
                body_elems[2 + fi] = fsym;
                param_syms[fi] = fsym;
            }
            const raw_body = gc.makeList(body_elems[0 .. 2 + spec.field_count]) catch return VMError.OutOfMemory;
            const params = gc.makeList(param_syms[0..spec.field_count]) catch return VMError.OutOfMemory;
            const lambda_sym = gc.allocSymbol("lambda") catch return VMError.OutOfMemory;
            const raw_lambda = gc.makeList(&[_]Value{ lambda_sym, params, raw_body }) catch return VMError.OutOfMemory;

            ctor_body = if (spec.protocol_expr) |protocol_expr|
                gc.makeList(&[_]Value{ protocol_expr, raw_lambda }) catch return VMError.OutOfMemory
            else
                raw_lambda;
        }

        const ctor_full = wrapInRtLet(gc, internal_name, ctor_body) catch return VMError.OutOfMemory;
        const define_sym = gc.allocSymbol("define") catch return VMError.OutOfMemory;
        // Bind an internal alias FIRST -- a child extending this type
        // references the constructor by this fixed internal name (see
        // internCtorName), regardless of what user-facing name this
        // type's own constructor was given.
        const ctor_internal = internCtorName(gc, spec.type_name) catch return VMError.OutOfMemory;
        const ctor_internal_sym = gc.allocSymbol(ctor_internal) catch return VMError.OutOfMemory;
        const define_internal_expr = gc.makeList(&[_]Value{ define_sym, ctor_internal_sym, ctor_full }) catch return VMError.OutOfMemory;
        try compileAndRunDefine(vm, define_internal_expr);

        // (define <user-ctor-name> __record_ctor_<type-name>)
        const ctor_sym = gc.allocSymbol(spec.ctor_name) catch return VMError.OutOfMemory;
        const alias_expr = gc.makeList(&[_]Value{ define_sym, ctor_sym, ctor_internal_sym }) catch return VMError.OutOfMemory;
        try compileAndRunDefine(vm, alias_expr);
    }

    // --- predicate: (define pred (let ((__rt ...)) (lambda (v) (%record?/inherit v __rt)))) ---
    {
        vm.gc.no_collect += 1;
        defer vm.gc.no_collect -= 1;
        const gc = vm.gc;
        const v_sym = gc.allocSymbol("v") catch return VMError.OutOfMemory;
        const rt_local = gc.allocSymbol(" __rt") catch return VMError.OutOfMemory;
        const rci_sym = gc.allocSymbol("%record?/inherit") catch return VMError.OutOfMemory;
        const body = gc.makeList(&[_]Value{ rci_sym, v_sym, rt_local }) catch return VMError.OutOfMemory;
        const params = gc.makeList(&[_]Value{v_sym}) catch return VMError.OutOfMemory;
        const lambda_sym = gc.allocSymbol("lambda") catch return VMError.OutOfMemory;
        const lambda_expr = gc.makeList(&[_]Value{ lambda_sym, params, body }) catch return VMError.OutOfMemory;
        const pred_full = wrapInRtLet(gc, internal_name, lambda_expr) catch return VMError.OutOfMemory;
        const define_sym = gc.allocSymbol("define") catch return VMError.OutOfMemory;
        const pred_sym = gc.allocSymbol(spec.pred_name) catch return VMError.OutOfMemory;
        const define_expr = gc.makeList(&[_]Value{ define_sym, pred_sym, pred_full }) catch return VMError.OutOfMemory;
        try compileAndRunDefine(vm, define_expr);
    }

    // --- accessors/mutators for THIS type's OWN fields only (inherited
    // fields already have accessors/mutators from the ancestor's own
    // define-record-type) ---
    for (0..spec.field_count) |fi| {
        const abs_idx = parent_total_fields + fi;
        {
            vm.gc.no_collect += 1;
            defer vm.gc.no_collect -= 1;
            const gc = vm.gc;
            const p_sym = gc.allocSymbol("p") catch return VMError.OutOfMemory;
            const rt_local = gc.allocSymbol(" __rt") catch return VMError.OutOfMemory;
            const rri_sym = gc.allocSymbol("%record-ref/inherit") catch return VMError.OutOfMemory;
            const idx_val = types.makeFixnum(@intCast(abs_idx));
            const body = gc.makeList(&[_]Value{ rri_sym, p_sym, idx_val, rt_local }) catch return VMError.OutOfMemory;
            const params = gc.makeList(&[_]Value{p_sym}) catch return VMError.OutOfMemory;
            const lambda_sym = gc.allocSymbol("lambda") catch return VMError.OutOfMemory;
            const lambda_expr = gc.makeList(&[_]Value{ lambda_sym, params, body }) catch return VMError.OutOfMemory;
            const acc_full = wrapInRtLet(gc, internal_name, lambda_expr) catch return VMError.OutOfMemory;
            const define_sym = gc.allocSymbol("define") catch return VMError.OutOfMemory;
            const acc_sym = gc.allocSymbol(spec.fields[fi].accessor_name) catch return VMError.OutOfMemory;
            const define_expr = gc.makeList(&[_]Value{ define_sym, acc_sym, acc_full }) catch return VMError.OutOfMemory;
            try compileAndRunDefine(vm, define_expr);
        }

        if (spec.fields[fi].mutator_name) |mut_name| {
            vm.gc.no_collect += 1;
            defer vm.gc.no_collect -= 1;
            const gc = vm.gc;
            const p_sym = gc.allocSymbol("p") catch return VMError.OutOfMemory;
            const v_sym = gc.allocSymbol("v") catch return VMError.OutOfMemory;
            const rt_local = gc.allocSymbol(" __rt") catch return VMError.OutOfMemory;
            const rsi_sym = gc.allocSymbol("%record-set!/inherit") catch return VMError.OutOfMemory;
            const idx_val = types.makeFixnum(@intCast(abs_idx));
            const body = gc.makeList(&[_]Value{ rsi_sym, p_sym, idx_val, v_sym, rt_local }) catch return VMError.OutOfMemory;
            const params = gc.makeList(&[_]Value{ p_sym, v_sym }) catch return VMError.OutOfMemory;
            const lambda_sym = gc.allocSymbol("lambda") catch return VMError.OutOfMemory;
            const lambda_expr = gc.makeList(&[_]Value{ lambda_sym, params, body }) catch return VMError.OutOfMemory;
            const mut_full = wrapInRtLet(gc, internal_name, lambda_expr) catch return VMError.OutOfMemory;
            const define_sym = gc.allocSymbol("define") catch return VMError.OutOfMemory;
            const mut_sym = gc.allocSymbol(mut_name) catch return VMError.OutOfMemory;
            const define_expr = gc.makeList(&[_]Value{ define_sym, mut_sym, mut_full }) catch return VMError.OutOfMemory;
            try compileAndRunDefine(vm, define_expr);
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

/// SRFI 237: every R6RS-clause-syntax record type's constructor is ALSO
/// bound under this fixed internal name, regardless of what user-facing
/// name the type's own `<name spec>` gave it -- a child type extending a
/// parent looks up the parent's constructor this way, so it never needs to
/// know (or guess) what name the parent's author actually chose.
fn internCtorName(gc: *GC, type_name: []const u8) CompileError![]const u8 {
    const buf = std.fmt.allocPrint(gc.allocator, " __record_ctor_{s}", .{type_name}) catch
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
    // SRFI 237/240's R6RS clause syntax is only supported at the top level
    // (handleDefineRecordTypeR6RS), not yet inside a library body -- fail
    // clearly here rather than letting parseRecordSpec's R7RS-shaped parser
    // silently misinterpret a clause list as malformed constructor syntax.
    if (looksLikeR6RSClauseSyntax(form_args)) return CompileError.InvalidSyntax;
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
    // See the identical guard in collectRecordTypeDefNames above.
    if (looksLikeR6RSClauseSyntax(form_args)) return CompileError.InvalidSyntax;
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

    // 2. (define ctor (let (( __rt __record_type_X)) (lambda (f1 f2) (%make-record  __rt ...))))
    {
        const rt_local = gc.allocSymbol(" __rt") catch return CompileError.OutOfMemory;
        const lambda_sym = gc.allocSymbol("lambda") catch return CompileError.OutOfMemory;
        const mr_sym = gc.allocSymbol("%make-record") catch return CompileError.OutOfMemory;

        var body_elems: [258]Value = undefined;
        body_elems[0] = mr_sym;
        body_elems[1] = rt_local;
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

        const lambda_expr = gc.makeList(&[_]Value{ lambda_sym, params, body }) catch return CompileError.OutOfMemory;
        const let_sym = gc.allocSymbol("let") catch return CompileError.OutOfMemory;
        const rt_ref = gc.allocSymbol(internal_name) catch return CompileError.OutOfMemory;
        const let_binding = gc.makeList(&[_]Value{ rt_local, rt_ref }) catch return CompileError.OutOfMemory;
        const let_bindings = gc.makeList(&[_]Value{let_binding}) catch return CompileError.OutOfMemory;
        def_inits[count.*] = gc.makeList(&[_]Value{ let_sym, let_bindings, lambda_expr }) catch return CompileError.OutOfMemory;
        def_names[count.*] = spec.ctor_name;
        extra_roots.append(gc.allocator, def_inits[count.*]) catch return CompileError.OutOfMemory;
        count.* += 1;
    }

    // 3. (define pred? (let (( __rt ...)) (lambda (v) (%record? v  __rt))))
    {
        const rt_local = gc.allocSymbol(" __rt") catch return CompileError.OutOfMemory;
        const lambda_sym = gc.allocSymbol("lambda") catch return CompileError.OutOfMemory;
        const rc_sym = gc.allocSymbol("%record?") catch return CompileError.OutOfMemory;
        const v_sym = gc.allocSymbol("v") catch return CompileError.OutOfMemory;

        const body = gc.makeList(&[_]Value{ rc_sym, v_sym, rt_local }) catch return CompileError.OutOfMemory;
        const params = gc.makeList(&[_]Value{v_sym}) catch return CompileError.OutOfMemory;
        const lambda_expr = gc.makeList(&[_]Value{ lambda_sym, params, body }) catch return CompileError.OutOfMemory;
        const let_sym = gc.allocSymbol("let") catch return CompileError.OutOfMemory;
        const rt_ref = gc.allocSymbol(internal_name) catch return CompileError.OutOfMemory;
        const let_binding = gc.makeList(&[_]Value{ rt_local, rt_ref }) catch return CompileError.OutOfMemory;
        const let_bindings = gc.makeList(&[_]Value{let_binding}) catch return CompileError.OutOfMemory;
        def_inits[count.*] = gc.makeList(&[_]Value{ let_sym, let_bindings, lambda_expr }) catch return CompileError.OutOfMemory;
        def_names[count.*] = spec.pred_name;
        extra_roots.append(gc.allocator, def_inits[count.*]) catch return CompileError.OutOfMemory;
        count.* += 1;
    }

    // 4. Accessors: (define acc (let (( __rt ...)) (lambda (p) (%record-ref p idx  __rt))))
    for (0..spec.field_count) |fi| {
        const rt_local = gc.allocSymbol(" __rt") catch return CompileError.OutOfMemory;
        const lambda_sym = gc.allocSymbol("lambda") catch return CompileError.OutOfMemory;
        const rr_sym = gc.allocSymbol("%record-ref") catch return CompileError.OutOfMemory;
        const p_sym = gc.allocSymbol("p") catch return CompileError.OutOfMemory;
        const idx = types.makeFixnum(@intCast(fi));

        const body = gc.makeList(&[_]Value{ rr_sym, p_sym, idx, rt_local }) catch return CompileError.OutOfMemory;
        const params = gc.makeList(&[_]Value{p_sym}) catch return CompileError.OutOfMemory;
        const lambda_expr = gc.makeList(&[_]Value{ lambda_sym, params, body }) catch return CompileError.OutOfMemory;
        const let_sym = gc.allocSymbol("let") catch return CompileError.OutOfMemory;
        const rt_ref = gc.allocSymbol(internal_name) catch return CompileError.OutOfMemory;
        const let_binding = gc.makeList(&[_]Value{ rt_local, rt_ref }) catch return CompileError.OutOfMemory;
        const let_bindings = gc.makeList(&[_]Value{let_binding}) catch return CompileError.OutOfMemory;
        def_inits[count.*] = gc.makeList(&[_]Value{ let_sym, let_bindings, lambda_expr }) catch return CompileError.OutOfMemory;
        def_names[count.*] = spec.accessor_names[fi];
        extra_roots.append(gc.allocator, def_inits[count.*]) catch return CompileError.OutOfMemory;
        count.* += 1;
    }

    // 5. Mutators: (define mut! (let (( __rt ...)) (lambda (p v) (%record-set! p idx v  __rt))))
    for (0..spec.field_count) |fi| {
        if (spec.mutator_names[fi]) |mname| {
            const rt_local = gc.allocSymbol(" __rt") catch return CompileError.OutOfMemory;
            const lambda_sym = gc.allocSymbol("lambda") catch return CompileError.OutOfMemory;
            const rs_sym = gc.allocSymbol("%record-set!") catch return CompileError.OutOfMemory;
            const p_sym = gc.allocSymbol("p") catch return CompileError.OutOfMemory;
            const v_sym = gc.allocSymbol("v") catch return CompileError.OutOfMemory;
            const idx = types.makeFixnum(@intCast(fi));

            const body = gc.makeList(&[_]Value{ rs_sym, p_sym, idx, v_sym, rt_local }) catch return CompileError.OutOfMemory;
            const params = gc.makeList(&[_]Value{ p_sym, v_sym }) catch return CompileError.OutOfMemory;
            const lambda_expr = gc.makeList(&[_]Value{ lambda_sym, params, body }) catch return CompileError.OutOfMemory;
            const let_sym = gc.allocSymbol("let") catch return CompileError.OutOfMemory;
            const rt_ref = gc.allocSymbol(internal_name) catch return CompileError.OutOfMemory;
            const let_binding = gc.makeList(&[_]Value{ rt_local, rt_ref }) catch return CompileError.OutOfMemory;
            const let_bindings = gc.makeList(&[_]Value{let_binding}) catch return CompileError.OutOfMemory;
            def_inits[count.*] = gc.makeList(&[_]Value{ let_sym, let_bindings, lambda_expr }) catch return CompileError.OutOfMemory;
            def_names[count.*] = mname;
            extra_roots.append(gc.allocator, def_inits[count.*]) catch return CompileError.OutOfMemory;
            count.* += 1;
        }
    }

    gc.no_collect -= 1;
}
