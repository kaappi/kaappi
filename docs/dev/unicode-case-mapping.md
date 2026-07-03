# Unicode Case Mapping

Coverage reference for case conversion (`char-upcase`, `char-downcase`,
`char-foldcase` and their string equivalents), implemented in
`src/primitives_char.zig`.

## Current coverage

Case mappings are driven by auto-generated tables in `src/unicode_tables.zig`
(derived from Unicode 15.1 `UnicodeData.txt` and `CaseFolding.txt`). Any
codepoint with a simple case mapping in Unicode is handled automatically.

| Script | Range | Upcase | Downcase | Identifier | Notes |
|--------|-------|--------|----------|------------|-------|
| ASCII | U+0000-U+007F | Yes | Yes | Yes | Standard `toUpper`/`toLower` |
| Latin-1 Supplement | U+00C0-U+00FF | Yes | Yes | Yes | |
| Latin Extended-A | U+0100-U+017E | Yes | Yes | Yes | Even/odd parity |
| Latin Extended-B/IPA | U+0180-U+02AF | Yes | Yes | Yes | Table-driven |
| Greek and Coptic | U+0370-U+03FF | Yes | Yes | Yes | Includes accented, final sigma |
| Cyrillic | U+0400-U+04FF | Yes | Yes | Yes | |
| Cyrillic Supplement | U+0500-U+052F | Yes | Yes | Yes | Even/odd parity |
| Armenian | U+0530-U+058F | Yes | Yes | Yes | +0x30 offset |
| Georgian (Mtavruli) | U+1C90-U+1CBA | Yes | Yes | Yes | ↔ Mkhedruli U+10D0-10FA |
| Cherokee | U+13A0-U+13F5 / U+AB70-U+ABBF | Yes | Yes | Yes | |
| Coptic | U+2C80-U+2CF3 | Yes | Yes | Yes | Even/odd parity |
| Glagolitic | U+2C00-U+2C5F | Yes | Yes | Yes | +0x30 offset |
| Deseret | U+10400-U+1044F | Yes | Yes | Yes | +0x28 offset (SMP) |
| Osage | U+104B0-U+104FB | Yes | Yes | Yes | +0x28 offset (SMP) |
| Warang Citi | U+118A0-U+118DF | Yes | Yes | Yes | +0x20 offset (SMP) |
| Adlam | U+1E900-U+1E943 | Yes | Yes | Yes | +0x22 offset (SMP) |

**Identifier** column = accepted as bare identifiers in the reader (no `|...|`
quoting needed). The reader falls back to the Unicode case tables for any
codepoint not in its hardcoded ranges, so new scripts added to
`unicode_tables.zig` are automatically recognized as letters.

Khutsuri Georgian (Asomtavruli U+10A0–U+10C5 ↔ Nuskhuri U+2D00–U+2D25) is
covered by the case tables (upcase/downcase work) but is a historical script
and not explicitly listed in the reader's fast path.

String operations also handle multi-codepoint expansions:
- `string-upcase`: ß→SS, ǰ→J+caron, ΐ/ΰ→decomposed, ff/fi/fl ligatures
- `string-downcase`: İ→i+dot, Σ→ς (final sigma context)
- `string-foldcase`: ß→ss, İ→i+dot, ſ→s, ǰ→j+caron

Examples:

```scheme
(char-upcase #\ⲁ)      ;=> #\Ⲁ   (Coptic, U+2C81 → U+2C80)
(char-downcase #\Ⰰ)    ;=> #\ⰰ   (Glagolitic, U+2C00 → U+2C30)
(char-upcase #\𞤢)      ;=> #\𞤀   (Adlam, U+1E922 → U+1E900)
(string-upcase "ⲁⲃⲅ")  ;=> "ⲀⲂⲄ"
```

## Reader fold-case

The `#!fold-case` directive folds identifiers using full Unicode case folding
(`charFoldcase` per codepoint). This means non-ASCII identifiers are folded
correctly:

```scheme
#!fold-case
(define ΑΒΓ 42)
αβγ  ;=> 42  (Greek uppercase folds to lowercase)
```

## Key files

| Component | Location |
|-----------|----------|
| Character case ops | `src/primitives_char.zig` (`unicodeUpcase`/`unicodeDowncase`) |
| Character predicates | `src/primitives_char.zig` (`isUnicodeUppercase`/`isUnicodeLowercase`) |
| Letter classification | `src/primitives_char.zig` (`isUnicodeLetter`) |
| Reader letter classification | `src/reader.zig` (`isUnicodeLetter`) |
| String case ops | `src/primitives_char.zig` (`stringCaseMapExpanding`) |
| Reader fold-case | `src/reader_tokens.zig` (`foldAndReturnSymbol`) |
| Unicode tables | `src/unicode_tables.zig` (auto-generated from Unicode 15.1) |

## Tests

```bash
zig build test
zig build run -- tests/scheme/compliance/chars.scm
zig build run -- tests/scheme/compliance/unicode.scm
zig build run -- tests/scheme/compliance/unicode-case.scm
zig build run -- tests/scheme/compliance/fold-case-unicode.scm
```
