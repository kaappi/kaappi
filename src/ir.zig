const std = @import("std");
const types = @import("types.zig");
const memory = @import("memory.zig");
const compiler_mod = @import("compiler.zig");
const globals_mod = @import("globals.zig");

const Value = types.Value;
const OpCode = types.OpCode;
pub const CompileError = compiler_mod.CompileError;

pub const NodeTag = enum {
    constant,
    global_ref,
    call,
    @"if",
    begin,
    and_form,
    or_form,
    when_form,
    unless_form,
    define,
    set_form,
    lambda,
    let_form,
    let_star,
    letrec,
    letrec_star,
    sexpr_form,
    passthrough,
};

pub const FormKind = enum {
    do_form,
    delay,
    delay_force,
    cond,
    case_form,
    case_lambda,
    guard,
    quasiquote,
    parameterize,
    define_values,
    let_values,
    let_star_values,
    define_syntax,
    named_let,
    let_syntax,
    letrec_syntax,
    cond_expand,

    pub fn keyword(self: FormKind) []const u8 {
        return switch (self) {
            .do_form => "do",
            .delay => "delay",
            .delay_force => "delay-force",
            .cond => "cond",
            .case_form => "case",
            .case_lambda => "case-lambda",
            .guard => "guard",
            .quasiquote => "quasiquote",
            .parameterize => "parameterize",
            .define_values => "define-values",
            .let_values => "let-values",
            .let_star_values => "let*-values",
            .define_syntax => "define-syntax",
            .named_let => "let",
            .let_syntax => "let-syntax",
            .letrec_syntax => "letrec-syntax",
            .cond_expand => "cond-expand",
        };
    }
};

pub const LLVMCapability = enum { native, eval_fallback };

pub const LLVMNodeEntry = struct {
    tag: NodeTag,
    capability: LLVMCapability,
    form_name: ?[]const u8 = null,
    include_in_name_set: bool = true,
};

pub const llvm_node_table: [18]LLVMNodeEntry = .{
    .{ .tag = .constant, .capability = .native },
    .{ .tag = .global_ref, .capability = .native },
    .{ .tag = .call, .capability = .native },
    .{ .tag = .@"if", .capability = .native },
    .{ .tag = .begin, .capability = .native },
    .{ .tag = .and_form, .capability = .native },
    .{ .tag = .or_form, .capability = .native },
    .{ .tag = .when_form, .capability = .native },
    .{ .tag = .unless_form, .capability = .native },
    .{ .tag = .define, .capability = .native },
    .{ .tag = .set_form, .capability = .native },
    .{ .tag = .lambda, .capability = .native },
    .{ .tag = .let_form, .capability = .native, .form_name = "let" },
    .{ .tag = .let_star, .capability = .native, .form_name = "let*" },
    .{ .tag = .letrec, .capability = .eval_fallback, .form_name = "letrec" },
    .{ .tag = .letrec_star, .capability = .eval_fallback, .form_name = "letrec*" },
    .{ .tag = .sexpr_form, .capability = .eval_fallback },
    .{ .tag = .passthrough, .capability = .native },
};

const eval_fallback_name_count = countEvalFallbackNames();

fn countEvalFallbackNames() usize {
    var count: usize = 0;
    for (llvm_node_table) |entry| {
        if (entry.capability == .eval_fallback and entry.include_in_name_set and entry.form_name != null)
            count += 1;
    }
    const form_fields = @typeInfo(FormKind).@"enum".fields;
    for (form_fields) |f| {
        const fk: FormKind = @enumFromInt(f.value);
        if (fk == .named_let) continue;
        count += 1;
    }
    return count;
}

pub const eval_fallback_form_names: [eval_fallback_name_count][]const u8 = blk: {
    var names: [eval_fallback_name_count][]const u8 = undefined;
    var i: usize = 0;
    for (llvm_node_table) |entry| {
        if (entry.capability == .eval_fallback and entry.include_in_name_set) {
            if (entry.form_name) |name| {
                names[i] = name;
                i += 1;
            }
        }
    }
    const form_fields = @typeInfo(FormKind).@"enum".fields;
    for (form_fields) |f| {
        const fk: FormKind = @enumFromInt(f.value);
        if (fk == .named_let) continue;
        names[i] = fk.keyword();
        i += 1;
    }
    break :blk names;
};

pub fn llvmCapability(tag: NodeTag) LLVMCapability {
    for (llvm_node_table) |entry| {
        if (entry.tag == tag) return entry.capability;
    }
    unreachable;
}

pub fn llvmFormName(tag: NodeTag) ?[]const u8 {
    for (llvm_node_table) |entry| {
        if (entry.tag == tag) return entry.form_name;
    }
    return null;
}

comptime {
    const fields = @typeInfo(NodeTag).@"enum".fields;
    if (llvm_node_table.len != fields.len)
        @compileError("llvm_node_table must have exactly one entry per NodeTag");
    var seen: [fields.len]bool = .{false} ** fields.len;
    for (llvm_node_table) |entry| {
        const idx = @intFromEnum(entry.tag);
        if (seen[idx])
            @compileError("duplicate tag in llvm_node_table");
        seen[idx] = true;
    }
    for (seen) |s| {
        if (!s) @compileError("missing tag in llvm_node_table");
    }
}

pub const Annotations = struct {
    is_tail: bool = false,
    source_line: u32 = 0,
};

pub const Node = struct {
    tag: NodeTag,
    data: Data,
    ann: Annotations = .{},

    const Data = union {
        constant: Value,
        global_ref: Value,
        call: CallData,
        @"if": IfData,
        begin: []const *Node,
        and_form: []const *Node,
        or_form: []const *Node,
        when_form: CondBodyData,
        unless_form: CondBodyData,
        define: DefineData,
        set_form: SetData,
        lambda: LambdaData,
        let_form: LetData,
        let_star: LetData,
        letrec: LetData,
        letrec_star: LetData,
        sexpr_form: SexprFormData,
        passthrough: Value,
    };
};

