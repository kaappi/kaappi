const std = @import("std");
const ir = @import("ir.zig");
const types = @import("types.zig");
const printer = @import("printer.zig");
const native_decls = @import("native_decls.zig");
// #1499 forward-reference reservation + finalization stubs (mutual tail calls).
const tailcall = @import("llvm_emit_tailcall.zig");
// #1493 inline fixnum fast paths (+, -, *, <, =, null?).
const inline_prim = @import("llvm_emit_inline.zig");
// Native let / let* emission.
const let_emit = @import("llvm_emit_let.zig");

const Value = types.Value;

// #1499: tailcc + musttail give guaranteed constant-stack mutual tail calls,
// but only on backends whose LLVM target supports them. aarch64 and x86_64 both
// do; other hosts keep the uniform array ABI (best-effort `tail call` hint).
// RISC-V musttail is recent LLVM work and can be enabled here once verified.
pub const fast_tailcalls_supported = switch (@import("builtin").cpu.arch) {
    .aarch64, .x86_64 => true,
    else => false,
};

/// The LLVM `target triple` for a host `(arch, os)`, or null on an architecture
/// the native backend cannot target. A real triple exists only for aarch64 and
/// x86_64 (× the six supported OSes); every other arch would otherwise be
/// emitted as `unknown-unknown-unknown`, which the `-w` on the `zig cc` link
/// lets the driver silently override with the host default — so the link
/// *succeeds* and the user gets a binary that segfaults (#1656). This is the
/// single source of truth for both the emitted triple (emitPreamble) and
/// `native_backend_supported`, so a future port that adds an arch arm here
/// flips both at once. The `windows` arms use the gnu (MinGW) ABI: it matches
/// how the runtime lib is built and how `zig cc` links on a box without MSVC
/// (#1610).
pub fn targetTriple(arch: std.Target.Cpu.Arch, os: std.Target.Os.Tag) ?[]const u8 {
    return switch (arch) {
        .aarch64 => switch (os) {
            .macos => "aarch64-apple-macosx",
            .linux => "aarch64-unknown-linux-gnu",
            .windows => "aarch64-pc-windows-gnu",
            .freebsd => "aarch64-unknown-freebsd",
            .openbsd => "aarch64-unknown-openbsd",
            .netbsd => "aarch64-unknown-netbsd",
            else => "aarch64-unknown-unknown",
        },
        .x86_64 => switch (os) {
            .macos => "x86_64-apple-macosx",
            .linux => "x86_64-unknown-linux-gnu",
            .windows => "x86_64-pc-windows-gnu",
            .freebsd => "x86_64-unknown-freebsd",
            .openbsd => "x86_64-unknown-openbsd",
            .netbsd => "x86_64-unknown-netbsd",
            else => "x86_64-unknown-unknown",
        },
        else => null,
    };
}

/// Whether the LLVM native backend can target this host. False on the
/// interpreter-tier arches (riscv64, s390x, ppc64le, …) — `kaappi compile`,
/// `--emit-llvm`, and `kaappi doctor` consult this to refuse native compilation
/// *loudly* instead of emitting an unknown-triple module that links to a
/// crashing binary (#1656). The interpreter tier runs on every arch regardless.
/// See docs/dev/decisions/native-backend-architecture-scope.md.
pub const native_backend_supported = targetTriple(@import("builtin").cpu.arch, @import("builtin").os.tag) != null;

test "targetTriple: only aarch64/x86_64 are native-compilable; others refuse (#1656)" {
    // Supported hosts get a concrete triple for every supported OS.
    try std.testing.expect(targetTriple(.aarch64, .linux) != null);
    try std.testing.expect(targetTriple(.aarch64, .macos) != null);
    try std.testing.expect(targetTriple(.x86_64, .linux) != null);
    try std.testing.expect(targetTriple(.x86_64, .windows) != null);
    // The interpreter-tier arches have no triple, so native_backend_supported
    // is false there and `kaappi compile` refuses instead of linking a
    // segfaulting binary. A future port that adds one of these arms flips this
    // assertion and native_backend_supported together (single source of truth).
    try std.testing.expect(targetTriple(.riscv64, .linux) == null);
    try std.testing.expect(targetTriple(.s390x, .linux) == null);
    try std.testing.expect(targetTriple(.powerpc64le, .linux) == null);
    // native_backend_supported is exactly "the host has a triple".
    try std.testing.expectEqual(
        targetTriple(@import("builtin").cpu.arch, @import("builtin").os.tag) != null,
        native_backend_supported,
    );
}

