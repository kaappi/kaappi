# Kaappi Scheme Procedure Reference

This document lists all built-in procedures organized by domain. Each procedure
shows its arity (`N` = exactly N arguments, `N+` = N or more arguments) and a
short description.

---

## Arithmetic

| Procedure | Arity | Description |
|-----------|-------|-------------|
| `+` | 0+ | Sum of all arguments (0 with no args) |
| `-` | 1+ | Negation (1 arg) or subtraction (2+ args) |
| `*` | 0+ | Product of all arguments (1 with no args) |
| `/` | 1+ | Reciprocal (1 arg) or division (2+ args) |
| `quotient` | 2 | Integer division truncated toward zero |
| `remainder` | 2 | Remainder after truncated division |
| `modulo` | 2 | Modulo (sign follows divisor) |
| `=` | 2+ | Numeric equality |
| `<` | 2+ | Monotonically increasing |
| `>` | 2+ | Monotonically decreasing |
| `<=` | 2+ | Monotonically non-decreasing |
| `>=` | 2+ | Monotonically non-increasing |
| `zero?` | 1 | True if argument is zero |
| `positive?` | 1 | True if argument is positive |
| `negative?` | 1 | True if argument is negative |
| `abs` | 1 | Absolute value |
| `min` | 1+ | Minimum of arguments |
| `max` | 1+ | Maximum of arguments |
| `even?` | 1 | True if integer is even |
| `odd?` | 1 | True if integer is odd |
| `gcd` | 0+ | Greatest common divisor |
| `lcm` | 0+ | Least common multiple |
| `floor` | 1 | Largest integer not greater than argument |
| `ceiling` | 1 | Smallest integer not less than argument |
| `truncate` | 1 | Integer part, truncated toward zero |
| `round` | 1 | Round to nearest integer (banker's rounding) |
| `exact?` | 1 | True if number is exact |
| `inexact?` | 1 | True if number is inexact |
| `exact-integer?` | 1 | True if number is an exact integer |
| `exact` | 1 | Convert to exact representation |
| `inexact` | 1 | Convert to inexact representation |
| `exact->inexact` | 1 | Alias for `inexact` |
| `inexact->exact` | 1 | Alias for `exact` |
| `expt` | 2 | Raise base to a power |
| `square` | 1 | Square of a number |
| `sqrt` | 1 | Square root (complex result for negative reals) |
| `exact-integer-sqrt` | 1 | Integer square root, returns root and remainder via values |
| `sin` | 1 | Sine (radians) |
| `cos` | 1 | Cosine (radians) |
| `tan` | 1 | Tangent (radians) |
| `asin` | 1 | Arcsine |
| `acos` | 1 | Arccosine |
| `atan` | 1+ | Arctangent (1 arg) or two-argument atan2 |
| `exp` | 1 | Exponential (e^x) |
| `log` | 1+ | Natural log (1 arg) or log base b (2 args) |
| `finite?` | 1 | True if number is finite |
| `infinite?` | 1 | True if number is infinite |
| `nan?` | 1 | True if number is NaN |
| `number->string` | 1 | Convert number to string representation |
| `string->number` | 1+ | Parse string as number (optional radix) |
| `floor-quotient` | 2 | Quotient from floor division |
| `floor-remainder` | 2 | Remainder from floor division |
| `floor/` | 2 | Floor division returning quotient and remainder |
| `truncate-quotient` | 2 | Quotient from truncated division |
| `truncate-remainder` | 2 | Remainder from truncated division |
| `truncate/` | 2 | Truncated division returning quotient and remainder |
| `numerator` | 1 | Numerator of a rational (identity for integers) |
| `denominator` | 1 | Denominator of a rational (1 for integers) |
| `rationalize` | 2 | Simplest rational within tolerance |

## Complex Numbers

| Procedure | Arity | Description |
|-----------|-------|-------------|
| `make-rectangular` | 2 | Construct complex from real and imaginary parts |
| `make-polar` | 2 | Construct complex from magnitude and angle |
| `real-part` | 1 | Real part of a complex number |
| `imag-part` | 1 | Imaginary part of a complex number |
| `magnitude` | 1 | Magnitude (absolute value) of a complex number |
| `angle` | 1 | Angle (argument) of a complex number |

## Pairs and Lists

| Procedure | Arity | Description |
|-----------|-------|-------------|
| `cons` | 2 | Construct a pair |
| `car` | 1 | First element of a pair |
| `cdr` | 1 | Second element of a pair |
| `set-car!` | 2 | Mutate the car of a pair |
| `set-cdr!` | 2 | Mutate the cdr of a pair |
| `list` | 0+ | Construct a list from arguments |
| `length` | 1 | Length of a proper list |
| `append` | 0+ | Append lists together |
| `reverse` | 1 | Reverse a list |
| `caar` | 1 | `(car (car x))` |
| `cadr` | 1 | `(car (cdr x))` |
| `cdar` | 1 | `(cdr (car x))` |
| `cddr` | 1 | `(cdr (cdr x))` |
| `list-ref` | 2 | Element at index k |
| `list-tail` | 2 | Sublist starting at index k |
| `list-set!` | 3 | Set element at index k |
| `list-copy` | 1 | Shallow copy of a list |
| `make-list` | 1+ | Create list of k elements (optional fill value) |
| `member` | 2+ | Search by `equal?` (optional comparator) |
| `memq` | 2 | Search by `eq?` |
| `memv` | 2 | Search by `eqv?` |
| `assoc` | 2+ | Association list lookup by `equal?` (optional comparator) |
| `assq` | 2 | Association list lookup by `eq?` |
| `assv` | 2 | Association list lookup by `eqv?` |
| `map` | 2+ | Apply procedure to corresponding elements of lists |
| `for-each` | 2+ | Like `map` but for side effects only |
| `apply` | 2+ | Apply procedure to a list of arguments |

## SRFI-1 List Library

| Procedure | Arity | Description |
|-----------|-------|-------------|
| `fold` | 3+ | Left fold over one or more lists |
| `fold-right` | 3+ | Right fold over one or more lists |
| `reduce` | 3 | Like fold with identity element |
| `reduce-right` | 3 | Like fold-right with identity element |
| `filter` | 2 | Keep elements satisfying predicate |
| `remove` | 2 | Remove elements satisfying predicate |
| `partition` | 2 | Split list by predicate into two lists |
| `find` | 2 | First element satisfying predicate, or `#f` |
| `find-tail` | 2 | Tail starting at first element satisfying predicate |
| `any` | 2+ | True if predicate holds for any element |
| `every` | 2+ | True if predicate holds for every element |
| `count` | 2+ | Count elements satisfying predicate |
| `iota` | 1+ | Generate list of integers (count, optional start and step) |
| `zip` | 1+ | Transpose lists into list of lists |
| `concatenate` | 1 | Append a list of lists |
| `take` | 2 | First k elements |
| `drop` | 2 | All but first k elements |
| `take-while` | 2 | Leading elements satisfying predicate |
| `drop-while` | 2 | Drop leading elements satisfying predicate |
| `filter-map` | 2+ | Map then filter false values |
| `append-map` | 2+ | Map then append results |
| `last` | 1 | Last element of a non-empty list |
| `last-pair` | 1 | Last pair of a non-empty list |
| `proper-list?` | 1 | True if argument is a proper list |
| `dotted-list?` | 1 | True if argument is a dotted (improper) list |
| `circular-list?` | 1 | True if argument is a circular list |
| `not-pair?` | 1 | True if argument is not a pair |
| `null-list?` | 1 | True if argument is the empty list (error on non-list) |
| `list=` | 2+ | Compare lists element-wise with a given equality predicate |
| `cons*` | 1+ | Like `list` but last arg is the tail |
| `xcons` | 2 | `(cons cdr car)` — reversed cons |
| `list-tabulate` | 2 | Build list of k elements from init procedure |
| `circular-list` | 1+ | Build a circular list from arguments |
| `first` | 1 | First element (same as `car`) |
| `second` | 1 | Second element |
| `third` | 1 | Third element |
| `fourth` | 1 | Fourth element |
| `fifth` | 1 | Fifth element |
| `sixth` | 1 | Sixth element |
| `seventh` | 1 | Seventh element |
| `eighth` | 1 | Eighth element |
| `ninth` | 1 | Ninth element |
| `tenth` | 1 | Tenth element |
| `car+cdr` | 1 | Return car and cdr as multiple values |
| `take-right` | 2 | Last k elements |
| `drop-right` | 2 | All but last k elements |
| `split-at` | 2 | Split list at index k into two values |
| `span` | 2 | Split list at first element not satisfying predicate |
| `break` | 2 | Split list at first element satisfying predicate |
| `unfold` | 4+ | Unfold a list from a seed value |
| `unfold-right` | 4+ | Unfold a list in reverse from a seed value |
| `pair-fold` | 3+ | Fold over pairs (not elements) |
| `pair-fold-right` | 3+ | Right fold over pairs |
| `pair-for-each` | 2+ | For-each over pairs |
| `map-in-order` | 2+ | Map with guaranteed left-to-right evaluation |
| `list-index` | 2+ | Index of first element satisfying predicate |
| `delete` | 2+ | Remove all occurrences equal to element |
| `delete-duplicates` | 1+ | Remove duplicate elements |
| `alist-cons` | 3 | `(cons (cons key value) alist)` |
| `alist-copy` | 1 | Shallow copy of an association list |
| `alist-delete` | 2+ | Remove entries with matching key |
| `lset=` | 2+ | Set equality |
| `lset-adjoin` | 2+ | Add elements to a set |
| `lset-union` | 2+ | Set union |
| `lset-intersection` | 2+ | Set intersection |
| `lset-difference` | 2+ | Set difference |
| `lset-xor` | 2+ | Set symmetric difference |
| `append-reverse` | 2 | `(append (reverse list1) list2)` |
| `length+` | 1 | Length or `#f` for circular lists |
| `unzip1` | 1 | Unzip list of lists (first elements) |
| `unzip2` | 1 | Unzip list of lists (first two elements as values) |

## CXR Compositions (3- and 4-level)

All 24 compositions of `car` and `cdr` up to four deep. Each takes exactly 1 argument.

| Procedure | Equivalent |
|-----------|------------|
| `caaar` | `(car (car (car x)))` |
| `caadr` | `(car (car (cdr x)))` |
| `cadar` | `(car (cdr (car x)))` |
| `caddr` | `(car (cdr (cdr x)))` |
| `cdaar` | `(cdr (car (car x)))` |
| `cdadr` | `(cdr (car (cdr x)))` |
| `cddar` | `(cdr (cdr (car x)))` |
| `cdddr` | `(cdr (cdr (cdr x)))` |
| `caaaar` | `(car (car (car (car x))))` |
| `caaadr` | `(car (car (car (cdr x))))` |
| `caadar` | `(car (car (cdr (car x))))` |
| `caaddr` | `(car (car (cdr (cdr x))))` |
| `cadaar` | `(car (cdr (car (car x))))` |
| `cadadr` | `(car (cdr (car (cdr x))))` |
| `caddar` | `(car (cdr (cdr (car x))))` |
| `cadddr` | `(car (cdr (cdr (cdr x))))` |
| `cdaaar` | `(cdr (car (car (car x))))` |
| `cdaadr` | `(cdr (car (car (cdr x))))` |
| `cdadar` | `(cdr (car (cdr (car x))))` |
| `cdaddr` | `(cdr (car (cdr (cdr x))))` |
| `cddaar` | `(cdr (cdr (car (car x))))` |
| `cddadr` | `(cdr (cdr (car (cdr x))))` |
| `cdddar` | `(cdr (cdr (cdr (car x))))` |
| `cddddr` | `(cdr (cdr (cdr (cdr x))))` |

## Strings

| Procedure | Arity | Description |
|-----------|-------|-------------|
| `string` | 0+ | Construct string from characters |
| `make-string` | 1+ | Create string of k characters (optional fill char) |
| `string-length` | 1 | Number of codepoints in string |
| `string-ref` | 2 | Character at codepoint index k |
| `string-set!` | 3 | Set character at codepoint index k |
| `substring` | 3 | Extract substring by codepoint indices |
| `string-append` | 0+ | Concatenate strings |
| `string-copy` | 1+ | Copy string (optional start and end) |
| `string-copy!` | 3+ | Copy into mutable string at offset |
| `string-fill!` | 2+ | Fill string with a character (optional start/end) |
| `string->list` | 1+ | Convert string to list of characters |
| `list->string` | 1 | Convert list of characters to string |
| `string->symbol` | 1 | Intern string as a symbol |
| `symbol->string` | 1 | Symbol name as a string |
| `string->utf8` | 1 | Convert string to UTF-8 bytevector |
| `utf8->string` | 1 | Convert UTF-8 bytevector to string |
| `string->vector` | 1+ | Convert string to vector of characters |
| `string->number` | 1+ | Parse string as number (optional radix) |
| `number->string` | 1 | Convert number to string |
| `string-for-each` | 2+ | Apply procedure to each character |
| `string-map` | 2+ | Map procedure over characters |
| `string<?` | 2+ | Lexicographic less-than |
| `string<=?` | 2+ | Lexicographic less-than-or-equal |
| `string=?` | 2+ | String equality |
| `string>=?` | 2+ | Lexicographic greater-than-or-equal |
| `string>?` | 2+ | Lexicographic greater-than |

### SRFI-13 String Extensions

| Procedure | Arity | Description |
|-----------|-------|-------------|
| `string-contains` | 2 | Index of first occurrence of substring, or `#f` |
| `string-prefix?` | 2 | True if first string is a prefix of second |
| `string-suffix?` | 2 | True if first string is a suffix of second |
| `string-trim` | 1+ | Remove leading whitespace (optional predicate) |
| `string-trim-right` | 1+ | Remove trailing whitespace (optional predicate) |
| `string-trim-both` | 1+ | Remove leading and trailing whitespace (optional predicate) |
| `string-index` | 2 | Index of first char satisfying predicate, or `#f` |
| `string-count` | 2 | Count characters satisfying predicate |
| `string-split` | 2 | Split string by delimiter string |
| `string-join` | 1+ | Join list of strings with delimiter |
| `string-concatenate` | 1 | Concatenate a list of strings |

## Characters

| Procedure | Arity | Description |
|-----------|-------|-------------|
| `char->integer` | 1 | Unicode codepoint as integer |
| `integer->char` | 1 | Character from Unicode codepoint |
| `char<?` | 2+ | Character less-than by codepoint |
| `char<=?` | 2+ | Character less-than-or-equal |
| `char=?` | 2+ | Character equality |
| `char>=?` | 2+ | Character greater-than-or-equal |
| `char>?` | 2+ | Character greater-than |
| `char-alphabetic?` | 1 | True if Unicode alphabetic |
| `char-numeric?` | 1 | True if Unicode numeric |
| `char-whitespace?` | 1 | True if Unicode whitespace |
| `char-upper-case?` | 1 | True if Unicode uppercase |
| `char-lower-case?` | 1 | True if Unicode lowercase |
| `char-upcase` | 1 | Convert to uppercase |
| `char-downcase` | 1 | Convert to lowercase |
| `char-foldcase` | 1 | Convert to foldcase (for case-insensitive comparison) |
| `digit-value` | 1 | Numeric value of digit character, or `#f` |

### Case-Insensitive Comparisons

| Procedure | Arity | Description |
|-----------|-------|-------------|
| `char-ci<?` | 2+ | Case-insensitive character less-than |
| `char-ci<=?` | 2+ | Case-insensitive character less-than-or-equal |
| `char-ci=?` | 2+ | Case-insensitive character equality |
| `char-ci>=?` | 2+ | Case-insensitive character greater-than-or-equal |
| `char-ci>?` | 2+ | Case-insensitive character greater-than |
| `string-ci<?` | 2+ | Case-insensitive string less-than |
| `string-ci<=?` | 2+ | Case-insensitive string less-than-or-equal |
| `string-ci=?` | 2+ | Case-insensitive string equality |
| `string-ci>=?` | 2+ | Case-insensitive string greater-than-or-equal |
| `string-ci>?` | 2+ | Case-insensitive string greater-than |
| `string-upcase` | 1 | Convert entire string to uppercase |
| `string-downcase` | 1 | Convert entire string to lowercase |
| `string-foldcase` | 1 | Foldcase entire string |

## Vectors

| Procedure | Arity | Description |
|-----------|-------|-------------|
| `vector` | 0+ | Construct vector from arguments |
| `make-vector` | 1+ | Create vector of k elements (optional fill value) |
| `vector?` | 1 | True if argument is a vector |
| `vector-length` | 1 | Number of elements |
| `vector-ref` | 2 | Element at index k |
| `vector-set!` | 3 | Set element at index k |
| `vector->list` | 1+ | Convert to list (optional start and end) |
| `list->vector` | 1 | Convert list to vector |
| `vector->string` | 1 | Convert vector of characters to string |
| `vector-fill!` | 2 | Fill vector with a value |
| `vector-copy` | 1+ | Copy vector (optional start and end) |
| `vector-copy!` | 3+ | Copy into vector at offset |
| `vector-append` | 0+ | Concatenate vectors |
| `vector-for-each` | 2+ | Apply procedure to each element |
| `vector-map` | 2+ | Map procedure over elements |

## Bytevectors

| Procedure | Arity | Description |
|-----------|-------|-------------|
| `bytevector?` | 1 | True if argument is a bytevector |
| `make-bytevector` | 1+ | Create bytevector of k bytes (optional fill) |
| `bytevector` | 0+ | Construct bytevector from byte values |
| `bytevector-length` | 1 | Number of bytes |
| `bytevector-u8-ref` | 2 | Byte at index k |
| `bytevector-u8-set!` | 3 | Set byte at index k |
| `bytevector-copy` | 1+ | Copy bytevector (optional start and end) |
| `bytevector-copy!` | 3+ | Copy into bytevector at offset |
| `bytevector-append` | 0+ | Concatenate bytevectors |
| `utf8->string` | 1+ | Decode UTF-8 bytevector to string |
| `string->utf8` | 1+ | Encode string to UTF-8 bytevector |

### Binary I/O

| Procedure | Arity | Description |
|-----------|-------|-------------|
| `read-u8` | 0+ | Read one byte from port |
| `peek-u8` | 0+ | Peek at next byte without consuming |
| `write-u8` | 1+ | Write one byte to port |
| `u8-ready?` | 0+ | True if a byte is available to read |
| `read-bytevector` | 1+ | Read k bytes into a new bytevector |
| `read-bytevector!` | 1+ | Read bytes into an existing bytevector |
| `write-bytevector` | 1+ | Write bytevector to port |
| `open-input-bytevector` | 1 | Open bytevector as input port |
| `open-output-bytevector` | 0 | Create output port backed by bytevector |
| `get-output-bytevector` | 1 | Get accumulated bytevector from output port |

## Ports and I/O

### Port Operations

| Procedure | Arity | Description |
|-----------|-------|-------------|
| `current-input-port` | 0 | Current default input port (stdin) |
| `current-output-port` | 0 | Current default output port (stdout) |
| `current-error-port` | 0 | Current default error port (stderr) |
| `port?` | 1 | True if argument is a port |
| `input-port?` | 1 | True if port supports input |
| `output-port?` | 1 | True if port supports output |
| `textual-port?` | 1 | True if port is textual |
| `binary-port?` | 1 | True if port is binary |
| `input-port-open?` | 1 | True if input port is open |
| `output-port-open?` | 1 | True if output port is open |

### File I/O

| Procedure | Arity | Description |
|-----------|-------|-------------|
| `open-input-file` | 1 | Open file for textual input |
| `open-output-file` | 1 | Open file for textual output |
| `open-binary-input-file` | 1 | Open file for binary input |
| `open-binary-output-file` | 1 | Open file for binary output |
| `close-port` | 1 | Close a port |
| `close-input-port` | 1 | Close an input port |
| `close-output-port` | 1 | Close an output port |
| `file-exists?` | 1 | True if file exists at path |
| `delete-file` | 1 | Delete a file |
| `call-with-input-file` | 2 | Open file, call proc, close file |
| `call-with-output-file` | 2 | Open file, call proc, close file |
| `call-with-port` | 2 | Call proc with port, close port when done |
| `with-input-from-file` | 2 | Parameterize current-input-port for proc |
| `with-output-to-file` | 2 | Parameterize current-output-port for proc |

### Textual I/O

| Procedure | Arity | Description |
|-----------|-------|-------------|
| `read` | 0+ | Read a Scheme datum from port |
| `read-char` | 0+ | Read one character |
| `peek-char` | 0+ | Peek at next character without consuming |
| `read-line` | 0+ | Read a line as a string |
| `read-string` | 1+ | Read k characters as a string |
| `char-ready?` | 0+ | True if a character is available to read |
| `display` | 1+ | Write value in human-readable form |
| `write` | 1+ | Write value in machine-readable form (with quotes) |
| `write-shared` | 1+ | Write with datum labels for shared structure |
| `write-simple` | 1+ | Write without datum labels |
| `write-char` | 1+ | Write a single character |
| `write-string` | 1+ | Write a string (or substring) |
| `newline` | 0+ | Write a newline character |
| `flush-output-port` | 0+ | Flush output port buffer |

### String Ports

| Procedure | Arity | Description |
|-----------|-------|-------------|
| `open-input-string` | 1 | Open string as input port |
| `open-output-string` | 0 | Create output port backed by string |
| `get-output-string` | 1 | Get accumulated string from output port |
| `eof-object?` | 1 | True if argument is the EOF object |
| `eof-object` | 0 | Return the EOF object |

## Control Flow

| Procedure | Arity | Description |
|-----------|-------|-------------|
| `apply` | 2+ | Apply procedure to arguments |
| `call-with-current-continuation` | 1 | Capture the current continuation |
| `call/cc` | 1 | Alias for `call-with-current-continuation` |
| `call-with-escape-continuation` | 1 | Capture a one-shot escape continuation |
| `call/ec` | 1 | Alias for `call-with-escape-continuation` |
| `dynamic-wind` | 3 | Install before/after thunks around a body |
| `values` | 0+ | Return multiple values |
| `call-with-values` | 2 | Pass multiple values from producer to consumer |

### Exceptions

| Procedure | Arity | Description |
|-----------|-------|-------------|
| `raise` | 1 | Raise an exception |
| `raise-continuable` | 1 | Raise a continuable exception |
| `with-exception-handler` | 2 | Install an exception handler |
| `error` | 1+ | Create error object and raise it |
| `error-object?` | 1 | True if argument is an error object |
| `error-object-message` | 1 | Error message string |
| `error-object-irritants` | 1 | List of irritant values from error |
| `file-error?` | 1 | True if error is a file error |
| `read-error?` | 1 | True if error is a read error |

## Boolean and Equivalence

| Procedure | Arity | Description |
|-----------|-------|-------------|
| `not` | 1 | Boolean negation |
| `boolean=?` | 2+ | True if all arguments are the same boolean |
| `eq?` | 2 | Pointer identity |
| `eqv?` | 2 | Value equivalence (numbers, chars, booleans) |
| `equal?` | 2 | Deep structural equality |
| `symbol=?` | 2+ | True if all arguments are the same symbol |

## Type Predicates

| Procedure | Arity | Description |
|-----------|-------|-------------|
| `pair?` | 1 | True if argument is a pair |
| `null?` | 1 | True if argument is the empty list |
| `number?` | 1 | True if argument is a number |
| `integer?` | 1 | True if argument is an integer |
| `real?` | 1 | True if argument is a real number |
| `complex?` | 1 | True if argument is a complex number |
| `rational?` | 1 | True if argument is rational |
| `symbol?` | 1 | True if argument is a symbol |
| `string?` | 1 | True if argument is a string |
| `boolean?` | 1 | True if argument is a boolean |
| `char?` | 1 | True if argument is a character |
| `procedure?` | 1 | True if argument is a procedure |
| `list?` | 1 | True if argument is a proper list |
| `vector?` | 1 | True if argument is a vector |
| `bytevector?` | 1 | True if argument is a bytevector |
| `port?` | 1 | True if argument is a port |
| `hash-table?` | 1 | True if argument is a hash table |
| `promise?` | 1 | True if argument is a promise |
| `error-object?` | 1 | True if argument is an error object |

## Lazy Evaluation

| Procedure | Arity | Description |
|-----------|-------|-------------|
| `promise?` | 1 | True if argument is a promise |
| `make-promise` | 1 | Wrap a value as an already-forced promise |
| `force` | 1 | Force a promise, memoizing the result |

Note: `delay` and `delay-force` are syntax forms, not procedures.

## Records (Internal Primitives)

These are used by the `define-record-type` syntax form. Users normally do not
call them directly.

| Procedure | Arity | Description |
|-----------|-------|-------------|
| `%make-record-type` | 2 | Create a record type descriptor |
| `%make-record` | 1+ | Construct a record instance |
| `%record?` | 2 | Check if value is instance of record type |
| `%record-ref` | 2 | Access field by index |
| `%record-set!` | 3 | Mutate field by index |

## Hash Tables (SRFI-69)

| Procedure | Arity | Description |
|-----------|-------|-------------|
| `make-hash-table` | 0+ | Create a new hash table |
| `hash-table?` | 1 | True if argument is a hash table |
| `hash-table-ref` | 2+ | Look up key (optional default value) |
| `hash-table-set!` | 3 | Associate key with value |
| `hash-table-delete!` | 2 | Remove key |
| `hash-table-exists?` | 2 | True if key is present |
| `hash-table-size` | 1 | Number of key-value pairs |
| `hash-table-keys` | 1 | List of all keys |
| `hash-table-values` | 1 | List of all values |
| `hash-table-walk` | 2 | Call procedure on each key-value pair |
| `hash-table->alist` | 1 | Convert to association list |
| `alist->hash-table` | 1 | Convert association list to hash table |
| `hash-table-copy` | 1 | Shallow copy of hash table |
| `hash-table-update!/default` | 4 | Update value for key using procedure, with default |

## Random Numbers (SRFI-27)

| Procedure | Arity | Description |
|-----------|-------|-------------|
| `random-integer` | 1 | Random integer in [0, n) |
| `random-real` | 0 | Random real in [0, 1) |

## FFI (Foreign Function Interface)

| Procedure | Arity | Description |
|-----------|-------|-------------|
| `ffi-open` | 1 | Open a shared library by path |
| `ffi-fn` | 4 | Bind a C function: `(ffi-fn lib "name" '(param-types) 'return-type)` |
| `ffi-close` | 1 | Close a shared library handle |

## System and Environment

| Procedure | Arity | Description |
|-----------|-------|-------------|
| `exit` | 0+ | Exit the process (optional status code) |
| `emergency-exit` | 0+ | Immediate exit without cleanup |
| `command-line` | 0 | List of command-line arguments |
| `get-environment-variable` | 1 | Value of environment variable, or `#f` |
| `get-environment-variables` | 0 | Association list of all environment variables |
| `current-second` | 0 | Current TAI time as inexact real |
| `current-jiffy` | 0 | Current time in jiffies (high resolution) |
| `jiffies-per-second` | 0 | Number of jiffies per second |
| `features` | 0 | List of implementation feature identifiers |
| `eval` | 1+ | Evaluate expression in an environment |
| `environment` | 0+ | Create environment from library imports |
| `interaction-environment` | 0 | REPL environment with all bindings |
| `load` | 1 | Load and evaluate a Scheme source file |
| `make-parameter` | 1+ | Create a parameter object (optional converter) |

## Syntax Forms (Not Procedures)

These are handled by the compiler, not the procedure dispatch. They are listed
here for completeness.

| Form | Description |
|------|-------------|
| `define` | Variable and function definition |
| `lambda` | Anonymous function |
| `if` | Conditional |
| `quote` | Literal datum |
| `set!` | Variable mutation |
| `begin` | Sequence of expressions |
| `cond` | Multi-branch conditional |
| `case` | Dispatch on datum equality |
| `and` | Short-circuit logical and |
| `or` | Short-circuit logical or |
| `when` | One-armed conditional with implicit begin |
| `unless` | Negated one-armed conditional |
| `let` | Local bindings |
| `let*` | Sequential local bindings |
| `letrec` | Mutually recursive bindings |
| `letrec*` | Sequential mutually recursive bindings |
| `let-values` | Destructure multiple values |
| `let*-values` | Sequential destructure multiple values |
| `do` | Iteration with step expressions |
| `case-lambda` | Arity-dispatched lambda |
| `define-syntax` | Define a macro |
| `syntax-rules` | Pattern-based macro transformer |
| `let-syntax` | Local macro bindings |
| `letrec-syntax` | Mutually recursive local macro bindings |
| `quasiquote` | Template with unquote and unquote-splicing |
| `define-record-type` | Define a record type |
| `define-library` | Define a library |
| `import` | Import library bindings |
| `guard` | Exception handling with cond clauses |
| `delay` | Create a promise (lazy thunk) |
| `delay-force` | Create an iterative promise |
| `parameterize` | Dynamically bind parameters |
| `cond-expand` | Feature-based conditional expansion |

## SRFI-13 String Library

| Procedure | Arity | Description |
|-----------|-------|-------------|
| `string-contains` | 2+ | Index of substring in string, or `#f` (optional start/end) |
| `string-prefix?` | 2+ | True if first string is a prefix of second (optional start/end) |
| `string-suffix?` | 2+ | True if first string is a suffix of second (optional start/end) |
| `string-index` | 2+ | Index of first char satisfying predicate/char-set (optional start/end) |
| `string-index-right` | 2+ | Index of last char satisfying predicate/char-set (optional start/end) |
| `string-skip` | 2+ | Index of first char NOT satisfying predicate/char-set (optional start/end) |
| `string-skip-right` | 2+ | Index of last char NOT satisfying predicate/char-set (optional start/end) |
| `string-count` | 2+ | Count chars satisfying predicate/char-set (optional start/end) |
| `string-trim` | 1+ | Remove leading chars matching predicate/char-set (optional start/end) |
| `string-trim-right` | 1+ | Remove trailing chars matching predicate/char-set (optional start/end) |
| `string-trim-both` | 1+ | Remove leading and trailing chars (optional start/end) |
| `string-split` | 2 | Split string by delimiter into list of strings |
| `string-join` | 1+ | Join list of strings with delimiter |
| `string-concatenate` | 1 | Concatenate a list of strings |
| `string-take` | 2 | First k characters |
| `string-drop` | 2 | All but first k characters |
| `string-take-right` | 2 | Last k characters |
| `string-drop-right` | 2 | All but last k characters |
| `string-pad` | 2+ | Pad string on the left to given length |
| `string-pad-right` | 2+ | Pad string on the right to given length |
| `string-reverse` | 1+ | Reverse a string (optional start/end) |
| `string-filter` | 2+ | Keep chars satisfying predicate/char-set (optional start/end) |
| `string-delete` | 2+ | Remove chars satisfying predicate/char-set (optional start/end) |
| `string-replace` | 4 | Replace substring by codepoint indices |
| `string-titlecase` | 1+ | Titlecase a string (optional start/end) |
| `string-every` | 2+ | True if predicate/char-set matches every char (optional start/end) |
| `string-any` | 2+ | True if predicate/char-set matches any char (optional start/end) |
| `string-tabulate` | 2 | Build string from index→char procedure |
| `string-unfold` | 4+ | Unfold a string from a seed |
| `string-unfold-right` | 4+ | Unfold a string in reverse from a seed |

## SRFI-133 Vector Library

| Procedure | Arity | Description |
|-----------|-------|-------------|
| `vector-unfold` | 2+ | Build vector from seed function |
| `vector-unfold-right` | 2+ | Build vector in reverse from seed function |
| `vector-concatenate` | 1 | Concatenate a list of vectors |
| `vector-any` | 2+ | True if predicate holds for any element |
| `vector-every` | 2+ | True if predicate holds for every element |
| `vector-index` | 2+ | Index of first element satisfying predicate |
| `vector-index-right` | 2+ | Index of last element satisfying predicate |
| `vector-skip` | 2+ | Index of first element NOT satisfying predicate |
| `vector-skip-right` | 2+ | Index of last element NOT satisfying predicate |
| `vector-binary-search` | 3 | Binary search with comparator |
| `vector-swap!` | 3 | Swap two elements by index |
| `vector-reverse!` | 1+ | Reverse vector in place (optional start/end) |
| `vector-reverse-copy` | 1+ | Reversed copy (optional start/end) |
| `vector-cumulate` | 3 | Cumulative fold into new vector |
| `vector-partition` | 2 | Partition by predicate into two vectors |
| `vector-count` | 2+ | Count elements satisfying predicate |
| `vector-fold` | 3+ | Left fold over vector |
| `vector-fold-right` | 3+ | Right fold over vector |
| `vector-map!` | 2+ | In-place map |
| `vector-empty?` | 1 | True if vector has zero length |
| `vector=` | 3 | Element-wise equality with comparator |

## SRFI-18 Threads

| Procedure | Arity | Description |
|-----------|-------|-------------|
| `current-thread` | 0 | Current thread object |
| `thread?` | 1 | True if argument is a thread |
| `make-thread` | 1+ | Create a new thread (thunk, optional name) |
| `thread-name` | 1 | Thread's name |
| `thread-specific` | 1 | Thread's specific value |
| `thread-specific-set!` | 2 | Set thread's specific value |
| `thread-start!` | 1 | Start a thread |
| `thread-yield!` | 0 | Yield to the scheduler |
| `thread-sleep!` | 1 | Sleep for a duration |
| `thread-terminate!` | 1 | Terminate a thread |
| `thread-join!` | 1+ | Wait for thread completion (optional timeout) |
| `mutex?` | 1 | True if argument is a mutex |
| `make-mutex` | 0+ | Create a mutex (optional name) |
| `mutex-name` | 1 | Mutex name |
| `mutex-specific` | 1 | Mutex specific value |
| `mutex-specific-set!` | 2 | Set mutex specific value |
| `mutex-state` | 1 | Mutex state (locked/unlocked/owner) |
| `mutex-lock!` | 1+ | Lock a mutex (optional timeout/thread) |
| `mutex-unlock!` | 1+ | Unlock a mutex (optional condition variable/timeout) |
| `condition-variable?` | 1 | True if argument is a condition variable |
| `make-condition-variable` | 0+ | Create a condition variable (optional name) |
| `condition-variable-name` | 1 | Condition variable name |
| `condition-variable-specific` | 1 | Condition variable specific value |
| `condition-variable-specific-set!` | 2 | Set condition variable specific value |
| `condition-variable-signal!` | 1 | Wake one waiting thread |
| `condition-variable-broadcast!` | 1 | Wake all waiting threads |
| `current-time` | 0 | Current time as time object |
| `time?` | 1 | True if argument is a time object |
| `time->seconds` | 1 | Convert time to seconds |
| `seconds->time` | 1 | Convert seconds to time |
| `join-timeout-exception?` | 1 | True if exception is a join timeout |
| `abandoned-mutex-exception?` | 1 | True if exception is an abandoned mutex |
| `terminated-thread-exception?` | 1 | True if exception is a terminated thread |
| `uncaught-exception?` | 1 | True if exception is an uncaught exception |
| `uncaught-exception-reason` | 1 | Get the reason from an uncaught exception |

## Green Threads (Fibers)

| Procedure | Arity | Description |
|-----------|-------|-------------|
| `spawn` | 1 | Create and start a fiber running a thunk |
| `yield` | 0 | Yield to the fiber scheduler |
| `fiber?` | 1 | True if argument is a fiber |
| `fiber-join` | 1 | Wait for fiber completion, return its result |
| `make-channel` | 0 | Create a new channel |
| `channel-send` | 2 | Send a value on a channel |
| `channel-receive` | 1 | Receive a value from a channel |
| `channel?` | 1 | True if argument is a channel |

## SRFI-170 Filesystem

| Procedure | Arity | Description |
|-----------|-------|-------------|
| `file-info` | 1+ | Get file metadata (optional follow-symlinks?) |
| `file-info?` | 1 | True if argument is a file-info object |
| `file-info-type` | 1 | File type as symbol (regular, directory, symlink, ...) |
| `file-info:size` | 1 | File size in bytes |
| `file-info:mtime` | 1 | Modification time |
| `file-info:atime` | 1 | Access time |
| `file-info:ctime` | 1 | Status change time |
| `file-info:mode` | 1 | File permission mode |
| `file-info:nlinks` | 1 | Number of hard links |
| `file-info:uid` | 1 | Owner user ID |
| `file-info:gid` | 1 | Owner group ID |
| `file-info:inode` | 1 | Inode number |
| `file-info:device` | 1 | Device ID |
| `file-info:blksize` | 1 | Block size |
| `file-info:blocks` | 1 | Number of blocks |
| `file-info-directory?` | 1 | True if file is a directory |
| `file-info-regular?` | 1 | True if file is a regular file |
| `file-info-symlink?` | 1 | True if file is a symlink |
| `file-info-fifo?` | 1 | True if file is a FIFO |
| `file-info-socket?` | 1 | True if file is a socket |
| `file-info-device?` | 1 | True if file is a device |
| `create-directory` | 1+ | Create a directory (optional mode) |
| `delete-directory` | 1 | Delete a directory |
| `rename-file` | 2 | Rename a file |
| `create-symlink` | 2 | Create a symbolic link |
| `read-symlink` | 1 | Read the target of a symbolic link |
| `create-hard-link` | 2 | Create a hard link |
| `real-path` | 1 | Resolve to canonical absolute path |
| `set-file-mode` | 2 | Set file permissions |
| `truncate-file` | 2 | Truncate file to given length |
| `create-fifo` | 1+ | Create a named pipe (optional mode) |
| `set-file-owner` | 3 | Set file owner (uid, gid) |
| `set-file-times` | 3 | Set access and modification times |
| `directory-files` | 1+ | List files in a directory |
| `open-directory` | 1 | Open a directory stream |
| `read-directory` | 1 | Read next entry from directory stream |
| `close-directory` | 1 | Close a directory stream |
| `pid` | 0 | Current process ID |
| `umask` | 0 | Current umask |
| `set-umask!` | 1 | Set umask |
| `current-directory` | 0 | Current working directory |
| `set-current-directory!` | 1 | Change working directory |
| `user-uid` | 0 | Current user ID |
| `user-gid` | 0 | Current group ID |
| `user-effective-uid` | 0 | Effective user ID |
| `user-effective-gid` | 0 | Effective group ID |
| `user-supplementary-gids` | 0 | Supplementary group IDs |
| `nice` | 1 | Adjust process priority |
| `set-environment-variable!` | 2 | Set an environment variable |
| `delete-environment-variable!` | 1 | Delete an environment variable |
| `terminal?` | 1 | True if port is connected to a terminal |
| `posix-time` | 0 | Current time as seconds since epoch |
| `monotonic-time` | 0 | Monotonic clock time |
| `temp-file-prefix` | 0 | Default temporary file prefix |
| `create-temp-file` | 0+ | Create a temporary file (optional prefix) |
