const std = @import("std");
const types = @import("types.zig");
const memory = @import("memory.zig");
const compiler_mod = @import("compiler.zig");
const forms = @import("compiler_forms.zig");
const advanced = @import("compiler_advanced.zig");
const compiler_lambda = @import("compiler_lambda.zig");
const macro = @import("compiler_macro.zig");
const globals_mod = @import("globals.zig");
const ir_mod = @import("ir.zig");
const vm_records = @import("vm_records.zig");
const Value = types.Value;
const OpCode = types.OpCode;
const Compiler = compiler_mod.Compiler;
const CompileError = compiler_mod.CompileError;

pub fn compileFromNode(self: *Compiler, node: *ir_mod.Node, dst: u16, is_tail: bool) CompileError!void {
    if (node.ann.source_line > 0 and node.ann.source_line != self.current_line) {
        self.current_line = node.ann.source_line;
        try self.func.line_table.append(self.gc.allocator, .{
            .offset = @intCast(self.func.code.items.len),
            .line = node.ann.source_line,
        });
    }

    const tail = if (node.ann.is_tail) true else is_tail;
    switch (node.tag) {
        .constant => try self.emitLoadValue(dst, node.data.constant),
        .global_ref => try self.compileVariable(node.data.global_ref, dst),
        .call => try compileCallFromIR(self, node.data.call, dst, tail),
        .@"if" => try compileIfFromIR(self, node.data.@"if", dst, tail),
        .begin => try compileBeginFromIR(self, node.data.begin, dst, tail),
        .and_form => try compileAndFromIR(self, node.data.and_form, dst, tail),
        .or_form => try compileOrFromIR(self, node.data.or_form, dst, tail),
        .when_form => try compileWhenFromIR(self, node.data.when_form, dst, tail),
        .unless_form => try compileUnlessFromIR(self, node.data.unless_form, dst, tail),
        .define => try compileDefineFromIR(self, node.data.define, dst),
        .set_form => try compileSetFromIR(self, node.data.set_form, dst),
        .lambda => try compileLambdaWithIR(self, node.data.lambda.args, dst, node.data.lambda.name),
        .let_form => try forms.compileLet(self, node.data.let_form.args, dst, tail),
        .let_star => try forms.compileLetStar(self, node.data.let_star.args, dst, tail),
        .letrec => try forms.compileLetrec(self, node.data.letrec.args, dst, tail),
        .letrec_star => try forms.compileLetrecStar(self, node.data.letrec_star.args, dst, tail),
        .sexpr_form => {
            const sf = node.data.sexpr_form;
            switch (sf.form) {
                .do_form => try forms.compileDo(self, sf.args, dst, tail),
                .delay => try compiler_lambda.compileDelay(self, sf.args, dst),
                .delay_force => try compiler_lambda.compileDelayForce(self, sf.args, dst),
                .cond => try forms.compileCond(self, sf.args, dst, tail),
                .case_form => try forms.compileCase(self, sf.args, dst, tail),
                .case_lambda => try forms.compileCaseLambda(self, sf.args, dst),
                .guard => try forms.compileGuard(self, sf.args, dst, tail),
                .quasiquote => try advanced.compileQuasiquote(self, sf.args, dst),
                .parameterize => try advanced.compileParameterize(self, sf.args, dst, tail),
                .define_values => try compiler_lambda.compileDefineValues(self, sf.args, dst),
                .let_values => try forms.compileLetValues(self, sf.args, dst, tail),
                .let_star_values => try forms.compileLetStarValues(self, sf.args, dst, tail),
                .define_syntax => try macro.compileDefineSyntax(self, sf.args, dst),
                .named_let => try forms.compileNamedLet(self, sf.args, dst, tail),
                .let_syntax => try macro.compileLetSyntax(self, sf.args, dst, tail),
                .letrec_syntax => try macro.compileLetrecSyntax(self, sf.args, dst, tail),
                .cond_expand => try forms.compileCondExpand(self, sf.args, dst, is_tail),
            }
        },
        .passthrough => try self.compileExpr(node.data.passthrough, dst, is_tail),
    }
}

