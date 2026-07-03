const std = @import("std");
const types = @import("types.zig");
const memory = @import("memory.zig");
const Value = types.Value;
const GC = memory.GC;

var active_custom_ellipsis: ?[]const u8 = null;
var active_literals: []const Value = &.{};

fn isEllipsis(name: []const u8) bool {
    // If the name is listed as a literal, it's not the ellipsis
    for (active_literals) |lit| {
        if (types.isSymbol(lit) and std.mem.eql(u8, types.symbolName(lit), name)) return false;
    }
    if (active_custom_ellipsis) |ce| {
        return std.mem.eql(u8, name, ce);
    }
    return std.mem.eql(u8, name, "...");
}

// ---------------------------------------------------------------------------
// Hygienic renaming support (sets-of-scopes, simplified)
// ---------------------------------------------------------------------------
//
// Template-introduced identifiers that are NOT pattern variables, NOT
// literals, and NOT well-known special forms / built-in procedures get
// consistently renamed to gensyms within a single macro invocation.
// This prevents the classic hygiene bugs where a macro's internal
// binding (e.g. `temp` in `or`) captures a user variable of the same name.

/// Identifiers that must NEVER be renamed. Special forms that CAN be
/// rebound as variables (if, let, begin, etc.) are NOT in this list --
/// they get hygiene-renamed, and the compiler recognizes them via the
/// `if` and `let` are omitted — the R7RS test rebinds them as
/// variables. The compiler recognizes hygienic renames via
/// effective_name stripping.
const well_known_forms = [_][]const u8{
    "begin",         "define",        "set!",             "lambda",
    "let*",          "letrec",        "letrec*",          "quote",
    "quasiquote",    "unquote",       "unquote-splicing", "define-syntax",
    "let-syntax",    "letrec-syntax", "syntax-rules",     "define-record-type",
    "define-values", "let-values",    "let*-values",      "case-lambda",
    "cond-expand",   "cond",          "case",             "and",
    "or",            "when",          "unless",           "do",
    "guard",         "delay",         "delay-force",      "parameterize",
    "syntax-error",  "include",       "include-ci",       "define-library",
    "import",        "export",        "else",             "=>",
    "...",           "_",
};

pub fn isWellKnown(name: []const u8) bool {
    for (&well_known_forms) |wk| {
        if (std.mem.eql(u8, wk, name)) return true;
    }
    return false;
}

/// Monotonically increasing counter for generating unique hygienic names.
var gensym_counter: u32 = 0;

/// Scope identifier for macro invocations (each invocation gets a fresh one).
var next_scope_id: u32 = 0;

fn freshScope() u32 {
    next_scope_id += 1;
    return next_scope_id;
}

/// Tracks renamings within a single macro invocation so that the same
/// template identifier maps to the same gensym consistently.
const ScopeEntry = struct {
    original_name: []const u8,
    scope: u32,
    renamed_to: []const u8,
};

const MAX_SCOPE_ENTRIES = 256;
var scope_table: [MAX_SCOPE_ENTRIES]ScopeEntry = undefined;
var scope_table_count: usize = 0;

// ---------------------------------------------------------------------------
// Pattern variable binding
// ---------------------------------------------------------------------------

const MAX_BINDINGS = 128;
const MAX_ELLIPSIS_VALUES = 1024;

fn vectorToList(gc: *GC, data: []const Value) !Value {
    var result: Value = types.NIL;
    var i = data.len;
    while (i > 0) {
        i -= 1;
        result = try gc.allocPair(data[i], result);
    }
    return result;
}

fn listToVector(gc: *GC, list: Value) !Value {
    var len: usize = 0;
    var cur = list;
    while (cur != types.NIL and types.isPair(cur)) {
        len += 1;
        cur = types.cdr(cur);
    }
    const data = try gc.allocator.alloc(Value, len);
    defer gc.allocator.free(data);
    cur = list;
    for (0..len) |idx| {
        data[idx] = types.car(cur);
        cur = types.cdr(cur);
    }
    return gc.allocVector(data);
}

const Binding = struct {
    name: []const u8,
    value: Value,
    ellipsis_values: [MAX_ELLIPSIS_VALUES]Value = undefined,
    ellipsis_count: usize = 0,
    depth: u8,
    is_list: bool,
};

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