// A named native function with at most this many fixed parameters gets a
// register-argument `tailcc` fast entry (see emitLambdaFunction). Beyond it the
// uniform array ABI is kept — the bound keeps register pressure and signature
// width reasonable; it is not an ABI limit and can be raised.
pub const max_fast_arity: usize = 8;

const NativeLambda = struct {
    llvm_name: []const u8,
    arity: u8,
    is_variadic: bool,
    // The `tailcc` register-argument entry (`@<name>.fast`) for a fixed-arity,
    // non-variadic, non-boxed function, or null when the function has only the
    // uniform array-ABI entry. Direct call sites emit register-argument calls —
    // and `musttail` for guaranteed mutual TCO — when this is set (#1499).
    fast_name: ?[]const u8 = null,
    // True when the function's native body reaches a *code* eval fallback
    // (`kaappi_eval_cached` — a variadic inner lambda, letrec, guard, …). Such a
    // fallback republishes the enclosing frame's params as globals
    // (bindParamsAsGlobals), which aliases across separate activations — a
    // pre-existing native-backend limitation. Direct call sites (immediate use)
    // are unaffected, but binding the function's *value* to a native closure
    // (#1500) would run that body from new contexts and widen the aliasing to
    // the common `(define a (f 1)) (define b (f 2))` pattern, so a function with
    // this set keeps its correctly-capturing interpreter-closure value. A quoted
    // constant (`kaappi_quote_cached`) is NOT a code fallback and does not set
    // this — quotes can't alias and the re-entrant-eval fix covers them.
    has_eval_fallback: bool = false,
};

// A top-level define reserved by the pre-scan (preScanReserve) so a *forward*
// tail call — a mutually-recursive callee defined later in the program — still
// resolves to a direct `musttail` to a stable `@r{i}.fast` name. The real body
// (when the define compiles natively) or a finalization stub (when it falls back
// to the interpreter) defines that symbol, so the reference always links (#1499).
pub const ReservedFast = struct {
    base: []const u8, // "@r{i}" — the uniform trampoline name
    fast: []const u8, // "@r{i}.fast" — the register-arg entry a musttail targets
    arity: u8,
    consumed: bool = false, // a top-level define of this name has been emitted
};

// One `locals` entry: a binding introduced by let/let*, a do-loop variable, or
// an internal define in a let body. When `boxed`, the slot alloca holds a box
// POINTER (assignment conversion, #1497) and reads/writes go through
// kaappi_box_ref / kaappi_box_set; otherwise the slot holds the value itself.
pub const LocalBinding = struct {
    slot: []const u8,
    boxed: bool = false,
};

