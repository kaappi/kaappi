const std = @import("std");
const types = @import("types.zig");
const memory = @import("memory.zig");
const expander = @import("expander.zig");
const forms = @import("compiler_forms.zig");
const advanced = @import("compiler_advanced.zig");
const passthrough = @import("compiler_passthrough.zig");
const macro = @import("compiler_macro.zig");
const ir_mod = @import("ir.zig");
const compiler_ir = @import("compiler_ir.zig");
const timings = @import("timings.zig");
const globals_mod = @import("globals.zig");
const printer = @import("printer.zig");
const Value = types.Value;
const OpCode = types.OpCode;

pub threadlocal var syntax_error_detail: [512]u8 = [_]u8{0} ** 512;
pub threadlocal var syntax_error_detail_len: usize = 0;

pub fn getSyntaxErrorDetail() []const u8 {
    return syntax_error_detail[0..syntax_error_detail_len];
}

// Span of the form a compile error was raised for, so the reporter can render
// `file:line:col` and a full range instead of just the top-level datum line
// (kaappi#1506). Set by `noteCompileErrorSpan` from IR lowering's error path;
// like `syntax_error_detail`, it is a threadlocal channel out of the compiler,
// cleared at each compile entry and after the reporter consumes it.
pub threadlocal var compile_error_span: types.Span = .{};
pub threadlocal var compile_error_span_set: bool = false;

/// Record the failing form's span, keeping the first (deepest) one recorded for
/// this compile. A no-op once a span is set — see the caller in `ir.lowerExpr`.
pub fn noteCompileErrorSpan(sp: types.Span) void {
    if (compile_error_span_set) return;
    if (!sp.known()) return;
    compile_error_span = sp;
    compile_error_span_set = true;
}

/// The recorded compile-error span, or null if none was captured (the reporter
/// then falls back to the top-level datum position).
pub fn getCompileErrorSpan() ?types.Span {
    return if (compile_error_span_set) compile_error_span else null;
}

/// Clear the channel. Called at each compile entry (before a fresh attempt) and
/// after the reporter consumes the span, so a stale span never leaks forward.
pub fn resetCompileErrorSpan() void {
    compile_error_span_set = false;
    compile_error_span = .{};
}

pub const CompileError = error{
    OutOfMemory,
    InvalidSyntax,
    UndefinedVariable,
    TooManyConstants,
    TooManyLocals,
    InternalLimit,
    MacroExpansionLimit,
    JumpOutOfRange,
};

var next_binding_id: u32 = 0;

pub fn freshBindingId() u32 {
    const id = next_binding_id;
    next_binding_id += 1;
    return id;
}

const Local = struct {
    name: []const u8,
    depth: u16,
    slot: u16,
    binding_id: u32,
    is_boxed: bool = false,
    // Register alias for a global, injected during macro expansion so a
    // template's free reference pierces use-site shadowing. set! through
    // the alias must write back to the global (see compileSet).
    is_global_alias: bool = false,
    // The actual global's name, when is_global_alias is true. `name` itself
    // is the reference's hygienic rename (e.g. __hyg_N_count), not the bare
    // global name — kept distinct from any use-site identifier of the same
    // spelling (kaappi#1832) — so compileSet's write-through must target
    // THIS name instead of `name`. Unused (empty) when is_global_alias is
    // false.
    alias_global_name: []const u8 = "",
};

const Upvalue = struct {
    index: u16,
    is_local: bool,
};

const BodyMacro = struct {
    name: []const u8,
    saved: ?Value,
};

const build_options = @import("build_options");
const MAX_COMPILER_REGISTERS: u16 = std.math.maxInt(u16);

