---
description: R7RS lexical syntax reference for implementing/modifying the Kaappi reader
---

# R7RS Lexical Syntax (Section 7.1)

Reader implementation: `src/reader.zig` (entry, symbols, strings),
`src/reader_tokens.zig` (numbers, `#` forms, characters),
`src/reader_datum.zig` (datum construction, datum labels). The full
description of how it works — the grammar table, the reader/numeric-tower
boundary, datum-label patching, spans, the incomplete-input invariant, the
rooting shapes — is `docs/dev/reader.md`. Read that before changing a
scanner; this file is the R7RS checklist to test against.

## Token types (all implemented)

- `(` `)` — list delimiters; `.` — dotted-pair separator
- `'` `` ` `` `,` `,@` — abbreviations for `quote`, `quasiquote`, `unquote`,
  `unquote-splicing`
- `#(` vector, `#u8(` bytevector, `#s8(`…`#f64(`/`#c64(`/`#c128(` SRFI 4/160
  numeric vectors, `#u8"…"` SRFI 207 byte strings
- `#t` `#f` `#true` `#false` — booleans
- `#\x` `#\space` `#\xHH` `#\λ` — characters
- `"..."` strings with `\a \b \t \n \r \" \\ \| \xHH; \<newline>`;
  `#"X"…"X"` SRFI 267 raw strings
- numbers: decimal, `#b #o #d #x` radix and `#e #i` exactness prefixes,
  rationals, bignums, flonums with `e s f d l` markers, hex floats
  (SRFI 270), `_` digit separators (SRFI 169), complex `a+bi` / `+i` /
  `+inf.0i`, `+inf.0 -inf.0 +nan.0`
- identifiers — standard R7RS rules plus Unicode initials/subsequents and
  `|piped|` symbols
- `#N=` `#N#` datum labels (SRFI 38, labels 0–31)
- `#!fold-case` `#!no-fold-case`; any other `#!name` is ignored

## Identifier rules

- **Initial**: letter or `! $ % & * / : < = > ? @ ^ _ ~`
- **Subsequent**: initial or digit or `+ - . @`
- **Peculiar**: `+`, `-`, `...`, or `+`/`-` followed by a sign subsequent
- **Quoted**: `|...|` with the string escapes; an unknown escape is the
  literal byte
- A number token must end at a delimiter (whitespace `( ) " ; |`); `3-state`
  is an invalid number, not a symbol

## Character names

`alarm` `backspace` `delete` `escape` `newline` `null` `return` `space` `tab`
(case-insensitive); `#\xHH…` must be ≤ U+10FFFF and not a surrogate

## Comment forms

- `;` to a line ending (`\n`, `\r`, or `\r\n`)
- `#;` datum comment (skips the next datum)
- `#| ... |#` nested block comment (depth ≤ 256)

## The one rule for a new scanner

With `incomplete_input` set, every proper byte prefix of a datum must
report `UnexpectedEof` — never another error, never a shorter datum. Where
a scan would finalize or reject at end-of-slice, write
`if (self.truncatedHere()) return ReadError.UnexpectedEof;` first. The
prefix sweep in `src/tests_reader_incremental.zig` checks it; `kaappi fmt`'s
separate lexer (`src/fmt.zig`) must learn any new lexeme too.

## Deliberately not implemented

SRFI 10 `#,(…)` reader macros, and the syntax-replacing SRFIs (49, 105,
107–110, 119) and array literals (58, 163) — see
`docs/dev/srfi-exclusions.md`.
