# Kaappi R7RS Implementation Status

## Phase 0: Runtime Architecture — DONE
- [x] Tagged u64 value representation
- [x] Heap objects (Pair, Symbol, String, Closure, Function, NativeFn)
- [x] Mark-and-sweep GC
- [x] Symbol interning
- [x] Reader (tokenizer + recursive descent parser)
- [x] Compiler (S-expr → bytecode)
- [x] Register-based VM
- [x] Printer (write/display)
- [x] REPL

## Phase 1: Minimal Lisp — DONE
- [x] Fixnum integers
- [x] Booleans (#t, #f)
- [x] Characters (#\a, #\space, etc.)
- [x] Strings
- [x] Symbols
- [x] Pairs and proper/improper lists
- [x] `quote`
- [x] `if`
- [x] `lambda` (fixed arity, rest params)
- [x] `begin`
- [x] `define` (variable and function shorthand)
- [x] `set!`
- [x] Procedure calls
- [x] Lexical closures with upvalues

### Built-in procedures implemented
- Arithmetic: `+`, `-`, `*`, `quotient`, `remainder`, `modulo`, `=`, `<`, `>`, `<=`, `>=`, `zero?`, `positive?`, `negative?`, `abs`, `min`, `max`
- Pairs: `cons`, `car`, `cdr`, `set-car!`, `set-cdr!`, `list`, `length`, `append`, `reverse`
- Predicates: `pair?`, `null?`, `number?`, `integer?`, `symbol?`, `string?`, `boolean?`, `char?`, `procedure?`, `list?`
- Equivalence: `eq?`, `eqv?`, `equal?`
- Boolean: `not`
- I/O: `display`, `write`, `newline`
- String: `number->string`, `string-length`, `string-append`, `symbol->string`
- Misc: `error`

## Phase 2: Proper Tail Calls — DONE
- [x] TAIL_CALL opcode reuses current frame
- [x] Tail position detection in compiler for `if`, `begin`, `lambda` bodies
- [x] Test: `(loop 1000000)` completes without stack overflow
- [x] Mutual tail recursion: `(my-even? 10000)` works
- [x] Non-tail recursion (fib) still works correctly

## Phase 3: Full Core Expressions — DONE
- [x] `cond` (with `else`, `=>` support)
- [x] `and`, `or` (short-circuit)
- [x] `when`, `unless`
- [x] `let`, `let*`, `letrec`, `letrec*`
- [x] Named `let`
- [x] `do`
- [ ] `case` (deferred — needs inline eqv? comparison)
- [ ] `case-lambda` (separate library)
- [ ] `let-values`, `let*-values` (Phase 10 — needs multiple values)

## Phase 4: Numeric Tower — TODO
- [ ] Flonum (f64)
- [ ] Exact/inexact distinction
- [ ] Full numeric procedures (floor, ceiling, truncate, round, sqrt, expt, etc.)
- [ ] Bignum (later)
- [ ] Rational (later)

## Phase 5: Hygienic Macros — TODO
- [ ] `syntax-rules`
- [ ] `define-syntax`
- [ ] `let-syntax`, `letrec-syntax`

## Phase 6: Libraries — TODO
- [ ] `define-library`, `import`, `export`
- [ ] `(scheme base)` library
- [ ] Library file loading (.sld)

## Phase 7: Exceptions — TODO
- [ ] `error`, `with-exception-handler`, `raise`, `raise-continuable`
- [ ] `guard`

## Phase 8: Records — TODO
- [ ] `define-record-type`

## Phase 9: Ports and I/O — TODO
- [ ] Port objects
- [ ] `open-input-file`, `open-output-file`
- [ ] `read`, `read-char`, `read-line`
- [ ] `write-char`, `write-string`

## Phase 10: Continuations — TODO
- [ ] `call-with-current-continuation`
- [ ] `dynamic-wind`
- [ ] `values`, `call-with-values`

## (scheme base) — Appendix A Coverage

Total exports: ~230 identifiers

### Implemented: ~40
`*`, `+`, `-`, `<`, `<=`, `=`, `>`, `>=`, `abs`, `and` (no), `append`, `begin`, `boolean?`, `car`, `cdr`, `char?`, `cons`, `define`, `display`, `eq?`, `eqv?`, `equal?`, `error`, `if`, `integer?`, `lambda`, `length`, `list`, `list?`, `max`, `min`, `modulo`, `negative?`, `newline`, `not`, `null?`, `number->string`, `number?`, `pair?`, `positive?`, `procedure?`, `quote`, `quotient`, `remainder`, `reverse`, `set!`, `set-car!`, `set-cdr!`, `string-append`, `string-length`, `string?`, `symbol->string`, `symbol?`, `write`, `zero?`

### Not yet implemented: ~190
Everything else in Appendix A.