pub const Compiler = struct {
    gc: *memory.GC,
    func: *types.Function,
    locals: std.ArrayList(Local),
    upvalues: std.ArrayList(Upvalue),
    macros: std.StringHashMap(Value),
    globals: ?*std.StringHashMap(Value) = null,
    lib_env: ?*std.StringHashMap(Value) = null,
    lib_env_val: Value = types.NIL,
    // True whenever `globals` is a partial environment map rather than
    // vm.globals — a library's lib_env, or a restricted (environment ...) —
    // so a name's *absence* from it proves nothing about what that name will
    // resolve to at run time. Read only by IR.isRedefined, which then declines
    // to treat the name as a known primitive: a compile-time optimization
    // gate, nothing more. Whether the run-time lookup may fall back to
    // vm.globals is the separate Function.restricted_globals, which
    // compileExpressionInEnv sets from its EnvKind and not from this
    // (kaappi#1860).
    restricted_env: bool = false,
    // Names that are `set!` somewhere in the top-level form being compiled.
    // Owned by the top-level compile() frame and inherited by child compilers
    // so nested lambda bodies see the same suppression set. Consulted by the
    // constant folders (IR and legacy) to avoid folding calls to a name that
    // may be reassigned before the call executes.
    set_targets: ?*std.StringHashMap(void) = null,
    // True when the pre-scan that built `set_targets` had to stop early (see
    // SetScanBudget), making that map an under-approximation. Both consumers
    // then behave as if *every* name were a `set!` target: box every local and
    // fold nothing. Costs optimization, never correctness — the opposite bias
    // from a silently-truncated scan, which would leave a mutated local
    // unboxed and reintroduce #1168/#1250 (kaappi#1775).
    set_targets_all: bool = false,
    scope_depth: u16 = 0,
    next_register: u16 = 0,
    parent: ?*Compiler = null,
    in_body_scope: bool = false,
    // Body-scoped define-syntax tracking (R7RS 5.3): while depth > 0,
    // compileDefineSyntax records each registration so the enclosing body
    // restores the macro table on exit. At depth 0 (top level) definitions
    // persist, which top-level (begin ...) splicing relies on.
    body_macros: std.ArrayList(BodyMacro) = .empty,
    body_macro_depth: u16 = 0,
    current_line: u32 = 0,
    current_col: u32 = 0,
    macro_expansion_depth: u16 = 0,
    macro_expansion_steps: u32 = 0,
    // Set by expandAndCompileMacroUse when a macro expansion is a fixed
    // point (output equals input).  compileForm skips the macro check
    // for this keyword so the built-in special form handles it instead.
    suppress_macro_name: ?[]const u8 = null,

    pub fn init(gc: *memory.GC) CompileError!Compiler {
        const func = gc.allocFunction() catch return CompileError.OutOfMemory;
        gc.extra_roots.append(gc.allocator, types.makePointer(&func.header)) catch return CompileError.OutOfMemory;
        return .{
            .gc = gc,
            .func = func,
            .locals = .empty,
            .upvalues = .empty,
            .macros = std.StringHashMap(Value).init(gc.allocator),
        };
    }

    pub fn deinit(self: *Compiler) void {
        self.locals.deinit(self.gc.allocator);
        self.upvalues.deinit(self.gc.allocator);
        self.macros.deinit();
        self.body_macros.deinit(self.gc.allocator);
    }

    pub fn unrootFunction(gc: *memory.GC, func: *types.Function) void {
        const func_val = types.makePointer(&func.header);
        for (gc.extra_roots.items, 0..) |v, i| {
            if (v == func_val) {
                _ = gc.extra_roots.orderedRemove(i);
                return;
            }
        }
    }

    pub fn initChild(parent: *Compiler) CompileError!Compiler {
        const func = parent.gc.allocFunction() catch return CompileError.OutOfMemory;
        func.env = parent.lib_env;
        func.env_val = parent.lib_env_val;
        // Inherited with `env`, which it qualifies: whether a name missing
        // from that env may fall back to vm.globals is a property of the
        // environment, not of how deeply nested the reference happens to be.
        func.restricted_globals = parent.func.restricted_globals;
        func.source_line = parent.func.source_line;
        func.source_name = parent.func.source_name;
        parent.gc.extra_roots.append(parent.gc.allocator, types.makePointer(&func.header)) catch return CompileError.OutOfMemory;
        return .{
            .gc = parent.gc,
            .func = func,
            .locals = .empty,
            .upvalues = .empty,
            .macros = std.StringHashMap(Value).init(parent.gc.allocator),
            .globals = parent.globals,
            .lib_env = parent.lib_env,
            .lib_env_val = parent.lib_env_val,
            .restricted_env = parent.restricted_env,
            .set_targets = parent.set_targets,
            .set_targets_all = parent.set_targets_all,
            .parent = parent,
        };
    }

    /// Enter a body scope for define-syntax tracking. Returns a mark for
    /// the matching endBodyMacroScope.
    pub fn beginBodyMacroScope(self: *Compiler) usize {
        self.body_macro_depth += 1;
        return self.body_macros.items.len;
    }

    /// Restore macro-table entries registered since the matching
    /// beginBodyMacroScope, newest first so re-registrations of the same
    /// name unwind correctly.
    pub fn endBodyMacroScope(self: *Compiler, mark: usize) CompileError!void {
        self.body_macro_depth -= 1;
        while (self.body_macros.items.len > mark) {
            const entry = self.body_macros.pop().?;
            if (entry.saved) |old_val| {
                try self.macros.put(entry.name, old_val);
            } else {
                _ = self.macros.remove(entry.name);
            }
        }
    }

    /// Record a macro registration for restoration at body-scope exit.
    /// No-op at top level, where define-syntax must persist.
    pub fn recordBodyMacro(self: *Compiler, name: []const u8) CompileError!void {
        if (self.body_macro_depth == 0) return;
        self.body_macros.append(self.gc.allocator, .{
            .name = name,
            .saved = self.macros.get(name),
        }) catch return CompileError.OutOfMemory;
    }

    pub fn lookupMacro(self: *const Compiler, name: []const u8) ?Value {
        // Check this compiler's macros first
        if (self.macros.get(name)) |v| return v;
        // Then check parent chain
        var p = self.parent;
        while (p) |par| {
            if (par.macros.get(name)) |v| return v;
            p = par.parent;
        }
        return null;
    }

    pub fn populateDebugLocals(self: *Compiler) void {
        if (self.locals.items.len > 0) {
            const debug = self.gc.allocator.alloc(types.DebugLocal, self.locals.items.len) catch return;
            for (self.locals.items, 0..) |local, i| {
                debug[i] = .{ .name = local.name, .slot = local.slot };
            }
            self.func.debug_locals = debug;
        }
    }

    pub fn emit(self: *Compiler, byte: u8) CompileError!void {
        self.func.code.append(self.gc.allocator, byte) catch return CompileError.OutOfMemory;
    }

    pub fn emitOp(self: *Compiler, op: OpCode) CompileError!void {
        try self.emit(@intFromEnum(op));
    }

    pub fn emitU16(self: *Compiler, val: u16) CompileError!void {
        try self.emit(@truncate(val >> 8));
        try self.emit(@truncate(val & 0xFF));
    }

    pub fn emitI16(self: *Compiler, val: i16) CompileError!void {
        const unsigned: u16 = @bitCast(val);
        try self.emitU16(unsigned);
    }

    pub fn addConstant(self: *Compiler, value: Value) CompileError!u16 {
        // Check if constant already exists
        for (self.func.constants.items, 0..) |c, i| {
            if (c == value) return @intCast(i);
        }
        if (self.func.constants.items.len >= 65536) return CompileError.TooManyConstants;
        self.func.constants.append(self.gc.allocator, value) catch return CompileError.OutOfMemory;
        return @intCast(self.func.constants.items.len - 1);
    }

    /// Build a reference to `name`'s pristine `(scheme base)` binding,
    /// immune to any later top-level/library redefinition of `name`
    /// (#1715). Returns an ordinary symbol carrying
    /// `globals_mod.base_binding_prefix`; get_global/call_global recognize
    /// the prefix and resolve the suffix through the base-library registry
    /// instead of vm.globals (see that constant's doc comment for why this
    /// must stay a runtime, by-name lookup rather than a pre-resolved
    /// constant). Used for compiler-synthesized references to
    /// `list`/`apply`/`call-with-values` in let-values/let*-values's
    /// desugaring, which must always mean the standard procedures
    /// regardless of what the user's program does with those names.
    pub fn trueBuiltinRefOrSymbol(gc: *memory.GC, name: []const u8) CompileError!Value {
        return globals_mod.baseBindingSymbol(gc, name) catch return CompileError.OutOfMemory;
    }

    /// Emit code loading `name`'s pristine `(scheme base)` binding into
    /// `reg` (#1715, see `trueBuiltinRefOrSymbol`).
    pub fn emitTrueBuiltinLoad(self: *Compiler, name: []const u8, reg: u16) CompileError!void {
        const ref = try trueBuiltinRefOrSymbol(self.gc, name);
        const idx = try self.addConstant(ref);
        try self.emitOp(.get_global);
        try self.emitU16(reg);
        try self.emitU16(idx);
    }

    pub fn currentOffset(self: *Compiler) usize {
        return self.func.code.items.len;
    }

    pub fn patchJump(self: *Compiler, offset: usize) CompileError!void {
        const dist = @as(isize, @intCast(self.currentOffset())) - @as(isize, @intCast(offset)) - 2;
        if (dist < std.math.minInt(i16) or dist > std.math.maxInt(i16)) {
            return CompileError.JumpOutOfRange;
        }
        const jump_dist: i16 = @intCast(dist);
        const unsigned: u16 = @bitCast(jump_dist);
        self.func.code.items[offset] = @truncate(unsigned >> 8);
        self.func.code.items[offset + 1] = @truncate(unsigned & 0xFF);
    }

    pub fn allocReg(self: *Compiler) CompileError!u16 {
        if (self.next_register >= MAX_COMPILER_REGISTERS) return CompileError.TooManyLocals;
        const reg = self.next_register;
        self.next_register += 1;
        // Record the high-water mark of register usage for this function.
        // This is the exact count of registers the frame can ever use, which
        // lets continuation capture copy only the live register window instead
        // of a conservative upper bound. All register allocation funnels through
        // here, so next_register's peak is a sound upper bound.
        if (self.next_register > self.func.locals_count) {
            self.func.locals_count = self.next_register;
        }
        return reg;
    }

    pub fn freeReg(self: *Compiler) void {
        if (self.next_register > 0) self.next_register -= 1;
    }

    pub fn resolveLocal(self: *Compiler, name: []const u8) ?u16 {
        var i: usize = self.locals.items.len;
        while (i > 0) {
            i -= 1;
            if (std.mem.eql(u8, self.locals.items[i].name, name)) {
                return self.locals.items[i].slot;
            }
        }
        return null;
    }

    pub fn resolveBindingId(self: *Compiler, name: []const u8) ?u32 {
        var i: usize = self.locals.items.len;
        while (i > 0) {
            i -= 1;
            if (std.mem.eql(u8, self.locals.items[i].name, name)) {
                return self.locals.items[i].binding_id;
            }
        }
        return null;
    }

    /// Pure predicate: is `name` bound as a lexical variable — a local in this
    /// compiler or any enclosing compiler? Unlike `resolveUpvalue`, this has no
    /// side effects (it does not register upvalues), so the IR optimizer can
    /// call it while deciding whether a call to a primitive name is safe to
    /// constant-fold. A lambda parameter (or enclosing local) that shadows a
    /// built-in must suppress folding: the reference is to the binding, not the
    /// primitive. See issue #790.
    pub fn isLexicallyBound(self: *const Compiler, name: []const u8) bool {
        var comp: ?*const Compiler = self;
        while (comp) |c| {
            for (c.locals.items) |local| {
                if (std.mem.eql(u8, local.name, name)) return true;
            }
            comp = c.parent;
        }
        return false;
    }

    pub fn isLocalBoxed(self: *Compiler, name: []const u8) bool {
        var i: usize = self.locals.items.len;
        while (i > 0) {
            i -= 1;
            if (std.mem.eql(u8, self.locals.items[i].name, name)) {
                return self.locals.items[i].is_boxed;
            }
        }
        return false;
    }

    /// The real global name backing a global-alias local, or null if `name`
    /// isn't a global-alias local. See Local.alias_global_name.
    pub fn globalAliasTargetName(self: *Compiler, name: []const u8) ?[]const u8 {
        var i: usize = self.locals.items.len;
        while (i > 0) {
            i -= 1;
            if (std.mem.eql(u8, self.locals.items[i].name, name)) {
                if (!self.locals.items[i].is_global_alias) return null;
                return self.locals.items[i].alias_global_name;
            }
        }
        return null;
    }

    pub fn isSlotBoxed(self: *Compiler, slot: u16) bool {
        for (self.locals.items) |local| {
            if (local.slot == slot) return local.is_boxed;
        }
        return false;
    }

    pub fn markLocalBoxedBySlot(self: *Compiler, slot: u16) CompileError!void {
        // Flip every local aliasing this slot (hygienic-capture aliases share
        // the slot of the local they mirror), so all names read through the
        // box. Emit the box_local op only on the first transition — if any
        // entry was already boxed, the register already holds a box.
        var had_boxed = false;
        var transitioned = false;
        for (self.locals.items) |*local| {
            if (local.slot == slot) {
                if (local.is_boxed) {
                    had_boxed = true;
                } else {
                    local.is_boxed = true;
                    transitioned = true;
                }
            }
        }
        if (transitioned and !had_boxed) {
            try self.emitOp(.box_local);
            try self.emitU16(slot);
        }
    }

    /// Scan `expr` for set! targets and add them to the current set_targets map.
    /// Called from expandAndCompileMacroUse after expansion to discover targets
    /// introduced by macro templates (#1250). Does NOT re-expand nested macro
    /// uses: each nested use gets its own scan when compilation expands it,
    /// and recursive expansion here made deep macro towers (e.g. CPS-style
    /// pattern matchers) quadratic — every level re-expanded its whole subtree.
    pub fn scanSetTargets(self: *Compiler, expr: Value) CompileError!void {
        if (self.set_targets) |st| {
            try collectSetTargets(self, expr, st, 0, null);
        }
    }

    /// Box a local if its name is a set! target anywhere in the top-level form.
    /// R7RS §3.4: set! modifies the store (a heap location), not the
    /// continuation. Register-allocated mutated locals violate this when a
    /// continuation is restored, because the register snapshot rolls back the
    /// mutation. Boxing ensures the register holds a pointer to a heap cell
    /// whose car survives restore. (#1168)
    pub fn boxIfSetTarget(self: *Compiler, name: []const u8, slot: u16) CompileError!void {
        const targets = self.set_targets orelse return;
        if (self.set_targets_all or targets.contains(name)) {
            try self.markLocalBoxedBySlot(slot);
        }
    }

    pub fn resolveUpvalue(self: *Compiler, name: []const u8) CompileError!?u16 {
        if (self.parent) |parent| {
            if (parent.resolveLocal(name)) |local_slot| {
                return try self.addUpvalue(local_slot, true);
            }
            if (try parent.resolveUpvalue(name)) |upvalue_idx| {
                return try self.addUpvalue(upvalue_idx, false);
            }
        }
        return null;
    }

    fn addUpvalue(self: *Compiler, index: u16, is_local: bool) CompileError!u16 {
        for (self.upvalues.items, 0..) |uv, i| {
            if (uv.index == index and uv.is_local == is_local) {
                return @intCast(i);
            }
        }
        // upvalue_count and upvalue indices are u16; refuse to overflow rather
        // than panic on the @intCast below (mirrors the register cap in allocReg).
        if (self.upvalues.items.len >= std.math.maxInt(u16)) return CompileError.TooManyLocals;
        self.upvalues.append(self.gc.allocator, .{ .index = index, .is_local = is_local }) catch return CompileError.OutOfMemory;
        self.func.upvalue_count = @intCast(self.upvalues.items.len);
        return @intCast(self.upvalues.items.len - 1);
    }

    // -- Scope management --

    pub fn beginScope(self: *Compiler) void {
        self.scope_depth += 1;
    }

    pub fn endScope(self: *Compiler) void {
        while (self.locals.items.len > 0 and
            self.locals.items[self.locals.items.len - 1].depth >= self.scope_depth)
        {
            _ = self.locals.pop();
            self.freeReg();
        }
        self.scope_depth -= 1;
    }

    pub fn addLocal(self: *Compiler, name: []const u8, slot: u16) CompileError!void {
        self.locals.append(self.gc.allocator, .{
            .name = name,
            .depth = self.scope_depth,
            .slot = slot,
            .binding_id = freshBindingId(),
        }) catch return CompileError.OutOfMemory;
    }

    // -- Public compilation API --

    pub fn compile(self: *Compiler, expr: Value, is_tail: bool) CompileError!void {
        // Root the source datum for the whole compile: the expander and the
        // derived-form compilers allocate (triggering GC), and the datum tree
        // is otherwise reachable only through this unrooted argument. Without
        // this, not-yet-compiled tails of the form (e.g. string literals) can
        // be swept mid-compilation and end up as dangling constant-pool entries.
        var expr_root = expr;
        self.gc.pushRoot(&expr_root);
        defer self.gc.popRoot();

        // Scan the whole top-level form for `set!` targets so the constant
        // folders never fold a call to a name that is reassigned within it
        // (including in nested lambda bodies, which inherit this set).
        var set_targets = std.StringHashMap(void).init(self.gc.allocator);
        defer set_targets.deinit();
        var budget = SetScanBudget{ .expansions_left = prescan_expansion_limit };
        try collectSetTargets(self, expr_root, &set_targets, 0, &budget);
        self.set_targets = &set_targets;
        self.set_targets_all = budget.truncated;
        if (budget.truncated) prescan_truncations += 1;
        defer {
            self.set_targets = null;
            self.set_targets_all = false;
        }

        // Lower AST to IR, run analysis and optimizations, then emit bytecode.
        var ir = ir_mod.IR.init(self.gc.allocator);
        ir.globals = self.globals;
        ir.restricted_env = self.restricted_env;
        ir.compiler = self;
        ir.set_targets = self.set_targets;
        defer ir.deinit();
        const root = try ir_mod.lowerAndOptimize(&ir, expr_root, &self.macros, is_tail);

        const dst = try self.allocReg();
        // `--timings` (kaappi#1515): bytecode emission is the outermost `emit`
        // scope. Passthrough macro uses re-enter the compiler from inside here;
        // their nested expand/lower/optimize/emit are attributed correctly by
        // the self-time stack. `defer` fires even on a `try` error path.
        {
            timings.begin(.emit);
            defer timings.end();
            try compiler_ir.compileFromNode(self, root, dst, is_tail);
        }
        try self.emitOp(.@"return");
        try self.emitU16(dst);

        self.populateDebugLocals();
    }

    pub fn compileMultiple(self: *Compiler, exprs: []const Value) CompileError!void {
        // Keep all source data rooted across compilation (see compile()).
        const roots_base = self.gc.extra_roots.items.len;
        defer self.gc.extra_roots.shrinkRetainingCapacity(roots_base);
        for (exprs) |e| self.gc.extra_roots.append(self.gc.allocator, e) catch return CompileError.OutOfMemory;

        if (exprs.len == 0) {
            const dst = try self.allocReg();
            try self.emitOp(.load_void);
            try self.emitU16(dst);
            try self.emitOp(.@"return");
            try self.emitU16(dst);
            return;
        }

        var dst: u16 = 0;
        for (exprs, 0..) |expr, i| {
            // Lower each expression through the IR pipeline.
            var ir = ir_mod.IR.init(self.gc.allocator);
            ir.globals = self.globals;
            ir.restricted_env = self.restricted_env;
            ir.compiler = self;
            ir.set_targets = self.set_targets;
            defer ir.deinit();
            const root = try ir_mod.lowerAndOptimize(&ir, expr, &self.macros, false);

            dst = try self.allocReg();
            {
                timings.begin(.emit); // see compile(): outermost emit scope (kaappi#1515)
                defer timings.end();
                try compiler_ir.compileFromNode(self, root, dst, false);
            }
            if (i < exprs.len - 1) {
                self.freeReg();
            }
        }
        try self.emitOp(.@"return");
        try self.emitU16(dst);

        self.populateDebugLocals();
    }

    pub fn compileDesugared(self: *Compiler, form: Value, dst: u16, is_tail: bool) CompileError!void {
        var rooted = form;
        self.gc.pushRoot(&rooted);
        defer self.gc.popRoot();
        return self.compileExprViaIR(rooted, dst, is_tail);
    }

    pub fn compileExprViaIR(self: *Compiler, expr: Value, dst: u16, is_tail: bool) CompileError!void {
        var ir = ir_mod.IR.init(self.gc.allocator);
        ir.globals = self.globals;
        ir.restricted_env = self.restricted_env;
        ir.compiler = self;
        ir.set_targets = self.set_targets;
        defer ir.deinit();
        const root = try ir_mod.lowerAndOptimize(&ir, expr, &self.macros, is_tail);
        try compiler_ir.compileFromNode(self, root, dst, is_tail);
    }

    pub fn compileExpr(self: *Compiler, expr: Value, dst: u16, is_tail: bool) CompileError!void {
        if (types.isFixnum(expr)) {
            const idx = try self.addConstant(expr);
            try self.emitOp(.load_const);
            try self.emitU16(dst);
            try self.emitU16(idx);
            return;
        }

        if (expr == types.TRUE) {
            try self.emitOp(.load_true);
            try self.emitU16(dst);
            return;
        }
        if (expr == types.FALSE) {
            try self.emitOp(.load_false);
            try self.emitU16(dst);
            return;
        }
        if (expr == types.NIL) {
            try self.emitOp(.load_nil);
            try self.emitU16(dst);
            return;
        }

        if (types.isSymbol(expr)) {
            return self.compileVariable(expr, dst);
        }

        if (types.isString(expr)) {
            const idx = try self.addConstant(expr);
            try self.emitOp(.load_const);
            try self.emitU16(dst);
            try self.emitU16(idx);
            return;
        }

        if (types.isChar(expr)) {
            const idx = try self.addConstant(expr);
            try self.emitOp(.load_const);
            try self.emitU16(dst);
            try self.emitU16(idx);
            return;
        }

        if (types.isFlonum(expr)) {
            const idx = try self.addConstant(expr);
            try self.emitOp(.load_const);
            try self.emitU16(dst);
            try self.emitU16(idx);
            return;
        }

        if (types.isBignum(expr)) {
            const idx = try self.addConstant(expr);
            try self.emitOp(.load_const);
            try self.emitU16(dst);
            try self.emitU16(idx);
            return;
        }

        if (types.isComplex(expr)) {
            const idx = try self.addConstant(expr);
            try self.emitOp(.load_const);
            try self.emitU16(dst);
            try self.emitU16(idx);
            return;
        }

        if (types.isRationalObj(expr)) {
            const idx = try self.addConstant(expr);
            try self.emitOp(.load_const);
            try self.emitU16(dst);
            try self.emitU16(idx);
            return;
        }

        if (types.isVector(expr)) {
            const idx = try self.addConstant(expr);
            try self.emitOp(.load_const);
            try self.emitU16(dst);
            try self.emitU16(idx);
            return;
        }

        if (types.isBytevector(expr)) {
            const idx = try self.addConstant(expr);
            try self.emitOp(.load_const);
            try self.emitU16(dst);
            try self.emitU16(idx);
            return;
        }

        if (types.isPair(expr)) {
            if (self.gc.source_spans.get(expr)) |sp| {
                if (sp.line > 0 and (sp.line != self.current_line or sp.col != self.current_col)) {
                    self.current_line = sp.line;
                    self.current_col = sp.col;
                    try self.func.line_table.append(self.gc.allocator, .{
                        .offset = @intCast(self.func.code.items.len),
                        .line = sp.line,
                        .col = sp.col,
                    });
                }
            }
            return self.compileForm(expr, dst, is_tail);
        }

        return CompileError.InvalidSyntax;
    }

    pub fn compileVariable(self: *Compiler, sym: Value, dst: u16) CompileError!void {
        const name = types.symbolName(sym);

        if (self.resolveLocal(name)) |slot| {
            if (self.isLocalBoxed(name)) {
                try self.emitOp(.get_box_local);
                try self.emitU16(dst);
                try self.emitU16(slot);
            } else if (slot != dst) {
                try self.emitOp(.move);
                try self.emitU16(dst);
                try self.emitU16(slot);
            }
            return;
        }

        if (try self.resolveUpvalue(name)) |idx| {
            try self.emitOp(.get_upvalue);
            try self.emitU16(dst);
            try self.emitU16(idx);
            return;
        }

        const sym_idx = try self.addConstant(sym);
        try self.emitOp(.get_global);
        try self.emitU16(dst);
        try self.emitU16(sym_idx);
    }

    fn compileForm(self: *Compiler, expr: Value, dst: u16, is_tail: bool) CompileError!void {
        const head = types.car(expr);
        const args = types.cdr(expr);

        if (types.isSymbol(head)) {
            const name = types.symbolName(head);

            // Safety net: a user-text provenance marker that survived to
            // compilation is transparent — compile the wrapped datum.
            if (std.mem.eql(u8, name, expander.USERTEXT_MARKER)) {
                return self.compileExpr(args, dst, is_tail);
            }

            const effective_name = types.stripHygienicPrefix(name);

            // If the effective name is a variable binding in scope but NOT a
            // hygienic rename, it's a function call, not a special form. The
            // binding may be a same-scope local or an upvalue captured from an
            // enclosing function, so probe both (mirrors the `apply` and macro
            // checks below). Probing an upvalue registers it in this function,
            // but a shadowing name compiles to a call referencing that same
            // upvalue anyway, so the side effect is harmless. The cheap name
            // comparison is checked first so hygienic renames short-circuit
            // without touching the scope-resolution machinery.
            const is_shadowed = std.mem.eql(u8, effective_name, name) and
                (self.resolveLocal(name) != null or (try self.resolveUpvalue(name)) != null);

            // R7RS has no reserved words: an imported macro may shadow a
            // special form keyword (e.g. SRFI-219 redefines `define`).
            // Check macros BEFORE special forms so the macro wins.
            // suppress_macro_name is set when a macro expansion produced a
            // fixed-point (identity) — skip re-expansion to let the built-in
            // special form handle the base case.
            if (!is_shadowed) {
                const suppressed = if (self.suppress_macro_name) |smn| std.mem.eql(u8, name, smn) else false;
                if (suppressed) self.suppress_macro_name = null;
                if (!suppressed) {
                    const macro_hit: ?Value = if (self.lookupMacro(name)) |t|
                        if (self.resolveLocal(name) != null or (try self.resolveUpvalue(name)) != null) null else t
                    else
                        null;
                    if (macro_hit) |transformer| {
                        return macro.expandAndCompileMacroUse(self, expr, name, transformer, dst, is_tail);
                    }
                }
            }

            // Primitive forms — only if not shadowed by local binding
            if (!is_shadowed) {
                if (std.mem.eql(u8, effective_name, "quote")) return passthrough.compileQuote(self, args, dst);
                if (std.mem.eql(u8, effective_name, "if")) return passthrough.compileIf(self, args, dst, is_tail);
                if (std.mem.eql(u8, effective_name, "lambda")) return self.compileLambda(args, dst, null);
                if (std.mem.eql(u8, effective_name, "define")) return self.compileDefine(args, dst);
                if (std.mem.eql(u8, effective_name, "define-record-type")) return self.compileDefineRecordType(args, dst);
                if (std.mem.eql(u8, effective_name, "define-values")) return self.compileDefineValues(args, dst);
                if (std.mem.eql(u8, effective_name, "set!")) return self.compileSet(args, dst);
                if (std.mem.eql(u8, effective_name, "begin")) return self.compileBegin(args, dst, is_tail);

                // Derived expression forms (in compiler_forms.zig)
                if (std.mem.eql(u8, effective_name, "and")) return forms.compileAnd(self, args, dst, is_tail);
                if (std.mem.eql(u8, effective_name, "or")) return forms.compileOr(self, args, dst, is_tail);
                if (std.mem.eql(u8, effective_name, "when")) return forms.compileWhen(self, args, dst, is_tail);
                if (std.mem.eql(u8, effective_name, "unless")) return forms.compileUnless(self, args, dst, is_tail);
                if (std.mem.eql(u8, effective_name, "cond")) return forms.compileCond(self, args, dst, is_tail);
                if (std.mem.eql(u8, effective_name, "let")) return forms.compileLet(self, args, dst, is_tail);
                if (std.mem.eql(u8, effective_name, "let*")) return forms.compileLetStar(self, args, dst, is_tail);
                if (std.mem.eql(u8, effective_name, "let-values")) return forms.compileLetValues(self, args, dst, is_tail);
                if (std.mem.eql(u8, effective_name, "let*-values")) return forms.compileLetStarValues(self, args, dst, is_tail);
                if (std.mem.eql(u8, effective_name, "letrec")) return forms.compileLetrec(self, args, dst, is_tail);
                if (std.mem.eql(u8, effective_name, "letrec*")) return forms.compileLetrecStar(self, args, dst, is_tail);
                if (std.mem.eql(u8, effective_name, "case")) return forms.compileCase(self, args, dst, is_tail);
                if (std.mem.eql(u8, effective_name, "case-lambda")) return forms.compileCaseLambda(self, args, dst);
                if (std.mem.eql(u8, effective_name, "cond-expand")) return forms.compileCondExpand(self, args, dst, is_tail);
                if (std.mem.eql(u8, effective_name, "do")) return forms.compileDo(self, args, dst, is_tail);
                if (std.mem.eql(u8, effective_name, "guard")) return forms.compileGuard(self, args, dst, is_tail);
                if (std.mem.eql(u8, effective_name, "delay")) return self.compileDelay(args, dst);
                if (std.mem.eql(u8, effective_name, "delay-force")) return self.compileDelayForce(args, dst);

                // Quasiquote
                if (std.mem.eql(u8, effective_name, "quasiquote")) return advanced.compileQuasiquote(self, args, dst);

                // Parameterize
                if (std.mem.eql(u8, effective_name, "parameterize")) return advanced.compileParameterize(self, args, dst, is_tail);

                // syntax-error
                if (std.mem.eql(u8, effective_name, "syntax-error")) {
                    formatSyntaxError(args);
                    return CompileError.InvalidSyntax;
                }

                // Macro forms (kept in compiler.zig)
                if (std.mem.eql(u8, effective_name, "define-syntax")) return macro.compileDefineSyntax(self, args, dst);
                if (std.mem.eql(u8, effective_name, "let-syntax")) return macro.compileLetSyntax(self, args, dst, is_tail);
                if (std.mem.eql(u8, effective_name, "letrec-syntax")) return macro.compileLetrecSyntax(self, args, dst, is_tail);
                if (std.mem.eql(u8, effective_name, "syntax-rules")) return CompileError.InvalidSyntax;
            } // end if (!is_local)
        }

        if (is_tail and types.isSymbol(head)) {
            const sym_name = types.symbolName(head);
            if (std.mem.eql(u8, sym_name, "apply")) {
                if (self.resolveLocal(sym_name) == null and
                    (try self.resolveUpvalue(sym_name)) == null)
                {
                    return passthrough.compileApplyTail(self, expr, dst);
                }
            }
            if (std.mem.eql(u8, sym_name, "call-with-values")) {
                if (self.resolveLocal(sym_name) == null and
                    (try self.resolveUpvalue(sym_name)) == null)
                {
                    return passthrough.compileCallWithValuesTail(self, expr, dst);
                }
            }
            if (std.mem.eql(u8, sym_name, "call-with-current-continuation") or
                std.mem.eql(u8, sym_name, "call/cc"))
            {
                if (self.resolveLocal(sym_name) == null and
                    (try self.resolveUpvalue(sym_name)) == null)
                {
                    return passthrough.compileCallCCTail(self, expr, dst);
                }
            }
            if (std.mem.eql(u8, sym_name, "eval")) {
                if (self.resolveLocal(sym_name) == null and
                    (try self.resolveUpvalue(sym_name)) == null)
                {
                    return passthrough.compileEvalTail(self, expr, dst);
                }
            }
        }

        return passthrough.compileCall(self, expr, dst, is_tail);
    }

    const compiler_lambda = @import("compiler_lambda.zig");

    pub fn compileLambda(self: *Compiler, args: Value, dst: u16, name: ?[]const u8) CompileError!void {
        return compiler_lambda.compileLambda(self, args, dst, name);
    }

    fn compileBody(self: *Compiler, body: Value) CompileError!void {
        return compiler_lambda.compileBody(self, body);
    }

    fn compileDefine(self: *Compiler, args: Value, dst: u16) CompileError!void {
        return compiler_lambda.compileDefine(self, args, dst);
    }

    fn compileDefineRecordType(self: *Compiler, args: Value, dst: u16) CompileError!void {
        return compiler_lambda.compileDefineRecordType(self, args, dst);
    }

    fn compileDefineValues(self: *Compiler, args: Value, dst: u16) CompileError!void {
        return compiler_lambda.compileDefineValues(self, args, dst);
    }

    fn compileSet(self: *Compiler, args: Value, dst: u16) CompileError!void {
        return compiler_lambda.compileSet(self, args, dst);
    }

    fn compileBegin(self: *Compiler, args: Value, dst: u16, is_tail: bool) CompileError!void {
        return compiler_lambda.compileBegin(self, args, dst, is_tail);
    }

    fn compileDelay(self: *Compiler, args: Value, dst: u16) CompileError!void {
        return compiler_lambda.compileDelay(self, args, dst);
    }

    fn compileDelayForce(self: *Compiler, args: Value, dst: u16) CompileError!void {
        return compiler_lambda.compileDelayForce(self, args, dst);
    }

    pub fn emitLoadValue(self: *Compiler, dst: u16, val: Value) CompileError!void {
        if (val == types.NIL) {
            try self.emitOp(.load_nil);
            try self.emitU16(dst);
        } else if (val == types.TRUE) {
            try self.emitOp(.load_true);
            try self.emitU16(dst);
        } else if (val == types.FALSE) {
            try self.emitOp(.load_false);
            try self.emitU16(dst);
        } else {
            const idx = try self.addConstant(val);
            try self.emitOp(.load_const);
            try self.emitU16(dst);
            try self.emitU16(idx);
        }
    }
};