pub const DefineData = struct {
    name: Value,
    value: Value,
};

pub const SetData = struct {
    name: Value,
    value: Value,
};

pub const LambdaData = struct {
    args: Value,
    name: ?[]const u8,
};

pub const LetData = struct {
    args: Value,
};

pub const SexprFormData = struct {
    form: FormKind,
    args: Value,
};

pub const CondBodyData = struct {
    test_expr: *Node,
    body: []const *Node,
};

pub const CallData = struct {
    operator: *Node,
    args: []const *Node,
};

pub const IfData = struct {
    test_expr: *Node,
    consequent: *Node,
    alternate: ?*Node,
};

pub const IR = struct {
    allocator: std.mem.Allocator,
    nodes: std.ArrayList(*Node),
    globals: ?*const std.StringHashMap(Value) = null,
    restricted_env: bool = false, // true when compiling in a restricted environment (environment procedure)
    // Enclosing compiler, when lowering happens inside one. Supplies lexical
    // scope so lowering can honor R7RS shadowing: a local or captured binding
    // of a keyword (if, begin, +, ...) shadows the syntax/primitive, so the
    // form must lower to an ordinary call rather than a special form or a fold
    // (issues #788, #790). Null for standalone lowering, where only the
    // globals check applies.
    compiler: ?*const compiler_mod.Compiler = null,
    // Extra lexically-bound names that shadow primitives, for lowering paths
    // that have no Compiler (the LLVM native backend passes a lambda's own
    // parameter names here). Also consulted by isRedefined (issue #790).
    bound_names: ?[]const []const u8 = null,
    // Names that are the target of a `set!` somewhere in the enclosing form
    // being compiled. Folding a call to such a name is unsound: the `set!`
    // may run before the call (e.g. `(lambda () (set! + -) (+ 5 2))`), so the
    // primitive's value at compile time no longer reflects its value at the
    // call site. Populated conservatively (whole-form scan) by the compiler.
    set_targets: ?*const std.StringHashMap(void) = null,

    pub fn init(allocator: std.mem.Allocator) IR {
        return .{
            .allocator = allocator,
            .nodes = .empty,
        };
    }

    fn isRedefined(self: *const IR, name: []const u8) bool {
        // A lexical binding (lambda parameter or enclosing local) shadowing the
        // primitive makes any fold that assumes the built-in's semantics wrong.
        // The globals map never sees these, so consult the compiler's scope.
        if (self.compiler) |c| {
            if (c.isLexicallyBound(name)) return true;
        }
        if (self.bound_names) |names| {
            for (names) |n| {
                if (std.mem.eql(u8, n, name)) return true;
            }
        }
        // A `set!` target in the enclosing form suppresses folding even when
        // the global still holds the original primitive at compile time.
        if (self.set_targets) |st| {
            if (st.contains(name)) return true;
        }
        const g = self.globals orelse return false;
        const glk = globals_mod.acquireGlobalsRead(g);
        defer globals_mod.releaseGlobalsRead(glk);
        const val = g.get(name) orelse {
            // In a restricted environment, missing names mean "not available".
            // Return true so the IR does not inline the primitive; the VM
            // will raise "undefined variable" at runtime.
            return self.restricted_env;
        };
        if (!types.isPointer(val)) return true;
        const obj = types.toObject(val);
        if (obj.tag != .native_fn) return true;
        const nfn = obj.as(types.NativeFn);
        return !std.mem.eql(u8, nfn.name, name);
    }

    pub fn deinit(self: *IR) void {
        for (self.nodes.items) |node| {
            self.freeNode(node);
        }
        self.nodes.deinit(self.allocator);
    }

    fn freeNode(self: *IR, node: *Node) void {
        switch (node.tag) {
            .call => self.allocator.free(node.data.call.args),
            .begin => self.allocator.free(node.data.begin),
            .and_form => self.allocator.free(node.data.and_form),
            .or_form => self.allocator.free(node.data.or_form),
            .when_form => self.allocator.free(node.data.when_form.body),
            .unless_form => self.allocator.free(node.data.unless_form.body),
            else => {},
        }
        self.allocator.destroy(node);
    }

    fn allocNode(self: *IR, tag: NodeTag, data: Node.Data) CompileError!*Node {
        const node = self.allocator.create(Node) catch return CompileError.OutOfMemory;
        node.* = .{ .tag = tag, .data = data };
        self.nodes.append(self.allocator, node) catch return CompileError.OutOfMemory;
        return node;
    }

    pub fn makeConst(self: *IR, value: Value) CompileError!*Node {
        return self.allocNode(.constant, .{ .constant = value });
    }

    pub fn makeGlobalRef(self: *IR, sym: Value) CompileError!*Node {
        return self.allocNode(.global_ref, .{ .global_ref = sym });
    }

    pub fn makeCall(self: *IR, operator: *Node, args: []const *Node) CompileError!*Node {
        const args_copy = self.allocator.alloc(*Node, args.len) catch return CompileError.OutOfMemory;
        @memcpy(args_copy, args);
        return self.allocNode(.call, .{ .call = .{ .operator = operator, .args = args_copy } });
    }

    pub fn makeIf(self: *IR, test_expr: *Node, consequent: *Node, alternate: ?*Node) CompileError!*Node {
        return self.allocNode(.@"if", .{ .@"if" = .{ .test_expr = test_expr, .consequent = consequent, .alternate = alternate } });
    }

    pub fn makeBegin(self: *IR, exprs: []const *Node) CompileError!*Node {
        const copy = self.allocator.alloc(*Node, exprs.len) catch return CompileError.OutOfMemory;
        @memcpy(copy, exprs);
        return self.allocNode(.begin, .{ .begin = copy });
    }

    pub fn makeAnd(self: *IR, exprs: []const *Node) CompileError!*Node {
        const copy = self.allocator.alloc(*Node, exprs.len) catch return CompileError.OutOfMemory;
        @memcpy(copy, exprs);
        return self.allocNode(.and_form, .{ .and_form = copy });
    }

    pub fn makeOr(self: *IR, exprs: []const *Node) CompileError!*Node {
        const copy = self.allocator.alloc(*Node, exprs.len) catch return CompileError.OutOfMemory;
        @memcpy(copy, exprs);
        return self.allocNode(.or_form, .{ .or_form = copy });
    }

    pub fn makeWhen(self: *IR, test_expr: *Node, body: []const *Node) CompileError!*Node {
        const copy = self.allocator.alloc(*Node, body.len) catch return CompileError.OutOfMemory;
        @memcpy(copy, body);
        return self.allocNode(.when_form, .{ .when_form = .{ .test_expr = test_expr, .body = copy } });
    }

    pub fn makeUnless(self: *IR, test_expr: *Node, body: []const *Node) CompileError!*Node {
        const copy = self.allocator.alloc(*Node, body.len) catch return CompileError.OutOfMemory;
        @memcpy(copy, body);
        return self.allocNode(.unless_form, .{ .unless_form = .{ .test_expr = test_expr, .body = copy } });
    }

    pub fn makeLambda(self: *IR, args: Value, name: ?[]const u8) CompileError!*Node {
        return self.allocNode(.lambda, .{ .lambda = .{ .args = args, .name = name } });
    }

    pub fn makeLet(self: *IR, args: Value) CompileError!*Node {
        return self.allocNode(.let_form, .{ .let_form = .{ .args = args } });
    }

    pub fn makeLetStar(self: *IR, args: Value) CompileError!*Node {
        return self.allocNode(.let_star, .{ .let_star = .{ .args = args } });
    }

    pub fn makeLetrec(self: *IR, args: Value) CompileError!*Node {
        return self.allocNode(.letrec, .{ .letrec = .{ .args = args } });
    }

    pub fn makeLetrecStar(self: *IR, args: Value) CompileError!*Node {
        return self.allocNode(.letrec_star, .{ .letrec_star = .{ .args = args } });
    }

    pub fn makeSexprNode(self: *IR, form: FormKind, args: Value) CompileError!*Node {
        return self.allocNode(.sexpr_form, .{ .sexpr_form = .{ .form = form, .args = args } });
    }

    pub fn makeDefine(self: *IR, name: Value, value: Value) CompileError!*Node {
        return self.allocNode(.define, .{ .define = .{ .name = name, .value = value } });
    }

    pub fn makeSet(self: *IR, name: Value, value: Value) CompileError!*Node {
        return self.allocNode(.set_form, .{ .set_form = .{ .name = name, .value = value } });
    }

    pub fn makePassthrough(self: *IR, expr: Value) CompileError!*Node {
        return self.allocNode(.passthrough, .{ .passthrough = expr });
    }
};