pub fn expandMacro(gc: *GC, expr: Value, transformer_val: Value, globals: ?*std.StringHashMap(Value), macros: ?*const std.StringHashMap(Value)) !Value {
    const transformer = types.toObject(transformer_val).as(types.Transformer);
    const saved_ellipsis = active_custom_ellipsis;
    active_custom_ellipsis = transformer.custom_ellipsis;
    defer active_custom_ellipsis = saved_ellipsis;
    const saved_literals = active_literals;
    active_literals = transformer.literals;
    defer active_literals = saved_literals;
    const input = types.cdr(expr); // skip the keyword

    // Extract the macro keyword name from the first pattern (car of the
    // full pattern list). This identifier must not be renamed during
    // hygiene: recursive macro calls in the template need to resolve
    // back to the same macro.
    var macro_keyword: ?[]const u8 = null;
    if (transformer.num_rules > 0) {
        const first_pat = transformer.patterns[0];
        if (types.isPair(first_pat)) {
            const kw = types.car(first_pat);
            if (types.isSymbol(kw)) {
                macro_keyword = types.symbolName(kw);
            }
        }
    }

    // Create a fresh scope for this macro invocation. All template-
    // introduced identifiers within this expansion share this scope,
    // so they get consistent renaming (the same name maps to the same
    // gensym) while differing from user identifiers.
    const intro_scope = freshScope();

    // The scope table is only a dedup cache for renames *within* this
    // expansion: each expansion has a globally-unique scope id, so entries
    // from prior expansions are never matched again. Release them on return
    // so the fixed-size table doesn't fill up over many expansions. (Once it
    // was full, new renames went unrecorded, so repeated references to the
    // same template identifier got *different* gensyms — splitting a binding
    // from its uses, e.g. `__hyg_N_res` undefined.) Save/restore rather than
    // zeroing keeps this correct even if expansion ever becomes re-entrant.
    const saved_scope_count = scope_table_count;
    defer scope_table_count = saved_scope_count;

    // Try each rule in order
    for (0..transformer.num_rules) |i| {
        var bindings: [MAX_BINDINGS]Binding = undefined;
        var bind_count: usize = 0;

        // Skip the keyword in the pattern (first element of pattern)
        const pattern_body = types.cdr(transformer.patterns[i]);

        if (matchPattern(pattern_body, input, transformer.literals[0..], &bindings, &bind_count, gc)) {
            return instantiateTemplate(gc, transformer.templates[i], bindings[0..bind_count], intro_scope, transformer.literals, macro_keyword, globals, macros);
        }
    }

    return error.NoMatchingPattern;
}

pub const ExpandError = error{
    NoMatchingPattern,
    ScopeTableFull,
    PatternTooComplex,
    EllipsisCountMismatch,
    EllipsisDepthMismatch,
    OutOfMemory,
};

// ---------------------------------------------------------------------------
// Pattern matching
// ---------------------------------------------------------------------------

fn matchPattern(pattern: Value, input: Value, literals: []const Value, bindings: *[MAX_BINDINGS]Binding, count: *usize, gc: ?*GC) bool {
    // Symbol patterns
    if (types.isSymbol(pattern)) {
        const name = types.symbolName(pattern);

        // Check if it's a literal (including _ when in literals list)
        for (literals) |lit| {
            if (types.isSymbol(lit) and std.mem.eql(u8, types.symbolName(lit), name)) {
                return types.isSymbol(input) and std.mem.eql(u8, types.symbolName(input), name);
            }
        }

        // Underscore (not in literals): match anything, bind nothing
        if (std.mem.eql(u8, name, "_")) return true;

        // Pattern variable: bind to input
        if (count.* >= MAX_BINDINGS) return false;
        bindings[count.*] = .{
            .name = name,
            .value = input,
            .depth = 0,
            .is_list = false,
        };
        count.* += 1;
        return true;
    }

    // Constants: match via equality
    if (types.isFixnum(pattern)) {
        return types.isFixnum(input) and pattern == input;
    }
    if (types.isFlonum(pattern)) {
        return types.isFlonum(input) and pattern == input;
    }
    if (types.isBool(pattern)) {
        return pattern == input;
    }
    if (types.isChar(pattern)) {
        return pattern == input;
    }
    if (types.isString(pattern) and types.isString(input)) {
        const sp = types.toObject(pattern).as(types.SchemeString);
        const si = types.toObject(input).as(types.SchemeString);
        return std.mem.eql(u8, sp.data, si.data);
    }

    // Nil matches nil
    if (pattern == types.NIL) return input == types.NIL;

    // Vector pattern: #(p1 ... pn) matches a vector input
    if (types.isVector(pattern)) {
        if (!types.isVector(input)) return false;
        const the_gc = gc orelse return false;
        const pvec = types.toObject(pattern).as(types.Vector);
        const ivec = types.toObject(input).as(types.Vector);
        const plist = vectorToList(the_gc, pvec.data) catch return false;
        const ilist = vectorToList(the_gc, ivec.data) catch return false;
        return matchListPattern(plist, ilist, literals, bindings, count, gc);
    }

    // List pattern
    if (types.isPair(pattern)) {
        return matchListPattern(pattern, input, literals, bindings, count, gc);
    }

    return false;
}