fn formatSyntaxError(args: Value) void {
    var w: std.Io.Writer = .fixed(&syntax_error_detail);
    var rest = args;
    // First argument is the message string.
    if (types.isPair(rest)) {
        const msg = types.car(rest);
        printer.printValue(&w, msg, .display) catch {};
        rest = types.cdr(rest);
    }
    // Remaining arguments are irritants.
    while (types.isPair(rest)) {
        w.print(" ", .{}) catch {};
        printer.printValue(&w, types.car(rest), .write) catch {};
        rest = types.cdr(rest);
    }
    syntax_error_detail_len = w.buffered().len;
}

/// Work limit for one top-level `set!` pre-scan (kaappi#1775).
///
/// The pre-scan expands macros so it can see a `set!` a template introduces
/// (#1250). That makes it a speculative *evaluator* of compile-time macro
/// code, and it explores branches the real compiler never takes: at
/// `(m kt kf)`, where `m` is a helper the enclosing expansion defined with
/// `define-syntax`, the scan has no binding for `m`, so it treats `kt` and
/// `kf` as ordinary sub-forms and expands macros inside *both*. The real
/// compiler registers `m`, expands it, and follows exactly one. Every such
/// fork doubles the work, so macros that generate macros — SRFI 148's
/// `em-syntax-rules`, SRFI 257's CK-machine combinators — cost time
/// exponential in the number of forks.
///
/// Exceeding the limit is safe by construction: the scan sets `truncated`,
/// and Compiler.set_targets_all makes both consumers assume every name is a
/// `set!` target. A truncated scan therefore loses optimization, never
/// correctness.
///
/// 4096 is ~2.5x the highest count any non-pathological top-level form in
/// this repo's Scheme suites reaches (p99.99 = 1649 expansions; 87% of forms
/// need none at all) and well under the 6299+ the macro-generating cases
/// start at. That headroom matters: a truncated scan boxes every local in the
/// form, measured at ~2x runtime on compute-heavy code, so ordinary programs
/// must never reach the limit.
///
/// A `var` only so tests can lower it and exercise the truncation path
/// without a multi-second pathological program; nothing in the compiler
/// writes it. Threadlocal for the same reason as `ir.optimize_enabled`: an
/// SRFI-18 child thread compiling concurrently keeps the default rather than
/// racing on whatever a test left in a shared global.
pub threadlocal var prescan_expansion_limit: u32 = 4096;

