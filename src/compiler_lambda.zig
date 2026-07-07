const std = @import("std");
const types = @import("types.zig");
const memory = @import("memory.zig");
const compiler_mod = @import("compiler.zig");
const globals_mod = @import("globals.zig");
const macro = @import("compiler_macro.zig");
const vm_records = @import("vm_records.zig");
const Compiler = compiler_mod.Compiler;
const CompileError = compiler_mod.CompileError;
const Value = types.Value;
pub fn emitClosureEpilogue(self: *Compiler, child: *Compiler, target_reg: u16) CompileError!void {
    for (child.upvalues.items) |uv| {
        if (uv.is_local) {
            try self.markLocalBoxedBySlot(uv.index);
        }
    }
    const func_val = types.makePointer(@ptrCast(child.func));
    const idx = try self.addConstant(func_val);
    try self.emitOp(.closure);
    try self.emitU16(target_reg);
    try self.emitU16(idx);
    for (child.upvalues.items) |uv| {
        try self.emit(if (uv.is_local) 1 else 0);
        try self.emitU16(uv.index);
    }
}

pub fn compileLambda(self: *Compiler, args: Value, dst: u16, name: ?[]const u8) CompileError!void {
    if (args == types.NIL) return CompileError.InvalidSyntax;
    const formals = types.car(args);
    const body = types.cdr(args);
    if (body == types.NIL) return CompileError.InvalidSyntax;

    var child = try Compiler.initChild(self);
    defer child.deinit();

    // Parse formals
    var arity: u8 = 0;
    var is_variadic = false;
    var param_list = formals;

    if (types.isSymbol(formals)) {
        // (lambda x body) -- variadic, takes all args as list
        is_variadic = true;
        arity = 0;
        const slot = child.allocReg() catch return CompileError.TooManyLocals;
        child.locals.append(child.gc.allocator, .{
            .name = types.symbolName(formals),
            .depth = 1,
            .slot = slot,
            .binding_id = compiler_mod.freshBindingId(),
        }) catch return CompileError.OutOfMemory;
    } else {
        while (param_list != types.NIL) {
            if (types.isSymbol(param_list)) {
                // Rest parameter: (lambda (a b . rest) body)
                is_variadic = true;
                const slot = child.allocReg() catch return CompileError.TooManyLocals;
                child.locals.append(child.gc.allocator, .{
                    .name = types.symbolName(param_list),
                    .depth = 1,
                    .slot = slot,
                    .binding_id = compiler_mod.freshBindingId(),
                }) catch return CompileError.OutOfMemory;
                break;
            }
            if (!types.isPair(param_list)) return CompileError.InvalidSyntax;
            const param = types.car(param_list);
            if (!types.isSymbol(param)) return CompileError.InvalidSyntax;

            const slot = child.allocReg() catch return CompileError.TooManyLocals;
            child.locals.append(child.gc.allocator, .{
                .name = types.symbolName(param),
                .depth = 1,
                .slot = slot,
                .binding_id = compiler_mod.freshBindingId(),
            }) catch return CompileError.OutOfMemory;
            arity += 1;
            param_list = types.cdr(param_list);
        }
    }

    child.func.arity = arity;
    child.func.is_variadic = is_variadic;
    child.func.name = name;
    child.scope_depth = 1;

    for (child.locals.items) |local| {
        try child.boxIfSetTarget(local.name, local.slot);
    }

    // Compile body as implicit begin
    try compileBody(&child, body);

    child.populateDebugLocals();
    try emitClosureEpilogue(self, &child, dst);
}

pub fn compileBody(self: *Compiler, body: Value) CompileError!void {
    const saved_body_scope = self.in_body_scope;
    self.in_body_scope = true;
    const last_dst = try compileBodyForms(self, body, .{ .handle_define_syntax = true });
    self.in_body_scope = saved_body_scope;
    try self.emitOp(.@"return");
    try self.emitU16(last_dst);
}

pub const BodyOpts = struct {
    dst: ?u16 = null,
    is_tail: ?bool = null,
    handle_define_syntax: bool = false,
};