fn matchListPattern(pattern: Value, input: Value, literals: []const Value, bindings: *[MAX_BINDINGS]Binding, count: *usize, gc: ?*GC) bool {
    var pat = pattern;
    var inp = input;

    while (pat != types.NIL) {
        if (!types.isPair(pat)) {
            // Dotted pattern tail
            return matchPattern(pat, inp, literals, bindings, count, gc);
        }

        const pat_elem = types.car(pat);
        const pat_rest = types.cdr(pat);

        // Check if next element is ellipsis
        if (pat_rest != types.NIL and types.isPair(pat_rest)) {
            const maybe_ellipsis = types.car(pat_rest);
            if (types.isSymbol(maybe_ellipsis) and isEllipsis(types.symbolName(maybe_ellipsis))) {
                // Ellipsis: pat_elem matches zero or more input elements
                const after_ellipsis = types.cdr(pat_rest);
                return matchEllipsis(pat_elem, after_ellipsis, inp, literals, bindings, count, gc);
            }
        }

        // Regular element: input must be a pair
        if (!types.isPair(inp)) return false;
        if (!matchPattern(pat_elem, types.car(inp), literals, bindings, count, gc)) return false;

        pat = pat_rest;
        inp = types.cdr(inp);
    }

    return inp == types.NIL;
}

fn countPairs(v: Value) ?usize {
    // Cycle detection (tortoise-hare) to avoid looping forever on
    // cyclic structures produced via datum labels.
    var slow = v;
    var fast = v;
    while (types.isPair(fast)) {
        fast = types.cdr(fast);
        if (!types.isPair(fast)) break;
        fast = types.cdr(fast);
        if (types.isPair(slow)) slow = types.cdr(slow);
        if (slow == fast) return null;
    }

    var n: usize = 0;
    var cur = v;
    while (types.isPair(cur)) {
        n += 1;
        if (n > MAX_ELLIPSIS_VALUES) return null;
        cur = types.cdr(cur);
    }
    return n;
}

