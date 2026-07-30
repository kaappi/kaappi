//! syntax-rules template instantiation and hygiene renaming, split out of
//! expander.zig (file size policy). expander.zig keeps macro-use entry points
//! (expandMacro/expandProceduralMacro), pattern matching, and the usertext /
//! hygiene-strip walks; this file owns the template side: instantiateTemplate
//! and its ellipsis machinery, plus renameForHygiene and the scope-table
//! rename minting it drives. The two files share the expander's threadlocal
//! per-expansion context (scope_table, active_*), always referenced through
//! `expander.` here so there is exactly one copy of that state.

const std = @import("std");
const types = @import("types.zig");
const memory = @import("memory.zig");
const Value = types.Value;
const GC = memory.GC;

const expander = @import("expander.zig");
const ExpandError = expander.ExpandError;
const Binding = expander.Binding;
const MAX_BINDINGS = expander.MAX_BINDINGS;
const MAX_ELLIPSIS_VALUES = expander.MAX_ELLIPSIS_VALUES;
const MAX_SCOPE_ENTRIES = expander.MAX_SCOPE_ENTRIES;
const USERTEXT_MARKER = expander.USERTEXT_MARKER;
const isUsertextPair = expander.isUsertextPair;
const unwrapUsertext = expander.unwrapUsertext;
const isEllipsis = expander.isEllipsis;
const isWellKnown = expander.isWellKnown;
const vectorToList = expander.vectorToList;
const listToVector = expander.listToVector;
const freshGensymId = expander.freshGensymId;

// ---------------------------------------------------------------------------
// Template instantiation
// ---------------------------------------------------------------------------

// Context flags carried in the high bits of intro_scope. Scope ids come from
// a small monotonically increasing counter, so the top bits are free.
// renameForHygiene must mask off every flag that doesn't change renaming
// behavior so scope-table entries stay consistent across contexts.
const ESCAPE_FLAG: u32 = 0x80000000; // inside (... <template>) ellipsis escape
const QUOTE_FLAG: u32 = 0x40000000; // inside (quote ...): substitute, hygiene-rename (#1801)
const BINDING_FLAG: u32 = 0x20000000; // identifier is in binding position
const NESTED_SR_FLAG: u32 = 0x10000000; // inside a nested syntax-rules template
const LET_PAIR_FLAG: u32 = 0x08000000; // template is a single let-binding (var init) pair
// Re-walking a usertext-marker-protected splice (an enclosing expansion's
// pattern-var value, spliced verbatim into a nested syntax-rules template) in
// substitute-only mode. Reuses QUOTE_FLAG's "substitute, expand ellipses"
// walk shape, but MUST suppress renameForHygiene's QUOTE_FLAG rename (#1801):
// unlike a literal identifier written directly in a quote form, this
// identifier is use-site DATA from an enclosing expansion, never a
// template-introduced identifier of the CURRENT one, so it must always pass
// through unrenamed -- exactly the pre-#1801 QUOTE_FLAG behavior.
const VERBATIM_FLAG: u32 = 0x00800000;
// Quasiquote nesting depth (0-7, saturating). Symbols under `quasiquote` are
// DATA — they must not be hygiene-renamed — but a depth-matching `unquote`
// re-enters expression territory where renaming resumes. Three bits cover any
// realistic template nesting; like the flag bits above, they assume expansion
// scope ids stay below the flag region.
const QQ_DEPTH_MASK: u32 = 0x07000000;
const QQ_DEPTH_ONE: u32 = 0x01000000;

/// Whether an ellipsis element template references any outer list binding —
/// the condition under which instantiateEllipsis can find a repeat count.
/// Inside a nested syntax-rules template, an ellipsis whose element
/// references none belongs to the inner macro and must be preserved.
fn ellipsisReferencesOuter(elem: Value, bindings: []Binding) bool {
    for (bindings) |b| {
        if (b.is_list and templateReferencesVar(elem, b.name)) {
            if (templateReferencesVarDirectly(elem, b.name) or b.depth > 1) return true;
        }
    }
    return false;
}