/// Number of top-level forms whose `set!` pre-scan truncated. Diagnostic
/// only — read by tests to assert the guard did (or did not) engage.
pub threadlocal var prescan_truncations: u64 = 0;

const SetScanBudget = struct {
    expansions_left: u32,
    /// Set when the scan stopped early (budget exhausted or depth cap hit),
    /// meaning `out` is an under-approximation of the real target set.
    truncated: bool = false,
};

/// Recursively collect the symbol names that appear as the target of a
/// `(set! <name> ...)` anywhere in `expr` into `out`. Used to suppress
/// constant folding of those names within the enclosing form (see
/// Compiler.set_targets) and to box locals for correct continuation
/// semantics (R7RS §3.4). Conservative: it scans every sub-form except
/// the interior of `quote`d data. When `budget` is non-null and a known
/// macro is encountered, it is expanded and the expansion is scanned
/// (#1250). Only the top-level pre-scan expands; the per-expansion Part B
/// scan passes null (see scanSetTargets).
///
/// `self` is needed only to expand macros, i.e. only when `budget` is
/// non-null — a null `budget` makes the whole walk a pure function of `expr`,
/// which is what `scanSetTargetsWithoutMacros` below exposes to the LLVM
/// native backend (it has no Compiler at all).
fn collectSetTargets(self: ?*Compiler, expr: Value, out: *std.StringHashMap(void), depth: u16, budget: ?*SetScanBudget) CompileError!void {
    // This is the scan's *own* recursion cap, deliberately not shared with
    // compiler_macro.MAX_MACRO_EXPANSION_DEPTH despite both being 256: they
    // count different things. That one bounds the real expansion of code that
    // will be compiled, and exceeding it is a user-visible error (KP2003).
    // This one bounds a speculative walk that also descends into branches the
    // compiler discards, so it is reached by programs whose real expansion
    // depth never comes close — measured: every SRFI 257 suite trips this cap
    // several times per run while compiling and passing normally. Tying the
    // two together would assert an equivalence the measurements contradict.
    if (depth > 256) {
        if (budget) |b| b.truncated = true;
        return;
    }
    var cur = expr;
    while (types.isPair(cur)) {
        const head = types.car(cur);
        if (types.isSymbol(head)) {
            const hname = types.stripHygienicPrefix(types.symbolName(head));
            if (std.mem.eql(u8, hname, "quote")) return; // literal data, not code
            if (std.mem.eql(u8, hname, "set!")) {
                const rest = types.cdr(cur);
                if (types.isPair(rest)) {
                    const target = types.car(rest);
                    if (types.isSymbol(target)) {
                        out.put(types.symbolName(target), {}) catch return CompileError.OutOfMemory;
                    }
                }
            } else if (budget) |b| {
                // Only a budgeted scan expands, and only a budgeted scan is
                // ever handed a Compiler — so `self.?` below is reached only
                // when `maybe_macro` was non-null, which requires one.
                const maybe_macro = if (self) |c| c.lookupMacro(types.symbolName(head)) else null;
                if (maybe_macro) |transformer| {
                    if (b.expansions_left == 0) {
                        b.truncated = true;
                        return;
                    }
                    b.expansions_left -= 1;
                    const c = self.?;
                    // Best-effort expansion: uses an empty UseSiteBindingCheck
                    // (no locals exist at pre-scan time), so patterns with
                    // literals may diverge from the real expansion.  Part B
                    // (scanSetTargets in expandAndCompileMacroUse) corrects
                    // any misses at real-expansion time.
                    c.gc.no_collect += 1;
                    const expanded = expander.expandMacro(
                        c.gc,
                        cur,
                        transformer,
                        c.globals,
                        &c.macros,
                        .{},
                    ) catch {
                        c.gc.no_collect -= 1;
                        cur = types.cdr(cur);
                        continue;
                    };
                    var expanded_root = expanded;
                    c.gc.pushRoot(&expanded_root);
                    defer c.gc.popRoot();
                    c.gc.no_collect -= 1;
                    // Fixed point (e.g. SRFI-219 rule 3: (define x e) →
                    // (define x e)): the expansion is the input, so scanning
                    // it again can only repeat what this pass already did.
                    // expandAndCompileMacroUse detects the same case to hand
                    // the form to its built-in handler; here it just stops the
                    // scan from re-expanding until the depth cap (kaappi#1775).
                    // Fall through to the sub-form walk below, which is what
                    // compiling the built-in form will visit anyway.
                    if (macro.valuesStructurallyEqual(expanded_root, cur, 128)) {
                        cur = types.cdr(cur);
                        continue;
                    }
                    try collectSetTargets(self, expanded_root, out, depth + 1, budget);
                    return;
                } else if (std.mem.eql(u8, hname, "define-syntax")) {
                    // (define-syntax name <transformer-spec>): the spec is
                    // compile-time data — it resolves to a transformer object
                    // and never contributes a runtime `set!` to THIS form —
                    // so walk it for literal `set!`s in templates but never
                    // macro-expand inside it. Speculatively running a
                    // SRFI 147 spec like SRFI 148's `(em-syntax-rules ...)`
                    // drove the whole CK machine per definition, burning the
                    // entire budget (and with it set_targets_all boxing) on
                    // forms with no runtime code at all (kaappi#1802). A
                    // `set!` that only materializes when the spec's own
                    // macros run is caught at the macro's real use site —
                    // its own form's pre-scan, or Part B — the same
                    // correct-late path every divergent best-effort
                    // expansion above already takes.
                    const rest = types.cdr(cur);
                    if (types.isPair(rest)) {
                        // Skip the macro name; walk the spec without a budget.
                        try collectSetTargets(self, types.cdr(rest), out, depth, null);
                    }
                    return;
                } else if (std.mem.eql(u8, hname, "let-syntax") or
                    std.mem.eql(u8, hname, "letrec-syntax"))
                {
                    // ((name <transformer-spec>) ...) bindings are compile-time
                    // data like define-syntax specs; the body is real code and
                    // keeps the budgeted scan. Walk each spec individually,
                    // skipping the binding NAME, so a binding pair is never
                    // misread as a form: a macro bound under a special-form
                    // name (R7RS lets a binding shadow `quote`, `set!`, ...)
                    // would otherwise derail the walk — a binding literally
                    // named `quote` early-returns before its own spec is
                    // scanned. Verified unobservable end-to-end today (the
                    // let-syntax body compiles via passthrough, where the
                    // folder doesn't engage, and a late-discovered target is
                    // still boxed via the box_local transition — pinned by
                    // tests/scheme/hygiene/quote-shadow-boxing.scm), so this
                    // is scan hygiene, not a bug fix.
                    const rest = types.cdr(cur);
                    if (!types.isPair(rest)) return;
                    var bindings_cur = types.car(rest);
                    while (types.isPair(bindings_cur)) {
                        const binding = types.car(bindings_cur);
                        if (types.isPair(binding)) {
                            try collectSetTargets(self, types.cdr(binding), out, depth, null);
                        }
                        bindings_cur = types.cdr(bindings_cur);
                    }
                    cur = types.cdr(rest);
                    continue;
                }
            }
        }
        try collectSetTargets(self, head, out, depth, budget);
        cur = types.cdr(cur);
    }
}