fn compileIfFromIR(self: *Compiler, data: ir_mod.IfData, dst: u16, is_tail: bool) CompileError!void {
    try compileFromNode(self, data.test_expr, dst, false);
    try self.emitOp(.jump_false);
    try self.emitU16(dst);
    const else_jump = self.currentOffset();
    try self.emitI16(0);
    try compileFromNode(self, data.consequent, dst, is_tail);
    if (data.alternate) |alt| {
        try self.emitOp(.jump);
        const end_jump = self.currentOffset();
        try self.emitI16(0);
        try self.patchJump(else_jump);
        try compileFromNode(self, alt, dst, is_tail);
        try self.patchJump(end_jump);
    } else {
        try self.emitOp(.jump);
        const end_jump = self.currentOffset();
        try self.emitI16(0);
        try self.patchJump(else_jump);
        try self.emitOp(.load_void);
        try self.emitU16(dst);
        try self.patchJump(end_jump);
    }
}

fn compileBeginFromIR(self: *Compiler, exprs: []const *ir_mod.Node, dst: u16, is_tail: bool) CompileError!void {
    if (exprs.len == 0) {
        try self.emitOp(.load_void);
        try self.emitU16(dst);
        return;
    }
    for (exprs, 0..) |expr, i| {
        const tail = is_tail and i == exprs.len - 1;
        try compileFromNode(self, expr, dst, tail);
    }
}

fn compileCallFromIR(self: *Compiler, call: ir_mod.CallData, dst: u16, is_tail: bool) CompileError!void {
    if (call.args.len > 255) return CompileError.InternalLimit;
    const nargs: u8 = @intCast(call.args.len);

    if (is_tail and call.operator.tag == .global_ref and self.func.name != null) {
        const sym = call.operator.data.global_ref;
        if (types.isSymbol(sym)) {
            const op_name = types.symbolName(sym);
            if (std.mem.eql(u8, op_name, self.func.name.?) and !self.func.is_variadic and nargs == self.func.arity) {
                if (std.mem.startsWith(u8, op_name, "__nlet_")) {
                    return compileSelfTailCallFromIR(self, call, dst, nargs);
                }
                if (self.resolveLocal(op_name) == null and (try self.resolveUpvalue(op_name)) == null) {
                    return compileSelfTailCallFromIR(self, call, dst, nargs);
                }
            }
        }
    }

    if (!is_tail and call.operator.tag == .global_ref) {
        const sym = call.operator.data.global_ref;
        if (types.isSymbol(sym)) {
            if (self.resolveLocal(types.symbolName(sym)) == null) {
                if ((try self.resolveUpvalue(types.symbolName(sym))) == null) {
                    const op_name = types.symbolName(sym);
                    const is_cont = types.isContinuationBarrier(op_name);
                    if (!is_cont) {
                        return compileCallGlobalFromIR(self, sym, call.args, dst, nargs, is_tail);
                    }
                }
            }
        }
    }

    const needs_rebase = (dst + 1 != self.next_register);
    const base = if (needs_rebase) try self.allocReg() else dst;

    try compileFromNode(self, call.operator, base, false);

    for (call.args) |arg| {
        const arg_reg = try self.allocReg();
        try compileFromNode(self, arg, arg_reg, false);
    }

    if (is_tail) {
        try self.emitOp(.tail_call);
    } else {
        try self.emitOp(.call);
    }
    try self.emitU16(base);
    try self.emit(nargs);

    var i: u8 = 0;
    while (i < nargs) : (i += 1) {
        self.freeReg();
    }

    if (needs_rebase) {
        try self.emitOp(.move);
        try self.emitU16(dst);
        try self.emitU16(base);
        self.freeReg();
    }
}

fn compileSelfTailCallFromIR(self: *Compiler, call: ir_mod.CallData, dst: u16, nargs: u8) CompileError!void {
    const needs_rebase = (dst + 1 != self.next_register);
    const base = if (needs_rebase) try self.allocReg() else dst;

    for (call.args) |arg| {
        const arg_reg = try self.allocReg();
        try compileFromNode(self, arg, arg_reg, false);
    }

    try self.emitOp(.self_tail_call);
    try self.emitU16(base);
    try self.emit(nargs);

    var i: u8 = 0;
    while (i < nargs) : (i += 1) {
        self.freeReg();
    }

    if (needs_rebase) {
        self.freeReg();
    }
}