pub fn instantiateTemplate(gc: *GC, template: Value, bindings: []Binding, intro_scope: u32, literals: []const Value, macro_keyword: ?[]const u8, globals: ?*std.StringHashMap(Value), macros: ?*const std.StringHashMap(Value)) (std.mem.Allocator.Error || ExpandError)!Value {
    if (types.isSymbol(template)) {
        const name = types.symbolName(template);

        // 1. Pattern variable -- substitute with matched value (from use site)
        for (bindings) |b| {
            if (std.mem.eql(u8, b.name, name)) {
                // Inside a nested syntax-rules template (and outside quote),
                // mark the spliced value so the generated macro's own
                // expansion later inserts it verbatim instead of re-walking
                // it as template text (see USERTEXT_MARKER).
                if ((intro_scope & NESTED_SR_FLAG) != 0 and
                    (intro_scope & QUOTE_FLAG) == 0 and
                    (types.isSymbol(b.value) or types.isPair(b.value)))
                {
                    if (isUsertextPair(b.value)) return b.value; // already protected
                    var val_root = b.value;
                    gc.pushRoot(&val_root);
                    defer gc.popRoot();
                    const marker = try gc.allocSymbol(USERTEXT_MARKER);
                    return gc.allocPair(marker, val_root);
                }
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

    // A user-text splice from an enclosing expansion. The chunk is use-site
    // text, so hygiene renaming must not touch it — but it may reference
    // THIS macro's pattern variables (define-match-pattern builds the
    // generated macro's rules out of user text), so substitution and
    // ellipsis expansion still apply. That combination is exactly the
    // quote-mode walk: substitute, expand ellipses, rename nothing. The
    // wrapper is PRESERVED: the chunk may land inside yet another generated
    // syntax-rules spec (SRFI 257's accumulator rebinds) and must stay
    // protected for that next generation too. Markers are stripped once,
    // at the compile boundary (stripUsertextMarkers).
    if (isUsertextPair(template)) {
        const inner = unwrapUsertext(template);
        // A forged cyclic marker chain unwraps to itself: treat as opaque data.
        if (isUsertextPair(inner)) return inner;
        // A marker-protected chunk that is ITSELF, directly, a `(quote X)`
        // form (e.g. em-gensym's own `'g` template text, captured wholesale
        // as em-syntax-rules's own `template` pattern-var value and spliced,
        // marker-protected, into the generated macro's stored transformer)
        // is not opaque use-site data -- it's the ORIGINAL macro author's own
        // literal template text, merely routed through em-syntax-rules's
        // multi-step desugaring plumbing. Such an identifier must still get
        // a fresh hygiene rename per invocation (#1801), so this case is
        // excluded from VERBATIM_FLAG and falls through to the normal quote
        // handling below. A chunk that merely CONTAINS a quote/quasiquote
        // somewhere within a larger structure -- e.g. `(em `(let ((e ...))
        // ...))`, where the let-bound `e` must stay verbatim to match a
        // reference threaded through a completely separate expansion event
        // (SRFI 148's own CK-machine, which compiles sub-pieces at different
        // times) -- or a bare symbol (an ordinary pattern-var's actual
        // use-site value, e.g. SRFI 257's accumulator rebinds) keeps the
        // original, always-verbatim treatment: only the EXACT `(quote
        // <datum>)` shape at the very top of the protected chunk counts,
        // never one merely nested deeper inside.
        const is_direct_quote = types.isPair(inner) and
            types.isSymbol(types.car(inner)) and
            std.mem.eql(u8, types.symbolName(types.car(inner)), "quote") and
            types.isPair(types.cdr(inner)) and
            types.cdr(types.cdr(inner)) == types.NIL;
        const verbatim_bits: u32 = if (is_direct_quote) 0 else VERBATIM_FLAG;
        const new_inner = try instantiateTemplate(gc, inner, bindings, (intro_scope | QUOTE_FLAG | verbatim_bits) & ~NESTED_SR_FLAG, literals, macro_keyword, globals, macros);
        if (isUsertextPair(new_inner)) return new_inner; // already protected
        if (!types.isSymbol(new_inner) and !types.isPair(new_inner)) return new_inner;
        var inner_root = new_inner;
        gc.pushRoot(&inner_root);
        defer gc.popRoot();
        const marker = try gc.allocSymbol(USERTEXT_MARKER);
        return gc.allocPair(marker, inner_root);
    }

    const in_escape = (intro_scope & ESCAPE_FLAG) != 0;

    // Check for (quote <datum>) — substitute pattern vars but skip hygiene
    // renaming. Must be a genuine, exactly-2-element quote form (R7RS quote
    // is strictly unary): a template sub-list that merely STARTS with the
    // symbol `quote` for an unrelated reason (e.g. passing the bare symbol
    // `quote` as one argument among several to some other macro/procedure)
    // is not a quote form at all, and treating it as one silently discarded
    // every element after the second (e.g. `(op quote free-identifier=?
    // more...)` instantiated as `(op (quote free-identifier=?))`, dropping
    // `more...`).
    const tmpl_head = types.car(template);
    if (types.isSymbol(tmpl_head) and std.mem.eql(u8, types.symbolName(tmpl_head), "quote")) {
        const q_rest = types.cdr(template);
        if (q_rest != types.NIL and types.isPair(q_rest)) {
            if (types.cdr(q_rest) == types.NIL) {
                const quoted = types.car(q_rest);
                const new_quoted = try instantiateTemplate(gc, quoted, bindings, intro_scope | QUOTE_FLAG, literals, macro_keyword, globals, macros);
                var nq_root = new_quoted;
                gc.pushRoot(&nq_root);
                defer gc.popRoot();
                const tail = try gc.allocPair(nq_root, types.NIL);
                return gc.allocPair(tmpl_head, tail);
            }
            // More than 2 elements: `quote` is not forming a quote special
            // form here, just an ordinary (possibly data) value in head
            // position -- fall through to regular pair processing so the
            // rest of the list survives instead of being silently dropped.
        } else {
            return template;
        }
    }

    // Quasiquote: its symbols are data (no renaming, like quote), but a
    // depth-matching unquote/unquote-splicing switches back to expression
    // mode where renaming resumes. Track nesting in QQ_DEPTH bits. Inside a
    // plain (quote ...) context (QUOTE_FLAG set, depth 0), quasiquote and
    // unquote are ordinary data — leave them to the regular walk.
    if (types.isSymbol(tmpl_head)) {
        const hname = types.symbolName(tmpl_head);
        const qq_depth = (intro_scope & QQ_DEPTH_MASK) / QQ_DEPTH_ONE;
        const q_rest = types.cdr(template);
        const unary = q_rest != types.NIL and types.isPair(q_rest) and types.cdr(q_rest) == types.NIL;
        if (unary and std.mem.eql(u8, hname, "quasiquote")) {
            const in_plain_quote = (intro_scope & QUOTE_FLAG) != 0 and qq_depth == 0;
            if (!in_plain_quote) {
                const new_depth = if (qq_depth < 7) qq_depth + 1 else 7;
                const sub_scope = (intro_scope & ~QQ_DEPTH_MASK) | QUOTE_FLAG | (new_depth * QQ_DEPTH_ONE);
                const new_inner = try instantiateTemplate(gc, types.car(q_rest), bindings, sub_scope, literals, macro_keyword, globals, macros);
                var ni_root = new_inner;
                gc.pushRoot(&ni_root);
                defer gc.popRoot();
                const tail = try gc.allocPair(ni_root, types.NIL);
                return gc.allocPair(tmpl_head, tail);
            }
        } else if (unary and qq_depth > 0 and
            (std.mem.eql(u8, hname, "unquote") or std.mem.eql(u8, hname, "unquote-splicing")))
        {
            const new_depth = qq_depth - 1;
            var sub_scope = (intro_scope & ~QQ_DEPTH_MASK) | (new_depth * QQ_DEPTH_ONE);
            if (new_depth == 0) sub_scope &= ~QUOTE_FLAG;
            const new_inner = try instantiateTemplate(gc, types.car(q_rest), bindings, sub_scope, literals, macro_keyword, globals, macros);
            var ni_root = new_inner;
            gc.pushRoot(&ni_root);
            defer gc.popRoot();
            const tail = try gc.allocPair(ni_root, types.NIL);
            return gc.allocPair(tmpl_head, tail);
        }
    }

    // Check for ellipsis escape: (... <template>) — treat ... as literal inside
    //
    // Both ellipsis checks below unwrap a usertext marker first: a nested
    // syntax-rules template's ordinary (non-quoted) position can receive a
    // custom ellipsis identifier substituted from an OUTER pattern variable
    // (SRFI 147/148's generating-macro pattern), which NESTED_SR_FLAG's
    // marking protocol wraps so the generating macro's own later expansion
    // doesn't re-walk it as template text. Only a quoted position skips the
    // wrap (QUOTE_FLAG suppresses it, see the pattern-variable substitution
    // case above) -- an ordinary template position needs the unwrap to even
    // recognize the ellipsis at all; without it, `(x my-ellipsis)` never
    // matches "element followed by ellipsis" and my-ellipsis is emitted
    // literally (as an unresolvable wrapped pair) instead of splicing x's
    // repetitions.
    const elem = types.car(template);
    const rest = types.cdr(template);
    const elem_unwrapped = unwrapUsertext(elem);
    if (!in_escape and types.isSymbol(elem_unwrapped) and isEllipsis(types.symbolName(elem_unwrapped))) {
        if (rest != types.NIL and types.isPair(rest) and types.cdr(rest) == types.NIL) {
            const inner = types.car(rest);
            return instantiateTemplate(gc, inner, bindings, intro_scope | ESCAPE_FLAG, literals, macro_keyword, globals, macros);
        }
        return template;
    }

    // Check for ellipsis in template: (Te ...) — skip inside escape context
    if (!in_escape and rest != types.NIL and types.isPair(rest)) {
        const maybe_ellipsis = unwrapUsertext(types.car(rest));
        if (types.isSymbol(maybe_ellipsis) and isEllipsis(types.symbolName(maybe_ellipsis))) {
            // Inside a nested syntax-rules template, an ellipsis whose
            // element references no outer list binding belongs to the inner
            // macro: keep the element (with outer scalar substitution and
            // hygiene applied) and the ellipsis token(s) literally instead
            // of expanding to zero repetitions.
            if ((intro_scope & NESTED_SR_FLAG) != 0 and !ellipsisReferencesOuter(elem, bindings)) {
                const new_elem = try instantiateTemplate(gc, elem, bindings, intro_scope, literals, macro_keyword, globals, macros);
                var elem_root = new_elem;
                gc.pushRoot(&elem_root);
                defer gc.popRoot();
                // Collect the run of consecutive ellipsis tokens
                var tokens: Value = types.NIL;
                gc.pushRoot(&tokens);
                defer gc.popRoot();
                var cur = rest;
                while (types.isPair(cur)) {
                    const tok = types.car(cur);
                    if (types.isSymbol(tok) and isEllipsis(types.symbolName(tok))) {
                        tokens = try gc.allocPair(tok, tokens);
                        cur = types.cdr(cur);
                    } else break;
                }
                const new_tail = try instantiateTemplate(gc, cur, bindings, intro_scope, literals, macro_keyword, globals, macros);
                var result = new_tail;
                gc.pushRoot(&result);
                defer gc.popRoot();
                while (types.isPair(tokens)) {
                    result = try gc.allocPair(types.car(tokens), result);
                    tokens = types.cdr(tokens);
                }
                return gc.allocPair(elem_root, result);
            }
            // Replicate elem for each ellipsis binding
            const after = types.cdr(rest);
            return instantiateEllipsis(gc, elem, after, bindings, intro_scope, literals, macro_keyword, globals, macros);
        }
    }

    // A single (var init) let-binding pair delegated from an ellipsis
    // repetition (instantiateLetBindings): the var is in binding position,
    // the init is not. Without this, repeated template-introduced binders
    // skip the binding-position rename and capture use-site references.
    if ((intro_scope & LET_PAIR_FLAG) != 0) {
        const base = intro_scope & ~LET_PAIR_FLAG;
        const new_var = try instantiateTemplate(gc, elem, bindings, base | BINDING_FLAG, literals, macro_keyword, globals, macros);
        var var_root = new_var;
        gc.pushRoot(&var_root);
        defer gc.popRoot();
        const new_init = try instantiateTemplate(gc, rest, bindings, base & ~BINDING_FLAG, literals, macro_keyword, globals, macros);
        return gc.allocPair(var_root, new_init);
    }

    // Nested syntax-rules: outer pattern variables substitute into its
    // patterns, literals, and templates (R7RS template semantics), but its
    // own ellipses must be preserved — set the context flag for the subtree.
    if (types.isSymbol(elem) and std.mem.eql(u8, types.symbolName(elem), "syntax-rules")) {
        const nested_scope = (intro_scope | NESTED_SR_FLAG) & ~BINDING_FLAG;
        var car_root = elem;
        gc.pushRoot(&car_root);
        defer gc.popRoot();
        const new_cdr = try instantiateTemplate(gc, rest, bindings, nested_scope, literals, macro_keyword, globals, macros);
        return gc.allocPair(car_root, new_cdr);
    }

    // Detect binding forms and set binding-position flag for variable names
    if (types.isSymbol(elem)) {
        const form_name = types.symbolName(elem);
        const is_let_form = std.mem.eql(u8, form_name, "let") or
            std.mem.eql(u8, form_name, "let*") or
            std.mem.eql(u8, form_name, "letrec") or
            std.mem.eql(u8, form_name, "letrec*");
        if (is_let_form) {
            const new_car = try instantiateTemplate(gc, elem, bindings, intro_scope, literals, macro_keyword, globals, macros);
            var car_root = new_car;
            gc.pushRoot(&car_root);
            defer gc.popRoot();
            const let_rest = types.cdr(template);
            if (let_rest != types.NIL and types.isPair(let_rest)) {
                const binding_list = types.car(let_rest);
                const body = types.cdr(let_rest);
                const new_bindings = try instantiateLetBindings(gc, binding_list, bindings, intro_scope | BINDING_FLAG, literals, macro_keyword, globals, macros);
                var bindings_root = new_bindings;
                gc.pushRoot(&bindings_root);
                defer gc.popRoot();
                const new_body = try instantiateTemplate(gc, body, bindings, intro_scope & ~BINDING_FLAG, literals, macro_keyword, globals, macros);
                var body_root = new_body;
                gc.pushRoot(&body_root);
                defer gc.popRoot();
                const inner = try gc.allocPair(bindings_root, body_root);
                return gc.allocPair(car_root, inner);
            }
        }
    }

    // Regular pair: recurse
    const new_car = try instantiateTemplate(gc, types.car(template), bindings, intro_scope & ~BINDING_FLAG, literals, macro_keyword, globals, macros);
    var car_root = new_car;
    gc.pushRoot(&car_root);
    defer gc.popRoot();
    const new_cdr = try instantiateTemplate(gc, types.cdr(template), bindings, intro_scope & ~BINDING_FLAG, literals, macro_keyword, globals, macros);
    return gc.allocPair(car_root, new_cdr);
}

fn instantiateLetBindings(gc: *GC, binding_list: Value, bindings: []Binding, scope: u32, literals: []const Value, macro_keyword: ?[]const u8, globals: ?*std.StringHashMap(Value), macros: ?*const std.StringHashMap(Value)) !Value {
    if (binding_list == types.NIL) return types.NIL;
    if (!types.isPair(binding_list)) return instantiateTemplate(gc, binding_list, bindings, scope, literals, macro_keyword, globals, macros);
    const pair = types.car(binding_list);
    // Ellipsis after a binding element: ((var init) ...) — expand the
    // repetitions via the regular ellipsis machinery, then continue
    // let-binding processing on whatever follows the ellipsis token(s).
    // Consecutive extra ellipses (((var init) ... ...), R7RS 4.3.2
    // flattening) are collected into a synthetic rest-template so
    // instantiateEllipsis applies its existing flattening logic.
    const after = types.cdr(binding_list);
    if (types.isPair(after)) {
        const nxt = types.car(after);
        if (types.isSymbol(nxt) and isEllipsis(types.symbolName(nxt))) {
            var synth_rest: Value = types.NIL;
            gc.pushRoot(&synth_rest);
            defer gc.popRoot();
            var rest_after = types.cdr(after);
            while (types.isPair(rest_after)) {
                const tok = types.car(rest_after);
                if (types.isSymbol(tok) and isEllipsis(types.symbolName(tok))) {
                    synth_rest = try gc.allocPair(tok, synth_rest);
                    rest_after = types.cdr(rest_after);
                } else break;
            }
            // Inside a nested syntax-rules template with no outer list
            // binding referenced, the ellipsis belongs to the inner macro:
            // keep the pair and the ellipsis token(s) literally.
            if ((scope & NESTED_SR_FLAG) != 0 and !ellipsisReferencesOuter(pair, bindings)) {
                const new_pair = try instantiateTemplate(gc, pair, bindings, scope & ~BINDING_FLAG, literals, macro_keyword, globals, macros);
                var pair_root = new_pair;
                gc.pushRoot(&pair_root);
                defer gc.popRoot();
                const tail = try instantiateLetBindings(gc, rest_after, bindings, scope, literals, macro_keyword, globals, macros);
                var result = tail;
                gc.pushRoot(&result);
                defer gc.popRoot();
                result = try gc.allocPair(nxt, result);
                while (types.isPair(synth_rest)) {
                    result = try gc.allocPair(types.car(synth_rest), result);
                    synth_rest = types.cdr(synth_rest);
                }
                return gc.allocPair(pair_root, result);
            }
            const segment = try instantiateEllipsis(gc, pair, synth_rest, bindings, (scope & ~BINDING_FLAG) | LET_PAIR_FLAG, literals, macro_keyword, globals, macros);
            var seg_root = segment;
            gc.pushRoot(&seg_root);
            defer gc.popRoot();
            const tail = try instantiateLetBindings(gc, rest_after, bindings, scope, literals, macro_keyword, globals, macros);
            if (seg_root == types.NIL) return tail;
            var last = seg_root;
            while (types.isPair(types.cdr(last))) last = types.cdr(last);
            gc.writeBarrier(types.toObject(last), tail);
            types.setCdr(last, tail);
            return seg_root;
        }
    }
    if (!types.isPair(pair)) {
        const new_pair = try instantiateTemplate(gc, pair, bindings, scope, literals, macro_keyword, globals, macros);
        var pair_root = new_pair;
        gc.pushRoot(&pair_root);
        defer gc.popRoot();
        const new_rest = try instantiateLetBindings(gc, types.cdr(binding_list), bindings, scope, literals, macro_keyword, globals, macros);
        return gc.allocPair(pair_root, new_rest);
    }
    const var_name = types.car(pair);
    const init_and_rest = types.cdr(pair);
    const new_var = try instantiateTemplate(gc, var_name, bindings, scope, literals, macro_keyword, globals, macros);
    var var_root = new_var;
    gc.pushRoot(&var_root);
    defer gc.popRoot();
    const new_init = try instantiateTemplate(gc, init_and_rest, bindings, scope & ~BINDING_FLAG, literals, macro_keyword, globals, macros);
    var init_root = new_init;
    gc.pushRoot(&init_root);
    defer gc.popRoot();
    const new_pair = try gc.allocPair(var_root, init_root);
    var np_root = new_pair;
    gc.pushRoot(&np_root);
    defer gc.popRoot();
    const new_rest = try instantiateLetBindings(gc, types.cdr(binding_list), bindings, scope, literals, macro_keyword, globals, macros);
    return gc.allocPair(np_root, new_rest);
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

/// Like templateReferencesVar, but skips sub-expressions consumed by a
/// nested inner ellipsis — i.e. elements immediately followed by `...`.
/// A binding found only inside such a sub-expression is "indirectly"
/// referenced and should not drive the outer ellipsis's repeat count.
fn templateReferencesVarDirectly(template: Value, name: []const u8) bool {
    if (types.isSymbol(template)) {
        return std.mem.eql(u8, types.symbolName(template), name);
    }
    if (types.isPair(template)) {
        const head = types.car(template);
        const tail = types.cdr(template);
        if (types.isPair(tail)) {
            const next = types.car(tail);
            if (types.isSymbol(next) and isEllipsis(types.symbolName(next))) {
                var rest = types.cdr(tail);
                while (types.isPair(rest)) {
                    const r = types.car(rest);
                    if (types.isSymbol(r) and isEllipsis(types.symbolName(r))) {
                        rest = types.cdr(rest);
                    } else break;
                }
                return templateReferencesVarDirectly(rest, name);
            }
        }
        return templateReferencesVarDirectly(head, name) or
            templateReferencesVarDirectly(tail, name);
    }
    return false;
}

/// Checks whether a candidate variable and any Pass-1 driver variable both
/// appear inside the SAME inner `(elem ...)` sub-template.  When they do,
/// the candidate shares a pattern group with the driver and should be
/// consumed per-iteration (SRFI 149's excess-ellipsis replication).  When
/// they don't — the candidate's only inner `(x ...)` contains no driver —
/// the candidate is from an independent group and should be passed through
/// wholesale (issue #1721).
fn sharesInnerEllipsisWithDriver(template: Value, candidate_name: []const u8, bindings: []const Binding, referenced: *const [MAX_BINDINGS]bool) bool {
    if (!types.isPair(template)) return false;

    const head = types.car(template);
    const tail = types.cdr(template);

    if (types.isPair(tail)) {
        const next = types.car(tail);
        if (types.isSymbol(next) and isEllipsis(types.symbolName(next))) {
            // `head` is consumed by an inner ellipsis.  Check whether it
            // references both the candidate and any Pass-1 driver.
            if (templateReferencesVar(head, candidate_name)) {
                for (bindings, 0..) |b, bi| {
                    if (referenced[bi] and templateReferencesVar(head, b.name)) {
                        return true;
                    }
                }
            }
            // Skip past consecutive ellipses and check the rest of the list.
            var rest = types.cdr(tail);
            while (types.isPair(rest)) {
                const r = types.car(rest);
                if (types.isSymbol(r) and isEllipsis(types.symbolName(r))) {
                    rest = types.cdr(rest);
                } else break;
            }
            return sharesInnerEllipsisWithDriver(rest, candidate_name, bindings, referenced);
        }
    }

    return sharesInnerEllipsisWithDriver(head, candidate_name, bindings, referenced) or
        sharesInnerEllipsisWithDriver(tail, candidate_name, bindings, referenced);
}

fn instantiateEllipsis(gc: *GC, elem_template: Value, rest_template: Value, bindings: []Binding, intro_scope: u32, literals: []const Value, macro_keyword: ?[]const u8, globals: ?*std.StringHashMap(Value), macros: ?*const std.StringHashMap(Value)) (std.mem.Allocator.Error || ExpandError)!Value {
    // Per-iteration sub-binding scratch, hoisted out of the loop and written
    // field-by-field there: whole-struct assignment re-initializes or copies
    // the 8KB ellipsis_values field each time, which dominated expansion time
    // on macro-heavy code (ellipsis_values is only read when is_list).
    // Declared under a safety-off function scope so ReleaseSafe's 0xAA fill
    // of `= undefined` locals is not emitted; the whole body runs in the
    // safety-on block below (see expandMacro; kaappi#1802).
    @setRuntimeSafety(false);
    var sub_bindings: [MAX_BINDINGS]Binding = undefined;
    {
        @setRuntimeSafety(true);
        // Find the repeat count from ellipsis bindings referenced in elem_template.
        // All referenced list bindings must have equal counts (R7RS). Bindings
        // with depth > 1 (nested ellipses) participate too: their ellipsis_count
        // at this level is the outer repetition count, and each iteration below
        // unpacks them one level for the inner ellipsis to consume.
        var repeat_count: usize = 0;
        var count_set = false;
        var referenced: [MAX_BINDINGS]bool = @splat(false);
        var indirect: [MAX_BINDINGS]bool = @splat(false);

        for (bindings, 0..) |b, bi| {
            if (b.is_list and (templateReferencesVarDirectly(elem_template, b.name) or
                (b.depth > 1 and templateReferencesVar(elem_template, b.name))))
            {
                referenced[bi] = true;
                if (!count_set) {
                    repeat_count = b.ellipsis_count;
                    count_set = true;
                } else if (b.ellipsis_count != repeat_count) {
                    return ExpandError.EllipsisCountMismatch;
                }
            }
        }

        for (bindings, 0..) |b, bi| {
            if (b.is_list and !referenced[bi] and templateReferencesVar(elem_template, b.name)) {
                if (sharesInnerEllipsisWithDriver(elem_template, b.name, bindings, &referenced)) {
                    referenced[bi] = true;
                    if (!count_set) {
                        repeat_count = b.ellipsis_count;
                        count_set = true;
                    } else if (b.ellipsis_count != repeat_count) {
                        return ExpandError.EllipsisCountMismatch;
                    }
                } else {
                    indirect[bi] = true;
                }
            }
        }

        // R7RS 4.3.2 (kaappi#1791): no pattern variable at this ellipsis
        // depth drove the repeat count, so this is not "zero repetitions" —
        // it's a template bug (most often a typo'd bare `...` where the
        // literal-ellipsis escape `(... ...)` was meant, kaappi#1787).
        // Silently producing zero copies here previously let the malformed
        // expansion continue and fail far away with a misleading error.
        //
        // This can never fire for the legitimate "ellipsis belongs to a
        // nested syntax-rules template's own grammar" case: both call sites
        // of this function (instantiateTemplate and instantiateLetBindings)
        // already special-case `NESTED_SR_FLAG and !ellipsisReferencesOuter`
        // *before* calling here, and `ellipsisReferencesOuter` is exactly
        // the same predicate — over the same elem_template/bindings — as
        // the `count_set` computation above. So `!count_set` here implies
        // `ellipsisReferencesOuter` was false, which means the caller could
        // only have reached this call with NESTED_SR_FLAG unset.
        if (!count_set) return ExpandError.EllipsisNoPatternVariable;

        // Consecutive ellipses (R7RS 4.3.2): (x ... ...) flattens depth-2
        // bindings into a single list.  Count and strip leading ellipsis
        // tokens from rest_template so the tail instantiation sees only the
        // non-ellipsis remainder.
        var extra_ellipsis: u32 = 0;
        var true_rest = rest_template;
        while (types.isPair(true_rest)) {
            const head = types.car(true_rest);
            if (types.isSymbol(head) and isEllipsis(types.symbolName(head))) {
                extra_ellipsis += 1;
                true_rest = types.cdr(true_rest);
            } else {
                break;
            }
        }

        // First instantiate the rest (after all consumed ellipses)
        const result = try instantiateTemplate(gc, true_rest, bindings, intro_scope, literals, macro_keyword, globals, macros);
        var result_root = result;
        gc.pushRoot(&result_root);
        defer gc.popRoot();

        // When extra ellipses are present, build the synthetic template
        // (elem_template ... ...) once outside the loop — it is invariant
        // across iterations and instantiateTemplate only reads it.
        var synth = types.NIL;
        if (extra_ellipsis > 0) {
            gc.pushRoot(&synth);
            const ellipsis_name = expander.active_custom_ellipsis orelse "...";
            var ei: u32 = 0;
            while (ei < extra_ellipsis) : (ei += 1) {
                const dots = try gc.allocSymbol(ellipsis_name);
                synth = try gc.allocPair(dots, synth);
            }
            synth = try gc.allocPair(elem_template, synth);
        }
        defer if (extra_ellipsis > 0) gc.popRoot();

        // Generate copies in reverse so we build the list from right to left.
        var i = repeat_count;
        while (i > 0) {
            i -= 1;
            // Create sub-bindings with the i-th value for each referenced list
            // binding. Unreferenced list bindings are skipped: their
            // ellipsis_count can be smaller than repeat_count (e.g. two
            // ellipsis groups of different lengths in one template), so
            // indexing ellipsis_values[i] would read uninitialized data.
            var sub_count: usize = 0;
            for (bindings, 0..) |b, bi| {
                if (b.is_list) {
                    if (!referenced[bi] and !indirect[bi]) continue;
                    if (indirect[bi]) {
                        sub_bindings[sub_count].name = b.name;
                        sub_bindings[sub_count].value = types.NIL;
                        sub_bindings[sub_count].depth = b.depth;
                        sub_bindings[sub_count].is_list = true;
                        sub_bindings[sub_count].ellipsis_count = b.ellipsis_count;
                        var ec: usize = 0;
                        while (ec < b.ellipsis_count and ec < MAX_ELLIPSIS_VALUES) : (ec += 1) {
                            sub_bindings[sub_count].ellipsis_values[ec] = b.ellipsis_values[ec];
                        }
                        sub_count += 1;
                        continue;
                    }
                    if (b.depth > 1) {
                        // Nested ellipsis: unpack list into sub-binding
                        sub_bindings[sub_count].name = b.name;
                        sub_bindings[sub_count].value = types.NIL;
                        sub_bindings[sub_count].depth = b.depth - 1;
                        sub_bindings[sub_count].is_list = true;
                        var list_val = b.ellipsis_values[i];
                        var ev_count: usize = 0;
                        while (types.isPair(list_val) and ev_count < MAX_ELLIPSIS_VALUES) {
                            sub_bindings[sub_count].ellipsis_values[ev_count] = types.car(list_val);
                            ev_count += 1;
                            list_val = types.cdr(list_val);
                        }
                        sub_bindings[sub_count].ellipsis_count = ev_count;
                    } else {
                        sub_bindings[sub_count].name = b.name;
                        sub_bindings[sub_count].value = b.ellipsis_values[i];
                        sub_bindings[sub_count].depth = 0;
                        sub_bindings[sub_count].is_list = false;
                        sub_bindings[sub_count].ellipsis_count = 0;
                    }
                } else {
                    sub_bindings[sub_count].name = b.name;
                    sub_bindings[sub_count].value = b.value;
                    sub_bindings[sub_count].depth = b.depth;
                    sub_bindings[sub_count].is_list = false;
                    sub_bindings[sub_count].ellipsis_count = 0;
                }
                sub_count += 1;
            }

            if (extra_ellipsis == 0) {
                const expanded = try instantiateTemplate(gc, elem_template, sub_bindings[0..sub_count], intro_scope, literals, macro_keyword, globals, macros);
                var expanded_root = expanded;
                gc.pushRoot(&expanded_root);
                result_root = try gc.allocPair(expanded_root, result_root);
                gc.popRoot();
            } else {
                const expanded_list = try instantiateTemplate(gc, synth, sub_bindings[0..sub_count], intro_scope, literals, macro_keyword, globals, macros);

                // Splice expanded_list (a proper list) into result_root.
                if (expanded_list != types.NIL and types.isPair(expanded_list)) {
                    var tail = expanded_list;
                    while (types.isPair(types.cdr(tail))) {
                        tail = types.cdr(tail);
                    }
                    gc.writeBarrier(types.toObject(tail), result_root);
                    types.setCdr(tail, result_root);
                    result_root = expanded_list;
                }
            }
        }

        return result_root;
    }
}

// ---------------------------------------------------------------------------
// Hygienic renaming
// ---------------------------------------------------------------------------

fn scopeTableContains(scope: u32, name: []const u8) bool {
    for (expander.scope_table[0..expander.scope_table_count]) |entry| {
        if (entry.scope == scope and std.mem.eql(u8, entry.original_name, name)) return true;
    }
    return false;
}

/// Rename a template-introduced identifier for hygiene. Within a single
/// macro invocation (identified by `scope`), the same original name always
/// maps to the same gensym, ensuring internal references stay consistent
/// while avoiding capture of user bindings.
pub fn renameForHygiene(gc: *GC, name: []const u8, scope: u32, globals: ?*std.StringHashMap(Value)) !Value {
    // Already renamed by an enclosing expansion: macro-generating macros
    // bake __hyg_ names into the inner macro's stored template. Gensyms are
    // globally unique, so renaming again cannot prevent any capture — it
    // only severs the reference from the binding created by the generating
    // expansion (issue #919: __hyg_N___hyg_M_march-hare undefined). The same
    // holds for the named-let loop gensym (__nlet_N_name): named-let desugars
    // during compilation, interleaved with macro expansion, so its loop name
    // can flow back through a macro whose template re-emits it (e.g. SRFI 257's
    // ~etc, where the recursive (loop ...) call rides inside a submatch
    // argument). Re-renaming it splits the reference from the letrec binding.
    // Checked before the quote branch below too, so a quoted occurrence of an
    // already-renamed name is passed through rather than re-minted.
    //
    // The same holds for a def_env_binding_prefix-marked name (#1812): a
    // macro template can itself contain ANOTHER macro's whole definition
    // (e.g. SRFI 41's stream-match, a syntax-rules template whose body is a
    // letrec-syntax defining smp/smt) — the outer expansion walks and
    // hygiene-renames every free identifier in that nested spec too,
    // including ones already marked with this prefix by THIS transformer's
    // own expander.active_def_env check below. If the nested macro (smp/smt) is
    // itself top-level/REPL-scoped (its own def_env is null, as here — it's
    // defined via letrec-syntax at the *use* site, not within any library),
    // its own later expansion would otherwise see the prefixed name as a
    // fresh, unrecognized identifier and re-wrap it with a __hyg_ gensym,
    // severing it from anything vm_dispatch's prefix parser can resolve.
    if (std.mem.startsWith(u8, name, "__hyg_") or std.mem.startsWith(u8, name, "__nlet_") or
        std.mem.startsWith(u8, name, types.def_env_binding_prefix))
        return gc.allocSymbol(name);

    // A usertext-marker splice being re-walked in substitute-only mode: this
    // name is use-site data from an ENCLOSING expansion, not a template-
    // introduced identifier of this one, so it must never be renamed --
    // regardless of QUOTE_FLAG, which is also set here purely to get the
    // rest of the quote-mode walk (substitute, expand ellipses). See
    // VERBATIM_FLAG's own comment.
    if ((scope & VERBATIM_FLAG) != 0) return gc.allocSymbol(name);

    if ((scope & QUOTE_FLAG) != 0) {
        // A template-introduced identifier inside `(quote ...)` is still an
        // IDENTIFIER at the macro-expansion level, not yet inert data: two
        // separate expansions of e.g. `(define-syntax gensym (syntax-rules ()
        // ((gensym) 'g)))` must stay distinguishable via
        // bound-identifier=?/free-identifier=?-style comparisons built out of
        // further macro expansion (nested define-syntax/literal matching),
        // even though `g` will eventually print/compare as the plain symbol
        // `g` once actually compiled into a literal runtime value (#1801).
        // So a quoted, template-introduced identifier is hygiene-renamed
        // exactly like a non-quoted one -- deduped within THIS expansion via
        // the same clean_scope lookup (needed so a nested syntax-rules
        // template's quoted reference to its OWN pattern variable `y` in
        // `((_ y) '(fixed y))` picks up the SAME rename the pattern side
        // already claimed) -- and the compiler strips the `__hyg_` prefix
        // back off wherever it compiles a REAL `(quote ...)` datum to a
        // literal Value (stripHygieneFromDatum, called from quote and
        // quasiquote compilation), so ordinary uses of `'sym` in a template
        // still behave exactly as before once the code actually runs: two
        // unrelated macro expansions that both quote the same literal tag
        // still produce `eq?` symbols.
        const clean_scope = scope & ~(BINDING_FLAG | NESTED_SR_FLAG | LET_PAIR_FLAG | QQ_DEPTH_MASK | QUOTE_FLAG);
        for (expander.scope_table[0..expander.scope_table_count]) |entry| {
            if (entry.scope == clean_scope and std.mem.eql(u8, entry.original_name, name)) {
                return gc.allocSymbol(entry.renamed_to);
            }
        }
        return mintHygienicRename(gc, name, clean_scope);
    }

    const in_binding = (scope & BINDING_FLAG) != 0;
    // Strip context flags that don't change renaming, so the same template
    // identifier gets the same gensym inside and outside those contexts
    // (e.g. an outer binding referenced from a nested syntax-rules template).
    const clean_scope = scope & ~(BINDING_FLAG | NESTED_SR_FLAG | LET_PAIR_FLAG | QQ_DEPTH_MASK);
    const gmod = @import("globals.zig");

    // #1812: a free reference bound in the macro's OWN definition-
    // environment library (def_env — set only for a library-defined
    // transformer, never a top-level/REPL one) must resolve through THAT
    // library's own environment, not whatever the use site's mutable
    // globals table currently holds for the same name — checked before the
    // `globals` block below so it takes priority over a same-named entry
    // that merely happens to also exist in the use site's table (e.g. one
    // copyTransformerFreeRefs planted there at import time). Same
    // shadowing guard as the isProcedure/VOID branches below: a template
    // binding of the same name still wins.
    //
    // Guarded by `expander.active_def_env != globals`: when they're the SAME map,
    // this expansion is compiling within the macro's own defining library,
    // which hasn't necessarily finished loading yet — lookupDefEnvBinding
    // resolves by canonical name through vm.libraries, which only gains an
    // entry once a library's declaration processing completes in full
    // (handleDefineLibrary registers it last). A macro used by a LATER
    // declaration in that same body would resolve fine (loading finished
    // by then), but one used by an EARLIER/self-referential declaration
    // would spuriously raise "undefined variable" (confirmed: this is
    // exactly how SRFI 35's own make-condition-type reference broke while
    // SRFI 35 itself is still loading). The existing get_global/call_global
    // path already resolves this case correctly via func.env pointing
    // straight at the same live lib_env, no registration required, so just
    // fall through to it unchanged.
    //
    // ALSO guarded by "not a true (scheme base) binding" (lookupBaseBinding):
    // a library merely re-exporting/importing a standard procedure like
    // call-with-values, raise-continuable, with-exception-handler, call/cc,
    // or dynamic-wind is not the "genuinely library-internal helper" case
    // #1812 targets, and several compiler spots (compileCallWithValuesTail's
    // is_tail dispatch in compiler.zig, similarly for apply/call/cc/eval)
    // recognize these by exact bare name — confirmed by tracing SRFI 248's
    // guard macro, whose tail-position (call-with-values (lambda () ...) k)
    // silently lost its dedicated tail-call handling once call-with-values
    // was renamed, breaking multiple-value passing to k. Universal, rarely-
    // shadowed builtins aren't worth chasing every such exact-name spot for;
    // leaving them exactly as renameForHygiene already treated them (the
    // isProcedure branch below, unprefixed) sidesteps the whole class.
    if (expander.active_def_env) |denv| {
        if (expander.active_def_lib_name) |libname| {
            if (denv != globals and !in_binding and !scopeTableContains(clean_scope, name) and
                denv.contains(name) and gmod.lookupBaseBinding(name) == null)
            {
                var buf: [512]u8 = undefined;
                return gc.allocSymbol(gmod.buildDefEnvBindingSymbolName(&buf, libname, name));
            }
        }
    }

    if (globals) |g| {
        const glk = gmod.acquireGlobalsRead(g);
        defer gmod.releaseGlobalsRead(glk);
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
    if (gmod.globals_ctx) |gctx| {
        gctx.lockShared();
        const found = gctx.globals.get(name);
        gctx.unlockShared();
        if (found) |val| {
            if (types.isTransformer(val)) return gc.allocSymbol(name);
        }
    }

    // A free template reference to a definition-site LOCAL variable. When the
    // expansion happens in the same function frame, fall through: the rename +
    // captured-locals slot alias resolves it shadow-proof. But when the macro's
    // output lands in a nested lambda (a different frame), no slot alias can
    // reach the outer frame — keep the name so the reference compiles through
    // the regular local/upvalue path. Without this, user code that a macro
    // splices into a nested syntax-rules template (SRFI 257's submatch/
    // if-new-var protocol) loses its free variables to the rename (#1644).
    if (!in_binding and !scopeTableContains(clean_scope, name)) {
        for (expander.active_def_local_refs) |ref| {
            if (std.mem.eql(u8, ref, name)) {
                if (!expander.active_use_check.resolvesInFrame(name)) {
                    return gc.allocSymbol(name);
                }
                break;
            }
        }
    }

    for (expander.scope_table[0..expander.scope_table_count]) |entry| {
        if (entry.scope == clean_scope and std.mem.eql(u8, entry.original_name, name)) {
            return gc.allocSymbol(entry.renamed_to);
        }
    }

    return mintHygienicRename(gc, name, clean_scope);
}

/// Generate a fresh hygienic name for a truly new template-introduced
/// identifier and record it in scope_table (keyed by clean_scope) so later
/// references to the same original name within this expansion, quoted or
/// not, resolve to the same rename. Callers have already checked
/// scope_table for an existing entry.
fn mintHygienicRename(gc: *GC, name: []const u8, clean_scope: u32) !Value {
    const gensym_id = freshGensymId();
    var buf: [128]u8 = undefined;
    const len = std.fmt.bufPrint(&buf, "__hyg_{d}_{s}", .{ gensym_id, name }) catch
        return gc.allocSymbol(name);

    const sym_val = try gc.allocSymbol(len);
    const renamed_persistent = types.symbolName(sym_val);

    if (expander.scope_table_count >= MAX_SCOPE_ENTRIES) return ExpandError.ScopeTableFull;
    expander.scope_table[expander.scope_table_count] = .{
        .original_name = name,
        .scope = clean_scope,
        .renamed_to = renamed_persistent,
    };
    expander.scope_table_count += 1;

    return sym_val;
}