/// The `set!`-target scan for callers with no Compiler — the LLVM native
/// backend, which re-lowers each lambda/let body through a scratch IR and
/// needs the same suppression set the interpreter's per-form pre-scan builds
/// (#2117). Macros are not expanded (that needs a Compiler); the backend
/// declines native compilation of any body containing a macro use anyway
/// (`sexprHasMacroUse`, #1807), so the two limits line up.
pub fn scanSetTargetsWithoutMacros(expr: Value, out: *std.StringHashMap(void)) CompileError!void {
    return collectSetTargets(null, expr, out, 0, null);
}

// ---------------------------------------------------------------------------
// Convenience functions
// ---------------------------------------------------------------------------

// The `compileExpression*` entry points below are the pipeline's compile
// boundary: every caller that keeps running after a compile error goes
// through one of them (the REPL and `main`'s file loop, `kaappi check`, the
// LSP, `pipeline`'s stage dumps, `native_compiler`, the `eval` and `load`
// primitives, library-body compilation). Each snapshots the GC root-stack
// depth alongside its existing `extra_roots` watermark and truncates back to
// it when the compile fails (#1855).
//
// A failed compile unwinds through `try`s that sit between a `pushRoot` and
// its `popRoot` — `expander_instantiate`'s ellipsis instantiation is the
// confirmed case — so without this the root stack keeps pointing into frames
// that no longer exist, and the leaked entry also misaligns every
// `defer popRoot()` still to fire above it. Truncating here, once, is what
// `GC.truncateRoots` documents; per-site errdefers would be ~340 edits of
// exactly the pattern gc-safety.md warns about. Ordered first in the defer
// block so nothing that runs after it can collect with dead roots live.
pub fn compileExpression(gc: *memory.GC, expr: Value) CompileError!*types.Function {
    syntax_error_detail_len = 0;
    resetCompileErrorSpan();
    var c = try Compiler.init(gc);
    const roots_base = gc.extra_roots.items.len;
    const root_depth = gc.root_count;
    var ok = false;
    defer {
        if (!ok) gc.truncateRoots(root_depth);
        gc.extra_roots.shrinkRetainingCapacity(roots_base);
        if (!ok) Compiler.unrootFunction(gc, c.func);
        c.deinit();
    }
    try c.compile(expr, false);
    ok = true;
    return c.func;
}