/// Shared implementation for lambda bodies and let-form bodies.
/// In lambda mode (dst=null): allocates per-expression registers, last is
/// always tail. In let-body mode (dst set): reuses caller's register.
pub fn compileBodyForms(self: *Compiler, body: Value, opts: BodyOpts) CompileError!u16 {
    const allocates_regs = opts.dst == null;

    // --- Globals prescan sentinel dance (#958) ---
    // Plant VOID sentinels for define names so macro expansion can see
    // sibling defs. Clean up still-VOID entries on exit.
    var prescan_names: std.ArrayList([]const u8) = .empty;
    defer prescan_names.deinit(self.gc.allocator);
    if (self.globals) |globals| {
        const glk = globals_mod.acquireGlobalsWrite(globals);
        defer globals_mod.releaseGlobalsWrite(glk);
        var scan = body;
        while (scan != types.NIL and types.isPair(scan)) {
            const form = types.car(scan);
            if (types.isPair(form)) {
                const head = types.car(form);
                if (types.isSymbol(head)) {
                    const form_name = types.symbolName(head);
                    if (std.mem.eql(u8, form_name, "define")) {
                        const form_args = types.cdr(form);
                        if (form_args != types.NIL and types.isPair(form_args)) {
                            const target = types.car(form_args);
                            var def_name: ?[]const u8 = null;
                            if (types.isSymbol(target)) {
                                def_name = types.symbolName(target);
                            } else if (types.isPair(target)) {
                                const fn_name = types.car(target);
                                if (types.isSymbol(fn_name)) def_name = types.symbolName(fn_name);
                            }
                            if (def_name) |dn| {
                                if (!globals.contains(dn)) {
                                    try globals.put(dn, types.VOID);
                                    try prescan_names.append(self.gc.allocator, dn);
                                }
                            }
                        }
                    } else if (std.mem.eql(u8, form_name, "define-record-type")) {
                        if (vm_records.parseRecordSpec(types.cdr(form))) |spec| {
                            if (!globals.contains(spec.ctor_name)) {
                                globals.put(spec.ctor_name, types.VOID) catch {};
                                prescan_names.append(self.gc.allocator, spec.ctor_name) catch {};
                            }
                            if (!globals.contains(spec.pred_name)) {
                                globals.put(spec.pred_name, types.VOID) catch {};
                                prescan_names.append(self.gc.allocator, spec.pred_name) catch {};
                            }
                            for (0..spec.field_count) |fi| {
                                if (!globals.contains(spec.accessor_names[fi])) {
                                    globals.put(spec.accessor_names[fi], types.VOID) catch {};
                                    prescan_names.append(self.gc.allocator, spec.accessor_names[fi]) catch {};
                                }
                                if (spec.mutator_names[fi]) |mn| {
                                    if (!globals.contains(mn)) {
                                        globals.put(mn, types.VOID) catch {};
                                        prescan_names.append(self.gc.allocator, mn) catch {};
                                    }
                                }
                            }
                        }
                    }
                }
            }
            scan = types.cdr(scan);
        }
    }
    defer {
        if (self.globals) |globals| {
            const glk = globals_mod.acquireGlobalsWrite(globals);
            for (prescan_names.items) |pn| {
                if (globals.get(pn)) |val| {
                    if (val == types.VOID) _ = globals.remove(pn);
                }
            }
            globals_mod.releaseGlobalsWrite(glk);
        }
    }

    // --- Collect leading internal defines (R7RS 5.3.2 letrec* desugar) ---
    const MAX_BODY_DEFS = 256;
    var def_names_arr: [MAX_BODY_DEFS][]const u8 = undefined;
    var def_inits: [MAX_BODY_DEFS]Value = undefined;
    var def_slots: [MAX_BODY_DEFS]u16 = undefined;
    var def_count: usize = 0;

    // def_inits lives in a stack array the GC cannot see. The (define (name
    // args...) body) case below allocates fresh lambda pairs into it, and both
    // the rest of this scan and the phase-2 compileExpr calls allocate, so a
    // collection would sweep the not-yet-compiled inits (issue #1010). Mirror
    // them into extra_roots (by value, realloc-safe) for the duration.
    const roots_base = self.gc.extra_roots.items.len;
    defer self.gc.extra_roots.shrinkRetainingCapacity(roots_base);

    var macro_count: usize = 0;
    const macro_mark = if (opts.handle_define_syntax) self.beginBodyMacroScope() else 0;
    defer if (opts.handle_define_syntax) self.endBodyMacroScope(macro_mark) catch {};

    // First pass: collect ALL leading define names so that define-syntax
    // forms (which may appear before or after a define in the same letrec*
    // region) see the complete set via extra_bound.
    var all_def_names: [MAX_BODY_DEFS][]const u8 = undefined;
    var all_def_count: usize = 0;
    {
        var scan = body;
        while (scan != types.NIL and types.isPair(scan)) {
            const expr = types.car(scan);
            if (!types.isPair(expr)) break;
            const head = types.car(expr);
            if (!types.isSymbol(head)) break;
            const hn = types.symbolName(head);
            if (std.mem.eql(u8, hn, "define")) {
                const da = types.cdr(expr);
                if (da == types.NIL or !types.isPair(da)) break;
                const tgt = types.car(da);
                if (types.isSymbol(tgt)) {
                    if (all_def_count < MAX_BODY_DEFS) {
                        all_def_names[all_def_count] = types.symbolName(tgt);
                        all_def_count += 1;
                    }
                } else if (types.isPair(tgt)) {
                    const fn_name = types.car(tgt);
                    if (types.isSymbol(fn_name) and all_def_count < MAX_BODY_DEFS) {
                        all_def_names[all_def_count] = types.symbolName(fn_name);
                        all_def_count += 1;
                    }
                } else break;
            } else if (std.mem.eql(u8, hn, "define-record-type")) {
                vm_records.collectRecordTypeDefNames(self.gc, types.cdr(expr), all_def_names[0..], &all_def_count) catch |err| switch (err) {
                    CompileError.InvalidSyntax => break,
                    else => return err,
                };
            } else if (!(opts.handle_define_syntax and std.mem.eql(u8, hn, "define-syntax"))) {
                break;
            }
            scan = types.cdr(scan);
        }
    }

    // Second pass: collect define inits and process define-syntax forms.
    var current = body;
    while (current != types.NIL and types.isPair(current)) {
        const expr = types.car(current);
        if (!types.isPair(expr)) break;
        const head = types.car(expr);
        if (!types.isSymbol(head)) break;
        const head_name = types.symbolName(head);
        if (std.mem.eql(u8, head_name, "define")) {
            const def_args = types.cdr(expr);
            if (def_args == types.NIL or !types.isPair(def_args)) break;
            const target = types.car(def_args);
            const def_rest = types.cdr(def_args);

            if (types.isSymbol(target)) {
                if (def_rest == types.NIL or !types.isPair(def_rest)) break;
                if (def_count >= MAX_BODY_DEFS) return CompileError.TooManyLocals;
                def_names_arr[def_count] = types.symbolName(target);
                def_inits[def_count] = types.car(def_rest);
                def_count += 1;
            } else if (types.isPair(target)) {
                const fn_name = types.car(target);
                if (!types.isSymbol(fn_name)) break;
                if (def_count >= MAX_BODY_DEFS) return CompileError.TooManyLocals;
                def_names_arr[def_count] = types.symbolName(fn_name);
                const param_formals = types.cdr(target);
                const lambda_sym = self.gc.allocSymbol("lambda") catch return CompileError.OutOfMemory;
                {
                    var lambda_args = self.gc.allocPair(param_formals, def_rest) catch return CompileError.OutOfMemory;
                    self.gc.pushRoot(&lambda_args);
                    defer self.gc.popRoot();
                    def_inits[def_count] = self.gc.allocPair(lambda_sym, lambda_args) catch return CompileError.OutOfMemory;
                }
                self.gc.extra_roots.append(self.gc.allocator, def_inits[def_count]) catch return CompileError.OutOfMemory;
                def_count += 1;
            } else {
                break;
            }
        } else if (std.mem.eql(u8, head_name, "define-record-type")) {
            vm_records.expandRecordTypeDefines(
                self.gc,
                types.cdr(expr),
                def_names_arr[0..],
                def_inits[0..],
                &def_count,
                &self.gc.extra_roots,
            ) catch |err| switch (err) {
                CompileError.InvalidSyntax => break,
                else => return err,
            };
        } else if (opts.handle_define_syntax and std.mem.eql(u8, head_name, "define-syntax")) {
            const ds_args = types.cdr(expr);
            if (ds_args == types.NIL or !types.isPair(ds_args)) break;
            const keyword = types.car(ds_args);
            if (!types.isSymbol(keyword)) break;
            const ds_rest = types.cdr(ds_args);
            if (ds_rest == types.NIL or !types.isPair(ds_rest)) break;
            const transformer_spec = types.car(ds_rest);

            const transformer = macro.parseSyntaxRules(self, transformer_spec, all_def_names[0..all_def_count]) catch break;
            const name = types.symbolName(keyword);

            try self.recordBodyMacro(name);
            macro_count += 1;

            const tx = types.toObject(transformer).as(types.Transformer);
            if (self.lib_env) |env| {
                tx.def_env = env;
                tx.def_env_val = self.lib_env_val;
            }
            self.macros.put(name, transformer) catch return CompileError.OutOfMemory;
        } else {
            break;
        }
        current = types.cdr(current);
    }

    // --- Compile defines + remaining body ---
    var last_dst: u16 = opts.dst orelse 0;

    if (def_count > 0) {
        self.beginScope();

        for (0..def_count) |i| {
            const slot = try self.allocReg();
            def_slots[i] = slot;
            try self.emitOp(.load_void);
            try self.emitU16(slot);
            try self.addLocal(def_names_arr[i], slot);
            try self.markLocalBoxedBySlot(slot);
        }

        for (0..def_count) |i| {
            if (allocates_regs) {
                last_dst = try self.allocReg();
                try self.compileExprViaIR(def_inits[i], last_dst, false);
                try self.emitOp(.set_box_local);
                try self.emitU16(def_slots[i]);
                try self.emitU16(last_dst);
                self.freeReg();
            } else {
                try self.compileExprViaIR(def_inits[i], last_dst, false);
                try self.emitOp(.set_box_local);
                try self.emitU16(def_slots[i]);
                try self.emitU16(last_dst);
            }
        }

        if (current == types.NIL and allocates_regs) {
            last_dst = try self.allocReg();
            try self.emitOp(.load_void);
            try self.emitU16(last_dst);
        } else {
            try compileExprSequence(self, &current, &last_dst, allocates_regs, opts.is_tail);
        }

        self.endScope();
    } else if (current != types.NIL) {
        try compileExprSequence(self, &current, &last_dst, allocates_regs, opts.is_tail);
    } else if (macro_count > 0 and !allocates_regs) {
        try self.emitOp(.load_void);
        try self.emitU16(last_dst);
    }

    return last_dst;
}

