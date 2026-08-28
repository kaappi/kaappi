const std = @import("std");
const types = @import("types.zig");
const memory = @import("memory.zig");
const compiler_mod = @import("compiler.zig");
const globals_mod = @import("globals.zig");
const timings = @import("timings.zig");
const expander = @import("expander.zig");

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
    define_property,
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
            .define_property => "define-property",
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
    // Tag-level `.native` because the shape `emitPassthrough` special-cases —
    // a `(define (f …) …)` shorthand — does compile natively. Every *other*
    // passthrough shape is eval'd whole, so the keywords that produce one
    // contribute to `eval_fallback_form_names` from `other_special_forms`
    // instead of from this entry (kaappi#1799).
    .{ .tag = .passthrough, .capability = .native },
};

const eval_fallback_name_count = countEvalFallbackNames();

// FormKinds the LLVM native backend lowers directly rather than routing through
// `kaappi_eval`, so they are NOT in `eval_fallback_form_names` and do not force
// an enclosing native let/lambda body to fall back. `named_let` is excluded
// because `lowerLet` handles it structurally (no keyword mapping); `cond`,
// `case_form`, and `do_form` are excluded because the backend emits them
// natively (kaappi#1496) — `llvm_emit_forms.zig` gates each on
// `exprNativeEmittable` and only the ungated remainder reaches the interpreter.
fn isNativeLoweredForm(fk: FormKind) bool {
    return switch (fk) {
        .named_let, .cond, .case_form, .do_form => true,
        else => false,
    };
}