pub fn compileExpressionWithMacros(gc: *memory.GC, expr: Value, vm_macros: *std.StringHashMap(Value), vm_globals: ?*std.StringHashMap(Value)) CompileError!*types.Function {
    return compileExpressionWithMacrosAt(gc, expr, vm_macros, vm_globals, 0, null, false);
}

pub fn compileExpressionWithMacrosAt(gc: *memory.GC, expr: Value, vm_macros: *std.StringHashMap(Value), vm_globals: ?*std.StringHashMap(Value), source_line: u32, source_name: ?[]const u8, is_tail: bool) CompileError!*types.Function {
    syntax_error_detail_len = 0;
    resetCompileErrorSpan();
    var c = try Compiler.init(gc);
    const roots_base = gc.extra_roots.items.len;
    const root_depth = gc.root_count;
    c.globals = vm_globals;
    c.func.source_line = source_line;
    c.func.source_name = source_name;
    var ok = false;
    defer {
        if (!ok) gc.truncateRoots(root_depth); // #1855, see compileExpression
        gc.extra_roots.shrinkRetainingCapacity(roots_base);
        if (!ok) Compiler.unrootFunction(gc, c.func);
        c.deinit();
    }
    var it = vm_macros.iterator();
    while (it.next()) |entry| {
        c.macros.put(entry.key_ptr.*, entry.value_ptr.*) catch return CompileError.OutOfMemory;
    }
    try c.compile(expr, is_tail);
    var out_it = c.macros.iterator();
    while (out_it.next()) |entry| {
        vm_macros.put(entry.key_ptr.*, entry.value_ptr.*) catch return CompileError.OutOfMemory;
    }
    ok = true;
    return c.func;
}