fn compileExprSequence(self: *Compiler, current: *Value, last_dst: *u16, allocates_regs: bool, caller_tail: ?bool) CompileError!void {
    while (current.* != types.NIL) {
        if (!types.isPair(current.*)) return CompileError.InvalidSyntax;
        const expr = types.car(current.*);
        current.* = types.cdr(current.*);
        const is_last = current.* == types.NIL;
        if (allocates_regs) {
            last_dst.* = try self.allocReg();
            if (is_last) {
                try self.compileExprViaIR(expr, last_dst.*, true);
            } else {
                const saved_next = self.next_register;
                try self.compileExprViaIR(expr, last_dst.*, false);
                if (self.next_register == saved_next) {
                    self.freeReg();
                }
            }
        } else {
            const tail = (caller_tail orelse false) and is_last;
            try self.compileExprViaIR(expr, last_dst.*, tail);
        }
    }
}

pub fn compileDefine(self: *Compiler, args: Value, dst: u16) CompileError!void {
    if (args == types.NIL) return CompileError.InvalidSyntax;
    const target = types.car(args);
    const rest = types.cdr(args);

    if (types.isSymbol(target)) {
        // (define x expr)
        if (rest == types.NIL) return CompileError.InvalidSyntax;
        const value_expr = types.car(rest);
        try self.compileExprViaIR(value_expr, dst, false);

        // If the expression compiled to a lambda, set its name for debugging
        if (self.func.constants.items.len > 0) {
            const last_const = self.func.constants.items[self.func.constants.items.len - 1];
            if (types.isFunction(last_const)) {
                const child_func = types.toObject(last_const).as(types.Function);
                if (child_func.name == null) {
                    child_func.name = types.symbolName(target);
                }
            }
        }

        if (self.in_body_scope) {
            const slot = try self.allocReg();
            try self.emitOp(.move);
            try self.emitU16(slot);
            try self.emitU16(dst);
            self.locals.append(self.gc.allocator, .{
                .name = types.symbolName(target),
                .depth = self.scope_depth,
                .slot = slot,
                .binding_id = compiler_mod.freshBindingId(),
            }) catch return CompileError.OutOfMemory;
            try self.emitOp(.load_void);
            try self.emitU16(dst);
            return;
        }
        const sym_idx = try self.addConstant(target);
        try self.emitOp(.define_global);
        try self.emitU16(sym_idx);
        try self.emitU16(dst);
        try self.emitOp(.load_void);
        try self.emitU16(dst);
        return;
    }

    if (types.isPair(target)) {
        // (define (name args...) body) => (define name (lambda (args...) body))
        const name = types.car(target);
        if (!types.isSymbol(name)) return CompileError.InvalidSyntax;
        const param_formals = types.cdr(target);

        var lambda_args = self.gc.allocPair(param_formals, rest) catch return CompileError.OutOfMemory;
        self.gc.pushRoot(&lambda_args);
        defer self.gc.popRoot();
        try compileLambda(self, lambda_args, dst, types.symbolName(name));

        if (self.in_body_scope) {
            const slot = try self.allocReg();
            try self.emitOp(.move);
            try self.emitU16(slot);
            try self.emitU16(dst);
            self.locals.append(self.gc.allocator, .{
                .name = types.symbolName(name),
                .depth = self.scope_depth,
                .slot = slot,
                .binding_id = compiler_mod.freshBindingId(),
            }) catch return CompileError.OutOfMemory;
            try self.emitOp(.load_void);
            try self.emitU16(dst);
            return;
        }
        const sym_idx = try self.addConstant(name);
        try self.emitOp(.define_global);
        try self.emitU16(sym_idx);
        try self.emitU16(dst);
        try self.emitOp(.load_void);
        try self.emitU16(dst);
        return;
    }

    return CompileError.InvalidSyntax;
}