// ---------------------------------------------------------------------------
// AST (S-expression) → IR lowering
// ---------------------------------------------------------------------------

pub const sexpr_form_map = std.StaticStringMap(FormKind).initComptime(.{
    .{ "cond", .cond },
    .{ "case", .case_form },
    .{ "case-lambda", .case_lambda },
    .{ "do", .do_form },
    .{ "guard", .guard },
    .{ "delay", .delay },
    .{ "delay-force", .delay_force },
    .{ "quasiquote", .quasiquote },
    .{ "parameterize", .parameterize },
    .{ "define-values", .define_values },
    .{ "let-values", .let_values },
    .{ "let*-values", .let_star_values },
    .{ "define-syntax", .define_syntax },
    .{ "let-syntax", .let_syntax },
    .{ "letrec-syntax", .letrec_syntax },
    .{ "cond-expand", .cond_expand },
});

const other_special_forms = std.StaticStringMap(void).initComptime(.{
    .{ "quote", {} },
    .{ "if", {} },
    .{ "lambda", {} },
    .{ "define", {} },
    .{ "set!", {} },
    .{ "begin", {} },
    .{ "and", {} },
    .{ "or", {} },
    .{ "when", {} },
    .{ "unless", {} },
    .{ "let", {} },
    .{ "let*", {} },
    .{ "letrec", {} },
    .{ "letrec*", {} },
    .{ "syntax-error", {} },
    .{ "syntax-rules", {} },
    .{ "apply", {} },
    .{ "call-with-values", {} },
    .{ "call-with-current-continuation", {} },
    .{ "call/cc", {} },
    .{ "eval", {} },
    .{ "define-record-type", {} },
    .{ "import", {} },
    .{ "define-library", {} },
    .{ "include", {} },
    .{ "include-ci", {} },
});

pub fn isSpecialForm(name: []const u8) bool {
    return sexpr_form_map.get(name) != null or other_special_forms.get(name) != null;
}

pub fn lowerWithMacros(ir: *IR, expr: Value, macros: ?*std.StringHashMap(Value)) CompileError!*Node {
    if (types.isFixnum(expr) or types.isFlonum(expr) or types.isBignum(expr) or
        types.isComplex(expr) or types.isRationalObj(expr) or types.isString(expr) or
        types.isChar(expr) or types.isVector(expr) or types.isBytevector(expr))
    {
        return ir.makeConst(expr);
    }

    if (expr == types.TRUE or expr == types.FALSE or expr == types.NIL) {
        return ir.makeConst(expr);
    }

    if (types.isSymbol(expr)) {
        return ir.makeGlobalRef(expr);
    }

    if (types.isPair(expr)) {
        const node = try lowerFormWithMacros(ir, expr, macros);
        if (ir.compiler) |c| {
            if (c.gc.source_lines.get(expr)) |line| {
                node.ann.source_line = line;
            }
        }
        return node;
    }

    return CompileError.InvalidSyntax;
}