fn matchEllipsis(elem_pattern: Value, rest_pattern: Value, input: Value, literals: []const Value, bindings: *[MAX_BINDINGS]Binding, count: *usize, gc: ?*GC) bool {
    // Count how many elements the rest_pattern needs (handles improper lists)
    const rest_len = countPairs(rest_pattern) orelse return false;
    const input_len = countPairs(input) orelse return false;

    if (input_len < rest_len) return false;
    const repeat_count = input_len - rest_len;

    var elem_var_names: [128][]const u8 = undefined;
    var elem_var_count: usize = 0;
    var var_overflow = false;
    collectPatternVars(elem_pattern, literals, &elem_var_names, &elem_var_count, &var_overflow);
    if (var_overflow) return false;

    // Create list bindings for each pattern variable found in the ellipsis sub-pattern
    const base_count = count.*;
    for (0..elem_var_count) |vi| {
        if (count.* >= MAX_BINDINGS) return false;
        bindings[count.*] = .{
            .name = elem_var_names[vi],
            .value = types.NIL,
            .depth = 1,
            .is_list = true,
        };
        count.* += 1;
    }

    // Match each repetition
    var inp = input;
    for (0..repeat_count) |_| {
        var sub_bindings: [MAX_BINDINGS]Binding = undefined;
        var sub_count: usize = 0;
        if (!matchPattern(elem_pattern, types.car(inp), literals, &sub_bindings, &sub_count, gc))
            return false;

        // Append each sub-binding value to the corresponding list binding
        for (0..sub_count) |si| {
            for (base_count..count.*) |bi| {
                if (std.mem.eql(u8, bindings[bi].name, sub_bindings[si].name)) {
                    if (bindings[bi].ellipsis_count >= MAX_ELLIPSIS_VALUES) return false;
                    if (sub_bindings[si].is_list) {
                        // Nested ellipsis: build list from inner values
                        if (gc) |g| {
                            var inner_list: Value = types.NIL;
                            var k = sub_bindings[si].ellipsis_count;
                            while (k > 0) {
                                k -= 1;
                                inner_list = g.allocPair(sub_bindings[si].ellipsis_values[k], inner_list) catch return false;
                            }
                            bindings[bi].ellipsis_values[bindings[bi].ellipsis_count] = inner_list;
                            bindings[bi].depth = sub_bindings[si].depth + 1;
                        } else {
                            bindings[bi].ellipsis_values[bindings[bi].ellipsis_count] = sub_bindings[si].value;
                        }
                    } else {
                        bindings[bi].ellipsis_values[bindings[bi].ellipsis_count] = sub_bindings[si].value;
                    }
                    bindings[bi].ellipsis_count += 1;
                    break;
                }
            }
        }

        inp = types.cdr(inp);
    }

    // Match remaining input against rest_pattern
    if (rest_pattern == types.NIL) return inp == types.NIL;
    return matchListPattern(rest_pattern, inp, literals, bindings, count, gc);
}

fn collectPatternVars(pattern: Value, literals: []const Value, names: *[128][]const u8, count: *usize, overflowed: *bool) void {
    if (types.isSymbol(pattern)) {
        const name = types.symbolName(pattern);
        if (std.mem.eql(u8, name, "_")) return;
        for (literals) |lit| {
            if (types.isSymbol(lit) and std.mem.eql(u8, types.symbolName(lit), name))
                return;
        }
        if (isEllipsis(name)) return;
        if (count.* >= 128) {
            overflowed.* = true;
            return;
        }
        names[count.*] = name;
        count.* += 1;
        return;
    }

    if (types.isPair(pattern)) {
        collectPatternVars(types.car(pattern), literals, names, count, overflowed);
        collectPatternVars(types.cdr(pattern), literals, names, count, overflowed);
    }
    if (types.isVector(pattern)) {
        const vec = types.toObject(pattern).as(types.Vector);
        for (vec.data) |elem| {
            collectPatternVars(elem, literals, names, count, overflowed);
        }
    }
}

// ---------------------------------------------------------------------------
// Template instantiation
// ---------------------------------------------------------------------------

