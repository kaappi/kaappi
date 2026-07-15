# `kaappi fmt` — the canonical formatter

`kaappi fmt` lays Scheme source out in one canonical form. A canonical
formatter makes diffs meaningful, ends style review, and gives agents
format-on-save invariance — the same job `zig fmt` does for the compiler's own
Zig. It is the final item of the machine-legibility epic (kaappi#1518, part of
kaappi#1503).

```
kaappi fmt [--check] files...     # format each file in place
kaappi fmt [--check]              # format stdin to stdout
```

* Without `--check`, each file is rewritten in place (only when its contents
  actually change), and stdin is formatted to stdout.
* With `--check`, nothing is written. Each path that is **not** already
  formatted is printed, and the process exits non-zero if any file differs (or
  fails to read/parse). This is the CI gate; the stdin form exits non-zero if
  stdin is not already formatted.

## What "canonical" means here

* **2-space R7RS indentation.** Special forms indent their bodies two spaces
  from the open paren; `define`/`lambda`/`let` bodies, `cond`/`case` clauses,
  and the like follow the conventional Scheme shape (see *Layout rules*).
* **Single-space separators.** Runs of spaces and tabs between elements collapse
  to one space.
* **Closing parens gathered.** A closing paren follows the last element on its
  line — never dangling on a line of its own — unless a trailing line comment
  forces it down.
* **Reflowed to width.** A form that fits within `max_width` (80) columns is put
  on one line; one that does not breaks. Layout depends only on the program's
  content and its comments, **not** on the input's own line breaks, so two files
  that differ only in whitespace format identically.
* **Verbatim atoms.** Symbol, number, string, and character spellings are never
  rewritten — `1.5e10`, `#xFF`, `#\newline`, `'x` vs `(quote x)` all pass
  through untouched. The formatter rearranges whitespace *between* lexemes; it
  never edits a lexeme.

## Why it needs its own reader

Comments are not datums, so the ordinary reader — which discards them — cannot
drive a formatter. `fmt` has its own *concrete* syntax reader (`src/fmt.zig`):

1. A **lexer** emits every lexeme, including the three comment kinds (`; line`,
   `#| block |#`, `#;datum`) and the count of newlines before each lexeme (so
   blank-line grouping and trailing-vs-leading comment placement survive).
2. A **parser** builds a CST of `Node`s — lists/vectors, atoms, reader prefixes
   (`'` `` ` `` `,` `,@` and datum labels `#3=`), datum comments, and line/block
   comments — keeping every lexeme's text verbatim.
3. The **printer** (`src/fmt_print.zig`) walks the CST and lays it out.

The lexer mirrors the real reader's delimiter rules, and handles the awkward
cases that make a naive tokenizer wrong: `#\(` / `#\;` / `#\ ` (a delimiter *is*
the character), `#0#` and `#e#xFF` (interior `#`), strings and `|piped symbols|`
that contain parens or semicolons, and nested `#| … |#`.

## Layout rules

When a list does not fit on one line it breaks in one of two shapes, chosen from
its head:

* **Body style** — `define`, `lambda`, `let`/`let*`/`letrec`, `when`, `unless`,
  `begin`, `case`, `do`, `parameterize`, `guard`, `syntax-rules`,
  `define-record-type`, `define-library`, and a few common macros
  (`test-group`, `receive`): a fixed number of *distinguished* subforms stay on
  the head line and the remaining **body** goes one item per line, indented two
  spaces. `let` distinguishes its binding list; named `let` also distinguishes
  the loop name.

* **Call style** — function calls, `cond`, `and`/`or`, vectors, and any
  unrecognised head: the first argument stays on the head line and the rest
  align under it (the Emacs/`scmindent` default, the natural look for calls).

The distinguished-subform table lives in `bodyDistinguished` in
`src/fmt_print.zig`; unknown heads default to call style, so an unfamiliar macro
formats predictably rather than wrongly.

### Comments and blank lines

A line comment forces its enclosing list to break and keeps the closing paren
off its line. A comment on the same source line as the preceding datum stays
*trailing*; on its own line it *leads* the next datum. A single blank line
between body items or top-level forms is preserved (runs of blanks collapse to
one); a blank before a subform that rides the head line is dropped. Everything
else about layout is recomputed — that is what makes the output canonical.

## The round-trip safety net

Layout can only rearrange whitespace between lexemes, so the datums a program
reads are invariant by construction. That invariant is *also checked at
runtime*: before writing any file, `verifyRoundTrip` re-reads both the original
and the formatted text **with the real reader** and compares the datum sequences
with `equal?` (`primitives.deepEqual`). On any mismatch — or if either side
fails to read — `fmt` refuses to write and reports an error. A bug in the
lexer, parser, or printer can therefore never corrupt a source file; at worst a
file is left unformatted.

One consequence: a source whose datums cannot be compared this way — in
practice, only a file containing a self-referential datum label the real reader
builds into a cyclic structure that some readers cannot round-trip — is left
untouched and reported, rather than reformatted. This is rare in hand-written
program source.

## Idempotence

`fmt(fmt(x)) == fmt(x)`. This rests on two invariants, both under test:

* `measure` (the fit predicate) and the inline emitter agree exactly on width.
* Layout is a pure function of content and comments, never of the input's line
  breaks. The one subtlety is blank lines: `hasBodyBlank` forces a break only
  for a blank that layout will *preserve* (before an own-line item), so a
  dropped blank never resurrects on the next pass and a preserved one always
  re-forces the same break.

## Tests

* **`src/tests_fmt.zig`** — exact input→output cases, comment and blank-line
  preservation, the idempotence property and semantics-preserving round-trip
  over programs from the grammar fuzzer (`fuzz_gen`), and parser diagnostics.
* **`tests/scheme/fmt/fmt.sh`** — CLI behaviour (write in place, `--check` exit
  codes, stdin) plus two corpus-wide properties: formatting every `.scm`/`.sld`
  under `tests/scheme/` and `lib/` has **zero semantic drift**, and the result
  is **idempotent**.

## CI adoption

Ecosystem repos can gate formatting in CI with the check form:

```yaml
- name: Check formatting
  run: kaappi fmt --check $(git ls-files '*.scm' '*.sld')
```

which exits non-zero (and prints the offending paths) when anything is
unformatted.