fn lowerFormWithMacros(ir: *IR, expr: Value, macros: ?*std.StringHashMap(Value)) CompileError!*Node {
    const head = types.car(expr);

    if (types.isSymbol(head)) {
        const name = types.symbolName(head);

        const effective_name = types.stripHygienicPrefix(name);

        // R7RS has no reserved words: a lexical binding of a keyword shadows
        // the syntax. If the (non-hygienic) head names a local or captured
        // binding in the enclosing compiler scope, treat the form as an
        // ordinary procedure call instead of a special form or macro use.
        // Mirrors the `is_shadowed` guard in the legacy compileForm path.
        // A hygienic rename (effective_name != name) is never shadowed: it
        // came from a macro template and must keep its special-form meaning.
        const is_shadowed = std.mem.eql(u8, effective_name, name) and
            if (ir.compiler) |c| c.isLexicallyBound(name) else false;

        if (!is_shadowed) {
            if (std.mem.eql(u8, effective_name, "if")) return lowerIf(ir, types.cdr(expr), macros);
            if (std.mem.eql(u8, effective_name, "quote")) return lowerQuote(ir, types.cdr(expr));
            if (std.mem.eql(u8, effective_name, "begin")) return lowerBegin(ir, types.cdr(expr), macros);
            if (std.mem.eql(u8, effective_name, "lambda")) return ir.makeLambda(types.cdr(expr), null);
            if (std.mem.eql(u8, effective_name, "let")) return lowerLet(ir, expr);
            if (std.mem.eql(u8, effective_name, "let*")) return ir.makeLetStar(types.cdr(expr));
            if (std.mem.eql(u8, effective_name, "letrec")) return ir.makeLetrec(types.cdr(expr));
            if (std.mem.eql(u8, effective_name, "letrec*")) return ir.makeLetrecStar(types.cdr(expr));
            if (std.mem.eql(u8, effective_name, "define")) return lowerDefine(ir, expr);
            if (std.mem.eql(u8, effective_name, "set!")) return lowerSet(ir, types.cdr(expr));
            if (std.mem.eql(u8, effective_name, "and")) return lowerList(ir, types.cdr(expr), .and_form, macros);
            if (std.mem.eql(u8, effective_name, "or")) return lowerList(ir, types.cdr(expr), .or_form, macros);
            if (std.mem.eql(u8, effective_name, "when")) return lowerCondBody(ir, types.cdr(expr), .when_form, macros);
            if (std.mem.eql(u8, effective_name, "unless")) return lowerCondBody(ir, types.cdr(expr), .unless_form, macros);

            if (sexpr_form_map.get(effective_name)) |form|
                return ir.makeSexprNode(form, types.cdr(expr));

            if (isSpecialForm(effective_name)) return ir.makePassthrough(expr);

            if (ir.compiler) |c| {
                if (c.lookupMacro(name) != null) return ir.makePassthrough(expr);
            } else if (macros) |m| {
                if (m.get(name) != null) return ir.makePassthrough(expr);
            }
        }

        if (tryFoldFromAST(ir, expr)) |folded| return folded;
        return lowerCall(ir, expr, macros);
    }

    if (tryFoldFromAST(ir, expr)) |folded| return folded;
    return lowerCall(ir, expr, macros);
}

pub fn lower(irn: *IR, expr: Value) CompileError!*Node {
    return lowerWithMacros(irn, expr, null);
}

pub fn lowerAndOptimize(
    ir_instance: *IR,
    expr: Value,
    macros: ?*std.StringHashMap(Value),
    is_tail: bool,
) CompileError!*Node {
    var node = try lowerWithMacros(ir_instance, expr, macros);
    markTailPositions(node, is_tail);
    node = foldConstants(ir_instance, node);
    node = eliminateDeadBranches(ir_instance, node);
    node = simplifyBooleans(ir_instance, node);
    node = eliminateIdentity(ir_instance, node);
    node = simplifyBegin(ir_instance, node);
    return node;
}

pub fn lowerSingleExpr(allocator: std.mem.Allocator, expr: Value) CompileError!*Node {
    return lowerSingleExprTail(allocator, expr, false);
}

pub fn lowerSingleExprTail(allocator: std.mem.Allocator, expr: Value, is_tail: bool) CompileError!*Node {
    var scratch = IR.init(allocator);
    return lowerAndOptimize(&scratch, expr, null, is_tail);
}

fn lowerIf(ir: *IR, args: Value, macros: ?*std.StringHashMap(Value)) CompileError!*Node {
    if (args == types.NIL) return CompileError.InvalidSyntax;
    const test_expr = types.car(args);
    const rest = types.cdr(args);
    if (rest == types.NIL) return CompileError.InvalidSyntax;
    const consequent = types.car(rest);
    const rest2 = types.cdr(rest);

    const test_node = try lowerWithMacros(ir, test_expr, macros);
    const cons_node = try lowerWithMacros(ir, consequent, macros);
    const alt_node: ?*Node = if (rest2 != types.NIL)
        try lowerWithMacros(ir, types.car(rest2), macros)
    else
        null;

    return ir.makeIf(test_node, cons_node, alt_node);
}

fn lowerQuote(ir: *IR, args: Value) CompileError!*Node {
    if (args == types.NIL) return CompileError.InvalidSyntax;
    return ir.makeConst(types.car(args));
}

fn lowerBegin(ir: *IR, args: Value, macros: ?*std.StringHashMap(Value)) CompileError!*Node {
    var nodes: std.ArrayList(*Node) = .empty;
    defer nodes.deinit(ir.allocator);
    var current = args;
    while (current != types.NIL) {
        if (!types.isPair(current)) return CompileError.InvalidSyntax;
        nodes.append(ir.allocator, try lowerWithMacros(ir, types.car(current), macros)) catch return CompileError.OutOfMemory;
        current = types.cdr(current);
    }
    return ir.makeBegin(nodes.items);
}

fn lowerLet(ir: *IR, expr: Value) CompileError!*Node {
    const args = types.cdr(expr);
    if (args == types.NIL) return CompileError.InvalidSyntax;
    const first = types.car(args);
    if (types.isSymbol(first)) return ir.makeSexprNode(FormKind.named_let, args);
    return ir.makeLet(args);
}