fn instantiateTemplate(gc: *GC, template: Value, bindings: []Binding, intro_scope: u32, literals: []const Value, macro_keyword: ?[]const u8, globals: ?*std.StringHashMap(Value), macros: ?*const std.StringHashMap(Value)) (std.mem.Allocator.Error || ExpandError)!Value {
    if (types.isSymbol(template)) {
        const name = types.symbolName(template);

        // 1. Pattern variable -- substitute with matched value (from use site)
        for (bindings) |b| {
            if (std.mem.eql(u8, b.name, name)) {
                if (!b.is_list) return b.value;
                // Shouldn't use a list binding at depth 0 without ellipsis
                return b.value;
            }
        }

        // 2. Literal keyword -- keep as-is
        for (literals) |lit| {
            if (types.isSymbol(lit) and std.mem.eql(u8, types.symbolName(lit), name)) {
                return template;
            }
        }

        // 3. Well-known form or built-in -- keep as-is
        if (isWellKnown(name)) {
            return template;
        }

        // 4. Macro's own keyword (for recursive calls) -- keep as-is
        if (macro_keyword) |kw| {
            if (std.mem.eql(u8, kw, name)) {
                return template;
            }
        }

        // 4b. Known macro keyword (for mutual recursion in letrec-syntax) -- keep as-is
        if (macros) |m| {
            if (m.contains(name)) {
                return template;
            }
        }

        // 5. Template-introduced identifier -- rename for hygiene
        return renameForHygiene(gc, name, intro_scope, globals);
    }

    if (types.isVector(template)) {
        const vec = types.toObject(template).as(types.Vector);
        const as_list = vectorToList(gc, vec.data) catch return error.OutOfMemory;
        const result_list = try instantiateTemplate(gc, as_list, bindings, intro_scope, literals, macro_keyword, globals, macros);
        return listToVector(gc, result_list) catch return error.OutOfMemory;
    }

    if (!types.isPair(template)) return template;

    const QUOTE_FLAG: u32 = 0x40000000;
    const ESCAPE_FLAG: u32 = 0x80000000;
    const in_escape = (intro_scope & ESCAPE_FLAG) != 0;

    // Check for (quote ...) — substitute pattern vars but skip hygiene renaming
    const tmpl_head = types.car(template);
    if (types.isSymbol(tmpl_head) and std.mem.eql(u8, types.symbolName(tmpl_head), "quote")) {
        const q_rest = types.cdr(template);
        if (q_rest != types.NIL and types.isPair(q_rest)) {
            const quoted = types.car(q_rest);
            const new_quoted = try instantiateTemplate(gc, quoted, bindings, intro_scope | QUOTE_FLAG, literals, macro_keyword, globals, macros);
            return gc.allocPair(tmpl_head, try gc.allocPair(new_quoted, types.NIL));
        }
        return template;
    }

    // Check for ellipsis escape: (... <template>) — treat ... as literal inside
    const elem = types.car(template);
    const rest = types.cdr(template);
    if (!in_escape and types.isSymbol(elem) and isEllipsis(types.symbolName(elem))) {
        if (rest != types.NIL and types.isPair(rest) and types.cdr(rest) == types.NIL) {
            const inner = types.car(rest);
            return instantiateTemplate(gc, inner, bindings, intro_scope | ESCAPE_FLAG, literals, macro_keyword, globals, macros);
        }
        return template;
    }

    // Check for ellipsis in template: (Te ...) — skip inside escape context
    if (!in_escape and rest != types.NIL and types.isPair(rest)) {
        const maybe_ellipsis = types.car(rest);
        if (types.isSymbol(maybe_ellipsis) and isEllipsis(types.symbolName(maybe_ellipsis))) {
            // Replicate elem for each ellipsis binding
            const after = types.cdr(rest);
            return instantiateEllipsis(gc, elem, after, bindings, intro_scope, literals, macro_keyword, globals, macros);
        }
    }

    // Nested syntax-rules: protect inner pattern variables from outer substitution
    if (types.isSymbol(elem) and std.mem.eql(u8, types.symbolName(elem), "syntax-rules")) {
        return instantiateNestedSyntaxRules(gc, template, bindings, intro_scope, literals, macro_keyword, globals, macros);
    }

    // Detect binding forms and set binding-position flag for variable names
    const BINDING_FLAG: u32 = 0x20000000;
    if (types.isSymbol(elem)) {
        const form_name = types.symbolName(elem);
        const is_let_form = std.mem.eql(u8, form_name, "let") or
            std.mem.eql(u8, form_name, "let*") or
            std.mem.eql(u8, form_name, "letrec") or
            std.mem.eql(u8, form_name, "letrec*");
        if (is_let_form) {
            const new_car = try instantiateTemplate(gc, elem, bindings, intro_scope, literals, macro_keyword, globals, macros);
            var car_root = new_car;
            try gc.pushRoot(&car_root);
            defer gc.popRoot();
            const let_rest = types.cdr(template);
            if (let_rest != types.NIL and types.isPair(let_rest)) {
                const binding_list = types.car(let_rest);
                const body = types.cdr(let_rest);
                const new_bindings = try instantiateLetBindings(gc, binding_list, bindings, intro_scope | BINDING_FLAG, literals, macro_keyword, globals, macros);
                var bindings_root = new_bindings;
                try gc.pushRoot(&bindings_root);
                defer gc.popRoot();
                const new_body = try instantiateTemplate(gc, body, bindings, intro_scope & ~BINDING_FLAG, literals, macro_keyword, globals, macros);
                var body_root = new_body;
                try gc.pushRoot(&body_root);
                defer gc.popRoot();
                const inner = try gc.allocPair(bindings_root, body_root);
                return gc.allocPair(car_root, inner);
            }
        }
    }

    // Regular pair: recurse
    const new_car = try instantiateTemplate(gc, types.car(template), bindings, intro_scope & ~BINDING_FLAG, literals, macro_keyword, globals, macros);
    var car_root = new_car;
    try gc.pushRoot(&car_root);
    defer gc.popRoot();
    const new_cdr = try instantiateTemplate(gc, types.cdr(template), bindings, intro_scope & ~BINDING_FLAG, literals, macro_keyword, globals, macros);
    return gc.allocPair(car_root, new_cdr);
}