/// Which kind of non-vm.globals environment `compileExpressionInEnv` is
/// compiling against. Its two callers hand it structurally identical `env`
/// maps and want opposite things from a name the map doesn't hold, so the
/// distinction cannot be recovered from the map itself (kaappi#1860).
pub const EnvKind = enum {
    /// A `define-library` body — its `begin` blocks, and the
    /// `define-record-type` boilerplate they expand to. `lib_env` holds only
    /// what this library imported or defined, so a reference to anything else
    /// (a `(scheme cxr)` name, a `%`-prefixed internal primitive) has to keep
    /// reaching vm.globals, exactly as it does from inside a closure in the
    /// same body.
    library,
    /// An R7RS restricted environment: `(environment ...)`,
    /// `null-environment`, or the env argument of `eval`/`load`. Withholding
    /// vm.globals is the entire point — only what the environment imported may
    /// resolve (kaappi#1253).
    restricted,
};

pub fn compileExpressionInEnv(gc: *memory.GC, expr: Value, vm_macros: *std.StringHashMap(Value), env: *std.StringHashMap(Value), env_val: Value, is_tail: bool, kind: EnvKind) CompileError!*types.Function {
    syntax_error_detail_len = 0;
    resetCompileErrorSpan();
    var c = try Compiler.init(gc);
    const roots_base = gc.extra_roots.items.len;
    const root_depth = gc.root_count;
    c.globals = env;
    c.lib_env = env;
    c.lib_env_val = env_val;
    c.restricted_env = true;
    // Before compile(), not after: initChild copies it onto every nested
    // function as that compile runs. Nothing in the compiler reads it — only
    // vm_dispatch.lookupGlobalLocked does, at run time.
    c.func.restricted_globals = kind == .restricted;
    var ok = false;
    defer {
        if (!ok) gc.truncateRoots(root_depth); // #1855, see compileExpression
        gc.extra_roots.shrinkRetainingCapacity(roots_base);
        if (!ok) Compiler.unrootFunction(gc, c.func);
        c.deinit();
    }
    var it = vm_macros.iterator();
    while (it.next()) |entry| {
        c.macros.put(entry.key_ptr.*, entry.value_ptr.*) catch return CompileError.OutOfMemory;
    }
    try c.compile(expr, is_tail);
    c.func.env = env;
    c.func.env_val = env_val;
    var out_it = c.macros.iterator();
    while (out_it.next()) |entry| {
        vm_macros.put(entry.key_ptr.*, entry.value_ptr.*) catch return CompileError.OutOfMemory;
    }
    ok = true;
    return c.func;
}

