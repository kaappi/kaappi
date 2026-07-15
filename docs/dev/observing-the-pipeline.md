# Observing the pipeline

Kaappi compiles a program through a fixed sequence of stages:

```
Source → Reader → Expander → IR → (optimization) → Bytecode → VM
         ast       expand      ir      ir            --disassemble
```

Each stage before bytecode now has a read-only dump command, so you can watch a
program change shape from source to instructions without reading compiler source
or guessing. All output is S-expressions or structured text — already
machine-readable; feed it to a diff, a script, or an agent.

Part of the machine-legibility epic
([#1503](https://github.com/kaappi/kaappi/issues/1503)); tracked in
[#1512](https://github.com/kaappi/kaappi/issues/1512). The IR stage is documented
in depth in [ir.md](ir.md); the bytecode instruction set in
[bytecode.md](bytecode.md).

| Stage | Command | Answers |
|-------|---------|---------|
| Reader | `kaappi ast <file>` | How did the reader parse this? |
| Expander | `kaappi expand <file>` | What did the macros expand to? |
| IR | `kaappi ir <file> [--no-opt]` | What tree does the compiler lower to, before/after optimization? |
| Bytecode | `kaappi --disassemble <file>` | What instructions run? |

None of these run your program. `ast` reads and writes and nothing more;
`expand` and `ir` establish only the environment later forms depend on —
`import`, `define-library`, `include`, `define-record-type` are processed (as
[`kaappi check`](check.md) does) so imported and locally-defined macros are in
scope, and a `define-syntax` transformer is registered — but ordinary `define`s
and expressions are never evaluated.

## `kaappi ast` — the reader's view

Prints each post-read datum with `write`, one per line. Homoiconicity makes this
nearly free — it is `read` followed by `write` — but the round trip is exactly
what makes reader behavior legible: abbreviations, fold-case, datum labels and
literal edge cases all show their parsed form.

```console
$ cat abbrev.scm
'(a b c)
#!fold-case
(HELLO World)
#e1.5

$ kaappi ast abbrev.scm
(quote (a b c))
(hello world)
3/2
```

`'(a b c)` is revealed as `(quote (a b c))`; the `#!fold-case` directive
lower-cases the identifiers that follow it; `#e1.5` is the exact rational `3/2`.
Quasiquote (`` ` ``, `,`, `,@`) desugars the same way to `quasiquote` /
`unquote` / `unquote-splicing`.

## `kaappi expand` — the macro's view

Prints the program after **full** macro expansion, as S-expressions. This is the
most useful stage dump for debugging `syntax-rules`: it shows exactly what a
macro use turned into, hygiene renaming and all.

```console
$ cat swap.scm
(define-syntax swap!
  (syntax-rules ()
    ((_ a b) (let ((tmp a)) (set! a b) (set! b tmp)))))
(define x 1)
(define y 2)
(swap! x y)

$ kaappi expand swap.scm
(define-syntax swap! (syntax-rules () ((_ a b) (let ((tmp a)) (set! a b) (set! b tmp)))))
(define x 1)
(define y 2)
(__hyg_1_let ((__hyg_2_tmp x)) (set! x y) (set! y __hyg_2_tmp))
```

The `swap!` use expanded to a `let` that binds a fresh temporary. The
`__hyg_N_` prefixes are the expander's **hygiene marks**: `tmp` became
`__hyg_2_tmp` so it cannot capture a user variable also named `tmp`, and the
template's `let` keyword is marked too (the compiler strips `__hyg_N_` when it
recognizes a keyword, so this still means `let`). The marks are shown verbatim
rather than hidden — hiding them would misrepresent what the expander did and
could break the round-trip guarantee below.

**Round-trip.** Feeding `expand` output back through kaappi preserves behavior:

```console
$ kaappi swap.scm            # (with a display added)
(2 1)
$ kaappi expand swap.scm | kaappi /dev/stdin
(2 1)
```

### Fidelity and limits

The expander is driven by the same engine the compiler uses, so a top-level
`syntax-rules` macro expands exactly. A few cases are deliberately left
unexpanded — which is always sound, because an unexpanded macro use is simply
expanded again when the program is compiled:

- **`quote` / `quasiquote` data** is never touched — a macro-named list inside
  `'(...)` stays literal.
- **`let-syntax` / `letrec-syntax` local macros** are not built; uses of a
  locally-bound syntax are left in place (the transformer spec is still shown).
- **Macros that capture use-site locals** (only reachable inside a `lambda` /
  `let` body) may not expand identically to a real compile — the dump uses the
  same best-effort expansion the compiler's own pre-scan does.

Environment forms (`import`, `define-syntax`, `define-record-type`, …) are shown
unchanged; their effect is applied so later forms expand against it.

## `kaappi ir` — the compiler's tree

Prints the [IR](ir.md) tree each top-level form lowers to. By default the five
optimization passes have run; with `--no-opt` the tree is shown straight after
lowering — so the two are a before/after diff of what optimization did.

```console
$ echo '(define (f n) (if (< n 2) 1 (* n (f (- n 1)))))
(f (+ 1 2))' > fact.scm

$ kaappi ir fact.scm --no-opt        # after lowering
(passthrough (define (f n) (if (< n 2) 1 (* n (f (- n 1))))))
(call
  (global-ref f)
  (call
    (global-ref +)
    (constant 1)
    (constant 2)))

$ kaappi ir fact.scm                 # after optimization
(passthrough (define (f n) (if (< n 2) 1 (* n (f (- n 1))))))
(call
  (global-ref f)
  (constant 3))
```

The `(+ 1 2)` call folded to `(constant 3)`; pass `--no-opt` to keep it. (`ir`
drives IR optimization directly, so — unlike a normal run — it does not touch or
consult the `.sbc` bytecode cache.)

### Reading the tree

Fully-lowered forms show their child-node structure; forms the compiler
delegates as raw S-expressions (`let`, `cond`, `case`, `do`, `define` bodies,
and macro uses) show that S-expression — matching the two node categories in
[ir.md](ir.md).

| Printed | Node |
|---------|------|
| `(constant V)` | literal value |
| `(global-ref sym)` | global variable reference |
| `(call op arg…)` | function call: operator then arguments |
| `(if test then else?)` | conditional |
| `(begin …)` / `(and …)` / `(or …)` | sequence / short-circuit |
| `(when test body…)` / `(unless …)` | one-armed conditionals |
| `(define name value)` / `(set! name value)` | definition / mutation (value is raw) |
| `(lambda args)` | lambda (body compiled during emission) |
| `(let args)` / `(let* …)` / `(letrec …)` | binding forms (delegated) |
| `(sexpr-form kw args)` | a delegated derived form (`cond`, `case`, `do`, …) |
| `(passthrough expr)` | raw S-expression — a macro use or special form deferred to the legacy compiler path |

A node in tail position is annotated with a trailing `; tail`.

`--no-opt` here is the subcommand-local spelling of the global
[`--no-ir-opt`](ir.md) flag; both disable the same passes.

## Bytecode: `--disassemble`

The last stage before execution. `kaappi --disassemble <file>` prints the
register-based bytecode each top-level function compiles to;
`(disassemble proc)` does the same from inside a running program. See
[bytecode.md](bytecode.md) for the instruction set.

## Where this fits

These four commands make every stage in the compilation pipeline observable from
the CLI, so the operational test of the machine-legibility epic holds for the
pipeline itself: a failing program can be understood — and a macro or lowering
surprise diagnosed — using only documented command output, no compiler-source
spelunking.