pub const LLVMEmitter = struct {
    buf: std.ArrayList(u8),
    symbols: std.StringHashMap(u32),
    string_decls: std.ArrayList([]const u8),
    lambda_defs: std.ArrayList([]const u8),
    native_fns: std.StringHashMap(NativeLambda),
    rebound_globals: std.StringHashMap(void),
    // The VM's macro table, borrowed for the lifetime of emission (never
    // mutated here). Used only to keep native cond/case/do lowering (#1496)
    // from mis-compiling a macro use as a call to a same-named global: a form
    // that invokes a macro is not `exprNativeEmittable` and is sent to the
    // interpreter, which expands it. Null when the emitter is driven without a
    // VM (unit tests) — then no name is treated as a macro, which is correct
    // because those tests never exercise macros inside these forms.
    macros: ?*const std.StringHashMap(Value) = null,
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
    // One global cache slot per quoted-heap-constant call site (#1495), naming
    // each `@.quote_cache.N`. Distinct from eval_cache: it memoizes the built
    // constant itself (a pair/vector value), not a compiled Function. Same
    // module-monotonic, non-SavedScope discipline as the counters above.
    quote_cache_counter: u32,
    arena: std.heap.ArenaAllocator,
    backing_alloc: std.mem.Allocator,
    current_fn_name: ?[]const u8 = null,
    body_label: ?[]const u8 = null,
    current_block: []const u8 = "entry",
    rest_param_alloca: ?[]const u8 = null,
    rest_param_name: ?[]const u8 = null,
    // Lexical bindings introduced inside the frame body: let/let* bindings,
    // do-loop variables, and internal defines in a let body. Scope constructs
    // clone this map on entry and restore it on exit, so `put` on a name
    // shadows any same-named outer binding — including a boxed one: box-ness
    // is a per-binding attribute, never a name-level one (#1584).
    locals: ?std.StringHashMap(LocalBinding) = null,
    // Frame-level boxed bindings (assignment conversion, #1497): boxed fixed
    // params and, inside a native closure, the mirrored boxed captures — name
    // -> the alloca that holds the box POINTER. Reads go through
    // kaappi_box_ref and writes through kaappi_box_set, and nested closures
    // capture the box pointer, restoring the interpreter's by-location
    // semantics. Boxed let-locals do NOT live here — they are `locals`
    // entries with `.boxed = true`, so inner scopes shadow correctly (#1584).
    // bindParamsAsGlobals also reads this map as the frame-level "does this
    // frame have boxed params/upvalues" fact, which must stay visible even
    // while a let-local shadows the name.
    boxes: ?std.StringHashMap([]const u8) = null,
    // Number of GC roots pushed at the current frame's entry that must be popped
    // before every `ret` the frame emits: the boxed-param box slots (#1497) and,
    // for a variadic frame, the rest-list slot (#1498). Boxed frames disable
    // tail-call emission, so their only `ret` is the trailing one; a variadic
    // self-tail loop keeps tail calls, so emitCallNode/emitDirectCall also pop
    // these before a tail-call `ret` (a no-op when the count is zero). These are
    // pushed BEFORE the frame's loop header (body_label), so a self-tail call's
    // branch-back to that header does NOT pop them — they persist across
    // iterations (the rest-list slot is overwritten in place).
    frame_entry_roots: usize = 0,
    // Number of GC roots pushed by let/let* bindings AFTER the frame's loop
    // header that are live at the current tail position and must be released
    // before EVERY tail transfer: both a `ret` through an in-body tail call and
    // a self-tail call's branch-back to the header (which re-enters the let and
    // re-pushes them, so leaving them would leak one root set per iteration —
    // #1585). Distinct from frame_entry_roots precisely because the branch-back
    // must pop these but not those. emitLet publishes its binding_root_count
    // here while lowering its body in tail position and restores the prior value
    // afterwards; nested lets accumulate. Always 0 unless self.locals != null
    // (inside a rooted let), which keeps musttail disabled while it is nonzero.
    body_scope_roots: usize = 0,
    // True only while emitting a `tailcc` register-argument fast-entry body
    // (#1499). A tail call to another native fast entry may be a guaranteed
    // `musttail call tailcc` only here — the uniform (ccc) entries, closures,
    // and the top-level body never can (calling-convention mismatch).
    in_fast_entry: bool = false,
    // Forward-reference plumbing (#1499): populated once by preScanReserve and
    // then read-only. reserved_fast maps a reserved top-level define name to its
    // stable @r{i}/@r{i}.fast names; fulfilled_fast records names whose real
    // @r{i}.fast body was emitted; forward_referenced records names a musttail
    // was emitted to, so finalization can stub any that never got a real body.
    reserved_fast: std.StringHashMap(ReservedFast),
    fulfilled_fast: std.StringHashMap(void),
    forward_referenced: std.StringHashMap(void),
    // Monotonic counter naming the reserved @r{i} entries (see ReservedFast).
    reserved_counter: u32,

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
        locals: ?std.StringHashMap(LocalBinding),
        boxes: ?std.StringHashMap([]const u8),
        frame_entry_roots: usize,
        body_scope_roots: usize,
        in_fast_entry: bool,
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
            .frame_entry_roots = self.frame_entry_roots,
            .body_scope_roots = self.body_scope_roots,
            .in_fast_entry = self.in_fast_entry,
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
        self.frame_entry_roots = s.frame_entry_roots;
        self.body_scope_roots = s.body_scope_roots;
        self.in_fast_entry = s.in_fast_entry;
    }

    pub fn init(backing: std.mem.Allocator) LLVMEmitter {
        return .{
            .buf = .empty,
            .symbols = std.StringHashMap(u32).init(backing),
            .string_decls = .empty,
            .lambda_defs = .empty,
            .native_fns = std.StringHashMap(NativeLambda).init(backing),
            .rebound_globals = std.StringHashMap(void).init(backing),
            .reserved_fast = std.StringHashMap(ReservedFast).init(backing),
            .fulfilled_fast = std.StringHashMap(void).init(backing),
            .forward_referenced = std.StringHashMap(void).init(backing),
            .reserved_counter = 0,
            .params = null,
            .upvalues = null,
            .tmp_counter = 0,
            .label_counter = 0,
            .string_counter = 0,
            .sym_counter = 0,
            .lambda_counter = 0,
            .eval_cache_counter = 0,
            .quote_cache_counter = 0,
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
        self.reserved_fast.deinit();
        self.fulfilled_fast.deinit();
        self.forward_referenced.deinit();
        self.arena.deinit();
    }

    pub fn emitProgram(self: *LLVMEmitter, nodes: []const *ir.Node) EmitError!void {
        // Reserve stable @r{i}.fast names for top-level defines so a forward
        // mutually-recursive tail call still lowers to a direct musttail (#1499).
        try tailcall.preScanReserve(self, nodes);

        // Emit body into a separate buffer to collect string decls
        var body: std.ArrayList(u8) = .empty;
        defer body.deinit(self.backing_alloc);
        const saved_buf = self.buf;
        self.buf = body;

        self.write("  %vm = call ptr @kaappi_runtime_init()\n") catch return error.OutOfMemory;
        for (nodes) |node| {
            _ = self.emitNode(node) catch return error.OutOfMemory;
        }

        // Any reserved name a musttail targeted but that never got a real native
        // body (fell back to the interpreter) needs a forwarding stub so its
        // @r{i}.fast symbol resolves at link time (#1499). Appended to
        // lambda_defs — and its symbol interning done — before the symbol
        // constants below are emitted.
        try tailcall.emitForwardStubs(self);

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

        // One mutable global per quoted-heap-constant call site (#1495): 0 until
        // the literal is first built, then the cached pair/vector value. Emitted
        // at module scope for the same reason as the eval-cache slots above.
        var quote_slot: u32 = 0;
        while (quote_slot < self.quote_cache_counter) : (quote_slot += 1) {
            try self.print("@.quote_cache.{d} = internal global i64 0\n", .{quote_slot});
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
            .let_form => try let_emit.emitLet(self, node.data.let_form.args, false, node.ann.is_tail),
            .let_star => try let_emit.emitLet(self, node.data.let_star.args, true, node.ann.is_tail),
            .letrec => try self.emitLetEvalFallback(node.data.letrec.args, "letrec"),
            .letrec_star => try self.emitLetEvalFallback(node.data.letrec_star.args, "letrec*"),
            .passthrough => try self.emitPassthrough(node.data.passthrough),
            .sexpr_form => try self.emitSexprEval(node),
        };
    }

    pub fn emitConstant(self: *LLVMEmitter, value: Value) EmitError![]const u8 {
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

    // Mirrors emitGlobalRef's lexical resolution order (locals, boxes, rest
    // param, params, upvalues). Also consulted by the closure-tier
    // free-variable analysis in llvm_emit_lambda.zig: a shadowed name is a
    // capture even when a known global of the same name exists.
    pub fn isNameShadowed(self: *LLVMEmitter, name: []const u8) bool {
        if (self.locals) |loc| {
            if (loc.get(name) != null) return true;
        }
        if (self.boxes) |bx| {
            if (bx.get(name) != null) return true;
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

    // Whether `name` resolves to a top-level global rather than a lexical
    // capture: a built-in / special form (ir.isKnownGlobal), or a name reserved
    // for a top-level define emitted later in the program (#1499). The latter is
    // what lets a *forward* mutual-recursion reference — a callee defined after
    // its caller — count as a global call instead of a free variable that would
    // wrongly reject native compilation of the caller. Callers must still check
    // isNameShadowed first: a lexical binding of the same name outranks a global.
    pub fn isKnownOrReservedGlobal(self: *LLVMEmitter, name: []const u8) bool {
        return ir.isKnownGlobal(name) or self.reserved_fast.contains(name);
    }

    // Read through a box: `slot` holds the box pointer, the result temp holds
    // the box's current value.
    fn emitBoxRead(self: *LLVMEmitter, slot: []const u8) EmitError![]const u8 {
        const boxptr = try self.freshTemp();
        try self.print("  {s} = load i64, ptr {s}\n", .{ boxptr, slot });
        const tmp = try self.freshTemp();
        try self.print("  {s} = call i64 @kaappi_box_ref(i64 {s})\n", .{ tmp, boxptr });
        return tmp;
    }

    // Write through a box: `slot` holds the box pointer; the box's contents
    // are replaced so every closure over the same binding sees the new value.
    fn emitBoxWrite(self: *LLVMEmitter, slot: []const u8, val: []const u8) EmitError!void {
        const boxptr = try self.freshTemp();
        try self.print("  {s} = load i64, ptr {s}\n", .{ boxptr, slot });
        try self.print("  call void @kaappi_box_set(i64 {s}, i64 {s})\n", .{ boxptr, val });
    }

    fn emitGlobalRef(self: *LLVMEmitter, sym: Value) EmitError![]const u8 {
        if (!types.isSymbol(sym)) return error.UnsupportedNodeType;
        const name = types.symbolName(sym);

        // Innermost lexical bindings first: a let-local/do-var shadows any
        // same-named boxed param or boxed outer binding (#1584). A boxed
        // local's slot holds the box pointer; read through the box so a set!
        // from any closure over the same binding is visible (#1497).
        if (self.locals) |loc| {
            if (loc.get(name)) |b| {
                if (b.boxed) return self.emitBoxRead(b.slot);
                const tmp = try self.freshTemp();
                try self.print("  {s} = load i64, ptr {s}\n", .{ tmp, b.slot });
                return tmp;
            }
        }

        // Frame-level boxed bindings: assignment-converted params and, inside
        // a native closure, mirrored boxed captures (#1497).
        if (self.boxes) |bx| {
            if (bx.get(name)) |box_alloca| {
                return self.emitBoxRead(box_alloca);
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
                                // A variadic self-call needs at least the fixed
                                // params; the extras rebuild the rest list.
                                const arity_ok = if (self_fn.is_variadic)
                                    call.args.len >= self_fn.arity
                                else
                                    call.args.len == self_fn.arity;
                                if (arity_ok) {
                                    return self.emitSelfTailCall(call.args, self_fn.arity, self_fn.is_variadic, body_lbl);
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
                        // A fast-entry callee takes register arguments and, in
                        // tail position from another fast entry, a guaranteed
                        // `musttail` (#1499); otherwise the uniform array ABI.
                        if (native.fast_name) |fast|
                            return self.emitFastCall(fast, call.args, is_tail);
                        return self.emitDirectCall(native.llvm_name, call.args, is_tail);
                    }
                }
                // Forward reference to a reserved mutually-recursive callee
                // defined later in the program (#1499): only lowered to a direct
                // musttail when it is provably safe (tail position, inside a fast
                // entry, shadow stack balanced). Unsafe/non-tail forward refs
                // fall through to the indirect path, which observes the runtime
                // binding. The reserved @r{i}.fast is defined by the real body or
                // a finalization stub, so the reference always links.
                if (!self.rebound_globals.contains(op_name) and self.mustTailSafe(is_tail)) {
                    if (self.reserved_fast.get(op_name)) |rf| {
                        if (call.args.len == rf.arity) {
                            self.forward_referenced.put(op_name, {}) catch return error.OutOfMemory;
                            return self.emitFastCall(rf.fast, call.args, is_tail);
                        }
                    }
                }
            }
            if (!is_shadowed and !self.rebound_globals.contains(op_name)) {
                if (call.args.len == 2) {
                    if (inline_prim.tryEmitInlineBinary(self, op_name, call.args)) |result| return result;
                }
                if (call.args.len == 1) {
                    if (inline_prim.tryEmitInlineUnary(self, op_name, call.args[0])) |result| return result;
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
            // Balance the frame-entry GC roots (variadic rest list, boxed
            // params) AND any let-binding roots live in the body (#1585) before
            // returning through this tail call (#1498). A no-op when both are 0.
            try self.emitPopRoots(self.frame_entry_roots + self.body_scope_roots);
            try self.print("  ret i64 {s}\n", .{result});
            try self.emitOrphanAfterTail();
        }

        return result;
    }

    fn emitSelfTailCall(self: *LLVMEmitter, args: []const *ir.Node, arity: u8, is_variadic: bool, body_lbl: []const u8) EmitError![]const u8 {
        const arg_tmps = self.allocator().alloc([]const u8, args.len) catch return error.OutOfMemory;
        var root_count: usize = 0;
        for (args, 0..) |arg, i| {
            arg_tmps[i] = try self.emitNode(arg);
            if (i + 1 < args.len) {
                try self.emitRootPush(arg_tmps[i]);
                root_count += 1;
            }
        }

        // A variadic self-call rebuilds the rest list from the args past the
        // fixed arity, cons'ing them onto NIL in reverse so element order is
        // preserved. This runs BEFORE the roots are popped: kaappi_cons
        // allocates, and the fixed-param temps (rooted above) must survive it.
        // kaappi_cons roots its own two arguments, so each element and the
        // growing accumulator are safe across their cons; nothing allocates
        // between the last cons and the store below.
        var rest_tmp: []const u8 = "";
        if (is_variadic) {
            rest_tmp = try self.emitImm(@bitCast(types.NIL));
            var i = args.len;
            while (i > arity) {
                i -= 1;
                const new_pair = try self.freshTemp();
                try self.print("  {s} = call i64 @kaappi_cons(i64 {s}, i64 {s})\n", .{ new_pair, arg_tmps[i], rest_tmp });
                rest_tmp = new_pair;
            }
        }

        try self.emitPopRoots(root_count);

        // Overwrite only the fixed parameter slots in %args. A variadic frame
        // was entered with nargs >= arity, so %args has room for `arity` slots;
        // the extra args live in the rebuilt rest list and are never stored back
        // into %args (which may be smaller than this call's argument count).
        const fixed: usize = if (is_variadic) arity else args.len;
        for (0..fixed) |i| {
            const gep = try self.freshTemp();
            try self.print("  {s} = getelementptr i64, ptr %args, i64 {d}\n", .{ gep, i });
            try self.print("  store i64 {s}, ptr {s}\n", .{ arg_tmps[i], gep });
        }
        if (is_variadic) {
            // Overwrite the frame's rest slot (already a frame GC root from
            // emitRestListBuilder) in place; the loop body re-reads it.
            if (self.rest_param_alloca) |alloca| {
                try self.print("  store i64 {s}, ptr {s}\n", .{ rest_tmp, alloca });
            }
        }

        // Release the let-binding roots pushed since the loop header before
        // branching back to it (#1585): the loop re-enters those lets and
        // re-pushes fresh roots, so leaving them stacked leaks one set per
        // iteration until the shadow stack overflows. frame_entry_roots (the
        // rest-list slot) live BEFORE the header and are deliberately NOT popped
        // — they persist across iterations, overwritten in place above.
        try self.emitPopRoots(self.body_scope_roots);

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

    pub fn inLexicalScope(self: *LLVMEmitter) bool {
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
    // reach the same binding — in particular a let-local shadowing a boxed
    // name must receive the store, not the outer box (#1584).
    fn emitStoreToVariable(self: *LLVMEmitter, name: []const u8, val: []const u8) EmitError!void {
        if (self.locals) |loc| {
            if (loc.get(name)) |b| {
                // A boxed binding is mutated through its heap cell so the new
                // value is visible to every closure that captured the same
                // box (#1497).
                if (b.boxed) return self.emitBoxWrite(b.slot, val);
                try self.print("  store i64 {s}, ptr {s}\n", .{ val, b.slot });
                return;
            }
        }
        if (self.boxes) |bx| {
            if (bx.get(name)) |box_alloca| {
                return self.emitBoxWrite(box_alloca, val);
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

    const forms = @import("llvm_emit_forms.zig");

    // True if `name` is bound as a syntax transformer in the VM's macro table.
    // Guards native lowering of cond/case/do (#1496): a macro use must not be
    // compiled as a call to a same-named global — it has to reach the
    // interpreter, which expands it.
    pub fn isMacroName(self: *LLVMEmitter, name: []const u8) bool {
        const m = self.macros orelse return false;
        return m.contains(name);
    }

    fn emitSexprEval(self: *LLVMEmitter, node: *const ir.Node) EmitError![]const u8 {
        if (node.tag != .sexpr_form) return error.UnsupportedNodeType;
        const sf = node.data.sexpr_form;
        // cond/case/do are lowered natively when every sub-form is emittable in
        // the current lexical scope; otherwise they fall back like any other
        // sexpr form (#1496). The dispatch is here so nested occurrences reached
        // via emitNode take the same path.
        switch (sf.form) {
            .cond => return forms.emitCond(self, sf.args, node.ann.is_tail),
            .case_form => return forms.emitCase(self, sf.args, node.ann.is_tail),
            .do_form => return forms.emitDo(self, sf.args, node.ann.is_tail),
            else => {},
        }
        return self.emitFormEval(sf.args, sf.form.keyword());
    }

    fn emitLetEvalFallback(self: *LLVMEmitter, args: Value, form_name: []const u8) EmitError![]const u8 {
        return self.emitFormEval(args, form_name);
    }

    pub fn emitFormEval(self: *LLVMEmitter, args: Value, form_name: []const u8) EmitError![]const u8 {
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
                            // #1500: bind the global to a native closure over the
                            // compiled entry instead of eval'ing the whole define
                            // form. Fixed-arity, and not when the body reaches a
                            // code eval fallback (its bindParamsAsGlobals aliases
                            // across activations — see NativeLambda.has_eval_fallback);
                            // both keep the eval path, and `@f` still serves direct
                            // call sites.
                            if (self.native_fns.get(fn_name)) |info| {
                                if (!info.is_variadic and !info.has_eval_fallback) {
                                    const val = try self.emitNativeFnClosureValue(info, fn_name);
                                    const sym = try self.internSymbol(fn_name);
                                    try self.print("  call void @kaappi_define_global(ptr %vm, ptr {s}, i64 {d}, i64 {s})\n", .{ sym, fn_name.len, val });
                                    return self.emitVoid();
                                }
                            }
                        }
                    }
                }
            }
        }
        return self.emitEvalExpr(expr);
    }

    // Build the runtime Value for a natively-compiled top-level function as a
    // native closure over its uniform C-ABI entry (#1500). A value use of the
    // name — passing it to `map`/`apply`, `(eq? f f)`, returning it — then runs
    // the native `@f` instead of an interpreter closure, and startup no longer
    // parses and compiles the lambda through the eval fallback. Valid only for a
    // fixed-arity function: `callNativeClosure` dispatches native closures by
    // exact arity, so a variadic entry keeps the eval-fallback value. Referencing
    // the entry here also takes its address, which keeps LLVM from dropping the
    // `internal` fast-entry trampoline it would otherwise discard (#1499).
    fn emitNativeFnClosureValue(self: *LLVMEmitter, info: NativeLambda, name: []const u8) EmitError![]const u8 {
        const name_str = try self.internString(name);
        const result = try self.freshTemp();
        try self.print("  {s} = call i64 @kaappi_create_native_closure(ptr %vm, ptr {s}, ptr null, i64 0, i64 {d}, ptr {s}, i64 {d})\n", .{ result, info.llvm_name, info.arity, name_str, name.len });
        return result;
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
            self.locals.?.put(name, .{ .slot = alloca }) catch return error.OutOfMemory;
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

        const val = blk: {
            // #1500: the value compiled to a native function — bind the global
            // to a native closure over its uniform entry instead of eval'ing the
            // lambda source. Fixed-arity, and not when the body reaches a code
            // eval fallback (its bindParamsAsGlobals aliases across activations;
            // see NativeLambda.has_eval_fallback and emitNativeFnClosureValue).
            if (self.native_fns.get(name)) |info| {
                if (!info.is_variadic and !info.has_eval_fallback)
                    break :blk try self.emitNativeFnClosureValue(info, name);
            }
            break :blk if (types.isPair(data.value))
                try self.emitEvalExpr(data.value)
            else if (types.isSymbol(data.value))
                try self.emitGlobalRef(data.value)
            else
                try self.emitConstant(data.value);
        };

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

    // Whether a tail call here can be a guaranteed `musttail call tailcc`
    // (#1499). It must be in tail position, inside a `tailcc` fast-entry body
    // (matching calling convention), and the shadow stack must hold no roots a
    // torn-down frame would strand: not inside a rooted `let` (self.locals is
    // non-null only there, and body_scope_roots is likewise nonzero only there —
    // #1585) and with the frame-entry roots — rest list / boxed params, always 0
    // in a fast entry — already balanced. LLVM also requires the musttail to
    // immediately precede its `ret`, which these guarantee.
    fn mustTailSafe(self: *LLVMEmitter, is_tail: bool) bool {
        return is_tail and self.in_fast_entry and self.locals == null and
            self.frame_entry_roots == 0 and self.body_scope_roots == 0;
    }

    // Direct call to a native fast entry (#1499): arguments are passed by value
    // in registers (no caller-frame args array), so a real `musttail` is sound.
    // Emits `musttail call tailcc` when mustTailSafe, a `tail call tailcc` hint
    // for a tail call from a non-fast caller, else a plain `call tailcc`.
    fn emitFastCall(self: *LLVMEmitter, fast_name: []const u8, args: []const *ir.Node, is_tail: bool) EmitError![]const u8 {
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

        const musttail = self.mustTailSafe(is_tail);
        const prefix: []const u8 = if (musttail)
            "musttail call tailcc"
        else if (is_tail)
            "tail call tailcc"
        else
            "call tailcc";

        const result = try self.freshTemp();
        // By-value args: (ptr %vm, i64 a0, …, ptr null). Fast entries are the
        // direct-call targets — closed functions — so upvalues is always null.
        try self.print("  {s} = {s} i64 {s}(ptr %vm", .{ result, prefix, fast_name });
        for (arg_tmps) |a| try self.print(", i64 {s}", .{a});
        try self.write(", ptr null)\n");

        if (is_tail) {
            // A fast entry has no frame-entry roots, so for musttail this is a
            // no-op and the musttail immediately precedes ret as LLVM requires;
            // a non-fast tail caller may still have frame-entry roots and, inside
            // a let, body-scope roots to balance (#1498, #1585). musttail is only
            // chosen when both counts are 0 (see mustTailSafe).
            if (!musttail) try self.emitPopRoots(self.frame_entry_roots + self.body_scope_roots);
            try self.print("  ret i64 {s}\n", .{result});
            try self.emitOrphanAfterTail();
        }

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
            // Balance the frame-entry GC roots (variadic rest list, boxed
            // params) AND any let-binding roots live in the body (#1585) before
            // returning through this tail call (#1498). A no-op when both are 0.
            try self.emitPopRoots(self.frame_entry_roots + self.body_scope_roots);
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

    // A quoted heap constant (pair/vector/… — anything with no immediate
    // representation) is serialized to a `(quote …)` source string and built
    // once via the caching runtime entry point (#1495). Plain @kaappi_eval
    // re-reads and re-builds the constant on every execution, which is both a
    // hot-path cliff and a correctness divergence: the interpreter compiles a
    // quote to a single constant-pool entry, so every evaluation of one literal
    // returns the SAME object (`eq?`). @kaappi_quote_cached memoizes the built
    // constant in a per-call-site global slot, reproducing that per-site sharing
    // in native code. Distinct source occurrences get distinct slots, so two
    // textually separate literals stay non-`eq?`, again matching the interpreter.
    fn emitQuotedEvalExpr(self: *LLVMEmitter, value: Value) EmitError![]const u8 {
        const printed = printer.valueToString(self.backing_alloc, value, .write) catch return error.OutOfMemory;
        defer self.backing_alloc.free(printed);
        const source = std.fmt.allocPrint(self.backing_alloc, "(quote {s})", .{printed}) catch return error.OutOfMemory;
        defer self.backing_alloc.free(source);
        const str_name = try self.internString(source);
        const slot_name = try self.nextQuoteCacheSlot();
        const tmp = try self.freshTemp();
        try self.print("  {s} = call i64 @kaappi_quote_cached(ptr %vm, ptr {s}, i64 {d}, ptr {s})\n", .{ tmp, str_name, source.len, slot_name });
        return tmp;
    }

    fn nextQuoteCacheSlot(self: *LLVMEmitter) EmitError![]const u8 {
        const id = self.quote_cache_counter;
        self.quote_cache_counter += 1;
        return std.fmt.allocPrint(self.allocator(), "@.quote_cache.{d}", .{id}) catch return error.OutOfMemory;
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
        // native_compiler refuses on unsupported arches before reaching here
        // (#1656), so targetTriple is non-null in every real compile; the
        // `orelse` is a defensive fallback so a stray direct call still emits
        // *something* rather than crashing the compiler.
        const triple = targetTriple(@import("builtin").cpu.arch, @import("builtin").os.tag) orelse "unknown-unknown-unknown";
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
        // for +, -, * (emitInlineArith in llvm_emit_inline.zig).
        try self.write("declare { i64, i1 } @llvm.sadd.with.overflow.i64(i64, i64)\n");
        try self.write("declare { i64, i1 } @llvm.ssub.with.overflow.i64(i64, i64)\n");
        try self.write("declare { i64, i1 } @llvm.smul.with.overflow.i64(i64, i64)\n");
    }

    pub fn emitRootPush(self: *LLVMEmitter, tmp: []const u8) EmitError!void {
        const slot = try self.freshTemp();
        try self.print("  {s} = alloca i64, align 8\n", .{slot});
        try self.print("  store i64 {s}, ptr {s}\n", .{ tmp, slot });
        try self.print("  call void @kaappi_gc_push_root(ptr {s})\n", .{slot});
    }

    pub fn emitRootPushAlloca(self: *LLVMEmitter, alloca: []const u8) EmitError!void {
        try self.print("  call void @kaappi_gc_push_root(ptr {s})\n", .{alloca});
    }

    pub fn emitPopRoots(self: *LLVMEmitter, n: usize) EmitError!void {
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