fn compileCallGlobalFromIR(self: *Compiler, sym: Value, args: []const *ir_mod.Node, dst: u16, nargs: u8, is_tail: bool) CompileError!void {
    const sym_idx = try self.addConstant(sym);

    const needs_rebase = (dst + 1 != self.next_register);
    const base = if (needs_rebase) try self.allocReg() else blk: {
        if (self.next_register == dst) {
            _ = try self.allocReg();
        }
        break :blk dst;
    };

    for (args) |arg| {
        const arg_reg = try self.allocReg();
        try compileFromNode(self, arg, arg_reg, false);
    }

    if (is_tail) {
        try self.emitOp(.tail_call_global);
    } else {
        try self.emitOp(.call_global);
    }
    try self.emitU16(base);
    try self.emitU16(sym_idx);
    try self.emit(nargs);

    var i: u8 = 0;
    while (i < nargs) : (i += 1) {
        self.freeReg();
    }

    if (needs_rebase) {
        try self.emitOp(.move);
        try self.emitU16(dst);
        try self.emitU16(base);
        self.freeReg();
    }
}

pub fn compileLambdaWithIR(self: *Compiler, args: Value, dst: u16, name: ?[]const u8) CompileError!void {
    if (args == types.NIL) return CompileError.InvalidSyntax;
    const formals = types.car(args);
    const body = types.cdr(args);
    if (body == types.NIL) return CompileError.InvalidSyntax;

    var child = try Compiler.initChild(self);
    defer child.deinit();

    var arity: u8 = 0;
    var is_variadic = false;
    var param_list = formals;

    if (types.isSymbol(formals)) {
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

    const saved_body_scope = child.in_body_scope;
    child.in_body_scope = true;

    // Pre-scan globals for macro expansion visibility (R7RS 5.3.2).
    var prescan_names: std.ArrayList([]const u8) = .empty;
    defer prescan_names.deinit(child.gc.allocator);
    if (child.globals) |globals| {
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
                                    globals.put(dn, types.VOID) catch return CompileError.OutOfMemory;
                                    prescan_names.append(child.gc.allocator, dn) catch return CompileError.OutOfMemory;
                                }
                            }
                        }
                    } else if (std.mem.eql(u8, form_name, "define-record-type")) {
                        if (vm_records.parseRecordSpec(types.cdr(form))) |spec| {
                            if (!globals.contains(spec.ctor_name)) {
                                globals.put(spec.ctor_name, types.VOID) catch {};
                                prescan_names.append(child.gc.allocator, spec.ctor_name) catch {};
                            }
                            if (!globals.contains(spec.pred_name)) {
                                globals.put(spec.pred_name, types.VOID) catch {};
                                prescan_names.append(child.gc.allocator, spec.pred_name) catch {};
                            }
                            for (0..spec.field_count) |fi| {
                                if (!globals.contains(spec.accessor_names[fi])) {
                                    globals.put(spec.accessor_names[fi], types.VOID) catch {};
                                    prescan_names.append(child.gc.allocator, spec.accessor_names[fi]) catch {};
                                }
                                if (spec.mutator_names[fi]) |mn| {
                                    if (!globals.contains(mn)) {
                                        globals.put(mn, types.VOID) catch {};
                                        prescan_names.append(child.gc.allocator, mn) catch {};
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
        if (child.globals) |globals| {
            const glk = globals_mod.acquireGlobalsWrite(globals);
            for (prescan_names.items) |pn| {
                if (globals.get(pn)) |val| {
                    if (val == types.VOID) _ = globals.remove(pn);
                }
            }
            globals_mod.releaseGlobalsWrite(glk);
        }
    }

    // Collect leading internal defines for letrec* desugaring (R7RS 5.3.2).
    const MAX_BODY_DEFS = 512;
    var def_names: [MAX_BODY_DEFS][]const u8 = undefined;
    var def_inits: [MAX_BODY_DEFS]Value = undefined;
    var def_slots: [MAX_BODY_DEFS]u16 = undefined;
    var def_count: usize = 0;

    const roots_base = child.gc.extra_roots.items.len;
    defer child.gc.extra_roots.shrinkRetainingCapacity(roots_base);

    // First pass: collect ALL leading define names so that define-syntax
    // forms see the complete letrec* region via extra_bound.
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
                    const fn_nm = types.car(tgt);
                    if (types.isSymbol(fn_nm) and all_def_count < MAX_BODY_DEFS) {
                        all_def_names[all_def_count] = types.symbolName(fn_nm);
                        all_def_count += 1;
                    }
                } else break;
            } else if (std.mem.eql(u8, hn, "define-record-type")) {
                vm_records.collectRecordTypeDefNames(child.gc, types.cdr(expr), all_def_names[0..], &all_def_count) catch |err| switch (err) {
                    CompileError.InvalidSyntax => break,
                    else => return err,
                };
            } else if (!std.mem.eql(u8, hn, "define-syntax")) {
                break;
            }
            scan = types.cdr(scan);
        }
    }

    const macro_mark = child.beginBodyMacroScope();
    defer child.endBodyMacroScope(macro_mark) catch {};

    var current = body;
    while (current != types.NIL and types.isPair(current)) {
        const expr = types.car(current);
        if (!types.isPair(expr)) break;
        const head = types.car(expr);
        if (!types.isSymbol(head)) break;
        const head_name = types.symbolName(head);
        if (std.mem.eql(u8, head_name, "define-syntax")) {
            const ds_args = types.cdr(expr);
            if (ds_args == types.NIL or !types.isPair(ds_args)) break;
            const keyword = types.car(ds_args);
            if (!types.isSymbol(keyword)) break;
            const ds_rest = types.cdr(ds_args);
            if (ds_rest == types.NIL or !types.isPair(ds_rest)) break;
            const transformer_spec = types.car(ds_rest);
            const tx_val = macro.parseSyntaxRules(&child, transformer_spec, all_def_names[0..all_def_count]) catch break;
            // Root the transformer for the rest of this top-level compile:
            // it lives only in the compiler-local macro map, which the GC
            // cannot see, and it must survive collections triggered while
            // compiling sibling body forms that use it (#1401). Released by
            // the extra_roots truncation in compileExpression*.
            child.gc.extra_roots.append(child.gc.allocator, tx_val) catch return CompileError.OutOfMemory;
            const ds_name = types.symbolName(keyword);
            try child.recordBodyMacro(ds_name);
            const tx_obj = types.toObject(tx_val).as(types.Transformer);
            if (child.lib_env) |env| {
                tx_obj.def_env = env;
                tx_obj.def_env_val = child.lib_env_val;
            }
            try macro.captureLocalsOnTransformer(&child, tx_val);
            child.macros.put(ds_name, tx_val) catch return CompileError.OutOfMemory;
            current = types.cdr(current);
            continue;
        }
        if (std.mem.eql(u8, head_name, "define-record-type")) {
            vm_records.expandRecordTypeDefines(
                child.gc,
                types.cdr(expr),
                def_names[0..],
                def_inits[0..],
                &def_count,
                &child.gc.extra_roots,
            ) catch |err| switch (err) {
                CompileError.InvalidSyntax => break,
                else => return err,
            };
            current = types.cdr(current);
            continue;
        }
        if (!std.mem.eql(u8, head_name, "define")) break;

        const def_args = types.cdr(expr);
        if (def_args == types.NIL or !types.isPair(def_args)) break;
        const target = types.car(def_args);
        const def_rest = types.cdr(def_args);

        if (types.isSymbol(target)) {
            if (def_rest == types.NIL or !types.isPair(def_rest)) break;
            if (def_count >= MAX_BODY_DEFS) return CompileError.TooManyLocals;
            def_names[def_count] = types.symbolName(target);
            def_inits[def_count] = types.car(def_rest);
            def_count += 1;
        } else if (types.isPair(target)) {
            const fn_name = types.car(target);
            if (!types.isSymbol(fn_name)) break;
            if (def_count >= MAX_BODY_DEFS) return CompileError.TooManyLocals;
            def_names[def_count] = types.symbolName(fn_name);
            const param_formals = types.cdr(target);
            const lambda_sym = child.gc.allocSymbol("lambda") catch return CompileError.OutOfMemory;
            {
                var lambda_args = child.gc.allocPair(param_formals, def_rest) catch return CompileError.OutOfMemory;
                child.gc.pushRoot(&lambda_args);
                defer child.gc.popRoot();
                def_inits[def_count] = child.gc.allocPair(lambda_sym, lambda_args) catch return CompileError.OutOfMemory;
            }
            child.gc.extra_roots.append(child.gc.allocator, def_inits[def_count]) catch return CompileError.OutOfMemory;
            def_count += 1;
        } else {
            break;
        }
        current = types.cdr(current);
    }

    var last_dst: u16 = 0;

    if (def_count > 0) {
        child.beginScope();

        for (0..def_count) |i| {
            const slot = try child.allocReg();
            def_slots[i] = slot;
            try child.emitOp(.load_void);
            try child.emitU16(slot);
            try child.addLocal(def_names[i], slot);
            try child.markLocalBoxedBySlot(slot);
        }

        for (0..def_count) |i| {
            last_dst = try child.allocReg();

            var ir = ir_mod.IR.init(child.gc.allocator);
            ir.globals = child.globals;
            ir.restricted_env = child.restricted_env;
            ir.compiler = &child;
            ir.set_targets = child.set_targets;
            defer ir.deinit();
            const root = try ir_mod.lowerAndOptimize(&ir, def_inits[i], &child.macros, false);

            try compileFromNode(&child, root, last_dst, false);

            if (child.func.constants.items.len > 0) {
                const last_const = child.func.constants.items[child.func.constants.items.len - 1];
                if (types.isFunction(last_const)) {
                    const child_func = types.toObject(last_const).as(types.Function);
                    if (child_func.name == null) {
                        child_func.name = def_names[i];
                    }
                }
            }

            try child.emitOp(.set_box_local);
            try child.emitU16(def_slots[i]);
            try child.emitU16(last_dst);
            child.freeReg();
        }

        if (current == types.NIL) {
            last_dst = try child.allocReg();
            try child.emitOp(.load_void);
            try child.emitU16(last_dst);
        } else {
            while (current != types.NIL) {
                if (!types.isPair(current)) return CompileError.InvalidSyntax;
                const expr = types.car(current);
                const rest = types.cdr(current);
                last_dst = try child.allocReg();

                var ir = ir_mod.IR.init(child.gc.allocator);
                ir.globals = child.globals;
                ir.restricted_env = child.restricted_env;
                ir.compiler = &child;
                ir.set_targets = child.set_targets;
                defer ir.deinit();
                const root = try ir_mod.lowerAndOptimize(&ir, expr, &child.macros, rest == types.NIL);

                if (rest == types.NIL) {
                    try compileFromNode(&child, root, last_dst, true);
                } else {
                    const saved_next = child.next_register;
                    try compileFromNode(&child, root, last_dst, false);
                    if (child.next_register == saved_next) {
                        child.freeReg();
                    }
                }
                current = rest;
            }
        }

        child.endScope();
    } else {
        while (current != types.NIL) {
            if (!types.isPair(current)) return CompileError.InvalidSyntax;
            const expr = types.car(current);
            const rest = types.cdr(current);
            last_dst = try child.allocReg();

            var ir = ir_mod.IR.init(child.gc.allocator);
            ir.globals = child.globals;
            ir.restricted_env = child.restricted_env;
            ir.compiler = &child;
            ir.set_targets = child.set_targets;
            defer ir.deinit();
            const root = try ir_mod.lowerAndOptimize(&ir, expr, &child.macros, rest == types.NIL);

            if (rest == types.NIL) {
                try compileFromNode(&child, root, last_dst, true);
            } else {
                const saved_next = child.next_register;
                try compileFromNode(&child, root, last_dst, false);
                if (child.next_register == saved_next) {
                    child.freeReg();
                }
            }
            current = rest;
        }
    }

    child.in_body_scope = saved_body_scope;
    try child.emitOp(.@"return");
    try child.emitU16(last_dst);

    child.populateDebugLocals();
    try compiler_lambda.emitClosureEpilogue(self, &child, dst);
}

