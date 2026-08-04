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

// #1410 param-globals binding lives with the lambda emitter; the #1497
// capture/mutation analysis and eval-fallback detection live in freevars.
const lambda = @import("llvm_emit_lambda.zig");
const freevars = @import("llvm_emit_freevars.zig");

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
    // It declines outright when an enclosing let's locals are in scope, since
    // those it cannot publish — the error then abandons that outer let too, so
    // the interpreter gets the whole scope in one piece (#1862).
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

// Abandon a partially emitted native let and compile the whole form via the
// interpreter instead. Native let lowering is transactional (#1586): binding
// initializers are written into self.buf as they are lowered, but the
// interpreter fallback re-evaluates the WHOLE form, so any already-emitted init
// with side effects would run once natively and again from the fallback.
// Truncating self.buf back to the pre-let checkpoint discards every stranded
// instruction — allocas, initializer side effects, box creation, and the GC
// root pushes alike — so there is exactly one evaluation and nothing to pop
// (the push_root calls were discarded with the rest). Restoring current_block
// reopens the block the let began in: an initializer's in-scope control flow
// (an `if`, say) may have split that block into terminated predecessors and a
// fresh successor, all now truncated away, leaving the checkpoint block live
// again for the fallback to emit into.
fn abandonLetForFallback(self: *LLVMEmitter, args: Value, sequential: bool, saved_locals: ?std.StringHashMap(llvm_emit.LocalBinding), checkpoint: Checkpoint) EmitError![]const u8 {
    self.buf.shrinkRetainingCapacity(checkpoint.buf_len);
    self.current_block = checkpoint.block;
    self.body_scope_roots = checkpoint.body_scope_roots;
    self.scope_define_names = checkpoint.scope_define_names;
    self.locals.?.deinit();
    self.locals = saved_locals;
    return emitLetFallback(self, args, sequential);
}

// The emitter state emitLet must be able to roll back to when it abandons a
// partially lowered form to the interpreter (#1586). Captured before any of the
// let's own IR is written.
const Checkpoint = struct {
    buf_len: usize,
    block: []const u8,
    body_scope_roots: usize,
    scope_define_names: []const []const u8,
};

// The bound name of a `(define <symbol> <expr>)` body form, or null for
// anything else — including `(define (f …) …)`, which `lowerDefine` turns into a
// passthrough that never reaches emitDefine's internal path (#1854). Returning
// null for the shorthand is what makes `emitPassthrough` decline it in a lexical
// scope, abandoning this let to the interpreter (#1861); modelling it here
// instead would mean holding a closure value in one of these slots.
fn headDefineName(form: Value) ?[]const u8 {
    if (!types.isPair(form)) return null;
    const head = types.car(form);
    if (!types.isSymbol(head) or !std.mem.eql(u8, types.symbolName(head), "define")) return null;
    const rest = types.cdr(form);
    if (!types.isPair(rest)) return null;
    const target = types.car(rest);
    if (!types.isSymbol(target)) return null;
    if (!types.isPair(types.cdr(rest))) return null;
    return types.symbolName(target);
}

// Same ceiling as this file's binding arrays: a body with more head defines than
// this abandons to the interpreter rather than leaving the extras unrooted.
const max_head_defines = 32;