fn instantiateLetBindings(gc: *GC, binding_list: Value, bindings: []Binding, scope: u32, literals: []const Value, macro_keyword: ?[]const u8, globals: ?*std.StringHashMap(Value), macros: ?*const std.StringHashMap(Value)) !Value {
    if (binding_list == types.NIL) return types.NIL;
    if (!types.isPair(binding_list)) return instantiateTemplate(gc, binding_list, bindings, scope, literals, macro_keyword, globals, macros);
    const pair = types.car(binding_list);
    if (!types.isPair(pair)) {
        const new_pair = try instantiateTemplate(gc, pair, bindings, scope, literals, macro_keyword, globals, macros);
        var pair_root = new_pair;
        try gc.pushRoot(&pair_root);
        defer gc.popRoot();
        const new_rest = try instantiateLetBindings(gc, types.cdr(binding_list), bindings, scope, literals, macro_keyword, globals, macros);
        return gc.allocPair(pair_root, new_rest);
    }
    const var_name = types.car(pair);
    const init_and_rest = types.cdr(pair);
    const new_var = try instantiateTemplate(gc, var_name, bindings, scope, literals, macro_keyword, globals, macros);
    var var_root = new_var;
    try gc.pushRoot(&var_root);
    defer gc.popRoot();
    const new_init = try instantiateTemplate(gc, init_and_rest, bindings, scope & ~@as(u32, 0x20000000), literals, macro_keyword, globals, macros);
    var init_root = new_init;
    try gc.pushRoot(&init_root);
    defer gc.popRoot();
    const new_pair = try gc.allocPair(var_root, init_root);
    var np_root = new_pair;
    try gc.pushRoot(&np_root);
    defer gc.popRoot();
    const new_rest = try instantiateLetBindings(gc, types.cdr(binding_list), bindings, scope, literals, macro_keyword, globals, macros);
    return gc.allocPair(np_root, new_rest);
}

fn instantiateNestedSyntaxRules(gc: *GC, template: Value, bindings: []Binding, intro_scope: u32, literals: []const Value, macro_keyword: ?[]const u8, globals: ?*std.StringHashMap(Value), macros: ?*const std.StringHashMap(Value)) (std.mem.Allocator.Error || ExpandError)!Value {
    // template = (syntax-rules (lits...) (pat tmpl) ...)
    // Collect inner pattern variable names to exclude from outer bindings
    var inner_pvs: [128][]const u8 = undefined;
    var inner_pv_count: usize = 0;
    const sr_rest = types.cdr(template); // skip 'syntax-rules'
    if (sr_rest != types.NIL and types.isPair(sr_rest)) {
        var rules = types.cdr(sr_rest); // skip literals list
        while (rules != types.NIL and types.isPair(rules)) {
            const rule = types.car(rules);
            if (types.isPair(rule)) {
                var overflowed = false;
                collectPatternVars(types.car(rule), literals, &inner_pvs, &inner_pv_count, &overflowed);
                if (overflowed) return ExpandError.PatternTooComplex;
            }
            rules = types.cdr(rules);
        }
    }
    // Filter outer bindings: remove any that clash with inner pattern variables
    var filtered: [MAX_BINDINGS]Binding = undefined;
    var filt_count: usize = 0;
    for (bindings) |b| {
        var is_inner = false;
        for (inner_pvs[0..inner_pv_count]) |ipv| {
            if (std.mem.eql(u8, b.name, ipv)) {
                is_inner = true;
                break;
            }
        }
        if (!is_inner) {
            filtered[filt_count] = b;
            filt_count += 1;
        }
    }
    // Recurse with filtered bindings
    const new_car = try instantiateTemplate(gc, types.car(template), filtered[0..filt_count], intro_scope, literals, macro_keyword, globals, macros);
    var car_root = new_car;
    try gc.pushRoot(&car_root);
    defer gc.popRoot();
    const new_cdr = try instantiateTemplate(gc, types.cdr(template), filtered[0..filt_count], intro_scope, literals, macro_keyword, globals, macros);
    return gc.allocPair(car_root, new_cdr);
}