fn lowerDefine(ir: *IR, expr: Value) CompileError!*Node {
    const args = types.cdr(expr);
    if (args == types.NIL) return CompileError.InvalidSyntax;
    const target = types.car(args);
    if (types.isPair(target)) return ir.makePassthrough(expr);
    if (!types.isSymbol(target)) return CompileError.InvalidSyntax;
    const rest = types.cdr(args);
    if (rest == types.NIL) return CompileError.InvalidSyntax;
    return ir.makeDefine(target, types.car(rest));
}

fn lowerSet(ir: *IR, args: Value) CompileError!*Node {
    if (args == types.NIL) return CompileError.InvalidSyntax;
    const name = types.car(args);
    if (!types.isSymbol(name)) return CompileError.InvalidSyntax;
    const rest = types.cdr(args);
    if (rest == types.NIL) return CompileError.InvalidSyntax;
    return ir.makeSet(name, types.car(rest));
}

fn lowerList(ir: *IR, args: Value, tag: NodeTag, macros: ?*std.StringHashMap(Value)) CompileError!*Node {
    var nodes: std.ArrayList(*Node) = .empty;
    defer nodes.deinit(ir.allocator);
    var current = args;
    while (current != types.NIL) {
        if (!types.isPair(current)) return CompileError.InvalidSyntax;
        nodes.append(ir.allocator, try lowerWithMacros(ir, types.car(current), macros)) catch return CompileError.OutOfMemory;
        current = types.cdr(current);
    }
    return switch (tag) {
        .and_form => ir.makeAnd(nodes.items),
        .or_form => ir.makeOr(nodes.items),
        else => ir.makeBegin(nodes.items),
    };
}

fn lowerCondBody(ir: *IR, args: Value, tag: NodeTag, macros: ?*std.StringHashMap(Value)) CompileError!*Node {
    if (args == types.NIL) return CompileError.InvalidSyntax;
    const test_expr = try lowerWithMacros(ir, types.car(args), macros);

    var nodes: std.ArrayList(*Node) = .empty;
    defer nodes.deinit(ir.allocator);
    var current = types.cdr(args);
    while (current != types.NIL) {
        if (!types.isPair(current)) return CompileError.InvalidSyntax;
        nodes.append(ir.allocator, try lowerWithMacros(ir, types.car(current), macros)) catch return CompileError.OutOfMemory;
        current = types.cdr(current);
    }
    return switch (tag) {
        .when_form => ir.makeWhen(test_expr, nodes.items),
        .unless_form => ir.makeUnless(test_expr, nodes.items),
        else => unreachable,
    };
}

fn lowerCall(ir: *IR, expr: Value, macros: ?*std.StringHashMap(Value)) CompileError!*Node {
    if (tryFoldFromAST(ir, expr)) |folded| return folded;

    const operator = types.car(expr);
    const op_node = try lowerWithMacros(ir, operator, macros);

    var arg_buf: [256]*Node = undefined;
    var nargs: usize = 0;
    var arg_list = types.cdr(expr);
    while (arg_list != types.NIL) {
        if (!types.isPair(arg_list)) return CompileError.InvalidSyntax;
        if (nargs >= 256) return CompileError.InternalLimit;
        arg_buf[nargs] = try lowerWithMacros(ir, types.car(arg_list), macros);
        nargs += 1;
        arg_list = types.cdr(arg_list);
    }

    return ir.makeCall(op_node, arg_buf[0..nargs]);
}

fn tryFoldFromAST(ir: *IR, expr: Value) ?*Node {
    const operator = types.car(expr);
    if (!types.isSymbol(operator)) return null;
    const name = types.symbolName(operator);
    if (ir.isRedefined(name)) return null;

    const args_pair = types.cdr(expr);
    if (!types.isPair(args_pair)) return null;
    const a = types.car(args_pair);
    const rest = types.cdr(args_pair);

    if (rest == types.NIL) {
        if (!types.isFixnum(a) and a != types.TRUE and a != types.FALSE) return null;

        const result: ?Value = if (std.mem.eql(u8, name, "not"))
            (if (a == types.FALSE) types.TRUE else types.FALSE)
        else if (std.mem.eql(u8, name, "zero?") and types.isFixnum(a))
            (if (types.toFixnum(a) == 0) types.TRUE else types.FALSE)
        else if (std.mem.eql(u8, name, "-") and types.isFixnum(a)) blk: {
            const neg = @subWithOverflow(@as(i64, 0), types.toFixnum(a));
            if (neg[1] != 0) break :blk null;
            if (neg[0] < std.math.minInt(i48) or neg[0] > std.math.maxInt(i48)) break :blk null;
            break :blk types.makeFixnum(neg[0]);
        } else null;

        if (result) |val| return ir.makeConst(val) catch null;
        return null;
    }

    if (!types.isPair(rest)) return null;
    const b = types.car(rest);
    if (types.cdr(rest) != types.NIL) return null;

    if (!types.isFixnum(a) or !types.isFixnum(b)) return null;
    const va = types.toFixnum(a);
    const vb = types.toFixnum(b);

    const result: ?Value =
        if (std.mem.eql(u8, name, "+")) blk: {
            const r = @addWithOverflow(va, vb);
            if (r[1] != 0) break :blk null;
            if (r[0] < std.math.minInt(i48) or r[0] > std.math.maxInt(i48)) break :blk null;
            break :blk types.makeFixnum(r[0]);
        } else if (std.mem.eql(u8, name, "-")) blk: {
            const r = @subWithOverflow(va, vb);
            if (r[1] != 0) break :blk null;
            if (r[0] < std.math.minInt(i48) or r[0] > std.math.maxInt(i48)) break :blk null;
            break :blk types.makeFixnum(r[0]);
        } else if (std.mem.eql(u8, name, "*")) blk: {
            const r = @mulWithOverflow(va, vb);
            if (r[1] != 0) break :blk null;
            if (r[0] < std.math.minInt(i48) or r[0] > std.math.maxInt(i48)) break :blk null;
            break :blk types.makeFixnum(r[0]);
        } else if (std.mem.eql(u8, name, "<"))
            (if (va < vb) types.TRUE else types.FALSE)
        else if (std.mem.eql(u8, name, ">"))
            (if (va > vb) types.TRUE else types.FALSE)
        else if (std.mem.eql(u8, name, "<="))
            (if (va <= vb) types.TRUE else types.FALSE)
        else if (std.mem.eql(u8, name, ">="))
            (if (va >= vb) types.TRUE else types.FALSE)
        else if (std.mem.eql(u8, name, "="))
            (if (va == vb) types.TRUE else types.FALSE)
        else
            null;

    if (result) |val| return ir.makeConst(val) catch null;
    return null;
}

