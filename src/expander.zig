const std = @import("std");
const types = @import("types.zig");
const memory = @import("memory.zig");
const Value = types.Value;
const GC = memory.GC;

// ---------------------------------------------------------------------------
// Hygienic renaming support (sets-of-scopes, simplified)
// ---------------------------------------------------------------------------
//
// Template-introduced identifiers that are NOT pattern variables, NOT
// literals, and NOT well-known special forms / built-in procedures get
// consistently renamed to gensyms within a single macro invocation.
// This prevents the classic hygiene bugs where a macro's internal
// binding (e.g. `temp` in `or`) captures a user variable of the same name.

/// Identifiers that must NEVER be renamed -- they are special forms
/// recognized by the compiler or fundamental built-in procedures that
/// macro templates legitimately reference.
const well_known_forms = [_][]const u8{
    // Special forms (compiler keywords)
    "if",           "let",        "let*",       "letrec",
    "letrec*",      "lambda",     "define",     "set!",
    "begin",        "quote",      "quasiquote", "unquote",
    "unquote-splicing",
    "cond",         "case",       "and",        "or",
    "when",         "unless",     "do",
    "define-syntax", "let-syntax", "letrec-syntax", "syntax-rules",
    "define-record-type",
    "define-values", "let-values", "let*-values",
    "case-lambda",  "cond-expand",
    "guard",        "delay",      "delay-force",
    "parameterize", "syntax-error",
    "include",      "include-ci",
    "define-library", "import",   "export",
    // Tail-form keywords
    "else",         "=>",
    // Built-in procedures commonly used in macro templates
    "cons",         "car",        "cdr",        "list",
    "append",       "map",        "for-each",
    "+",            "-",          "*",          "/",
    "=",            "<",          ">",          "<=",        ">=",
    "not",          "null?",      "pair?",      "boolean?",
    "number?",      "symbol?",    "string?",    "char?",
    "vector?",      "procedure?", "port?",      "eof-object?",
    "eq?",          "eqv?",       "equal?",
    "zero?",        "positive?",  "negative?",
    "even?",        "odd?",
    "abs",          "min",        "max",
    "length",       "reverse",    "memq",       "memv",
    "assq",         "assv",
    "values",       "call-with-values", "apply",
    "call-with-current-continuation", "call/cc",
    "dynamic-wind",
    "with-exception-handler", "raise", "raise-continuable",
    "error",        "error-object?",
    "display",      "newline",    "write",      "read",
    "open-input-file", "open-output-file",
    "close-input-port", "close-output-port",
    "current-input-port", "current-output-port", "current-error-port",
    "string-ref",   "string-set!",
    "string-length", "substring",  "string-append",
    "string->number", "number->string",
    "string->symbol", "symbol->string",
    "string-copy",  "string-copy!",
    "vector-ref",   "vector-set!",
    "vector-length", "make-vector", "vector->list", "list->vector",
    "make-string",  "string->list", "list->string",
    "char->integer", "integer->char",
    "exact",        "inexact",
    "floor",        "ceiling",    "truncate",   "round",
    "modulo",       "remainder",  "quotient",
    "gcd",          "lcm",
    "expt",         "sqrt",
    "make-parameter",
    "make-promise", "force",
    "boolean=?",
    "char=?",       "char<?",     "char>?",
    "string=?",     "string<?",
    "...",          "_",
};

