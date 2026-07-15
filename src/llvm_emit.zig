const std = @import("std");
const ir = @import("ir.zig");
const types = @import("types.zig");
const printer = @import("printer.zig");
const native_decls = @import("native_decls.zig");

const Value = types.Value;

// NaN-box encoding constants for inline primitive emission. Derived at comptime
// from types.zig so the emitted IR always matches the runtime's value
// representation — no hand-transcribed magic numbers to drift out of sync.
// These describe only the immediate Value bit layout (fixnum tag, payload, nil,
// booleans), which is stable; heap-object field offsets (auto-layout structs)
// are deliberately NOT encoded here, so car/cdr/cons stay as runtime calls.
const nanbox = struct {
    // High 16 bits (v >> 48) that mark a fixnum: 0xFFFD.
    const fix_tag_hi: u64 = types.makeFixnum(0) >> 48;
    // Base fixnum tag bits, OR'd with a 48-bit payload to box an integer.
    const fix_base: i64 = @bitCast(types.makeFixnum(0));
    // Mask selecting the 48-bit fixnum payload.
    const payload_mask: i64 = std.math.maxInt(u48);
    // Inclusive range of integers representable as a fixnum (i48).
    const fix_min: i64 = std.math.minInt(i48);
    const fix_max: i64 = std.math.maxInt(i48);
    const nil: i64 = @bitCast(types.NIL);
    const true_val: i64 = @bitCast(types.TRUE);
    const false_val: i64 = @bitCast(types.FALSE);
};

const ArithOp = enum {
    add,
    sub,
    mul,

    // LLVM checked-arithmetic intrinsic that mirrors the runtime's
    // @addWithOverflow / @subWithOverflow / @mulWithOverflow fast path.
    fn overflowIntrinsic(self: ArithOp) []const u8 {
        return switch (self) {
            .add => "@llvm.sadd.with.overflow.i64",
            .sub => "@llvm.ssub.with.overflow.i64",
            .mul => "@llvm.smul.with.overflow.i64",
        };
    }

    fn fromName(name: []const u8) ?ArithOp {
        if (std.mem.eql(u8, name, "+")) return .add;
        if (std.mem.eql(u8, name, "-")) return .sub;
        if (std.mem.eql(u8, name, "*")) return .mul;
        return null;
    }
};

const NativeLambda = struct {
    llvm_name: []const u8,
    arity: u8,
    is_variadic: bool,
};

fn nameInList(names: []const []const u8, name: []const u8) bool {
    for (names) |n| {
        if (std.mem.eql(u8, n, name)) return true;
    }
    return false;
}

// Conservative "evaluating this node might allocate (and therefore trigger a
// GC)". Used to elide the shadow-stack rooting that only exists to keep an
// already-computed operand alive while a *later* operand is evaluated: if the
// later operand cannot allocate, nothing can collect, so the root push/pop pair
// (two cross-module runtime calls) is pure overhead. Errs toward `true` — only
// leaves whose emission is provably allocation-free return `false`:
//   - immediate constants (fixnum/bool/char/nil) lower to a bare `add i64 0, K`;
//     heap constants (string/symbol/pair) call make_string/intern_symbol/eval.
//   - variable references (global_ref) always lower to a load or a
//     non-allocating runtime call (global_lookup / box_ref).
// Every compound form may allocate, so it stays `true`.
fn nodeMayAllocate(node: *const ir.Node) bool {
    return switch (node.tag) {
        .constant => types.isPointer(node.data.constant),
        .global_ref => false,
        else => true,
    };
}