// ---------------------------------------------------------------------------
// Semantic analysis: tail-position marking
// ---------------------------------------------------------------------------

pub fn markTailPositions(node: *Node, is_tail: bool) void {
    node.ann.is_tail = is_tail;
    switch (node.tag) {
        .@"if" => {
            markTailPositions(node.data.@"if".test_expr, false);
            markTailPositions(node.data.@"if".consequent, is_tail);
            if (node.data.@"if".alternate) |alt| markTailPositions(alt, is_tail);
        },
        .begin => {
            for (node.data.begin, 0..) |expr, i| {
                markTailPositions(expr, is_tail and i == node.data.begin.len - 1);
            }
        },
        .and_form => {
            for (node.data.and_form, 0..) |expr, i| {
                markTailPositions(expr, is_tail and i == node.data.and_form.len - 1);
            }
        },
        .or_form => {
            for (node.data.or_form, 0..) |expr, i| {
                markTailPositions(expr, is_tail and i == node.data.or_form.len - 1);
            }
        },
        .when_form => {
            markTailPositions(node.data.when_form.test_expr, false);
            for (node.data.when_form.body, 0..) |expr, i| {
                markTailPositions(expr, is_tail and i == node.data.when_form.body.len - 1);
            }
        },
        .unless_form => {
            markTailPositions(node.data.unless_form.test_expr, false);
            for (node.data.unless_form.body, 0..) |expr, i| {
                markTailPositions(expr, is_tail and i == node.data.unless_form.body.len - 1);
            }
        },
        .call => {
            markTailPositions(node.data.call.operator, false);
            for (node.data.call.args) |arg| markTailPositions(arg, false);
        },
        else => {},
    }
}

// ---------------------------------------------------------------------------
// Semantic analysis: primitive identification
// ---------------------------------------------------------------------------

pub fn isKnownGlobal(name: []const u8) bool {
    for (primitives) |p| {
        if (std.mem.eql(u8, name, p)) return true;
    }
    return isSpecialForm(name);
}

const primitives = [_][]const u8{
    "+",              "-",                 "*",            "/",                             "=",                "<",               ">",
    "<=",             ">=",                "zero?",        "not",                           "null?",            "pair?",           "car",
    "cdr",            "cons",              "list",         "length",                        "append",           "map",             "apply",
    "values",         "vector-ref",        "vector-set!",  "vector-length",                 "string-ref",       "string-length",   "char->integer",
    "integer->char",  "number?",           "string?",      "symbol?",                       "boolean?",         "char?",           "vector?",
    "procedure?",     "eq?",               "eqv?",         "equal?",                        "abs",              "max",             "min",
    "remainder",      "modulo",            "quotient",     "expt",                          "sqrt",             "number->string",  "string->number",
    "exact->inexact", "inexact->exact",    "floor",        "ceiling",                       "truncate",         "round",           "string-append",
    "substring",      "string-copy",       "string->list", "list->string",                  "make-string",      "make-vector",     "vector",
    "display",        "write",             "newline",      "read",                          "even?",            "odd?",            "positive?",
    "negative?",      "exact?",            "inexact?",     "integer?",                      "rational?",        "real?",           "complex?",
    "gcd",            "lcm",               "call/ec",      "call-with-escape-continuation", "call-with-values", "dynamic-wind",    "with-exception-handler",
    "raise",          "raise-continuable", "error",        "for-each",                      "string-for-each",  "vector-for-each", "vector-map",
    "string-map",     "assoc",             "assq",         "assv",                          "member",           "memq",            "memv",
};

// ---------------------------------------------------------------------------
// Optimization: constant folding on the IR
// ---------------------------------------------------------------------------