fn compileDefineFromIR(self: *Compiler, data: ir_mod.DefineData, dst: u16) CompileError!void {
    var ir = ir_mod.IR.init(self.gc.allocator);
    ir.globals = self.globals;
    ir.restricted_env = self.restricted_env;
    ir.compiler = self;
    ir.set_targets = self.set_targets;
    defer ir.deinit();
    const val_root = try ir_mod.lowerAndOptimize(&ir, data.value, &self.macros, false);

    if (val_root.tag == .lambda) {
        val_root.data.lambda.name = types.symbolName(data.name);
    }

    try compileFromNode(self, val_root, dst, false);

    if (self.func.constants.items.len > 0) {
        const last_const = self.func.constants.items[self.func.constants.items.len - 1];
        if (types.isFunction(last_const)) {
            const child_func = types.toObject(last_const).as(types.Function);
            if (child_func.name == null) {
                child_func.name = types.symbolName(data.name);
            }
        }
    }

    if (self.in_body_scope) {
        const slot = try self.allocReg();
        try self.emitOp(.move);
        try self.emitU16(slot);
        try self.emitU16(dst);
        self.locals.append(self.gc.allocator, .{
            .name = types.symbolName(data.name),
            .depth = self.scope_depth,
            .slot = slot,
            .binding_id = compiler_mod.freshBindingId(),
        }) catch return CompileError.OutOfMemory;
        try self.emitOp(.load_void);
        try self.emitU16(dst);
        return;
    }
    const sym_idx = try self.addConstant(data.name);
    try self.emitOp(.define_global);
    try self.emitU16(sym_idx);
    try self.emitU16(dst);
    try self.emitOp(.load_void);
    try self.emitU16(dst);
}

