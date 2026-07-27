// Hygiene/expansion regressions for NESTED syntax-rules generation --
// split out of tests_macros.zig (kept that file under the 1500-line policy)
// as its own natural seam: every test here exercises a macro whose template
// itself generates a fresh, nested syntax-rules transformer (the mechanism
// SRFI 147's custom transformers and SRFI 148's em-syntax-rules both build
// on), as opposed to tests_macros.zig's own more general hygiene tests.
const std = @import("std");
const th = @import("testing_helpers.zig");

test "hygiene: nested syntax-rules pattern variable referenced inside its own quoted template" {
    // The outer macro's template defines an inner macro via a NESTED
    // syntax-rules. The inner macro's own pattern variable `y` is renamed
    // for hygiene where it appears in the PATTERN `(_ y)` (walked without
    // QUOTE_FLAG), but its template `'(fixed y)` wraps `y` in `quote`.
    // renameForHygiene used to treat any quoted identifier as inert literal
    // data and skip renaming it there unconditionally, splitting the
    // pattern and template occurrences of the SAME inner pattern variable:
    // the inner macro's own matcher then had nothing to bind to the
    // template's unrenamed `y`, so it passed through literally instead of
    // substituting the call's actual argument (99).
    try th.expectEvalTrue(
        \\(begin
        \\  (define-syntax outer-qs
        \\    (syntax-rules ()
        \\      ((_)
        \\       (begin
        \\         (define-syntax inner-qs
        \\           (syntax-rules ()
        \\             ((_ y) '(fixed y))))
        \\         (inner-qs 99)))))
        \\  (equal? (outer-qs) '(fixed 99)))
    );
}

test "hygiene: genuinely inert quoted literal in a nested template is still not renamed" {
    // Companion to the test above: a symbol quoted inside a nested macro's
    // template that is NOT one of the inner macro's own pattern variables
    // must still come through unrenamed (the fix must not start renaming
    // every quoted identifier in a nested syntax-rules template -- only
    // ones that already have a same-scope pattern-side rename to match).
    try th.expectEvalTrue(
        \\(begin
        \\  (define-syntax outer-qs2
        \\    (syntax-rules ()
        \\      ((_)
        \\       (begin
        \\         (define-syntax inner-qs2
        \\           (syntax-rules ()
        \\             ((_ y) (list 'literal-tag y))))
        \\         (inner-qs2 99)))))
        \\  (equal? (outer-qs2) '(literal-tag 99)))
    );
}

test "hygiene: a template list starting with the symbol quote, but longer than 2 elements, is not treated as a quote form" {
    // instantiateTemplate's (quote <datum>) fast path used to trigger for
    // ANY template sub-list whose first element was literally the symbol
    // `quote`, regardless of the list's actual length. R7RS quote is
    // strictly unary, so a longer list starting with `quote` for an
    // unrelated reason -- e.g. passing the bare symbol `quote` as one
    // argument among several to some other macro -- was misinterpreted as
    // `(quote <2nd-element>)`, silently discarding every element after the
    // second. Found while porting SRFI 148's em-syntax-rules, whose own
    // template literally begins `(em-syntax-rules-aux1 quote ...)`.
    try th.expectEvalTrue(
        \\(begin
        \\  (define-syntax sink
        \\    (syntax-rules ()
        \\      ((_ a b c) '(got a b c))))
        \\  (define-syntax probe
        \\    (syntax-rules ()
        \\      ((_ (lit ...))
        \\       (sink quote (lit ...) 42))))
        \\  (equal? (probe ()) '(got quote () 42)))
    );
}

test "hygiene: a custom ellipsis identifier substituted through a nested syntax-rules template is recognized, not misparsed as a literal" {
    // parseSyntaxRules's custom-ellipsis detection (the optional symbol
    // right after `syntax-rules`) requires a bare, unwrapped symbol. When a
    // nested syntax-rules template substitutes an OUTER pattern variable
    // into that exact position (NESTED_SR_FLAG's usertext-marking protocol
    // wraps the value so the generating macro's own expansion doesn't
    // re-walk it as template text), the wrapped value isn't a bare symbol,
    // so the ellipsis position was silently missed and the wrapped pair
    // was misparsed as the literals list instead -- corrupting everything
    // that should have come after it. Found while porting SRFI 148's
    // em-syntax-rules, whose custom-ellipsis branch generates exactly this
    // shape. my-ellipsis is substituted (to the symbol :::) before this
    // embedded syntax-rules is parsed, so both the declared ellipsis
    // argument and its two uses (pattern and template) end up as the
    // literal symbol :::, exercising the exact generated shape.
    try th.expectEvalTrue(
        \\(begin
        \\  (define-syntax gen-with-ellipsis
        \\    (syntax-rules ()
        \\      ((_ my-ellipsis)
        \\       (syntax-rules my-ellipsis ()
        \\         ((_ x my-ellipsis) '(x my-ellipsis))))))
        \\  (define-syntax use-it (gen-with-ellipsis :::))
        \\  (equal? (use-it 1 2 3) '(1 2 3)))
    );
}

test "hygiene: a usertext marker spliced into a generated macro's dotted-tail pattern position is unwrapped mid-match, not just at pattern-matching entry" {
    // A pattern variable bound to a LIST (here `p`, bound to the 2-element
    // list `(a b)`) that a generating macro's own template splices into a
    // NESTED syntax-rules pattern's dotted tail (`. p`) becomes, once
    // flattened through the cons chain, structurally indistinguishable from
    // a run of ordinary list elements: `(_ head . p)` with p=(a b) becomes
    // `(_ head MARKER a b)` where MARKER is a real usertext-marker pair
    // (car = the reserved __hyg-usertext symbol), not a literal token.
    // matchPattern's own entry point unwraps its immediate pattern_in/
    // input_in parameters, which is enough when the marker sits in the
    // FIRST position (nothing consumed yet) -- but matchListPattern's own
    // internal loop advances past `head` first without re-unwrapping, so a
    // marker arriving at any LATER position (mid-match, after some
    // elements are already consumed -- forced here by the leading `head`)
    // surfaced as a bogus extra pattern element, shifting every subsequent
    // position and failing the match outright. Found while porting SRFI
    // 148's em-syntax-rules, whose generated pattern is always exactly
    // this dotted-tail shape (`(_ :prepare s . p)`).
    try th.expectEvalTrue(
        \\(begin
        \\  (define-syntax gen-dotted
        \\    (syntax-rules ()
        \\      ((_ p)
        \\       (syntax-rules ()
        \\         ((_ head . p) '(matched . p))))))
        \\  (define-syntax use-it (gen-dotted (a b)))
        \\  (equal? (use-it 99 10 20) '(matched 10 20)))
    );
}

test "hygiene: a custom ellipsis substituted into an ORDINARY (non-quoted) template position is also recognized" {
    // Companion to the test above: the same NESTED_SR_FLAG usertext-marking
    // protocol only wraps a substituted value outside quote (QUOTE_FLAG
    // suppresses the wrap entirely), so the previous test's quoted template
    // never actually exercised the wrapped case at the ellipsis-detection
    // site -- it worked because the value was substituted unwrapped, not
    // because the detection handled wrapping correctly. An ordinary,
    // non-quoted template position (e.g. a generated macro's own template
    // calling another procedure/macro with spliced arguments, exactly how
    // em-syntax-rules-aux2's own generated syntax-rules works) DOES receive
    // the wrapped value, and instantiateTemplate's "element followed by
    // ellipsis" detection must unwrap it too or the ellipsis is never
    // recognized (the element is emitted literally, unresolvable, instead
    // of splicing its repetitions). Caught by CodeRabbit's review of PR
    // #1776, which shipped the pattern-matching/parsing-side fix but missed
    // this ordinary-template-expansion site.
    try th.expectEvalTrue(
        \\(begin
        \\  (define-syntax gen-with-ellipsis2
        \\    (syntax-rules ()
        \\      ((_ my-ellipsis)
        \\       (syntax-rules my-ellipsis ()
        \\         ((_ x my-ellipsis) (list x my-ellipsis))))))
        \\  (define-syntax use-it2 (gen-with-ellipsis2 :::))
        \\  (equal? (use-it2 1 2 3) '(1 2 3)))
    );
}

test "hygiene: a WHOLE generated rule pattern spliced from user text keeps its keyword slot" {
    // Third site of the same usertext-marker-in-the-spine gap (#1787). When
    // a generating macro splices an entire rule PATTERN (not just a tail),
    // the marker wraps the whole thing: `(_ x y)` arrives as
    // `(MARKER _ x y)`. expandMacro drops the pattern's first element to
    // skip the macro keyword -- so it dropped the MARKER instead, leaving
    // `(_ x y)` to line up against the argument list `(1 2)`. Every
    // position then sat one slot late: the user's own `_` keyword
    // placeholder swallowed the first argument, `x` took the second, and
    // `y` had nothing left, so a perfectly well-formed call failed to match
    // at all. (The keyword-name extraction a few lines above had the same
    // gap, reading the marker symbol as the macro's own name.)
    try th.expectEvalTrue(
        \\(begin
        \\  (define-syntax gen-rule
        \\    (syntax-rules ()
        \\      ((_ pat tmpl)
        \\       (syntax-rules () (pat tmpl)))))
        \\  (define-syntax use-rule (gen-rule (_ x y) (list 'ok x y)))
        \\  (equal? (use-rule 1 2) '(ok 1 2)))
    );
}

test "hygiene: an ellipsis followed by a spliced dotted tail reserves the right number of trailing elements" {
    // Fourth site (#1787), and the only one that failed SILENTLY rather
    // than erroring. matchEllipsis splits the input by counting how many
    // elements the pattern after the ellipsis needs -- but a marker pair
    // spliced into that trailing position is a wrapper, not an element, so
    // the count came out one too high and the ellipsis stopped one element
    // short. The trailing pattern still matched (the marker symbol behaved
    // like an anonymous pattern variable and bound the element the ellipsis
    // should have taken), so the expansion succeeded with a SHORT ellipsis
    // binding: `(use-tail 1 2 99)` below yielded `(ok 1)` instead of
    // `(ok 1 2)` with no diagnostic anywhere. The literal `99` in the
    // spliced tail is what makes this observable -- a trailing pattern
    // VARIABLE absorbs the off-by-one on both sides and gives the right
    // answer for the wrong reason.
    try th.expectEvalTrue(
        \\(begin
        \\  (define-syntax gen-tail
        \\    (syntax-rules ()
        \\      ((_ tailpat)
        \\       (syntax-rules ()
        \\         ((_ a (... ...) . tailpat) (list 'ok a (... ...)))))))
        \\  (define-syntax use-tail (gen-tail (99)))
        \\  (equal? (use-tail 1 2 99) '(ok 1 2)))
    );
}