/// General-dispatch handler for define-record-type.
/// Builds define S-expressions and compiles each one, so that compileDefine's
/// in_body_scope path creates local variables when appropriate.
/// Covers positions the leading-define body scanner doesn't reach
/// (e.g. let-values bodies, begin-splicing inside lambdas).
pub fn compileDefineRecordType(self: *Compiler, args: Value, dst: u16) CompileError!void {
    const gc = self.gc;
    const spec = vm_records.parseRecordSpec(args) orelse return CompileError.InvalidSyntax;
    const internal_name = try vm_records.internRecordTypeName(gc, spec.type_name);

    gc.no_collect += 1;
    errdefer gc.no_collect -= 1;

    const define_sym = gc.allocSymbol("define") catch return CompileError.OutOfMemory;

    // Build all define forms as a list (consing in reverse)
    var forms = types.NIL;

    // Mutators (reverse order)
    {
        var fi = spec.field_count;
        while (fi > 0) {
            fi -= 1;
            if (spec.mutator_names[fi]) |mn| {
                const rs = gc.allocSymbol("%record-set!") catch return CompileError.OutOfMemory;
                const p = gc.allocSymbol("p") catch return CompileError.OutOfMemory;
                const v = gc.allocSymbol("v") catch return CompileError.OutOfMemory;
                const idx = types.makeFixnum(@intCast(fi));
                const rt_ref = gc.allocSymbol(internal_name) catch return CompileError.OutOfMemory;
                const body = gc.makeList(&[_]Value{ rs, p, idx, v, rt_ref }) catch return CompileError.OutOfMemory;
                const np = gc.allocPair(gc.allocSymbol(mn) catch return CompileError.OutOfMemory, gc.makeList(&[_]Value{ p, v }) catch return CompileError.OutOfMemory) catch return CompileError.OutOfMemory;
                forms = gc.allocPair(gc.makeList(&[_]Value{ define_sym, np, body }) catch return CompileError.OutOfMemory, forms) catch return CompileError.OutOfMemory;
            }
        }
    }

    // Accessors (reverse order)
    {
        var fi = spec.field_count;
        while (fi > 0) {
            fi -= 1;
            const rr = gc.allocSymbol("%record-ref") catch return CompileError.OutOfMemory;
            const p = gc.allocSymbol("p") catch return CompileError.OutOfMemory;
            const idx = types.makeFixnum(@intCast(fi));
            const rt_ref = gc.allocSymbol(internal_name) catch return CompileError.OutOfMemory;
            const body = gc.makeList(&[_]Value{ rr, p, idx, rt_ref }) catch return CompileError.OutOfMemory;
            const np = gc.allocPair(gc.allocSymbol(spec.accessor_names[fi]) catch return CompileError.OutOfMemory, gc.makeList(&[_]Value{p}) catch return CompileError.OutOfMemory) catch return CompileError.OutOfMemory;
            forms = gc.allocPair(gc.makeList(&[_]Value{ define_sym, np, body }) catch return CompileError.OutOfMemory, forms) catch return CompileError.OutOfMemory;
        }
    }

    // Predicate
    {
        const rc = gc.allocSymbol("%record?") catch return CompileError.OutOfMemory;
        const v = gc.allocSymbol("v") catch return CompileError.OutOfMemory;
        const rt_ref = gc.allocSymbol(internal_name) catch return CompileError.OutOfMemory;
        const body = gc.makeList(&[_]Value{ rc, v, rt_ref }) catch return CompileError.OutOfMemory;
        const np = gc.allocPair(gc.allocSymbol(spec.pred_name) catch return CompileError.OutOfMemory, gc.makeList(&[_]Value{v}) catch return CompileError.OutOfMemory) catch return CompileError.OutOfMemory;
        forms = gc.allocPair(gc.makeList(&[_]Value{ define_sym, np, body }) catch return CompileError.OutOfMemory, forms) catch return CompileError.OutOfMemory;
    }

    // Constructor
    {
        const mr = gc.allocSymbol("%make-record") catch return CompileError.OutOfMemory;
        const rt_ref = gc.allocSymbol(internal_name) catch return CompileError.OutOfMemory;
        var body_elems: [258]Value = undefined;
        body_elems[0] = mr;
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
        const np = gc.allocPair(gc.allocSymbol(spec.ctor_name) catch return CompileError.OutOfMemory, gc.makeList(param_syms[0..spec.ctor_field_count]) catch return CompileError.OutOfMemory) catch return CompileError.OutOfMemory;
        forms = gc.allocPair(gc.makeList(&[_]Value{ define_sym, np, body }) catch return CompileError.OutOfMemory, forms) catch return CompileError.OutOfMemory;
    }

    // Internal record type: (define __rt (%make-record-type "name" n))
    {
        const mrt = gc.allocSymbol("%make-record-type") catch return CompileError.OutOfMemory;
        const ns = gc.allocString(spec.type_name) catch return CompileError.OutOfMemory;
        const nf = types.makeFixnum(@intCast(spec.field_count));
        const init = gc.makeList(&[_]Value{ mrt, ns, nf }) catch return CompileError.OutOfMemory;
        const rt_sym = gc.allocSymbol(internal_name) catch return CompileError.OutOfMemory;
        forms = gc.allocPair(gc.makeList(&[_]Value{ define_sym, rt_sym, init }) catch return CompileError.OutOfMemory, forms) catch return CompileError.OutOfMemory;
    }

    gc.no_collect -= 1;

    gc.pushRoot(&forms);
    defer gc.popRoot();
    var current = forms;
    while (current != types.NIL and types.isPair(current)) {
        try self.compileExprViaIR(types.car(current), dst, false);
        current = types.cdr(current);
    }
}

