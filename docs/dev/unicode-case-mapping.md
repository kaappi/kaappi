# Unicode Case Mapping

Coverage reference for case conversion (`char-upcase`, `char-downcase`,
`char-foldcase` and their string equivalents), implemented in
`src/primitives_char.zig`.

## Current coverage

| Script | Range | Upcase | Downcase | Notes |
|--------|-------|--------|----------|-------|
| ASCII | U+0000-U+007F | Yes | Yes | Standard `toUpper`/`toLower` |
| Latin-1 Supplement | U+00C0-U+00FF | Yes | Yes | +-0x20 mapping |
| Latin Extended-A | U+0100-U+017E | Yes | Yes | Even/odd parity |
| Latin Extended-B/IPA | U+0180-U+024F | Letter classification only | No case mapping | Pass-through |
| Greek and Coptic | U+0370-U+03FF | Yes | Yes | Includes 6 accented mappings, final sigma |
| Cyrillic | U+0400-U+04FF | Yes | Yes | U+0410-042F ↔ U+0430-044F |
| Cyrillic Supplement | U+0500-U+052F | Letter classification only | No case mapping | Pass-through |
| Armenian | U+0530-U+058F | Yes | Yes | +0x30 offset mapping |
| Georgian (Mtavruli) | U+1C90-U+1CBA | Yes | Yes | ↔ Mkhedruli U+10D0-10FA |
| Cherokee | U+13A0-U+13EF / U+AB70-U+ABBF | Yes | Yes | +0x97D0 offset |

String operations also handle multi-codepoint expansions:
- `string-upcase`: ß→SS, ǰ→J+caron, ΐ/ΰ→decomposed, ff/fi/fl ligatures
- `string-downcase`: İ→i+dot, Σ→ς (final sigma context)
- `string-foldcase`: ß→ss, İ→i+dot, ſ→s, ǰ→j+caron

Examples:

```scheme
(char-upcase #\ա)      ;=> #\Ա   (Armenian, U+0561 → U+0531)
(char-upcase #\ꭰ)      ;=> #\Ꭰ   (Cherokee, U+AB70 → U+13A0)
(string-upcase "աբգ")   ;=> "ԱԲԳ"
```

## Known gaps

Tracked in [#920](https://github.com/kaappi/kaappi/issues/920):

- Latin Extended-B/IPA and Cyrillic Supplement have letter classification
  but no case mapping (pass-through).
- Bicameral scripts not yet covered (all simple offset patterns): Coptic,
  Glagolitic, Deseret, Osage, Warang Citi, Adlam. Khutsuri Georgian
  (Asomtavruli ↔ Nuskhuri) was deliberately skipped as a historical script.
- The reader's `#!fold-case` directive lowercases identifiers with
  `std.ascii.toLower`, so non-ASCII identifiers are not folded
  (`foldAndReturnSymbol` in `src/reader_tokens.zig`).

## Key files

| Component | Location |
|-----------|----------|
| Character case ops | `src/primitives_char.zig` (`unicodeUpcase`/`unicodeDowncase`) |
| Character predicates | `src/primitives_char.zig` (`isUnicodeUppercase`/`isUnicodeLowercase`) |
| Letter classification | `src/primitives_char.zig` (`isUnicodeLetter`) |
| String case ops | `src/primitives_char.zig` (`stringCaseMapExpanding`) |
| Reader fold-case | `src/reader_tokens.zig` (`foldAndReturnSymbol`) |

## Tests

```bash
zig build test
zig build run -- tests/scheme/compliance/chars.scm
zig build run -- tests/scheme/compliance/unicode.scm
```
