# Unicode Case-Mapping Expansion

## Current coverage

Case conversion (`char-upcase`, `char-downcase`, `char-foldcase` and their
string equivalents) is implemented in `src/primitives_char.zig`. The current
implementation covers:

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

## What's missing

### Armenian (U+0530-U+058F)

Armenian has a clear uppercase/lowercase distinction:
- Uppercase: U+0531-U+0556 (38 letters)
- Lowercase: U+0561-U+0586 (38 letters)
- Mapping: lowercase = uppercase + 0x30

```zig
// In unicodeUpcase:
if (c >= 0x0561 and c <= 0x0586) return c - 0x30;  // lowercase → uppercase

// In unicodeDowncase:
if (c >= 0x0531 and c <= 0x0556) return c + 0x30;  // uppercase → lowercase

// In isUnicodeUppercase:
if (c >= 0x0531 and c <= 0x0556) return true;

// In isUnicodeLowercase:
if (c >= 0x0561 and c <= 0x0586) return true;
```

**Effort:** 4 lines of code. Simple offset mapping.

### Georgian (U+10A0-U+10FF)

Georgian case mapping is more nuanced. Traditional Georgian (Mkhedruli) is
unicameral (no case distinction). Unicode added Mtavruli (uppercase) in
Unicode 11.0:
- Mtavruli (uppercase): U+1C90-U+1CBA (45 letters)
- Mkhedruli (lowercase): U+10D0-U+10FA (43 letters)
- Mapping: Mtavruli = Mkhedruli - 0x10D0 + 0x1C90 (offset 0xBC0)

Additionally, the older Khutsuri script has case:
- Asomtavruli (uppercase): U+10A0-U+10C5 (38 letters)
- Nuskhuri (lowercase): U+2D00-U+2D25 (38 letters)
- Mapping: Nuskhuri = Asomtavruli - 0x10A0 + 0x2D00 (offset 0x1C60)

**Effort:** ~10 lines. Two separate offset mappings. The Mkhedruli/Mtavruli
mapping requires checking if the target range is recognized as letters.

### Cherokee (U+13A0-U+13FF, U+AB70-U+ABBF)

Cherokee was originally unicameral but Unicode 8.0 added lowercase:
- Uppercase: U+13A0-U+13EF (80 letters)
- Lowercase: U+AB70-U+ABBF (80 letters)
- Mapping: lowercase = uppercase - 0x13A0 + 0xAB70 (offset 0x97D0)

Additional uppercase letters at U+13F0-U+13F5 map to U+13F8-U+13FD.

**Note:** Cherokee letters are NOT currently classified in `isUnicodeLetter`.
They would need to be added to the letter classification as well.

**Effort:** ~10 lines for case mapping + 2 lines for letter classification.

### Other scripts with case (lower priority)

| Script | Uppercase | Lowercase | Letters |
|--------|-----------|-----------|---------|
| Coptic | U+2C80-U+2CB2 (even) | U+2C81-U+2CB3 (odd) | ~50 |
| Glagolitic | U+2C00-U+2C2F | U+2C30-U+2C5F | ~48 |
| Deseret | U+10400-U+10427 | U+10428-U+1044F | 40 |
| Osage | U+104B0-U+104D3 | U+104D8-U+104FB | 36 |
| Warang Citi | U+118A0-U+118BF | U+118C0-U+118DF | 32 |
| Adlam | U+1E900-U+1E921 | U+1E922-U+1E943 | 34 |

These are less commonly needed but follow simple offset patterns.

## Implementation plan

### Step 1: Armenian (highest value, simplest)

Add 4 range checks each to `unicodeUpcase`, `unicodeDowncase`,
`isUnicodeUppercase`, `isUnicodeLowercase` in `src/primitives_char.zig`.

### Step 2: Cherokee

Add letter classification range + 4 case mapping checks. Cherokee is widely
used in digital text and the Unicode Consortium specifically added case
mapping for it.

### Step 3: Georgian (Mtavruli)

Add Mtavruli ↔ Mkhedruli mapping. Skip Khutsuri (historical script, rarely
used in digital text).

### Step 4 (optional): Reader fold-case

The `#!fold-case` directive currently uses `std.ascii.toLower()` for
identifiers. For full Unicode compliance, it should use `unicodeDowncase`.
This is a separate change in `src/reader_tokens.zig:226`.

## Verification

```scheme
;; Armenian
(char-upcase #\ա)     ;=> #\Ա   (U+0561 → U+0531)
(char-downcase #\Ա)   ;=> #\ա   (U+0531 → U+0561)

;; Cherokee
(char-upcase #\ꭰ)     ;=> #\Ꭰ   (U+AB70 → U+13A0)
(char-downcase #\Ꭰ)   ;=> #\ꭰ   (U+13A0 → U+AB70)

;; String operations
(string-upcase "աբգ")  ;=> "ԱԲԳ"
(string-downcase "ԱԲԳ") ;=> "աբգ"
```

Run existing tests to verify no regressions:
```bash
zig build test
zig build run -- tests/scheme/compliance/chars.scm
zig build run -- tests/scheme/compliance/unicode.scm
```

## Key files

| Component | Location |
|-----------|----------|
| Character case ops | `src/primitives_char.zig:179-225` (`unicodeUpcase`/`unicodeDowncase`) |
| Character predicates | `src/primitives_char.zig:108-140` (`isUnicodeUppercase`/`isUnicodeLowercase`) |
| Letter classification | `src/primitives_char.zig:63-106` (`isUnicodeLetter`) |
| String case ops | `src/primitives_char.zig:454-548` (`stringCaseMapExpanding`) |
| Reader fold-case | `src/reader_tokens.zig:226` |

## Complexity

Low. Armenian is 4 lines. Cherokee is ~12 lines (including letter
classification). Georgian is ~10 lines. Total: ~30 lines of code for all
three scripts.