fn templateReferencesVar(template: Value, name: []const u8) bool {
    if (types.isSymbol(template)) {
        return std.mem.eql(u8, types.symbolName(template), name);
    }
    if (types.isPair(template)) {
        return templateReferencesVar(types.car(template), name) or
            templateReferencesVar(types.cdr(template), name);
    }
    return false;
}

fn instantiateEllipsis(gc: *GC, elem_template: Value, rest_template: Value, bindings: []Binding, intro_scope: u32, literals: []const Value, macro_keyword: ?[]const u8, globals: ?*std.StringHashMap(Value), macros: ?*const std.StringHashMap(Value)) (std.mem.Allocator.Error || ExpandError)!Value {
    // Find the repeat count from ellipsis bindings referenced in elem_template.
    // All referenced list bindings must have equal counts (R7RS). Bindings
    // with depth > 1 (nested ellipses) participate too: their ellipsis_count
    // at this level is the outer repetition count, and each iteration below
    // unpacks them one level for the inner ellipsis to consume.
    var repeat_count: usize = 0;
    var count_set = false;
    for (bindings) |b| {
        if (b.is_list and templateReferencesVar(elem_template, b.name)) {
            if (!count_set) {
                repeat_count = b.ellipsis_count;
                count_set = true;
            } else if (b.ellipsis_count != repeat_count) {
                return ExpandError.EllipsisCountMismatch;
            }
        }
    }

    // First instantiate the rest (after the ellipsis)
    const result = try instantiateTemplate(gc, rest_template, bindings, intro_scope, literals, macro_keyword, globals, macros);
    var result_root = result;
    try gc.pushRoot(&result_root);
    defer gc.popRoot();

    // Generate copies in reverse so we build the list from right to left
    var i = repeat_count;
    while (i > 0) {
        i -= 1;
        // Create sub-bindings with the i-th value for each list binding
        var sub_bindings: [MAX_BINDINGS]Binding = undefined;
        var sub_count: usize = 0;
        for (bindings) |b| {
            if (b.is_list) {
                if (b.depth > 1) {
                    // Nested ellipsis: unpack list into sub-binding
                    sub_bindings[sub_count] = .{
                        .name = b.name,
                        .value = types.NIL,
                        .depth = b.depth - 1,
                        .is_list = true,
                    };
                    var list_val = b.ellipsis_values[i];
                    var ev_count: usize = 0;
                    while (types.isPair(list_val) and ev_count < MAX_ELLIPSIS_VALUES) {
                        sub_bindings[sub_count].ellipsis_values[ev_count] = types.car(list_val);
                        ev_count += 1;
                        list_val = types.cdr(list_val);
                    }
                    sub_bindings[sub_count].ellipsis_count = ev_count;
                } else {
                    sub_bindings[sub_count] = .{
                        .name = b.name,
                        .value = b.ellipsis_values[i],
                        .depth = 0,
                        .is_list = false,
                    };
                }
            } else {
                sub_bindings[sub_count] = b;
            }
            sub_count += 1;
        }
        const expanded = try instantiateTemplate(gc, elem_template, sub_bindings[0..sub_count], intro_scope, literals, macro_keyword, globals, macros);
        var expanded_root = expanded;
        try gc.pushRoot(&expanded_root);
        result_root = try gc.allocPair(expanded_root, result_root);
        gc.popRoot();
    }

    return result_root;
}

// ---------------------------------------------------------------------------
// Hygienic renaming
// ---------------------------------------------------------------------------