fn countEvalFallbackNames() usize {
    var count: usize = 0;
    for (llvm_node_table) |entry| {
        if (entry.capability == .eval_fallback and entry.include_in_name_set and entry.form_name != null)
            count += 1;
    }
    const form_fields = @typeInfo(FormKind).@"enum".fields;
    for (form_fields) |f| {
        const fk: FormKind = @enumFromInt(f.value);
        if (isNativeLoweredForm(fk)) continue;
        count += 1;
    }
    for (other_special_forms.values()) |evals_via_passthrough| {
        if (evals_via_passthrough) count += 1;
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
        if (isNativeLoweredForm(fk)) continue;
        names[i] = fk.keyword();
        i += 1;
    }
    // The keyword-only special forms that reach the interpreter as a whole
    // `.passthrough` form (kaappi#1799). The `.passthrough` node itself carries
    // `.capability = .native` in `llvm_node_table` — correct for what the tag
    // *can* be, since its `(define (f …) …)` shape compiles natively — so these
    // names have to come from the keyword map, which knows which shapes do not.
    for (other_special_forms.keys(), other_special_forms.values()) |name, evals_via_passthrough| {
        if (!evals_via_passthrough) continue;
        names[i] = name;
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

// -- Doc sync gate ----------------------------------------------------------
//
// Several docs quote these two counts to describe how lowered the IR is, and
// they went stale at 33 — the pre-`sexpr_form` tag count — for long enough to
// give readers entirely the wrong picture (kaappi#2102).
//
// `.coderabbit.yaml` is in the list because it is *configuration for the
// automated reviewer*: a stale count there does not merely misinform a human
// who might check, it feeds the wrong model into every future PR review.
//
// As with the OpCode gate in `types.zig`, treat the list as the known set
// rather than a guarantee, and re-run the search — grep the noun, not the
// number, since the count appears as "18 node types", "**18** node tags" and
// "node types (18)" alike, and a bare "18" collides with every SRFI number.
comptime {
    if (@typeInfo(NodeTag).@"enum".fields.len != 18)
        @compileError("NodeTag count changed. Update docs/dev/ir.md, docs/dev/architecture.md, " ++
            "docs/dev/README.md, CLAUDE.md, README.md and .coderabbit.yaml. Find any others with: " ++
            "grep -rniE 'node (type|tag)' --include='*.md' --include='*.yaml' . Then update this number.");
    if (@typeInfo(FormKind).@"enum".fields.len != 18)
        @compileError("FormKind count changed. Update the FormKind table in docs/dev/ir.md, and the " ++
            "count in CLAUDE.md, docs/dev/architecture.md and .coderabbit.yaml. Find any others with: " ++
            "grep -rniE 'form ?kind' --include='*.md' --include='*.yaml' . Then update this number.");
}

pub const Annotations = struct {
    is_tail: bool = false,
    /// Source span of the form this node was lowered from, if it was a datum the
    /// reader could key (a pair/vector). `span.line == 0` means unknown. The
    /// compiler emits `span.line`/`span.col` into the bytecode line table so
    /// runtime errors can report `file:line:col` (kaappi#1506).
    span: types.Span = .{},
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
    // Extra lexically-bound names, for lowering paths that have no Compiler
    // (the LLVM native backend passes every name visible at the emission
    // point — this frame's parameters plus the enclosing frames' params,
    // upvalues, locals and boxes — see LLVMEmitter.lexicalNames). Stands in
    // for `compiler.isLexicallyBound` at BOTH places that consult it: the
    // fold gate in isRedefined (#790/#2117) and the special-form-vs-call
    // decision in lowerFormWithMacros (#788/#2118). Feeding it only the
    // immediate frame's parameters, as the native backend once did, left a
    // shadowing binding one level out invisible to both.
    bound_names: ?[]const []const u8 = null,
    // Names that are the target of a `set!` somewhere in the enclosing form
    // being compiled. Folding a call to such a name is unsound: the `set!`
    // may run before the call (e.g. `(lambda () (set! + -) (+ 5 2))`), so the
    // primitive's value at compile time no longer reflects its value at the
    // call site. Populated conservatively (whole-form scan) by the compiler.
    set_targets: ?*const std.StringHashMap(void) = null,
    // GC that owns the Values being lowered, needed by lowerQuote to strip
    // hygiene renames from a quoted datum (#1801). `compiler.gc` already
    // supplies this for ordinary compilation; standalone lowering paths with
    // no Compiler (the LLVM native backend, IR unit tests) set this
    // explicitly when they have one. Deliberately NOT defaulted to the
    // memory.gc_instance threadlocal: some standalone callers (e.g.
    // tests_native.zig) construct their own short-lived GC without ever
    // pointing that threadlocal at it, so trusting it here risked rooting
    // onto a stale or unrelated GC.
    gc: ?*memory.GC = null,
    // Pairs on the active lowering path (#2405), keyed on Object address
    // (stable across collections in this non-moving GC, and holding no
    // Values so the GC never needs to trace it). A datum-label cycle in
    // code position recurses through lowerWithMacros on the same pair
    // forever; membership here means that back-edge. Path membership, not
    // mere prior visitation: shared-but-acyclic structure (the same `#1=`
    // sub-datum in two argument positions) renews legitimately, and each
    // sibling's push/remove is balanced before the next one starts.
    // Scoped correctly because every caller lowers one expression tree per
    // IR instance (compile/compileExprViaIR/compileDefineFromIR/the LLVM
    // emitter's scratch instances each build a fresh IR).
    lower_path: std.AutoHashMapUnmanaged(usize, void) = .empty,

    pub fn init(allocator: std.mem.Allocator) IR {
        return .{
            .allocator = allocator,
            .nodes = .empty,
        };
    }

    /// True when `name` is lexically bound according to the scope this
    /// lowering was given: the enclosing Compiler's own scope, or the
    /// `bound_names` list a Compiler-less path (the LLVM native backend)
    /// supplies in its place. The single answer to "does a binding hide the
    /// keyword/primitive spelled `name` here?", shared by the fold gate
    /// (isRedefined) and the special-form dispatch (lowerFormWithMacros) so
    /// the two can never disagree about the same binding again (#2117/#2118).
    pub fn isLexicallyBound(self: *const IR, name: []const u8) bool {
        if (self.compiler) |c| {
            if (c.isLexicallyBound(name)) return true;
        }
        if (self.bound_names) |names| {
            for (names) |n| {
                if (std.mem.eql(u8, n, name)) return true;
            }
        }
        return false;
    }

    pub fn isRedefined(self: *const IR, name: []const u8) bool {
        // A lexical binding (lambda parameter or enclosing local) shadowing the
        // primitive makes any fold that assumes the built-in's semantics wrong.
        // The globals map never sees these, so consult the lexical scope.
        if (self.isLexicallyBound(name)) return true;
        if (self.compiler) |c| {
            // A truncated `set!` pre-scan means "any name may be reassigned"
            // (kaappi#1775); suppress every fold rather than trust a partial
            // set_targets map. Every caller of isRedefined is an optimization
            // or lint gate (folding here and in tryFoldFromAST/simplifyBooleans,
            // the KP4xxx built-in-call lint in check_lint), so the only effects
            // are: no constant folding in this form, and `kaappi check` stays
            // quiet about its direct built-in calls. Nothing here decides
            // special-form-vs-call lowering.
            if (c.set_targets_all) return true;
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
        self.lower_path.deinit(self.allocator);
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
    .{ "define-property", .define_property },
    .{ "let-syntax", .let_syntax },
    .{ "letrec-syntax", .letrec_syntax },
    .{ "cond-expand", .cond_expand },
});

// Special-form keywords with no `FormKind` of their own. The bool payload is
// the LLVM backend's question, not the compiler's: when this keyword heads an
// *evaluated* form, does that form lower to a `.passthrough` node that
// `emitPassthrough` then hands whole to `kaappi_eval`? An interpreter eval runs
// in the GLOBAL environment, so `true` entries must appear in
// `eval_fallback_form_names` — otherwise an enclosing native lambda frame or
// `let` compiles natively and the eval'd text loses every lexical binding it
// referenced (kaappi#1799: `(define (s xs) (apply + xs))` compiled cleanly and
// failed at run time with "undefined variable 'xs'"). `isSpecialForm`, which every other caller
// uses, ignores the payload entirely.
//
// `false` covers the three kinds of keyword that must stay OUT of the name
// set, because their presence would wrongly reject natively-lowered code
// wholesale:
//
//   - the ones `lowerFormWithMacros` intercepts before the `isSpecialForm`
//     check — `if`, `lambda`, `let`, `define`, … (`letrec`/`letrec*` still
//     reach the name set, via their own `llvm_node_table` entries);
//   - syntax-position keywords that only ever appear *inside* another form:
//     `else`/`=>` inside `cond`/`case` (both natively lowered, kaappi#1496),
//     `_`/`...` inside `syntax-rules` patterns, and `unquote`/`unquote-splicing`
//     inside `quasiquote` (already a fallback form in its own right);
//   - `apply`, which DOES reach `emitPassthrough` as an evaluated head but is
//     lowered natively there inside a lexical scope (emitApplyForm →
//     @kaappi_apply, kaappi#1803), so the enclosing frame keeps its native
//     compilation instead of paying the whole-function fallback.
const other_special_forms = std.StaticStringMap(bool).initComptime(.{
    .{ "quote", false },
    .{ "if", false },
    .{ "lambda", false },
    .{ "define", false },
    .{ "set!", false },
    .{ "begin", false },
    .{ "and", false },
    .{ "or", false },
    .{ "when", false },
    .{ "unless", false },
    .{ "let", false },
    .{ "let*", false },
    .{ "letrec", false },
    .{ "letrec*", false },
    .{ "syntax-error", true },
    .{ "syntax-rules", true },
    .{ "apply", false },
    .{ "call-with-values", true },
    .{ "call-with-current-continuation", true },
    .{ "call/cc", true },
    .{ "eval", true },
    .{ "define-record-type", true },
    .{ "import", true },
    .{ "define-library", true },
    .{ "include", true },
    .{ "include-ci", true },
    .{ "else", false },
    .{ "=>", false },
    .{ "_", false },
    .{ "...", false },
    .{ "unquote", false },
    .{ "unquote-splicing", false },
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
        // #2405: a car-side datum-label cycle (`(display #1=(p #1# q))`)
        // re-enters this function on the same pair at ever-increasing depth
        // — every recursive position routes through this one funnel — until
        // the native stack aborts, uncatchably. Membership on the active
        // path means exactly that back-edge (see IR.lower_path); a cycle
        // has no leaves to bottom out at, so it is a named compile error,
        // not an internal one. Quoted data never passes through here —
        // lowerQuote makes the whole datum a constant without walking it —
        // so circular *data* keeps working (#1954 controls).
        const path_key = @intFromPtr(types.toObject(expr));
        if (ir.lower_path.contains(path_key)) return compiler_mod.circularFormError();
        ir.lower_path.put(ir.allocator, path_key, {}) catch return CompileError.OutOfMemory;
        defer _ = ir.lower_path.remove(path_key);
        const node = lowerFormWithMacros(ir, expr, macros) catch |err| {
            // Record the failing form's span for the compile-error reporter.
            // Lowering is post-order, so the innermost pair fails first on the
            // way out; `noteCompileErrorSpan` keeps that first (deepest) span
            // and later frames don't overwrite it (kaappi#1506).
            if (ir.compiler) |c| {
                if (c.gc.source_spans.get(expr)) |sp| {
                    compiler_mod.noteCompileErrorSpan(sp);
                }
            }
            return err;
        };
        if (ir.compiler) |c| {
            if (c.gc.source_spans.get(expr)) |sp| {
                node.ann.span = sp;
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
        //
        // `isLexicallyBound` answers from the Compiler's scope when there is
        // one and from `bound_names` otherwise, so the LLVM native backend —
        // which lowers every lambda/let body through a scratch IR with no
        // Compiler — honours the binding too (#2118). Without that it read
        // `(define (f if) (if 1 2))` as the special form and printed 2 where
        // the interpreter printed 99.
        const is_shadowed = std.mem.eql(u8, effective_name, name) and
            ir.isLexicallyBound(name);

        if (!is_shadowed) {
            // R7RS has no reserved words: an imported macro may shadow a
            // special form keyword (e.g. SRFI-219 redefines `define`).
            // Check macros BEFORE special forms so the macro wins.
            if (ir.compiler) |c| {
                if (c.lookupMacro(name) != null) return ir.makePassthrough(expr);
            } else if (macros) |m| {
                if (m.get(name) != null) return ir.makePassthrough(expr);
            }

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

            // A compiler-synthesized reference to a special form — the
            // let-values/let*-values/define-values/case-lambda desugarings
            // mint __kaappi_base__apply / _call-with-values (#1715) — must
            // be dispatched exactly like its bare spelling: the tail-position
            // superinstructions in compileForm recognize it there, and the
            // base-binding prefix marks it immune to redefinition so the
            // #2033 gate skips it. Lowered as a plain call node it would
            // bypass compileForm entirely and lose the fast path.
            if (globals_mod.stripBaseBindingPrefix(effective_name)) |base_name| {
                if (isSpecialForm(base_name)) return ir.makePassthrough(expr);
            }

            if (isSpecialForm(effective_name)) return ir.makePassthrough(expr);
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

/// Master switch for IR optimization: when false, `lowerAndOptimize` skips
/// the five optimization passes and `tryFoldFromAST` stops folding during
/// lowering. Analysis (`markTailPositions`) always runs — it is required for
/// correctness, not an optimization. Threadlocal (like `vm_instance`) so
/// SRFI-18 child threads keep the default regardless of the parent's setting.
/// Toggled by the `--no-ir-opt` CLI flag and by the differential fuzz oracle
/// in tests_fuzz.zig (#1393).
pub threadlocal var optimize_enabled: bool = true;

pub fn lowerAndOptimize(
    ir_instance: *IR,
    expr: Value,
    macros: ?*std.StringHashMap(Value),
    is_tail: bool,
) CompileError!*Node {
    // `--timings` (kaappi#1515): lowering (AST→IR, with macro uses deferred to
    // passthrough nodes) and analysis are one self-timed stage; the five
    // optimization passes are another. Nested lowering triggered later by macro
    // expansion during emission is credited correctly by the self-time stack.
    timings.begin(.lower);
    var node = lowerWithMacros(ir_instance, expr, macros) catch |err| {
        timings.end();
        return err;
    };
    markTailPositions(node, is_tail);
    timings.end();
    // Lint hook for `kaappi check` (kaappi#1511). Inert (one null test) outside a
    // check run. Walked before the optimization passes so constant folding can't
    // hide a call the lint would flag.
    @import("check_lint.zig").maybeWalk(ir_instance, node);
    if (!optimize_enabled) return node;
    timings.begin(.optimize);
    defer timings.end();
    node = foldConstants(ir_instance, node);
    node = eliminateDeadBranches(ir_instance, node);
    node = simplifyBooleans(ir_instance, node);
    node = eliminateIdentity(ir_instance, node);
    node = simplifyBegin(ir_instance, node);
    return node;
}

// The scope-less `lowerSingleExpr` / `lowerSingleExprTail` that used to live
// here are gone (kaappi#2117/#2118). Their only callers were the LLVM native
// backend's re-lowering sites, and a scratch IR built with neither
// `bound_names` nor `set_targets` answers "is this name bound here?" and "may
// this name's value change?" as if the program had no lexical scope at all —
// which is exactly how a shadowed keyword lowered as the special form and a
// `set!`-clobbered primitive folded to its stale value. `LLVMEmitter.lowerScoped`
// replaces both and cannot be called without a scope.

fn lowerIf(ir: *IR, args: Value, macros: ?*std.StringHashMap(Value)) CompileError!*Node {
    if (args == types.NIL) return CompileError.InvalidSyntax;
    const test_expr = types.car(args);
    const rest = types.cdr(args);
    if (rest == types.NIL) return CompileError.InvalidSyntax;
    const consequent = types.car(rest);
    const rest2 = types.cdr(rest);

    // #2405: `if` consumes its alternate from a position and never walks
    // what follows — `(if a b c . junk)` has always been silently accepted —
    // but a CYCLIC tail means the form contains itself, and compiling the
    // `if` symbol as the alternate is garbage-in-garbage-out (#0=(if #t 1
    // . #0#) printed 1). Detection-only: the lax acceptance of extra
    // non-cyclic forms is unchanged.
    if (rest2 != types.NIL and compiler_mod.spineCyclic(types.cdr(rest2)))
        return compiler_mod.circularFormError();

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
    const datum = types.car(args);
    // A template-introduced identifier inside `(quote ...)` is hygiene-
    // renamed like any other during expansion (#1801); strip it back to its
    // base name now that this quote is being compiled into a real literal
    // Value, so the rename never leaks into the running program.
    const gc: ?*memory.GC = ir.gc orelse if (ir.compiler) |c| c.gc else null;
    const stripped = if (gc) |g| expander.stripHygieneFromDatum(g, datum) catch return CompileError.OutOfMemory else datum;
    return ir.makeConst(stripped);
}

fn lowerBegin(ir: *IR, args: Value, macros: ?*std.StringHashMap(Value)) CompileError!*Node {
    var nodes: std.ArrayList(*Node) = .empty;
    defer nodes.deinit(ir.allocator);

    // A literal `begin` lowers every child in one eager pass, all before any
    // of them compile. A `define-syntax` sibling's real registration is a
    // side effect of *compiling* its node (compiler_macro.compileDefineSyntax),
    // not of lowering it, so without this, a later sibling lowered in this
    // same pass never sees it via lookupMacro and its macro use lowers as a
    // plain call instead of deferring to real expansion (kaappi#1772).
    // Reserve each literal define-syntax sibling's name the moment it's
    // reached, before lowering the next one — mirroring how
    // compiler_lambda.scanBodyDefs resolves the identical problem for a
    // body's own leading definitions. A name already visible via lookupMacro
    // (a real transformer from this scope or an enclosing one) is left
    // untouched, so this can never clobber a real value. The placeholder
    // itself is never read as a transformer: begin's children compile in the
    // same left-to-right order this loop lowers them in, so
    // compileDefineSyntax overwrites it with the real transformer strictly
    // before any later sibling compiles. If a later sibling fails to lower,
    // roll back every reservation this call made, so the failure leaves the
    // macro table exactly as it found it.
    var reserved: std.ArrayList([]const u8) = .empty;
    defer reserved.deinit(ir.allocator);
    errdefer {
        if (macros) |m| {
            for (reserved.items) |rn| _ = m.remove(rn);
        }
    }

    var walk = compiler_mod.SpineWalk.init(args);
    while (types.isPair(walk.cur)) : (walk.next()) {
        if (walk.cyclic()) return compiler_mod.circularFormError();
        const form = types.car(walk.cur);
        try reserveLiteralDefineSyntax(ir, form, macros, &reserved);
        nodes.append(ir.allocator, try lowerWithMacros(ir, form, macros)) catch return CompileError.OutOfMemory;
    }
    if (walk.cur != types.NIL) return CompileError.InvalidSyntax;
    return ir.makeBegin(nodes.items);
}

/// If `form` is a literal, unshadowed `(define-syntax <name> <spec>)` — the
/// same test `lowerFormWithMacros` applies a moment later when it actually
/// lowers `form` — reserve `<name>` in the macro table backing this lowering
/// pass, so a sibling lowered right after this call sees it via lookupMacro.
/// No-op when there's no mutable macro table to reserve into, when `form`
/// isn't really this special form (shadowed by a lexical binding, or
/// `define-syntax` itself is shadowed by an enclosing macro), or when
/// `<name>` is already visible — nothing to fix in that last case, and
/// overwriting it would risk losing a real transformer if this define-syntax
/// node is never actually compiled (e.g. a later sibling fails to lower).
fn reserveLiteralDefineSyntax(
    ir: *IR,
    form: Value,
    macros: ?*std.StringHashMap(Value),
    reserved: *std.ArrayList([]const u8),
) CompileError!void {
    const target = macros orelse return;
    if (!types.isPair(form)) return;
    const head = types.car(form);
    if (!types.isSymbol(head)) return;
    const name = types.symbolName(head);
    const effective_name = types.stripHygienicPrefix(name);
    if (!std.mem.eql(u8, effective_name, "define-syntax")) return;

    const is_shadowed = std.mem.eql(u8, effective_name, name) and
        if (ir.compiler) |c| c.isLexicallyBound(name) else false;
    if (is_shadowed) return;

    const shadowed_by_macro = if (ir.compiler) |c|
        c.lookupMacro(name) != null
    else
        target.get(name) != null;
    if (shadowed_by_macro) return;

    const ds_args = types.cdr(form);
    if (!types.isPair(ds_args)) return;
    const keyword = types.car(ds_args);
    if (!types.isSymbol(keyword)) return;
    const kw_name = types.symbolName(keyword);

    if (target.contains(kw_name)) return;
    target.put(kw_name, types.VOID) catch return CompileError.OutOfMemory;
    reserved.append(ir.allocator, kw_name) catch return CompileError.OutOfMemory;
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
    const rest = types.cdr(args);
    if (rest == types.NIL) return CompileError.InvalidSyntax;

    if (types.isSymbol(name)) {
        return ir.makeSet(name, types.car(rest));
    }

    // SRFI-17 generalized set!: (set! (proc arg ...) val)
    // Desugar to: ((setter proc) arg ... val)
    // Requires (srfi 17) imported so the global `setter` is defined.
    // Needs ir.compiler for symbol interning; the LLVM native backend
    // (compiler-less lowering) falls through to InvalidSyntax — it
    // would need an eval fallback for this form anyway.
    if (types.isPair(name)) {
        const c = ir.compiler orelse return CompileError.InvalidSyntax;
        const proc = types.car(name);
        const proc_args = types.cdr(name);
        const val_expr = types.car(rest);

        // Build (setter proc) call node
        const setter_sym = c.gc.allocSymbol("setter") catch return CompileError.OutOfMemory;
        const setter_ref = try ir.makeGlobalRef(setter_sym);
        const proc_node = try lowerWithMacros(ir, proc, null);
        const setter_call = try ir.makeCall(setter_ref, &.{proc_node});

        // Collect proc_args + val into argument list
        var arg_nodes: std.ArrayList(*Node) = .empty;
        defer arg_nodes.deinit(ir.allocator);
        // #2405 (CodeRabbit on PR #2413): the SRFI-17 target's operand spine
        // is a raw walk — `(set! #0=(f 1 . #0#) 3)` spun it forever, the one
        // cycle shape that never routes through lowerWithMacros.
        var cur = compiler_mod.SpineWalk.init(proc_args);
        while (cur.cur != types.NIL) : (cur.next()) {
            if (!types.isPair(cur.cur)) return CompileError.InvalidSyntax;
            if (cur.cyclic()) return compiler_mod.circularFormError();
            arg_nodes.append(ir.allocator, try lowerWithMacros(ir, types.car(cur.cur), null)) catch return CompileError.OutOfMemory;
        }
        arg_nodes.append(ir.allocator, try lowerWithMacros(ir, val_expr, null)) catch return CompileError.OutOfMemory;

        return ir.makeCall(setter_call, arg_nodes.items);
    }

    return CompileError.InvalidSyntax;
}

fn lowerList(ir: *IR, args: Value, tag: NodeTag, macros: ?*std.StringHashMap(Value)) CompileError!*Node {
    var nodes: std.ArrayList(*Node) = .empty;
    defer nodes.deinit(ir.allocator);
    // #2405: and/or bodies are spines — a datum-label cycle spins forever.
    var walk = compiler_mod.SpineWalk.init(args);
    while (types.isPair(walk.cur)) : (walk.next()) {
        if (walk.cyclic()) return compiler_mod.circularFormError();
        nodes.append(ir.allocator, try lowerWithMacros(ir, types.car(walk.cur), macros)) catch return CompileError.OutOfMemory;
    }
    if (walk.cur != types.NIL) return CompileError.InvalidSyntax;
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
    // #2405: when/unless bodies are spines — a datum-label cycle spins forever.
    var walk = compiler_mod.SpineWalk.init(types.cdr(args));
    while (types.isPair(walk.cur)) : (walk.next()) {
        if (walk.cyclic()) return compiler_mod.circularFormError();
        nodes.append(ir.allocator, try lowerWithMacros(ir, types.car(walk.cur), macros)) catch return CompileError.OutOfMemory;
    }
    if (walk.cur != types.NIL) return CompileError.InvalidSyntax;
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
    // #2405: a spine cycle (`#0=(display 1 . #0#)`) used to spin this walk
    // until the 256-argument cap reported KP9001 "internal error"; the
    // tortoise-and-hare guard names the cycle instead, and finite improper
    // tails still fail the isPair check exactly as before.
    var walk = compiler_mod.SpineWalk.init(types.cdr(expr));
    while (types.isPair(walk.cur)) : (walk.next()) {
        if (walk.cyclic()) return compiler_mod.circularFormError();
        if (nargs >= 256) return CompileError.InternalLimit;
        arg_buf[nargs] = try lowerWithMacros(ir, types.car(walk.cur), macros);
        nargs += 1;
    }
    if (walk.cur != types.NIL) return CompileError.InvalidSyntax;

    return ir.makeCall(op_node, arg_buf[0..nargs]);
}

fn tryFoldFromAST(ir: *IR, expr: Value) ?*Node {
    if (!optimize_enabled) return null;
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
// Known-global vocabulary
//
// This list outlived the `identifyPrimitives` IR analysis pass it was written
// for (removed in v0.13.0). Its one remaining caller is the LLVM backend's
// `isKnownOrReservedGlobal` (`llvm_emit.zig`), deciding global-vs-lexical for
// free-variable analysis. It is not an IR annotation source — nothing here
// marks nodes — so do not describe it as an analysis pass.
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
    "list-ref",
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