pub const LLVMEmitter = struct {
    buf: std.ArrayList(u8),
    symbols: std.StringHashMap(u32),
    string_decls: std.ArrayList([]const u8),
    lambda_defs: std.ArrayList([]const u8),
    native_fns: std.StringHashMap(NativeLambda),
    rebound_globals: std.StringHashMap(void),
    params: ?std.StringHashMap(u8),
    upvalues: ?std.StringHashMap(u8),
    tmp_counter: u32,
    label_counter: u32,
    string_counter: u32,
    sym_counter: u32,
    lambda_counter: u32,
    // One global cache slot is emitted per eval-fallback call site (#1494);
    // this counts them and names each `@.eval_cache.N`. Like the other module
    // counters (string/sym/lambda) it is monotonic across the whole module and
    // deliberately NOT part of SavedScope.
    eval_cache_counter: u32,
    arena: std.heap.ArenaAllocator,
    backing_alloc: std.mem.Allocator,
    current_fn_name: ?[]const u8 = null,
    body_label: ?[]const u8 = null,
    current_block: []const u8 = "entry",
    rest_param_alloca: ?[]const u8 = null,
    rest_param_name: ?[]const u8 = null,
    locals: ?std.StringHashMap([]const u8) = null,
    // Boxed variables in the current frame (assignment conversion, #1497):
    // name -> the alloca that holds the box POINTER. A boxed variable is both
    // captured by a nested lambda and mutated; reads go through kaappi_box_ref
    // and writes through kaappi_box_set, and nested closures capture the box
    // pointer, restoring the interpreter's by-location semantics. Checked
    // before params/upvalues in name resolution.
    boxes: ?std.StringHashMap([]const u8) = null,
    // Number of box-slot roots pushed at the current frame's entry that must be
    // popped before the frame's `ret` (see emitLambdaFunction / the closure
    // tier). Boxed frames disable tail-call emission so there is exactly one
    // `ret` at which to pop.
    frame_box_roots: usize = 0,

    pub const SavedScope = struct {
        buf: std.ArrayList(u8),
        params: ?std.StringHashMap(u8),
        upvalues: ?std.StringHashMap(u8),
        tmp_counter: u32,
        label_counter: u32,
        current_fn_name: ?[]const u8,
        body_label: ?[]const u8,
        current_block: []const u8,
        rest_param_alloca: ?[]const u8,
        rest_param_name: ?[]const u8,
        locals: ?std.StringHashMap([]const u8),
        boxes: ?std.StringHashMap([]const u8),
        frame_box_roots: usize,
    };

    pub fn saveScope(self: *LLVMEmitter) SavedScope {
        return .{
            .buf = self.buf,
            .params = self.params,
            .upvalues = self.upvalues,
            .tmp_counter = self.tmp_counter,
            .label_counter = self.label_counter,
            .current_fn_name = self.current_fn_name,
            .body_label = self.body_label,
            .current_block = self.current_block,
            .rest_param_alloca = self.rest_param_alloca,
            .rest_param_name = self.rest_param_name,
            .locals = self.locals,
            .boxes = self.boxes,
            .frame_box_roots = self.frame_box_roots,
        };
    }

    pub fn restoreScope(self: *LLVMEmitter, s: SavedScope) void {
        self.buf = s.buf;
        self.params = s.params;
        self.upvalues = s.upvalues;
        self.tmp_counter = s.tmp_counter;
        self.label_counter = s.label_counter;
        self.current_fn_name = s.current_fn_name;
        self.body_label = s.body_label;
        self.current_block = s.current_block;
        self.rest_param_alloca = s.rest_param_alloca;
        self.rest_param_name = s.rest_param_name;
        self.locals = s.locals;
        self.boxes = s.boxes;
        self.frame_box_roots = s.frame_box_roots;
    }

    pub fn init(backing: std.mem.Allocator) LLVMEmitter {
        return .{
            .buf = .empty,
            .symbols = std.StringHashMap(u32).init(backing),
            .string_decls = .empty,
            .lambda_defs = .empty,
            .native_fns = std.StringHashMap(NativeLambda).init(backing),
            .rebound_globals = std.StringHashMap(void).init(backing),
            .params = null,
            .upvalues = null,
            .tmp_counter = 0,
            .label_counter = 0,
            .string_counter = 0,
            .sym_counter = 0,
            .lambda_counter = 0,
            .eval_cache_counter = 0,
            .arena = std.heap.ArenaAllocator.init(backing),
            .backing_alloc = backing,
        };
    }

    pub fn allocator(self: *LLVMEmitter) std.mem.Allocator {
        return self.arena.allocator();
    }

    pub fn deinit(self: *LLVMEmitter) void {
        self.buf.deinit(self.backing_alloc);
        self.symbols.deinit();
        self.string_decls.deinit(self.backing_alloc);
        self.lambda_defs.deinit(self.backing_alloc);
        self.native_fns.deinit();
        self.rebound_globals.deinit();
        self.arena.deinit();
    }

    pub fn emitProgram(self: *LLVMEmitter, nodes: []const *ir.Node) EmitError!void {
        // Emit body into a separate buffer to collect string decls
        var body: std.ArrayList(u8) = .empty;
        defer body.deinit(self.backing_alloc);
        const saved_buf = self.buf;
        self.buf = body;

        self.write("  %vm = call ptr @kaappi_runtime_init()\n") catch return error.OutOfMemory;
        for (nodes) |node| {
            _ = self.emitNode(node) catch return error.OutOfMemory;
        }

        body = self.buf;
        self.buf = saved_buf;

        // Now emit preamble + symbols + string decls + body
        try self.emitPreamble();

        // Emit all symbol constants collected during body emission
        var sym_iter = self.symbols.iterator();
        try self.write("\n");
        while (sym_iter.next()) |entry| {
            const name = entry.key_ptr.*;
            const id = entry.value_ptr.*;
            try self.print("@.sym.{d} = private unnamed_addr constant [{d} x i8] c\"", .{ id, name.len });
            for (name) |byte| {
                if (byte >= 0x20 and byte < 0x7F and byte != '"' and byte != '\\') {
                    try self.print("{c}", .{byte});
                } else {
                    try self.print("\\{X:0>2}", .{byte});
                }
            }
            try self.write("\"\n");
        }

        for (self.string_decls.items) |decl| {
            try self.write(decl);
        }

        // One mutable global per eval-fallback call site (#1494): 0 until the
        // form is compiled, then the cached Function value. Emitted here, at
        // module scope, so both the top-level body and lambda bodies (in
        // lambda_defs) can reference the slots they were assigned.
        var cache_slot: u32 = 0;
        while (cache_slot < self.eval_cache_counter) : (cache_slot += 1) {
            try self.print("@.eval_cache.{d} = internal global i64 0\n", .{cache_slot});
        }

        for (self.lambda_defs.items) |def| {
            try self.write("\n");
            try self.write(def);
        }

        try self.write("\ndefine i32 @main() {\nentry:\n");
        try self.write(body.items);

        try self.write("\n  call void @kaappi_runtime_deinit(ptr %vm)\n");
        try self.write("  ret i32 0\n}\n");
    }

    pub fn emitNode(self: *LLVMEmitter, node: *const ir.Node) EmitError![]const u8 {
        return switch (node.tag) {
            .constant => try self.emitConstant(node.data.constant),
            .global_ref => try self.emitGlobalRef(node.data.global_ref),
            .call => try self.emitCallNode(node),
            .begin => try self.emitBegin(node.data.begin),
            .@"if" => try self.emitIf(node.data.@"if"),
            .and_form => try self.emitAnd(node.data.and_form),
            .or_form => try self.emitOr(node.data.or_form),
            .when_form => try self.emitWhen(node.data.when_form),
            .unless_form => try self.emitUnless(node.data.unless_form),
            .define => try self.emitDefine(node.data.define),
            .set_form => try self.emitSet(node.data.set_form),
            .lambda => try self.emitLambda(node.data.lambda),
            .let_form => try self.emitLet(node.data.let_form.args, false, node.ann.is_tail),
            .let_star => try self.emitLet(node.data.let_star.args, true, node.ann.is_tail),
            .letrec => try self.emitLetEvalFallback(node.data.letrec.args, "letrec"),
            .letrec_star => try self.emitLetEvalFallback(node.data.letrec_star.args, "letrec*"),
            .passthrough => try self.emitPassthrough(node.data.passthrough),
            .sexpr_form => try self.emitSexprEval(node),
        };
    }

    fn emitConstant(self: *LLVMEmitter, value: Value) EmitError![]const u8 {
        if (types.isString(value)) {
            const str_data = types.toObject(value).as(types.SchemeString).data;
            const str_name = try self.internString(str_data);
            const tmp = try self.freshTemp();
            try self.print("  {s} = call i64 @kaappi_make_string(ptr %vm, ptr {s}, i64 {d})\n", .{ tmp, str_name, str_data.len });
            return tmp;
        }
        if (types.isSymbol(value)) {
            const sym_data = types.symbolName(value);
            const str_name = try self.internString(sym_data);
            const tmp = try self.freshTemp();
            try self.print("  {s} = call i64 @kaappi_intern_symbol(ptr %vm, ptr {s}, i64 {d})\n", .{ tmp, str_name, sym_data.len });
            return tmp;
        }
        if (types.isPointer(value)) {
            return self.emitQuotedEvalExpr(value);
        }
        return self.emitImm(@bitCast(value));
    }

    // Mirrors emitGlobalRef's lexical resolution order (locals, rest param,
    // params, upvalues). Also consulted by the closure-tier free-variable
    // analysis in llvm_emit_lambda.zig: a shadowed name is a capture even
    // when a known global of the same name exists.
    pub fn isNameShadowed(self: *LLVMEmitter, name: []const u8) bool {
        if (self.boxes) |bx| {
            if (bx.get(name) != null) return true;
        }
        if (self.locals) |loc| {
            if (loc.get(name) != null) return true;
        }
        if (self.rest_param_name) |rp_name| {
            if (std.mem.eql(u8, name, rp_name)) return true;
        }
        if (self.params) |p| {
            if (p.get(name) != null) return true;
        }
        if (self.upvalues) |uv| {
            if (uv.get(name) != null) return true;
        }
        return false;
    }

    fn emitGlobalRef(self: *LLVMEmitter, sym: Value) EmitError![]const u8 {
        if (!types.isSymbol(sym)) return error.UnsupportedNodeType;
        const name = types.symbolName(sym);

        // A boxed variable's slot holds the box pointer; read through the box
        // so a set! from any sibling closure over the same binding is visible.
        if (self.boxes) |bx| {
            if (bx.get(name)) |box_alloca| {
                const boxptr = try self.freshTemp();
                try self.print("  {s} = load i64, ptr {s}\n", .{ boxptr, box_alloca });
                const tmp = try self.freshTemp();
                try self.print("  {s} = call i64 @kaappi_box_ref(i64 {s})\n", .{ tmp, boxptr });
                return tmp;
            }
        }

        if (self.locals) |loc| {
            if (loc.get(name)) |alloca_name| {
                const tmp = try self.freshTemp();
                try self.print("  {s} = load i64, ptr {s}\n", .{ tmp, alloca_name });
                return tmp;
            }
        }

        if (self.rest_param_name) |rp_name| {
            if (std.mem.eql(u8, name, rp_name)) {
                const tmp = try self.freshTemp();
                try self.print("  {s} = load i64, ptr {s}\n", .{ tmp, self.rest_param_alloca.? });
                return tmp;
            }
        }

        if (self.params) |p| {
            if (p.get(name)) |idx| {
                const tmp = try self.freshTemp();
                const gep = try self.freshTemp();
                try self.print("  {s} = getelementptr i64, ptr %args, i64 {d}\n", .{ gep, idx });
                try self.print("  {s} = load i64, ptr {s}\n", .{ tmp, gep });
                return tmp;
            }
        }

        if (self.upvalues) |uv| {
            if (uv.get(name)) |idx| {
                const tmp = try self.freshTemp();
                const gep = try self.freshTemp();
                try self.print("  {s} = getelementptr i64, ptr %upvalues, i64 {d}\n", .{ gep, idx });
                try self.print("  {s} = load i64, ptr {s}\n", .{ tmp, gep });
                return tmp;
            }
        }

        const sym_name = try self.internSymbol(name);
        const tmp = try self.freshTemp();
        try self.print("  {s} = call i64 @kaappi_global_lookup(ptr %vm, ptr {s}, i64 {d})\n", .{ tmp, sym_name, name.len });
        return tmp;
    }

    fn emitCallNode(self: *LLVMEmitter, node: *const ir.Node) EmitError![]const u8 {
        const call = node.data.call;
        const is_tail = node.ann.is_tail;

        if (call.operator.tag == .global_ref and types.isSymbol(call.operator.data.global_ref)) {
            const op_name = types.symbolName(call.operator.data.global_ref);

            const is_shadowed = self.isNameShadowed(op_name);

            if (!is_shadowed and is_tail) {
                if (self.current_fn_name) |fn_name| {
                    if (self.body_label) |body_lbl| {
                        if (std.mem.eql(u8, op_name, fn_name)) {
                            if (self.native_fns.get(fn_name)) |self_fn| {
                                if (call.args.len == self_fn.arity) {
                                    return self.emitSelfTailCall(call.args, body_lbl);
                                }
                            }
                        }
                    }
                }
            }

            if (!is_shadowed) {
                if (self.native_fns.get(op_name)) |native| {
                    const arity_ok = if (native.is_variadic)
                        call.args.len >= native.arity
                    else
                        call.args.len == native.arity;
                    if (arity_ok) {
                        return self.emitDirectCall(native.llvm_name, call.args, is_tail);
                    }
                }
            }
            if (!is_shadowed and !self.rebound_globals.contains(op_name)) {
                if (call.args.len == 2) {
                    if (self.tryEmitInlineBinary(op_name, call.args)) |result| return result;
                }
                if (call.args.len == 1) {
                    if (self.tryEmitInlineUnary(op_name, call.args[0])) |result| return result;
                }
            }
        }

        const callee = try self.emitNode(call.operator);
        const nargs = call.args.len;

        var root_count: usize = 0;
        if (nargs > 0) {
            try self.emitRootPush(callee);
            root_count += 1;
        }

        const arg_tmps = self.allocator().alloc([]const u8, nargs) catch return error.OutOfMemory;
        for (call.args, 0..) |arg, i| {
            arg_tmps[i] = try self.emitNode(arg);
            if (i + 1 < nargs) {
                try self.emitRootPush(arg_tmps[i]);
                root_count += 1;
            }
        }

        try self.emitPopRoots(root_count);

        const result = try self.freshTemp();

        if (nargs == 0) {
            const call_prefix: []const u8 = if (is_tail) "tail call" else "call";
            try self.print("  {s} = {s} i64 @kaappi_call_scheme(ptr %vm, i64 {s}, ptr null, i64 0)\n", .{ result, call_prefix, callee });
        } else {
            const args_alloca = try self.freshTemp();
            try self.print("  {s} = alloca [{d} x i64], align 8\n", .{ args_alloca, nargs });

            for (0..nargs) |i| {
                const gep = try self.freshTemp();
                try self.print("  {s} = getelementptr [1 x i64], ptr {s}, i64 {d}\n", .{ gep, args_alloca, i });
                try self.print("  store i64 {s}, ptr {s}\n", .{ arg_tmps[i], gep });
            }

            try self.print("  {s} = call i64 @kaappi_call_scheme(ptr %vm, i64 {s}, ptr {s}, i64 {d})\n", .{ result, callee, args_alloca, nargs });
        }

        if (is_tail) {
            try self.print("  ret i64 {s}\n", .{result});
            try self.emitOrphanAfterTail();
        }

        return result;
    }

    fn emitSelfTailCall(self: *LLVMEmitter, args: []const *ir.Node, body_lbl: []const u8) EmitError![]const u8 {
        const arg_tmps = self.allocator().alloc([]const u8, args.len) catch return error.OutOfMemory;
        var root_count: usize = 0;
        for (args, 0..) |arg, i| {
            arg_tmps[i] = try self.emitNode(arg);
            if (i + 1 < args.len) {
                try self.emitRootPush(arg_tmps[i]);
                root_count += 1;
            }
        }
        try self.emitPopRoots(root_count);

        for (0..args.len) |i| {
            const gep = try self.freshTemp();
            try self.print("  {s} = getelementptr i64, ptr %args, i64 {d}\n", .{ gep, i });
            try self.print("  store i64 {s}, ptr {s}\n", .{ arg_tmps[i], gep });
        }

        try self.print("  br label %{s}\n", .{body_lbl});

        try self.emitOrphanAfterTail();

        return self.emitImm(@bitCast(types.VOID));
    }

    fn emitBegin(self: *LLVMEmitter, exprs: []const *ir.Node) EmitError![]const u8 {
        var last: []const u8 = "";
        for (exprs) |expr| {
            last = try self.emitNode(expr);
        }
        return last;
    }

    fn emitLetFallback(self: *LLVMEmitter, args: Value, sequential: bool) EmitError![]const u8 {
        // The let form is about to be evaluated in the global environment;
        // bind the enclosing frame's params/rest/upvalues as globals first
        // or references to them inside the form come up undefined (#1410).
        try lambda.bindParamsAsGlobals(self);
        const keyword = if (sequential) "let*" else "let";
        // Build `(let bindings body ...)` by iterating the args list elements.
        // The args value is `(bindings body ...)` — a list whose elements must
        // be printed individually (not as one list) to avoid extra parens.
        var source_buf: std.ArrayList(u8) = .empty;
        defer source_buf.deinit(self.backing_alloc);
        source_buf.appendSlice(self.backing_alloc, "(") catch return error.OutOfMemory;
        source_buf.appendSlice(self.backing_alloc, keyword) catch return error.OutOfMemory;
        var current = args;
        while (current != types.NIL and types.isPair(current)) {
            source_buf.append(self.backing_alloc, ' ') catch return error.OutOfMemory;
            const elem = types.car(current);
            const elem_str = printer.valueToString(self.backing_alloc, elem, .write) catch return error.OutOfMemory;
            defer self.backing_alloc.free(elem_str);
            source_buf.appendSlice(self.backing_alloc, elem_str) catch return error.OutOfMemory;
            current = types.cdr(current);
        }
        source_buf.append(self.backing_alloc, ')') catch return error.OutOfMemory;
        return self.emitCachedEval(source_buf.items);
    }

    // Abandon a partially emitted native let and compile the whole form via
    // the interpreter instead. Pops the GC roots already pushed for emitted
    // bindings (the natively computed values are dead once the interpreter
    // re-evaluates the form; leaving their roots pushed would leak stack
    // slots into the GC root set on every execution of this code path).
    fn abandonLetForFallback(self: *LLVMEmitter, args: Value, sequential: bool, saved_locals: ?std.StringHashMap([]const u8), roots_pushed: usize) EmitError![]const u8 {
        try self.emitPopRoots(roots_pushed);
        self.locals.?.deinit();
        self.locals = saved_locals;
        return self.emitLetFallback(args, sequential);
    }

    fn emitLet(self: *LLVMEmitter, args: Value, sequential: bool, is_tail: bool) EmitError![]const u8 {
        const bindings = types.car(args);
        const body_list = types.cdr(args);

        // #827: If the let form (bindings or body) contains sub-expressions
        // that need interpreter eval fallback (cond, do, letrec, etc.),
        // compile the entire let via the interpreter to preserve correct
        // lexical scoping.
        if (lambda.sexprNeedsEvalFallback(args)) {
            return self.emitLetFallback(args, sequential);
        }
        // #827/#1497: A body lambda that captures a let-bound variable cannot
        // be compiled natively unless that variable is boxed — the native
        // closure tier rejects by-value capture of let-locals. A captured var
        // that is also mutated is assignment-converted to a heap box (#1497);
        // a captured but unmutated var has no box, so the whole let falls back
        // to the interpreter (which handles the scope correctly).
        var box_names: [32][]const u8 = undefined;
        var box_count: usize = 0;
        {
            var var_names: [32][]const u8 = undefined;
            var name_count: usize = 0;
            var blist = bindings;
            while (blist != types.NIL and types.isPair(blist)) : (blist = types.cdr(blist)) {
                if (name_count >= 32) break;
                const b = types.car(blist);
                if (types.isPair(b) and types.isSymbol(types.car(b))) {
                    var_names[name_count] = types.symbolName(types.car(b));
                    name_count += 1;
                }
            }
            for (var_names[0..name_count]) |v| {
                if (!lambda.bodyHasCapturingLambda(body_list, (&v)[0..1])) continue;
                if (!lambda.sexprBodySetsName(body_list, v)) {
                    return self.emitLetFallback(args, sequential);
                }
                box_names[box_count] = v;
                box_count += 1;
            }
        }
        const any_boxed = box_count > 0;

        // Boxed lets lower their body non-tail so the binding roots (which hold
        // the box pointers) are always popped at the fall-through, never
        // stranded past an in-body tail-call ret.
        const body_tail = is_tail and !any_boxed;

        // Box map scope for this let, extending any enclosing frame's boxes.
        const saved_boxes = self.boxes;
        var owns_boxes = false;
        defer if (owns_boxes) {
            if (self.boxes) |*b| b.deinit();
            self.boxes = saved_boxes;
        };
        if (any_boxed) {
            self.boxes = if (saved_boxes) |existing|
                existing.clone() catch return error.OutOfMemory
            else
                std.StringHashMap([]const u8).init(self.allocator());
            owns_boxes = true;
        }

        const saved_locals = self.locals;
        self.locals = if (saved_locals) |existing|
            existing.clone() catch return error.OutOfMemory
        else
            std.StringHashMap([]const u8).init(self.allocator());

        var binding_root_count: usize = 0;

        if (!sequential) {
            var binding_allocas: [32][]const u8 = undefined;
            var var_names: [32][]const u8 = undefined;
            var count: usize = 0;
            var blist = bindings;
            while (blist != types.NIL and types.isPair(blist)) {
                if (count >= 32) {
                    return self.abandonLetForFallback(args, sequential, saved_locals, count);
                }
                const binding = types.car(blist);
                const var_sym = types.car(binding);
                const init_expr = types.car(types.cdr(binding));
                if (!types.isSymbol(var_sym)) {
                    return self.abandonLetForFallback(args, sequential, saved_locals, count);
                }

                const node = ir.lowerSingleExpr(self.allocator(), init_expr) catch {
                    return self.abandonLetForFallback(args, sequential, saved_locals, count);
                };
                const alloca = try self.freshTemp();
                try self.print("  {s} = alloca i64, align 8\n", .{alloca});
                // #827: an init that cannot be emitted in this lexical scope
                // (e.g. a lambda) sends the whole let to the interpreter,
                // like the body path below.
                const val = self.emitNode(node) catch {
                    return self.abandonLetForFallback(args, sequential, saved_locals, count);
                };
                // A captured+mutated let-local is stored as a heap box; the
                // alloca (rooted below) then holds the box pointer (#1497).
                if (nameInList(box_names[0..box_count], types.symbolName(var_sym))) {
                    const box = try self.freshTemp();
                    try self.print("  {s} = call i64 @kaappi_make_box(ptr %vm, i64 {s})\n", .{ box, val });
                    try self.print("  store i64 {s}, ptr {s}\n", .{ box, alloca });
                } else {
                    try self.print("  store i64 {s}, ptr {s}\n", .{ val, alloca });
                }
                try self.emitRootPushAlloca(alloca);

                binding_allocas[count] = alloca;
                var_names[count] = types.symbolName(var_sym);
                count += 1;
                blist = types.cdr(blist);
            }

            for (0..count) |i| {
                if (nameInList(box_names[0..box_count], var_names[i])) {
                    self.boxes.?.put(var_names[i], binding_allocas[i]) catch return error.OutOfMemory;
                } else {
                    self.locals.?.put(var_names[i], binding_allocas[i]) catch return error.OutOfMemory;
                }
            }
            binding_root_count = count;
        } else {
            var blist = bindings;
            while (blist != types.NIL and types.isPair(blist)) {
                const binding = types.car(blist);
                const var_sym = types.car(binding);
                const init_expr = types.car(types.cdr(binding));
                if (!types.isSymbol(var_sym)) {
                    return self.abandonLetForFallback(args, sequential, saved_locals, binding_root_count);
                }

                const node = ir.lowerSingleExpr(self.allocator(), init_expr) catch {
                    return self.abandonLetForFallback(args, sequential, saved_locals, binding_root_count);
                };
                const val = self.emitNode(node) catch {
                    return self.abandonLetForFallback(args, sequential, saved_locals, binding_root_count);
                };
                const alloca = try self.freshTemp();
                try self.print("  {s} = alloca i64, align 8\n", .{alloca});
                // Box a captured+mutated let*-local; later inits in this same
                // let* then read it through the box (#1497).
                if (nameInList(box_names[0..box_count], types.symbolName(var_sym))) {
                    const box = try self.freshTemp();
                    try self.print("  {s} = call i64 @kaappi_make_box(ptr %vm, i64 {s})\n", .{ box, val });
                    try self.print("  store i64 {s}, ptr {s}\n", .{ box, alloca });
                    self.boxes.?.put(types.symbolName(var_sym), alloca) catch return error.OutOfMemory;
                } else {
                    try self.print("  store i64 {s}, ptr {s}\n", .{ val, alloca });
                    self.locals.?.put(types.symbolName(var_sym), alloca) catch return error.OutOfMemory;
                }
                try self.emitRootPushAlloca(alloca);
                binding_root_count += 1;
                blist = types.cdr(blist);
            }
        }

        var last: []const u8 = "";
        var body_expr = body_list;
        while (body_expr != types.NIL and types.isPair(body_expr)) {
            const rest = types.cdr(body_expr);
            const expr_is_tail = body_tail and (rest == types.NIL or !types.isPair(rest));
            const node = ir.lowerSingleExprTail(self.allocator(), types.car(body_expr), expr_is_tail) catch {
                return self.abandonLetForFallback(args, sequential, saved_locals, binding_root_count);
            };
            // #827: if emitNode fails (e.g. a lambda that cannot be eval'd in
            // this lexical scope), fall back to evaluating the entire let form
            // via the interpreter.
            last = self.emitNode(node) catch {
                return self.abandonLetForFallback(args, sequential, saved_locals, binding_root_count);
            };
            body_expr = rest;
        }

        try self.emitPopRoots(binding_root_count);
        self.locals.?.deinit();
        self.locals = saved_locals;
        return last;
    }

    fn emitIf(self: *LLVMEmitter, data: ir.IfData) EmitError![]const u8 {
        const test_val = try self.emitNode(data.test_expr);

        const false_val: i64 = @bitCast(types.FALSE);
        const cmp = try self.freshTemp();
        try self.print("  {s} = icmp ne i64 {s}, {d}\n", .{ cmp, test_val, false_val });

        const label_id = self.label_counter;
        self.label_counter += 1;

        const then_label = try std.fmt.allocPrint(self.allocator(), "then{d}", .{label_id});
        const else_label = try std.fmt.allocPrint(self.allocator(), "else{d}", .{label_id});
        const merge_label = try std.fmt.allocPrint(self.allocator(), "merge{d}", .{label_id});
        const pre_label = try std.fmt.allocPrint(self.allocator(), "pre{d}", .{label_id});

        // Name the current block so phi can reference it
        try self.print("  br label %{s}\n{s}:\n", .{ pre_label, pre_label });
        self.current_block = pre_label;

        if (data.alternate != null) {
            try self.print("  br i1 {s}, label %{s}, label %{s}\n", .{ cmp, then_label, else_label });
        } else {
            try self.print("  br i1 {s}, label %{s}, label %{s}\n", .{ cmp, then_label, merge_label });
        }

        try self.startBlock(then_label);
        const then_val = try self.emitNode(data.consequent);
        const then_end_block = self.current_block;
        try self.print("  br label %{s}\n", .{merge_label});

        if (data.alternate) |alt| {
            try self.startBlock(else_label);
            const else_val = try self.emitNode(alt);
            const else_end_block = self.current_block;
            try self.print("  br label %{s}\n", .{merge_label});

            try self.startBlock(merge_label);
            const result = try self.freshTemp();
            try self.print("  {s} = phi i64 [ {s}, %{s} ], [ {s}, %{s} ]\n", .{ result, then_val, then_end_block, else_val, else_end_block });
            return result;
        } else {
            const void_val: i64 = @bitCast(types.VOID);
            try self.startBlock(merge_label);
            const result = try self.freshTemp();
            try self.print("  {s} = phi i64 [ {s}, %{s} ], [ {d}, %{s} ]\n", .{ result, then_val, then_end_block, void_val, pre_label });
            return result;
        }
    }

    fn emitAnd(self: *LLVMEmitter, exprs: []const *ir.Node) EmitError![]const u8 {
        if (exprs.len == 0) return self.emitImm(@bitCast(types.TRUE));
        if (exprs.len == 1) return try self.emitNode(exprs[0]);

        const false_val: i64 = @bitCast(types.FALSE);
        const label_id = self.label_counter;
        self.label_counter += 1;
        const merge_label = try std.fmt.allocPrint(self.allocator(), "and_merge{d}", .{label_id});

        var prev_val = try self.emitNode(exprs[0]);
        for (exprs[1..], 0..) |expr, i| {
            const next_label = try std.fmt.allocPrint(self.allocator(), "and_next{d}_{d}", .{ label_id, i });
            const cmp = try self.freshTemp();
            try self.print("  {s} = icmp ne i64 {s}, {d}\n", .{ cmp, prev_val, false_val });
            const short_label = try std.fmt.allocPrint(self.allocator(), "and_short{d}_{d}", .{ label_id, i });
            try self.print("  br i1 {s}, label %{s}, label %{s}\n", .{ cmp, next_label, short_label });
            try self.print("{s}:\n", .{short_label});
            try self.print("  br label %{s}\n", .{merge_label});
            try self.print("{s}:\n", .{next_label});
            prev_val = try self.emitNode(expr);
        }
        const last_next = try std.fmt.allocPrint(self.allocator(), "and_done{d}", .{label_id});
        try self.print("  br label %{s}\n{s}:\n", .{ last_next, last_next });
        try self.print("  br label %{s}\n", .{merge_label});
        try self.startBlock(merge_label);

        const result = try self.freshTemp();
        try self.print("  {s} = phi i64 [ {s}, %{s} ]", .{ result, prev_val, last_next });
        for (0..exprs.len - 1) |i| {
            try self.print(", [ {d}, %and_short{d}_{d} ]", .{ false_val, label_id, i });
        }
        try self.write("\n");
        return result;
    }

    fn emitOr(self: *LLVMEmitter, exprs: []const *ir.Node) EmitError![]const u8 {
        if (exprs.len == 0) return self.emitImm(@bitCast(types.FALSE));
        if (exprs.len == 1) return try self.emitNode(exprs[0]);

        const false_val: i64 = @bitCast(types.FALSE);
        const label_id = self.label_counter;
        self.label_counter += 1;
        const merge_label = try std.fmt.allocPrint(self.allocator(), "or_merge{d}", .{label_id});

        const branch_count = exprs.len - 1;
        const vals = self.allocator().alloc([]const u8, branch_count) catch return error.OutOfMemory;
        const or_labels = self.allocator().alloc([]const u8, branch_count) catch return error.OutOfMemory;
        var count: usize = 0;

        for (exprs[0 .. exprs.len - 1], 0..) |expr, i| {
            const val = try self.emitNode(expr);
            vals[count] = val;
            or_labels[count] = try std.fmt.allocPrint(self.allocator(), "or_check{d}_{d}", .{ label_id, i });
            count += 1;
            const next_label = try std.fmt.allocPrint(self.allocator(), "or_next{d}_{d}", .{ label_id, i });
            const pre_label = or_labels[count - 1];
            try self.print("  br label %{s}\n{s}:\n", .{ pre_label, pre_label });
            const cmp = try self.freshTemp();
            try self.print("  {s} = icmp ne i64 {s}, {d}\n", .{ cmp, val, false_val });
            try self.print("  br i1 {s}, label %{s}, label %{s}\n", .{ cmp, merge_label, next_label });
            try self.print("{s}:\n", .{next_label});
        }

        const last_val = try self.emitNode(exprs[exprs.len - 1]);
        const last_label = try std.fmt.allocPrint(self.allocator(), "or_last{d}", .{label_id});
        try self.print("  br label %{s}\n{s}:\n", .{ last_label, last_label });
        try self.print("  br label %{s}\n", .{merge_label});
        try self.startBlock(merge_label);

        const result = try self.freshTemp();
        try self.print("  {s} = phi i64 [ {s}, %{s} ]", .{ result, last_val, last_label });
        for (0..count) |i| {
            try self.print(", [ {s}, %{s} ]", .{ vals[i], or_labels[i] });
        }
        try self.write("\n");
        return result;
    }

    fn emitWhen(self: *LLVMEmitter, data: ir.CondBodyData) EmitError![]const u8 {
        const test_val = try self.emitNode(data.test_expr);
        const false_val: i64 = @bitCast(types.FALSE);
        const cmp = try self.freshTemp();
        try self.print("  {s} = icmp ne i64 {s}, {d}\n", .{ cmp, test_val, false_val });

        const label_id = self.label_counter;
        self.label_counter += 1;
        const body_label = try std.fmt.allocPrint(self.allocator(), "when_body{d}", .{label_id});
        const merge_label = try std.fmt.allocPrint(self.allocator(), "when_merge{d}", .{label_id});
        const pre_label = try std.fmt.allocPrint(self.allocator(), "when_pre{d}", .{label_id});

        try self.print("  br label %{s}\n{s}:\n", .{ pre_label, pre_label });
        try self.print("  br i1 {s}, label %{s}, label %{s}\n", .{ cmp, body_label, merge_label });
        try self.startBlock(body_label);

        var last: []const u8 = "";
        for (data.body) |expr| {
            last = try self.emitNode(expr);
        }
        const body_end_block = self.current_block;
        try self.print("  br label %{s}\n", .{merge_label});
        try self.startBlock(merge_label);

        const void_val: i64 = @bitCast(types.VOID);
        const result = try self.freshTemp();
        try self.print("  {s} = phi i64 [ {s}, %{s} ], [ {d}, %{s} ]\n", .{ result, last, body_end_block, void_val, pre_label });
        return result;
    }

    fn emitUnless(self: *LLVMEmitter, data: ir.CondBodyData) EmitError![]const u8 {
        const test_val = try self.emitNode(data.test_expr);
        const false_val: i64 = @bitCast(types.FALSE);
        const cmp = try self.freshTemp();
        try self.print("  {s} = icmp eq i64 {s}, {d}\n", .{ cmp, test_val, false_val });

        const label_id = self.label_counter;
        self.label_counter += 1;
        const body_label = try std.fmt.allocPrint(self.allocator(), "unless_body{d}", .{label_id});
        const merge_label = try std.fmt.allocPrint(self.allocator(), "unless_merge{d}", .{label_id});
        const pre_label = try std.fmt.allocPrint(self.allocator(), "unless_pre{d}", .{label_id});

        try self.print("  br label %{s}\n{s}:\n", .{ pre_label, pre_label });
        try self.print("  br i1 {s}, label %{s}, label %{s}\n", .{ cmp, body_label, merge_label });
        try self.startBlock(body_label);

        var last: []const u8 = "";
        for (data.body) |expr| {
            last = try self.emitNode(expr);
        }
        const body_end_block = self.current_block;
        try self.print("  br label %{s}\n", .{merge_label});
        try self.startBlock(merge_label);

        const void_val: i64 = @bitCast(types.VOID);
        const result = try self.freshTemp();
        try self.print("  {s} = phi i64 [ {s}, %{s} ], [ {d}, %{s} ]\n", .{ result, last, body_end_block, void_val, pre_label });
        return result;
    }

    fn emitSet(self: *LLVMEmitter, data: ir.SetData) EmitError![]const u8 {
        if (!types.isSymbol(data.name)) return error.UnsupportedNodeType;
        const name = types.symbolName(data.name);
        // Evaluate the new value with lexical scope respected, then store it
        // into whichever slot `name` resolves to (local alloca, parameter,
        // rest parameter, upvalue, or global). The old code always evaluated
        // the value in the global environment and rebound a global (#819).
        const val = try self.emitScopedValue(data.value);
        try self.emitStoreToVariable(name, val);

        // When set! targets a global, invalidate the native_fns entry so
        // later call sites fall back to kaappi_global_lookup (#822).
        if (!self.isNameShadowed(name)) {
            _ = self.native_fns.fetchRemove(name);
            self.rebound_globals.put(name, {}) catch {};
        }

        return self.emitVoid();
    }

    fn inLexicalScope(self: *LLVMEmitter) bool {
        return self.params != null or self.locals != null or
            self.rest_param_name != null or self.upvalues != null;
    }

    // Emit a value expression, resolving variable references against the
    // current lexical scope (params, locals, upvalues) rather than assuming
    // the global environment.
    fn emitScopedValue(self: *LLVMEmitter, value: Value) EmitError![]const u8 {
        if (types.isSymbol(value)) return self.emitGlobalRef(value);
        if (!types.isPair(value)) return self.emitConstant(value);
        // At the top level there are no lexical bindings, so evaluate the value
        // in the global environment via kaappi_eval. That also expands macro
        // calls correctly; the standalone IR lowering below runs without a
        // macro table and would mis-lower a top-level (set! x (some-macro ...)).
        if (!self.inLexicalScope()) return self.emitEvalExpr(value);
        const node = ir.lowerSingleExpr(self.allocator(), value) catch return self.emitEvalExpr(value);
        return self.emitNode(node);
    }

    // Store `val` into the slot that `name` denotes in the current scope.
    // Resolution order mirrors emitGlobalRef's read path so writes and reads
    // reach the same binding.
    fn emitStoreToVariable(self: *LLVMEmitter, name: []const u8, val: []const u8) EmitError!void {
        // A boxed variable is mutated through its heap cell so the new value is
        // visible to every closure that captured the same box (#1497).
        if (self.boxes) |bx| {
            if (bx.get(name)) |box_alloca| {
                const boxptr = try self.freshTemp();
                try self.print("  {s} = load i64, ptr {s}\n", .{ boxptr, box_alloca });
                try self.print("  call void @kaappi_box_set(i64 {s}, i64 {s})\n", .{ boxptr, val });
                return;
            }
        }
        if (self.locals) |loc| {
            if (loc.get(name)) |alloca_name| {
                try self.print("  store i64 {s}, ptr {s}\n", .{ val, alloca_name });
                return;
            }
        }
        if (self.rest_param_name) |rp_name| {
            if (std.mem.eql(u8, name, rp_name)) {
                try self.print("  store i64 {s}, ptr {s}\n", .{ val, self.rest_param_alloca.? });
                return;
            }
        }
        if (self.params) |p| {
            if (p.get(name)) |idx| {
                const gep = try self.freshTemp();
                try self.print("  {s} = getelementptr i64, ptr %args, i64 {d}\n", .{ gep, idx });
                try self.print("  store i64 {s}, ptr {s}\n", .{ val, gep });
                return;
            }
        }
        if (self.upvalues) |uv| {
            if (uv.get(name)) |idx| {
                const gep = try self.freshTemp();
                try self.print("  {s} = getelementptr i64, ptr %upvalues, i64 {d}\n", .{ gep, idx });
                try self.print("  store i64 {s}, ptr {s}\n", .{ val, gep });
                return;
            }
        }
        // Not a lexical binding: set! an existing global, erroring if unbound.
        const sym_name = try self.internSymbol(name);
        try self.print("  call void @kaappi_set_global(ptr %vm, ptr {s}, i64 {d}, i64 {s})\n", .{ sym_name, name.len, val });
    }

    // Emit an SSA temp holding the unspecified/void value (the result of set!
    // and define).
    fn emitVoid(self: *LLVMEmitter) EmitError![]const u8 {
        return self.emitImm(@bitCast(types.VOID));
    }

    fn emitSexprEval(self: *LLVMEmitter, node: *const ir.Node) EmitError![]const u8 {
        if (node.tag != .sexpr_form) return error.UnsupportedNodeType;
        const sf = node.data.sexpr_form;
        return self.emitFormEval(sf.args, sf.form.keyword());
    }

    fn emitLetEvalFallback(self: *LLVMEmitter, args: Value, form_name: []const u8) EmitError![]const u8 {
        return self.emitFormEval(args, form_name);
    }

    fn emitFormEval(self: *LLVMEmitter, args: Value, form_name: []const u8) EmitError![]const u8 {
        try lambda.bindParamsAsGlobals(self);

        var source_buf: std.ArrayList(u8) = .empty;
        defer source_buf.deinit(self.backing_alloc);
        source_buf.appendSlice(self.backing_alloc, "(") catch return error.OutOfMemory;
        source_buf.appendSlice(self.backing_alloc, form_name) catch return error.OutOfMemory;

        var current = args;
        while (current != types.NIL and types.isPair(current)) {
            source_buf.append(self.backing_alloc, ' ') catch return error.OutOfMemory;
            const elem = types.car(current);
            const elem_str = printer.valueToString(self.backing_alloc, elem, .write) catch return error.OutOfMemory;
            defer self.backing_alloc.free(elem_str);
            source_buf.appendSlice(self.backing_alloc, elem_str) catch return error.OutOfMemory;
            current = types.cdr(current);
        }
        source_buf.append(self.backing_alloc, ')') catch return error.OutOfMemory;

        return self.emitCachedEval(source_buf.items);
    }

    fn emitPassthrough(self: *LLVMEmitter, expr: Value) EmitError![]const u8 {
        if (types.isPair(expr)) {
            const head = types.car(expr);
            if (types.isSymbol(head) and std.mem.eql(u8, types.symbolName(head), "define")) {
                const rest = types.cdr(expr);
                if (rest != types.NIL and types.isPair(rest)) {
                    const target = types.car(rest);
                    if (types.isPair(target) and types.isSymbol(types.car(target))) {
                        const fn_name = types.symbolName(types.car(target));
                        const formals = types.cdr(target);
                        const body = types.cdr(rest);
                        _ = self.native_fns.fetchRemove(fn_name);
                        self.rebound_globals.put(fn_name, {}) catch {};
                        if (self.tryCompileDefineFunction(fn_name, formals, body) != null) {
                            _ = self.rebound_globals.fetchRemove(fn_name);
                        }
                    }
                }
            }
        }
        return self.emitEvalExpr(expr);
    }

    fn emitDefine(self: *LLVMEmitter, data: ir.DefineData) EmitError![]const u8 {
        if (!types.isSymbol(data.name)) return error.UnsupportedNodeType;
        const name = types.symbolName(data.name);

        // Internal define inside a natively compiled lexical scope (a `let`
        // body). self.locals is only populated while emitLet emits a body, so
        // top-level and lambda-body defines fall through to the global path.
        // Create a fresh local binding so the define shadows any global of the
        // same name for the rest of the body, instead of overwriting it (#819).
        if (self.locals != null) {
            const alloca = try self.freshTemp();
            try self.print("  {s} = alloca i64, align 8\n", .{alloca});
            // Register before emitting the value so a self/mutual reference in
            // the initializer resolves to this binding (letrec*-style).
            self.locals.?.put(name, alloca) catch return error.OutOfMemory;
            const val = try self.emitScopedValue(data.value);
            try self.print("  store i64 {s}, ptr {s}\n", .{ val, alloca });
            return self.emitVoid();
        }

        const sym_name = try self.internSymbol(name);

        // Remove any stale native_fns entry before attempting native
        // compilation; tryCompileLambdaNative re-registers if it succeeds.
        // Mark the name rebound so inline primitive dispatch is suppressed
        // for later call sites (#822).
        _ = self.native_fns.fetchRemove(name);
        self.rebound_globals.put(name, {}) catch {};

        if (types.isPair(data.value)) {
            const head = types.car(data.value);
            if (types.isSymbol(head) and std.mem.eql(u8, types.symbolName(head), "lambda")) {
                const lambda_data = ir.LambdaData{ .args = types.cdr(data.value), .name = name };
                if (self.tryCompileLambdaNative(lambda_data) != null) {
                    _ = self.rebound_globals.fetchRemove(name);
                }
            }
        }

        const val = if (types.isPair(data.value))
            try self.emitEvalExpr(data.value)
        else if (types.isSymbol(data.value))
            try self.emitGlobalRef(data.value)
        else
            try self.emitConstant(data.value);

        try self.print("  call void @kaappi_define_global(ptr %vm, ptr {s}, i64 {d}, i64 {s})\n", .{ sym_name, name.len, val });

        return self.emitVoid();
    }

    const lambda = @import("llvm_emit_lambda.zig");

    fn emitLambda(self: *LLVMEmitter, data: ir.LambdaData) EmitError![]const u8 {
        return lambda.emitLambda(self, data);
    }

    pub fn tryCompileDefineFunction(self: *LLVMEmitter, name: []const u8, formals: Value, body: Value) ?[]const u8 {
        return lambda.tryCompileDefineFunction(self, name, formals, body);
    }

    fn tryCompileLambdaNative(self: *LLVMEmitter, data: ir.LambdaData) ?[]const u8 {
        return lambda.tryCompileLambdaNative(self, data);
    }

    fn tryEmitInlineBinary(self: *LLVMEmitter, name: []const u8, args: []const *ir.Node) ?[]const u8 {
        const export_name = native_decls.findInline(.binary, name) orelse return null;
        const a = self.emitNode(args[0]) catch return null;
        // Root the first operand across the second's evaluation only when that
        // evaluation could actually collect. For the common hot-loop shapes
        // `(op var const)` and `(op var var)` the second operand is a leaf, so
        // this drops two runtime calls (push_root/pop_roots) per operation.
        const root_a = nodeMayAllocate(args[1]);
        if (root_a) self.emitRootPush(a) catch return null;
        const b = self.emitNode(args[1]) catch return null;
        if (root_a) self.emitPopRoots(1) catch return null;

        // Arithmetic and comparison operate purely on NaN-boxed Value bits, so
        // their fixnum fast paths lower to inline IR with a call to the runtime
        // only on the slow path (non-fixnum operands, or overflow out of the
        // i48 fixnum range → bignum promotion). This removes the per-operation
        // cross-module call that -O2 alone cannot eliminate (#1493). cons falls
        // through to a direct specialized call: it always allocates, so there is
        // no call-free fast path, and its Pair layout is not encodable here.
        if (ArithOp.fromName(name)) |op|
            return self.emitInlineArith(op, a, b, export_name) catch return null;
        if (std.mem.eql(u8, name, "<"))
            return self.emitInlineCompare(.lt, a, b, export_name) catch return null;
        if (std.mem.eql(u8, name, "="))
            return self.emitInlineCompare(.eq, a, b, export_name) catch return null;

        const result = self.freshTemp() catch return null;
        self.print("  {s} = call i64 @{s}(i64 {s}, i64 {s})\n", .{ result, export_name, a, b }) catch return null;
        return result;
    }

    fn tryEmitInlineUnary(self: *LLVMEmitter, name: []const u8, arg: *const ir.Node) ?[]const u8 {
        const export_name = native_decls.findInline(.unary, name) orelse return null;
        const v = self.emitNode(arg) catch return null;

        // null? is a single Value comparison against the nil immediate — no
        // heap access, no fallback needed. car/cdr touch the (auto-layout) Pair
        // struct and raise on a non-pair, so they stay as direct runtime calls.
        if (std.mem.eql(u8, name, "null?"))
            return self.emitInlineNullCheck(v) catch return null;

        const result = self.freshTemp() catch return null;
        self.print("  {s} = call i64 @{s}(i64 {s})\n", .{ result, export_name, v }) catch return null;
        return result;
    }

    // Emit `%dst = <sign-extended i48 payload of %boxed>`. Shifting the tag bits
    // out to the left and arithmetic-shifting back sign-extends bit 47, matching
    // types.toFixnum. Caller must have already checked %boxed is a fixnum.
    fn emitUnboxFixnum(self: *LLVMEmitter, boxed: []const u8) EmitError![]const u8 {
        const shifted = try self.freshTemp();
        try self.print("  {s} = shl i64 {s}, 16\n", .{ shifted, boxed });
        const val = try self.freshTemp();
        try self.print("  {s} = ashr i64 {s}, 16\n", .{ val, shifted });
        return val;
    }

    // Emit `%dst = i1` that is true iff %boxed carries the fixnum tag
    // (`(boxed >> 48) == 0xFFFD`), matching types.isFixnum.
    fn emitIsFixnum(self: *LLVMEmitter, boxed: []const u8) EmitError![]const u8 {
        const hi = try self.freshTemp();
        try self.print("  {s} = lshr i64 {s}, 48\n", .{ hi, boxed });
        const is_fix = try self.freshTemp();
        try self.print("  {s} = icmp eq i64 {s}, {d}\n", .{ is_fix, hi, nanbox.fix_tag_hi });
        return is_fix;
    }

    // Compute `i1` = both operands are fixnums, then branch to the caller's
    // fixnum fast-path block or its runtime slow-path block accordingly.
    fn emitBothFixnumBranch(self: *LLVMEmitter, a: []const u8, b: []const u8, fast: []const u8, slow: []const u8) EmitError!void {
        const a_fix = try self.emitIsFixnum(a);
        const b_fix = try self.emitIsFixnum(b);
        const both = try self.freshTemp();
        try self.print("  {s} = and i1 {s}, {s}\n", .{ both, a_fix, b_fix });
        try self.print("  br i1 {s}, label %{s}, label %{s}\n", .{ both, fast, slow });
    }

    // Fixnum fast path for +, -, *. On non-fixnum operands or a result outside
    // the i48 fixnum range (overflow → bignum), fall back to the runtime.
    fn emitInlineArith(self: *LLVMEmitter, op: ArithOp, a: []const u8, b: []const u8, export_name: []const u8) EmitError![]const u8 {
        const id = self.label_counter;
        self.label_counter += 1;
        const fast = try std.fmt.allocPrint(self.allocator(), "arith_fast{d}", .{id});
        const box = try std.fmt.allocPrint(self.allocator(), "arith_box{d}", .{id});
        const slow = try std.fmt.allocPrint(self.allocator(), "arith_slow{d}", .{id});
        const done = try std.fmt.allocPrint(self.allocator(), "arith_done{d}", .{id});

        try self.emitBothFixnumBranch(a, b, fast, slow);

        try self.startBlock(fast);
        const va = try self.emitUnboxFixnum(a);
        const vb = try self.emitUnboxFixnum(b);
        const ov = try self.freshTemp();
        try self.print("  {s} = call {{ i64, i1 }} {s}(i64 {s}, i64 {s})\n", .{ ov, op.overflowIntrinsic(), va, vb });
        const raw = try self.freshTemp();
        try self.print("  {s} = extractvalue {{ i64, i1 }} {s}, 0\n", .{ raw, ov });
        const ovf = try self.freshTemp();
        try self.print("  {s} = extractvalue {{ i64, i1 }} {s}, 1\n", .{ ovf, ov });
        const ge = try self.freshTemp();
        try self.print("  {s} = icmp sge i64 {s}, {d}\n", .{ ge, raw, nanbox.fix_min });
        const le = try self.freshTemp();
        try self.print("  {s} = icmp sle i64 {s}, {d}\n", .{ le, raw, nanbox.fix_max });
        const in_range = try self.freshTemp();
        try self.print("  {s} = and i1 {s}, {s}\n", .{ in_range, ge, le });
        const not_ovf = try self.freshTemp();
        try self.print("  {s} = xor i1 {s}, true\n", .{ not_ovf, ovf });
        const ok = try self.freshTemp();
        try self.print("  {s} = and i1 {s}, {s}\n", .{ ok, in_range, not_ovf });
        try self.print("  br i1 {s}, label %{s}, label %{s}\n", .{ ok, box, slow });

        try self.startBlock(box);
        const masked = try self.freshTemp();
        try self.print("  {s} = and i64 {s}, {d}\n", .{ masked, raw, nanbox.payload_mask });
        const boxed = try self.freshTemp();
        try self.print("  {s} = or i64 {s}, {d}\n", .{ boxed, masked, nanbox.fix_base });
        try self.print("  br label %{s}\n", .{done});

        try self.startBlock(slow);
        const slow_res = try self.freshTemp();
        try self.print("  {s} = call i64 @{s}(i64 {s}, i64 {s})\n", .{ slow_res, export_name, a, b });
        try self.print("  br label %{s}\n", .{done});

        try self.startBlock(done);
        const result = try self.freshTemp();
        try self.print("  {s} = phi i64 [ {s}, %{s} ], [ {s}, %{s} ]\n", .{ result, boxed, box, slow_res, slow });
        return result;
    }

    const CompareKind = enum { lt, eq };

    // Fixnum fast path for < and =. Non-fixnum operands fall back to the
    // runtime, which handles the full numeric tower.
    fn emitInlineCompare(self: *LLVMEmitter, kind: CompareKind, a: []const u8, b: []const u8, export_name: []const u8) EmitError![]const u8 {
        const id = self.label_counter;
        self.label_counter += 1;
        const fast = try std.fmt.allocPrint(self.allocator(), "cmp_fast{d}", .{id});
        const slow = try std.fmt.allocPrint(self.allocator(), "cmp_slow{d}", .{id});
        const done = try std.fmt.allocPrint(self.allocator(), "cmp_done{d}", .{id});

        try self.emitBothFixnumBranch(a, b, fast, slow);

        try self.startBlock(fast);
        const cond = try self.freshTemp();
        switch (kind) {
            // Fixnums have a canonical encoding, so equal integers have equal
            // bits — the raw compare matches the runtime's `a == b`.
            .eq => try self.print("  {s} = icmp eq i64 {s}, {s}\n", .{ cond, a, b }),
            // Ordering needs the sign-extended payloads (raw compare would
            // mis-order negatives).
            .lt => {
                const va = try self.emitUnboxFixnum(a);
                const vb = try self.emitUnboxFixnum(b);
                try self.print("  {s} = icmp slt i64 {s}, {s}\n", .{ cond, va, vb });
            },
        }
        const fast_res = try self.freshTemp();
        try self.print("  {s} = select i1 {s}, i64 {d}, i64 {d}\n", .{ fast_res, cond, nanbox.true_val, nanbox.false_val });
        try self.print("  br label %{s}\n", .{done});

        try self.startBlock(slow);
        const slow_res = try self.freshTemp();
        try self.print("  {s} = call i64 @{s}(i64 {s}, i64 {s})\n", .{ slow_res, export_name, a, b });
        try self.print("  br label %{s}\n", .{done});

        try self.startBlock(done);
        const result = try self.freshTemp();
        try self.print("  {s} = phi i64 [ {s}, %{s} ], [ {s}, %{s} ]\n", .{ result, fast_res, fast, slow_res, slow });
        return result;
    }

    // null? — a single comparison against the nil immediate, no heap access.
    fn emitInlineNullCheck(self: *LLVMEmitter, v: []const u8) EmitError![]const u8 {
        const cond = try self.freshTemp();
        try self.print("  {s} = icmp eq i64 {s}, {d}\n", .{ cond, v, nanbox.nil });
        const result = try self.freshTemp();
        try self.print("  {s} = select i1 {s}, i64 {d}, i64 {d}\n", .{ result, cond, nanbox.true_val, nanbox.false_val });
        return result;
    }

    fn emitDirectCall(self: *LLVMEmitter, fn_name: []const u8, args: []const *ir.Node, is_tail: bool) EmitError![]const u8 {
        const nargs = args.len;
        const arg_tmps = self.allocator().alloc([]const u8, nargs) catch return error.OutOfMemory;
        var root_count: usize = 0;
        for (args, 0..) |arg, i| {
            arg_tmps[i] = try self.emitNode(arg);
            if (i + 1 < nargs) {
                try self.emitRootPush(arg_tmps[i]);
                root_count += 1;
            }
        }
        try self.emitPopRoots(root_count);

        const result = try self.freshTemp();

        if (nargs == 0) {
            const call_prefix: []const u8 = if (is_tail) "tail call" else "call";
            try self.print("  {s} = {s} i64 {s}(ptr %vm, ptr null, i64 0, ptr null)\n", .{ result, call_prefix, fn_name });
        } else {
            const args_alloca = try self.freshTemp();
            try self.print("  {s} = alloca [{d} x i64], align 8\n", .{ args_alloca, nargs });

            for (0..nargs) |i| {
                const gep = try self.freshTemp();
                try self.print("  {s} = getelementptr i64, ptr {s}, i64 {d}\n", .{ gep, args_alloca, i });
                try self.print("  store i64 {s}, ptr {s}\n", .{ arg_tmps[i], gep });
            }

            try self.print("  {s} = call i64 {s}(ptr %vm, ptr {s}, i64 {d}, ptr null)\n", .{ result, fn_name, args_alloca, nargs });
        }

        if (is_tail) {
            try self.print("  ret i64 {s}\n", .{result});
            try self.emitOrphanAfterTail();
        }

        return result;
    }

    fn emitEvalExpr(self: *LLVMEmitter, value: Value) EmitError![]const u8 {
        const source = printer.valueToString(self.backing_alloc, value, .write) catch return error.OutOfMemory;
        defer self.backing_alloc.free(source);
        return self.emitCachedEval(source);
    }

    fn emitQuotedEvalExpr(self: *LLVMEmitter, value: Value) EmitError![]const u8 {
        const printed = printer.valueToString(self.backing_alloc, value, .write) catch return error.OutOfMemory;
        defer self.backing_alloc.free(printed);
        const source = std.fmt.allocPrint(self.backing_alloc, "(quote {s})", .{printed}) catch return error.OutOfMemory;
        defer self.backing_alloc.free(source);
        const str_name = try self.internString(source);
        const tmp = try self.freshTemp();
        try self.print("  {s} = call i64 @kaappi_eval(ptr %vm, ptr {s}, i64 {d})\n", .{ tmp, str_name, source.len });
        return tmp;
    }

    pub fn internSymbol(self: *LLVMEmitter, name: []const u8) EmitError![]const u8 {
        if (!self.symbols.contains(name)) {
            const id = self.sym_counter;
            self.sym_counter += 1;
            self.symbols.put(name, id) catch return error.OutOfMemory;
        }
        const id = self.symbols.get(name).?;
        return std.fmt.allocPrint(self.allocator(), "@.sym.{d}", .{id}) catch return error.OutOfMemory;
    }

    // Emit a call to the compile-once caching eval (#1494) for a serialized
    // form. Interns the source string, allocates a fresh per-call-site cache
    // slot, and emits the call passing the slot by pointer. Every code-shaped
    // eval fallback (letrec/cond/case/do/guard/quasiquote/named-let, let/let*,
    // fallback lambdas, and general expressions) routes through here instead of
    // @kaappi_eval so the reader + compiler run at most once per call site.
    // Quoted heap constants intentionally stay on plain @kaappi_eval — building
    // them once is a distinct optimization tracked as #1495.
    pub fn emitCachedEval(self: *LLVMEmitter, source: []const u8) EmitError![]const u8 {
        const str_name = try self.internString(source);
        const slot_name = try self.nextEvalCacheSlot();
        const tmp = try self.freshTemp();
        try self.print("  {s} = call i64 @kaappi_eval_cached(ptr %vm, ptr {s}, i64 {d}, ptr {s})\n", .{ tmp, str_name, source.len, slot_name });
        return tmp;
    }

    fn nextEvalCacheSlot(self: *LLVMEmitter) EmitError![]const u8 {
        const id = self.eval_cache_counter;
        self.eval_cache_counter += 1;
        return std.fmt.allocPrint(self.allocator(), "@.eval_cache.{d}", .{id}) catch return error.OutOfMemory;
    }

    pub fn internString(self: *LLVMEmitter, data: []const u8) EmitError![]const u8 {
        const id = self.string_counter;
        self.string_counter += 1;
        const global_name = std.fmt.allocPrint(self.allocator(), "@.str.{d}", .{id}) catch return error.OutOfMemory;

        var escaped: std.ArrayList(u8) = .empty;
        defer escaped.deinit(self.backing_alloc);
        for (data) |byte| {
            if (byte >= 0x20 and byte < 0x7F and byte != '"' and byte != '\\') {
                escaped.append(self.backing_alloc, byte) catch return error.OutOfMemory;
            } else {
                const hex = std.fmt.allocPrint(self.backing_alloc, "\\{X:0>2}", .{byte}) catch return error.OutOfMemory;
                defer self.backing_alloc.free(hex);
                escaped.appendSlice(self.backing_alloc, hex) catch return error.OutOfMemory;
            }
        }

        const decl = std.fmt.allocPrint(self.allocator(), "{s} = private unnamed_addr constant [{d} x i8] c\"{s}\"\n", .{ global_name, data.len, escaped.items }) catch return error.OutOfMemory;
        self.string_decls.append(self.backing_alloc, decl) catch return error.OutOfMemory;

        return global_name;
    }

    fn emitPreamble(self: *LLVMEmitter) EmitError!void {
        const arch = @import("builtin").cpu.arch;
        const os = @import("builtin").os.tag;
        const triple = switch (arch) {
            .aarch64 => switch (os) {
                .macos => "aarch64-apple-macosx",
                .linux => "aarch64-unknown-linux-gnu",
                else => "aarch64-unknown-unknown",
            },
            .x86_64 => switch (os) {
                .macos => "x86_64-apple-macosx",
                .linux => "x86_64-unknown-linux-gnu",
                else => "x86_64-unknown-unknown",
            },
            else => "unknown-unknown-unknown",
        };

        try self.print("; Generated by Kaappi Scheme LLVM backend\ntarget triple = \"{s}\"\n\n", .{triple});
        for (native_decls.decls) |d| {
            try self.print("declare {s} @{s}(", .{ d.ret.toLLVM(), d.export_name });
            for (d.param_types, 0..) |p, i| {
                if (i > 0) try self.write(", ");
                try self.write(p.toLLVM());
            }
            try self.write(")\n");
        }
        // Checked-arithmetic intrinsics used by the inline fixnum fast paths
        // for +, -, * (emitInlineArith).
        try self.write("declare { i64, i1 } @llvm.sadd.with.overflow.i64(i64, i64)\n");
        try self.write("declare { i64, i1 } @llvm.ssub.with.overflow.i64(i64, i64)\n");
        try self.write("declare { i64, i1 } @llvm.smul.with.overflow.i64(i64, i64)\n");
    }

    fn emitRootPush(self: *LLVMEmitter, tmp: []const u8) EmitError!void {
        const slot = try self.freshTemp();
        try self.print("  {s} = alloca i64, align 8\n", .{slot});
        try self.print("  store i64 {s}, ptr {s}\n", .{ tmp, slot });
        try self.print("  call void @kaappi_gc_push_root(ptr {s})\n", .{slot});
    }

    fn emitRootPushAlloca(self: *LLVMEmitter, alloca: []const u8) EmitError!void {
        try self.print("  call void @kaappi_gc_push_root(ptr {s})\n", .{alloca});
    }

    fn emitPopRoots(self: *LLVMEmitter, n: usize) EmitError!void {
        if (n > 0) {
            try self.print("  call void @kaappi_gc_pop_roots(i64 {d})\n", .{n});
        }
    }

    pub fn freshTemp(self: *LLVMEmitter) EmitError![]const u8 {
        const n = self.tmp_counter;
        self.tmp_counter += 1;
        const s = std.fmt.allocPrint(self.allocator(), "%t{d}", .{n}) catch return error.OutOfMemory;
        return s;
    }

    pub fn freshLabel(self: *LLVMEmitter, comptime prefix: []const u8) EmitError![]const u8 {
        const id = self.label_counter;
        self.label_counter += 1;
        return std.fmt.allocPrint(self.allocator(), prefix ++ "{d}", .{id}) catch return error.OutOfMemory;
    }

    pub fn emitImm(self: *LLVMEmitter, val: i64) EmitError![]const u8 {
        const tmp = try self.freshTemp();
        try self.print("  {s} = add i64 0, {d}\n", .{ tmp, val });
        return tmp;
    }

    pub fn startBlock(self: *LLVMEmitter, label: []const u8) EmitError!void {
        try self.print("{s}:\n", .{label});
        self.current_block = label;
    }

    fn emitOrphanAfterTail(self: *LLVMEmitter) EmitError!void {
        const after_label = try self.freshLabel("after_tail_");
        try self.startBlock(after_label);
    }

    pub fn write(self: *LLVMEmitter, s: []const u8) EmitError!void {
        self.buf.appendSlice(self.backing_alloc, s) catch return error.OutOfMemory;
    }

    pub fn print(self: *LLVMEmitter, comptime fmt: []const u8, args: anytype) EmitError!void {
        const s = std.fmt.allocPrint(self.backing_alloc, fmt, args) catch return error.OutOfMemory;
        defer self.backing_alloc.free(s);
        try self.write(s);
    }

    pub fn toSlice(self: *LLVMEmitter) []const u8 {
        return self.buf.items;
    }
};

pub const EmitError = error{
    UnsupportedNodeType,
    OutOfMemory,
};