pub fn compileProgram(gc: *memory.GC, exprs: []const Value) CompileError!*types.Function {
    var c = try Compiler.init(gc);
    const root_depth = gc.root_count;
    var ok = false;
    defer {
        if (!ok) gc.truncateRoots(root_depth); // #1855, see compileExpression
        if (!ok) Compiler.unrootFunction(gc, c.func);
        c.deinit();
    }
    try c.compileMultiple(exprs);
    ok = true;
    return c.func;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "compile integer literal" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();

    const expr = types.makeFixnum(42);
    const func = try compileExpression(&gc, expr);
    try std.testing.expect(func.code.items.len > 0);
    try std.testing.expectEqual(OpCode.load_const, @as(OpCode, @enumFromInt(func.code.items[0])));
}

test "compile symbol" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();

    const sym = try gc.allocSymbol("x");
    const func = try compileExpression(&gc, sym);
    try std.testing.expectEqual(OpCode.get_global, @as(OpCode, @enumFromInt(func.code.items[0])));
}

test "compile if expression" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();

    const reader_mod = @import("reader.zig");
    const expr = try reader_mod.readString(&gc, "(if #t 1 2)");
    const func = try compileExpression(&gc, expr);
    try std.testing.expect(func.code.items.len > 0);
}

test "compile lambda" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();

    const reader_mod = @import("reader.zig");
    const expr = try reader_mod.readString(&gc, "(lambda (x) x)");
    const func = try compileExpression(&gc, expr);
    try std.testing.expect(func.code.items.len > 0);
    try std.testing.expectEqual(OpCode.closure, @as(OpCode, @enumFromInt(func.code.items[0])));
}