pub fn foldConstants(ir: *IR, node: *Node) *Node {
    switch (node.tag) {
        .call => {
            const call = node.data.call;
            if (call.operator.tag != .global_ref) return node;
            const sym = call.operator.data.global_ref;
            if (!types.isSymbol(sym)) return node;
            const name = types.symbolName(sym);
            if (ir.isRedefined(name)) return node;

            if (call.args.len == 1) {
                const a = call.args[0];
                if (a.tag != .constant) return node;
                const av = a.data.constant;
                if (!types.isFixnum(av) and av != types.TRUE and av != types.FALSE) return node;

                const result: ?Value = if (std.mem.eql(u8, name, "not"))
                    (if (av == types.FALSE) types.TRUE else types.FALSE)
                else if (std.mem.eql(u8, name, "zero?") and types.isFixnum(av))
                    (if (types.toFixnum(av) == 0) types.TRUE else types.FALSE)
                else if (std.mem.eql(u8, name, "-") and types.isFixnum(av)) blk: {
                    const neg = @subWithOverflow(@as(i64, 0), types.toFixnum(av));
                    if (neg[1] != 0) break :blk null;
                    if (neg[0] < std.math.minInt(i48) or neg[0] > std.math.maxInt(i48)) break :blk null;
                    break :blk types.makeFixnum(neg[0]);
                } else null;

                if (result) |val| return ir.makeConst(val) catch return node;
            }

            if (call.args.len == 2) {
                const a = call.args[0];
                const b = call.args[1];
                if (a.tag != .constant or b.tag != .constant) return node;
                const av = a.data.constant;
                const bv = b.data.constant;
                if (!types.isFixnum(av) or !types.isFixnum(bv)) return node;
                const va = types.toFixnum(av);
                const vb = types.toFixnum(bv);

                const result: ?Value = if (std.mem.eql(u8, name, "+")) blk: {
                    const r = @addWithOverflow(va, vb);
                    if (r[1] != 0) break :blk null;
                    if (r[0] < std.math.minInt(i48) or r[0] > std.math.maxInt(i48)) break :blk null;
                    break :blk types.makeFixnum(r[0]);
                } else if (std.mem.eql(u8, name, "-")) blk: {
                    const r = @subWithOverflow(va, vb);
                    if (r[1] != 0) break :blk null;
                    if (r[0] < std.math.minInt(i48) or r[0] > std.math.maxInt(i48)) break :blk null;
                    break :blk types.makeFixnum(r[0]);
                } else if (std.mem.eql(u8, name, "*")) blk: {
                    const r = @mulWithOverflow(va, vb);
                    if (r[1] != 0) break :blk null;
                    if (r[0] < std.math.minInt(i48) or r[0] > std.math.maxInt(i48)) break :blk null;
                    break :blk types.makeFixnum(r[0]);
                } else if (std.mem.eql(u8, name, "<"))
                    (if (va < vb) types.TRUE else types.FALSE)
                else if (std.mem.eql(u8, name, ">"))
                    (if (va > vb) types.TRUE else types.FALSE)
                else if (std.mem.eql(u8, name, "<="))
                    (if (va <= vb) types.TRUE else types.FALSE)
                else if (std.mem.eql(u8, name, ">="))
                    (if (va >= vb) types.TRUE else types.FALSE)
                else if (std.mem.eql(u8, name, "="))
                    (if (va == vb) types.TRUE else types.FALSE)
                else
                    null;

                if (result) |val| return ir.makeConst(val) catch return node;
            }
            return node;
        },
        .@"if" => {
            const data = node.data.@"if";
            const new_test = foldConstants(ir, data.test_expr);
            const new_cons = foldConstants(ir, data.consequent);
            const new_alt = if (data.alternate) |alt| foldConstants(ir, alt) else null;
            if (new_test != data.test_expr or new_cons != data.consequent or
                (data.alternate != null and new_alt != data.alternate.?))
            {
                return ir.makeIf(new_test, new_cons, new_alt) catch return node;
            }
            return node;
        },
        .begin => {
            var changed = false;
            var stack_buf: [256]*Node = undefined;
            const heap_buf = if (node.data.begin.len > 256) (ir.allocator.alloc(*Node, node.data.begin.len) catch return node) else null;
            defer if (heap_buf) |h| ir.allocator.free(h);
            const buf: []*Node = heap_buf orelse &stack_buf;
            for (node.data.begin, 0..) |expr, i| {
                buf[i] = foldConstants(ir, expr);
                if (buf[i] != expr) changed = true;
            }
            if (changed) return ir.makeBegin(buf[0..node.data.begin.len]) catch return node;
            return node;
        },
        else => return node,
    }
}

// ---------------------------------------------------------------------------
// Optimization: dead branch elimination
// ---------------------------------------------------------------------------

pub fn eliminateDeadBranches(ir: *IR, node: *Node) *Node {
    switch (node.tag) {
        .@"if" => {
            const data = node.data.@"if";
            const new_test = eliminateDeadBranches(ir, data.test_expr);
            const new_cons = eliminateDeadBranches(ir, data.consequent);
            const new_alt = if (data.alternate) |alt| eliminateDeadBranches(ir, alt) else null;

            if (new_test.tag == .constant) {
                const test_val = new_test.data.constant;
                if (test_val != types.FALSE) return new_cons;
                if (new_alt) |alt| return alt;
                return ir.makeConst(types.VOID) catch return node;
            }
            if (new_test != data.test_expr or new_cons != data.consequent or
                (data.alternate != null and new_alt != data.alternate.?))
            {
                return ir.makeIf(new_test, new_cons, new_alt) catch return node;
            }
            return node;
        },
        .begin => {
            var changed = false;
            var stack_buf: [256]*Node = undefined;
            const heap_buf = if (node.data.begin.len > 256) (ir.allocator.alloc(*Node, node.data.begin.len) catch return node) else null;
            defer if (heap_buf) |h| ir.allocator.free(h);
            const buf: []*Node = heap_buf orelse &stack_buf;
            for (node.data.begin, 0..) |expr, i| {
                buf[i] = eliminateDeadBranches(ir, expr);
                if (buf[i] != expr) changed = true;
            }
            if (changed) return ir.makeBegin(buf[0..node.data.begin.len]) catch return node;
            return node;
        },
        else => return node,
    }
}

// ---------------------------------------------------------------------------
// Optimization: boolean simplification
// ---------------------------------------------------------------------------

pub fn simplifyBooleans(ir: *IR, node: *Node) *Node {
    switch (node.tag) {
        .@"if" => {
            const data = node.data.@"if";
            var new_test = simplifyBooleans(ir, data.test_expr);
            const new_cons = simplifyBooleans(ir, data.consequent);
            const new_alt = if (data.alternate) |alt| simplifyBooleans(ir, alt) else null;

            // (if (not X) A B) → (if X B A)
            if (new_test.tag == .call and new_test.data.call.args.len == 1 and
                new_test.data.call.operator.tag == .global_ref)
            {
                const sym = new_test.data.call.operator.data.global_ref;
                if (types.isSymbol(sym) and std.mem.eql(u8, types.symbolName(sym), "not") and !ir.isRedefined("not")) {
                    new_test = new_test.data.call.args[0];
                    return ir.makeIf(new_test, new_alt orelse (ir.makeConst(types.VOID) catch return node), new_cons) catch return node;
                }
            }

            if (new_test != data.test_expr or new_cons != data.consequent or
                (data.alternate != null and new_alt != data.alternate.?))
            {
                return ir.makeIf(new_test, new_cons, new_alt) catch return node;
            }
            return node;
        },
        .begin => {
            var changed = false;
            var stack_buf: [256]*Node = undefined;
            const heap_buf = if (node.data.begin.len > 256) (ir.allocator.alloc(*Node, node.data.begin.len) catch return node) else null;
            defer if (heap_buf) |h| ir.allocator.free(h);
            const buf: []*Node = heap_buf orelse &stack_buf;
            for (node.data.begin, 0..) |expr, i| {
                buf[i] = simplifyBooleans(ir, expr);
                if (buf[i] != expr) changed = true;
            }
            if (changed) return ir.makeBegin(buf[0..node.data.begin.len]) catch return node;
            return node;
        },
        .call => return node,
        else => return node,
    }
}

