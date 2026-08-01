# `kaappi fmt` — the canonical formatter

`kaappi fmt` lays Scheme source out in one canonical form. A canonical
formatter makes diffs meaningful, ends style review, and gives agents
format-on-save invariance — the same job `zig fmt` does for the compiler's own
Zig. It is the final item of the machine-legibility epic (kaappi#1518, part of
kaappi#1503).

```text
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
* **LF line endings.** Every line break `fmt` emits is a bare `\n`, whatever the
  input used. See *Line endings* below.

## Line endings

`kaappi fmt` **normalises line endings to LF** — the same policy `zig fmt`
applies to this compiler's own Zig, verified against it. CRLF and lone CR
between lexemes are line-ending whitespace, and normalise like any other
whitespace run; the file ends in exactly one `\n`.

**Bytes inside a datum are never touched.** A CR there is program data, not
layout, so all of these survive byte-for-byte under this policy and would under
any other:

| Datum | Example |
|---|---|
| String literal | `"a<CR>b"`, `"a<CR><LF>b"` |
| SRFI 267 raw string | `#"X"a<CR>b"X"` |
| Piped symbol | `\|a<CR>b\|` |
| Character literal | `#\<CR>` (and its `#\return` spelling) |

Comments are not datums, so both kinds normalise. A line comment's trailing
`\r` is the carriage return of the CRLF that ended it, and is dropped alongside
the trailing spaces beside it; a block comment ends at `|#`, so its *interior*
line endings normalise outright.

`--check` reports a file that differs only in line endings, because `fmt` would
rewrite it. The two share one comparison in `formatFile`, so they can never
disagree about any file.

### Why this is not left to the round-trip guard

The [safety net](#the-round-trip-safety-net) below is structurally blind to
this. `\r` is whitespace to the reader, so a whole-file CRLF→LF rewrite is
`equal?`-**invariant**: the guard passes while every line in the file changes.
It proves the *program* did not change; it cannot prove the *bytes* did not.
Line endings are the one dimension it cannot see, which is why the policy is
stated here and enforced by dedicated tests rather than inferred from the
guard (kaappi#1897).

### On Windows

`fmt` writes LF on every platform — file descriptors are opened `O_BINARY`, and
stdin/stdout/stderr are `_setmode(O_BINARY)` (`src/platform.zig`), so no CRT
translation applies. On a checkout with `core.autocrlf=true` the working tree
holds CRLF, so `fmt` rewrites those files and `fmt --check` reports them. The
fix is the same one Go and Zig projects use — normalise the checkout:

```gitattributes
*.scm text eol=lf
*.sld text eol=lf
```

or `git config core.autocrlf input`. This repo needs neither: no tracked
`.scm`/`.sld` contains a CR.

### Known deviation: a lone CR does not end a `;` comment

R7RS 7.1.1 defines `⟨line ending⟩ → ⟨newline⟩ | ⟨return⟩ ⟨newline⟩ | ⟨return⟩`
and ends a `;` comment at one, but this **reader** ends it only at `\n`
(kaappi#2079) — so in a classic-Mac-line-ending file everything after the first
`;` is one comment. `fmt`'s lexer mirrors the real reader by design, so it
inherits that: the comment's interior CR is preserved rather than normalised,
since rewriting it to `\n` would split the comment and promote its tail to real
code. Every other lone CR in such a file does become LF. `fmt` is faithful to
what the program means today; fixing the reader is what changes it.

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

<!-- The space inside `#\ ` is the space character literal being documented,
     not stray padding — MD038's autofix would delete it. -->
<!-- markdownlint-disable MD038 -->
The lexer mirrors the real reader's delimiter rules, and handles the awkward
cases that make a naive tokenizer wrong: `#\(` / `#\;` / `#\ ` (a delimiter *is*
the character), `#0#` and `#e#xFF` (interior `#`), strings and `|piped symbols|`
that contain parens or semicolons, and nested `#| … |#`.
<!-- markdownlint-enable MD038 -->

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
  codes, stdin), the line-ending policy, plus two corpus-wide properties:
  formatting every `.scm`/`.sld` under `tests/scheme/` and `lib/` has **zero
  semantic drift**, and the result is **idempotent**.

  Its line-ending fixtures are built with `printf`, never checked in: a
  committed CRLF file would be rewritten by git's own eol filters on a
  `core.autocrlf=true` checkout — exactly the Windows configuration those cases
  exist to cover — leaving the test asserting nothing.

* **`tests/scheme/fmt/fmt-adversarial.sh`** — comment placement where the
  layout engine has a decision to make (between `define` and its name, after a
  dotted `.`, inside a `case` datum list, `#|` inside a `;` and vice versa, a
  comment as a file's only content, one with no trailing newline, …). Each case
  asserts all three of: `fmt` accepts it, every comment survives in order, and a
  second pass changes nothing. Plus the parser-depth property — an input deeper
  than any reader accepts must be *rejected*, not fatal.

* **`tools/fmt_fuzz.py`** — the fuzzer those cases came from, run on demand.
  Not in `run-all.sh`: a useful run takes minutes, past that suite's 60 s
  per-file budget. Four modes over the repo's own corpus — random byte
  mutation, whitespace-run resizing (which must not change the output at all),
  comment and blank-line insertion, and an exhaustive comment × blank-line
  grid. Nothing is written over a corpus file: every mutant reaches `fmt` on
  stdin. Run it when changing `fmt.zig` or `fmt_print.zig`.

  Why a fuzzer earns its keep here specifically: the round-trip guard proves
  the *program* is unchanged, and comments are not part of the program, so
  comment handling and idempotence are exactly the two properties nothing else
  checks. Both of the bugs the first campaign found live there
  (kaappi#2142, kaappi#2143), along with a parser-depth crash (kaappi#2141).

## CI adoption

Ecosystem repos can gate formatting in CI with the check form:

```yaml
- name: Check formatting
  run: kaappi fmt --check $(git ls-files '*.scm' '*.sld')
```

which exits non-zero (and prints the offending paths) when anything is
unformatted.
