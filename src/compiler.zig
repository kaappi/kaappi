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
const globals_mod = @import("globals.zig");
const Value = types.Value;
const OpCode = types.OpCode;

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

const Local = struct {
    name: []const u8,
    depth: u16,
    slot: u16,
    is_boxed: bool = false,
    // Register alias for a global, injected during macro expansion so a
    // template's free reference pierces use-site shadowing. set! through
    // the alias must write back to the global (see compileSet).
    is_global_alias: bool = false,
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
    restricted_env: bool = false, // true for restricted environments (null-environment, environment)
    // Names that are `set!` somewhere in the top-level form being compiled.
    // Owned by the top-level compile() frame and inherited by child compilers
    // so nested lambda bodies see the same suppression set. Consulted by the
    // constant folders (IR and legacy) to avoid folding calls to a name that
    // may be reassigned before the call executes.
    set_targets: ?*const std.StringHashMap(void) = null,
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
    macro_expansion_depth: u16 = 0,
    macro_expansion_steps: u32 = 0,

    pub fn init(gc: *memory.GC) CompileError!Compiler {
        const func = gc.allocFunction() catch return CompileError.OutOfMemory;
        gc.extra_roots.append(gc.allocator, types.makePointer(@ptrCast(func))) catch return CompileError.OutOfMemory;
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
        const func_val = types.makePointer(@ptrCast(func));
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
        func.source_line = parent.func.source_line;
        func.source_name = parent.func.source_name;
        parent.gc.extra_roots.append(parent.gc.allocator, types.makePointer(@ptrCast(func))) catch return CompileError.OutOfMemory;
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

    pub fn isLocalGlobalAlias(self: *Compiler, name: []const u8) bool {
        var i: usize = self.locals.items.len;
        while (i > 0) {
            i -= 1;
            if (std.mem.eql(u8, self.locals.items[i].name, name)) {
                return self.locals.items[i].is_global_alias;
            }
        }
        return false;
    }

    pub fn isSlotBoxed(self: *Compiler, slot: u16) bool {
        for (self.locals.items) |local| {
            if (local.slot == slot) return local.is_boxed;
        }
        return false;
    }

    pub fn markLocalBoxedBySlot(self: *Compiler, slot: u16) CompileError!void {
        for (self.locals.items) |*local| {
            if (local.slot == slot and !local.is_boxed) {
                local.is_boxed = true;
                try self.emitOp(.box_local);
                try self.emitU16(slot);
                return;
            }
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
        }) catch return CompileError.OutOfMemory;
    }

    // -- Public compilation API --

    pub fn compile(self: *Compiler, expr: Value) CompileError!void {
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
        try collectSetTargets(expr_root, &set_targets);
        self.set_targets = &set_targets;
        defer self.set_targets = null;

        // Lower AST to IR, run analysis and optimizations, then emit bytecode.
        var ir = ir_mod.IR.init(self.gc.allocator);
        ir.globals = self.globals;
        ir.restricted_env = self.restricted_env;
        ir.compiler = self;
        ir.set_targets = self.set_targets;
        defer ir.deinit();
        const root = try ir_mod.lowerAndOptimize(&ir, expr_root, &self.macros, false);

        const dst = try self.allocReg();
        try compiler_ir.compileFromNode(self, root, dst, false);
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
            try compiler_ir.compileFromNode(self, root, dst, false);
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
            if (self.gc.source_lines.get(expr)) |line| {
                if (line != self.current_line and line > 0) {
                    self.current_line = line;
                    try self.func.line_table.append(self.gc.allocator, .{
                        .offset = @intCast(self.func.code.items.len),
                        .line = line,
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

            // Primitive forms — only if not shadowed by local binding
            if (!is_shadowed) {
                if (std.mem.eql(u8, effective_name, "quote")) return passthrough.compileQuote(self, args, dst);
                if (std.mem.eql(u8, effective_name, "if")) return passthrough.compileIf(self, args, dst, is_tail);
                if (std.mem.eql(u8, effective_name, "lambda")) return self.compileLambda(args, dst, null);
                if (std.mem.eql(u8, effective_name, "define")) return self.compileDefine(args, dst);
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
                if (std.mem.eql(u8, effective_name, "syntax-error")) return CompileError.InvalidSyntax;

                // Macro forms (kept in compiler.zig)
                if (std.mem.eql(u8, effective_name, "define-syntax")) return macro.compileDefineSyntax(self, args, dst);
                if (std.mem.eql(u8, effective_name, "let-syntax")) return macro.compileLetSyntax(self, args, dst, is_tail);
                if (std.mem.eql(u8, effective_name, "letrec-syntax")) return macro.compileLetrecSyntax(self, args, dst, is_tail);
                if (std.mem.eql(u8, effective_name, "syntax-rules")) return CompileError.InvalidSyntax;
            } // end if (!is_local)

            // Check if head is a macro keyword. A variable binding in scope
            // shadows the macro (R7RS 5.3: a body's definitions shadow outer
            // syntactic bindings), so a local or captured binding with the
            // same name makes this a procedure call instead.
            const macro_hit: ?Value = if (self.lookupMacro(name)) |t|
                if (self.resolveLocal(name) != null or (try self.resolveUpvalue(name)) != null) null else t
            else
                null;
            if (macro_hit) |transformer| {
                return macro.expandAndCompileMacroUse(self, expr, name, transformer, dst, is_tail);
            }
        }

        if (is_tail and types.isSymbol(head) and std.mem.eql(u8, types.symbolName(head), "apply")) {
            if (self.resolveLocal(types.symbolName(head)) == null and
                (try self.resolveUpvalue(types.symbolName(head))) == null)
            {
                return passthrough.compileApplyTail(self, expr, dst);
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

/// Recursively collect the symbol names that appear as the target of a
/// `(set! <name> ...)` anywhere in `expr` into `out`. Used to suppress
/// constant folding of those names within the enclosing form (see
/// Compiler.set_targets). Conservative: it scans every sub-form except the
/// interior of `quote`d data. Iterates the cdr spine to stay bounded on long
/// lists and only recurses into car sub-forms.
fn collectSetTargets(expr: Value, out: *std.StringHashMap(void)) CompileError!void {
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
            }
        }
        try collectSetTargets(head, out);
        cur = types.cdr(cur);
    }
}

// ---------------------------------------------------------------------------
// Convenience functions
// ---------------------------------------------------------------------------

pub fn compileExpression(gc: *memory.GC, expr: Value) CompileError!*types.Function {
    var c = try Compiler.init(gc);
    const roots_base = gc.extra_roots.items.len;
    var ok = false;
    defer {
        gc.extra_roots.shrinkRetainingCapacity(roots_base);
        if (!ok) Compiler.unrootFunction(gc, c.func);
        c.deinit();
    }
    try c.compile(expr);
    ok = true;
    return c.func;
}

pub fn compileExpressionWithMacros(gc: *memory.GC, expr: Value, vm_macros: *std.StringHashMap(Value), vm_globals: ?*std.StringHashMap(Value)) CompileError!*types.Function {
    return compileExpressionWithMacrosAt(gc, expr, vm_macros, vm_globals, 0, null);
}

pub fn compileExpressionWithMacrosAt(gc: *memory.GC, expr: Value, vm_macros: *std.StringHashMap(Value), vm_globals: ?*std.StringHashMap(Value), source_line: u32, source_name: ?[]const u8) CompileError!*types.Function {
    var c = try Compiler.init(gc);
    const roots_base = gc.extra_roots.items.len;
    c.globals = vm_globals;
    c.func.source_line = source_line;
    c.func.source_name = source_name;
    var ok = false;
    defer {
        gc.extra_roots.shrinkRetainingCapacity(roots_base);
        if (!ok) Compiler.unrootFunction(gc, c.func);
        c.deinit();
    }
    var it = vm_macros.iterator();
    while (it.next()) |entry| {
        c.macros.put(entry.key_ptr.*, entry.value_ptr.*) catch return CompileError.OutOfMemory;
    }
    try c.compile(expr);
    var out_it = c.macros.iterator();
    while (out_it.next()) |entry| {
        vm_macros.put(entry.key_ptr.*, entry.value_ptr.*) catch return CompileError.OutOfMemory;
    }
    ok = true;
    return c.func;
}

pub fn compileExpressionInEnv(gc: *memory.GC, expr: Value, vm_macros: *std.StringHashMap(Value), env: *std.StringHashMap(Value), env_val: Value) CompileError!*types.Function {
    var c = try Compiler.init(gc);
    const roots_base = gc.extra_roots.items.len;
    c.globals = env;
    c.lib_env = env;
    c.lib_env_val = env_val;
    c.restricted_env = true;
    var ok = false;
    defer {
        gc.extra_roots.shrinkRetainingCapacity(roots_base);
        if (!ok) Compiler.unrootFunction(gc, c.func);
        c.deinit();
    }
    var it = vm_macros.iterator();
    while (it.next()) |entry| {
        c.macros.put(entry.key_ptr.*, entry.value_ptr.*) catch return CompileError.OutOfMemory;
    }
    try c.compile(expr);
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
    var ok = false;
    defer {
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
