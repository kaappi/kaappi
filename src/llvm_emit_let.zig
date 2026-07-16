// Native `let` / `let*` emission for the LLVM backend.
//
// `emitLet` (the entry point, dispatched from emitNode in llvm_emit.zig for
// both .let_form and .let_star) lowers a let whose bindings and body are all
// natively emittable into stack allocas rooted on the shadow stack. Anything it
// cannot compile in the current lexical scope — a binding/body form that needs
// interpreter eval fallback (#827), or a captured-but-unmutated binding the
// native closure tier can't take by value (#1497) — routes the whole form
// through the interpreter via `emitLetFallback`, never splitting one lexical
// scope across the native/interpreted boundary.
//
// `abandonLetForFallback` is the mid-emission escape hatch: once some bindings
// have already been emitted (and their roots pushed), it unwinds that partial
// state before handing the form to the interpreter.

const std = @import("std");
const ir = @import("ir.zig");
const types = @import("types.zig");
const printer = @import("printer.zig");

const llvm_emit = @import("llvm_emit.zig");
const LLVMEmitter = llvm_emit.LLVMEmitter;
const EmitError = llvm_emit.EmitError;

// #1497 assignment-conversion helpers (capture/mutation analysis) and #1410
// param-globals binding live with the lambda emitter.
const lambda = @import("llvm_emit_lambda.zig");

const Value = types.Value;

fn nameInList(names: []const []const u8, name: []const u8) bool {
    for (names) |n| {
        if (std.mem.eql(u8, n, name)) return true;
    }
    return false;
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
    return emitLetFallback(self, args, sequential);
}

pub fn emitLet(self: *LLVMEmitter, args: Value, sequential: bool, is_tail: bool) EmitError![]const u8 {
    const bindings = types.car(args);
    const body_list = types.cdr(args);

    // #827: If the let form (bindings or body) contains sub-expressions
    // that need interpreter eval fallback (cond, do, letrec, etc.),
    // compile the entire let via the interpreter to preserve correct
    // lexical scoping.
    if (lambda.sexprNeedsEvalFallback(args)) {
        return emitLetFallback(self, args, sequential);
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
            if (!lambda.bodyHasCapturingLambda(self, body_list, (&v)[0..1])) continue;
            if (!lambda.sexprBodySetsName(body_list, v)) {
                return emitLetFallback(self, args, sequential);
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
                return abandonLetForFallback(self, args, sequential, saved_locals, count);
            }
            const binding = types.car(blist);
            const var_sym = types.car(binding);
            const init_expr = types.car(types.cdr(binding));
            if (!types.isSymbol(var_sym)) {
                return abandonLetForFallback(self, args, sequential, saved_locals, count);
            }

            const node = ir.lowerSingleExpr(self.allocator(), init_expr) catch {
                return abandonLetForFallback(self, args, sequential, saved_locals, count);
            };
            const alloca = try self.freshTemp();
            try self.print("  {s} = alloca i64, align 8\n", .{alloca});
            // #827: an init that cannot be emitted in this lexical scope
            // (e.g. a lambda) sends the whole let to the interpreter,
            // like the body path below.
            const val = self.emitNode(node) catch {
                return abandonLetForFallback(self, args, sequential, saved_locals, count);
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
                return abandonLetForFallback(self, args, sequential, saved_locals, binding_root_count);
            }

            const node = ir.lowerSingleExpr(self.allocator(), init_expr) catch {
                return abandonLetForFallback(self, args, sequential, saved_locals, binding_root_count);
            };
            const val = self.emitNode(node) catch {
                return abandonLetForFallback(self, args, sequential, saved_locals, binding_root_count);
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
            return abandonLetForFallback(self, args, sequential, saved_locals, binding_root_count);
        };
        // #827: if emitNode fails (e.g. a lambda that cannot be eval'd in
        // this lexical scope), fall back to evaluating the entire let form
        // via the interpreter.
        last = self.emitNode(node) catch {
            return abandonLetForFallback(self, args, sequential, saved_locals, binding_root_count);
        };
        body_expr = rest;
    }

    try self.emitPopRoots(binding_root_count);
    self.locals.?.deinit();
    self.locals = saved_locals;
    return last;
}