pub fn compileDefineValues(self: *Compiler, args: Value, dst: u16) CompileError!void {
    if (args == types.NIL) return CompileError.InvalidSyntax;
    const formals = types.car(args);
    const rest = types.cdr(args);
    if (rest == types.NIL or !types.isPair(rest)) return CompileError.InvalidSyntax;
    const expr = types.car(rest);

    // Collect formal names and count
    var names_buf: [64][]const u8 = undefined;
    var name_count: usize = 0;
    var rest_name: ?[]const u8 = null;
    var formal = formals;

    if (formals == types.NIL) {
        // (define-values () expr) — no bindings, just evaluate for side effects
        try self.compileExprViaIR(expr, dst, false);
        try self.emitOp(.load_void);
        try self.emitU16(dst);
        return;
    }

    if (types.isSymbol(formals)) {
        // (define-values x expr) — single symbol collects all values as list
        rest_name = types.symbolName(formals);
    } else {
        while (formal != types.NIL) {
            if (types.isSymbol(formal)) {
                rest_name = types.symbolName(formal);
                break;
            }
            if (!types.isPair(formal)) return CompileError.InvalidSyntax;
            const sym = types.car(formal);
            if (!types.isSymbol(sym)) return CompileError.InvalidSyntax;
            if (name_count >= 64) return CompileError.InvalidSyntax;
            names_buf[name_count] = types.symbolName(sym);
            name_count += 1;
            formal = types.cdr(formal);
        }
    }

    // Build desugared form:
    //   (define x (if #f #f)) ...  ;; pre-define all variables
    //   (call-with-values (lambda () expr) (lambda (a b c ...) (set! x a) (set! y b) ...))
    // Then compile the desugared begin block.

    // Step 1: emit (define name (if #f #f)) for each name
    for (names_buf[0..name_count]) |name| {
        var def_args = try buildVoidDefineArgs(self, name);
        self.gc.pushRoot(&def_args);
        defer self.gc.popRoot();
        try compileDefine(self, def_args, dst);
    }
    if (rest_name) |rn| {
        var def_args = try buildVoidDefineArgs(self, rn);
        self.gc.pushRoot(&def_args);
        defer self.gc.popRoot();
        try compileDefine(self, def_args, dst);
    }

    // Steps 2+3 build chains of fresh unrooted pairs, each allocation able to
    // sweep the previous ones, so collection is disabled for the whole build
    // (issue #1010). The final form is rooted across the compile that follows.
    var final_form: Value = types.NIL;
    const is_single = name_count == 0 and rest_name != null;
    {
        self.gc.no_collect += 1;
        defer self.gc.no_collect -= 1;

        // Step 2: Build the consumer lambda params and set! body
        // Consumer: (lambda (p0 p1 ... [. prest]) (set! x0 p0) (set! x1 p1) ... )
        var consumer_body: Value = types.NIL;

        // Build set! forms from right to left
        if (rest_name) |rn| {
            if (name_count > 0) {
                const rn_sym = self.gc.allocSymbol(rn) catch return CompileError.OutOfMemory;
                const param_sym = self.gc.allocSymbol("__dv_rest") catch return CompileError.OutOfMemory;
                const set_rest = self.gc.allocPair(param_sym, types.NIL) catch return CompileError.OutOfMemory;
                const set_args = self.gc.allocPair(rn_sym, set_rest) catch return CompileError.OutOfMemory;
                const set_sym = self.gc.allocSymbol("set!") catch return CompileError.OutOfMemory;
                const set_form = self.gc.allocPair(set_sym, set_args) catch return CompileError.OutOfMemory;
                consumer_body = self.gc.allocPair(set_form, consumer_body) catch return CompileError.OutOfMemory;
            }
        }

        var i = name_count;
        while (i > 0) {
            i -= 1;
            const orig_sym = self.gc.allocSymbol(names_buf[i]) catch return CompileError.OutOfMemory;
            var param_name_buf: [32]u8 = undefined;
            const pname = std.fmt.bufPrint(&param_name_buf, "__dv_{d}", .{i}) catch return CompileError.OutOfMemory;
            const param_sym = self.gc.allocSymbol(pname) catch return CompileError.OutOfMemory;
            const set_rest = self.gc.allocPair(param_sym, types.NIL) catch return CompileError.OutOfMemory;
            const set_args = self.gc.allocPair(orig_sym, set_rest) catch return CompileError.OutOfMemory;
            const set_sym = self.gc.allocSymbol("set!") catch return CompileError.OutOfMemory;
            const set_form = self.gc.allocPair(set_sym, set_args) catch return CompileError.OutOfMemory;
            consumer_body = self.gc.allocPair(set_form, consumer_body) catch return CompileError.OutOfMemory;
        }

        // Build consumer params list
        var consumer_params: Value = if (rest_name != null and name_count > 0)
            self.gc.allocSymbol("__dv_rest") catch return CompileError.OutOfMemory
        else
            types.NIL;

        i = name_count;
        while (i > 0) {
            i -= 1;
            var param_name_buf: [32]u8 = undefined;
            const pname = std.fmt.bufPrint(&param_name_buf, "__dv_{d}", .{i}) catch return CompileError.OutOfMemory;
            const param_sym = self.gc.allocSymbol(pname) catch return CompileError.OutOfMemory;
            consumer_params = self.gc.allocPair(param_sym, consumer_params) catch return CompileError.OutOfMemory;
        }

        if (is_single) {
            // Single-symbol case: (define-values x expr) needs list conversion
            // Desugar: (define-values x expr) → (set! x (call-with-values (lambda () expr) list))
            const rn_sym = self.gc.allocSymbol(rest_name.?) catch return CompileError.OutOfMemory;
            const list_sym = self.gc.allocSymbol("list") catch return CompileError.OutOfMemory;

            const producer_body = self.gc.allocPair(expr, types.NIL) catch return CompileError.OutOfMemory;
            const producer_lambda = self.gc.allocPair(types.NIL, producer_body) catch return CompileError.OutOfMemory;
            const lambda_sym = self.gc.allocSymbol("lambda") catch return CompileError.OutOfMemory;
            const producer = self.gc.allocPair(lambda_sym, producer_lambda) catch return CompileError.OutOfMemory;

            const cwv_sym = self.gc.allocSymbol("call-with-values") catch return CompileError.OutOfMemory;
            const cwv_3 = self.gc.allocPair(list_sym, types.NIL) catch return CompileError.OutOfMemory;
            const cwv_2 = self.gc.allocPair(producer, cwv_3) catch return CompileError.OutOfMemory;
            const cwv_form = self.gc.allocPair(cwv_sym, cwv_2) catch return CompileError.OutOfMemory;

            const set_rest2 = self.gc.allocPair(cwv_form, types.NIL) catch return CompileError.OutOfMemory;
            final_form = self.gc.allocPair(rn_sym, set_rest2) catch return CompileError.OutOfMemory;
        } else {
            // Build (lambda consumer_params consumer_body...)
            const consumer_lambda_args = self.gc.allocPair(consumer_params, consumer_body) catch return CompileError.OutOfMemory;
            const lambda_sym = self.gc.allocSymbol("lambda") catch return CompileError.OutOfMemory;
            const consumer = self.gc.allocPair(lambda_sym, consumer_lambda_args) catch return CompileError.OutOfMemory;

            // Build (lambda () expr)
            const producer_body = self.gc.allocPair(expr, types.NIL) catch return CompileError.OutOfMemory;
            const producer_lambda = self.gc.allocPair(types.NIL, producer_body) catch return CompileError.OutOfMemory;
            const producer = self.gc.allocPair(lambda_sym, producer_lambda) catch return CompileError.OutOfMemory;

            // Build (call-with-values producer consumer)
            const cwv_sym = self.gc.allocSymbol("call-with-values") catch return CompileError.OutOfMemory;
            const cwv_3 = self.gc.allocPair(consumer, types.NIL) catch return CompileError.OutOfMemory;
            const cwv_2 = self.gc.allocPair(producer, cwv_3) catch return CompileError.OutOfMemory;
            final_form = self.gc.allocPair(cwv_sym, cwv_2) catch return CompileError.OutOfMemory;
        }
    }

    self.gc.pushRoot(&final_form);
    defer self.gc.popRoot();
    if (is_single) {
        try compileSet(self, final_form, dst);
        return;
    }

    // Compile the call-with-values expression
    try self.compileExprViaIR(final_form, dst, false);
    try self.emitOp(.load_void);
    try self.emitU16(dst);
}

