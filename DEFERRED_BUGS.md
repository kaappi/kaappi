# Deferred Bugs

Found during `/audit-primitives` systematic audit. Lower priority — none cause crashes, but each is a spec deviation or quality gap.

---

### 1. `write-bytevector` ignores optional start/end arguments

**File:** `src/primitives_io.zig` lines 859-865

**Spec:** R7RS 6.13.3 — `(write-bytevector bytevector [port [start [end]]])`

**Behavior:** Always writes the entire bytevector regardless of start/end args.

**Fix:** Parse `args[2]` (start) and `args[3]` (end) when present, slice `bv.data[start..end]` before writing.

---

### 2. `textual-port?` returns `#t` for binary-only ports

**File:** `src/primitives_io.zig` lines 269-271

**Spec:** R7RS 6.13.1 — `textual-port?` should return `#f` for ports opened with `open-binary-input-file` / `open-binary-output-file`.

**Behavior:** Returns `#t` unconditionally for all ports.

**Fix:** Check the port's `is_binary` flag (if it exists) or track the port mode at open time.

---

### 3. `random-source-state-ref`/`state-set!` only saves one word of PRNG state

**File:** `src/primitives_random.zig` lines 93-103

**Spec:** SRFI-27 — state-ref/state-set! must faithfully save and restore the full generator state.

**Behavior:** Only saves `s[0]` of the xoshiro256 state (which has 4 × u64 words). A ref/set! roundtrip corrupts the generator — subsequent random values differ from what they would have been.

**Fix:** Save all 4 state words, e.g. as a list of fixnums or a bytevector. Restore all 4 on `state-set!`.

---

### 4. `interaction-environment` returns `#t` instead of an environment specifier

**File:** `src/primitives_r7rs.zig` line 284

**Spec:** R7RS 6.12 — must return an environment specifier usable with `eval`.

**Behavior:** Returns `types.TRUE`. Works accidentally because `eval` ignores its environment argument when it matches the interaction environment, but `(environment? (interaction-environment))` would be wrong if `environment?` existed.

**Fix:** Define an environment type tag or return a sentinel value that `eval` recognizes.

---

### 5. `ffi-open` gives uninformative error on missing library

**File:** `src/primitives_ffi.zig` line 56

**Behavior:** Returns `PrimitiveError.TypeError` with no detail when `dlopen` fails. User sees "type error" instead of the actual `dlerror()` message (e.g., "image not found").

**Fix:** Call `std.c.dlerror()` and pass the message to `vm.setErrorDetail`.

---

### 6. `ffi-fn` gives uninformative error on missing symbol

**File:** `src/primitives_ffi.zig` line 80

**Behavior:** Same as above — `dlsym` failure returns generic TypeError.

**Fix:** Same approach — include `dlerror()` message in the error detail.

---

### 7. `string-ci-hash` only lowercases ASCII

**File:** `src/primitives_string_ext.zig` lines 359-375

**Spec:** SRFI-69 — case-insensitive hash should use Unicode case folding.

**Behavior:** Only folds ASCII A-Z to lowercase. Non-ASCII uppercase letters (é vs É, ñ vs Ñ) produce different hashes.

**Fix:** Apply `char-foldcase` (Unicode-aware) to each codepoint before hashing, not just ASCII tolower.

---

### 8. `load` raises TypeError instead of file-error

**File:** `src/primitives_r7rs.zig` line 199

**Spec:** R7RS 6.14 — `load` should raise a condition satisfying `file-error?` when the file cannot be opened.

**Behavior:** Returns `PrimitiveError.TypeError`. The error message was improved to include the filename, but `file-error?` on the resulting error object returns `#f`.

**Fix:** Add `FileError` to `PrimitiveError` enum, handle it in `vm.zig` to create an error object with the file-error type flag, and return it from `load`.