// ---------------------------------------------------------------------------
// Optimization: identity elimination
// ---------------------------------------------------------------------------

fn isExactInteger(val: Value) bool {
    return types.isFixnum(val) or types.isBignum(val);
}

pub fn eliminateIdentity(ir: *IR, node: *Node) *Node {
    switch (node.tag) {
        .call => {
            const call = node.data.call;
            if (call.operator.tag != .global_ref) return node;
            const sym = call.operator.data.global_ref;
            if (!types.isSymbol(sym)) return node;
            const name = types.symbolName(sym);

            if (call.args.len == 2) {
                const a = call.args[0];
                const b = call.args[1];

                // (+ x 0) → x, (+ 0 x) → x  (only for exact integer constants)
                if (std.mem.eql(u8, name, "+")) {
                    if (b.tag == .constant and types.isFixnum(b.data.constant) and types.toFixnum(b.data.constant) == 0 and a.tag == .constant and isExactInteger(a.data.constant))
                        return eliminateIdentity(ir, a);
                    if (a.tag == .constant and types.isFixnum(a.data.constant) and types.toFixnum(a.data.constant) == 0 and b.tag == .constant and isExactInteger(b.data.constant))
                        return eliminateIdentity(ir, b);
                }
                // (* x 1) → x, (* 1 x) → x  (only for exact integer constants)
                if (std.mem.eql(u8, name, "*")) {
                    if (b.tag == .constant and types.isFixnum(b.data.constant) and types.toFixnum(b.data.constant) == 1 and a.tag == .constant and isExactInteger(a.data.constant))
                        return eliminateIdentity(ir, a);
                    if (a.tag == .constant and types.isFixnum(a.data.constant) and types.toFixnum(a.data.constant) == 1 and b.tag == .constant and isExactInteger(b.data.constant))
                        return eliminateIdentity(ir, b);
                    // (* x 0) → 0, (* 0 x) → 0 (only when both operands are exact integer constants)
                    if (b.tag == .constant and types.isFixnum(b.data.constant) and types.toFixnum(b.data.constant) == 0 and a.tag == .constant and isExactInteger(a.data.constant))
                        return ir.makeConst(types.makeFixnum(0)) catch return node;
                    if (a.tag == .constant and types.isFixnum(a.data.constant) and types.toFixnum(a.data.constant) == 0 and b.tag == .constant and isExactInteger(b.data.constant))
                        return ir.makeConst(types.makeFixnum(0)) catch return node;
                }
                // (- x 0) → x  (only for exact integer constants)
                if (std.mem.eql(u8, name, "-")) {
                    if (b.tag == .constant and types.isFixnum(b.data.constant) and types.toFixnum(b.data.constant) == 0 and a.tag == .constant and isExactInteger(a.data.constant))
                        return eliminateIdentity(ir, a);
                }
            }
            return node;
        },
        .@"if" => {
            const data = node.data.@"if";
            const new_test = eliminateIdentity(ir, data.test_expr);
            const new_cons = eliminateIdentity(ir, data.consequent);
            const new_alt = if (data.alternate) |alt| eliminateIdentity(ir, alt) else null;
            if (new_test != data.test_expr or new_cons != data.consequent or
                (data.alternate != null and new_alt != data.alternate.?))
            {
                return ir.makeIf(new_test, new_cons, new_alt) catch return node;
            }
            return node;
        },
        .begin => {
            var changed = false;
            var stack_buf: [256]*Node = undefined;
            const heap_buf = if (node.data.begin.len > 256) (ir.allocator.alloc(*Node, node.data.begin.len) catch return node) else null;
            defer if (heap_buf) |h| ir.allocator.free(h);
            const buf: []*Node = heap_buf orelse &stack_buf;
            for (node.data.begin, 0..) |expr, i| {
                buf[i] = eliminateIdentity(ir, expr);
                if (buf[i] != expr) changed = true;
            }
            if (changed) return ir.makeBegin(buf[0..node.data.begin.len]) catch return node;
            return node;
        },
        else => return node,
    }
}

// ---------------------------------------------------------------------------
// Optimization: begin simplification
// ---------------------------------------------------------------------------

pub fn simplifyBegin(ir: *IR, node: *Node) *Node {
    switch (node.tag) {
        .begin => {
            if (node.data.begin.len == 1) return simplifyBegin(ir, @constCast(node.data.begin[0]));
            var changed = false;
            var stack_buf: [256]*Node = undefined;
            const heap_buf = if (node.data.begin.len > 256) (ir.allocator.alloc(*Node, node.data.begin.len) catch return node) else null;
            defer if (heap_buf) |h| ir.allocator.free(h);
            const buf: []*Node = heap_buf orelse &stack_buf;
            for (node.data.begin, 0..) |expr, i| {
                buf[i] = simplifyBegin(ir, @constCast(expr));
                if (buf[i] != expr) changed = true;
            }
            if (changed) return ir.makeBegin(buf[0..node.data.begin.len]) catch return node;
            return node;
        },
        .@"if" => {
            const data = node.data.@"if";
            const new_test = simplifyBegin(ir, data.test_expr);
            const new_cons = simplifyBegin(ir, data.consequent);
            const new_alt = if (data.alternate) |alt| simplifyBegin(ir, alt) else null;
            if (new_test != data.test_expr or new_cons != data.consequent or
                (data.alternate != null and new_alt != data.alternate.?))
            {
                return ir.makeIf(new_test, new_cons, new_alt) catch return node;
            }
            return node;
        },
        else => return node,
    }
}