/// Build ((name (if #f #f))) define args for define-values pre-definitions,
/// with collection disabled during the chain of fresh pair allocations.
fn buildVoidDefineArgs(self: *Compiler, name: []const u8) CompileError!Value {
    self.gc.no_collect += 1;
    defer self.gc.no_collect -= 1;
    const sym = self.gc.allocSymbol(name) catch return CompileError.OutOfMemory;
    const void_expr = self.gc.allocPair(types.FALSE, types.NIL) catch return CompileError.OutOfMemory;
    const if_args = self.gc.allocPair(types.FALSE, void_expr) catch return CompileError.OutOfMemory;
    const if_sym = self.gc.allocSymbol("if") catch return CompileError.OutOfMemory;
    const if_form = self.gc.allocPair(if_sym, if_args) catch return CompileError.OutOfMemory;
    const def_rest = self.gc.allocPair(if_form, types.NIL) catch return CompileError.OutOfMemory;
    return self.gc.allocPair(sym, def_rest) catch return CompileError.OutOfMemory;
}

pub fn compileSet(self: *Compiler, args: Value, dst: u16) CompileError!void {
    if (args == types.NIL) return CompileError.InvalidSyntax;
    const target = types.car(args);
    const rest = types.cdr(args);
    if (rest == types.NIL) return CompileError.InvalidSyntax;
    if (!types.isSymbol(target)) return CompileError.InvalidSyntax;

    const value_expr = types.car(rest);
    try self.compileExprViaIR(value_expr, dst, false);

    const name = types.symbolName(target);
    if (self.resolveLocal(name)) |slot| {
        if (self.isLocalGlobalAlias(name)) {
            // The target is a register alias injected for a macro template's
            // free reference to a global: the variable itself lives in the
            // globals map, so write through to it, then refresh the alias
            // register for subsequent reads within the same expansion.
            const sym_idx = try self.addConstant(target);
            try self.emitOp(.set_global);
            try self.emitU16(sym_idx);
            try self.emitU16(dst);
            try self.emitOp(.move);
            try self.emitU16(slot);
            try self.emitU16(dst);
        } else if (self.isLocalBoxed(name)) {
            try self.emitOp(.set_box_local);
            try self.emitU16(slot);
            try self.emitU16(dst);
        } else {
            try self.emitOp(.move);
            try self.emitU16(slot);
            try self.emitU16(dst);
        }
    } else if (try self.resolveUpvalue(name)) |idx| {
        try self.emitOp(.set_upvalue);
        try self.emitU16(idx);
        try self.emitU16(dst);
    } else {
        const sym_idx = try self.addConstant(target);
        try self.emitOp(.set_global);
        try self.emitU16(sym_idx);
        try self.emitU16(dst);
    }
    try self.emitOp(.load_void);
    try self.emitU16(dst);
}

