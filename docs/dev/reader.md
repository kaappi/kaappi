# The datum reader

How source text becomes data: the grammar the reader accepts and the SRFI
extensions on top of R7RS, how numbers are tokenized and then built by the
numeric tower, how datum labels produce cyclic structure, how source spans
are recorded, how `read` on a port refills without ever splitting a token,
and what the reader must do while allocating. This is the as-built
companion to [KEP-0019](https://github.com/kaappi/keps/blob/main/keps/0019-reader.md)
(the design record). The formatter has a *separate* reader that keeps
comments; that one is [fmt.md](fmt.md)'s.

The one-paragraph version: **a lexer plus a recursive-descent parser over a
byte slice, producing plain heap data with no syntax objects.** `nextToken`
is the single token-dispatch entry; `readDatum` builds values from tokens
and records a source span for every pair and vector in a GC side table.
The reader owns numeric *syntax*; the numeric modules build the *values*,
through the same parser `string->number` uses. Reading allocates, so every
partially built datum is rooted, and one mode flag, `incomplete_input`,
makes every proper prefix of a datum report "need more input" instead of a
verdict — the invariant the incremental `read` loop rests on.

## Where it sits

| File | Owns |
|------|------|
| `reader.zig` | the `Reader` struct, `Token`, `ReadError`, the error-detail channel, whitespace and comment skipping, `nextToken`, symbol and string scanning, span recording, the limits |
| `reader_tokens.zig` | `readHash` (every `#` form), `readNumber` and `readNumberPrefixed`, complex tails, `readCharacter`, raw strings, byte strings |
| `reader_datum.zig` | `readDatum`/`readDatumOrEof`, `tokenToValue`, lists, vectors, bytevectors and numeric vectors, datum labels and `patchPlaceholder` |
| `primitives_io.zig` | the `read` primitive: string ports, the incremental fd-port loop, fold-case persistence |
| `repl.zig` | `inputIncomplete`, the completeness probe behind isocline's Enter handler |
| `diagnostics.zig` | `readErrorCode`, the `ReadError` → `KP1xxx` mapping |

`Reader.init(gc, source)` and `initWithName` construct one over a slice;
every driver — file loading, `eval`, `check`, the LSP, the REPL, `read`,
the fuzz generators — loops `readDatum` until error or EOF. There is no
`readAll`. `Reader.deinit` frees only the token buffer.

## The grammar

`nextToken` dispatches on the first significant byte after
`skipWhitespaceAndCommentsChecked`:

| Lead | Token |
|------|-------|
| `(` `)` | `lparen` / `rparen`; a `)` at datum position is `UnexpectedRightParen` |
| `.` | the improper-tail dot when followed by a delimiter; `.5` a number; `...` or `.foo` a symbol; a dot outside a list is `DotNotInList` |
| `'` `` ` `` `,` `,@` | abbreviations, built as `(quote d)`, `(quasiquote d)`, `(unquote d)`, `(unquote-splicing d)` |
| `"` | a string with the R7RS escapes `\a \b \t \n \r \" \\ \|`, `\xHH;` and `\<newline>` line continuation; anything else is `InvalidEscape` |
| `#` | `readHash`, below |
| `+` `-` | a number if a digit, `.digit` or a delimited `i` follows; otherwise a peculiar identifier (`+`, `-`, `->foo`, `+inf.0`) |
| digit | a number |
| `\|` | a `\|piped symbol\|` with the same escapes as strings, except that an unknown escape falls through to the literal byte |
| letter or `! $ % & * / : < = > ? @ ^ _ ~` | a symbol; `<subsequent>` adds digits and `+ - . @` |
| a byte ≥ 0x80 | a Unicode identifier if the codepoint is alphabetic (`unicode_tables.alphabetic_ranges`), else `UnexpectedChar` |

A **delimiter** is whitespace, `(`, `)`, `"`, `;` or `|`. Every atom must
end at one: a number glued to identifier characters (`3-state`, `5foo`) is
`InvalidNumber` with the whole token echoed in the detail message, since an
identifier can never begin with a digit (#1723).

**Comments**: `;` to a line ending (`\n`, `\r`, or `\r\n`, so a CR-only file
does not swallow everything after its first `;`, #2079); `#| … |#` nested
to `MAX_BLOCK_COMMENT_DEPTH` (256); `#;` reads and discards one datum.
Comments and `#!` directives are consumed *inside* `nextToken`, which is
why `readDatumOrEof` exists: `hasMore` cannot tell "only a trailing
directive left" from "truncated datum".

### The `#` forms

| Form | Meaning |
|------|---------|
| `#t #f #true #false` | booleans; the long spellings must match exactly and end at a delimiter |
| `#\x` | a character: one character, a name (`space newline tab return null alarm backspace delete escape`, case-insensitive), `#\xHH…` (≤ U+10FFFF, no surrogates), or one multibyte UTF-8 character |
| `#(` | vector |
| `#u8(` | bytevector; elements are fixnums 0–255 |
| `#s8( #u16( … #f64( #c64( #c128(` | SRFI 4 / SRFI 160 homogeneous numeric vectors; elements go through the same `encodeElementRaw` the `(srfi 160 <tag>)` constructors use, so a literal and a constructor cannot disagree (#2548) |
| `#u8"…"` | SRFI 207 string-notated bytevector: printable ASCII only, `\xHH;` is one raw byte |
| `#"X"…"X"` | SRFI 267 raw string: no escapes, `"X"` is the terminator |
| `#b #o #d #x` | radix prefix; `#e #i` exactness prefix; one further prefix of the other kind is allowed (`#e#x10`) |
| `#!fold-case` `#!no-fold-case` | directives; any other `#!name` is consumed and ignored (there is no `#!default`) |
| `#N=` `#N#` | datum labels, below |

`#f` shares its arm with `#f32(` and `#false`, so the arm scans the whole
alphanumeric word before deciding; that is also where an incomplete `#fa`
must report "need more" rather than "not a boolean".

**SRFI extensions present** in the grammar: 30 (nested block comments), 38
(datum labels), 62 (`#;`), 169 (digit separators `_`), 207, 267, 270 (hex
floats), and the SRFI 4/160 literals. **Excluded**, with reasons in
[srfi-exclusions.md](srfi-exclusions.md): SRFI 10 `#,(…)` (reader macros
make the reader non-local), and the syntax-replacing families (49, 105,
107–110, 119) and array literals (58, 163).

## Numbers: the reader validates, the tower builds

The reader scans numeric *syntax* and picks a `Token` variant; the
*values* are built at datum construction by other modules, which is the
boundary that keeps `read` and `string->number` from disagreeing:

| Token | Built by |
|-------|----------|
| `fixnum` | `makeFixnum`, or `allocBignumFromI64` past `i48` |
| `bignum_str` | `bignum.parseBignumString` |
| `rational`, `big_rational` | `primitives_arithmetic.makeRational*`; a zero denominator is `InvalidNumber` |
| `flonum` | `makeFlonum`; exponent markers `s f d l` are normalized to `e` first |
| `prefixed_real` | `primitives_numeric.parseNumberText` — the body of `string->number` — so an `#e`/`#i` literal and `(string->number "…")` cannot diverge (#1911). The token-level path it replaced parsed to `f64` and un-rounded with a continued fraction, which panicked at 2^63, dropped `#e` past `i64`, and collapsed values below 1e-15 to zero |
| `complex` | `makeComplexOrRealV`; both components are built digit-exactly by the scanner, never through `f64`, so `2^53+1` survives reading (#2166); `3+0i` is the real 3 and `-2.5+0.0i` stays complex (#2269) |

Complex literals cover `a+bi`, `+i`, `-i`, inf/nan parts, rational parts
(`1/2+3/4i`) and radix-prefixed forms (`#x1+2i`, #2243) — a grammar
deliberately richer than `string->number`'s, which is why `.complex` tokens
do not go through `parseNumberText`. The two component Values are rooted in
`Reader.complex_root` for the duration of one number's tokenization only,
opened and closed by the scanner itself (#2283).

## Symbols and fold-case

Symbols are interned through `gc.allocSymbol`, so identity is by name.
`#!fold-case` sets a per-`Reader` flag and `foldAndReturnSymbol` folds
each symbol Unicode-aware; the default is case-sensitive, as R7RS
requires. `read` seeds the flag from the port's `fold_case` and writes it
back after a successful parse, so a directive persists across `read` calls
on the same port (#2175); `saw_directive` keeps an otherwise-blank
incremental buffer alive so the directive's bytes are re-parsed after a
refill.

## Datum labels and cyclic structure

`labels` is a fixed `[32]?Value` on the `Reader`; a label ≥ 32 is
`InvalidNumber`. `#N=` allocates a placeholder pair `(VOID . NIL)`, roots
it, stores it under `N`, and reads the datum, so a forward or self
reference (`#N#`) resolves to the placeholder. Then:

- if the datum is a pair, its `car` and `cdr` are copied *into* the
  placeholder (with write barriers) and the placeholder is returned — the
  cycle's identity is the placeholder's;
- otherwise the datum replaces the label and `patchPlaceholder` walks it
  iteratively (a stack plus a visited set, so a cycle terminates) and
  rewrites every placeholder occurrence in pairs and vector slots.

The result is genuinely circular data, and every downstream consumer that
walks a datum has had to learn that: the printer's cycle detection, the
expander's usertext and hygiene-strip walks, `rename` in an ER macro, the
`set!` pre-scan's spine, and `lowerWithMacros`'s code-path set
([expander.md](expander.md), #2403–#2405). A new datum walker is not
finished until it has been fed `#0=(a . #0#)`.

## Source spans

The reader tracks only a byte `pos`. After each datum, `recordSpan` puts a
1-based, half-open `types.Span` (`line, col, end_line, end_col`) into
`gc.source_spans`, keyed by the Value. **Only pairs and vectors are keyed**:
they have heap identity, while an interned symbol or an immediate does not
(#1506). Line and column come from `lineColMonotone`, a cursor that
advances with the datum stream in O(distance) — the datum's start is
resolved *before* its children are read, since a rescan from byte zero per
enclosing list made every `.sld` load quadratic in its largest form
(#1888). The compiler copies each span's start into the bytecode line table
for runtime `file:line:col`; end positions stay in the side table for
`--diagnostics=json` and the LSP ([diagnostics-json.md](diagnostics-json.md)).

The table is never pruned, so a parse whose data is thrown away sets
`record_spans = false`; the REPL's completeness probe is the one such
caller today.

## What the reader must do while allocating

Reading allocates on every pair, string, symbol and vector, and a
collection can run at any of them. The rules the reader follows are the
general ones in [gc-safety-and-error-handling.md](gc-safety-and-error-handling.md);
the shapes it uses are worth knowing because the first GC bug in the
project's history was here
([postmortems/2026-06-17-gc-reachability-bug.md](postmortems/2026-06-17-gc-reachability-bug.md)):

- `readList` and `readListTail` root the head, the current element and the
  accumulating result with `pushRoot`, and barrier every `setCdr` into the
  growing spine (the list may be old by the time the next element is
  read).
- `readVector` mirrors each element into `gc.extra_roots` — an `ArrayList`
  of elements is not a root, and `&elems.items[i]` is not a stable address
  — and shrinks the list back on exit.
- `readAbbreviation` roots the datum, then the keyword symbol, then the
  inner pair.
- the datum-label placeholder is rooted across the nested `readDatum`.
- `mark_immutable` (default true) flags every literal pair, string,
  bytevector and vector immutable for the loader; `read` sets it false,
  because R7RS lets a program mutate what `read` returns.

`readDatumOrEof` counts nesting depth and refuses past
`MAX_NESTING_DEPTH` (1024, `NestingTooDeep`); `#u8(` and numeric-vector
elements pay the depth gate once in `readElementValue`. A single token is
capped at `MAX_TOKEN_BYTES` (64 KiB, `TokenTooLong`).

## `read` on a port, and incomplete input

`readDatumFn` has two paths. A **string port** parses one datum straight
from the remaining slice and advances the port. An **fd, custom,
transcoded or cyclic port** drains the peeked bytes and read buffer into a
growing accumulation, then loops: parse the accumulation with
`incomplete_input = true`; on a datum, persist `fold_case`, stash the
unconsumed tail back into the port's read buffer (a SRFI 277 cyclic port
rewinds its cursor instead), and return; on `UnexpectedEof`, read another
chunk (4096 bytes, or one burst from a custom port's `read!`); on any
other error, stop and raise it. A whitespace-only accumulation is
discarded unless it held a directive. At true EOF one final parse with the
flag off delivers the precise verdict.

**The invariant that makes this sound**, pinned by the prefix sweep in
`tests_reader_incremental.zig`: with `incomplete_input` set, *every proper
byte prefix of a datum parses to `UnexpectedEof`* — never to a different
error, which the loop treats as final, and never to a successful shorter
datum, which the loop would commit and thereby split the token
(#1893, #1920, #1940, #1945). Every scanner honours it with
`truncatedHere()` at
the point where it would otherwise finalize or reject: a `#tru` may become
`#true`, a `#\s` may become `#\space`, `1e` may become `1e5`, a line
comment cut at the chunk edge would otherwise resume as code, and a `.` as
the last byte is undecidable. The number scanners use a tail scan rather
than `pos >= len`, because they backtrack and can fail mid-slice with
bytes left. One consequence to keep: a bare atom on a still-open pipe with
no delimiter now *blocks* until the delimiter or EOF arrives; that early
return was the splitting bug. Newline-terminated interactive input
returns immediately (#847).

A clean EOF becomes the eof object; a read error is raised as an error
object with `error_type = .read` and a message that names what failed —
the registry template, or the reader's own detail when it left one.

The REPL's Enter handler asks the same question with the same reader:
`inputIncomplete` appends the newline the terminal stripped, parses in
incomplete mode without recording spans, and continues the edit only on
`UnexpectedEof`. A genuine syntax error submits the form so the prompt
reports it. The `.` and `#!` cases above are exactly the ones that used to
strand the prompt on its continuation line.

## Errors

`ReadError` is `UnexpectedEof`, `UnexpectedChar`, `UnexpectedRightParen`,
`InvalidNumber`, `InvalidCharacterName`, `UnterminatedString`,
`InvalidEscape`, `DotNotInList`, `NestingTooDeep`, `TokenTooLong` and
`OutOfMemory`; `diagnostics.readErrorCode` maps the first ten to
`KP1001`–`KP1010` in that order ([diagnostics.md](diagnostics.md)).
`read_error_detail` is a threadlocal 256-byte channel a scanner fills when
the registry template is not enough (echoing the offending token); it is
reset at the top of every `nextToken`, including the nested calls a `#;`
comment makes, so a stale detail can never be attributed to a later error
(#1723). `UnexpectedEof` doubles as the refill signal above, which is why
no scanner may repurpose it.

## Tests

| Suite | Covers |
|-------|--------|
| `src/reader.zig` (25 inline tests) | every token class, fold-case, datum labels, the delimiter rule, the monotone line/column cursor |
| `src/tests_reader_incremental.zig` (11) | the prefix-sweep invariant per token class |
| `src/tests_spans.zig` | span arithmetic and the reader → IR → bytecode line table |
| `tests/scheme/compliance/reader-*.scm`, `chars.scm`, `strings.scm`, `complex-strings.scm`, `string-ports.scm` | numerics, exactness prefixes, delimiter gaps, surrogates, the fd-port refill gaps against a string-port oracle |
| `tests/scheme/smoke/` (`reader-*`, `read-*`, `datum-label-*`, `peek-char-*`, `number-string-*`) | token validation, peculiar identifiers, numeric prefixes, long lists, incomplete datums, datum labels in vectors and under GC, interactive `read` (#847) |
| `fuzz reader` (`tests_fuzz.zig`) | raw bytes through tokenizer and parser ([fuzzing.md](fuzzing.md)) |

Two habits for reader changes. Any new scanner must answer "what do I
return when the slice ends mid-token?", and the answer is `truncatedHere`.
And `kaappi fmt` has its own lexer that must accept the same lexemes: a new
`#` form that the formatter's reader does not know is a formatter bug the
reader's tests will not find ([fmt.md](fmt.md)).

## What this design does not do

- **Syntax objects or `read-syntax`.** Spans are a side table keyed by
  heap identity; atoms carry no position. That is the same representation
  choice that keeps `syntax-case` out of the expander.
- **Reader macros.** SRFI 10 is excluded on purpose; the grammar is fixed
  at build time.
- **A shared lexer with the formatter.** Comments are not datums, so the
  formatter reads a concrete syntax tree with its own lexer.
- **Growing the label table** past 32, or the nesting limit past 1024.
  Both are fixed constants and their overflow errors are the contract.
