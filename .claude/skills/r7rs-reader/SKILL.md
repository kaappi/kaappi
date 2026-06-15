---
description: R7RS lexical syntax reference for implementing/modifying the Kaappi reader
---

# R7RS Lexical Syntax (Section 7.1)

Reader implementation: `src/reader.zig`

## Token types (currently implemented)
- `(` `)` — list delimiters
- `.` — dotted pair separator
- `'` — quote abbreviation → `(quote datum)`
- `` ` `` — quasiquote → `(quasiquote datum)`
- `,` — unquote → `(unquote datum)`
- `,@` — splicing unquote → `(unquote-splicing datum)`
- `#(` — vector literal (TODO)
- `#t` `#f` `#true` `#false` — booleans
- `#\x` `#\space` `#\newline` etc. — characters
- `"..."` — strings with escape sequences
- integers — decimal only for now
- identifiers — standard R7RS rules

## Identifier rules
- **Initial**: letter or `! $ % & * / : < = > ? @ ^ _ ~`
- **Subsequent**: initial or digit or `+ - . @`
- **Peculiar**: `+`, `-`, `...`, or identifiers starting with `+`/`-` followed by sign subsequent
- **Quoted**: `|...|` with `\|` and `\\` escapes

## String escape sequences
`\"` `\\` `\n` `\r` `\t` `\a` `\b` `\|` `\x<hex>;`

## Character names
`alarm` `backspace` `delete` `escape` `newline` `null` `return` `space` `tab`

## Comment forms
- `;` line comment
- `#;` datum comment (skips next datum)
- `#| ... |#` nested block comment

## Not yet implemented
- Floating point numbers
- Number prefixes: `#b` `#o` `#d` `#x` `#e` `#i`
- Complex numbers
- Rationals
- `#u8(` bytevector literals
- `#n=` `#n#` datum labels
- `#!fold-case` `#!no-fold-case` directives