fn isWellKnown(name: []const u8) bool {
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

const MAX_BINDINGS = 64;
const MAX_ELLIPSIS_VALUES = 256;

const Binding = struct {
    name: []const u8,
    value: Value,
    // For ellipsis-bound variables (depth > 0): collected values stored inline
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

    // Try each rule in order
    for (0..transformer.num_rules) |i| {
        var bindings: [MAX_BINDINGS]Binding = undefined;
        var bind_count: usize = 0;

        // Skip the keyword in the pattern (first element of pattern)
        const pattern_body = types.cdr(transformer.patterns[i]);

        if (matchPattern(pattern_body, input, transformer.literals[0..], &bindings, &bind_count)) {
            return instantiateTemplate(gc, transformer.templates[i], bindings[0..bind_count], intro_scope, transformer.literals, macro_keyword, globals, macros);
        }
    }

    return error.NoMatchingPattern;
}

pub const ExpandError = error{
    NoMatchingPattern,
    OutOfMemory,
};

// ---------------------------------------------------------------------------
// Pattern matching
// ---------------------------------------------------------------------------

fn matchPattern(pattern: Value, input: Value, literals: []const Value, bindings: *[MAX_BINDINGS]Binding, count: *usize) bool {
    // Underscore: match anything, bind nothing
    if (types.isSymbol(pattern) and std.mem.eql(u8, types.symbolName(pattern), "_")) {
        return true;
    }

    // Symbol patterns
    if (types.isSymbol(pattern)) {
        const name = types.symbolName(pattern);

        // Check if it's a literal
        for (literals) |lit| {
            if (types.isSymbol(lit) and std.mem.eql(u8, types.symbolName(lit), name)) {
                // Literal: must match exactly
                return types.isSymbol(input) and std.mem.eql(u8, types.symbolName(input), name);
            }
        }

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

    // List pattern
    if (types.isPair(pattern)) {
        return matchListPattern(pattern, input, literals, bindings, count);
    }

    return false;
}

fn matchListPattern(pattern: Value, input: Value, literals: []const Value, bindings: *[MAX_BINDINGS]Binding, count: *usize) bool {
    var pat = pattern;
    var inp = input;

    while (pat != types.NIL) {
        if (!types.isPair(pat)) {
            // Dotted pattern tail
            return matchPattern(pat, inp, literals, bindings, count);
        }

        const pat_elem = types.car(pat);
        const pat_rest = types.cdr(pat);

        // Check if next element is ellipsis
        if (pat_rest != types.NIL and types.isPair(pat_rest)) {
            const maybe_ellipsis = types.car(pat_rest);
            if (types.isSymbol(maybe_ellipsis) and std.mem.eql(u8, types.symbolName(maybe_ellipsis), "...")) {
                // Ellipsis: pat_elem matches zero or more input elements
                const after_ellipsis = types.cdr(pat_rest);
                return matchEllipsis(pat_elem, after_ellipsis, inp, literals, bindings, count);
            }
        }

        // Regular element: input must be a pair
        if (!types.isPair(inp)) return false;
        if (!matchPattern(pat_elem, types.car(inp), literals, bindings, count)) return false;

        pat = pat_rest;
        inp = types.cdr(inp);
    }

    return inp == types.NIL;
}

fn matchEllipsis(elem_pattern: Value, rest_pattern: Value, input: Value, literals: []const Value, bindings: *[MAX_BINDINGS]Binding, count: *usize) bool {
    // Count how many elements the rest_pattern needs
    const rest_len = types.listLength(rest_pattern) orelse 0;
    const input_len = types.listLength(input) orelse 0;

    if (input_len < rest_len) return false;
    const repeat_count = input_len - rest_len;

    // Collect pattern variable names from elem_pattern
    var elem_var_names: [16][]const u8 = undefined;
    var elem_var_count: usize = 0;
    collectPatternVars(elem_pattern, literals, &elem_var_names, &elem_var_count);

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
        if (!matchPattern(elem_pattern, types.car(inp), literals, &sub_bindings, &sub_count))
            return false;

        // Append each sub-binding value to the corresponding list binding
        for (0..sub_count) |si| {
            for (base_count..count.*) |bi| {
                if (std.mem.eql(u8, bindings[bi].name, sub_bindings[si].name)) {
                    if (bindings[bi].ellipsis_count < MAX_ELLIPSIS_VALUES) {
                        bindings[bi].ellipsis_values[bindings[bi].ellipsis_count] = sub_bindings[si].value;
                        bindings[bi].ellipsis_count += 1;
                    }
                    break;
                }
            }
        }

        inp = types.cdr(inp);
    }

    // Match remaining input against rest_pattern
    if (rest_pattern == types.NIL) return inp == types.NIL;
    return matchListPattern(rest_pattern, inp, literals, bindings, count);
}

fn collectPatternVars(pattern: Value, literals: []const Value, names: *[16][]const u8, count: *usize) void {
    if (types.isSymbol(pattern)) {
        const name = types.symbolName(pattern);
        // Skip underscore
        if (std.mem.eql(u8, name, "_")) return;
        // Skip literals
        for (literals) |lit| {
            if (types.isSymbol(lit) and std.mem.eql(u8, types.symbolName(lit), name))
                return;
        }
        // Skip ellipsis
        if (std.mem.eql(u8, name, "...")) return;
        // Add pattern variable
        if (count.* < 16) {
            names[count.*] = name;
            count.* += 1;
        }
        return;
    }

    if (types.isPair(pattern)) {
        collectPatternVars(types.car(pattern), literals, names, count);
        collectPatternVars(types.cdr(pattern), literals, names, count);
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

    if (!types.isPair(template)) return template;

    // Check for ellipsis in template: (Te ...)
    const elem = types.car(template);
    const rest = types.cdr(template);

    if (rest != types.NIL and types.isPair(rest)) {
        const maybe_ellipsis = types.car(rest);
        if (types.isSymbol(maybe_ellipsis) and std.mem.eql(u8, types.symbolName(maybe_ellipsis), "...")) {
            // Replicate elem for each ellipsis binding
            const after = types.cdr(rest);
            return instantiateEllipsis(gc, elem, after, bindings, intro_scope, literals, macro_keyword, globals, macros);
        }
    }

    // Regular pair: recurse
    const new_car = try instantiateTemplate(gc, types.car(template), bindings, intro_scope, literals, macro_keyword, globals, macros);
    // Root new_car to protect from GC during cdr instantiation
    var car_root = new_car;
    gc.pushRoot(&car_root);
    defer gc.popRoot();
    const new_cdr = try instantiateTemplate(gc, types.cdr(template), bindings, intro_scope, literals, macro_keyword, globals, macros);
    return gc.allocPair(car_root, new_cdr);
}

fn instantiateEllipsis(gc: *GC, elem_template: Value, rest_template: Value, bindings: []Binding, intro_scope: u32, literals: []const Value, macro_keyword: ?[]const u8, globals: ?*std.StringHashMap(Value), macros: ?*const std.StringHashMap(Value)) (std.mem.Allocator.Error || ExpandError)!Value {
    // Find the ellipsis-bound variable to determine repetition count
    var repeat_count: usize = 0;
    for (bindings) |b| {
        if (b.is_list) {
            repeat_count = b.ellipsis_count;
            break;
        }
    }

    // First instantiate the rest (after the ellipsis)
    const result = try instantiateTemplate(gc, rest_template, bindings, intro_scope, literals, macro_keyword, globals, macros);
    var result_root = result;
    gc.pushRoot(&result_root);
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
                sub_bindings[sub_count] = .{
                    .name = b.name,
                    .value = b.ellipsis_values[i],
                    .depth = 0,
                    .is_list = false,
                };
            } else {
                sub_bindings[sub_count] = b;
            }
            sub_count += 1;
        }
        const expanded = try instantiateTemplate(gc, elem_template, sub_bindings[0..sub_count], intro_scope, literals, macro_keyword, globals, macros);
        var expanded_root = expanded;
        gc.pushRoot(&expanded_root);
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
fn renameForHygiene(gc: *GC, name: []const u8, scope: u32, globals: ?*std.StringHashMap(Value)) !Value {
    // Check if we already renamed this (name, scope) pair
    for (scope_table[0..scope_table_count]) |entry| {
        if (entry.scope == scope and std.mem.eql(u8, entry.original_name, name)) {
            return gc.allocSymbol(entry.renamed_to);
        }
    }

    // Generate a fresh hygienic name
    gensym_counter += 1;
    var buf: [128]u8 = undefined;
    const len = std.fmt.bufPrint(&buf, "__hyg_{d}_{s}", .{ gensym_counter, name }) catch
        return gc.allocSymbol(name);

    // We need to persist the renamed string because scope_table entries
    // reference it and allocSymbol interns a copy. The interned copy in
    // the GC symbol table will outlive scope_table, so we can point at
    // the slice from the allocated symbol.
    const sym_val = try gc.allocSymbol(len);
    const renamed_persistent = types.symbolName(sym_val);

    // Record the renaming so subsequent occurrences of the same name
    // in this invocation map to the same gensym.
    if (scope_table_count < MAX_SCOPE_ENTRIES) {
        scope_table[scope_table_count] = .{
            .original_name = name,
            .scope = scope,
            .renamed_to = renamed_persistent,
        };
        scope_table_count += 1;
    }

    // Referential transparency: if the original name refers to an existing
    // global, alias the gensym to the same value. This way the renamed
    // identifier still resolves to the definition-site global rather than
    // being captured by a user local binding of the original name.
    if (globals) |g| {
        if (g.get(name)) |global_val| {
            g.put(renamed_persistent, global_val) catch {};
        }
    }

    return sym_val;
}
