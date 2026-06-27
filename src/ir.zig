const std = @import("std");
const types = @import("types.zig");
const memory = @import("memory.zig");
const compiler_mod = @import("compiler.zig");

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
    passthrough,
};

pub const Annotations = struct {
    is_tail: bool = false,
    is_primitive_call: bool = false,
    primitive_name: ?[]const u8 = null,
    is_constant: bool = false,
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
        do_form: SexprArgs,
        delay: SexprArgs,
        delay_force: SexprArgs,
        cond: SexprArgs,
        case_form: SexprArgs,
        case_lambda: SexprArgs,
        guard: SexprArgs,
        quasiquote: SexprArgs,
        parameterize: SexprArgs,
        define_values: SexprArgs,
        let_values: SexprArgs,
        let_star_values: SexprArgs,
        define_syntax: SexprArgs,
        named_let: SexprArgs,
        let_syntax: SexprArgs,
        letrec_syntax: SexprArgs,
        cond_expand: SexprArgs,
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

pub const SexprArgs = struct {
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

    pub fn init(allocator: std.mem.Allocator) IR {
        return .{
            .allocator = allocator,
            .nodes = .empty,
        };
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
            .constant,
            .global_ref,
            .@"if",
            .define,
            .set_form,
            .lambda,
            .let_form,
            .let_star,
            .letrec,
            .letrec_star,
            .do_form,
            .delay,
            .delay_force,
            .cond,
            .case_form,
            .case_lambda,
            .guard,
            .quasiquote,
            .parameterize,
            .define_values,
            .let_values,
            .let_star_values,
            .define_syntax,
            .named_let,
            .let_syntax,
            .letrec_syntax,
            .cond_expand,
            .passthrough,
            => {},
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

    pub fn makeSexprNode(self: *IR, tag: NodeTag, args: Value) CompileError!*Node {
        return switch (tag) {
            .do_form => self.allocNode(.do_form, .{ .do_form = .{ .args = args } }),
            .delay => self.allocNode(.delay, .{ .delay = .{ .args = args } }),
            .delay_force => self.allocNode(.delay_force, .{ .delay_force = .{ .args = args } }),
            .cond => self.allocNode(.cond, .{ .cond = .{ .args = args } }),
            .case_form => self.allocNode(.case_form, .{ .case_form = .{ .args = args } }),
            .case_lambda => self.allocNode(.case_lambda, .{ .case_lambda = .{ .args = args } }),
            .guard => self.allocNode(.guard, .{ .guard = .{ .args = args } }),
            .quasiquote => self.allocNode(.quasiquote, .{ .quasiquote = .{ .args = args } }),
            .parameterize => self.allocNode(.parameterize, .{ .parameterize = .{ .args = args } }),
            .define_values => self.allocNode(.define_values, .{ .define_values = .{ .args = args } }),
            .let_values => self.allocNode(.let_values, .{ .let_values = .{ .args = args } }),
            .let_star_values => self.allocNode(.let_star_values, .{ .let_star_values = .{ .args = args } }),
            .define_syntax => self.allocNode(.define_syntax, .{ .define_syntax = .{ .args = args } }),
            .named_let => self.allocNode(.named_let, .{ .named_let = .{ .args = args } }),
            .let_syntax => self.allocNode(.let_syntax, .{ .let_syntax = .{ .args = args } }),
            .letrec_syntax => self.allocNode(.letrec_syntax, .{ .letrec_syntax = .{ .args = args } }),
            .cond_expand => self.allocNode(.cond_expand, .{ .cond_expand = .{ .args = args } }),
            else => unreachable,
        };
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

const special_forms = [_][]const u8{
    "quote",         "if",         "lambda",        "define",
    "define-values", "set!",       "begin",         "and",
    "or",            "when",       "unless",        "cond",
    "let",           "let*",       "let-values",    "let*-values",
    "letrec",        "letrec*",    "case",          "case-lambda",
    "cond-expand",   "do",         "guard",         "delay",
    "delay-force",   "quasiquote", "parameterize",  "syntax-error",
    "define-syntax", "let-syntax", "letrec-syntax", "syntax-rules",
    "apply",
};

fn isSpecialForm(name: []const u8) bool {
    for (special_forms) |sf| {
        if (std.mem.eql(u8, name, sf)) return true;
    }
    return false;
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
        return lowerFormWithMacros(ir, expr, macros);
    }

    return CompileError.InvalidSyntax;
}

fn lowerFormWithMacros(ir: *IR, expr: Value, macros: ?*std.StringHashMap(Value)) CompileError!*Node {
    const head = types.car(expr);

    if (types.isSymbol(head)) {
        const name = types.symbolName(head);

        var effective_name = name;
        while (std.mem.startsWith(u8, effective_name, "__hyg_")) {
            if (std.mem.indexOfScalar(u8, effective_name[6..], '_')) |sep| {
                effective_name = effective_name[6 + sep + 1 ..];
            } else break;
        }

        if (std.mem.eql(u8, effective_name, "if")) return lowerIf(ir, types.cdr(expr));
        if (std.mem.eql(u8, effective_name, "quote")) return lowerQuote(ir, types.cdr(expr));
        if (std.mem.eql(u8, effective_name, "begin")) return lowerBegin(ir, types.cdr(expr));
        if (std.mem.eql(u8, effective_name, "lambda")) return ir.makeLambda(types.cdr(expr), null);
        if (std.mem.eql(u8, effective_name, "let")) return lowerLet(ir, expr);
        if (std.mem.eql(u8, effective_name, "let*")) return ir.makeLetStar(types.cdr(expr));
        if (std.mem.eql(u8, effective_name, "letrec")) return ir.makeLetrec(types.cdr(expr));
        if (std.mem.eql(u8, effective_name, "letrec*")) return ir.makeLetrecStar(types.cdr(expr));
        if (std.mem.eql(u8, effective_name, "define")) return lowerDefine(ir, expr);
        if (std.mem.eql(u8, effective_name, "define-values")) return ir.makeSexprNode(.define_values, types.cdr(expr));
        if (std.mem.eql(u8, effective_name, "set!")) return lowerSet(ir, types.cdr(expr));
        if (std.mem.eql(u8, effective_name, "and")) return lowerList(ir, types.cdr(expr), .and_form);
        if (std.mem.eql(u8, effective_name, "or")) return lowerList(ir, types.cdr(expr), .or_form);
        if (std.mem.eql(u8, effective_name, "when")) return lowerCondBody(ir, types.cdr(expr), .when_form);
        if (std.mem.eql(u8, effective_name, "unless")) return lowerCondBody(ir, types.cdr(expr), .unless_form);
        if (std.mem.eql(u8, effective_name, "cond")) return ir.makeSexprNode(.cond, types.cdr(expr));
        if (std.mem.eql(u8, effective_name, "case")) return ir.makeSexprNode(.case_form, types.cdr(expr));
        if (std.mem.eql(u8, effective_name, "case-lambda")) return ir.makeSexprNode(.case_lambda, types.cdr(expr));
        if (std.mem.eql(u8, effective_name, "do")) return ir.makeSexprNode(.do_form, types.cdr(expr));
        if (std.mem.eql(u8, effective_name, "guard")) return ir.makeSexprNode(.guard, types.cdr(expr));
        if (std.mem.eql(u8, effective_name, "delay")) return ir.makeSexprNode(.delay, types.cdr(expr));
        if (std.mem.eql(u8, effective_name, "delay-force")) return ir.makeSexprNode(.delay_force, types.cdr(expr));
        if (std.mem.eql(u8, effective_name, "quasiquote")) return ir.makeSexprNode(.quasiquote, types.cdr(expr));
        if (std.mem.eql(u8, effective_name, "parameterize")) return ir.makeSexprNode(.parameterize, types.cdr(expr));
        if (std.mem.eql(u8, effective_name, "let-values")) return ir.makeSexprNode(.let_values, types.cdr(expr));
        if (std.mem.eql(u8, effective_name, "let*-values")) return ir.makeSexprNode(.let_star_values, types.cdr(expr));
        if (std.mem.eql(u8, effective_name, "define-syntax")) return ir.makeSexprNode(.define_syntax, types.cdr(expr));
        if (std.mem.eql(u8, effective_name, "let-syntax")) return ir.makeSexprNode(.let_syntax, types.cdr(expr));
        if (std.mem.eql(u8, effective_name, "letrec-syntax")) return ir.makeSexprNode(.letrec_syntax, types.cdr(expr));
        if (std.mem.eql(u8, effective_name, "cond-expand")) return ir.makeSexprNode(.cond_expand, types.cdr(expr));

        if (isSpecialForm(effective_name)) return ir.makePassthrough(expr);

        if (macros) |m| {
            if (m.get(effective_name) != null) return ir.makePassthrough(expr);
        }

        if (tryFoldFromAST(ir, expr)) |folded| return folded;
        return lowerCall(ir, expr);
    }

    if (tryFoldFromAST(ir, expr)) |folded| return folded;
    return lowerCall(ir, expr);
}

pub fn lower(ir: *IR, expr: Value) CompileError!*Node {
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
        return lowerForm(ir, expr);
    }

    return CompileError.InvalidSyntax;
}

fn lowerForm(ir: *IR, expr: Value) CompileError!*Node {
    const head = types.car(expr);

    if (types.isSymbol(head)) {
        const name = types.symbolName(head);

        var effective_name = name;
        while (std.mem.startsWith(u8, effective_name, "__hyg_")) {
            if (std.mem.indexOfScalar(u8, effective_name[6..], '_')) |sep| {
                effective_name = effective_name[6 + sep + 1 ..];
            } else break;
        }

        if (std.mem.eql(u8, effective_name, "if")) return lowerIf(ir, types.cdr(expr));
        if (std.mem.eql(u8, effective_name, "quote")) return lowerQuote(ir, types.cdr(expr));
        if (std.mem.eql(u8, effective_name, "begin")) return lowerBegin(ir, types.cdr(expr));
        if (std.mem.eql(u8, effective_name, "lambda")) return ir.makeLambda(types.cdr(expr), null);
        if (std.mem.eql(u8, effective_name, "let")) return lowerLet(ir, expr);
        if (std.mem.eql(u8, effective_name, "let*")) return ir.makeLetStar(types.cdr(expr));
        if (std.mem.eql(u8, effective_name, "letrec")) return ir.makeLetrec(types.cdr(expr));
        if (std.mem.eql(u8, effective_name, "letrec*")) return ir.makeLetrecStar(types.cdr(expr));
        if (std.mem.eql(u8, effective_name, "define")) return lowerDefine(ir, expr);
        if (std.mem.eql(u8, effective_name, "define-values")) return ir.makeSexprNode(.define_values, types.cdr(expr));
        if (std.mem.eql(u8, effective_name, "set!")) return lowerSet(ir, types.cdr(expr));
        if (std.mem.eql(u8, effective_name, "and")) return lowerList(ir, types.cdr(expr), .and_form);
        if (std.mem.eql(u8, effective_name, "or")) return lowerList(ir, types.cdr(expr), .or_form);
        if (std.mem.eql(u8, effective_name, "when")) return lowerCondBody(ir, types.cdr(expr), .when_form);
        if (std.mem.eql(u8, effective_name, "unless")) return lowerCondBody(ir, types.cdr(expr), .unless_form);
        if (std.mem.eql(u8, effective_name, "cond")) return ir.makeSexprNode(.cond, types.cdr(expr));
        if (std.mem.eql(u8, effective_name, "case")) return ir.makeSexprNode(.case_form, types.cdr(expr));
        if (std.mem.eql(u8, effective_name, "case-lambda")) return ir.makeSexprNode(.case_lambda, types.cdr(expr));
        if (std.mem.eql(u8, effective_name, "do")) return ir.makeSexprNode(.do_form, types.cdr(expr));
        if (std.mem.eql(u8, effective_name, "guard")) return ir.makeSexprNode(.guard, types.cdr(expr));
        if (std.mem.eql(u8, effective_name, "delay")) return ir.makeSexprNode(.delay, types.cdr(expr));
        if (std.mem.eql(u8, effective_name, "delay-force")) return ir.makeSexprNode(.delay_force, types.cdr(expr));
        if (std.mem.eql(u8, effective_name, "quasiquote")) return ir.makeSexprNode(.quasiquote, types.cdr(expr));
        if (std.mem.eql(u8, effective_name, "parameterize")) return ir.makeSexprNode(.parameterize, types.cdr(expr));
        if (std.mem.eql(u8, effective_name, "let-values")) return ir.makeSexprNode(.let_values, types.cdr(expr));
        if (std.mem.eql(u8, effective_name, "let*-values")) return ir.makeSexprNode(.let_star_values, types.cdr(expr));
        if (std.mem.eql(u8, effective_name, "define-syntax")) return ir.makeSexprNode(.define_syntax, types.cdr(expr));
        if (std.mem.eql(u8, effective_name, "let-syntax")) return ir.makeSexprNode(.let_syntax, types.cdr(expr));
        if (std.mem.eql(u8, effective_name, "letrec-syntax")) return ir.makeSexprNode(.letrec_syntax, types.cdr(expr));
        if (std.mem.eql(u8, effective_name, "cond-expand")) return ir.makeSexprNode(.cond_expand, types.cdr(expr));

        // Remaining: syntax-rules (error), syntax-error (error), apply (tail)
        if (isSpecialForm(effective_name)) return ir.makePassthrough(expr);
    }

    // For calls where the operator is NOT a known special-form keyword,
    // check if constant folding applies. If not, passthrough to the
    // compiler which handles macro expansion and local shadowing.
    if (types.isSymbol(head)) {
        if (tryFoldFromAST(ir, expr)) |folded| return folded;
    }

    return ir.makePassthrough(expr);
}

fn lowerIf(ir: *IR, args: Value) CompileError!*Node {
    if (args == types.NIL) return CompileError.InvalidSyntax;
    const test_expr = types.car(args);
    const rest = types.cdr(args);
    if (rest == types.NIL) return CompileError.InvalidSyntax;
    const consequent = types.car(rest);
    const rest2 = types.cdr(rest);

    const test_node = try lower(ir, test_expr);
    const cons_node = try lower(ir, consequent);
    const alt_node: ?*Node = if (rest2 != types.NIL)
        try lower(ir, types.car(rest2))
    else
        null;

    return ir.makeIf(test_node, cons_node, alt_node);
}

fn lowerQuote(ir: *IR, args: Value) CompileError!*Node {
    if (args == types.NIL) return CompileError.InvalidSyntax;
    return ir.makeConst(types.car(args));
}

fn lowerBegin(ir: *IR, args: Value) CompileError!*Node {
    var buf: [256]*Node = undefined;
    var count: usize = 0;
    var current = args;
    while (current != types.NIL) {
        if (!types.isPair(current)) return CompileError.InvalidSyntax;
        if (count >= 256) return CompileError.InternalLimit;
        buf[count] = try lower(ir, types.car(current));
        count += 1;
        current = types.cdr(current);
    }
    return ir.makeBegin(buf[0..count]);
}

fn lowerLet(ir: *IR, expr: Value) CompileError!*Node {
    const args = types.cdr(expr);
    if (args == types.NIL) return CompileError.InvalidSyntax;
    const first = types.car(args);
    if (types.isSymbol(first)) return ir.makeSexprNode(.named_let, args);
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

fn lowerList(ir: *IR, args: Value, tag: NodeTag) CompileError!*Node {
    var buf: [256]*Node = undefined;
    var count: usize = 0;
    var current = args;
    while (current != types.NIL) {
        if (!types.isPair(current)) return CompileError.InvalidSyntax;
        if (count >= 256) return CompileError.InternalLimit;
        buf[count] = try lower(ir, types.car(current));
        count += 1;
        current = types.cdr(current);
    }
    return switch (tag) {
        .and_form => ir.makeAnd(buf[0..count]),
        .or_form => ir.makeOr(buf[0..count]),
        else => ir.makeBegin(buf[0..count]),
    };
}

fn lowerCondBody(ir: *IR, args: Value, tag: NodeTag) CompileError!*Node {
    if (args == types.NIL) return CompileError.InvalidSyntax;
    const test_expr = try lower(ir, types.car(args));

    var buf: [256]*Node = undefined;
    var count: usize = 0;
    var current = types.cdr(args);
    while (current != types.NIL) {
        if (!types.isPair(current)) return CompileError.InvalidSyntax;
        if (count >= 256) return CompileError.InternalLimit;
        buf[count] = try lower(ir, types.car(current));
        count += 1;
        current = types.cdr(current);
    }
    return switch (tag) {
        .when_form => ir.makeWhen(test_expr, buf[0..count]),
        .unless_form => ir.makeUnless(test_expr, buf[0..count]),
        else => unreachable,
    };
}

fn lowerCall(ir: *IR, expr: Value) CompileError!*Node {
    if (tryFoldFromAST(ir, expr)) |folded| return folded;

    const operator = types.car(expr);
    const op_node = try lower(ir, operator);

    var arg_buf: [256]*Node = undefined;
    var nargs: usize = 0;
    var arg_list = types.cdr(expr);
    while (arg_list != types.NIL) {
        if (!types.isPair(arg_list)) return CompileError.InvalidSyntax;
        if (nargs >= 256) return CompileError.InternalLimit;
        arg_buf[nargs] = try lower(ir, types.car(arg_list));
        nargs += 1;
        arg_list = types.cdr(arg_list);
    }

    return ir.makeCall(op_node, arg_buf[0..nargs]);
}

fn tryFoldFromAST(ir: *IR, expr: Value) ?*Node {
    const operator = types.car(expr);
    if (!types.isSymbol(operator)) return null;
    const name = types.symbolName(operator);

    const args_pair = types.cdr(expr);
    if (!types.isPair(args_pair)) return null;
    const a = types.car(args_pair);
    const rest = types.cdr(args_pair);

    if (rest == types.NIL) {
        if (!types.isFixnum(a) and a != types.TRUE and a != types.FALSE) return null;

        const result: ?Value = if (std.mem.eql(u8, name, "not"))
            (if (a == types.FALSE) types.TRUE else types.FALSE)
        else if (std.mem.eql(u8, name, "zero?"))
            (if (types.isFixnum(a) and types.toFixnum(a) == 0) types.TRUE else types.FALSE)
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
        .constant, .global_ref, .passthrough => {},
        .define,
        .set_form,
        .lambda,
        .let_form,
        .let_star,
        .letrec,
        .letrec_star,
        .do_form,
        .delay,
        .delay_force,
        .cond,
        .case_form,
        .case_lambda,
        .guard,
        .quasiquote,
        .parameterize,
        .define_values,
        .let_values,
        .let_star_values,
        .define_syntax,
        .named_let,
        .let_syntax,
        .letrec_syntax,
        .cond_expand,
        => {},
    }
}

// ---------------------------------------------------------------------------
// Semantic analysis: primitive identification
// ---------------------------------------------------------------------------

const primitives = [_][]const u8{
    "+",              "-",              "*",            "/",             "=",           "<",              ">",
    "<=",             ">=",             "zero?",        "not",           "null?",       "pair?",          "car",
    "cdr",            "cons",           "list",         "length",        "append",      "map",            "apply",
    "values",         "vector-ref",     "vector-set!",  "vector-length", "string-ref",  "string-length",  "char->integer",
    "integer->char",  "number?",        "string?",      "symbol?",       "boolean?",    "char?",          "vector?",
    "procedure?",     "eq?",            "eqv?",         "equal?",        "abs",         "max",            "min",
    "remainder",      "modulo",         "quotient",     "expt",          "sqrt",        "number->string", "string->number",
    "exact->inexact", "inexact->exact", "floor",        "ceiling",       "truncate",    "round",          "string-append",
    "substring",      "string-copy",    "string->list", "list->string",  "make-string", "make-vector",    "vector",
    "display",        "write",          "newline",      "read",          "even?",       "odd?",           "positive?",
    "negative?",      "exact?",         "inexact?",     "integer?",      "rational?",   "real?",          "complex?",
    "gcd",            "lcm",
};

pub fn identifyPrimitives(node: *Node) void {
    switch (node.tag) {
        .call => {
            if (node.data.call.operator.tag == .global_ref) {
                const sym = node.data.call.operator.data.global_ref;
                if (types.isSymbol(sym)) {
                    const name = types.symbolName(sym);
                    for (primitives) |p| {
                        if (std.mem.eql(u8, name, p)) {
                            node.ann.is_primitive_call = true;
                            node.ann.primitive_name = name;
                            break;
                        }
                    }
                }
            }
            identifyPrimitives(node.data.call.operator);
            for (node.data.call.args) |arg| identifyPrimitives(arg);
        },
        .@"if" => {
            identifyPrimitives(node.data.@"if".test_expr);
            identifyPrimitives(node.data.@"if".consequent);
            if (node.data.@"if".alternate) |alt| identifyPrimitives(alt);
        },
        .begin => {
            for (node.data.begin) |expr| identifyPrimitives(expr);
        },
        .and_form => {
            for (node.data.and_form) |expr| identifyPrimitives(expr);
        },
        .or_form => {
            for (node.data.or_form) |expr| identifyPrimitives(expr);
        },
        .when_form => {
            identifyPrimitives(node.data.when_form.test_expr);
            for (node.data.when_form.body) |expr| identifyPrimitives(expr);
        },
        .unless_form => {
            identifyPrimitives(node.data.unless_form.test_expr);
            for (node.data.unless_form.body) |expr| identifyPrimitives(expr);
        },
        .constant, .global_ref, .passthrough => {},
        .define,
        .set_form,
        .lambda,
        .let_form,
        .let_star,
        .letrec,
        .letrec_star,
        .do_form,
        .delay,
        .delay_force,
        .cond,
        .case_form,
        .case_lambda,
        .guard,
        .quasiquote,
        .parameterize,
        .define_values,
        .let_values,
        .let_star_values,
        .define_syntax,
        .named_let,
        .let_syntax,
        .letrec_syntax,
        .cond_expand,
        => {},
    }
}

// ---------------------------------------------------------------------------
// Semantic analysis: constant expression detection
// ---------------------------------------------------------------------------

pub fn markConstants(node: *Node) void {
    switch (node.tag) {
        .constant => node.ann.is_constant = true,
        .@"if" => {
            markConstants(node.data.@"if".test_expr);
            markConstants(node.data.@"if".consequent);
            if (node.data.@"if".alternate) |alt| markConstants(alt);
        },
        .begin => {
            for (node.data.begin) |expr| markConstants(expr);
            if (node.data.begin.len > 0) {
                node.ann.is_constant = node.data.begin[node.data.begin.len - 1].ann.is_constant;
            }
        },
        .call => {
            markConstants(node.data.call.operator);
            var all_const = node.data.call.operator.tag == .global_ref;
            for (node.data.call.args) |arg| {
                markConstants(arg);
                if (!arg.ann.is_constant) all_const = false;
            }
            if (all_const and node.ann.is_primitive_call) {
                node.ann.is_constant = true;
            }
        },
        .and_form => {
            for (node.data.and_form) |expr| markConstants(expr);
        },
        .or_form => {
            for (node.data.or_form) |expr| markConstants(expr);
        },
        .when_form => {
            markConstants(node.data.when_form.test_expr);
            for (node.data.when_form.body) |expr| markConstants(expr);
        },
        .unless_form => {
            markConstants(node.data.unless_form.test_expr);
            for (node.data.unless_form.body) |expr| markConstants(expr);
        },
        .global_ref, .passthrough => {},
        .define,
        .set_form,
        .lambda,
        .let_form,
        .let_star,
        .letrec,
        .letrec_star,
        .do_form,
        .delay,
        .delay_force,
        .cond,
        .case_form,
        .case_lambda,
        .guard,
        .quasiquote,
        .parameterize,
        .define_values,
        .let_values,
        .let_star_values,
        .define_syntax,
        .named_let,
        .let_syntax,
        .letrec_syntax,
        .cond_expand,
        => {},
    }
}

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

            if (call.args.len == 1) {
                const a = call.args[0];
                if (a.tag != .constant) return node;
                const av = a.data.constant;
                if (!types.isFixnum(av) and av != types.TRUE and av != types.FALSE) return node;

                const result: ?Value = if (std.mem.eql(u8, name, "not"))
                    (if (av == types.FALSE) types.TRUE else types.FALSE)
                else if (std.mem.eql(u8, name, "zero?"))
                    (if (types.isFixnum(av) and types.toFixnum(av) == 0) types.TRUE else types.FALSE)
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
            var buf: [256]*Node = undefined;
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
            var buf: [256]*Node = undefined;
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
                if (types.isSymbol(sym) and std.mem.eql(u8, types.symbolName(sym), "not")) {
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
            var buf: [256]*Node = undefined;
            for (node.data.begin, 0..) |expr, i| {
                buf[i] = simplifyBooleans(ir, expr);
                if (buf[i] != expr) changed = true;
            }
            if (changed) return ir.makeBegin(buf[0..node.data.begin.len]) catch return node;
            return node;
        },
        .call => {
            const call = node.data.call;
            // (not (not X)) → X
            if (call.args.len == 1 and call.operator.tag == .global_ref) {
                const sym = call.operator.data.global_ref;
                if (types.isSymbol(sym) and std.mem.eql(u8, types.symbolName(sym), "not")) {
                    const inner = call.args[0];
                    if (inner.tag == .call and inner.data.call.args.len == 1 and
                        inner.data.call.operator.tag == .global_ref)
                    {
                        const inner_sym = inner.data.call.operator.data.global_ref;
                        if (types.isSymbol(inner_sym) and std.mem.eql(u8, types.symbolName(inner_sym), "not")) {
                            return inner.data.call.args[0];
                        }
                    }
                }
            }
            return node;
        },
        else => return node,
    }
}

// ---------------------------------------------------------------------------
// Optimization: identity elimination
// ---------------------------------------------------------------------------

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

                // (+ x 0) → x, (+ 0 x) → x
                if (std.mem.eql(u8, name, "+")) {
                    if (b.tag == .constant and types.isFixnum(b.data.constant) and types.toFixnum(b.data.constant) == 0)
                        return eliminateIdentity(ir, a);
                    if (a.tag == .constant and types.isFixnum(a.data.constant) and types.toFixnum(a.data.constant) == 0)
                        return eliminateIdentity(ir, b);
                }
                // (* x 1) → x, (* 1 x) → x
                if (std.mem.eql(u8, name, "*")) {
                    if (b.tag == .constant and types.isFixnum(b.data.constant) and types.toFixnum(b.data.constant) == 1)
                        return eliminateIdentity(ir, a);
                    if (a.tag == .constant and types.isFixnum(a.data.constant) and types.toFixnum(a.data.constant) == 1)
                        return eliminateIdentity(ir, b);
                    // (* x 0) → 0, (* 0 x) → 0
                    if (b.tag == .constant and types.isFixnum(b.data.constant) and types.toFixnum(b.data.constant) == 0)
                        return ir.makeConst(types.makeFixnum(0)) catch return node;
                    if (a.tag == .constant and types.isFixnum(a.data.constant) and types.toFixnum(a.data.constant) == 0)
                        return ir.makeConst(types.makeFixnum(0)) catch return node;
                }
                // (- x 0) → x
                if (std.mem.eql(u8, name, "-")) {
                    if (b.tag == .constant and types.isFixnum(b.data.constant) and types.toFixnum(b.data.constant) == 0)
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
            var buf: [256]*Node = undefined;
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
            var buf: [256]*Node = undefined;
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

// ---------------------------------------------------------------------------
// IR → bytecode emission (standalone, used by Stage 1 parity tests)
// ---------------------------------------------------------------------------

pub const Emitter = struct {
    gc: *memory.GC,
    func: *types.Function,
    next_register: u16 = 0,

    pub fn init(gc: *memory.GC) CompileError!Emitter {
        const func = gc.allocFunction() catch return CompileError.OutOfMemory;
        return .{ .gc = gc, .func = func };
    }

    pub fn compile(self: *Emitter, node: *Node) CompileError!void {
        const dst = try self.allocReg();
        try self.emitNode(node, dst, false);
        try self.emitOp(.@"return");
        try self.emitU16(dst);
    }

    pub fn emitNode(self: *Emitter, node: *Node, dst: u16, is_tail: bool) CompileError!void {
        switch (node.tag) {
            .constant => try self.emitConstant(node.data.constant, dst),
            .global_ref => try self.emitGlobalRef(node.data.global_ref, dst),
            .call => try self.emitCall(node.data.call, dst, is_tail),
            .@"if" => try self.emitIf(node.data.@"if", dst, is_tail),
            .begin => try self.emitBegin(node.data.begin, dst, is_tail),
            .and_form,
            .or_form,
            .when_form,
            .unless_form,
            .define,
            .set_form,
            .lambda,
            .let_form,
            .let_star,
            .letrec,
            .letrec_star,
            .do_form,
            .delay,
            .delay_force,
            .cond,
            .case_form,
            .case_lambda,
            .guard,
            .quasiquote,
            .parameterize,
            .define_values,
            .let_values,
            .let_star_values,
            .define_syntax,
            .named_let,
            .let_syntax,
            .letrec_syntax,
            .cond_expand,
            => return CompileError.NotImplemented,
            .passthrough => return CompileError.NotImplemented,
        }
    }

    fn emitConstant(self: *Emitter, value: Value, dst: u16) CompileError!void {
        if (value == types.TRUE) {
            try self.emitOp(.load_true);
            try self.emitU16(dst);
        } else if (value == types.FALSE) {
            try self.emitOp(.load_false);
            try self.emitU16(dst);
        } else if (value == types.NIL) {
            try self.emitOp(.load_nil);
            try self.emitU16(dst);
        } else {
            const idx = try self.addConstant(value);
            try self.emitOp(.load_const);
            try self.emitU16(dst);
            try self.emitU16(idx);
        }
    }

    fn emitGlobalRef(self: *Emitter, sym: Value, dst: u16) CompileError!void {
        const sym_idx = try self.addConstant(sym);
        try self.emitOp(.get_global);
        try self.emitU16(dst);
        try self.emitU16(sym_idx);
    }

    fn emitCall(self: *Emitter, call: CallData, dst: u16, is_tail: bool) CompileError!void {
        const nargs: u8 = @intCast(call.args.len);

        if (!is_tail and call.operator.tag == .global_ref) {
            const sym = call.operator.data.global_ref;
            if (types.isSymbol(sym)) {
                const op_name = types.symbolName(sym);
                const is_cont = std.mem.eql(u8, op_name, "call-with-current-continuation") or
                    std.mem.eql(u8, op_name, "call/cc") or
                    std.mem.eql(u8, op_name, "call/ec") or
                    std.mem.eql(u8, op_name, "call-with-escape-continuation") or
                    std.mem.eql(u8, op_name, "call-with-values") or
                    std.mem.eql(u8, op_name, "dynamic-wind") or
                    std.mem.eql(u8, op_name, "with-exception-handler");

                if (!is_cont) {
                    return self.emitCallGlobal(sym, call.args, dst, nargs, is_tail);
                }
            }
        }

        const needs_rebase = (dst + 1 != self.next_register);
        const base = if (needs_rebase) try self.allocReg() else dst;

        try self.emitNode(call.operator, base, false);

        for (call.args) |arg| {
            const arg_reg = try self.allocReg();
            try self.emitNode(arg, arg_reg, false);
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

    fn emitCallGlobal(self: *Emitter, sym: Value, args: []const *Node, dst: u16, nargs: u8, is_tail: bool) CompileError!void {
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
            try self.emitNode(arg, arg_reg, false);
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

    fn emitIf(self: *Emitter, data: IfData, dst: u16, is_tail: bool) CompileError!void {
        try self.emitNode(data.test_expr, dst, false);

        try self.emitOp(.jump_false);
        try self.emitU16(dst);
        const else_jump = self.currentOffset();
        try self.emitI16(0);

        try self.emitNode(data.consequent, dst, is_tail);

        if (data.alternate) |alt| {
            try self.emitOp(.jump);
            const end_jump = self.currentOffset();
            try self.emitI16(0);

            try self.patchJump(else_jump);

            try self.emitNode(alt, dst, is_tail);

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

    fn emitBegin(self: *Emitter, exprs: []const *Node, dst: u16, is_tail: bool) CompileError!void {
        if (exprs.len == 0) {
            try self.emitOp(.load_void);
            try self.emitU16(dst);
            return;
        }
        for (exprs, 0..) |expr, i| {
            const tail = is_tail and i == exprs.len - 1;
            try self.emitNode(expr, dst, tail);
        }
    }

    // -- Low-level emission helpers --

    fn emit(self: *Emitter, byte: u8) CompileError!void {
        self.func.code.append(self.gc.allocator, byte) catch return CompileError.OutOfMemory;
    }

    fn emitOp(self: *Emitter, op: OpCode) CompileError!void {
        try self.emit(@intFromEnum(op));
    }

    fn emitU16(self: *Emitter, val: u16) CompileError!void {
        try self.emit(@truncate(val >> 8));
        try self.emit(@truncate(val & 0xFF));
    }

    fn emitI16(self: *Emitter, val: i16) CompileError!void {
        const unsigned: u16 = @bitCast(val);
        try self.emitU16(unsigned);
    }

    fn addConstant(self: *Emitter, value: Value) CompileError!u16 {
        for (self.func.constants.items, 0..) |c, i| {
            if (c == value) return @intCast(i);
        }
        if (self.func.constants.items.len >= 65535) return CompileError.TooManyConstants;
        self.func.constants.append(self.gc.allocator, value) catch return CompileError.OutOfMemory;
        return @intCast(self.func.constants.items.len - 1);
    }

    fn currentOffset(self: *Emitter) usize {
        return self.func.code.items.len;
    }

    fn patchJump(self: *Emitter, offset: usize) CompileError!void {
        const dist = @as(isize, @intCast(self.currentOffset())) - @as(isize, @intCast(offset)) - 2;
        if (dist < std.math.minInt(i16) or dist > std.math.maxInt(i16)) {
            return CompileError.JumpOutOfRange;
        }
        const jump_dist: i16 = @intCast(dist);
        const unsigned: u16 = @bitCast(jump_dist);
        self.func.code.items[offset] = @truncate(unsigned >> 8);
        self.func.code.items[offset + 1] = @truncate(unsigned & 0xFF);
    }

    fn allocReg(self: *Emitter) CompileError!u16 {
        if (self.next_register >= std.math.maxInt(u16)) return CompileError.TooManyLocals;
        const reg = self.next_register;
        self.next_register += 1;
        if (self.next_register > self.func.locals_count) {
            self.func.locals_count = self.next_register;
        }
        return reg;
    }

    fn freeReg(self: *Emitter) void {
        if (self.next_register > 0) self.next_register -= 1;
    }
};
