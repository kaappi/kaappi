const std = @import("std");
const types = @import("types.zig");
const memory = @import("memory.zig");
const compiler_mod = @import("compiler.zig");
const globals_mod = @import("globals.zig");
const macro = @import("compiler_macro.zig");
const vm_records = @import("vm_records.zig");
const Compiler = compiler_mod.Compiler;
const CompileError = compiler_mod.CompileError;
const Value = types.Value;
pub fn emitClosureEpilogue(self: *Compiler, child: *Compiler, target_reg: u16) CompileError!void {
    for (child.upvalues.items) |uv| {
        if (uv.is_local) {
            try self.markLocalBoxedBySlot(uv.index);
        }
    }
    const func_val = types.makePointer(&child.func.header);
    const idx = try self.addConstant(func_val);
    try self.emitOp(.closure);
    try self.emitU16(target_reg);
    try self.emitU16(idx);
    for (child.upvalues.items) |uv| {
        try self.emit(if (uv.is_local) 1 else 0);
        try self.emitU16(uv.index);
    }
}

pub fn compileLambda(self: *Compiler, args: Value, dst: u16, name: ?[]const u8) CompileError!void {
    if (args == types.NIL) return CompileError.InvalidSyntax;
    const formals = types.car(args);
    const body = types.cdr(args);
    if (body == types.NIL) return CompileError.InvalidSyntax;

    var child = try Compiler.initChild(self);
    defer child.deinit();

    // Parse formals
    var arity: u8 = 0;
    var is_variadic = false;
    var param_list = formals;

    if (types.isSymbol(formals)) {
        // (lambda x body) -- variadic, takes all args as list
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
                // Rest parameter: (lambda (a b . rest) body)
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

            // arity is a u8, and the call ISA encodes nargs as one byte, so
            // no call site could ever supply a 256th argument (the apply
            // path already rejects >255 loudly). Reject the formals list
            // cleanly instead of overflowing the counter below (#2185).
            // InvalidSyntax, not TooManyLocals: the latter reads as a KP9001
            // "internal error -- report this bug", and an oversized formals
            // list is the user's, matching parseRecordSpec's 255-field cap.
            if (arity == 255) return CompileError.InvalidSyntax;

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

    // Compile body as implicit begin
    try compileBody(&child, body);

    child.populateDebugLocals();
    try emitClosureEpilogue(self, &child, dst);
}

pub fn compileBody(self: *Compiler, body: Value) CompileError!void {
    const saved_body_scope = self.in_body_scope;
    self.in_body_scope = true;
    const last_dst = try compileBodyForms(self, body, .{ .handle_define_syntax = true });
    self.in_body_scope = saved_body_scope;
    try self.emitOp(.@"return");
    try self.emitU16(last_dst);
}

pub const BodyOpts = struct {
    dst: ?u16 = null,
    is_tail: ?bool = null,
    handle_define_syntax: bool = false,
};

pub const BodyScan = struct {
    pub const MAX_DEFS = 512;

    /// One ordered init/side-effect step of a body's leading letrec* region.
    /// Decoupled from def_names/def_inits (which track bound *names*, one
    /// slot each) because a `define-values` clause can bind 0..N names from
    /// a single shared init expression — it can't be represented as one
    /// name-to-init pair the way `define` and `define-record-type`'s
    /// expansions can.
    pub const DefStep = union(enum) {
        /// A plain define(-record-type)-style binding: compile
        /// def_inits[idx] and store the result into def_slots[idx].
        simple: usize,
        /// A define-values clause's already-desugared assignment form
        /// (see buildDefineValuesAssignForm): compile it and discard the
        /// result — it performs its own set!s against the names this scan
        /// already pre-declared (or, for a zero-name clause, is just the
        /// raw init expression, compiled for its side effects only).
        values_group: Value,
    };

    def_names: [MAX_DEFS][]const u8 = undefined,
    def_inits: [MAX_DEFS]Value = undefined,
    def_count: usize = 0,
    def_steps: [MAX_DEFS]DefStep = undefined,
    step_count: usize = 0,
    remaining: Value = types.NIL,
    macro_count: usize = 0,

    prescan_names: std.ArrayList([]const u8) = .empty,
    roots_base: usize = 0,
    macro_mark: usize = 0,
    compiler: *Compiler = undefined,
    handle_define_syntax: bool = false,

    pub fn deinit(self: *BodyScan) void {
        if (self.compiler.globals) |globals| {
            const glk = globals_mod.acquireGlobalsWrite(globals);
            for (self.prescan_names.items) |pn| {
                if (globals.get(pn)) |val| {
                    if (val == types.VOID) _ = globals.remove(pn);
                }
            }
            globals_mod.releaseGlobalsWrite(glk);
        }
        self.prescan_names.deinit(self.compiler.gc.allocator);
        self.compiler.gc.extra_roots.shrinkRetainingCapacity(self.roots_base);
        if (self.handle_define_syntax) {
            self.compiler.endBodyMacroScope(self.macro_mark) catch {};
        }
    }
};

/// Is `form` a definition-context `begin` — a literal `(begin ...)` whose
/// contents splice into the surrounding body per R7RS 4.2.3, "evaluated
/// exactly as if the enclosing begin construct were not present"?
///
/// The shadow test mirrors the IR lowerer (ir.zig, lowerFormWithMacros): a
/// lexical binding or macro shadowing `begin` makes the form an ordinary
/// procedure call, not a splice, while a hygienically renamed `begin` from a
/// macro template keeps its special-form meaning and is never shadowed.
fn isSpliceableBegin(compiler: *const Compiler, form: Value) bool {
    if (!types.isPair(form)) return false;
    const head = types.car(form);
    if (!types.isSymbol(head)) return false;
    const name = types.symbolName(head);
    const effective = types.stripHygienicPrefix(name);
    if (!std.mem.eql(u8, effective, "begin")) return false;
    if (std.mem.eql(u8, effective, name)) {
        if (compiler.isLexicallyBound(name)) return false;
        if (compiler.lookupMacro(name) != null) return false;
    }
    return true;
}

/// Recursively append the effective body elements of `form` to `elems`: a
/// spliceable `begin` contributes its (recursively spliced) children, any
/// other form contributes itself. Called under no_collect (see
/// spliceLeadingBegins).
fn appendSplicedBodyElement(compiler: *Compiler, elems: *std.ArrayList(Value), form: Value) CompileError!void {
    if (isSpliceableBegin(compiler, form)) {
        var child = types.cdr(form);
        while (types.isPair(child)) {
            try appendSplicedBodyElement(compiler, elems, types.car(child));
            child = types.cdr(child);
        }
        // An improper begin `(begin e1 . tail)` is invalid syntax — reject
        // it rather than silently dropping the tail from the spliced body.
        if (child != types.NIL) return CompileError.InvalidSyntax;
    } else {
        elems.append(compiler.gc.allocator, form) catch return CompileError.OutOfMemory;
    }
}

/// Does the body's leading definition region bind the name `begin` with a
/// `define-syntax`? The scanner installs body-local macro bindings only in
/// its second pass — after this splice would have run — and the IR lowerer
/// gives a macro shadowing `begin` precedence over the special form, so a
/// body that binds its own `begin` must not have its `(begin ...)` forms
/// spliced as if the wrapper were absent: they are macro uses. Walks the
/// already-flattened leading forms (the scan's own recognition rules: a
/// literal define-family head continues the region, anything else ends it);
/// the list is already spliced, so no descent is needed. The keyword is
/// compared after stripping a hygiene prefix, so a template-introduced
/// `define-syntax begin` shadows the (identically renamed) uses too.
fn bodyBindsBeginMacro(flattened: Value) bool {
    var cur = flattened;
    while (types.isPair(cur)) {
        const form = types.car(cur);
        if (!types.isPair(form)) break;
        const head = types.car(form);
        if (!types.isSymbol(head)) break;
        const hn = types.symbolName(head);
        if (std.mem.eql(u8, hn, "define-syntax")) {
            const rest = types.cdr(form);
            if (types.isPair(rest) and types.isSymbol(types.car(rest)) and
                std.mem.eql(u8, types.stripHygienicPrefix(types.symbolName(types.car(rest))), "begin"))
            {
                return true;
            }
            cur = types.cdr(cur);
            continue;
        }
        if (std.mem.eql(u8, hn, "define") or std.mem.eql(u8, hn, "define-record-type") or
            std.mem.eql(u8, hn, "define-values"))
        {
            cur = types.cdr(cur);
            continue;
        }
        break;
    }
    return false;
}

/// R7RS 4.2.3 definition-context `begin` splicing (#2075): a literal
/// `(begin ...)` among a body's leading forms — or directly nested in
/// another such begin — behaves exactly as if the wrapper were absent, so a
/// definition inside it joins the body's letrec* region: it must shadow an
/// enclosing binding and must not escape into the global environment. The
/// body scanners only recognize literal `define`-family heads as body
/// elements, so this helper unwraps every spliceable `begin` anywhere in
/// `body` before scanning.
///
/// Returns a freshly allocated list equivalent to `body` with every
/// spliceable begin removed (the caller must root it), or null when there
/// is nothing to splice — the common case allocates nothing. The result
/// shares all element and tail structure with `body`; only the cons cells
/// connecting spliced elements are new. Built under no_collect so the
/// fresh cells cannot be swept before the caller roots the result; the
/// recursion mirrors the IR's own unbounded lowering of nested begins.
fn spliceLeadingBegins(compiler: *Compiler, body: Value) CompileError!?Value {
    const gc = compiler.gc;

    // Fast path: a body with no spliceable begin element allocates nothing.
    var any_begin = false;
    {
        var cur = body;
        while (types.isPair(cur)) {
            if (isSpliceableBegin(compiler, types.car(cur))) {
                any_begin = true;
                break;
            }
            cur = types.cdr(cur);
        }
    }
    if (!any_begin) return null;

    gc.no_collect += 1;
    errdefer gc.no_collect -= 1;

    var elems: std.ArrayList(Value) = .empty;
    defer elems.deinit(gc.allocator);
    var cur = body;
    while (types.isPair(cur)) {
        try appendSplicedBodyElement(compiler, &elems, types.car(cur));
        cur = types.cdr(cur);
    }
    // An improper body tail must not be silently dropped either.
    if (cur != types.NIL) return CompileError.InvalidSyntax;

    var result = types.NIL;
    var i = elems.items.len;
    while (i > 0) {
        i -= 1;
        result = gc.allocPair(elems.items[i], result) catch return CompileError.OutOfMemory;
    }

    // A body-local `(define-syntax begin ...)` shadows the special form for
    // the whole body (IR precedence: macro over special form), and the scan
    // installs that binding only after this splice would have run — so
    // decline to splice and let the scan + IR handle every `(begin ...)` as
    // a macro use, exactly as they would in non-leading position.
    if (bodyBindsBeginMacro(result)) {
        gc.no_collect -= 1;
        return null;
    }

    gc.no_collect -= 1;
    return result;
}

pub fn scanBodyDefs(compiler: *Compiler, body: Value, handle_define_syntax: bool) CompileError!BodyScan {
    var scan_result = BodyScan{};
    scan_result.compiler = compiler;
    scan_result.handle_define_syntax = handle_define_syntax;
    scan_result.roots_base = compiler.gc.extra_roots.items.len;
    scan_result.macro_mark = if (handle_define_syntax) compiler.beginBodyMacroScope() else 0;
    errdefer scan_result.deinit();

    // R7RS 4.2.3: a definition-context `begin` is "evaluated exactly as if
    // the enclosing begin construct were not present", so a definition
    // written inside a literal `begin` body element must join this body's
    // letrec* region like an unwrapped one — shadowing an enclosing `let`
    // binding rather than escaping into the global environment (#2075).
    // The three passes below then scan the spliced body; its head is rooted
    // via extra_roots (truncated by deinit) so it outlives the scan and the
    // caller's compilation of scan.remaining (issue #1010 pattern).
    var effective_body = body;
    if (try spliceLeadingBegins(compiler, body)) |spliced| {
        effective_body = spliced;
        compiler.gc.extra_roots.append(compiler.gc.allocator, effective_body) catch return CompileError.OutOfMemory;
    }

    // --- Globals prescan sentinel dance (#958) ---
    if (compiler.globals) |globals| {
        const glk = globals_mod.acquireGlobalsWrite(globals);
        defer globals_mod.releaseGlobalsWrite(glk);
        var scan = effective_body;
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
                                    try globals.put(dn, types.VOID);
                                    try scan_result.prescan_names.append(compiler.gc.allocator, dn);
                                }
                            }
                        }
                    } else if (std.mem.eql(u8, form_name, "define-record-type")) {
                        if (vm_records.parseRecordSpec(types.cdr(form))) |spec| {
                            if (!globals.contains(spec.ctor_name)) {
                                globals.put(spec.ctor_name, types.VOID) catch {};
                                scan_result.prescan_names.append(compiler.gc.allocator, spec.ctor_name) catch {};
                            }
                            if (!globals.contains(spec.pred_name)) {
                                globals.put(spec.pred_name, types.VOID) catch {};
                                scan_result.prescan_names.append(compiler.gc.allocator, spec.pred_name) catch {};
                            }
                            for (0..spec.field_count) |fi| {
                                if (!globals.contains(spec.accessor_names[fi])) {
                                    globals.put(spec.accessor_names[fi], types.VOID) catch {};
                                    scan_result.prescan_names.append(compiler.gc.allocator, spec.accessor_names[fi]) catch {};
                                }
                                if (spec.mutator_names[fi]) |mn| {
                                    if (!globals.contains(mn)) {
                                        globals.put(mn, types.VOID) catch {};
                                        scan_result.prescan_names.append(compiler.gc.allocator, mn) catch {};
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

    // First pass: collect ALL leading define names so that define-syntax
    // forms see the complete letrec* region via extra_bound.
    var all_def_names: [BodyScan.MAX_DEFS][]const u8 = undefined;
    var all_def_count: usize = 0;
    {
        var scan = effective_body;
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
                    if (all_def_count < BodyScan.MAX_DEFS) {
                        all_def_names[all_def_count] = types.symbolName(tgt);
                        all_def_count += 1;
                    }
                } else if (types.isPair(tgt)) {
                    const fn_name = types.car(tgt);
                    if (types.isSymbol(fn_name) and all_def_count < BodyScan.MAX_DEFS) {
                        all_def_names[all_def_count] = types.symbolName(fn_name);
                        all_def_count += 1;
                    }
                } else break;
            } else if (std.mem.eql(u8, hn, "define-record-type")) {
                vm_records.collectRecordTypeDefNames(compiler.gc, types.cdr(expr), all_def_names[0..], &all_def_count) catch |err| switch (err) {
                    CompileError.InvalidSyntax => break,
                    else => return err,
                };
            } else if (std.mem.eql(u8, hn, "define-values")) {
                const dv_args = types.cdr(expr);
                if (dv_args == types.NIL or !types.isPair(dv_args)) break;
                var dv_names_buf: [64][]const u8 = undefined;
                var dv_rest_name: ?[]const u8 = null;
                const dv_name_count = parseDefineValuesFormals(types.car(dv_args), dv_names_buf[0..], &dv_rest_name) catch |err| switch (err) {
                    CompileError.InvalidSyntax => break,
                    else => return err,
                };
                for (dv_names_buf[0..dv_name_count]) |dn| {
                    if (all_def_count < BodyScan.MAX_DEFS) {
                        all_def_names[all_def_count] = dn;
                        all_def_count += 1;
                    }
                }
                if (dv_rest_name) |rn| {
                    if (all_def_count < BodyScan.MAX_DEFS) {
                        all_def_names[all_def_count] = rn;
                        all_def_count += 1;
                    }
                }
            } else if (!(handle_define_syntax and std.mem.eql(u8, hn, "define-syntax"))) {
                break;
            }
            scan = types.cdr(scan);
        }
    }

    // Second pass: collect define inits and process define-syntax forms.
    // def_inits lives in a stack array the GC cannot see. The (define (name
    // args...) body) case below allocates fresh lambda pairs into it, and both
    // the rest of this scan and the caller's compilation phase allocate, so a
    // collection would sweep the not-yet-compiled inits (issue #1010). Mirror
    // them into extra_roots (by value, realloc-safe) for the duration.
    var current = effective_body;
    while (current != types.NIL and types.isPair(current)) {
        const expr = types.car(current);
        if (!types.isPair(expr)) break;
        const head = types.car(expr);
        if (!types.isSymbol(head)) break;
        const head_name = types.symbolName(head);
        if (std.mem.eql(u8, head_name, "define")) {
            const def_args = types.cdr(expr);
            if (def_args == types.NIL or !types.isPair(def_args)) break;
            const target = types.car(def_args);
            const def_rest = types.cdr(def_args);

            if (types.isSymbol(target)) {
                if (def_rest == types.NIL or !types.isPair(def_rest)) break;
                if (scan_result.def_count >= BodyScan.MAX_DEFS) return CompileError.TooManyLocals;
                scan_result.def_names[scan_result.def_count] = types.symbolName(target);
                scan_result.def_inits[scan_result.def_count] = types.car(def_rest);
                scan_result.def_count += 1;
                if (scan_result.step_count >= BodyScan.MAX_DEFS) return CompileError.TooManyLocals;
                scan_result.def_steps[scan_result.step_count] = .{ .simple = scan_result.def_count - 1 };
                scan_result.step_count += 1;
            } else if (types.isPair(target)) {
                const fn_name = types.car(target);
                if (!types.isSymbol(fn_name)) break;
                if (scan_result.def_count >= BodyScan.MAX_DEFS) return CompileError.TooManyLocals;
                scan_result.def_names[scan_result.def_count] = types.symbolName(fn_name);
                const param_formals = types.cdr(target);
                const lambda_sym = compiler.gc.allocSymbol("lambda") catch return CompileError.OutOfMemory;
                {
                    var lambda_args = compiler.gc.allocPair(param_formals, def_rest) catch return CompileError.OutOfMemory;
                    compiler.gc.pushRoot(&lambda_args);
                    defer compiler.gc.popRoot();
                    scan_result.def_inits[scan_result.def_count] = compiler.gc.allocPair(lambda_sym, lambda_args) catch return CompileError.OutOfMemory;
                }
                compiler.gc.extra_roots.append(compiler.gc.allocator, scan_result.def_inits[scan_result.def_count]) catch return CompileError.OutOfMemory;
                scan_result.def_count += 1;
                if (scan_result.step_count >= BodyScan.MAX_DEFS) return CompileError.TooManyLocals;
                scan_result.def_steps[scan_result.step_count] = .{ .simple = scan_result.def_count - 1 };
                scan_result.step_count += 1;
            } else {
                break;
            }
        } else if (std.mem.eql(u8, head_name, "define-record-type")) {
            const rt_before = scan_result.def_count;
            vm_records.expandRecordTypeDefines(
                compiler.gc,
                types.cdr(expr),
                scan_result.def_names[0..],
                scan_result.def_inits[0..],
                &scan_result.def_count,
                &compiler.gc.extra_roots,
            ) catch |err| switch (err) {
                CompileError.InvalidSyntax => break,
                else => return err,
            };
            var rt_idx = rt_before;
            while (rt_idx < scan_result.def_count) : (rt_idx += 1) {
                if (scan_result.step_count >= BodyScan.MAX_DEFS) return CompileError.TooManyLocals;
                scan_result.def_steps[scan_result.step_count] = .{ .simple = rt_idx };
                scan_result.step_count += 1;
            }
        } else if (std.mem.eql(u8, head_name, "define-values")) {
            const dv_args = types.cdr(expr);
            if (dv_args == types.NIL or !types.isPair(dv_args)) break;
            const dv_formals = types.car(dv_args);
            const dv_rest = types.cdr(dv_args);
            if (dv_rest == types.NIL or !types.isPair(dv_rest)) break;
            const dv_expr = types.car(dv_rest);

            var dv_names_buf: [64][]const u8 = undefined;
            var dv_rest_name: ?[]const u8 = null;
            const dv_name_count = parseDefineValuesFormals(dv_formals, dv_names_buf[0..], &dv_rest_name) catch |err| switch (err) {
                CompileError.InvalidSyntax => break,
                else => return err,
            };

            const dv_total_new = dv_name_count + @as(usize, if (dv_rest_name != null) 1 else 0);
            if (scan_result.def_count + dv_total_new > BodyScan.MAX_DEFS) return CompileError.TooManyLocals;

            for (dv_names_buf[0..dv_name_count]) |dn| {
                scan_result.def_names[scan_result.def_count] = dn;
                scan_result.def_inits[scan_result.def_count] = types.VOID;
                scan_result.def_count += 1;
            }
            if (dv_rest_name) |rn| {
                scan_result.def_names[scan_result.def_count] = rn;
                scan_result.def_inits[scan_result.def_count] = types.VOID;
                scan_result.def_count += 1;
            }

            const dv_assign_form = buildDefineValuesAssignForm(compiler.gc, dv_names_buf[0..dv_name_count], dv_rest_name, dv_expr) catch |err| switch (err) {
                CompileError.InvalidSyntax => break,
                else => return err,
            };
            compiler.gc.extra_roots.append(compiler.gc.allocator, dv_assign_form) catch return CompileError.OutOfMemory;

            if (scan_result.step_count >= BodyScan.MAX_DEFS) return CompileError.TooManyLocals;
            scan_result.def_steps[scan_result.step_count] = .{ .values_group = dv_assign_form };
            scan_result.step_count += 1;
        } else if (handle_define_syntax and std.mem.eql(u8, head_name, "define-syntax")) {
            const ds_args = types.cdr(expr);
            if (ds_args == types.NIL or !types.isPair(ds_args)) break;
            const keyword = types.car(ds_args);
            if (!types.isSymbol(keyword)) break;
            const ds_rest = types.cdr(ds_args);
            if (ds_rest == types.NIL or !types.isPair(ds_rest)) break;
            const transformer_spec = types.car(ds_rest);

            const transformer = macro.parseSyntaxRules(compiler, transformer_spec, all_def_names[0..all_def_count]) catch break;
            // Root the transformer for the rest of this body compile: it
            // lives only in the compiler-local macro map, which the GC
            // cannot see, and it must survive collections triggered while
            // compiling sibling body forms that use it (#1401). Released
            // by deinit()'s extra_roots truncation (roots_base), after
            // the body — the macro's entire scope — is compiled.
            compiler.gc.extra_roots.append(compiler.gc.allocator, transformer) catch return CompileError.OutOfMemory;
            const name = types.symbolName(keyword);

            try compiler.recordBodyMacro(name);
            scan_result.macro_count += 1;

            const tx = types.toObject(transformer).as(types.Transformer);
            if (compiler.lib_env) |env| {
                tx.def_env = env;
                tx.def_env_val = compiler.lib_env_val;
                globals_mod.assertEnvMapInvariant(env, compiler.lib_env_val); // #1962
            }
            try macro.captureLocalsOnTransformer(compiler, transformer);
            compiler.macros.put(name, transformer) catch return CompileError.OutOfMemory;
        } else {
            break;
        }
        current = types.cdr(current);
    }

    scan_result.remaining = current;
    return scan_result;
}

pub fn compileBodyForms(self: *Compiler, body: Value, opts: BodyOpts) CompileError!u16 {
    const allocates_regs = opts.dst == null;

    // A ⟨body⟩ is a definition context even without an enclosing procedure:
    // a `define` reached here at compile time — a literal `begin` the body
    // scan could not splice, a macro expansion producing a definition, or a
    // degenerate non-head `define` — must bind a local in this body's scope,
    // never escape into the global environment. `compileBody`/`compileSyntaxBody`
    // already set this for procedure and let-syntax bodies; the let-family
    // bodies (the other callers of compileBodyForms) were missing it, so the
    // identical text at top level and inside a lambda compiled differently
    // (#2075).
    const saved_body_scope = self.in_body_scope;
    self.in_body_scope = true;
    defer self.in_body_scope = saved_body_scope;

    var scan = try scanBodyDefs(self, body, opts.handle_define_syntax);
    defer scan.deinit();

    var last_dst: u16 = opts.dst orelse 0;
    var current = scan.remaining;

    if (scan.step_count > 0) {
        self.beginScope();

        var def_slots: [BodyScan.MAX_DEFS]u16 = undefined;
        for (0..scan.def_count) |i| {
            const slot = try self.allocReg();
            def_slots[i] = slot;
            try self.emitOp(.load_void);
            try self.emitU16(slot);
            try self.addLocal(scan.def_names[i], slot);
            try self.markLocalBoxedBySlot(slot);
        }

        for (0..scan.step_count) |si| {
            switch (scan.def_steps[si]) {
                .simple => |idx| {
                    if (allocates_regs) {
                        last_dst = try self.allocReg();
                        try self.compileExprViaIR(scan.def_inits[idx], last_dst, false);
                        try self.emitOp(.set_box_local);
                        try self.emitU16(def_slots[idx]);
                        try self.emitU16(last_dst);
                        self.freeReg();
                    } else {
                        try self.compileExprViaIR(scan.def_inits[idx], last_dst, false);
                        try self.emitOp(.set_box_local);
                        try self.emitU16(def_slots[idx]);
                        try self.emitU16(last_dst);
                    }
                },
                .values_group => |form| {
                    // Already a self-contained set!-performing (or, for a
                    // zero-name clause, bare side-effecting) form — compile
                    // it and discard/void the result; no set_box_local,
                    // since it assigns directly to the pre-declared locals.
                    if (allocates_regs) {
                        last_dst = try self.allocReg();
                        try self.compileExprViaIR(form, last_dst, false);
                        try self.emitOp(.load_void);
                        try self.emitU16(last_dst);
                        self.freeReg();
                    } else {
                        try self.compileExprViaIR(form, last_dst, false);
                        try self.emitOp(.load_void);
                        try self.emitU16(last_dst);
                    }
                },
            }
        }

        if (current == types.NIL and allocates_regs) {
            last_dst = try self.allocReg();
            try self.emitOp(.load_void);
            try self.emitU16(last_dst);
        } else {
            try compileExprSequence(self, &current, &last_dst, allocates_regs, opts.is_tail);
        }

        self.endScope();
    } else if (current != types.NIL) {
        try compileExprSequence(self, &current, &last_dst, allocates_regs, opts.is_tail);
    } else if (scan.macro_count > 0 and !allocates_regs) {
        try self.emitOp(.load_void);
        try self.emitU16(last_dst);
    }

    return last_dst;
}

pub fn compileExprSequence(self: *Compiler, current: *Value, last_dst: *u16, allocates_regs: bool, caller_tail: ?bool) CompileError!void {
    while (current.* != types.NIL) {
        if (!types.isPair(current.*)) return CompileError.InvalidSyntax;
        const expr = types.car(current.*);
        current.* = types.cdr(current.*);
        const is_last = current.* == types.NIL;
        if (allocates_regs) {
            last_dst.* = try self.allocReg();
            if (is_last) {
                try self.compileExprViaIR(expr, last_dst.*, true);
            } else {
                const saved_next = self.next_register;
                try self.compileExprViaIR(expr, last_dst.*, false);
                if (self.next_register == saved_next) {
                    self.freeReg();
                }
            }
        } else {
            const tail = (caller_tail orelse false) and is_last;
            try self.compileExprViaIR(expr, last_dst.*, tail);
        }
    }
}

pub fn compileDefine(self: *Compiler, args: Value, dst: u16) CompileError!void {
    if (args == types.NIL) return CompileError.InvalidSyntax;
    const target = types.car(args);
    const rest = types.cdr(args);

    if (types.isSymbol(target)) {
        // (define x expr)
        if (rest == types.NIL) return CompileError.InvalidSyntax;
        const value_expr = types.car(rest);
        try self.compileExprViaIR(value_expr, dst, false);

        // If the expression compiled to a lambda, set its name for debugging
        if (self.func.constants.items.len > 0) {
            const last_const = self.func.constants.items[self.func.constants.items.len - 1];
            if (types.isFunction(last_const)) {
                const child_func = types.toObject(last_const).as(types.Function);
                if (child_func.name == null) {
                    child_func.name = types.symbolName(target);
                }
            }
        }

        if (self.in_body_scope) {
            const slot = try self.allocReg();
            try self.emitOp(.move);
            try self.emitU16(slot);
            try self.emitU16(dst);
            self.locals.append(self.gc.allocator, .{
                .name = types.symbolName(target),
                .depth = self.scope_depth,
                .slot = slot,
                .binding_id = compiler_mod.freshBindingId(),
            }) catch return CompileError.OutOfMemory;
            try self.emitOp(.load_void);
            try self.emitU16(dst);
            return;
        }
        const sym_idx = try self.addConstant(target);
        try self.emitOp(.define_global);
        try self.emitU16(sym_idx);
        try self.emitU16(dst);
        try self.emitOp(.load_void);
        try self.emitU16(dst);
        return;
    }

    if (types.isPair(target)) {
        // (define (name args...) body) => (define name (lambda (args...) body))
        const name = types.car(target);
        if (!types.isSymbol(name)) return CompileError.InvalidSyntax;
        const param_formals = types.cdr(target);

        var lambda_args = self.gc.allocPair(param_formals, rest) catch return CompileError.OutOfMemory;
        self.gc.pushRoot(&lambda_args);
        defer self.gc.popRoot();
        try compileLambda(self, lambda_args, dst, types.symbolName(name));

        if (self.in_body_scope) {
            const slot = try self.allocReg();
            try self.emitOp(.move);
            try self.emitU16(slot);
            try self.emitU16(dst);
            self.locals.append(self.gc.allocator, .{
                .name = types.symbolName(name),
                .depth = self.scope_depth,
                .slot = slot,
                .binding_id = compiler_mod.freshBindingId(),
            }) catch return CompileError.OutOfMemory;
            try self.emitOp(.load_void);
            try self.emitU16(dst);
            return;
        }
        const sym_idx = try self.addConstant(name);
        try self.emitOp(.define_global);
        try self.emitU16(sym_idx);
        try self.emitU16(dst);
        try self.emitOp(.load_void);
        try self.emitU16(dst);
        return;
    }

    return CompileError.InvalidSyntax;
}

/// General-dispatch handler for define-record-type.
/// Builds define S-expressions and compiles each one, so that compileDefine's
/// in_body_scope path creates local variables when appropriate.
/// Covers positions the leading-define body scanner doesn't reach
/// (e.g. let-values bodies, begin-splicing inside lambdas).
pub fn compileDefineRecordType(self: *Compiler, args: Value, dst: u16) CompileError!void {
    const gc = self.gc;
    const spec = vm_records.parseRecordSpec(args) orelse return CompileError.InvalidSyntax;
    const internal_name = try vm_records.internRecordTypeName(gc, spec.type_name);

    gc.no_collect += 1;
    errdefer gc.no_collect -= 1;

    const define_sym = gc.allocSymbol("define") catch return CompileError.OutOfMemory;

    // Build all define forms as a list (consing in reverse)
    var forms = types.NIL;

    // Mutators (reverse order)
    {
        var fi = spec.field_count;
        while (fi > 0) {
            fi -= 1;
            if (spec.mutator_names[fi]) |mn| {
                const rs = globals_mod.baseBindingSymbol(gc, "%record-set!") catch return CompileError.OutOfMemory;
                const p = gc.allocSymbol("p") catch return CompileError.OutOfMemory;
                const v = gc.allocSymbol("v") catch return CompileError.OutOfMemory;
                const idx = types.makeFixnum(@intCast(fi));
                const rt_ref = gc.allocSymbol(internal_name) catch return CompileError.OutOfMemory;
                const body = gc.makeList(&[_]Value{ rs, p, idx, v, rt_ref }) catch return CompileError.OutOfMemory;
                const np = gc.allocPair(gc.allocSymbol(mn) catch return CompileError.OutOfMemory, gc.makeList(&[_]Value{ p, v }) catch return CompileError.OutOfMemory) catch return CompileError.OutOfMemory;
                forms = gc.allocPair(gc.makeList(&[_]Value{ define_sym, np, body }) catch return CompileError.OutOfMemory, forms) catch return CompileError.OutOfMemory;
            }
        }
    }

    // Accessors (reverse order)
    {
        var fi = spec.field_count;
        while (fi > 0) {
            fi -= 1;
            const rr = globals_mod.baseBindingSymbol(gc, "%record-ref") catch return CompileError.OutOfMemory;
            const p = gc.allocSymbol("p") catch return CompileError.OutOfMemory;
            const idx = types.makeFixnum(@intCast(fi));
            const rt_ref = gc.allocSymbol(internal_name) catch return CompileError.OutOfMemory;
            const body = gc.makeList(&[_]Value{ rr, p, idx, rt_ref }) catch return CompileError.OutOfMemory;
            const np = gc.allocPair(gc.allocSymbol(spec.accessor_names[fi]) catch return CompileError.OutOfMemory, gc.makeList(&[_]Value{p}) catch return CompileError.OutOfMemory) catch return CompileError.OutOfMemory;
            forms = gc.allocPair(gc.makeList(&[_]Value{ define_sym, np, body }) catch return CompileError.OutOfMemory, forms) catch return CompileError.OutOfMemory;
        }
    }

    // Predicate
    {
        const rc = globals_mod.baseBindingSymbol(gc, "%record?") catch return CompileError.OutOfMemory;
        const v = gc.allocSymbol("v") catch return CompileError.OutOfMemory;
        const rt_ref = gc.allocSymbol(internal_name) catch return CompileError.OutOfMemory;
        const body = gc.makeList(&[_]Value{ rc, v, rt_ref }) catch return CompileError.OutOfMemory;
        const np = gc.allocPair(gc.allocSymbol(spec.pred_name) catch return CompileError.OutOfMemory, gc.makeList(&[_]Value{v}) catch return CompileError.OutOfMemory) catch return CompileError.OutOfMemory;
        forms = gc.allocPair(gc.makeList(&[_]Value{ define_sym, np, body }) catch return CompileError.OutOfMemory, forms) catch return CompileError.OutOfMemory;
    }

    // Constructor.
    //
    // Collision note (kaappi#2294): the R7RS grammar lets <name> and
    // <constructor name> be the same identifier, and this path accepts it —
    // the constructor's define below wins the name (the record type is only
    // ever bound under the internal __record_type_<name> alias, so there is
    // no user-visible type-name binding for the constructor to shadow). R7RS
    // §5.5 leaves the collision unspecified; Chibi and Guile reject it, so
    // such code is not portable. See vm_records.handleDefineRecordType.
    {
        const mr = globals_mod.baseBindingSymbol(gc, "%make-record") catch return CompileError.OutOfMemory;
        const rt_ref = gc.allocSymbol(internal_name) catch return CompileError.OutOfMemory;
        var body_elems: [258]Value = undefined;
        body_elems[0] = mr;
        body_elems[1] = rt_ref;
        for (0..spec.field_count) |fi| {
            var found = false;
            for (0..spec.ctor_field_count) |ci| {
                if (spec.ctor_field_indices[ci] == fi) {
                    body_elems[2 + fi] = gc.allocSymbol(spec.ctor_fields[ci]) catch return CompileError.OutOfMemory;
                    found = true;
                    break;
                }
            }
            if (!found) {
                const if_sym = gc.allocSymbol("if") catch return CompileError.OutOfMemory;
                body_elems[2 + fi] = gc.makeList(&[_]Value{ if_sym, types.FALSE, types.FALSE }) catch return CompileError.OutOfMemory;
            }
        }
        const body = gc.makeList(body_elems[0 .. 2 + spec.field_count]) catch return CompileError.OutOfMemory;
        var param_syms: [256]Value = undefined;
        for (0..spec.ctor_field_count) |ci| {
            param_syms[ci] = gc.allocSymbol(spec.ctor_fields[ci]) catch return CompileError.OutOfMemory;
        }
        const np = gc.allocPair(gc.allocSymbol(spec.ctor_name) catch return CompileError.OutOfMemory, gc.makeList(param_syms[0..spec.ctor_field_count]) catch return CompileError.OutOfMemory) catch return CompileError.OutOfMemory;
        forms = gc.allocPair(gc.makeList(&[_]Value{ define_sym, np, body }) catch return CompileError.OutOfMemory, forms) catch return CompileError.OutOfMemory;
    }

    // Internal record type: (define __rt (%make-record-type "name" n))
    {
        const mrt = globals_mod.baseBindingSymbol(gc, "%make-record-type") catch return CompileError.OutOfMemory;
        const ns = gc.allocString(spec.type_name) catch return CompileError.OutOfMemory;
        const nf = types.makeFixnum(@intCast(spec.field_count));
        const init = gc.makeList(&[_]Value{ mrt, ns, nf }) catch return CompileError.OutOfMemory;
        const rt_sym = gc.allocSymbol(internal_name) catch return CompileError.OutOfMemory;
        forms = gc.allocPair(gc.makeList(&[_]Value{ define_sym, rt_sym, init }) catch return CompileError.OutOfMemory, forms) catch return CompileError.OutOfMemory;
    }

    gc.no_collect -= 1;

    gc.pushRoot(&forms);
    defer gc.popRoot();
    var current = forms;
    while (current != types.NIL and types.isPair(current)) {
        try self.compileExprViaIR(types.car(current), dst, false);
        current = types.cdr(current);
    }
}

/// Parse a `define-values` formals spec — the same shape as a lambda
/// formals list: `()`, a bare symbol, a proper list, or an improper
/// (dotted) list — into fixed names (written into `names_buf`, count
/// returned) plus an optional rest name.
fn parseDefineValuesFormals(formals: Value, names_buf: [][]const u8, rest_name: *?[]const u8) CompileError!usize {
    rest_name.* = null;
    if (formals == types.NIL) return 0;
    if (types.isSymbol(formals)) {
        rest_name.* = types.symbolName(formals);
        return 0;
    }
    var name_count: usize = 0;
    var formal = formals;
    while (formal != types.NIL) {
        if (types.isSymbol(formal)) {
            rest_name.* = types.symbolName(formal);
            break;
        }
        if (!types.isPair(formal)) return CompileError.InvalidSyntax;
        const sym = types.car(formal);
        if (!types.isSymbol(sym)) return CompileError.InvalidSyntax;
        if (name_count >= names_buf.len) return CompileError.InvalidSyntax;
        names_buf[name_count] = types.symbolName(sym);
        name_count += 1;
        formal = types.cdr(formal);
    }
    return name_count;
}

/// Build the desugared assignment form for a `define-values` clause, given
/// its already-parsed fixed names, optional rest name, and init expression.
/// Returns a complete, self-contained form ready to compile via
/// `compileExprViaIR`:
///   - zero names, no rest: `expr` itself, unwrapped (nothing to bind, just
///     evaluate for side effects).
///   - zero fixed names, a rest name (the "single symbol" formals shape):
///     `(set! rest (call-with-values (lambda () expr) list))`.
///   - otherwise: `(call-with-values (lambda () expr) (lambda (p0 p1 ...
///     [. prest]) (set! n0 p0) (set! n1 p1) ... [(set! rest prest)]))`.
/// Does NOT pre-declare the names — callers must ensure they already exist
/// as locals or globals before compiling the returned form.
///
/// Builds a chain of fresh, unrooted pairs, each allocation able to sweep
/// the previous ones, so collection is disabled for the whole build
/// (issue #1010). The caller must root the result across whatever compiles
/// next.
fn buildDefineValuesAssignForm(gc: *memory.GC, names: []const []const u8, rest_name: ?[]const u8, expr: Value) CompileError!Value {
    const is_single = names.len == 0 and rest_name != null;

    gc.no_collect += 1;
    defer gc.no_collect -= 1;

    if (is_single) {
        // (define-values x expr) → (set! x (call-with-values (lambda () expr) list))
        const rn_sym = gc.allocSymbol(rest_name.?) catch return CompileError.OutOfMemory;
        const list_sym = try compiler_mod.Compiler.trueBuiltinRefOrSymbol(gc, "list");

        const producer_body = gc.allocPair(expr, types.NIL) catch return CompileError.OutOfMemory;
        const producer_lambda = gc.allocPair(types.NIL, producer_body) catch return CompileError.OutOfMemory;
        const lambda_sym = gc.allocSymbol("lambda") catch return CompileError.OutOfMemory;
        const producer = gc.allocPair(lambda_sym, producer_lambda) catch return CompileError.OutOfMemory;

        const cwv_sym = try compiler_mod.Compiler.trueBuiltinRefOrSymbol(gc, "call-with-values");
        const cwv_3 = gc.allocPair(list_sym, types.NIL) catch return CompileError.OutOfMemory;
        const cwv_2 = gc.allocPair(producer, cwv_3) catch return CompileError.OutOfMemory;
        const cwv_form = gc.allocPair(cwv_sym, cwv_2) catch return CompileError.OutOfMemory;

        const set_sym = gc.allocSymbol("set!") catch return CompileError.OutOfMemory;
        const set_rest2 = gc.allocPair(cwv_form, types.NIL) catch return CompileError.OutOfMemory;
        const set_args = gc.allocPair(rn_sym, set_rest2) catch return CompileError.OutOfMemory;
        return gc.allocPair(set_sym, set_args) catch return CompileError.OutOfMemory;
    }

    // Consumer: (lambda (p0 p1 ... [. prest]) (set! n0 p0) (set! n1 p1) ... )
    // Build set! forms from right to left.
    var consumer_body: Value = types.NIL;

    if (rest_name) |rn| {
        if (names.len > 0) {
            const rn_sym = gc.allocSymbol(rn) catch return CompileError.OutOfMemory;
            const param_sym = gc.allocSymbol("__dv_rest") catch return CompileError.OutOfMemory;
            const set_rest = gc.allocPair(param_sym, types.NIL) catch return CompileError.OutOfMemory;
            const set_args = gc.allocPair(rn_sym, set_rest) catch return CompileError.OutOfMemory;
            const set_sym = gc.allocSymbol("set!") catch return CompileError.OutOfMemory;
            const set_form = gc.allocPair(set_sym, set_args) catch return CompileError.OutOfMemory;
            consumer_body = gc.allocPair(set_form, consumer_body) catch return CompileError.OutOfMemory;
        }
    }

    var i = names.len;
    while (i > 0) {
        i -= 1;
        const orig_sym = gc.allocSymbol(names[i]) catch return CompileError.OutOfMemory;
        var param_name_buf: [32]u8 = undefined;
        const pname = std.fmt.bufPrint(&param_name_buf, "__dv_{d}", .{i}) catch return CompileError.OutOfMemory;
        const param_sym = gc.allocSymbol(pname) catch return CompileError.OutOfMemory;
        const set_rest = gc.allocPair(param_sym, types.NIL) catch return CompileError.OutOfMemory;
        const set_args = gc.allocPair(orig_sym, set_rest) catch return CompileError.OutOfMemory;
        const set_sym = gc.allocSymbol("set!") catch return CompileError.OutOfMemory;
        const set_form = gc.allocPair(set_sym, set_args) catch return CompileError.OutOfMemory;
        consumer_body = gc.allocPair(set_form, consumer_body) catch return CompileError.OutOfMemory;
    }

    if (consumer_body == types.NIL) {
        // (define-values () expr) — no bindings at all; just evaluate expr
        // for its side effects.
        return expr;
    }

    // Build consumer params list
    var consumer_params: Value = if (rest_name != null and names.len > 0)
        gc.allocSymbol("__dv_rest") catch return CompileError.OutOfMemory
    else
        types.NIL;

    i = names.len;
    while (i > 0) {
        i -= 1;
        var param_name_buf: [32]u8 = undefined;
        const pname = std.fmt.bufPrint(&param_name_buf, "__dv_{d}", .{i}) catch return CompileError.OutOfMemory;
        const param_sym = gc.allocSymbol(pname) catch return CompileError.OutOfMemory;
        consumer_params = gc.allocPair(param_sym, consumer_params) catch return CompileError.OutOfMemory;
    }

    // Build (lambda consumer_params consumer_body...)
    const consumer_lambda_args = gc.allocPair(consumer_params, consumer_body) catch return CompileError.OutOfMemory;
    const lambda_sym = gc.allocSymbol("lambda") catch return CompileError.OutOfMemory;
    const consumer = gc.allocPair(lambda_sym, consumer_lambda_args) catch return CompileError.OutOfMemory;

    // Build (lambda () expr)
    const producer_body = gc.allocPair(expr, types.NIL) catch return CompileError.OutOfMemory;
    const producer_lambda = gc.allocPair(types.NIL, producer_body) catch return CompileError.OutOfMemory;
    const producer = gc.allocPair(lambda_sym, producer_lambda) catch return CompileError.OutOfMemory;

    // Build (call-with-values producer consumer)
    // A compiler-synthesized reference: must mean the pristine (scheme base)
    // call-with-values even if the program rebinds the name at top level
    // (#1715, #2033).
    const cwv_sym = try compiler_mod.Compiler.trueBuiltinRefOrSymbol(gc, "call-with-values");
    const cwv_3 = gc.allocPair(consumer, types.NIL) catch return CompileError.OutOfMemory;
    const cwv_2 = gc.allocPair(producer, cwv_3) catch return CompileError.OutOfMemory;
    return gc.allocPair(cwv_sym, cwv_2) catch return CompileError.OutOfMemory;
}

pub fn compileDefineValues(self: *Compiler, args: Value, dst: u16) CompileError!void {
    if (args == types.NIL) return CompileError.InvalidSyntax;
    const formals = types.car(args);
    const rest = types.cdr(args);
    if (rest == types.NIL or !types.isPair(rest)) return CompileError.InvalidSyntax;
    const expr = types.car(rest);

    var names_buf: [64][]const u8 = undefined;
    var rest_name: ?[]const u8 = null;
    const name_count = try parseDefineValuesFormals(formals, names_buf[0..], &rest_name);

    // Build desugared form:
    //   (define x (if #f #f)) ...  ;; pre-define all variables
    //   (call-with-values (lambda () expr) (lambda (a b c ...) (set! x a) (set! y b) ...))
    // Then compile the desugared form.
    //
    // This pre-definition step is only reachable here for a define-values
    // clause that is NOT part of a body's leading letrec* region (e.g. one
    // following an ordinary expression, or at top level) — when it IS part
    // of that region, scanBodyDefs has already pre-declared these names
    // letrec*-style and compiles the clause via BodyScan.DefStep.values_group
    // instead of calling this function (#1719).
    for (names_buf[0..name_count]) |name| {
        var def_args = try buildVoidDefineArgs(self, name);
        self.gc.pushRoot(&def_args);
        defer self.gc.popRoot();
        try compileDefine(self, def_args, dst);
    }
    if (rest_name) |rn| {
        var def_args = try buildVoidDefineArgs(self, rn);
        self.gc.pushRoot(&def_args);
        defer self.gc.popRoot();
        try compileDefine(self, def_args, dst);
    }

    var assign_form = try buildDefineValuesAssignForm(self.gc, names_buf[0..name_count], rest_name, expr);
    self.gc.pushRoot(&assign_form);
    defer self.gc.popRoot();

    try self.compileExprViaIR(assign_form, dst, false);
    try self.emitOp(.load_void);
    try self.emitU16(dst);
}

/// Build ((name (if #f #f))) define args for define-values pre-definitions,
/// with collection disabled during the chain of fresh pair allocations.
fn buildVoidDefineArgs(self: *Compiler, name: []const u8) CompileError!Value {
    self.gc.no_collect += 1;
    defer self.gc.no_collect -= 1;
    const sym = self.gc.allocSymbol(name) catch return CompileError.OutOfMemory;
    const void_expr = self.gc.allocPair(types.FALSE, types.NIL) catch return CompileError.OutOfMemory;
    const if_args = self.gc.allocPair(types.FALSE, void_expr) catch return CompileError.OutOfMemory;
    const if_sym = self.gc.allocSymbol("if") catch return CompileError.OutOfMemory;
    const if_form = self.gc.allocPair(if_sym, if_args) catch return CompileError.OutOfMemory;
    const def_rest = self.gc.allocPair(if_form, types.NIL) catch return CompileError.OutOfMemory;
    return self.gc.allocPair(sym, def_rest) catch return CompileError.OutOfMemory;
}

pub fn compileSet(self: *Compiler, args: Value, dst: u16) CompileError!void {
    if (args == types.NIL) return CompileError.InvalidSyntax;
    const target = types.car(args);
    const rest = types.cdr(args);
    if (rest == types.NIL) return CompileError.InvalidSyntax;

    // SRFI-17 generalized set!: (set! (proc arg ...) val)
    // Desugar to: ((setter proc) arg ... val) and compile as a call.
    // Defensive fallback — the IR path (lowerSet) handles this first;
    // this branch fires only if compilation routes through compileExpr.
    // Requires (srfi 17) imported so the global `setter` is defined.
    if (types.isPair(target)) {
        const proc = types.car(target);
        const proc_args = types.cdr(target);
        const val_expr = types.car(rest);

        var arg_buf: [16]Value = undefined;
        var n_args: usize = 0;
        var cur = proc_args;
        while (cur != types.NIL) {
            if (!types.isPair(cur)) return CompileError.InvalidSyntax;
            if (n_args >= 16) return CompileError.InternalLimit;
            arg_buf[n_args] = types.car(cur);
            n_args += 1;
            cur = types.cdr(cur);
        }

        // Suppress GC during S-expression construction — intermediate
        // pairs are not reachable from any root until `desugared` is
        // rooted (same pattern as compileDefineValues, issue #1010).
        var desugared: Value = undefined;
        {
            self.gc.no_collect += 1;
            defer self.gc.no_collect -= 1;
            const setter_sym = self.gc.allocSymbol("setter") catch return CompileError.OutOfMemory;
            const setter_proc_pair = self.gc.allocPair(proc, types.NIL) catch return CompileError.OutOfMemory;
            const setter_call = self.gc.allocPair(setter_sym, setter_proc_pair) catch return CompileError.OutOfMemory;
            var ext_args = self.gc.allocPair(val_expr, types.NIL) catch return CompileError.OutOfMemory;
            var i = n_args;
            while (i > 0) {
                i -= 1;
                ext_args = self.gc.allocPair(arg_buf[i], ext_args) catch return CompileError.OutOfMemory;
            }
            desugared = self.gc.allocPair(setter_call, ext_args) catch return CompileError.OutOfMemory;
        }
        self.gc.pushRoot(&desugared);
        defer self.gc.popRoot();
        return self.compileExprViaIR(desugared, dst, false);
    }

    if (!types.isSymbol(target)) return CompileError.InvalidSyntax;

    const value_expr = types.car(rest);
    try self.compileExprViaIR(value_expr, dst, false);

    const name = types.symbolName(target);
    if (self.resolveLocal(name)) |slot| {
        if (self.globalAliasTargetName(name)) |gname| {
            // The target is a register alias injected for a macro template's
            // free reference to a global: the variable itself lives in the
            // globals map, so write through to it, then refresh the alias
            // register for subsequent reads within the same expansion.
            // `target` itself is the reference's hygienic rename, not the
            // bare global name (kaappi#1832), so the write-through must use
            // `gname` instead.
            const target_sym = try self.gc.allocSymbol(gname);
            const sym_idx = try self.addConstant(target_sym);
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
        const sym_idx = try self.addConstant(target);
        try self.emitOp(.set_global);
        try self.emitU16(sym_idx);
        try self.emitU16(dst);
    }
    try self.emitOp(.load_void);
    try self.emitU16(dst);
}

/// Compile (delay expr) as: create a promise wrapping (lambda () expr)
pub fn compileDelay(self: *Compiler, args: Value, dst: u16) CompileError!void {
    if (args == types.NIL) return CompileError.InvalidSyntax;
    const expr = types.car(args);

    // Compile (lambda () expr) using the same pattern as compileLambda
    var child = try Compiler.initChild(self);
    defer child.deinit();
    child.func.arity = 0;
    child.func.is_variadic = false;
    child.scope_depth = 1;
    const body_dst = child.allocReg() catch return CompileError.TooManyLocals;
    try child.compileExprViaIR(expr, body_dst, true);
    try child.emitOp(.@"return");
    try child.emitU16(body_dst);

    const thunk_reg = try self.allocReg();
    try emitClosureEpilogue(self, &child, thunk_reg);

    // Call %make-promise-lazy(thunk) — use fresh registers to avoid clobbering
    const sym = globals_mod.baseBindingSymbol(self.gc, "%make-promise-lazy") catch return CompileError.OutOfMemory;
    const sym_idx = try self.addConstant(sym);
    const call_base = try self.allocReg();
    try self.emitOp(.get_global);
    try self.emitU16(call_base);
    try self.emitU16(sym_idx);

    try self.emitOp(.move);
    try self.emitU16(call_base + 1);
    try self.emitU16(thunk_reg);

    try self.emitOp(.call);
    try self.emitU16(call_base);
    try self.emit(1);
    try self.emitOp(.move);
    try self.emitU16(dst);
    try self.emitU16(call_base);

    self.freeReg(); // free call_base
    self.freeReg(); // free thunk_reg
}

/// Compile (delay-force expr) — like delay but the result is itself forced iteratively
pub fn compileDelayForce(self: *Compiler, args: Value, dst: u16) CompileError!void {
    // delay-force is the same as delay for our purposes —
    // the iterative forcing in forceFn handles this correctly
    return compileDelay(self, args, dst);
}

pub fn compileBegin(self: *Compiler, args: Value, dst: u16, is_tail: bool) CompileError!void {
    if (args == types.NIL) {
        try self.emitOp(.load_void);
        try self.emitU16(dst);
        return;
    }

    var current = args;
    while (current != types.NIL) {
        if (!types.isPair(current)) return CompileError.InvalidSyntax;
        const expr = types.car(current);
        current = types.cdr(current);
        const tail = is_tail and current == types.NIL;
        try self.compileExprViaIR(expr, dst, tail);
    }
}

// -- Macro forms --