/// Rename a template-introduced identifier for hygiene. Within a single
/// macro invocation (identified by `scope`), the same original name always
/// maps to the same gensym, ensuring internal references stay consistent
/// while avoiding capture of user bindings.
fn substitutePatternVarsOnly(gc: *GC, template: Value, bindings: []Binding) !Value {
    if (types.isSymbol(template)) {
        const name = types.symbolName(template);
        for (bindings) |b| {
            if (std.mem.eql(u8, b.name, name)) return b.value;
        }
        return template;
    }
    if (!types.isPair(template)) return template;
    const new_car = try substitutePatternVarsOnly(gc, types.car(template), bindings);
    var car_root = new_car;
    try gc.pushRoot(&car_root);
    const new_cdr = try substitutePatternVarsOnly(gc, types.cdr(template), bindings);
    gc.popRoot();
    return gc.allocPair(car_root, new_cdr);
}

fn scopeTableContains(scope: u32, name: []const u8) bool {
    for (scope_table[0..scope_table_count]) |entry| {
        if (entry.scope == scope and std.mem.eql(u8, entry.original_name, name)) return true;
    }
    return false;
}

fn renameForHygiene(gc: *GC, name: []const u8, scope: u32, globals: ?*std.StringHashMap(Value)) !Value {
    const QUOTE_FLAG: u32 = 0x40000000;
    const BINDING_FLAG: u32 = 0x20000000;
    if ((scope & QUOTE_FLAG) != 0) return gc.allocSymbol(name);

    // Already renamed by an enclosing expansion: macro-generating macros
    // bake __hyg_ names into the inner macro's stored template. Gensyms are
    // globally unique, so renaming again cannot prevent any capture — it
    // only severs the reference from the binding created by the generating
    // expansion (issue #919: __hyg_N___hyg_M_march-hare undefined).
    if (std.mem.startsWith(u8, name, "__hyg_")) return gc.allocSymbol(name);
    const in_binding = (scope & BINDING_FLAG) != 0;
    const clean_scope = scope & ~BINDING_FLAG;
    const vm_mod = @import("vm.zig");
    if (globals) |g| {
        const glk = vm_mod.acquireGlobalsRead(g);
        defer vm_mod.releaseGlobalsRead(glk);
        if (g.get(name)) |val| {
            if (types.isProcedure(val) or types.isTransformer(val)) {
                // A template binding of the same name in this expansion
                // shadows the global procedure (e.g. a template let variable
                // named exp must not resolve to the builtin exp), so the
                // reference must follow the rename recorded for the binding.
                if (!in_binding and !scopeTableContains(clean_scope, name)) {
                    return gc.allocSymbol(name);
                }
            } else if (val == types.VOID) {
                // VOID entries are sentinels planted by the compiler's body
                // prescan (compileBody/compileLetBody) for internal defines
                // that appear later in the same body — the template reference
                // must keep its name so it resolves to that binding (R7RS
                // 5.3.2 letrec* body semantics). But if this expansion already
                // renamed the name as a template-introduced binding, the
                // reference must follow the rename instead.
                if (!in_binding and !scopeTableContains(clean_scope, name)) {
                    return gc.allocSymbol(name);
                }
            }
        }
    }
    if (vm_mod.vm_instance) |vm| {
        vm.lockGlobalsShared();
        const found = vm.globals.get(name);
        vm.unlockGlobalsShared();
        if (found) |val| {
            if (types.isTransformer(val)) return gc.allocSymbol(name);
        }
    }

    for (scope_table[0..scope_table_count]) |entry| {
        if (entry.scope == clean_scope and std.mem.eql(u8, entry.original_name, name)) {
            return gc.allocSymbol(entry.renamed_to);
        }
    }

    // Generate a fresh hygienic name for truly new identifiers
    gensym_counter += 1;
    var buf: [128]u8 = undefined;
    const len = std.fmt.bufPrint(&buf, "__hyg_{d}_{s}", .{ gensym_counter, name }) catch
        return gc.allocSymbol(name);

    const sym_val = try gc.allocSymbol(len);
    const renamed_persistent = types.symbolName(sym_val);

    if (scope_table_count >= MAX_SCOPE_ENTRIES) return ExpandError.ScopeTableFull;
    scope_table[scope_table_count] = .{
        .original_name = name,
        .scope = clean_scope,
        .renamed_to = renamed_persistent,
    };
    scope_table_count += 1;

    return sym_val;
}