/// Compile (delay expr) as: create a promise wrapping (lambda () expr)
pub fn compileDelay(self: *Compiler, args: Value, dst: u16) CompileError!void {
    if (args == types.NIL) return CompileError.InvalidSyntax;
    const expr = types.car(args);

    // Compile (lambda () expr) using the same pattern as compileLambda
    var child = try Compiler.initChild(self);
    defer child.deinit();
    child.func.arity = 0;
    child.func.is_variadic = false;
    child.scope_depth = 1;
    const body_dst = child.allocReg() catch return CompileError.TooManyLocals;
    try child.compileExprViaIR(expr, body_dst, true);
    try child.emitOp(.@"return");
    try child.emitU16(body_dst);

    const thunk_reg = try self.allocReg();
    try emitClosureEpilogue(self, &child, thunk_reg);

    // Call %make-promise-lazy(thunk) — use fresh registers to avoid clobbering
    const sym = self.gc.allocSymbol("%make-promise-lazy") catch return CompileError.OutOfMemory;
    const sym_idx = try self.addConstant(sym);
    const call_base = try self.allocReg();
    try self.emitOp(.get_global);
    try self.emitU16(call_base);
    try self.emitU16(sym_idx);

    try self.emitOp(.move);
    try self.emitU16(call_base + 1);
    try self.emitU16(thunk_reg);

    try self.emitOp(.call);
    try self.emitU16(call_base);
    try self.emit(1);
    try self.emitOp(.move);
    try self.emitU16(dst);
    try self.emitU16(call_base);

    self.freeReg(); // free call_base
    self.freeReg(); // free thunk_reg
}

/// Compile (delay-force expr) — like delay but the result is itself forced iteratively
pub fn compileDelayForce(self: *Compiler, args: Value, dst: u16) CompileError!void {
    // delay-force is the same as delay for our purposes —
    // the iterative forcing in forceFn handles this correctly
    return compileDelay(self, args, dst);
}

pub fn compileBegin(self: *Compiler, args: Value, dst: u16, is_tail: bool) CompileError!void {
    if (args == types.NIL) {
        try self.emitOp(.load_void);
        try self.emitU16(dst);
        return;
    }

    var current = args;
    while (current != types.NIL) {
        if (!types.isPair(current)) return CompileError.InvalidSyntax;
        const expr = types.car(current);
        current = types.cdr(current);
        const tail = is_tail and current == types.NIL;
        try self.compileExprViaIR(expr, dst, tail);
    }
}

// -- Macro forms --