pub fn emitLet(self: *LLVMEmitter, args: Value, sequential: bool, is_tail: bool) EmitError![]const u8 {
    const bindings = types.car(args);
    const body_list = types.cdr(args);

    // Snapshot the emitter state before writing any of this let's IR, so an
    // abandon partway through can roll back to exactly here (#1586). Captured up
    // front — the upfront fallbacks below emit nothing before returning, so they
    // never need it, but capturing here keeps the pre-let block/position exact.
    const checkpoint: Checkpoint = .{
        .buf_len = self.buf.items.len,
        .block = self.current_block,
        .body_scope_roots = self.body_scope_roots,
        .scope_define_names = self.scope_define_names,
    };

    // #827: If the let form (bindings or body) contains sub-expressions
    // that need interpreter eval fallback (cond, do, letrec, etc.),
    // compile the entire let via the interpreter to preserve correct
    // lexical scoping. #1807: the same goes for a macro use anywhere in the
    // bindings or body — this let's own bindings/body are lowered below via a
    // macro-blind scratch IR, so an unguarded macro call would compile as a
    // same-named global lookup instead of expanding.
    if (freevars.sexprNeedsEvalFallback(args) or freevars.sexprHasMacroUse(self, args)) {
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
            if (!freevars.bodyHasCapturingLambda(self, body_list, (&v)[0..1])) continue;
            if (!freevars.sexprBodySetsName(body_list, v)) {
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

    // Boxed let-locals are `locals` entries with `.boxed = true`, NOT
    // additions to the frame-level `self.boxes` map: box-ness is an attribute
    // of the individual binding, so an inner plain binding shadows an outer
    // boxed one (and vice versa) through the ordinary locals clone (#1584).
    const saved_locals = self.locals;
    self.locals = if (saved_locals) |existing|
        existing.clone() catch return error.OutOfMemory
    else
        std.StringHashMap(llvm_emit.LocalBinding).init(self.allocator());

    var binding_root_count: usize = 0;

    if (!sequential) {
        var binding_allocas: [32][]const u8 = undefined;
        var var_names: [32][]const u8 = undefined;
        var count: usize = 0;
        var blist = bindings;
        while (blist != types.NIL and types.isPair(blist)) {
            if (count >= 32) {
                return abandonLetForFallback(self, args, sequential, saved_locals, checkpoint);
            }
            const binding = types.car(blist);
            const var_sym = types.car(binding);
            const init_expr = types.car(types.cdr(binding));
            if (!types.isSymbol(var_sym)) {
                return abandonLetForFallback(self, args, sequential, saved_locals, checkpoint);
            }

            const node = self.lowerScoped(init_expr, false, &.{}) catch {
                return abandonLetForFallback(self, args, sequential, saved_locals, checkpoint);
            };
            const alloca = try self.freshTemp();
            try self.print("  {s} = alloca i64, align 8\n", .{alloca});
            // #827: an init that cannot be emitted in this lexical scope
            // (e.g. a lambda) sends the whole let to the interpreter,
            // like the body path below.
            const val = self.emitNode(node) catch {
                return abandonLetForFallback(self, args, sequential, saved_locals, checkpoint);
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
            self.locals.?.put(var_names[i], .{
                .slot = binding_allocas[i],
                .boxed = nameInList(box_names[0..box_count], var_names[i]),
            }) catch return error.OutOfMemory;
        }
        binding_root_count = count;
    } else {
        var blist = bindings;
        var count: usize = 0;
        while (blist != types.NIL and types.isPair(blist)) {
            // Same 32-binding ceiling as the parallel-let path: the capture
            // analysis above collects at most 32 names, so a binding past that
            // would be registered unboxed even when captured+mutated.
            if (count >= 32) {
                return abandonLetForFallback(self, args, sequential, saved_locals, checkpoint);
            }
            const binding = types.car(blist);
            const var_sym = types.car(binding);
            const init_expr = types.car(types.cdr(binding));
            if (!types.isSymbol(var_sym)) {
                return abandonLetForFallback(self, args, sequential, saved_locals, checkpoint);
            }

            const node = self.lowerScoped(init_expr, false, &.{}) catch {
                return abandonLetForFallback(self, args, sequential, saved_locals, checkpoint);
            };
            const val = self.emitNode(node) catch {
                return abandonLetForFallback(self, args, sequential, saved_locals, checkpoint);
            };
            const alloca = try self.freshTemp();
            try self.print("  {s} = alloca i64, align 8\n", .{alloca});
            // Box a captured+mutated let*-local; later inits in this same
            // let* then read it through the box (#1497).
            const is_boxed = nameInList(box_names[0..box_count], types.symbolName(var_sym));
            if (is_boxed) {
                const box = try self.freshTemp();
                try self.print("  {s} = call i64 @kaappi_make_box(ptr %vm, i64 {s})\n", .{ box, val });
                try self.print("  store i64 {s}, ptr {s}\n", .{ box, alloca });
            } else {
                try self.print("  store i64 {s}, ptr {s}\n", .{ val, alloca });
            }
            self.locals.?.put(types.symbolName(var_sym), .{
                .slot = alloca,
                .boxed = is_boxed,
            }) catch return error.OutOfMemory;
            try self.emitRootPushAlloca(alloca);
            binding_root_count += 1;
            count += 1;
            blist = types.cdr(blist);
        }
    }

    // R7RS internal defines at the head of the body are letrec* bindings, so
    // mint and root every slot here — before any initializer runs — and hand the
    // set to emitDefine, whose internal path then stores into an already-rooted
    // slot instead of minting one of its own (#1854). The slot it used to mint
    // was never pushed on the shadow stack, so an allocation later in the body
    // could collect the value out from under the binding: `(let ((a 1)) (define
    // xs (list 11 22 33)) <allocate a lot> (car xs))` returned whatever had been
    // built in xs's recycled memory, silently, in a compiled binary.
    //
    // Rooting from this one place is also what keeps the push count static: these
    // pushes dominate the whole body, unlike one emitted at a define nested
    // inside an `if`, which would run on one path only while the pop count below
    // is fixed. Those defines are exactly the ones absent from this set, and
    // emitDefine declines them so the body loop's abandon hands the whole form to
    // the interpreter (which binds a non-head define correctly).
    var define_names: [max_head_defines][]const u8 = undefined;
    var define_count: usize = 0;
    {
        var be = body_list;
        head_defines: while (be != types.NIL and types.isPair(be)) : (be = types.cdr(be)) {
            const dname = headDefineName(types.car(be)) orelse break;
            if (define_count >= max_head_defines) {
                return abandonLetForFallback(self, args, sequential, saved_locals, checkpoint);
            }
            // A redefinition of the same name reuses the first slot: every store
            // and every read resolves through `locals`, so one rooted slot per
            // name is exactly right, and a second would only be dead weight.
            for (define_names[0..define_count]) |n| {
                if (std.mem.eql(u8, n, dname)) continue :head_defines;
            }
            const alloca = try self.freshTemp();
            try self.print("  {s} = alloca i64, align 8\n", .{alloca});
            // The slot is rooted before its own initializer runs, so it has to
            // hold a scannable Value from the start. VOID is how this backend
            // spells letrec*'s bound-but-not-yet-assigned, and it also replaces
            // the uninitialized load a self-reference in the initializer used to
            // get from the freshly minted alloca.
            try self.print("  store i64 {d}, ptr {s}\n", .{ @as(i64, @bitCast(types.VOID)), alloca });
            try self.emitRootPushAlloca(alloca);
            binding_root_count += 1;
            self.locals.?.put(dname, .{ .slot = alloca }) catch return error.OutOfMemory;
            define_names[define_count] = dname;
            define_count += 1;
        }
    }
    // On the emitter's arena, not this frame's stack: the slice is read from
    // arbitrarily deep inside body emission and is restored on both exits below,
    // but an arena slice stays valid even if some future exit path forgets to.
    self.scope_define_names = self.allocator().dupe([]const u8, define_names[0..define_count]) catch
        return error.OutOfMemory;

    // #1585: while the body is lowered in tail position, the binding roots must
    // be released before every tail transfer — a `ret` through an in-body tail
    // call and a self-tail call's branch-back to the loop header alike.
    // Publishing them into body_scope_roots threads them into the same
    // pop-before-tail accounting the tail-call emitters already apply, so the
    // roots are dropped on those paths instead of being stranded past the `ret`
    // (or re-pushed unbounded each loop iteration). The trailing emitPopRoots
    // below still covers the ordinary fall-through (non-tail) exit; on a
    // tail-transfer path it lands in the dead orphan block after the `ret`.
    // Boxed lets set body_tail = false and pop only at fall-through.
    if (body_tail) self.body_scope_roots += binding_root_count;

    var last: []const u8 = "";
    var body_expr = body_list;
    while (body_expr != types.NIL and types.isPair(body_expr)) {
        const rest = types.cdr(body_expr);
        const expr_is_tail = body_tail and (rest == types.NIL or !types.isPair(rest));
        const node = self.lowerScoped(types.car(body_expr), expr_is_tail, &.{}) catch {
            return abandonLetForFallback(self, args, sequential, saved_locals, checkpoint);
        };
        // #827: if emitNode fails (e.g. a lambda that cannot be eval'd in
        // this lexical scope), fall back to evaluating the entire let form
        // via the interpreter.
        last = self.emitNode(node) catch {
            return abandonLetForFallback(self, args, sequential, saved_locals, checkpoint);
        };
        body_expr = rest;
    }

    self.body_scope_roots = checkpoint.body_scope_roots;
    self.scope_define_names = checkpoint.scope_define_names;
    try self.emitPopRoots(binding_root_count);
    self.locals.?.deinit();
    self.locals = saved_locals;
    return last;
}