fn compileSetFromIR(self: *Compiler, data: ir_mod.SetData, dst: u16) CompileError!void {
    const name = types.symbolName(data.name);

    var ir = ir_mod.IR.init(self.gc.allocator);
    ir.globals = self.globals;
    ir.restricted_env = self.restricted_env;
    ir.compiler = self;
    ir.set_targets = self.set_targets;
    defer ir.deinit();
    const val_root = try ir_mod.lowerAndOptimize(&ir, data.value, &self.macros, false);
    try compileFromNode(self, val_root, dst, false);

    if (self.resolveLocal(name)) |slot| {
        if (self.isLocalGlobalAlias(name)) {
            const sym_idx = try self.addConstant(data.name);
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
        const sym_idx = try self.addConstant(data.name);
        try self.emitOp(.set_global);
        try self.emitU16(sym_idx);
        try self.emitU16(dst);
    }
    try self.emitOp(.load_void);
    try self.emitU16(dst);
}

fn compileAndFromIR(self: *Compiler, exprs: []const *ir_mod.Node, dst: u16, is_tail: bool) CompileError!void {
    if (exprs.len == 0) {
        try self.emitOp(.load_true);
        try self.emitU16(dst);
        return;
    }
    var end_jumps: std.ArrayList(usize) = .empty;
    defer end_jumps.deinit(self.gc.allocator);
    for (exprs, 0..) |expr, i| {
        if (i == exprs.len - 1) {
            try compileFromNode(self, expr, dst, is_tail);
        } else {
            try compileFromNode(self, expr, dst, false);
            try self.emitOp(.jump_false);
            try self.emitU16(dst);
            end_jumps.append(self.gc.allocator, self.currentOffset()) catch return CompileError.TooManyLocals;
            try self.emitI16(0);
        }
    }
    for (end_jumps.items) |j| {
        try self.patchJump(j);
    }
}

fn compileOrFromIR(self: *Compiler, exprs: []const *ir_mod.Node, dst: u16, is_tail: bool) CompileError!void {
    if (exprs.len == 0) {
        try self.emitOp(.load_false);
        try self.emitU16(dst);
        return;
    }
    var end_jumps: std.ArrayList(usize) = .empty;
    defer end_jumps.deinit(self.gc.allocator);
    for (exprs, 0..) |expr, i| {
        if (i == exprs.len - 1) {
            try compileFromNode(self, expr, dst, is_tail);
        } else {
            try compileFromNode(self, expr, dst, false);
            try self.emitOp(.jump_true);
            try self.emitU16(dst);
            end_jumps.append(self.gc.allocator, self.currentOffset()) catch return CompileError.TooManyLocals;
            try self.emitI16(0);
        }
    }
    for (end_jumps.items) |j| {
        try self.patchJump(j);
    }
}

fn compileWhenFromIR(self: *Compiler, data: ir_mod.CondBodyData, dst: u16, is_tail: bool) CompileError!void {
    try compileFromNode(self, data.test_expr, dst, false);
    try self.emitOp(.jump_false);
    try self.emitU16(dst);
    const false_jump = self.currentOffset();
    try self.emitI16(0);

    for (data.body, 0..) |expr, i| {
        const tail = is_tail and i == data.body.len - 1;
        try compileFromNode(self, expr, dst, tail);
    }

    try self.emitOp(.jump);
    const end_jump = self.currentOffset();
    try self.emitI16(0);
    try self.patchJump(false_jump);
    try self.emitOp(.load_void);
    try self.emitU16(dst);
    try self.patchJump(end_jump);
}

fn compileUnlessFromIR(self: *Compiler, data: ir_mod.CondBodyData, dst: u16, is_tail: bool) CompileError!void {
    try compileFromNode(self, data.test_expr, dst, false);
    try self.emitOp(.jump_true);
    try self.emitU16(dst);
    const true_jump = self.currentOffset();
    try self.emitI16(0);

    for (data.body, 0..) |expr, i| {
        const tail = is_tail and i == data.body.len - 1;
        try compileFromNode(self, expr, dst, tail);
    }

    try self.emitOp(.jump);
    const end_jump = self.currentOffset();
    try self.emitI16(0);
    try self.patchJump(true_jump);
    try self.emitOp(.load_void);
    try self.emitU16(dst);
    try self.patchJump(end_jump);
}
