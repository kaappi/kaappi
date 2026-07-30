window.BENCHMARK_DATA = {
  "lastUpdate": 1785437292079,
  "repoUrl": "https://github.com/kaappi/kaappi",
  "entries": {
    "Benchmark": [
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "860beb34eff127508a063d565c66814138ebf7f7",
          "message": "Add 12 SRFI libraries, exclude 2, defer 1 (SRFI Phase 3) (#1728)\n\n* Add SRFI 30 and SRFI 62 wrapper libraries\n\nBoth are already-implemented R7RS reader syntax (nested block comments\nand datum comments); these are thin marker libraries with no exports\nso (import (srfi 30)) / (import (srfi 62)) succeed.\n\n* Add SRFI 169 (Underscores in numbers) and SRFI 270 (Hex float constants)\n\nBoth are genuine reader/lexer changes, not portable libraries:\n\n- SRFI 270: #x1.2p3-style hex float syntax in readIntegerWithRadix/\n  readHexFloatSuffix (reader_tokens.zig), sharing digit decoding with\n  string->number via bignum.parseHexFloat (bignum.zig), since the spec\n  requires string->number to also understand this syntax. The one new\n  procedure the spec adds, write-hexadecimal-float, is fully portable\n  (lib/srfi/270.sld) -- exact rational arithmetic via (exact x) gives a\n  flonum's precise value without needing raw bit access, so it round-trips\n  bit-exactly including subnormals, signed zero, and complex numbers.\n\n- SRFI 169: a single underscore as a digit separator strictly between two\n  digits anywhere in a numeric literal, in any radix. The digit-scanning\n  loops across reader_tokens.zig (readNumber's mantissa/exponent/\n  imaginary-part loops, readIntegerWithRadix, scanDenominatorDigits,\n  SRFI 270's readHexFloatSuffix) now tolerate an embedded underscore\n  without stopping the scan early; actual validation and stripping is\n  centralized in bignum.stripUnderscores, called from parseDecimalReal,\n  parseHexFloat, parseBignumString, and directly before each remaining\n  parseInt call. Misplaced underscores (leading, trailing, doubled, or\n  adjacent to a sign/./exponent-marker//radix-prefix) are rejected, not\n  silently accepted or dropped.\n\nFiled #1724 for a small pre-existing, unrelated gap noticed along the\nway: string->number's small-integer path inherits Zig std.fmt.parseInt's\nown (more permissive) underscore tolerance, wrongly accepting \"1__2\" as\n12 -- not something either SRFI asks to fix, since neither touches\nstring->number's decimal-integer path by design.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* Add SRFI 70 (Numbers), excluding its incompatible NaN-comparison clause\n\nSRFI 70 predates R7RS and argues that 0/0 (NaN) should be an illegal\nargument to <, <=, >, >= rather than silently comparing false. R7RS\nlater overrode that stance explicitly (\"all the predicates return #f\"\non +nan.0), and Kaappi already implements the R7RS rule throughout its\narithmetic, so this port deliberately omits that clause and does not\ntouch =, <, <=, >, >= at all.\n\nWhat's implemented as a pure .sld wrapper (no engine changes): the four\nnew exact-floor/exact-ceiling/exact-truncate/exact-round convenience\nprocedures, and shadowed quotient/remainder/modulo/gcd/lcm/expt that\nextend their domain to exact rationals (quotient/remainder/modulo also\ninherit Kaappi's existing inexact-real support) and fix `(expt 0 n)`\nfor negative exact n to return +inf.0 instead of raising a\ndivision-by-zero error, while leaving inexact +/-0.0's existing\nIEEE-signed behavior untouched. Every case is verified against SRFI\n70's own worked examples and reference implementation.\n\n* Add SRFI 29 (Localization)\n\nMessage-bundle localization: declare-bundle!/localized-template with the\nspec's exact locale fallback (package+language+country -> +language ->\npackage-only), current-language/current-country/current-locale-details\naccessors, and best-effort store-bundle!/load-bundle! persistence via\n(scheme file) + SRFI 170's temp-file-prefix. Also exports a format that\nextends (srfi 28)'s directives with SRFI 29's ~N@* absolute positional\nreference, needed for translations that reorder arguments.\n\nResolves two spec inconsistencies (documented in the file header): the\nSpecification section's signature heading spells the store procedure\n\"store-bundle\" but every other occurrence including the reference\nimplementation uses \"store-bundle!\", used here; and \"Bundle Searching\"\nsays an exhausted fallback should raise an error while\nlocalized-template's own procedure spec and reference implementation\nreturn #f, followed here.\n\nUpdates the SRFI count/list in CLAUDE.md, README.md, and CONFORMANCE.md\n(124 -> 125 portable, 137 -> 138 total).\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* Add SRFI 54 (Formatting) and SRFI 94 (Type-Restricted Numerical Functions)\n\nSRFI 54 implements `cat`, a free-sequence (type-directed, order-independent)\nstring formatter, ported from the spec's reference implementation with its\ncustom syntax-rules argument-parsing macros replaced by an equivalent\n`%cat-extract` function threaded through `let*-values` — easier to verify\nline-by-line against the spec's worked examples, nearly all of which are\nreproduced verbatim in the test suite.\n\nSRFI 94 adds thin type-checking wrappers (real-exp, real-ln, real-log,\nreal-sin/cos/tan/asin/acos/atan, real-sqrt, real-expt, integer-sqrt,\ninteger-expt, integer-log, quo, rem, mod, ln) around existing Kaappi\nprimitives. It deliberately does not re-export the spec's other seven\nsame-named replacements (abs, atan, make-rectangular, make-polar, quotient,\nremainder, modulo): four already satisfy the restriction natively, and the\nother three (quotient/remainder/modulo) would create an R7RS-ambiguous\nbinding against (scheme base) — see the .sld header for the full rationale.\n\nAlso documents a real gap found in `expt`: a negative real base with a\nnon-integer exponent (e.g. `(expt -8 1/3)`) returns +nan.0 instead of the\ncorrect complex result, unlike `sqrt` which handles negative reals properly.\nreal-expt's guard avoids this path entirely, matching the spec's own\nreference implementation.\n\nUpdates the SRFI count/list in CLAUDE.md, README.md, and CONFORMANCE.md\n(137->139 supported, 124->126 portable). Related but not closed: #1697 and\n#1700 each batch several other SRFIs alongside 54 and 94.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* Add SRFI 215 (Central Log Exchange)\n\nPortable (srfi 215): send-log plus the current-log-fields and\ncurrent-log-callback parameters, matching the spec's \"one procedure,\ntwo parameters, eight constants\" surface exactly (EMERGENCY..DEBUG,\n0-7). current-log-callback is a single dynamically-scoped slot with no\nregister/unregister API, per spec -- installed via parameterize or a\ndirect call, exactly like current-output-port. Its default value\nbuffers messages until a real callback replaces it, then flushes them\nin order via the parameter's converter (which Kaappi runs once per\nreplacement, never on parameterize's restore). Field values are\nwritten to a string unless already string?/bytevector?/exact-integer?/\nerror-object?; SEVERITY and MESSAGE are stored as given.\n\n44 SRFI-64 tests cover all eight severities, message structure,\nexplicit and ambient (current-log-fields) fields, value conversion,\nthe two spec-mandated error conditions, severity-based filtering\n(entirely the callback's own job, per spec), multiple receivers via a\nhand-rolled fan-out callback, and both forms of \"unregistering\" a\nreceiver. Full tests/scheme/run-all.sh suite (546 Scheme files + 1395\nR7RS tests) passes.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* Add SRFI 207 (String-notated bytevectors) and fix kaappi fmt for it\n\n#u8\"...\" is a genuine reader change (readByteStringLiteral in\nreader_tokens.zig, a deliberately separate function from the ordinary\nstring reader since the escape grammar and direct-character rules\ndiffer: direct characters must be printable ASCII, and \\xHH; decodes to\nexactly one raw byte 0-255, not a UTF-8-encoded codepoint). Also adds\nthe four procedures most directly tied to the notation itself\n(bytestring, bytevector->hex-string, hex-string->bytevector,\nwrite-textual-bytestring) -- the full spec defines ~25 procedures across\nan independent bytestring-processing library (padding, trimming,\nsearch, join/split, base64) that issue #1705 didn't scope in and this\nport doesn't implement, documented as a deliberate reduction in the\nlibrary's header.\n\nkaappi fmt has its own separate comment-preserving lexer (fmt.zig) that\ndidn't know about #u8\"...\" at all -- its scanHash only matched #u8( (the\nlist form), so #u8\"hello\" fell through to scanAtom, which stops at any\ndelimiter including '\"', splitting one token into two (\"#u8\" then a\nseparate string). Its own round-trip safety net correctly caught this\nas \"formatting would change the program\" rather than silently\ncorrupting anything, but it needed the actual fix: a new scanHash arm\nthat recognizes the #u8\" prefix and delegates to scanString's existing\nescape-aware boundary scanning (which only needs to find the real\nclosing quote, not decode escape semantics, so it works unchanged for\nthis different escape grammar).\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* Add SRFI 180 (JSON)\n\nPortable JSON reader/writer built on SRFI 158's generator/accumulator\nabstraction (already in this codebase, used by other ports like\n(srfi 225)): json-generator turns JSON text into a stream of events via\na coroutine generator over a recursive-descent parser, json-fold is a\ngeneric foldts-style iterator over that stream, json-accumulator is the\nwriter-side mirror, and json-read/json-write are the convenience\nport-based entry points most callers use.\n\nType mapping: null <-> the symbol 'null, true/false <-> #t/#f, array <->\nvector, object <-> an alist keyed by symbols. Numbers are read via a\nstrict RFC 8259 character-by-character grammar check before handing the\nvalidated substring to string->number, so exactness follows Kaappi's own\nnumeric-literal rules for free. Strings handle all short escapes plus\n\\uXXXX including UTF-16 surrogate pair combination, rejecting unescaped\ncontrol characters and unpaired surrogates per RFC 8259.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* Add SRFI 192 (Port Positioning)\n\nport-position, set-port-position!, port-has-port-position?, and\nport-has-set-port-position!? -- built-in (no lib/srfi/192.sld), gated\nbehind a new srfi_192 Lib tag. Positions are plain exact-integer byte\noffsets for every port kind; the spec's opaque \"implementation-dependent\nobject\" alternative for textual ports and the dedicated\ni/o-invalid-position-error condition type are not implemented (any\nfailure raises an ordinary error instead), documented in the primitives'\nown doc comments.\n\nString ports already tracked their own position for free (string_pos,\nstring_out_len). The real engine work is fd-backed ports: a new\nplatform.seek (POSIX lseek, Windows _lseeki64 -- wiring up a previously\ndead, unused extern -- and WASI fd_seek, which needs its own whence_t\nenum rather than a bare c_int, caught by the wasm32-wasi cross-compile\ncheck) plus correcting the OS's raw offset for whatever this port's own\nsoftware buffers have read ahead of (peek_byte, peek_extra, read_buf) or\nnot yet flushed behind (write_buf) -- otherwise position would silently\ndrift from what a subsequent read-then-position or position-then-read\npair expects. set-port-position! on an fd port discards the read-ahead\nbuffers (stale once the position jumps) and, per spec, flushes pending\nwrites first even when the position won't change.\n\nVerified: unit tests including a regression for the buffered-read-ahead\ncorrection and the flush-before-seek behavior; cross-compiled for\nwasm32-wasi, x86_64-windows, x86_64-linux, aarch64-macos.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* Reconcile SRFI counts and exclusions for Phase 3\n\n149 SRFIs supported (12 built-in, 135 portable, plus SRFI 261's\nresolver convention and SRFI 226's sub-library-only libraries), up from\n137/11/124 -- Phase 3 added 12 implemented SRFIs (29, 30, 54, 62, 70,\n94, 169, 180, 192, 207, 215, 270) and 2 newly-excluded ones (58, 208).\n\ndocs/dev/srfi-exclusions.md: added SRFI 58 (Array Notation) to the\nexisting \"Non-standard reader syntax\" category next to SRFI 163, which\nalready documents the identical typed-array-infrastructure blocker;\nadded a new \"Value-representation-dependent SRFIs\" category for SRFI\n208 (NaN procedures), whose bit-level NaN introspection Kaappi's\nNaN-boxing value representation makes categorically unrepresentable,\nnot merely unimplemented. 18 excluded SRFIs -> 20.\n\nCONFORMANCE.md: added a detailed coverage section for the newly\nbuilt-in SRFI 192, and table rows plus reduced-scope footnote entries\nfor the newly portable SRFIs (70 and 207 ship a reduced scope; the\nother 10 are full implementations).\n\nAlso fixes a small inconsistency from three independent contributors\n(two background agents plus this integration pass) each partially\nupdating the same dense count paragraph in CLAUDE.md -- rewritten once,\ncompletely, from kaappi features --json's authoritative output rather\nthan merging partial edits.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* Address CodeRabbit review findings on PR #1728\n\nVerified each finding directly against current code (and spec text via\nindependent WebFetch where the finding hinged on spec interpretation)\nbefore fixing or declining, per established project practice.\n\nFixed (7 genuine bugs):\n\n- string->number: a hex float whose mantissa overflows i64 (radix 16)\n  fell into the plain-integer overflow fallback, which doesn't\n  understand '.'/'p' and wrongly returned #f. Check for hex-float\n  syntax before attempting the plain-integer parse.\n- bignum.parseHexFloat: a pathologically long exponent digit run\n  overflowed the i32 accumulator and panicked (a real crash) in the\n  default ReleaseSafe build. Cap accumulation; any exponent magnitude\n  this large already saturates to +inf.0/0.0 regardless.\n- port-position/set-port-position!/port-has-port-position?: didn't\n  check is_open, so a closed port's stale fd (reused by the OS for an\n  unrelated file) could be silently repositioned or reported as valid.\n- set-port-position!: discarded read-ahead/peek buffers before the\n  underlying seek was confirmed to succeed; reorder to discard only on\n  success.\n- Output string ports: set-port-position! plus a shorter write\n  truncated everything after the write instead of overwriting in\n  place, unlike a seekable fd-backed port's OS-provided lseek+write\n  semantics. Added a write-cursor (string_out_pos) independent of the\n  buffer's total extent (string_out_len).\n- SRFI 215 current-log-callback: the converter flushed buffered\n  messages in one pass, but proc isn't actually current yet while its\n  own flush runs -- a message proc sent reentrantly via send-log\n  landed back in the buffer and was stranded until some unrelated\n  future callback replacement. Loop the flush until the buffer is dry.\n  Confirmed by repro before fixing.\n- SRFI 215 current-log-callback: an invalid (non-procedure) argument\n  cleared the buffer before attempting to use it, permanently losing\n  already-buffered messages even though the install itself failed.\n  Validate proc before touching the buffer.\n\nFixed (1 real but narrower issue, given a more robust fix than the\nminimal one needed):\n\n- SRFI 215's default buffering callback grew without limit before any\n  real callback was ever installed. The spec permits any\n  \"implementation-defined number\" with no stated overflow behavior, and\n  the original unbounded choice was a deliberate, documented reading of\n  that clause -- but a program whose only SRFI-215 user is a dependency\n  that logs routinely, and which never itself installs a callback,\n  would leak memory for its entire run. Capped the buffer, dropping the\n  oldest half at once when full (O(1) amortized) to keep a rolling\n  window of recent activity instead of growing without bound or (with\n  naive one-at-a-time eviction) paying O(cap) per call indefinitely.\n\nFixed (2 confirmed nitpicks, mechanical and low-risk):\n\n- SRFI 207's bytevector<->hex-string and %ascii-string? used indexed\n  string-ref/string-set! loops; Kaappi strings are UTF-8 byte arrays\n  with no fast codepoint-index path, so string-ref/string-set! are\n  O(k) per call and an indexed loop over a whole string is O(n^2).\n  Confirmed by reading utf8IndexToByteOffset directly. Rewrote to walk\n  string->list/list->string sequentially (both genuinely O(n),\n  confirmed by reading their implementations too).\n- reader_tokens.zig's readByteStringLiteral repeated an identical\n  3-line whitespace-skip loop 4 times across its line-continuation\n  escape handling. Extracted skipIntralineWhitespace.\n\nDeclined (1 finding, doesn't hold up against the spec text):\n\n- SRFI 215's send-log validating SEVERITY range / MESSAGE type. Fetched\n  the spec directly: it enumerates exactly two required validations for\n  send-log (odd-length plist, non-symbol key) and is conspicuously\n  silent on severity/message types -- those constraints are documented\n  as properties of a well-formed message (what a correct caller\n  produces), not as input validation send-log itself must perform.\n  Adding it would be unrequested speculative validation.\n\nAll 10 findings were genuine and independently verified (a different\noutcome from some earlier review rounds in this project, e.g. PR #1722,\nwhere a finding didn't survive verification) -- 9 fixed, 1 declined\nwith spec citation. Every fix has a regression test that fails without\nit. Full suite green: zig build test, 1952/1952 Scheme tests (557\nfiles + 1395 R7RS), kaappi fmt corpus (727 files, zero drift).\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* CI: bump Debug leg timeout from 30 to 40 minutes\n\nThe Debug leg has been running at its timeout ceiling with no real\nheadroom: a clean baseline run on this branch completed in 29:03, then\nafter this PR's own new tests landed, two consecutive reruns timed out\nat 30:16 and 30:21 -- both times the log shows nothing but the runner\nterminating orphaned zig/build processes at the 30:00 mark, not a test\nfailure. The suite has grown enough that the 30-min cap stopped being\na hang-bound (per the comment already at this call site) and started\nbeing exactly the \"race the suite\" problem that comment warns against.\nSame fix as the macOS/PR #1635 recurrence.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* CI: pin test job's check name independent of matrix.timeout\n\nThe test job had no explicit name, so GitHub auto-generated its check\nname from every matrix property present for a given combination --\nincluding include-only ones like timeout. Bumping the Debug leg's\ntimeout (30 -> 40, previous commit) silently renamed its check from\n\"test (ubuntu-latest, Debug, 30)\" to \"...Debug, 40\". Branch protection\nrequires that exact old string, so the renamed check can never be\nsatisfied again -- it sits \"Expected -- Waiting for status to be\nreported\" forever, blocking merge.\n\nPin the name to just os+optimize so a future timeout tweak can't repeat\nthis. The other four legs' names are unchanged (they already matched\nthis shape with no timeout override); only Debug's changes, from\n\"test (ubuntu-latest, Debug, 30)\" to \"test (ubuntu-latest, Debug)\" --\nbranch protection's required check list needs updating to match.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-23T01:41:22+05:30",
          "tree_id": "cb7d4a064b8aa77ca733306e53069346d18db15c",
          "url": "https://github.com/kaappi/kaappi/commit/860beb34eff127508a063d565c66814138ebf7f7"
        },
        "date": 1784753295360,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.976923,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.447585,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.92367,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.402175,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006723,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.053532,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.508897,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068301,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.290885,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.976158,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.535025,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.468936,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.731031,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.771908,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044958,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "d8853a26901293789bf4a02e59da1954a0b7d251",
          "message": "Add SRFI 181 custom ports (#1730)\n\n* Add SRFI 181 custom ports (closes #1727; transcoded ports split to #1729)\n\nImplements make-custom-binary-input-port, make-custom-binary-output-port,\nmake-custom-textual-input-port, make-custom-textual-output-port,\nmake-custom-binary-input/output-port, and make-file-error. This is the\nSRFI deferred out of Phase 3 (#1728) for being disproportionately\ncomplex: Port has never held a Scheme Value field before, and custom\nports need their read!/write!/get-position/set-position!/close/flush\nhooks to be Scheme procedures -- the first Value-bearing fields Port has\nhad, plus the first time a port needs to call back into Scheme\nreentrantly.\n\nTwo research passes and a design review (full spec fetch, tracing the\nGC marking switches and the reentrant-call/fiber-parking mechanism)\nproduced a validated design and caught concrete bugs before they\nshipped: a memory leak (missing freeObject/objectSize sites -- 5\ngc_collect.zig touch points needed, not the obvious 3), a\nuse-after-free trap (Kaappi strings reallocate their whole backing\nbuffer in place on a differing-byte-width string-set!, so a read!\ncallback's buffer must never be cached across the call), and a\nsilent-data-loss ordering bug (portWriteBytes has two fd-handling\nsteps, not one -- a custom port's branch must precede both).\n\nTranscoded ports (make-transcoder, codecs, eol-styles, the raise\nerror-handling mode) are split into #1729: the raise mode specifically\nneeds vm.callHandler's continuable-raise machinery, which is\narchitecturally harder than the custom-port plumbing itself.\n\nDesign:\n- Port.custom_backend: ?*CustomBacking holds the 6 callback Values\n  (read!/write!/get-position/set-position!/close/flush), following the\n  existing random_gen field's \"owned pointer, freed with the port\"\n  shape. GC-marked via a shared markPortValues helper wired into all\n  three marking switches (referencesYoung, markObjectContents,\n  markValueInner) plus the two dedicated freeObject/objectSize arms.\n- GC.allocCustomPort follows allocMultipleValues's slice_roots\n  template (rootArgs1/rootArgs2 cap out at 2 Values; this needs up to\n  6 protected across one allocation).\n- readOneByte/portWriteBytes (the single byte source/sink every port\n  primitive already funnels through) gained a custom-port branch each,\n  reusing the existing UTF-8 decode/encode pipeline by exploiting that\n  Kaappi strings are already UTF-8 byte arrays internally.\n- Custom port callbacks run through vm.callWithArgs, which always\n  executes with dispatched_from_scheduler forced false. A callback\n  that tries to block (another port's I/O, thread-sleep!) is rejected\n  with a catchable error via a new, narrow vm.in_custom_port_callback\n  counter (checked in fiber.waitForFd and threadSleepFn) instead of\n  risking the confirmed native-stack-overflow a silent recursive\n  scheduler drive would otherwise allow under concurrent fibers.\n- port-position/set-port-position!/port-has-port-position? (SRFI 192)\n  gained custom-port branches for free integration with get-position/\n  set-position!. close-port/flush-output-port gate their callback\n  invocations on is_open/non-#f so a double-close or a #f flush never\n  double-invokes or misfires.\n\n150 SRFIs now supported (13 built-in, up from 12). Doc counts\nreconciled across both CLAUDE.md files, README.md, and CONFORMANCE.md\nfrom `kaappi features --json`. Cross-compiles clean for Windows x86_64\nand WASM (zero platform-specific code -- every operation is a Scheme-\nlevel callWithArgs call). Full regression green: zig build test\n(including -Dgc-stress=true), 1953 Scheme tests (558 files + 1395\nR7RS).\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* Address CodeRabbit review findings on PR #1730\n\nVerified each finding directly against current code before fixing or\ndeclining, per established project practice.\n\nFixed (3 genuine bugs):\n\n- writeBytesToCustomPort: re-allocated and copied the entire shrinking\n  \"remaining\" slice into a fresh bytevector/string on every partial-\n  write iteration, even though write! never mutates its buffer -- O(n^2)\n  for a callback that only accepts a small chunk per call (the exact\n  \"one-at-a-time\" pattern this PR's own test file already exercised).\n  Confirmed via a 20000-byte write through a 1-byte-at-a-time callback\n  (12ms after the fix). Now allocates once and varies start/count.\n- closePort: didn't flush a custom output port before invoking\n  close_proc, unlike setPortPositionOnCustomPort (which already flushes\n  before seeking) and the fd path's drainWriteBuffer. R7RS: \"If port is\n  an output port, it is flushed before being closed.\" Confirmed via a\n  custom port simulating internal buffering (data relies on flush! to\n  emit) that silently lost it on close-port without the fix.\n- raiseCustomPortCallbackBlocked's error message said \"tried to block\n  on another port's I/O\", but the function is also raised from\n  threadSleepFn for thread-sleep! -- misleading for that case. Now\n  covers both.\n\nAdded (1 nitpick, genuinely strengthens coverage):\n\n- A new GC-stress test that passes allocCustomPort's callback arguments\n  in deliberately unrooted (from the test's own perspective) and forces\n  a collection via the runtime gc.stress field during the allocator's\n  own maybeCollect() call -- the existing two tests pre-root the\n  callbacks externally, so neither could actually detect a regression\n  in allocCustomPort's own slice_roots usage specifically. Verified by\n  temporarily removing the slice_roots assignment and confirming this\n  new test (and only this one) fails.\n\nDeclined (1 finding, real but out of scope for this PR):\n\n- types.zig exceeds the 1500-line policy (1627 lines). Confirmed this\n  predates this PR entirely (1605 lines on main already, before SRFI\n  181's 22-line addition) -- an organic, 105-commit history of one-more-\n  heap-type additions past the file's own documented ~500-line target.\n  A proper split is a repo-wide structural change touching call sites\n  across dozens of files (every heap type here is referenced from\n  primitives files, memory.zig, gc_collect.zig, every vm*.zig file,\n  printer.zig, and more) -- exactly the kind of \"heavy lift\" this\n  project scopes into its own focused PR rather than bundling into a\n  feature PR's already-large diff (same reasoning that split transcoded\n  ports into #1729). Filed as #1731 with a suggested first-cut split\n  and context for whoever picks it up.\n\nAll 5 findings were genuine and independently verified: 3 fixed with\nregression tests (each proven to fail without its fix), 1 test-coverage\nnitpick added, 1 declined with a filed follow-up and clear reasoning.\nFull suite green: zig build test, 1953/1953 Scheme tests (558 files +\n1395 R7RS).\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-23T08:26:57+05:30",
          "tree_id": "6f3c27fa2051390321fc7f6e8eb65a59c6ffad5a",
          "url": "https://github.com/kaappi/kaappi/commit/d8853a26901293789bf4a02e59da1954a0b7d251"
        },
        "date": 1784777130134,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.981008,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.429176,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.908313,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.379089,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006674,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.052694,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.50594,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.067996,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.333013,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.954859,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.509003,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.469617,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.717967,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.765668,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.04513,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "c06791039e6e42003aabc7714481635e49fd78ae",
          "message": "Add SRFI 181 transcoded ports (#1732)\n\n* Add SRFI 181 transcoded ports\n\nCompletes SRFI 181 alongside the custom ports already shipped in #1730:\nmake-transcoder, native-transcoder, codecs (utf-8-codec/make-codec),\neol-styles, the replace/raise error-handling modes, transcoded-port,\nbytevector->string/string->bytevector, and the i/o-decoding-error?/\ni/o-encoding-error?/i/o-encoding-error-char/unknown-encoding-error?\ncondition accessors.\n\nClosing the registry-shadows-a-same-named-.sld gap this uncovered (the\nsame one SRFI 248 already solved) required moving (srfi 181) off its\ndirect registry entry onto a real lib/srfi/181.sld backed by a new\n(srfi 181 primitives) sub-library — so it's now sandbox-embedded like\n(kaappi parallel), and reclassifies from builtin to portable in\n`kaappi features` (150 SRFIs: 12 builtin, 136 portable; doc counts\nreconciled in CLAUDE.md/README.md/CONFORMANCE.md).\n\nPort.transcode (a wrapped_port Value plus plain Codec/EolStyle/ErrorMode\nenums) follows custom_backend's precedent for GC integration. The decode/\nencode loops funnel through readOneByte/portWriteBytes exactly like every\nother port, committing one character per call so a fiber park (which\nreruns the whole native call from scratch) never loses partial progress;\nCRLF lookahead reuses the wrapped port's own peek_byte, the same\nmechanism read-line's CR/CRLF handling already relies on. raise mode\nneeded a mechanism custom ports never did: primitives_control.\nraiseContinuable (factored out of raise-continuable itself) signals a\ncontinuable condition and resumes after the handler returns, safe from\nretry-from-scratch since a reentrant runUntil always runs with\ndispatched_from_scheduler forced false. v1 supports only the UTF-8\ncodec; latin-1-codec/utf-16-codec are not exported at all rather than\nbound to always-failing procedures.\n\nCloses #1729.\n\n* Freeze unknown-encoding-error-name's string, per spec\n\nSRFI 181 requires unknown-encoding-error-name's result to be immutable\n(\"it is an error to mutate this string\") -- the same contract Kaappi\nalready enforces for symbol->string via flags.immutable. make-codec was\nreturning the caller's own make-codec argument verbatim: mutable unless\nthe caller happened to pass a literal, and aliased to the caller's own\nstring object either way.\n\nFixed by round-tripping through string->symbol/symbol->string, the only\nportable way to freeze a string's exact content without a new native\nprimitive. Caught by review; the first regression test written for this\npassed even without the fix, since it used a string literal (already\nimmutable via the reader's own quoted-data handling) rather than a\ngenuinely mutable string -- fixed to use string-copy instead, and added\na second test confirming the condition doesn't alias the caller's string.",
          "timestamp": "2026-07-23T13:26:08+05:30",
          "tree_id": "b6f482577a9467a005b9fea3727c7b190f9727f7",
          "url": "https://github.com/kaappi/kaappi/commit/c06791039e6e42003aabc7714481635e49fd78ae"
        },
        "date": 1784795715526,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.015114,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.282341,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.591024,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.95212,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.005569,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.039385,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.337135,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.048046,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.841725,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.30274,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.147056,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.361894,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.281067,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.733492,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.033847,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "cbf4dbe4d2f1115b4f390230a4733963ce125ba2",
          "message": "Add 7 SRFI libraries, exclude 3, reduce 1 (SRFI Phase 4 slice 1) (#1733)\n\n* Add 7 SRFI libraries, exclude 3, reduce 1 (SRFI Phase 4 slice 1)\n\nImplements SRFI 59 (Vicinity), 90 (Extensible hash table constructor,\nreduced scope), 112 (Environment Inquiry), 123 (Generic accessor and\nmodifier operators), 126 (R6RS-based hashtables, non-weak baseline),\n173 (Hooks), and 193 (Command line) from issue #1703.\n\nA new shared native primitive surface (src/primitives_sysinfo.zig,\n`(kaappi sysinfo)`) backs the script-path/version/platform inquiries\nthese libraries need: %script-path (vm.script_path, resolved once in\nrunFile -- absolute, `.`/`..` normalized, symlinks never followed) feeds\nboth SRFI 59's program-vicinity and SRFI 193's script-file/\nscript-directory; %implementation-version/%os-name/%cpu-architecture\nfeed SRFI 112.\n\nSRFI 88 (Keyword objects) and SRFI 89 (Optional/named parameters) are\nexcluded rather than implemented. SRFI 88's postfix-colon syntax\nreinterprets already-valid R7RS identifiers (breaking real, unrelated\nuses like the `(prefix lib id:)` import modifier and `:::`-style custom\nsyntax-rules ellipsis identifiers) in exchange for compatibility with\njust one of several competing, never-standardized keyword conventions\nacross the Scheme ecosystem. SRFI 89's named-parameter matching needs a\nruntime type check during macro pattern matching that plain\nsyntax-rules cannot express -- confirmed via the reference\nimplementation, which resorts to define-macro for exactly this reason;\nno mainstream syntax-rules-only Scheme has ported it faithfully either.\nSRFI 227 (Optional arguments), already implemented, covers the\noptional-positional-parameter niche instead. Full rationale for both in\ndocs/dev/srfi-exclusions.md, including why a working prototype of\nlambda*/define* as native compiler forms was reversed as disproportionate.\n\nSRFI 106 (Basic socket interface) is also excluded: raw sockets belong\nin the kaappi-net ecosystem package, which already covers this space\nwith TLS support core deliberately doesn't have.\n\n157 SRFIs now supported (12 built-in, 143 portable), up from 150.\n23 SRFIs excluded (was 20).\n\n* Address PR #1733 review: script-path lifetime, sandbox scope, vicinity gaps\n\n- resolveScriptPath: normalize \".\"/\"..\" in absolute paths too, not just\n  relative ones (regression test: script-path-normalization.sh)\n- vm.script_path: free the previous allocation in runFile, free on VM\n  deinit (root VM only), and share (never free) it with child SRFI-18\n  threads via initForThread\n- kaappi_sysinfo: stop blocking the whole library under --sandbox; rely on\n  the per-primitive sandbox flag so only %script-path opts out and the\n  other sysinfo procedures stay reachable\n- SRFI 59 program-vicinity: track vm.current_lib_dir (already maintained\n  as \"whatever file is currently loading\" for .sld/include resolution, now\n  also for `load`) instead of the static top-level script path, so a\n  nested load reports its own directory while active\n- SRFI 59 library-vicinity/implementation-vicinity: return real\n  directories ($KAAPPI_HOME/lib, the running executable's own directory)\n  instead of \"\", which silently meant \"current directory\"\n- SRFI 59 home-vicinity: fall back to USERPROFILE on Windows when HOME is\n  unset\n- Fix osName's doc comment and CLAUDE.md's SRFI total (208 = 157 + 28 + 23,\n  not 27)\n- srfi193.scm: accept Windows path separators in the script-file/\n  script-directory assertions (was failing windows-arm-test)\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* Fix script-path-normalization.sh to not hardcode a POSIX path spelling\n\nWindows CI failed: the test asserted the raw $tmpdir (an MSYS /tmp/...\nspelling from Git Bash's mktemp) against kaappi's own output, but kaappi\nprints native paths -- a backslash-separated, write-escaped Windows path\nunder a Git-Bash-translated temp directory, per tests/scheme/CLAUDE.md's\nown \"don't bake POSIX-only spellings into assertions\" guidance. Compare\nkaappi's output for a clean path against its output for a \"../\"-laden\npath to the same file instead, so the test never needs to predict the\nexact spelling on any given host.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-23T19:13:58Z",
          "tree_id": "f5888e97a8951889b596b38ab1b5b684ef1b1cec",
          "url": "https://github.com/kaappi/kaappi/commit/cbf4dbe4d2f1115b4f390230a4733963ce125ba2"
        },
        "date": 1784836422348,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.345868,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.026928,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.892785,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.400492,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006311,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.053963,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.502997,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069366,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.574566,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.908126,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.583309,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.430315,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.809545,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.667976,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044217,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "630f16a225baccd323a93ec3a13c5c60bbba98dc",
          "message": "Address PR #1733 second-round review: Windows paths, stale sandbox docs (#1734)\n\n* Address PR #1733 second-round review: Windows paths, stale sandbox docs\n\n- extractDir (vm_library.zig): recognize '\\' as a separator on Windows\n  too, matching vicinity:suffix?'s own platform split -- a Windows\n  `(load \"dir\\file.scm\")` was reporting program-vicinity as \"\" instead\n  of \"dir\\\" while loading, since extractDir only searched for '/'\n- Fix stale sandbox documentation in lib/srfi/59.sld and primitives.zig\n  left over from the earlier fix that stopped blocking the whole\n  `(kaappi sysinfo)` library under --sandbox: SRFI 59 is still\n  unavailable under --sandbox, but because it's a non-embedded .sld\n  file (blocked wholesale), not because of kaappi_sysinfo's own gate\n- Move the nested-load program-vicinity regression out of srfi59.scm\n  into its own file (srfi59-nested-load-vicinity.scm), per this\n  project's \"name bug regressions after the bug\" convention\n\nNot applied: using shell-common.sh's native_path in\nscript-path-normalization.sh. native_path converts via `cygpath -m`\n(forward-slash mixed style), but %script-path's actual Windows output\nis backslash-separated and write-escaped -- a format native_path\nwouldn't produce, so it can't build a matching expected value. The\ntest's existing self-referential comparison (clean path vs. \"../\"-laden\npath to the same file) sidesteps needing to predict the exact spelling\nat all, and is already verified passing on both windows-arm-test and\nwindows-x64-test in CI.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* Fix inconsistent procedure count in 59.sld sandbox comment\n\nSaid \"three of its four procedures\" but (kaappi sysinfo) has seven\nprimitives now (3 reachable + 4 sandbox-excluded), not four. Describe\nthe three by what they are instead of by a count.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-24T02:31:13+05:30",
          "tree_id": "99a948767e165370e2d430929da3a509f46cc33c",
          "url": "https://github.com/kaappi/kaappi/commit/630f16a225baccd323a93ec3a13c5c60bbba98dc"
        },
        "date": 1784842858325,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.983317,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.518741,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.912027,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.367203,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006567,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.052552,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.501848,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.067693,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.320823,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.944663,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.51852,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.470933,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.739299,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.765631,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043996,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "45cafd216e4b978bc35d53bdae61435b032930c5",
          "message": "Add SRFI 120, exclude 21 and 230 (SRFI Phase 4 slice 2) (#1735)\n\n* Add SRFI 120, exclude 21 and 230 (SRFI Phase 4 slice 2, closes #1702)\n\nSRFI 120 (Timer APIs) ships as a portable library with zero engine\nchanges: each make-timer spawns a dedicated SRFI-18 thread coordinated\nthrough a (kaappi fibers) control channel, with all mutating calls\n(schedule/reschedule/remove/exists) implemented as synchronous\nrequest/reply over fresh one-shot reply channels.\n\nSRFI 21 (real-time multithreading) and SRFI 230 (atomic operations) are\nexcluded: both need architecture Kaappi's SRFI-18 doesn't have (a\nuserspace-scheduled thread model with enforced priority inheritance, and\nshared mutable memory across threads' otherwise-independent heaps,\nrespectively). See docs/dev/srfi-exclusions.md for the full rationale.\n\nAlso discovered and documented (but did not fix, as out of scope for a\nportable-library change): calling SRFI 120's procedures on one timer from\nmore than one thread produces nondeterministic memory corruption, even\nthough a bare two-thread channel round trip with none of this library's\nother machinery does not reproduce it in isolation. The library's own\nheader comment and test suite treat single-calling-thread as a hard\nrequirement until that engine-level issue is investigated separately.\n\n158 SRFIs implemented, 25 tracked, 25 excluded (208 total).\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* Address PR #1735 review: spec-conformance fixes for SRFI 120\n\nThree genuine spec-conformance bugs found by review, all verified\nagainst the actual SRFI 120 spec text before fixing:\n\n- make-timer-delta only accepted full-word units (hours, seconds, ...);\n  the spec's required baseline vocabulary is the abbreviated symbols\n  (h/m/s/ms/us/ns). Both are now accepted.\n- timer-cancel! never re-raised a task's preserved error. The spec is\n  explicit: \"the procedure raises the preserved error if there is\" --\n  timer-cancel! is now synchronous (like the other operations) and\n  raises whatever condition caused the timer to stop, including a\n  re-raising error-handler's own condition.\n- A negative timer-delta (e.g. (make-timer-delta -1 's)) silently\n  produced a negative fire-at instead of being rejected, unlike the\n  plain-integer branch which already enforced non-negativity.\n\nAlso fixed: the SRFI 21/230 exclusion doc claimed both \"extend SRFI 18\",\nbut SRFI 230 is a standalone interface that merely notes an SRFI-18-based\nimplementation is possible.\n\nDocumented (not fixed, out of scope): the spec requires a task to be able\nto cancel/reschedule other tasks on the same timer, which this\nimplementation cannot do (thunks run synchronously inside the timer's own\nmessage loop, so a reentrant call from within a thunk deadlocks). A real\nfix needs either reentrant reply-channel semantics or per-task threads,\nand the latter would hit the same cross-thread channel bug already\nflagged as out of scope in the original PR.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* Fix timer-cancel! sentinel to survive the cross-thread channel hop\n\n%no-error-sentinel was a freshly-consed list sent from the timer thread\nto the caller over a channel. channel-send/receive deep-copies non-symbol\nheap values across threads' independent GC heaps, so the copy arriving\nin the calling thread was `equal?` but never `eq?` to the sender's own\nbinding -- timer-cancel! always mistook its own sentinel for a real\npreserved condition and raised it. Switched to a bare symbol, which\nsurvives the hop intact because Kaappi interns symbols through a table\nshared across every thread's heap (the same reason the 'schedule/'stop/\netc. message tags elsewhere in this file already work via `case`).\n\nAlso closes the edge case CodeRabbit flagged: a task that (raise #f)s\nwith no handler is now correctly re-raised by timer-cancel! instead of\nbeing confused with \"nothing was preserved\" (both previously looked\nlike plain #f).\n\n* Address PR #1735 third-round review: tagged stop-reply, id-return, doc fixes\n\nConfirmed and fixed against the SRFI 120 spec text and this codebase's\nactual behavior:\n\n- Replace the %no-error-sentinel value comparison with a tagged reply\n  pair, ('ok . #f) or ('error . condition), for the (stop) message. A\n  bare sentinel -- symbol or not -- compared by eq?/eqv? can never fully\n  rule out collision with a task's own raised condition (R7RS `raise`\n  accepts any object); tagging the pair makes the distinction structural\n  instead of relying on an unlikely value. Added a regression test that\n  raises the exact symbol the old sentinel used, proving the collision\n  this design point closes.\n- timer-reschedule! now returns the task id on success, matching \"the\n  procedure returns given id\" (it previously returned #t).\n- make-timer-delta now rejects non-integer n, matching \"n must be an\n  integer\".\n- Import (srfi 1) explicitly for filter rather than relying on it being\n  incidentally visible without a declared dependency.\n- Fixed a stale doc comment claiming preserved task errors have no\n  retrievable accessor -- timer-cancel! has re-raised them since the\n  previous commit.\n- Documented (as a known limitation, not fixed) that a task thunk running\n  longer than %reply-timeout-seconds makes concurrent requests see false\n  \"not responding\"/timeout answers, since %timer-loop services `control`\n  only between thunks; SRFI 120 tasks are meant to be short callbacks, so\n  a full liveness-aware reply protocol is left as a documented gap.\n- Tightened three tests that either ignored a channel-receive's result\n  (so a timer that silently never fired could still pass) or used a\n  fixed thread-sleep! to wait for a background task to run (replaced with\n  a channel signal sent immediately before the task raises).\n\nVerified two other CodeRabbit claims from this same round against actual\nKaappi behavior and declined them: `exit` and `filter` are both reachable\nfrom bare (scheme base) in top-level script execution regardless of\ndeclared imports (confirmed empirically and via precedent -- 43 existing\nsrfi test files already call exit without importing (scheme\nprocess-context), and lib/srfi/216.sld already imports (srfi 18)\nunconditionally the same way this library does), so adding cond-expand\nguards or a (scheme process-context) import would be unrequested churn\naddressing no observable bug.\n\n---------\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-24T10:02:45+05:30",
          "tree_id": "2bfadb4f6b121938a53c05e54a05bf1f5eb4e7b4",
          "url": "https://github.com/kaappi/kaappi/commit/45cafd216e4b978bc35d53bdae61435b032930c5"
        },
        "date": 1784869894278,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.356468,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.381419,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.90511,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.412713,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006319,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.054181,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.515244,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.071238,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.523627,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.89808,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.594672,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.436413,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.808304,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.663322,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045023,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "b0b4029997a65f24a40c5f542bef218de71512cb",
          "message": "Add SRFI 57/237/240/137/136/131, exclude 99/100/150 (SRFI Phase 4 slice 3, closes #1695) (#1736)\n\n* Add SRFI 237/240/137/136/131, exclude 99/100/150 (SRFI Phase 4 slice 3)\n\nCloses 8 of #1695's 9 SRFIs (57 remains open, tracked separately).\n\nSRFI 237 (R6RS Records, refined) is the one record-system SRFI needing\nreal engine changes, since a portable macro cannot synthesize the\nidentifiers R6RS's auto-naming record syntax requires: RecordType\n(types.zig) gained parent/own_field_names/own_field_mutable/uid/sealed/\nis_opaque fields (parent is the only new heap pointer, traced in all\nthree gc_collect.zig mark-graph switches; RecordType is fully immutable\nafter construction, so none of this needs a write barrier), and\nvm_records.zig's define-record-type desugarer gained a parallel R6RS-\nclause-syntax path dispatching alongside the original R7RS one.\nInheritance/protocol composition (including R6RS's own two-protocol\nworked example) uses a \"materialize the parent instance via its own\nconstructor, then re-extract its fields\" strategy instead of R6RS's own\nCPS n/p threading -- behaviorally identical, but needs no per-level\nspecial-casing regardless of protocol mixing at any depth. SRFI 240\n(Reconciled Records) is a thin syntactic-reconciliation layer over 237,\nexactly as its spec describes.\n\nGetting SRFI 136/131 (and any future SRFI reusing the name\ndefine-record-type) to work at all needed one more fix: Kaappi hardcoded\ndefine-record-type as a non-overridable special form in\nhandleTopLevelForm, checked before any macro table -- so no portable\nlibrary could ever give that name new meaning via define-syntax, even\nthough compiler.zig's compileForm already prioritized macros over\nspecial forms for every non-top-level use (its own comment cites SRFI\n219 redefining `define` as existing precedent for exactly this\nprinciple). handleTopLevelForm/isSpecialTopLevelForm now check for a\nuser macro literally named define-record-type first. This closes the\ngap only for top-level use; library-body use of a shadowing\ndefine-record-type is a documented, un-closed gap, same limitation as\nthe R6RS-clause syntax itself.\n\nSRFI 137 (Minimal Unique Types), 136 (Extensible record types, with its\nsignature CPS-style introspection macro), and 131 (ERR5RS Record Syntax\nreduced, with by-name rather than positional constructor field\nresolution) are pure portable Scheme built on (srfi 237)'s procedural\nlayer. SRFI 99, 100, and 150 are excluded: 99 and 100 both need\nidentifier synthesis from string concatenation at macro-expansion time\n(the same fundamental syntax-rules limitation as already-excluded SRFIs\n89/206/212); 150 needs SRFI 147/148's custom-macro-transformer support,\nwhich SRFI 147's own spec text says isn't portably implementable either.\n\nAlso documents a narrow, un-root-caused compiler quirk found while\nbuilding 136/131: calling one %-prefixed forward-referenced global as a\ndirect argument expression to another, inside a closure passed to map,\nraised a spurious \"undefined variable\" for the inner call -- reliably\nfixed by routing through an extra wrapper function, but worth a\ndedicated investigation later.\n\n* Add SRFI 57 (Records), fully closing issue #1695\n\nRecords with inheritance via \"schemes\" -- a named, reusable field-label\nlist that a type or another scheme can extend, with multiple schemes\nmergeable at once (left-to-right append + delete-duplicates), plus\nrecord-update/record-update!/record-compose for functional update,\nin-place update, and cross-type field composition.\n\nDeliberately does not port the spec's own reference implementation\ntechnique (macro-expansion-time identifier comparison via let-syntax):\na previously-undiscovered expander bug makes any let-syntax upstream of\na define-syntax in the same expansion chain fail to compile. Sidesteps\nit by doing all field-list merging/dedup/lookup on ordinary quoted\nsymbols at run time instead -- simpler than the reference design, not\njust a workaround, and needs no engine changes.\n\nThis closes SRFI Phase 4 issue #1695 in full (57/131/136/137/237/240\nshipped, 99/100/150 excluded).\n\n* Address CodeRabbit review: fix real bugs, document remaining gaps\n\nTwo genuine SRFI 57 spec violations, found by re-verifying against the\nactual spec text rather than trusting the earlier implementation:\n\n- record-compose had import precedence backwards (last import was\n  winning collisions; the spec's \"left to right, dropping any repeated\n  fields\" means the first import should win, matching delete-duplicates\n  semantics used elsewhere in this same spec).\n- define-record-type's field accessors/mutators were polymorphic\n  (resolving via the instance's own actual rtd) when the spec requires\n  them to be monomorphic (\"It is an error to pass an accessor a value\n  not of type <type name>\"); only scheme accessors are meant to be\n  polymorphic.\n\nAlso added: define-record-scheme/define-record-type's \"type-clause\nonly\" shorthand forms, runtime conformance/label-membership checks for\nrecord-update and record-update! (call-time, not expansion-time, since\ntarget is an ordinary value in this design -- documented), and an\nexplicit (srfi 237 primitives) import.\n\nOn the SRFI 237 engine side (used by 131/136/137/57 too): reject a\nsealed parent type per R6RS (both the define-record-type desugarer and\n%make-record-type-descriptor), check nongenerative-uid reuse for actual\nequivalence rather than reusing unconditionally, reject field counts\nthat would overflow the u8 field-count representation instead of\nletting @intCast panic, and make cross-thread deep-copy of a\nnongenerative record type reuse the destination VM's own registration\ninstead of minting a second, non-interoperable type with the same uid.\n\nLeft as documented, not fixed: SRFI 57's labeled record expressions\n(`(type-name (label expr)...)`) would need every scheme/type name to be\na macro rather than an ordinary value, conflicting with this library's\ncore design choice (see lib/srfi/57.sld's header); record_uid_registry\nhas the same lock-free cross-thread staleness tradeoff already accepted\nfor the pre-existing `macros` map, not a new regression.\n\nAlso fixes two documentation issues: a typo/garbled sentence in\nCLAUDE.md's SRFI 137 paragraph, and two self-contradicting statements\nin docs/dev/srfi-exclusions.md (an overgeneralized Gauche comparison,\nand a scope note that claimed SRFI 131 covers shorthands its own\n\"why excluded\" section says it drops).\n\n* Address second CodeRabbit pass: critical GC bug, nominal conformance\n\nCritical: fixed a permanent-GC-disable bug in vm_records.zig. Several\nblocks used `no_collect += 1; errdefer no_collect -= 1;` followed by a\nmanual mid-block `no_collect -= 1` and then MORE fallible operations\n(compileAndRunDefine) still inside the errdefer's scope. If any of those\nlater operations failed, the errdefer fired on top of the already-applied\nmanual decrement, underflowing the u32 counter and permanently disabling\nGC for the rest of the process. Fixed by replacing the errdefer + manual\ndecrement pair with a single unconditional `defer`, matching the pattern\ngc_deep_copy.zig already uses correctly. Applied to all 8 occurrences of\nthis shape in the file, including 4 pre-existing ones in the R7RS\nhandleDefineRecordType path (same file, same bug, latent before this PR).\n\nSRFI 57: replaced structural scheme conformance (\"has the right field\nnames\") with nominal conformance (\"was actually declared to extend this\nscheme\"), per the spec's own semantics. A record instance only carries a\npointer to its raw rtd, which has no room for this library's own scheme\nmetadata, so conformance now looks up a type's declared ancestry from a\nnew side table (%srfi57-registry, populated once per define-record-type)\nrather than checking field-name overlap. This closes a real gap: a\nsame-shaped but unrelated type used to pass every scheme predicate,\naccessor, and record-update/record-compose target check. Also added:\nrecord-compose now validates that each import actually conforms to its\ndeclared type/scheme, and that every explicit override label is a real\nfield of the export type (previously an import's raw field overlap was\nenough, and export labels went unchecked into %make-record positionally).\n\nAlso fixes two narrower gaps found in the same pass: cross-thread\ndeep-copy of a nongenerative record type was registering the copy in the\ndestination VM using the SOURCE's uid string as the hash key (a\ndangling-pointer risk once the source heap is freed) -- now keys by the\ncopy's own, destination-owned uid string. And the R6RS\ndefine-record-type desugarer's nongenerative-uid reuse had the same\nmissing equivalence check already fixed on the %make-record-type-descriptor\nprimitive in the previous commit -- factored fieldsEquivalent out as a\nshared, exported helper and applied it here too.\n\nTwo pre-existing test bugs surfaced by the nominal-conformance fix (both\nrelied on structural coincidence rather than declared conformance) are\ncorrected: `person` and `cp` in the test suite now actually declare the\nschemes their own tests assume they conform to.\n\n* Update CLAUDE.md's SRFI 57 writeup to reflect nominal conformance + no_collect fix\n\n* Fix SRFI 237 record-name binding and add generative clause support\n\nTwo more real gaps found by CodeRabbit's third pass, both in the R6RS\ndefine-record-type desugarer this PR added:\n\n- The declared record name itself (e.g. `point`) was never bound to\n  anything -- only a hidden, redefinition-stable internal alias\n  (`__record_type_point`) was. SRFI 237's own spec is explicit: \"As an\n  expression, this keyword evaluates to the underlying record\n  descriptor.\" Fixed by binding the declared name to the same rtd value,\n  alongside (not instead of) the internal alias, which inheritance/\n  self-reference still needs.\n\n- SRFI 237 adds a `(generative)` clause to R6RS's clause set, mutually\n  exclusive with `(nongenerative ...)`. It wasn't recognized at all, so\n  a spec-valid declaration fell through to the R7RS parser and failed.\n  Added as a clause keyword; parses as a no-op (a record type is already\n  generative by default) and is rejected in combination with\n  `nongenerative`.\n\nBoth verified against the actual SRFI 237 spec text before fixing.\nRegression tests added to tests/scheme/srfi/srfi237.scm; the\ngenerative+nongenerative rejection is verified via a standalone script\ninstead (a malformed top-level define-record-type is a compile error\nthat aborts the whole file, not a catchable exception a SRFI-64 suite\ncan assert against in-process).",
          "timestamp": "2026-07-24T21:25:23+05:30",
          "tree_id": "5d3586c48e5a89633f33fd3f0e39d0cc4ef5123d",
          "url": "https://github.com/kaappi/kaappi/commit/b0b4029997a65f24a40c5f542bef218de71512cb"
        },
        "date": 1784910978295,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.00241,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.853093,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.912306,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.394613,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006598,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.052864,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.508733,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068203,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.290659,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.958571,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.513155,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.47536,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.698233,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.726246,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045236,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "996051e0974bc1d7f442edfbc7587fcf48a19855",
          "message": "Add SRFI 160/66/74, fix SRFI 4 f32 precision (#1694 vector family) (#1737)\n\n* Add SRFI 160/66/74, fix SRFI 4 f32 precision (#1694 vector family)\n\nAdds a native NumericVector heap type (11 element kinds, u8 stays a\nbytevector alias) backing SRFI 160's homogeneous numeric vector\nlibraries, with the full SRFI-133-shaped extended surface implemented\nonce generically in portable Scheme over six minimal Zig primitives.\nSRFI 4 becomes a thin re-export over this substrate, which also fixes\na real bug in the old wrapped-vector implementation: f32vector never\nactually truncated to 32-bit precision. SRFI 66 (octet vectors) and\nSRFI 74 (binary blobs) are pure-portable additions over bytevectors,\nneeding only one new primitive (%host-big-endian?) so `(endianness\nnative)` is correct on kaappi's own big-endian CI targets.\n\nIssue #1694's array family (SRFI 25/47/58/63/164/179/231) remains open\nand tracked separately: three mutually incompatible API lineages plus\na reader-syntax SRFI, out of scope for one slice.\n\n* Fix CodeRabbit review findings: length overflow, complex sign printing\n\n- %make-numeric-vector: reject a length whose element count would\n  overflow usize before narrowing (unreachable on 64-bit targets given\n  the fixnum range, but a real panic-instead-of-catchable-error gap on\n  wasm32); same defense-in-depth check in allocNumericVectorFill,\n  mirroring allocVectorFill's existing pattern.\n- printer.zig: c64/c128 numeric-vector elements printed a doubled sign\n  for +inf/-inf/+nan imaginary parts (formatFlonum already includes its\n  own sign for these) and lost the sign of a -0.0 imaginary part (`<`\n  is false for negative zero). Factored the already-correct handling\n  from the standalone Complex printer arm into a shared helper.\n- srfi160.scm: strengthened three tests that couldn't actually catch a\n  wrong-direction fold-right/unfold-right/unfold! (commutative combiner,\n  index-only unfold callback) into order-sensitive ones.\n\nNot changed, with reasoning: CodeRabbit's suggestion to relocate the\nSRFI documentation additions out of CLAUDE.md/CONFORMANCE.md contradicts\nthis repo's own established convention (every prior SRFI-adding PR\ndocuments there; kaappi.github.io is end-user docs only per root\nCLAUDE.md). Its file-size-split suggestion for types.zig/memory.zig\nflags a pre-existing condition unrelated to this PR — both files were\nalready ~150-300 lines over the 1500 cap before this change, accumulated\nacross many prior SRFIs; splitting them is a large, separate refactor\ndisproportionate to one SRFI PR's scope.",
          "timestamp": "2026-07-25T01:26:04+05:30",
          "tree_id": "4b417a6073039a761e9dd2ed9a396a01dc1041d4",
          "url": "https://github.com/kaappi/kaappi/commit/996051e0974bc1d7f442edfbc7587fcf48a19855"
        },
        "date": 1784925284748,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.278905,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.140903,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.887334,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.400751,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006369,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.053304,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.497015,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068984,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.471225,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.951958,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.572697,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.43482,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.805104,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.596886,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043397,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "a814ffde3d3bd500ed3faaf546499fc4d1ef780c",
          "message": "Add SRFI 25, multi-dimensional array primitives (#1694 array family) (#1739)\n\n* Add SRFI 25, multi-dimensional array primitives (#1694 array family)\n\nPure portable Scheme (lib/srfi/25.sld) -- arrays are spec-defined as\nheterogeneous with no relationship to SRFI 4/160's numeric vectors, so\na define-record-type wrapping a plain vector is spec-sufficient. One\nrecord covers both simple (row-major backing vector) and share-array\n(affine view: base array + index-translation mapper) arrays; views\nrecurse into the base array's own ref/set! rather than its raw vector,\nso nested views compose correctly for both reads and writes.\n\nConfirms and corrects the \"three mutually incompatible lineages\"\nframing in issue #1694: SRFI 164 is actually a compatible extension of\n25 (identical shape representation), not a separate lineage, making it\na comparatively cheap follow-on. SRFI 47/63 (63 supersedes 47) is the\nreal incompatible lineage (array-set!'s value-last vs. value-second\nargument order is a silent-data-corruption-class conflict). SRFI 231\n(supersedes 179) is a third, much larger, unrelated redesign (118\nbindings). SRFI 58's reader syntax is written specifically against\n47/63's naming. All four remain open, tracked separately.\n\n* Fix CodeRabbit review findings: shape aliasing, arity/index validation\n\n- lib/srfi/25.sld: make-array/array/share-array now deep-copy the\n  caller's shape vector before storing it in the array record. Per\n  spec, \"an array does not retain a dependence to the shape array\" --\n  without the copy, a caller mutating their own shape object (shape\n  returns an ordinary, caller-visible mutable vector of pairs) could\n  retroactively corrupt an already-constructed array's bounds while\n  its backing store keeps the size computed at construction time.\n- make-array now rejects more than one fill-value argument instead of\n  silently discarding all but the first.\n- The packed-index-array form of array-ref/array-set! now requires the\n  index array to be 0-based, per spec (\"a 0-based 1-dimensional\n  array\"), instead of silently accepting any lower bound.\n- srfi25.scm: added regression tests for all three fixes, and wrapped\n  the share-array fixtures in let/let* instead of top-level defines\n  for cleaner test isolation.\n- CLAUDE.md: a line starting with \"#1694\" was being parsed as an ATX\n  heading attempt by markdown linters; reworded so it doesn't start\n  the line.",
          "timestamp": "2026-07-25T08:11:07+05:30",
          "tree_id": "bbb6102013228c9dce445b78550a4e63981ea2ab",
          "url": "https://github.com/kaappi/kaappi/commit/a814ffde3d3bd500ed3faaf546499fc4d1ef780c"
        },
        "date": 1784949459090,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.281301,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.002534,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.928057,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.407502,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006624,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.053803,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.510388,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069983,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.598937,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.927427,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.587934,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.44324,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.836557,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.697104,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044821,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "154e3506fe80900cca1cf915e0937f7d35392806",
          "message": "Add SRFI 164, enhanced multi-dimensional arrays (#1694 array family) (#1740)\n\n* Add SRFI 164, enhanced multi-dimensional arrays (#1694 array family)\n\nPure portable Scheme (lib/srfi/164.sld), no engine work. A documented,\ncompatible extension of SRFI 25 -- identical shape representation,\nshare-array copied verbatim -- so implemented as its own independent\nlibrary (record accessors don't cross library boundaries, and this\nSRFI's array needs a third mode SRFI 25's record has no room for).\n\nOne record covers three modes: simple (own row-major vector, as in\n25), shared/view (base array + index-translation mapper, same\nrecursive-delegation design as 25's share-array -- backs share-array,\narray-transform, array-reshape, and array-index-share), and virtual\n(a getter/optional-setter pair with no backing storage at all --\nbacks build-array, index-array, and array-index-ref's non-scalar\ncase).\n\narray-transform's transform uses a different calling convention than\nshare-array's mapper per the spec's own explicit contrast (one vector\nin/out vs. separate variadic arguments/multiple values) -- adapted\nwith a one-line wrapper, which works for a non-affine transform\nsince the shared/view mode never checked or exploited affineness.\narray-index-ref/array-index-share (APL-style generalized indexing)\nshare one resolver. array-reshape aliases the source's backing\nvector when simple, per spec, and recomputes via row-major rank\notherwise. array->vector is a live view only for simple arrays --\ndocumented as a deliberate scope reduction, since a non-simple live\nview isn't achievable with a literal R7RS vector in portable Scheme.\n\nTwo self-caught bugs during implementation, both instructive: a\ndeeply-nested first draft of the index-resolver mis-balanced its own\nclosing parens (kaappi check catches this immediately -- worth\nrunning on any new portable library before executing it), and once\nthat was fixed by flattening into named top-level helpers, the\nresolver closure took a rest parameter but every call site passed an\nalready-built list as one argument, silently double-wrapping it and\nproducing \"index out of range\" errors far from the real mistake.\n\n* Fix CodeRabbit review findings: shape-specifier coercion, build-array contract\n\n- Every shape-taking procedure (make-array, array, share-array,\n  build-array, index-array, array-transform, array-reshape) now\n  coerces its shape argument through ->shape before use, per spec:\n  \"the procedures in this specification that require a shape can\n  accept a shape-specifier, as if converted by the procedure\n  ->shape\". Previously only ->shape itself did this conversion, so\n  passing a raw specifier (e.g. #(2 4)) directly to make-array -- the\n  spec's own worked example -- raised a car/cdr type error instead of\n  working. ->shape's own output is already a fresh, non-aliased\n  vector, so this also satisfies the \"does not retain a dependence on\n  the shape argument\" rule without a separate copy.\n- ->shape now validates lo <= hi and exactness for both bound forms,\n  matching the validation `shape` already had.\n- build-array's getter/setter now match the spec's actual contract\n  (getter takes one index-vector argument; setter takes an\n  index-vector then the value) via a boundary adapter, instead of\n  the library's internal variadic-indices/value-first convention\n  that had leaked into the public API. Updated array-index-ref's own\n  use of build-array to match.\n- Documented, rather than implemented, the spec's \"should\" (not\n  \"must\") recommendation that array? also be true of plain R7RS\n  vectors (gvectors) -- doing so would need a parallel plain-vector\n  code path through every array-* procedure, a much larger change\n  than this PR's scope.\n- Added regression tests for the ->shape-coercion fix (one per\n  affected procedure), ->shape's bound validation, and packed-index\n  argument handling (vector and rank-1 array forms, plus their three\n  rejection cases) that had no coverage at all.\n\nFull regression suite (1974 tests) and unit tests still green. One\ncompile-import-error-703.sh flake on an initial run (same flake seen\non PR #1739, unrelated subsystem) reproduced as passing standalone\nand on a clean full rerun.",
          "timestamp": "2026-07-25T04:49:39Z",
          "tree_id": "9bed326883f68ba3f2344e530050f6a9962b4e93",
          "url": "https://github.com/kaappi/kaappi/commit/154e3506fe80900cca1cf915e0937f7d35392806"
        },
        "date": 1784957328748,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.27196,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.50592,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.899828,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.488024,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006377,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.053372,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.499704,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069381,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.53747,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.928412,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.572571,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.440707,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.801707,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.646194,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.046121,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "a44274124dd36c9c4d15c1c86f4dd16d7ca6cefd",
          "message": "Add SRFI 63, homogeneous and heterogeneous arrays (#1694 array family) (#1747)\n\n* Add SRFI 63, homogeneous and heterogeneous arrays (#1694 array family); exclude 47\n\nSRFI 63 supersedes SRFI 47 outright (its own page says so), implementing\nall 9 of 47's procedures plus 4 new ones (list->array, array->list,\nvector->array, array->vector) and 20 prototype-generator procedures (vs.\n47's 13). Confirmed incompatible with SRFI 25/164, already shipped\nearlier in this array family: array-set!'s value argument is second here\n(not last), make-array takes a type/fill prototype (not a bounds-shape\nobject), and every dimension is a plain zero-based size.\n\nOne <uarray> record covers simple arrays (kind-dispatched to the\nalready-shipped (srfi 160 <tag>) procedures for 12 of the 20 element\nkinds, falling back to a plain vector for the rest) and shared views\n(recursive delegation into the base array's own ref/set!, matching the\npattern from SRFI 25/164). list->array/array->list use a rank-nested\nlist structure while vector->array/array->vector use a flat vector plus\nexplicit dimensions -- confirmed via the spec's own examples rather than\nassumed, since the two pairs looked parallel but aren't.\n\nSRFI 47 moves to docs/dev/srfi-exclusions.md as permanently superseded.\n170 SRFIs now supported (169 -> 170); 9 tracked for future work (231,\nand issue #1699's 7 macro/syntax SRFIs); 29 excluded.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* Fix CodeRabbit findings: vectors/strings as arrays, prototype fill, bounds\n\nConfirmed against the primary SRFI 63 spec text before fixing:\n\n- array? must not be disjoint from vector/string (\"Arrays are not\n  disjoint from other Scheme types\" -- vectors/strings are rank-1\n  arrays in their own right). array-rank, array-dimensions,\n  array-in-bounds?, array-ref, and array-set! now dispatch across\n  <uarray> records, plain vectors, and plain strings via new\n  %array-like-* helpers; make-shared-array can now take any of the\n  three as its base too.\n- make-array now propagates a non-empty prototype's own origin element\n  as the fill value (\"the new array is filled with the element at the\n  origin of prototype\"), instead of always using the kind's zero-ish\n  default. The prototype-generator procedures (A:fixZ8b etc.) needed a\n  matching fix: they were building a zero-length store regardless of\n  whether a fill argument was given, so the value could never actually\n  be read back.\n- Shared-view array-ref/array-set! now validate indices against the\n  view's own declared dimensions before delegating through the mapper,\n  matching array-in-bounds? -- previously a mapper that didn't itself\n  bounds-check could make an out-of-range view index silently return\n  an in-bounds base element.\n- list->array now rejects a negative or non-integer rank up front\n  instead of recursing until stack exhaustion.\n\nequal?'s array-comparison branch stays scoped to genuine <uarray>\nrecords (documented as a deliberate reduction) since plain R7RS\nequal? already handles vector/string comparison correctly.\n\n31 new SRFI-64 assertions (65 -> 96) covering all of the above plus\nregression coverage for everything from the initial implementation.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-25T17:09:23+05:30",
          "tree_id": "4ad0d1013230d7e307d9626a8d93f74824a38392",
          "url": "https://github.com/kaappi/kaappi/commit/a44274124dd36c9c4d15c1c86f4dd16d7ca6cefd"
        },
        "date": 1784981948818,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 2.870186,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.749183,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.612456,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.02771,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.005722,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.03948,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.35109,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.05097,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.926134,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.338458,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.153176,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.381723,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.313163,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.874535,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.034764,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "8f513eaf073cbeca137cd3e23002ff2975153483",
          "message": "Add SRFI 231 intervals + misc helpers (#1694 array family, phase 1a) (#1749)\n\n* Add SRFI 231 intervals + misc helpers (#1694 array family, phase 1a)\n\nFirst of several slices implementing SRFI 231 (\"Intervals and Generalized\nArrays\") -- the last remaining piece of #1694's array family. At 118\nbindings (101 procedures/parameters + 17 storage-class singletons), this\nSRFI is roughly 5-10x larger than any prior slice and structurally\nunrelated to SRFI 25/164/63 already shipped: intervals are a genuinely new\nopaque type (two parallel vectors of exact-integer lower/upper bounds,\narbitrary sign) rather than a shape-object or plain-size model.\n\nThis slice covers only the interval layer plus the misc permutation/\ntranslation helpers -- fully self-contained, zero dependency on arrays or\nstorage classes, and independently testable. New internal sub-libraries\n(no bare (srfi 231) yet, matching the (srfi 160 base) + per-tag precedent):\n\n- lib/srfi/231/misc.sld: translation?, permutation?, index-rotate,\n  index-first, index-last, index-swap.\n- lib/srfi/231/intervals.sld: the <interval> record and all 26 interval\n  procedures -- construction (both 1-arg and 2-arg make-interval forms),\n  accessors, interval-for-each/fold-left/fold-right (general d-dimensional\n  lexicographic traversal calling callbacks with separate positional\n  index arguments), dilate/translate/permute/scale, intersect (returns #f\n  on no overlap, not an error), cartesian-product, and projections\n  (returns two values via `values`, split via take/drop from the\n  already-built-in (srfi 1)).\n\nEvery calling convention and error condition was confirmed against the\nprimary spec text and reference implementation before writing any code,\nincluding two procedures (translation?/permutation?) whose exact\nvalidation rule the spec states only in prose, and interval-fold-right's\n\"all f evaluations before any operator application\" requirement (a naive\nreverse-order fold interleaving f and operator would violate this even\nthough it looks equivalent for pure f).\n\nRemaining phases (storage classes, core array type, views/sharing,\ncombinators, multi-array assembly) are tracked as follow-up slices under\n#1694; (srfi 231) itself is not yet importable.\n\nAlso files #1748: tests/scheme/compile/compile-import-error-703.sh has now\nflaked 3 times in full run-all.sh runs across recent slices (never\nstandalone) with a concrete root-cause theory -- unrelated to this PR's\ndiff, passed both standalone and on a clean full rerun here.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* Fix CodeRabbit findings: reject malformed intervals/permutations/indices\n\nConfirmed against the primary SRFI 231 spec text before fixing:\n\n- make-interval now rejects a 3rd+ argument instead of silently\n  discarding it (the spec's signature is arg1 plus one optional arg2,\n  not arbitrary trailing arguments).\n- interval-subset? now errors on mismatched dimensions instead of\n  returning #f -- confirmed the spec's own \"assumes ... the same\n  dimension d\" precondition makes this an error condition, with #f\n  reserved for same-dimension intervals that fail the bound check.\n- interval-contains-multi-index? now rejects non-exact-integer\n  multi-index entries instead of silently comparing them numerically\n  (a coordinate like 1.5 would otherwise pass the <=/< bounds checks\n  and be treated as \"contained\").\n- interval-dilate/translate/permute/scale now validate that their\n  diff/translation/permutation/scales vector length matches the\n  interval's own dimension before calling vector-map, which silently\n  stops at the shortest input on a length mismatch (R7RS, matching\n  map) rather than erroring -- a too-short or too-long vector would\n  otherwise silently produce a wrong-rank result.\n- interval-intersect now requires all argument intervals to share one\n  dimension up front, instead of only ever iterating up to the FIRST\n  interval's own axis count -- a first interval with fewer axes than a\n  later one previously never even looked at the extra axes, silently\n  returning a lower-rank \"intersection\" instead of rejecting the\n  mismatch.\n- index-rotate/index-first/index-last/index-swap now validate their\n  n/k/i/j preconditions, confirmed against the spec's own exact\n  wording for each -- including the asymmetric boundary that\n  index-rotate's k may equal n (inclusive, the identity permutation)\n  while index-first/-last/-swap's k/i/j must be strictly less than n\n  (exclusive). index-last previously produced a vector containing -1\n  and missing an element for an out-of-range k, which isn't a valid\n  permutation at all.\n\n17 new SRFI-64 assertions (62 -> 79) covering all of the above plus\nregression coverage for existing behavior.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-25T13:35:09Z",
          "tree_id": "b4afba9cabd8833e5f61648f88b7573dcc5a48dc",
          "url": "https://github.com/kaappi/kaappi/commit/8f513eaf073cbeca137cd3e23002ff2975153483"
        },
        "date": 1784988493456,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.289341,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.297525,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.887234,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.447788,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006379,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.053701,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.499688,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069209,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.527479,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.934597,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.569695,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.434235,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.800298,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.668069,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.046425,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "3a570b4bc48aceb873e7294500c924da3fb5d42c",
          "message": "Add SRFI 231 storage classes (#1694 array family, phase 1b) (#1750)\n\n* Add SRFI 231 storage classes (#1694 array family, phase 1b)\n\nSecond of several slices implementing SRFI 231 (\"Intervals and\nGeneralized Arrays\") -- see lib/srfi/231/intervals.sld (phase 1a,\nmerged) for the overall roadmap. This slice adds the storage-class\nabstraction: a 9-field record (getter, setter, checker, maker, copier,\nlength, default, data?, data->body) managing a specialized array's\nbacking store, plus all 17 required storage-class global variables.\n\nlib/srfi/231/storage-classes.sld: 14 of the 17 map directly onto this\ncodebase's existing infrastructure with zero new engine work -- 11\nnumeric kinds (s8/s16/s32/s64/u16/u32/u64/f32/f64/c64/c128) reuse the\nalready-shipped (srfi 160 <tag>) procedures, u8 reuses plain R7RS\nbytevector procedures (matching u8's bytevector-alias treatment\nthroughout this codebase), and generic/char reuse native vector/string\ndirectly via the spec's own verbatim reference definitions. The\nremaining 3 (u1, f8, f16) have no Kaappi-native representation and are\nbound to #f, matching the spec's explicit \"shall define... to #f\"\npermission for implementations lacking the underlying type -- the\nreference implementation itself does the same for f8.\n\nEvery checker predicate encodes the exact range/type rule for its kind\n(e.g. s8: exact integer in [-128,127]), confirmed against the same\nper-kind rules already established for SRFI 63's kind-dispatch table.\n\nAlso confirmed (test-writing detail worth recording): reading a\ncomplex number back from a c64/c128 NumericVector always produces a\ngenuinely complex-tagged value, even with a zero imaginary part --\nunlike make-rectangular at the Scheme level, which collapses eagerly.\nThis is a pre-existing Kaappi representation characteristic, not a bug;\nthe test suite uses numeric equality (=) rather than equal? where this\nmatters.\n\n(srfi 231) itself remains not importable -- still tracked under #1694.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* Exercise storage-class-copier in the shared test helper\n\nCodeRabbit finding: the test helper covered 8 of the 9 storage-class\nfields but never called storage-class-copier, so a wrong copy\nprocedure would have passed every existing assertion undetected. Adds\na copy-then-verify step to the shared helper, exercised across all 14\nreal storage classes (14 new assertions, 123 -> 137).\n\nDeclined a second finding (import (scheme complex) for\nmake-rectangular): verified against Kaappi's own primitives table\n(src/primitives_numeric.zig) that make-rectangular/real-part/imag-part\nare registered as members of .scheme_base directly, alongside\n.scheme_complex and .scheme_r5rs -- unlike strict R7RS, where they are\n(scheme complex)-only, this implementation already exposes them from\n(scheme base), so no import is missing.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-25T22:12:03+05:30",
          "tree_id": "ec2f912bd9bd9989c325f78e4683b8a9dba2d2ad",
          "url": "https://github.com/kaappi/kaappi/commit/3a570b4bc48aceb873e7294500c924da3fb5d42c"
        },
        "date": 1784999728009,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.28029,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.349681,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.884297,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.40641,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006354,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.053663,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.4973,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069169,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.534873,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.927574,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.588197,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.434712,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.80321,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.653315,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043899,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "c2382e14981e5829e70219468c3e95497a78325b",
          "message": "Add SRFI 231 core array object (#1694 array family, phase 2) (#1751)\n\n* Add SRFI 231 core array object (#1694 array family, phase 2)\n\nThird of several slices implementing SRFI 231 (\"Intervals and\nGeneralized Arrays\") -- see lib/srfi/231/intervals.sld (phase 1a) and\nlib/srfi/231/storage-classes.sld (phase 1b, both merged) for the\noverall roadmap. This slice adds the array type itself: a domain (an\ninterval) plus a getter, with an optional setter making it mutable,\nand an optional storage-class/body/indexer making it specialized.\n\nlib/srfi/231/arrays.sld: one <array> record covers all four\ncombinations (plain immutable, plain mutable via closures, specialized\nmutable, specialized frozen-immutable) -- specialized-only fields are\nsimply #f on a plain array. array?/mutable-array?/specialized-array?\nconfirmed as a non-strict hierarchy (specialized => array and mutable\n=> array, but specialized and mutable are orthogonal -- array-freeze!\ncan make a specialized array immutable in place, and a closure-backed\nsparse array, per the spec's own example, can be mutable without being\nspecialized at all).\n\nConfirmed two conventions that don't match either prior array SRFI in\nthis codebase exactly: array? is disjoint from vector/string (matching\n25/164, NOT 63's \"vectors are rank-1 arrays\" rule -- easy to get\nbackwards, since getting this wrong was the single biggest miss when\nimplementing 63), while array-set!'s value argument is SECOND (matching\n63, not 25/164's value-last). Getters/setters are always called with\nseparate positional index arguments, never a packed vector/list.\n\nmake-specialized-array's indexer generalizes SRFI 63's 0-based-only\nrow-major offset to arbitrary (including negative) lower bounds: shift\neach axis by its own lower bound first, then apply the standard\nrow-major stride computation using the interval's own widths.\nmake-specialized-array-from-data wraps externally supplied data (e.g.\nan existing (srfi 160 <tag>) vector) as a new array's body with zero\ncopying, confirmed via a real vector-mutation-through-the-array test.\n\nspecialized-array-default-safe?/mutable? are genuine SRFI 39\nparameters, as the spec requires (a documented difference from the\npredecessor SRFI 179, where they were plain variables).\n\n(srfi 231) itself remains not importable -- still tracked under #1694.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* Address CodeRabbit nitpicks: early-exit array-packed?, 0-dim/empty tests\n\n- array-packed? now escapes via call/cc on the first packing mismatch\n  instead of always scanning the full domain -- harmless today since\n  specialized arrays are always packed right after construction, but\n  avoids a full interval-volume traversal once a later phase's\n  view/share/reverse procedures can produce non-packed arrays.\n- Added test coverage for zero-dimensional arrays (a single element,\n  accessed via a thunk-shaped getter/array-ref with no indices, for\n  both a plain and a specialized array) and empty-domain arrays (some\n  axis has lower = upper, so no multi-index can ever be valid -- any\n  access is rejected either via the explicit domain check in safe mode\n  or the storage layer's own bounds check on the resulting zero-length\n  body in unsafe mode). 13 new assertions (50 -> 63).\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-25T18:06:40Z",
          "tree_id": "cfa34740f249b6c819ab69f05c391b00b3c1c8f8",
          "url": "https://github.com/kaappi/kaappi/commit/c2382e14981e5829e70219468c3e95497a78325b"
        },
        "date": 1785005048514,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.280716,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.363761,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.887954,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.414683,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006378,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.0535,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.499586,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069087,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.555468,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.926546,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.560132,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.44076,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.79388,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.656009,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.04408,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "fa3743b61625f481f18067c3ae02bc1412bdfe3c",
          "message": "Add SRFI 231 views, sharing, and reshaping (#1694 array family, phase 3) (#1752)\n\nFourth of several slices implementing SRFI 231 (\"Intervals and\nGeneralized Arrays\") -- see lib/srfi/231/intervals.sld for the overall\nroadmap. This slice adds the 11-procedure \"views/sharing/reshaping\"\ncluster the spec's own \"Sharing generalized arrays\" section names as a\nnatural unit: specialized-array-share (the foundational primitive),\narray-extract, array-translate, array-permute, array-reverse,\narray-curry, array-tile, array-sample, array-copy/array-copy!, and\nspecialized-array-reshape.\n\nlib/srfi/231/arrays.sld (phase 2, already merged) gets one small,\npurely additive change: %make-array/%safe-getter/%safe-setter/\n%make-lex-indexer are now exported for this and later phases' sibling\nlibrary files to build genuinely specialized arrays with custom\nindexers, the same way (srfi 160 base)'s %uvec-* helpers exist only\nfor that package's own per-tag files.\n\nlib/srfi/231/views.sld: extract/translate/permute/reverse/sample all\nshare one 3-way dispatch shape (specialized -> specialized-array-share;\nmutable-non-specialized -> make-array with getter+setter; immutable ->\nmake-array with getter only), with the output mirroring the input's\nmode exactly. array-curry and array-tile break this pattern\ndeliberately -- their OUTER array is unconditionally plain immutable/\nnon-specialized regardless of input mode (confirmed by an explicit\nspec quote for curry: \"B is always an immutable array... computed anew\nfor each call\", i.e. never cached), while their INNER\nelements/tiles follow the same 3-way mirroring as everything else.\n\narray-permute needed real care to get the index-rearrangement direction\nright (apply the permutation's inverse to the new multi-index to\nrecover old coordinates) -- verified against both of the spec's own\nworked examples, including the rank-4 one showing it's the new getter's\nown parameter *list* that gets permuted, not a runtime rearrangement.\narray-tile's last-slice truncation (when an axis width doesn't divide\nevenly by a uniform slice size) is spec-sanctioned via an explicit\nmin(), not an error -- verified against the spec's own 6x6 non-uniform\nworked example exactly, including the truncated case.\n\nspecialized-array-reshape deliberately implements a conservative\nsimplification of the reference implementation's full NumPy-derived\nmulti-group stride-matching algorithm: it succeeds zero-copy whenever\nthe source is already array-packed? (the overwhelmingly common case,\ne.g. reshaping a fresh array-copy result) via a plain row-major\nreindex, and otherwise behaves exactly as the spec allows for a failed\ndetection (error, or forced-copy-then-retry when copy-on-failure? is\n#t). This never wrongly claims an affine map exists, but is more\nconservative than the full algorithm for some non-packed-but-still-\naffinely-reshapable arrays -- verified identical to the full algorithm\non both of the spec's own worked examples (a packed reshape succeeding;\na array-sample'd non-packed reshape failing, then succeeding with\ncopy-on-failure?).\n\narray-copy and array-copy! are implemented identically (a direct fill\nloop), a deliberate, documented scope reduction versus the spec's\noptional extra call/cc-safety guarantee for array-copy specifically\n(accumulate-to-a-list-before-filling) -- getters that escape and\nre-invoke a captured continuation mid-copy are exotic enough not to\njustify the added complexity for this phase.\n\n(srfi 231) itself remains not importable -- still tracked under #1694.\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-25T19:22:24Z",
          "tree_id": "51d17351f93a3fee98ec8369f58c05734ebfaebe",
          "url": "https://github.com/kaappi/kaappi/commit/fa3743b61625f481f18067c3ae02bc1412bdfe3c"
        },
        "date": 1785009716820,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.139127,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.743474,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.652961,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.233982,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006246,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.042183,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.363283,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.054663,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.122165,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.450183,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.242532,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.409978,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.374582,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.884071,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.034042,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "04f15e672efc71b160e0a10446f5be84c0f1d938",
          "message": "Add SRFI 231 bulk combinators and conversions (#1694 array family, phase 4) (#1753)\n\n* Add SRFI 231 bulk combinators and conversions (#1694 array family, phase 4)\n\nFifth of several slices implementing SRFI 231 (\"Intervals and\nGeneralized Arrays\") -- see lib/srfi/231/intervals.sld for the overall\nroadmap. This slice adds array-map/for-each/fold-left/fold-right/\nreduce/any/every, array-outer-product/inner-product, and the 8 flat and\nnested list/vector conversion procedures (array->list, list->array,\narray->list*, list*->array, array->vector, vector->array,\narray->vector*, vector*->array) -- 17 bindings in total.\n\narray-map/for-each/fold-left/fold-right/any/every are all variadic over\narrays, requiring exact domain equality (interval=, not just matching\nshape) across every argument array. array-reduce is the one exception:\nfixed 2-arg, single array only, and hard-errors on an empty array with\nno safety-flag opt-out, using a private sentinel object rather than a\nseed value (there is no safe placeholder that couldn't collide with a\nreal element).\n\narray-fold-left calls its operator as (operator acc e0 e1 ...);\narray-fold-right calls it as (operator e0 e1 ... acc) -- accumulator\nLAST, not first. Confirmed via the spec's own formal reference\ndefinition that elements are always passed as separate positional\narguments, never packed into one list argument, and verified the\ndivergence is real (not just notational) against the spec's own\nworked examples: (array-fold-left - 0 a) and (array-fold-right - 0 a)\ngive different results for the same non-associative operator.\n\narray-inner-product's compositional definition (curry + permute + copy\n+ outer-product + map + reduce) needed care in two places the spec's\nown prose pseudocode gets subtly wrong, both confirmed only by reading\nthe reference implementation directly: it omits the required second\nargument to array-curry on its second call, and its stated\npreconditions don't mention that the shared axis's width must be\nnonzero (needed because the inner reduction would otherwise call\narray-reduce on an empty array).\n\nlist*->array/array->list*/vector*->array/array->vector* infer or\nproduce a per-dimension shape from nested-list/vector structure\n(recursion depth = target dimension, sibling lengths at each level\nmust match -- a ragged structure is rejected). The empty-collection\nedge cases are genuinely undomesticable by intuition alone and were\nverified by hand-tracing all four of the spec's own worked examples\nagainst the actual algorithm: (list*->array 0 '()) yields a RANK-0,\nvolume-1 array whose single element IS the empty list, while\n(list*->array 1 '()) yields a genuinely EMPTY rank-1 array -- these\nlook superficially similar but are entirely different shapes.\nvector*->array/array->vector* delegate to the list* versions via a\nstructure-preserving nested-vector<->nested-list conversion rather\nthan duplicating the whole shape-inference algorithm in vector form.\n\n(srfi 231) itself remains not importable -- still tracked under #1694.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* Validate vector*->array's nested-vector shape; drop dead helper\n\nCodeRabbit finding: %nested-vector->nested-list (which vector*->array\ndelegates to) had no vector?/depth check before calling vector->list,\nunlike the list path (%check-nested-list validates via list? at every\nrecursion level and raises a domain-specific \"not the right shape\"\nerror). A malformed nested vector would instead crash with a raw\nvector->list type error. Fixed by validating vector? at each recursion\nlevel before delegating, matching the list path's error message and\nirritants -- rectangularity itself is still validated for free once\n%check-nested-list runs on the converted result.\n\nAlso removed %vector-every, defined but never called anywhere in this\nfile (a leftover from the same helper pattern used in sibling files\nwhere it IS needed).\n\n1 new regression assertion (55 -> 56).\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-26T06:25:43+05:30",
          "tree_id": "a945ea0e6cf5da2ec5246e63003206fac4083d70",
          "url": "https://github.com/kaappi/kaappi/commit/04f15e672efc71b160e0a10446f5be84c0f1d938"
        },
        "date": 1785029658317,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.345456,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.094976,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.91286,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.460183,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006373,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.054464,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.505166,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.072741,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.530366,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.961158,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.590876,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.438201,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.833703,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.682412,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.046079,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "34e15133a27c823053078175621ebb3505263913",
          "message": "Add SRFI 231 multi-array assembly (#1694 array family, phase 5) (#1754)\n\n* Add SRFI 231 multi-array assembly (#1694 array family, phase 5)\n\nFinal content phase of SRFI 231: array-assign!, array-stack(!),\narray-decurry(!), array-append(!), array-block(!) (9 bindings). All\nfour stack/decurry/append/block constructors follow the established\nvirtual-array-then-array-copy pattern; their `!` twins are aliases,\nconfirmed safe by reading the reference implementation directly (the\ntwo only diverge under multi-shot continuation re-entry, which the\nspec itself declares undefined). array-block needed a two-pass design:\nfull per-axis width-consistency validation (reusing array-curry +\narray-permute + index-first) followed by cheap single-pencil probing\nfor offsets, both confirmed against the reference implementation.\n\nOnly the merge into a public lib/srfi/231.sld plus docs/SRFI-count\nbookkeeping remains for the whole SRFI (#1694).\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* Strengthen array-block test coverage with position-dependent blocks\n\nCodeRabbit review of #1754: every test block was a uniform constant\nalready sitting at a zero lower bound, so the local-index/block-lower\nremap in array-block's assembled getter (assembly.sld:259) could be\nmissing, sign-flipped, or otherwise wrong and every assertion would\nstill pass -- any index inside a constant, zero-based block returns\nthe same value regardless of whether the arithmetic is correct.\n\nReplaced the four const-array blocks with array-translate'd blocks\ncarrying distinct nonzero lower bounds and position-tagged values, so\neach assertion now depends on the real local coordinate. Verified the\nnew test actually catches the bug class: temporarily dropping the\nblock-lowers addition turned 0 failures into 12, confirming the fix\ncloses a real gap rather than just adding assertions.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-26T09:15:39+05:30",
          "tree_id": "e17d18ea65ba1ca63b0f3f04ba731b412444ae03",
          "url": "https://github.com/kaappi/kaappi/commit/34e15133a27c823053078175621ebb3505263913"
        },
        "date": 1785039818760,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.284387,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.416287,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.893852,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.416302,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006388,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.053715,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.497987,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069212,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.524828,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.93126,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.576853,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.434035,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.815633,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.65073,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044278,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "c5eb3c9811dc0566660ad33b568d261eb4aa0b87",
          "message": "Finalize SRFI 231: public lib/srfi/231.sld hub, close #1694 (#1755)\n\n* Finalize SRFI 231: public lib/srfi/231.sld hub, close #1694\n\nMerges the 7 internal phase files (misc, intervals, storage-classes,\narrays, views, combinators, assembly — Slices 8-13) into a public,\nbare-importable (srfi 231) re-export hub, following the (srfi 4) thin\nre-export precedent. The 118-binding public surface is confirmed an\nexact bijection against the reference implementation's own export\nclause, with the 4 %-prefixed internal helpers in (srfi 231 arrays)\ncorrectly excluded.\n\nAlso moves SRFI 179 from tracked to excluded: SRFI 231's own abstract\nstates it is \"a revised and improved version of SRFI 179\" (a breaking\nrevision, not a strict superset like 47/63 — see\ndocs/dev/srfi-exclusions.md for specifics).\n\nBumps the tracked SRFI count 170->171 across CLAUDE.md, README.md, and\nCONFORMANCE.md, all cross-checked against the canonical SRFI registry:\n171 implemented + 7 tracked + 30 excluded = 208, matching exactly.\n\nThis closes issue #1694 (the numeric-vector and array family) in full:\n4/160/66/74 (vector family) and 25/164/63/231 (array family, with 47\nand now 179 excluded as superseded) are all shipped.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* Add full public-export completeness audit to the hub test\n\nCodeRabbit review of #1755: the hub smoke test only exercised 14\nrepresentative bindings, so it couldn't catch the hub silently\ndropping some OTHER name from its claimed 118-binding surface (a typo\nor missed addition in lib/srfi/231.sld's own export clause).\n\nAdded a single assertion referencing all 118 exported identifiers by\nname, in the same order as the hub's own export clause -- evaluating\nit requires every one to resolve, so a missing export fails the\nassertion immediately rather than going unnoticed. Verified the check\nactually works: temporarily dropped array-block! from the hub's export\nclause and confirmed the audit assertion failed (16 pass, 1 fail)\nbefore restoring the real file.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-26T10:55:16+05:30",
          "tree_id": "19a2bc944dbc69ad1e1c2f6cb7a317cfbf78ad04",
          "url": "https://github.com/kaappi/kaappi/commit/c5eb3c9811dc0566660ad33b568d261eb4aa0b87"
        },
        "date": 1785045867883,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 2.417104,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.690055,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.504299,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.472516,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004873,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.031798,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.28291,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.042137,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.335787,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.128729,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 0.931677,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.307786,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.054815,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.813534,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.027284,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "8221fd0429993177149d81e279b0b3283e878890",
          "message": "Fix CLAUDE.md: the 7 tracked macro/syntax SRFIs are issue #1699, not untriaged (#1756)\n\nPR #1755's SRFI-count reconciliation correctly identified 72, 139, 147,\n148, 149, 211, 213 as the 7 still-tracked final SRFIs, but wrongly\ncalled them \"untriaged; no issue filed\" -- issue #1699 (\"Implement\nSRFI macro & syntax extension libraries\") already tracks exactly this\nset, filed and open. Caught by checking `gh issue list` after the\nfact, not by any verification built into the original edit.\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-26T10:59:58+05:30",
          "tree_id": "e4145f3453f6df3a8a80a2b2185619f356991aef",
          "url": "https://github.com/kaappi/kaappi/commit/8221fd0429993177149d81e279b0b3283e878890"
        },
        "date": 1785047057936,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.27975,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.220866,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.894887,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.409087,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006408,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.053375,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.498585,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069058,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.541488,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.931807,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.565725,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.433913,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.799244,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.661465,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043728,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "2e3b70a53dd6b3c2501bdd05fbbf2871e264d37a",
          "message": "Add SRFI 139 (syntax parameters) (#1757)\n\nFirst of 4 tractable pieces of issue #1699 (SRFI macro & syntax\nextension libraries) picked up after issue #1694 closed. Despite being\ngrouped with 6 SRFIs needing real expander/compiler work, 139 needs\nnone: let-syntax already implements exactly syntax-parameterize's own\nsemantics (adjust the live macro table for a bounded compile extent,\nthen restore it), so lib/srfi/139.sld is a 2-form, 6-line library.\n\nVerified against both of the spec's own worked examples (forever/\nabort, lambda^/return) plus 2 adversarial cases -- nested\nsyntax-parameterize of the same keyword, and a body-local variable\nsharing a name with the macro's own internal continuation identifier\n-- both passing without any implementation changes.\n\nBumps the SRFI count 171->172, reconciled against the canonical\nregistry: 172 implemented + 6 tracked + 30 excluded = 208.\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-26T13:03:49+05:30",
          "tree_id": "4b70b5b99b5adceee9fd87b2cd4b0636bcad3ac6",
          "url": "https://github.com/kaappi/kaappi/commit/2e3b70a53dd6b3c2501bdd05fbbf2871e264d37a"
        },
        "date": 1785053514670,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.302535,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.596801,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.889038,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.412917,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006401,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.053974,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.500314,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069164,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.538497,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.94864,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.564177,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.441065,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.790539,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.601312,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043321,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "0bf6f03c849d30a05e7584b2ef8fd5f0a2baf207",
          "message": "Add SRFI 149 (basic syntax-rules template extensions) (#1758)\n\n* Add SRFI 149 (basic syntax-rules template extensions)\n\nSecond of 4 tractable pieces of issue #1699. Like SRFI 139, this needed\nno engine changes despite being grouped with SRFIs that do: Kaappi's\nexpander already implements both of this SRFI's extensions --\nconsecutive ellipses directly after one template element, and letting\na pattern variable be followed by more ellipses than its own\npattern-matched depth, with the excess replicating a shallower sibling\nat the innermost position.\n\nThe spec's own prose gives no worked example for the genuinely-new\nnonzero-depth-excess case, so this needed fetching the reference\nimplementation's expand-template algorithm to understand precisely\nwhat \"innermost\" means, then confirming empirically (against both of\nthe spec's own worked examples, my-append and foo, plus 2 more) that\nKaappi's binding-driven design -- live per-binding depth reduction --\nproduces the identical result via a different mechanism than the\nreference's free-variables-at-this-dimension scan.\n\nlib/srfi/149.sld is a trivial (export syntax-rules) re-export, the\nsame shape as SRFI 46's own \"these R7RS extensions are already native\"\nlibrary. New Zig unit tests in tests_macros.zig plus the usual SRFI-64\nsuite. One pre-existing, unrelated gap found and deliberately left\nalone: an ellipsis with no driving variable at all silently produces\nan empty result instead of erroring -- predates this SRFI and isn't a\ncase it needs to support; fixing it is a separate, broader project.\n\nBumps the SRFI count 172->173, reconciled against the canonical\nregistry: 173 implemented + 5 tracked + 30 excluded = 208.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* Fix markdown lint: avoid #1699 starting a line in CLAUDE.md\n\nCodeRabbit review of #1758: a line starting with \"#1699\" triggers\nMD018 (no-missing-space-atx), since Markdown parses a leading # as an\nATX heading. Reworded to keep it mid-line.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-26T14:34:36+05:30",
          "tree_id": "cb0dd54a0cc59ab0c7c9f7fab318a3187d86d2ad",
          "url": "https://github.com/kaappi/kaappi/commit/0bf6f03c849d30a05e7584b2ef8fd5f0a2baf207"
        },
        "date": 1785059045733,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.278715,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.023719,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.887319,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.389266,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006348,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.05338,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.497781,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068974,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.48396,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.965794,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.561787,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.429299,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.796559,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.585379,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043476,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "f0ac6759c0c2c9a20422d556d583176d8da7fad8",
          "message": "Ship lib/kaappi/ in the release library tarball (#1759)\n\nThe \"Bundle portable libraries\" release step enumerated lib/srfi/ and\nlib/chibi/ -- a list that predates lib/kaappi/ -- so every release from\nv0.18.0 through v0.21.0 shipped a kaappi-lib.tar.gz without\nlib/kaappi/parallel.sld, and (import (kaappi parallel)) failed with\n\"library not found\" on any stock install even though the library is\ndocumented, correct in the tree, and embedded in the binary for\n--sandbox/WASM. Pack the whole lib/ tree instead of an enumerated\nsubset so a future subdirectory cannot be silently dropped.\n\nThe acceptance suite never caught this because it only imported\nbuilt-in libraries (srfi 1/69), which resolve with no libraries\ninstalled at all -- and it runs from the repo checkout, where\ncwd-relative ./lib and the binary's <exe>/../lib fallback both resolve\nthe full source tree, masking any tarball gap. Add one disk-loaded\nimport per shipped lib/ subdirectory, run from a neutral directory\nwith a copied binary so only the installed ~/.kaappi/lib can satisfy\nthem; the (kaappi parallel) test reproduces the exact #1741 failure\nagainst a pre-fix tarball and passes with the fixed one.\n\nFixes #1741\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-26T09:15:50Z",
          "tree_id": "f79b683b5e354b05183cc33208a64dc0a87d1702",
          "url": "https://github.com/kaappi/kaappi/commit/f0ac6759c0c2c9a20422d556d583176d8da7fad8"
        },
        "date": 1785059334032,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.272342,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.775122,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.919443,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.396947,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006451,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.053764,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.50264,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069423,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.543474,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.932813,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.580197,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.441576,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.805693,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.661727,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045113,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "8c69cbc8f8057433f2b7aad3b614e5eb919615cc",
          "message": "Add SRFI 147 (custom macro transformers) (#1760)\n\n* Add SRFI 147 (custom macro transformers)\n\nThird of 4 tractable pieces of issue #1699, and the first that\ngenuinely needed an engine change. R7RS's <transformer spec> only\naccepts a literal (syntax-rules ...) form; this SRFI extends it to\nalso accept a macro use that itself expands (possibly through several\nsteps) to one -- letting a library define its own\ntransformer-generating-transformer, e.g. the spec's own worked\nexample, a syntax-rules* that auto-wraps multi-form templates in\nbegin. This is exactly what SRFI 148's em-syntax-rules needs, the\nreason this SRFI was implemented.\n\ncompileDefineSyntax/compileLetSyntax/compileLetrecSyntax now route\nevery transformer-spec through a new resolveTransformerSpec, which\nexpands a non-literal spec via the same expander.expandMacro every\nordinary macro call already goes through, looping (depth-bounded)\nuntil it bottoms out at a literal syntax-rules form. Two of the\ngrammar's other alternatives -- bare-keyword aliasing and\nbegin-wrapped-definitions -- are deliberately not implemented, since\nneither is needed by SRFI 148.\n\nVerifying against just the spec's own example wasn't enough --\nbash tests/scheme/run-all.sh caught two real, generalizable bugs no\namount of SRFI-147-specific testing alone would have found:\n\n1. A LIFO root-stack violation: an early draft rooted the resolved\n   spec via pushRoot + defer popRoot() inside compileLetSyntax's\n   per-binding loop, but the same iteration pushes an unrelated root\n   right after, so the deferred pop silently removed the wrong (most\n   recent) entry instead. Surfaced only in srfi257.scm's heavily\n   macro-based library as an unrelated-looking \"invalid syntax\" error.\n   Fixed by popping immediately and explicitly, never via defer across\n   a stretch that itself calls pushRoot -- now documented in\n   .claude/rules/gc-safety.md, whose glob also grew to cover\n   compiler*.zig/expander.zig.\n2. A parent-scope-chain visibility gap: the macro lookup only checked\n   self.macros, unlike the established expandAndCompileMacroUse path,\n   which merges every ancestor Compiler scope's macros first -- a\n   nested child scope (e.g. a let-syntax inside guard's desugared\n   lambda, as SRFI 64's own test-equal produces) never automatically\n   inherits an enclosing scope's macros.\n\nBumps the SRFI count 173->174, reconciled against the canonical\nregistry: 174 implemented + 4 tracked + 30 excluded = 208.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* Fix ancestor-scope shadowing order in resolveTransformerSpec\n\nCodeRabbit review of #1760: the ancestor-chain merge populated\nnearest-to-farthest (matching expandAndCompileMacroUse's own existing\npattern), but since a hash map's put() overwrites, this means a\nFARTHER ancestor's macro definition wins over a NEARER one when both\nredefine the same name -- backwards from correct lexical shadowing.\n\nConfirmed via a 3-level nested-lambda reproduction: an outermost\nmk-transformer definition wrongly won over a middle-scope redefinition\nthat should have shadowed it. Fixed by collecting the ancestor chain\nfirst, then populating farthest-to-nearest (self.macros last of all),\nso a nearer scope's put() call correctly happens after a farther one's.\n\nDeliberately not fixed in expandAndCompileMacroUse itself: it's the\nmost heavily-exercised path in the entire macro system, the scenario\nneeds 2+ ancestor generations redefining the exact same macro name\n(rare, never observed causing a problem there), and touching it\ncarries regression risk disproportionate to this PR's actual scope --\nworth its own dedicated fix.\n\nAlso fixes a markdown-lint nit (blank lines around fenced examples in\ngc-safety.md) and switches a manually-constructed GC/VM test to the\nestablished th.TestContext helper.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-26T20:17:10+05:30",
          "tree_id": "d9c5a05d813bbc52cf3d2b74d38808e12a28449d",
          "url": "https://github.com/kaappi/kaappi/commit/8c69cbc8f8057433f2b7aad3b614e5eb919615cc"
        },
        "date": 1785079333164,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.134434,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.426043,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.650484,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.238276,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006155,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.043289,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.373584,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.054549,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.168129,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.43825,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.239222,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.405442,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.383051,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.805854,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.036393,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "49699333+dependabot[bot]@users.noreply.github.com",
            "name": "dependabot[bot]",
            "username": "dependabot[bot]"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "b5dabae02d77837a641d1093ec0cf942160cecd9",
          "message": "Bump the github-actions group with 2 updates (#1738)\n\nBumps the github-actions group with 2 updates: [actions/checkout](https://github.com/actions/checkout) and [vmactions/freebsd-vm](https://github.com/vmactions/freebsd-vm).\n\n\nUpdates `actions/checkout` from 7.0.0 to 7.0.1\n- [Release notes](https://github.com/actions/checkout/releases)\n- [Changelog](https://github.com/actions/checkout/blob/main/CHANGELOG.md)\n- [Commits](https://github.com/actions/checkout/compare/9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0...3d3c42e5aac5ba805825da76410c181273ba90b1)\n\nUpdates `vmactions/freebsd-vm` from 1.5.0 to 1.5.2\n- [Release notes](https://github.com/vmactions/freebsd-vm/releases)\n- [Commits](https://github.com/vmactions/freebsd-vm/compare/5a72679103d223925653750faa878a143340fbd0...77ed28d336d03fe19a3f4f7266c1d2c4714dd79d)\n\n---\nupdated-dependencies:\n- dependency-name: actions/checkout\n  dependency-version: 7.0.1\n  dependency-type: direct:production\n  update-type: version-update:semver-patch\n  dependency-group: github-actions\n- dependency-name: vmactions/freebsd-vm\n  dependency-version: 1.5.2\n  dependency-type: direct:production\n  update-type: version-update:semver-patch\n  dependency-group: github-actions\n...\n\nSigned-off-by: dependabot[bot] <support@github.com>\nCo-authored-by: dependabot[bot] <49699333+dependabot[bot]@users.noreply.github.com>",
          "timestamp": "2026-07-26T21:19:48+05:30",
          "tree_id": "52428b465ec8c835eff5d0b2d880a43741db8d10",
          "url": "https://github.com/kaappi/kaappi/commit/b5dabae02d77837a641d1093ec0cf942160cecd9"
        },
        "date": 1785083208902,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.973826,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.014041,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.92491,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.466193,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006612,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.052518,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.50808,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.067369,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.320004,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.967904,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.499548,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.481464,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.689994,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.745343,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043951,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "963d3c78b1469da02f3356bcf2efd18ea25c9387",
          "message": "Reseed the default random source in fork(2)ed children (#1761)\n\nThe default SRFI 27 source is created eagerly at VM startup, so a forked\nchild — e.g. every http-listen-prefork worker, which forks via the FFI —\ninherited the parent's exact PRNG state: all workers continued the same\nstream and drew identical \"random\" values (identical kaappi-web session\nids across workers, and a child's draws exactly equal to the parent's).\n\nA pthread_atfork child handler now marks the source stale. The handler\nitself only writes one word: in the forked child of a multithreaded\nparent, anything that can take a libc lock or allocate is off-limits.\nThe next touch of the default source — every path funnels through\ngetRS — reseeds it in place from OS entropy: in place so the heap object\ncaptured by (srfi 27)'s load-time default-random-source binding stays\nthe live default, and flag-cleared-first so an explicit randomize!/\npseudo-randomize!/state-set! in the child stays authoritative.\n\nWindows and WASI have no fork; the handler is compiled out there.\nCross-compiled x86_64-linux, aarch64-windows, aarch64-netbsd, and wasm;\nfull unit + Scheme suites green (1986 pass).\n\nRegression tests: tests/scheme/ffi/fork-reseed.scm (real fork via FFI —\nthe child's 8 draws were element-for-element identical to the parent's\nbefore this fix) and a state-replay unit test in tests_random_port.zig.\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-26T21:20:10+05:30",
          "tree_id": "b2e96de4d809d631ff1ed3722f4a634a23f790b2",
          "url": "https://github.com/kaappi/kaappi/commit/963d3c78b1469da02f3356bcf2efd18ea25c9387"
        },
        "date": 1785083472932,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.301921,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.638808,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.948636,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.434615,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006497,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.055054,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.509945,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.06978,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.552324,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 2.001987,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.61036,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.440979,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.852601,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.741837,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044776,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "845b75622e3d7a4eac3e7d63f6adee32918a3075",
          "message": "Extend SRFI 147 with begin-wrapped and bare-alias transformer specs (#1762)\n\nDeeper research for SRFI 148 (reading its reference implementation, not\njust the spec prose) found that em-syntax-rules's own core mechanism\n(em-syntax-rules-aux1/aux2) bottoms out through exactly\n`(begin (define-syntax a spec) a)` -- a private helper definition\nfollowed by a bare reference to it. Both grammar alternatives this\nneeds (begin-wrapped definitions, and bare-keyword aliasing of a\nnon-builtin macro) were deferred in #1760 based on an earlier, shallower\npass that concluded neither was needed.\n\nresolveTransformerSpec now returns an already-parsed Transformer instead\nof raw syntax-rules source, since the bare-symbol alias case has no\nsource to hand back -- only a Transformer an earlier step already\nparsed. Aliasing a builtin special form still correctly falls through to\nInvalidSyntax: builtins are recognized structurally, never stored as\nTransformer values in the macro table a bare symbol resolves against.\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-26T16:43:21Z",
          "tree_id": "ed8bbbe59ae47dc0485d217451db18b135a1717a",
          "url": "https://github.com/kaappi/kaappi/commit/845b75622e3d7a4eac3e7d63f6adee32918a3075"
        },
        "date": 1785086432884,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.309789,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.914241,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.930957,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.445399,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006397,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.054384,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.506559,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.06879,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.542347,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.972524,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.607075,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.437158,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.84202,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.676303,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044597,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "826eeb3c9bea60ab1ec55b5584c00d9d624d627c",
          "message": "Persist begin-wrapped SRFI 147 helpers, fix double-finalization leak (#1763)\n\nTracing SRFI 148's actual reference implementation (not just its grammar)\nfound that em-syntax-rules-aux2's own base case expands to\n`(begin (define-syntax o spec) o)`, where the SURROUNDING syntax-rules\nbody also calls `o` directly from within its own rules (not just as the\nbare tail) -- so `o` must keep resolving every time the macro being\ndefined here is later invoked, not just while resolving that one\ntransformer-spec. A helper registered only in resolveTransformerSpec's\ntransient, function-local merged_macros (discarded once that call\nreturns) cannot satisfy this -- confirmed via direct reproduction\nfailing with \"undefined variable '__hyg_N_helper'\" on every subsequent\nuse of the outer macro.\n\nFixed by registering each begin-internal helper into the real,\npersistent-for-this-scope's-lifetime self.macros (and lib_env at library\ntop level), exactly like an ordinary define-syntax at the same nesting\ndepth gets.\n\nThat fix immediately surfaced an adjacent bug under the unit test\nsuite's leak-checking allocator: a begin-wrapped alias can hand the\nexact same Transformer Value to two or more different binding sites, and\ncaptureLocalsOnTransformer/computeBoundFreeRefs both allocate and\nunconditionally overwrite a slice field with no free of what was there\nbefore -- a second finalization pass on an already-finalized object\nleaked the first allocation. Fixed by merging both calls into one\nfinalizeTransformer, guarded by a new Transformer.finalized flag.\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-26T18:22:45Z",
          "tree_id": "ef8cad314bf1b89c43e8502abdd0d41f47ba0583",
          "url": "https://github.com/kaappi/kaappi/commit/826eeb3c9bea60ab1ec55b5584c00d9d624d627c"
        },
        "date": 1785092603121,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.325883,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.01117,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.694687,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.425462,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00687,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.045787,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.395867,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.059723,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.303349,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.517346,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.325476,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.443159,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.472464,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.041009,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.038237,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "26d841123133d7d96a61f4d95ce193a2a924a47c",
          "message": "Fix let_syntax_peer_names/vals leak when siblings share a Transformer (#1764)\n\nCodeRabbit-caught on #1763, after CI had already auto-merged it: the\nsame overwrite-without-free hazard just fixed for captured_locals/\nbound_free_refs (via finalizeTransformer) also applies to\ncompileLetSyntax's own let_syntax_peer_names/vals bookkeeping, which\nlives in a separate code block outside finalizeTransformer's reach.\nReachable as soon as two sibling let-syntax bindings resolve to the same\nTransformer object (a begin-wrapped helper reference for one, a bare\nalias of that same helper for the other).\n\nFixed with a narrower guard than Transformer.finalized: a linear scan of\nthis call's own tx_vals prefix for an identical Value already processed\nearlier in the SAME loop. This can't be a permanent per-object flag like\nfinalized, since a transformer aliased into some OTHER, unrelated\nlet-syntax form later genuinely needs its own peer snapshot computed\nagainst that different form's sibling set.\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-26T19:51:53Z",
          "tree_id": "b0f9bd8023419df813fea7d50f781e9c0410c7a4",
          "url": "https://github.com/kaappi/kaappi/commit/26d841123133d7d96a61f4d95ce193a2a924a47c"
        },
        "date": 1785097600957,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.335232,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.712538,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.894163,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.403217,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006376,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.053978,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.503101,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069153,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.506244,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.960459,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.599976,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.428366,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.806329,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.456877,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043949,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "beaee758678073c163814e3b772586296e066b42",
          "message": "Free let_syntax_peer_names/vals before cross-form recomputation too (#1765)\n\nCodeRabbit-caught follow-up to #1764's own fix (found in that PR's\nreview, after CI had already auto-merged it): the tx_vals-prefix scan\nonly catches the same Transformer reappearing within one let-syntax\nform. It genuinely can't skip recomputation when that transformer is\naliased into a DIFFERENT, unrelated let-syntax form later -- that\nform's own sibling set differs and needs its own snapshot -- but the\nrecomputation itself still unconditionally overwrote whatever an\nearlier form's processing had already set, with no free.\n\nFixed by freeing the previous let_syntax_peer_names/vals pair\nimmediately before every overwrite, regardless of which case (within-\nform repeat vs. cross-form reuse) triggered it. Mutation-tested: a\nsecond reproduction (the same helper aliased into two separate,\nsequential top-level let-syntax forms, each with a distinct sibling of\nthe same name) confirms the recomputation itself still resolves\ncorrectly, and leaks 2 allocations without this fix.\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-26T21:21:54Z",
          "tree_id": "6ee4ec3f51b4725f059bf7f7dcf68245d301b6d8",
          "url": "https://github.com/kaappi/kaappi/commit/beaee758678073c163814e3b772586296e066b42"
        },
        "date": 1785102960674,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.316555,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.250153,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.900124,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.412647,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006392,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.054069,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.507157,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069469,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.52858,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 2.007143,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.591855,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.429864,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.864783,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.66001,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044588,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "4fe15c21592e12c4ca0999662c85931c864a868f",
          "message": "Freeze R7RS 4.3.1 peer snapshot permanently, not per-call (#1766)\n\nCodeRabbit-caught, and more serious than it first looked: the previous\nfix (free the old let_syntax_peer_names/vals pair before every\ncross-form overwrite) treated recomputing the sibling-suppression\nsnapshot against a different let-syntax form's own bindings as\nnecessary and correct. It isn't. R7RS 4.3.1's peer snapshot exists to\nfreeze a template's free references against whatever was in scope at\nthe template's own true point of definition, specifically so that\nlater shadowing at some other use site can't reach in and change what\na name resolves to -- recomputing it against a different form's outer\nbindings is exactly the interference the mechanism exists to prevent.\n\nConfirmed via a properly discriminating reproduction (a plain top-level\nprocedure as the shared free reference can't tell the two designs\napart at all, since procedure bindings were never captured by\nlet_syntax_peer_vals in the first place -- only a macro, redefined\nbetween two forms, exposes it): recomputing silently changed a\npreviously-correct answer from 11 to -10. Nesting the reuse inside the\ndefining form's own body was worse, corrupting the outer binding too\n(500 instead of 6).\n\nFixed by replacing the per-call tx_vals-prefix scan with a permanent,\nonce-per-object Transformer.peers_computed flag, mirroring `finalized`\nbut kept as its own field since peer suppression is\ncompileLetSyntax-specific. Also applies CodeRabbit's suggested\natomic-dupe pattern (dupe both new slices before touching the old ones,\nso a second-dupe OOM can't leave one field freed and the other stale).\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-26T23:08:20Z",
          "tree_id": "b7e150daffa191224dc6bd6bc28487013267b00d",
          "url": "https://github.com/kaappi/kaappi/commit/4fe15c21592e12c4ca0999662c85931c864a868f"
        },
        "date": 1785109579145,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.362588,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.258808,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.904272,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.508168,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006376,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.054694,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.51119,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069472,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.489568,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.999023,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.591191,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.436074,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.866375,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.630811,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044109,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "4b1c584c78db89eac640c54b8e808cfa22b2b5ef",
          "message": "Set peers_computed only after the snapshot is durably stored (#1767)\n\nCodeRabbit-caught: the previous commit set Transformer.peers_computed\ntrue immediately, before the fallible allocations (peer_names_f/\npeer_vals_f appends, both dupe calls) that actually build the\nlet_syntax_peer_names/vals snapshot. An OOM partway through would leave\nthe flag permanently true with both fields still at their default-empty\nvalue -- every later reuse of that transformer would then treat \"no\nsibling suppression needed\" as the final, correct answer instead of\nretrying the computation.\n\nFixed by moving the flag assignment to strictly after both slices are\ndurably stored, immediately before the self.macros.put that was already\nthere.\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-27T00:21:06Z",
          "tree_id": "36ff10ce1f3a4d8689764568c132e67fef36404c",
          "url": "https://github.com/kaappi/kaappi/commit/4b1c584c78db89eac640c54b8e808cfa22b2b5ef"
        },
        "date": 1785113845148,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.3016,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.414037,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.901747,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.400381,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006399,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.054109,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.508896,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069633,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.542661,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.998438,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.584733,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.431699,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.855915,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.632937,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044316,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "76d6012c1338dd8215ff39a595eff82a777b3df7",
          "message": "Fix hygiene rename split between a nested syntax-rules pattern and its own quoted template (#1773)\n\nrenameForHygiene unconditionally treated any quoted identifier as inert\nliteral data, skipping the hygienic rename. That's correct for ordinary\nquoted data, but wrong when the quote sits inside a nested syntax-rules\ntemplate being generated by an outer macro: the corresponding pattern-side\noccurrence of the same identifier (walked without QUOTE_FLAG) already\nclaimed a rename, and the template must match it exactly or the inner\nmacro's own pattern-matcher can never bind the two together -- the\ntemplate's occurrence passed through literally instead of substituting the\ncall's actual argument.\n\nFound while porting SRFI 148's reference implementation, whose CK-machine\ntechnique defines helper macros via nested syntax-rules with quoted\ntemplates throughout -- but the bug is general and predates this session's\nSRFI work entirely.\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-27T02:26:44Z",
          "tree_id": "8ebdf1bbd2d5898b4717580929fe6ac9047fc1f9",
          "url": "https://github.com/kaappi/kaappi/commit/76d6012c1338dd8215ff39a595eff82a777b3df7"
        },
        "date": 1785122065891,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.974829,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.821687,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.914973,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.346275,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006713,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.052673,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.506153,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068082,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.339907,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.943199,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.527337,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.473816,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.720487,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.780091,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044355,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "672db1f109080ba0300b8be4a29eebf4fb7572fa",
          "message": "Promote expt to complex for negative base + non-integer exponent (#1725) (#1769)\n\nexptFn's real-number fallback called std.math.pow unconditionally,\nwhich returns +nan.0 for a negative base combined with a non-integer\nreal exponent (e.g. (expt -8.0 0.5), (expt -8 1/3)) instead of the\nwell-defined complex result — the same input shape sqrt already\npromotes correctly.\n\nFactored the existing z^w = e^(w*ln(z)) formula out of the\nalready-complex branch into a shared complexPowGeneral helper, and\nroute a finite negative base with a finite non-integer exponent\nthrough it before falling back to std.math.pow. Integer exponents\n(even via a flonum, e.g. -8.0^3.0) are left untouched since pow\nalready handles those correctly for a negative base.",
          "timestamp": "2026-07-27T08:05:00+05:30",
          "tree_id": "2c383fac6554457a1284c7c0b6197f216cad3a98",
          "url": "https://github.com/kaappi/kaappi/commit/672db1f109080ba0300b8be4a29eebf4fb7572fa"
        },
        "date": 1785123400646,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.092422,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.545508,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.950123,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.412205,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006846,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.052556,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.507999,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068205,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.318538,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.969588,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.530846,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.48407,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.766816,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.742168,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.04521,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "7fd9417875c9b0dc122d7f8afd5630b3de9f56d2",
          "message": "Detect cycles through record instances in the printer (#1713) (#1768)\n\nwrite/display/write-shared already datum-labeled cycles through pairs\nand vectors, but record instances were invisible to that machinery, so\nprinting fell through to the plain depth-limited recursive printer. A\ndirect self-reference merely recursed to the depth cap, but a record\nfield that's a vector of records which each reference it back (e.g.\ntwo mutually-referencing record types, the SRFI 209 enum/enum-type\nshape that motivated this issue) fans out combinatorially at every\nlevel of that recursion, hanging the process well before the cap.\n\nRecord instances now join pairs and vectors in both cycle-detection\npasses (markCyclesRec, markShared) and in the shared-aware printer, so\na cyclic web of records prints with #N=/#N# datum labels instead of\nlooping forever.\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-27T08:03:58+05:30",
          "tree_id": "5f13324199f5d46f80b9ca86ec5068d189b39932",
          "url": "https://github.com/kaappi/kaappi/commit/7fd9417875c9b0dc122d7f8afd5630b3de9f56d2"
        },
        "date": 1785123421662,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.341017,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.197353,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.895551,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.417431,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006274,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.053498,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.506268,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069531,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.512027,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.94447,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.621699,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.430284,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.805024,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.640263,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044066,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "281e135c480862edf2a01eaf1e36e5cb8b20f10d",
          "message": "Refuse kaappi compile when an import can't resolve at runtime (#1743) (#1770)\n\nThe compiled binary's own runtime starts a fresh VM with no library\nsearch path, and the native backend never bundles .sld sources into\nthe binary the way --compile/-Dbundle-src does. So any import the\ncompiling VM resolves from a file — a third-party package or one of\nthe 159 portable SRFIs, not just kaappi-json — compiled cleanly but\ndied at runtime with \"library not found\" despite kaappi compile\nreporting success and exiting 0.\n\nemitLlvmFile now detects this by reusing the .sbc bundler's own\nfile-collection hook (populated only when a library is resolved from\ndisk, never for built-ins) and refuses to emit anything, naming the\nunresolvable library file(s) and pointing at the interpreter or\nzig build -Dbundle-src as working alternatives. Covers both\nkaappi compile and --emit-llvm, with no false positives for built-in\nlibraries or self-contained define-library files.\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-27T08:05:49+05:30",
          "tree_id": "31727b22fbac02b7bcb61f25c539e58142e355df",
          "url": "https://github.com/kaappi/kaappi/commit/281e135c480862edf2a01eaf1e36e5cb8b20f10d"
        },
        "date": 1785123634432,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.32826,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.386337,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.902162,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.43885,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006334,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.05401,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.508503,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069434,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.536588,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 2.002797,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.574674,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.422828,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.812384,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.617504,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043845,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "4284fadcb52be2f98e5af097943da6dad8b8a33d",
          "message": "Fix let-values/let*-values corruption when list/apply/call-with-values are shadowed (#1771)\n\nBoth forms desugar internally to code that invokes list, apply, and\ncall-with-values by name. Those were ordinary, shadowable identifier\nreferences, so a program redefining any of them at the top level --\nexactly what SRFI 101 does for `list` -- could corrupt the desugaring\ninstead of the compiler always meaning the true (scheme base)\nprocedures. The reported symptom was a spurious \"apply: expected\nproper list, got #<record_instance>\" error: the shadowed `list`\nhanded back something other than a real list, and the\ncorrectly-resolved `apply` then correctly rejected it.\n\nCompiler-synthesized references to these three names now resolve\nthrough a protected path: a __kaappi_base__-prefixed symbol that\nget_global/call_global recognize and resolve against (scheme base)'s\nown pristine export table (captured once at VM startup, never\ntouched again) instead of the live, mutable globals map. The\nreference has to stay a plain symbol rather than a pre-resolved\nvalue, since the .sbc bytecode cache has no serialization tag for\nprocedure constants and would silently corrupt one to nil on a cache\nround-trip.\n\nAlso fixes an adjacent gap: even the \"protected\" call_global fast\npath already used by let*-values only ever guarded against lexical\nshadowing, not a top-level redefinition of call-with-values itself --\nand isContinuationBarrier needed to recognize the new prefixed name\nso call-with-values keeps the standard frame setup its continuation\ncapture semantics depend on.\n\nFixes #1715\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-27T08:23:29+05:30",
          "tree_id": "d05dd7be0867f3efd4b318aaf0b127e4b516af6a",
          "url": "https://github.com/kaappi/kaappi/commit/4284fadcb52be2f98e5af097943da6dad8b8a33d"
        },
        "date": 1785124210361,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.397541,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.597212,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.940857,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.528775,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006426,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.055121,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.515354,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068968,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.510032,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.996336,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.63078,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.44271,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.85868,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.665281,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043974,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "2cad8e5056713db621134718eb456cd51cc7762f",
          "message": "Isolate record-type/define-values desugaring from vm.macros (#1718) (#1774)\n\ndefine-record-type/define-values compiled their generated definitions\nagainst the process-global macro table instead of an isolated one, so\nonce any program imported a macro shadowing a core special form (e.g.\nlambda), every later library's own record types or define-values forms\ncould fail to compile -- or, when the shadowed name was\ndefine-record-type itself, be silently dropped with no error, since\ncompileLibExpr unconditionally returned after deferring to macro-aware\ncompilation without actually performing it.\n\nRecord-type/define-values desugaring now uses a macro table scoped to\nthe current library (or none at all, for record-type's own\ncompiler-synthesized forms, which never contain user subexpressions),\nand the define-record-type shadow check now consults the active\nlibrary's own scope rather than the whole process's. Also make\nrenaming a special form on import (`(rename (only (scheme base) let*)\n(let* my-let*))`) fail with a clear diagnostic at the import\ndeclaration instead of silently producing a binding that resolves to\nnothing.\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-27T08:23:43+05:30",
          "tree_id": "4b130be25f54c65fb611e7e38df0d56f6cd1b85d",
          "url": "https://github.com/kaappi/kaappi/commit/2cad8e5056713db621134718eb456cd51cc7762f"
        },
        "date": 1785125014934,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.330009,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.055987,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 1.008146,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.79278,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006359,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.056234,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.560776,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.07232,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.679658,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 2.215757,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.593543,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.434807,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.84345,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.668139,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043907,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "fb9e93dc6365cfc8765e5b56479eb06753976947",
          "message": "Fix two macro-expansion bugs found while investigating SRFI 148 (#1776)\n\ninstantiateTemplate's (quote ...) fast path triggered for any template\nsub-list whose first element was literally the symbol quote, regardless of\nlength. R7RS quote is strictly unary, so a longer list merely starting with\nquote for an unrelated reason (e.g. passing the bare symbol quote as one\nargument among several to some other macro) was misparsed as a 2-element\nquote form, silently dropping everything after the second element.\n\nparseSyntaxRules's custom-ellipsis-argument detection didn't unwrap a\nusertext-marker-wrapped value -- the protocol nested syntax-rules\ngeneration uses when substituting an outer pattern variable into the\ngenerated macro's own ellipsis-argument position -- so a NESTED_SR_FLAG-\nwrapped ellipsis symbol was silently missed and misparsed as part of the\nliterals list instead.\n\nBoth are general, pre-existing bugs unrelated to any specific SRFI, found\nwhile porting SRFI 148's em-syntax-rules mechanism (issue #1699's final\nslice). SRFI 148 itself remains blocked on a separate, deeper performance\nproblem with generating-macro chains (#1775) not addressed here.\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-27T04:55:52Z",
          "tree_id": "58b9111655f9294c65d58c5bef7656892aa2a390",
          "url": "https://github.com/kaappi/kaappi/commit/fb9e93dc6365cfc8765e5b56479eb06753976947"
        },
        "date": 1785130934384,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.417033,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.02136,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.997704,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.656057,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006364,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.05532,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.558627,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.072557,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.632659,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 2.177721,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.611033,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.435193,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.854334,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.694208,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045073,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "87085096f1b5c93e03f37f6cd58e6e1e46adbc8b",
          "message": "Fix string->number to reject misplaced digit-separator underscores (#1724) (#1777)\n\nstringToNumber's small-integer and rational numerator/denominator parsing\ncalled std.fmt.parseInt directly on unvalidated input, which has its own\nunderscore convenience more permissive than SRFI 169 (it only rejects a\nleading/trailing underscore, not a doubled one), so \"1__2\" silently\ncollapsed to 12 instead of #f. Validate and strip underscores once, up\nfront, using bignum.stripUnderscores -- the same validator the reader and\nthe hex-float/bignum-overflow paths already relied on -- before any\nshape-specific parsing runs.\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-27T11:15:03+05:30",
          "tree_id": "7cfedd6983279e5c466ab0ef3525d70df78b1d74",
          "url": "https://github.com/kaappi/kaappi/commit/87085096f1b5c93e03f37f6cd58e6e1e46adbc8b"
        },
        "date": 1785136406822,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.391552,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.776782,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.963213,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.617471,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006384,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.055219,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.546729,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.071155,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.707694,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 2.100148,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.613748,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.434456,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.840036,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.622388,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043399,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "d5f6c255d676645853700203b45877bcacd02a35",
          "message": "Give kaappi compile binaries real argv via (command-line) (#1744) (#1778)\n\nThe LLVM emitter generated every compiled binary's entry point as\n`define i32 @main()` -- zero parameters -- so argc/argv never reached\nthe runtime and (command-line) always returned () regardless of what\narguments the binary was invoked with.\n\nmain now takes the standard C (argc, argv) pair and hands argv to a\nnew kaappi_set_command_line_args runtime export right after init,\nwhich scans it to its NULL sentinel (every native_backend_supported\ntarget's libc/CRT guarantees argv[argc] == NULL, so argc itself never\nneeds to be threaded further). A compiled binary's (command-line) now\nreturns its own path followed by its real arguments, mirroring how\nthe interpreter reports a script's filename followed by its arguments.\n\nAdded a dedicated e2e phase (test-argv.scm + run-e2e.sh/run-e2e.ps1)\nsince the existing interpreter-vs-native parity loop can't cover this:\nthe leading \"command name\" element legitimately differs between an\ninterpreted and a compiled run of the same program.",
          "timestamp": "2026-07-27T11:36:35+05:30",
          "tree_id": "37feabeaf197d5b2de765a6914829c90152d0754",
          "url": "https://github.com/kaappi/kaappi/commit/d5f6c255d676645853700203b45877bcacd02a35"
        },
        "date": 1785136818600,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.396496,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.633474,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.94693,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.585681,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006505,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.056266,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.514895,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069434,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.661279,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 2.113426,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.598573,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.431568,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.029021,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.686757,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044053,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "db38f24a8c494cb5f4c01bad8016fbefa6ac4186",
          "message": "Fix custom-ellipsis recognition in ordinary template expansion; split tests_macros.zig (#1779)\n\ninstantiateTemplate's two ellipsis-detection sites (the \"(... template)\"\nescape check and the \"element followed by ellipsis\" check) required a bare\nsymbol, but a nested syntax-rules template's ordinary (non-quoted) position\ncan receive a custom ellipsis identifier substituted from an outer pattern\nvariable, wrapped by NESTED_SR_FLAG's usertext-marking protocol. Neither\nsite unwrapped it, so the ellipsis was silently unrecognized outside quote\n(where the same substitution happens to skip wrapping entirely) -- the\nelement was emitted literally instead of splicing its repetitions.\n\nCaught by CodeRabbit's review of the previous commit, which fixed the\npattern-matching/parsing-side half of this same class of bug but missed\nthis instantiation-side one.\n\nAlso splits the new nested-syntax-rules-generation regression tests into\ntheir own file (tests_macros_nested_sr.zig), keeping tests_macros.zig under\nthe project's 1500-line file-size policy (also flagged by CodeRabbit).\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-27T06:17:10Z",
          "tree_id": "0ef02e08d53bc4b17aa522cfefaca0cb25518849",
          "url": "https://github.com/kaappi/kaappi/commit/db38f24a8c494cb5f4c01bad8016fbefa6ac4186"
        },
        "date": 1785137317549,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.113651,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.198187,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.95809,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.4621,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006897,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.053776,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.524834,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070402,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.366506,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.986485,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.560591,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.475399,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.743634,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.838953,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045828,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "129c56acf712a8da04b9282385400a8c83f95ba3",
          "message": "Support letrec*-style mutual reference in define-values (#1780)\n\nR7RS draws no distinction between `define` and `define-values` for a\nbody's letrec* scoping (5.3.2/5.3.3): a definition may reference\nanother definition appearing later in the same body, as long as the\nreference isn't evaluated before that binding is initialized. Plain\n`define` already worked this way, but a `define-values` clause could\nnot reference a name bound by a later `define-values` (or `define`)\nclause -- the reference silently compiled as a global lookup instead\nof a local/upvalue (since the name hadn't been declared as a local\nyet), surfacing as a runtime \"undefined variable\" error once the\nenclosing procedure was actually called.\n\nThe root cause is scanBodyDefs, the shared prescan that gives `define`\nits forward visibility by declaring every leading definition's name\nas a boxed local before compiling any of their init expressions -- it\nonly recognized `define` and `define-record-type`. `define-values` now\nparticipates: BodyScan gains an ordered `DefStep` (a `.simple`\nname-to-init step, or a `.values_group` step carrying an\nalready-desugared call-with-values/set! form, since one clause can\nbind 0..N names from a single shared init that doesn't fit the\nexisting one-name-one-init shape).\n\nTwo independent, duplicated \"declare locals then compile inits\" loops\nconsume the scan's output and both needed the identical fix:\ncompiler_lambda.compileBodyForms (let-family bodies and the legacy\nlambda path) and compiler_ir.compileLambdaWithIR (the modern\nIR-pipeline lambda path, reached only via `(define name (lambda\n...))` long-hand or a bare `(lambda ...)` -- the far more common\n`(define (name args) body)` shorthand always routes through the\nformer).\n\nFixes #1719\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-27T11:51:25+05:30",
          "tree_id": "2d23485e7e99d533716dea4339355876a7dc6496",
          "url": "https://github.com/kaappi/kaappi/commit/129c56acf712a8da04b9282385400a8c83f95ba3"
        },
        "date": 1785137684171,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.43366,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.878428,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.968242,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.608393,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00635,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.055141,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.527016,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.071303,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.587695,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 2.035692,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.617809,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.437276,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.90263,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.69979,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045491,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "78744a1727fc64b53344bc6dede4cd3eba755717",
          "message": "Detect colliding import bindings across libraries (#1726) (#1781)\n\n(import (srfi 28) (srfi 29)), which both export format, silently picked\nwhichever library came last in the import-set list with no diagnostic\neither way, reversing the order flipped which binding won. R7RS 5.2 says\nimporting the same identifier from two different libraries with different\nbindings is an error. handleImportInto and the environment procedure now\ntrack which import-set in the same batch first claims each name and reject\na later one that would bind it to a genuinely different value, naming both\nimport-sets and the identifier atomically, per import-set. Re-importing the\nidentical binding through two paths (a diamond dependency) still merges\nsilently, since that is the same binding, not two different ones, and\nshadowing across separate top-level (import ...) forms stays legal.\n\nGetting there surfaced two related, previously-invisible bugs. First, a\nnon-exported helper macro reachable only through an exported macro's\nexpansion (e.g. SRFI 64's test-assert -> %test-comp1body chain) could leak\ninto an importer's globals as a plain, callable value once the resolved\nexport set was routed through a scratch map first -- true for\nonly/except/prefix/rename already, and now also true for a plain,\nunmodified import since it needs the same scratch-map resolution to run the\ncollision check. Fixed by chasing the transitive macro closure only into\nthe real, final target (importBinding's new chase_transitive parameter),\nnever a scratch map that exists purely to answer \"what does this\nimport-set resolve to\". Second, a multi-set (import a b c) form that\nfailed partway through kept processing the rest, letting a later,\nsuccessful library load's own native calls clobber the shared\nerror-detail buffer and reduce a specific message to a bare \"invalid\nsyntax\" by the time it was reported. handleImportInto now stops at the\nfirst failing import-set, matching environment's existing behavior.\n\nA few portable SRFI libraries ((srfi 167), (srfi 146 hash)) had internal\ncollisions between (srfi 69) and (srfi 128) over string-hash/\nstring-ci-hash that previously loaded silently; several SRFI test files\nand two native-compile fixtures likewise combined libraries with\nundiagnosed collisions (square colliding with (scheme base), etc.). All\nnow disambiguate explicitly with only/except/rename.\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-27T13:17:19+05:30",
          "tree_id": "049fb848c8280b0c0a802a32221b0096c91e93f1",
          "url": "https://github.com/kaappi/kaappi/commit/78744a1727fc64b53344bc6dede4cd3eba755717"
        },
        "date": 1785141244839,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.326866,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.581544,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.946035,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.733654,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006314,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.05519,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.513521,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070539,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.579726,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 2.058079,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.603111,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.439936,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.827459,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.674988,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043456,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "c9ce6cffd9a44d50aa2f9bb2bb5871184e5ebafa",
          "message": "Fix literal let/if matching in macro-generated nested syntax-rules (#1720) (#1782)\n\nlet and if are deliberately excluded from well_known_forms so a macro's\nown executable use of them stays hygienic under use-site shadowing, but\nthat exclusion meant a nested syntax-rules's let/if LITERAL (e.g. a\ngenerated dispatch macro's syntax-rules (let) ...) also got hygiene-\nrenamed by the generating macro's expansion. matchPattern's literal\nfallback only stripped a hygiene rename off the input side (for the\nreverse case, e.g. SRFI 257's cm-match), never off the literal side, so\na renamed literal could never match a real, unrenamed token typed at the\ngenerated macro's own use site. Strip both sides before comparing.\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-27T13:39:24+05:30",
          "tree_id": "6bbab6baa07bd8094071a6b07e45cc815011efe0",
          "url": "https://github.com/kaappi/kaappi/commit/c9ce6cffd9a44d50aa2f9bb2bb5871184e5ebafa"
        },
        "date": 1785142078322,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.043022,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.804879,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.931135,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.469486,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006701,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.054179,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.515231,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068757,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.283002,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.973155,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.540703,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.471939,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.706167,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.816634,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045194,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "f990d49a578a5d576c4a10df171762560b2b52b0",
          "message": "Build Linux release binaries against glibc so dynamic loading works (#1783)\n\nZig resolves the bare x86_64-linux / aarch64-linux targets to musl\nstatic, and static musl cannot dlopen — so every released Linux binary\nrejected (kaappi ffi) with 'Dynamic loading not supported', making the\nwhole C-extension ecosystem (net, http, sqlite, pg, redis, crypto)\nunusable from a release install. The docs site's docs-samples CI\ncaught it; the nightly ecosystem tests never could, because they build\nkaappi natively (glibc, dynamic) instead of testing release artifacts.\n\nThe two mainstream Linux targets now compile against glibc with a 2.28\nfloor (RHEL 8 / Debian 10 / Ubuntu 18.10+). A new zig_target matrix\nfield carries the compile triple so artifact names — which install.sh\nmatches (libkaappi_rt-<target>.a) — stay unchanged. Interpreter-tier\narches (riscv64, s390x, ppc64le) stay musl-static: their artifacts\nwere validated on Alpine VMs and gain nothing from a glibc floor.\nTrade-off: glibc binaries don't run on musl distros; Alpine users\nbuild from source until a musl-dynamic variant ships as an extra\nartifact.\n\nA linux-ffi-smoke job now runs the actual x86_64 and aarch64 artifacts\nand proves ffi-open + ffi-fn against libm.so.6 before the release job\npublishes anything, so this class of regression cannot ship again.\n\nVerified locally with zig 0.16.0: x86_64-linux builds 'statically\nlinked' (the bug), x86_64-linux-gnu.2.28 and aarch64-linux-gnu.2.28\nbuild 'dynamically linked' with the correct glibc interpreters, and\n'zig build lib' produces libkaappi_rt.a for the gnu targets.\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-27T13:42:36+05:30",
          "tree_id": "0e204dc687e640088a69ea69b533a17f9cd24391",
          "url": "https://github.com/kaappi/kaappi/commit/f990d49a578a5d576c4a10df171762560b2b52b0"
        },
        "date": 1785142855659,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.099848,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.985262,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.938519,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.467162,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006723,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.053164,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.515844,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.067643,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.3342,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.972837,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.531973,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.473288,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.707538,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.811869,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045796,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "c878b6983a7fbe64db8036e2d746fcb67cfb9838",
          "message": "Bound the set! pre-scan so macro-generating macros stop compiling exponentially (#1775) (#1784)\n\n* Bound the set! pre-scan so macro-generating macros stop compiling exponentially\n\nCompiling a macro that generates another macro — SRFI 148's em-syntax-rules,\nSRFI 257's CK-machine combinators — cost time exponential in the generated\nmacro's rule count. An 8-rule case took 31s; SRFI 257's own shipped test\nsuite spent 281s of its 289s runtime in the compiler.\n\nThe cost was never in the expander, despite --timings pointing there\n(`expand 2765.8ms`). It was compiler.collectSetTargets, the top-level `set!`\npre-scan. That scan expands macros so it can see a `set!` introduced by a\nmacro template (#1250) — which makes it a speculative evaluator of\ncompile-time macro code, and it explores branches the real compiler never\ntakes. At `(m kt kf)`, where `m` is a helper the enclosing expansion just\ndefined with define-syntax, the scan has no binding for `m`, so it treats\nboth continuations as ordinary sub-forms and expands macros inside each.\nThe real compiler registers `m` and follows exactly one. Every such fork\ndoubles the work.\n\nBound the scan at 4096 expansions per top-level form. Exceeding the bound is\nsafe by construction rather than by luck: it sets Compiler.set_targets_all,\nand both consumers then assume every name is a `set!` target — box every\nlocal, fold nothing. A truncated scan loses optimization, never correctness.\nThe pre-existing `depth > 256` cutoff now feeds the same flag; until now it\nsilently returned a partial answer, which is exactly the under-approximation\n#1168/#1250 are about.\n\n4096 is ~2.5x the highest count any non-pathological top-level form in this\nrepo's Scheme suites reaches (p99.99 = 1649; 87% of forms need none at all)\nand well below the 6299+ the macro-generating cases start at. The headroom\nis deliberate: truncation costs ~2x runtime on compute-heavy code, so\nordinary programs must never reach the limit.\n\nAlso give the pre-scan the fixed-point check expandAndCompileMacroUse\nalready has. SRFI 219 rule 3 is `(define name expr)` -> `(define name expr)`,\nso every plain `define` in a program importing it was re-expanded 257 times\nuntil the depth cap — and, once the depth cap became meaningful, would have\nsent ordinary code down the conservative path.\n\n  8-rule generating macro   31.6s -> 4.6s\n  srfi257-full.scm         280.8s -> 16.2s\n  srfi257-rx-full.scm      102.1s -> 23.5s\n  7/9-rule macro         14.9s/71.9s -> 4.8s/4.9s (flat, was exponential)\n\nNo change to compile time under the budget or to runtime: fib/tak/ack/\nheavy-arith/const-prop are unchanged.\n\ndocs/dev/timings.md gains a section on the trap that cost two earlier\nsessions: --timings names the stage, never the caller. `sample` put 99% of\nsamples under collectSetTargets on the first run.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Address CodeRabbit review on the set! pre-scan bound\n\nTwo of the three findings applied:\n\n- `prescan_expansion_limit` is now `threadlocal`, matching\n  `ir.optimize_enabled`'s documented rationale (an SRFI-18 child thread\n  compiling concurrently keeps the default instead of racing on whatever a\n  test left in a shared global). `prescan_truncations` beside it was already\n  threadlocal.\n- Tagged the timings.md fence `text` so markdownlint passes.\n\nDeclined sharing compiler_macro.MAX_MACRO_EXPANSION_DEPTH as the pre-scan's\ndepth cap, and said why in the code: the two 256s count different things.\nThat one bounds the real expansion of code that will be compiled, and\nexceeding it is a user-visible KP2003 error. This one bounds a speculative\nwalk that also descends into branches the compiler discards, so it is\nreached by programs whose real expansion depth never comes close — every\nSRFI 257 suite trips it several times per run while compiling and passing\nnormally. A shared constant would assert an equivalence the measurements\ncontradict.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-27T10:12:33Z",
          "tree_id": "89dcef06044fc6437283eb360b45d4a83049b153",
          "url": "https://github.com/kaappi/kaappi/commit/c878b6983a7fbe64db8036e2d746fcb67cfb9838"
        },
        "date": 1785149454802,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.357223,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.347647,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.950672,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.615654,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006296,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.05487,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.516252,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070482,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.513056,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 2.044553,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.592477,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.429877,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.917026,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.632425,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043671,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "71569effd2b3b3da93737f5f2fc004d46825dae2",
          "message": "Stop the reactor timer tests failing on a poll() that returns a tick early (#1785)\n\n`tests_reactor.test.addTimer fires when its deadline passes` failed once on\nwindows-x64-test during CI for #1784 (expected 1, found 0) and passed on\nre-run.\n\nThe test asserted that a single `poll()` would fire a timer 1ms out. It does\nnot have to. `effectiveTimeout` bounds the wait at the nearest deadline, and\nan OS wait requested for an interval near the scheduler's tick can return a\nfraction of a tick early; `clockNs()` then still reads below the deadline, so\n`popExpiredTimers` moves nothing and `poll()` returns empty.\n`WindowsEventBackend.wait` ceils its millisecond conversion so a timer never\nfires *early*, but nothing can stop the underlying wait from returning early\n— which is why only the 1ms deadlines here were exposed, and why the 5s waits\nelsewhere in this file never were.\n\nThat is `poll()`'s documented contract, not a bug in it:\n`FiberScheduler.parkOnReactor` treats an empty return as ordinary and\nre-checks after each capped return. The tests were the only callers assuming\none poll suffices, so they now loop the same way.\n\nTwo neighbours had the same defect latent:\n\n- \"the nearer of an fd timeout and a timer deadline bounds the wait\" polls a\n  1ms timer identically and could fail the same way.\n- \"removeTimer cancels a pending timer so it never fires\" fails in the other\n  direction: a poll() cut short before the deadline let it pass without ever\n  proving the cancellation. It now sleeps past the deadline before looking.\n\nRetrying alone would have *weakened* the first two — the loop would quietly\nwait out a badly late timer — so both keep an explicit upper bound on how\npromptly the timer fired (1s: ~60x the coarsest tick behind the flake, and\nthe bound the notify test in this file already uses). Mutation-tested against\nthree breakages: timers that never expire, a wait bound that ignores timers,\nand a no-op removeTimer are each caught.\n\n40 consecutive runs of the reactor suite, clean.\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-27T16:35:49+05:30",
          "tree_id": "d19869db2df242274fa74227591efd661a9fc2b1",
          "url": "https://github.com/kaappi/kaappi/commit/71569effd2b3b3da93737f5f2fc004d46825dae2"
        },
        "date": 1785153038765,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.052286,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.725277,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.925688,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.65764,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006649,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.053297,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.532912,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068733,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.260215,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.975266,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.537761,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.471671,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.706136,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.778072,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044666,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "370d8e85cac4ca3a532b1c634eabec9f33c6f555",
          "message": "Name the library whose own import declaration collides (#1726 follow-up) (#1786)\n\nThe KP2001 import-collision diagnostic cites the file:line of the\ntop-level form that triggered the library load, so when the colliding\nimport declaration lives inside a library's .sld, the reader is pointed\nat the wrong file entirely: kaappi-mpl's sin.sld collision surfaced as\n\"test-mpl.scm:8: identifier 'sqrt' is imported with different bindings\nfrom both (except (scheme base) ...) and (mpl sqrt)\" -- naming\nimport-sets that appear nowhere near test-mpl.scm line 8. During the\n2026-07-27 nightly triage this masqueraded as a core import-resolution\nregression and cost two wrong root-cause theories before the real one\n(fixed in kaappi-mpl#2).\n\nhandleDefineLibrary now records the library name in a save/restored\nvm.loading_library_name while its declarations are processed (nesting\nvia the call stack), and the collision message names it: \"... imported\nwith different bindings inside library (mpl.sin)'s own import\ndeclaration, from both ...\". The name sits early in the message because\nthe 256-byte detail buffer truncates the tail. Top-level import forms\nkeep the original message.\n\nThe regression test also checks the context is restored after a failed\nload, so a subsequent top-level collision is not misattributed to the\nlibrary that failed before it.\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-27T16:56:33+05:30",
          "tree_id": "346a9da9410e1a828259541a41577d5e83b6e851",
          "url": "https://github.com/kaappi/kaappi/commit/370d8e85cac4ca3a532b1c634eabec9f33c6f555"
        },
        "date": 1785153869757,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.299649,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.266447,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.930896,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.643098,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00633,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.055136,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.511519,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.06957,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.665713,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 2.201206,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.577296,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.43111,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.81663,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.63555,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044759,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "053f03d0831eb1d2c41dc19e74dd9bf5a94a364c",
          "message": "Re-unwrap usertext markers mid-match in matchListPattern's loop (#1788)\n\nmatchPattern unwraps its own pattern_in/input_in parameters once, at\nentry, but matchListPattern's internal loop advanced pat/inp on every\niteration without re-unwrapping. A usertext marker pair spliced into a\ndotted-tail position (e.g. a generated macro's pattern `(_ head . p)`\nwhere p's substituted value is a list) is only caught by the entry-level\nunwrap when it sits in the very first position; anything preceding it in\nthe pattern forces the marker to surface mid-loop as a bogus extra list\nelement, shifting every subsequent position and failing the match.\n\nFound while resuming SRFI 148 (eager syntax-rules, #1699), whose\ngenerated macro pattern is always exactly this dotted-tail shape. Fixes\none of two remaining blockers for that SRFI; the other (#1787) is a\nseparate, deeper bug in identifier-comparison against compound values.\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-27T17:59:20+05:30",
          "tree_id": "f4f82e850f3b5572ab9826e3829ecadf6130e8c0",
          "url": "https://github.com/kaappi/kaappi/commit/053f03d0831eb1d2c41dc19e74dd9bf5a94a364c"
        },
        "date": 1785157701733,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 2.641222,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.625905,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.508683,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.682333,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004981,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.033721,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.285418,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.0411,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.585004,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.138538,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 0.998893,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.318675,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.123621,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.82917,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.028901,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "1792c0e6e53144d6acefffbcbf61ea8f32ee3b00",
          "message": "Add a slowdown-investigation runbook; fix the cache's dirty-build-id claim (#1789)\n\nPerformance material was spread across eight documents, organized by tool\nor subsystem rather than by question. Someone holding \"this compiles too\nslowly, where do I start?\" had no entry point: the answer spanned\ntimings.md (which stage), an undocumented profiler step (which caller),\nand testing.md (is it a regression?). That gap has a measured cost —\n#1775 lost two sessions to plausible theories about expander.zig because\n`--timings` reported `expand 2765.8ms` and nothing said what to do next.\n\ndocs/dev/performance.md is a runbook in the same genre as fuzzing.md and\nporting.md: find the stage then the caller, measure before theorizing,\nA/B without fooling yourself, check the growth shape. It deliberately\ncarries no numbers — current figures belong to the benchmark dashboard,\npast results to lessons-learned.md section 11, campaign data to the KEP\ndocuments — so it has nothing to rot. Everything already documented\nelsewhere is linked, not restated.\n\nWhile checking what content would be genuinely new, found cache.md\nasserting the opposite of the truth on the one thing A/B measurement\ndepends on:\n\n    Rebuild after any edit -> dirty tree -> build id changes -> miss.\n\n`-dirty` is a flag, not a hash of the working tree (gitBuildId appends\nthe literal suffix whenever `git status --porcelain` prints anything), so\nthe id changes on the first clean->dirty transition and then never again.\nVerified by building two different uncommitted edits at the same commit:\nboth produced `370d8e85-dirty`, so they share .sbc cache entries and one\ncan execute bytecode the other produced. That is the original #1516\nfootgun surviving in the case contributors hit most, and it reads exactly\nlike nondeterminism in the code under test.\n\ncache.md now documents the case the build id does not cover and the\n`kaappi cache clear` remedy; bytecode_file.zig's two comments that\noverstated the same guarantee are corrected. compilerHashFor itself is\ncorrect and its test asserts nothing false — the aliasing is upstream in\nbuild.zig — so neither is changed.\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-27T18:07:46+05:30",
          "tree_id": "49d3ef0436bbb047c6f49ef25ea5298fc872963e",
          "url": "https://github.com/kaappi/kaappi/commit/1792c0e6e53144d6acefffbcbf61ea8f32ee3b00"
        },
        "date": 1785159466960,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.643284,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.788782,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 1.082157,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.237931,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006279,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.057462,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.583952,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.073966,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.561667,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 2.393289,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.601622,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.431523,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.803349,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.638421,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043442,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "9f68a1e376316bdfdc4ea11d2b28b59de61de275",
          "message": "Unwrap usertext markers in the two remaining pattern-spine walks (#1787) (#1790)\n\nThe preceding commit fixed matchListPattern's loop. Two more spine walks\nhad the same gap, and together they were the whole of what actually\nblocked SRFI 148 -- not the free-identifier=?/compound-identifier bug\n#1787 was filed for, which does not exist (see below).\n\nA pattern variable substituted into a NESTED syntax-rules template is\nwrapped as (__hyg-usertext . value) so the generated macro's own later\nexpansion inserts it verbatim instead of re-walking it as template text.\nWhen the substitution target is a list POSITION the wrapper gets its own\ncons cell and every consumer sees it; when the target is a SPINE position\n-- a dotted tail, or the whole pattern -- the wrapper becomes the cdr of\nan existing cell, so a naive walk reads the marker as one more ordinary\nelement. instantiateTemplate and stripUsertextWalk already handled that\nshape; three matching-side walks did not.\n\n  - expandMacro drops the pattern's first element to skip the macro\n    keyword. For a whole rule pattern spliced from user text -- a\n    generator taking (pat tmpl) and emitting (syntax-rules () (pat tmpl))\n    -- that dropped the marker instead, so every position sat one slot\n    late and the user's own `_` keyword placeholder swallowed the first\n    argument. The keyword-name extraction above it read the marker symbol\n    as the macro's name for the same reason.\n\n  - matchEllipsis splits the input by counting the elements the pattern\n    after the ellipsis needs. Counting a marker made it reserve one too\n    many, so the ellipsis stopped one element short -- and the trailing\n    pattern still matched, because the marker symbol behaves like an\n    anonymous pattern variable and binds the element the ellipsis should\n    have taken. That one failed SILENTLY, expanding with a short ellipsis\n    binding and no diagnostic. Fixed in countPairs (both callers walk a\n    marker-bearing spine) and in the repetition walk.\n\nWith all three, every em-syntax-rules-defined macro in a full SRFI 148\nport now expands correctly end-to-end -- em-cons, em-cons*, em-car/cdr,\nem-fold, em-map, em-filter, em-append, em-quasiquote, both identifier\ncomparisons, and custom-ellipsis variants -- where before the fix each\none failed with \"bad arguments to macro call\".\n\n#1787's own headline bug is not real. Its repro writes a bare `...` in a\nmacro template to pass the ellipsis identifier through to\nfree-identifier=?, but a template `...` IS the ellipsis; R7RS spells that\n(... ...), which is what SRFI 148's own em-syntax-rules writes. Kaappi\nexpands a driver-less ellipsis to zero copies in silence, so\n`(free-identifier=? ... (quote t) 'yes 'no)` quietly became\n`((quote t) 'yes 'no)` -- the \"not a procedure\" the issue reports, and\nnothing to do with identifier comparison. chibi-scheme rejects that same\nrepro at definition time with \"too many ...'s\". With the ellipsis escaped\ncorrectly, free-identifier=? and bound-identifier=? already answered\nevery compound-vs-symbol case right, before and after this commit. The\nsilent zero-expansion is a real diagnostic gap, filed separately.\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-27T21:07:39+05:30",
          "tree_id": "ce013bed71210ff6a21f8f1e3ff5823e4aacd0a9",
          "url": "https://github.com/kaappi/kaappi/commit/9f68a1e376316bdfdc4ea11d2b28b59de61de275"
        },
        "date": 1785169000502,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.889281,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.567803,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.889946,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.259545,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006452,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.050988,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.511368,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.067799,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.646429,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.815326,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.455769,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.405469,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.669011,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.916351,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.041558,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "d04dc522591d8e94e17690febd578f048178e4eb",
          "message": "Iterate head-position macro chains instead of recursing (#1796) (#1797)\n\n* Iterate head-position macro chains instead of recursing (#1796)\n\nAn expansion that is directly another macro use in the same position —\nSRFI 148's CK-machine steps, or a degenerate (loop) → (loop) — used to\ncompile by native recursion, one compileForm → expandAndCompileMacroUse\n→ compileExpr cycle per link, which made MAX_MACRO_EXPANSION_DEPTH an\nimplicit native-stack guard. Raising it to 4096 (what SRFI 148 seemed\nto need) overflowed the stack; the segfault fired inside the Debug test\nallocator's own stack capture while it held the std.debug SelfInfo\nlock, and the segfault handler then deadlocked on that same lock —\nthe unit suite's eternal 0%-CPU \"hang\". The pre-scan hypothesis from\nthe issue was refuted by profiling: collectSetTargets' own caps are\nindependent of this constant.\n\nexpandAndCompileMacroUse now loops over head-position chain links at\nO(1) native stack, bounded by MAX_MACRO_EXPANSION_STEPS (10,000);\nMAX_MACRO_EXPANSION_DEPTH stays 256 and guards only genuinely nested\nexpansions, which are what actually recurses natively. Per-link\nbookkeeping (temp-globals hygiene dance, injected captured-local\naliases, let-syntax peer swaps, lint suppression) accumulates in\nheap-side undo stacks and unwinds LIFO after the final form compiles,\npreserving the exact lifetimes the nested frames provided — an early\nlink's template identifiers can survive into the final form. Chain\nlinks are rooted via extra_roots; the fixed 1024-slot root stack was a\nsecond latent cliff at one pushRoot per nested level.\n\nDeep chains now just work at the shipped constant: em-member and\nem-set-union from the drafted SRFI 148 port run correctly at 256,\nremoving #1699's final blocker without touching the constant. Runaway\nchains still fail with the same deterministic KP2003, via the step\nlimit.\n\nFixes #1796.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n* Address review: flat per-link cost, emit-failure propagation, temp-globals test\n\n- Rebuild the chain's merged macro view only after a link that actually\n  performed a let-syntax peer swap: nothing else can change any macro\n  table between links (no compilation runs inside the loop), and the\n  unconditional per-link rebuild made a runaway chain's failure path\n  O(links x macros in scope) now that links are bounded by the\n  10,000-step budget instead of 256 nesting levels.\n- Propagate failures in the global-alias emit sequence instead of\n  swallowing them: emitOp(.get_global) succeeding and a later emitU16\n  failing left a truncated instruction in the chunk for the VM to\n  decode as garbage. Register exhaustion stays non-fatal (skips the\n  injection), as before.\n- The divergent-chain test now also asserts the temp-globals dance's\n  chain-wide undo: kick's template references a non-procedure global\n  that expansion temporarily marks VOID (#1208), and the failed compile\n  must restore its value.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-27T21:06:58Z",
          "tree_id": "a804da82f3586fbe6324008264aecdebaf18be66",
          "url": "https://github.com/kaappi/kaappi/commit/d04dc522591d8e94e17690febd578f048178e4eb"
        },
        "date": 1785188877188,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.308292,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.089748,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.925309,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.452204,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006671,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.052892,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.512063,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068454,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.38422,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 2.076868,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.531838,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.473256,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.8625,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.760718,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.046137,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "99dc2320e7707bf5a4f09b0dd7bebb5b68ceeeec",
          "message": "Stop the native backend evaluating `apply` in the global environment (#1798)\n\n* Stop the native backend evaluating `apply` in the global environment\n\n`kaappi compile` miscompiled `apply` over any local binding — a procedure\nparameter or a `let`-bound name. The binary linked cleanly and then died at\nrun time:\n\n    (define (s xs) (apply + xs))   ; => undefined variable 'xs'\n\n`call/cc`, `call-with-current-continuation`, `call-with-values` and `eval`\ntook the same broken path.\n\nWhy: `apply` lowers to an ir `.passthrough` node, and `emitPassthrough`\nserializes those to source for `kaappi_eval_cached` — an interpreter eval that\nresolves names in the GLOBAL environment. All four native-compilation gates\n(both closure tiers, tryCompileDefineFunction, emitLet) exist to stop a lexical\nscope being split that way (#827); each asks\n`freevars.sexprNeedsEvalFallback`, which matches head keywords against the\ncomptime-derived `ir.eval_fallback_form_names`.\n\n`apply` was missing from that set. The set derives from `llvm_node_table`,\nwhere `.passthrough` carries `.capability = .native` — right for the one shape\nemitPassthrough compiles (a `(define (f ...) ...)` shorthand), wrong for every\nother, which it evals whole. And because `apply` is an `ir.isKnownGlobal`,\nfree-variable analysis passed it too, so the frame compiled natively and the\neval went looking for `xs` among the globals. A same-named global made it worse\nthan an error: `(define x 100) (define (s x) (apply + (list x)))` silently\nreturned 100.\n\n`isRejectedFormHead` (the #1496 cond/case/do gate) is a second copy of the same\nconcept and was already complete, which is why `(cond ... (else (apply + lst)))`\nworked while a plain body did not.\n\n`ir.other_special_forms` now carries a bool payload — \"an evaluated form headed\nby this keyword becomes a passthrough the interpreter runs\" — and\n`eval_fallback_form_names` appends the true entries, so one list feeds both\nviews. `else`, `=>`, `_`, `...` and `unquote` stay false on purpose:\nsexprNeedsEvalFallback recurses blindly into sub-forms, so listing `else` would\nreject every natively lowered cond/case with an else clause. `isSpecialForm`\nignores the payload, leaving vm_library.zig and compiler_macro.zig unchanged.\n\nRepublishing the frame as globals (bindParamsAsGlobals, the #1410 mechanism the\nletrec/let fallbacks use) is not an alternative: it cannot see let-locals,\naliases across activations, and clobbers same-named globals. Declining the frame\nkeeps the interpreter's lexical scope authoritative.\n\nThe cost is that a function using `apply` is no longer natively compiled at all.\nDeliberate, documented in docs/dev/llvm-backend.md, and closable later by\nlowering `apply` natively.\n\nTests: a compile-suite script running ten shapes — parameter, let-bound name,\nbare top-level let, computed operator, fixed-args-plus-list, rest parameter,\nrecursion, closure capture, global-not-clobbered, and a summary-statistics\nprogram — each comparing the compiled binary against the interpreter, so it\nstays valid if `apply` is later lowered natively. Plus six emit-level tests\nincluding a direct assertion on the derived name set and its exclusions.\nMutation-tested: 9/10 shell cases and all 6 unit tests fail without the fix.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Reference issue #1799 in the apply lexical-scope fix\n\nThe regression test, its emit-level counterparts, and the surrounding comments\ncarried no issue number: none was filed when the fix landed. Stamp #1799 in and\nrename the compile-suite script to match the repo's convention of naming a\nregression test after the bug it pins.\n\nNo behavior change.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Address review: fail on a nonzero compile, drop future work from the guide\n\nThree findings from CodeRabbit on #1798, all in the new material:\n\n- The regression script ran `kaappi compile` under `|| true` and then judged\n  success by whether an executable existed. A compile that reported an error\n  but still left an executable behind would have passed as a green run, and a\n  genuine compiler rejection was reported as \"did not produce a binary\" with\n  its diagnostics discarded. Capture the status and the output, and fail on\n  either a nonzero exit or a missing binary, with the two spelled differently.\n\n- docs/dev/llvm-backend.md described how a future native `apply` lowering would\n  work. docs/dev/CLAUDE.md says roadmap and future work belong in issues, not\n  guides, because such sections rot. Cut it back to the limitation that exists\n  today; the design sketch lives in the PR discussion.\n\n- A line beginning `#1410` reads as an ATX heading (markdownlint MD018).\n  Reflowed, and spelled `kaappi#1410` to match the rest of the file.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-28T06:35:50+05:30",
          "tree_id": "483d1ceccb31184c5662b7f86542618565d69f7f",
          "url": "https://github.com/kaappi/kaappi/commit/99dc2320e7707bf5a4f09b0dd7bebb5b68ceeeec"
        },
        "date": 1785203048845,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.141848,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.54666,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.720374,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.410146,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.005231,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.040702,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.394673,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.053347,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.581524,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.517367,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.197731,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.37123,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.354078,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.500626,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.035783,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "ea71d9a5d04053bd2df83be7fd25b5fd8d5f1303",
          "message": "Stop ReleaseSafe memsetting the expander's 1MB buffers on every expansion (#1802) (#1804)\n\n* Stop ReleaseSafe memsetting the expander's 1MB buffers on every expansion (#1802)\n\nCompiling SRFI 148's 134-definition library took 80 seconds before a\nsingle combinator ran. A sample profile put 96% of it in _memset: Zig\n0.16's ReleaseSafe fills every plain `= undefined` local with 0xAA, and\nthe expander declares three ~1MB [MAX_BINDINGS]Binding scratch buffers\nper call (expandMacro, matchEllipsis, instantiateEllipsis). The\n`b: { @setRuntimeSafety(false); break :b undefined; }` initializer those\nsites used to suppress the fill now does the opposite: it materializes a\nruntime undefined value whose store into the local gets the fill anyway.\nThe only shape that works is @setRuntimeSafety(false) at the scope of\nthe declaration, so each function now declares its buffers under a\nsafety-off function scope and runs its entire body in a\n@setRuntimeSafety(true) block, keeping index/overflow checks intact.\n\nThe remaining cost was the set! pre-scan (#1775) treating transformer\nspecs as runtime code: `(define-syntax em-cadr (em-syntax-rules ...))`\nspeculatively ran the whole CK machine per definition, burning the full\n4096-expansion budget - and with it the truncation fallback that boxes\nevery local - on forms that produce no runtime code at all. A spec only\never resolves to a transformer object, so collectSetTargets now walks\ndefine-syntax/let-syntax/letrec-syntax spec positions without expanding\nmacros (still catching literal set!s in templates); let-syntax bodies\nkeep the budgeted scan. A set! that only materializes when the spec's\nown macros run is caught at the macro's real use site - the same\ncorrect-late Part B path every divergent best-effort expansion already\ntakes.\n\nImport of the drafted (srfi 148): 86.6s -> 0.07s; its full upstream\nreference suite now runs in 0.85s (134 expected passes, 8 known\nxfails), far under run-all.sh's 60s per-file timeout that blocked it.\nBoth prescan regression tests fail without the collectSetTargets change\n(verified by mutation); the buffer-fill half is pinned by disassembly\n(no 0xAA memset in the three functions) and documented in\ndocs/dev/performance.md's new \"profile bottoms out in memset\" entry.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n* Walk let-syntax specs per binding so special-form names can't derail the scan\n\nCodeRabbit review follow-up on #1804: collectSetTargets' let-syntax\nbranch walked the whole bindings list, so a binding pair whose NAME is a\nspecial-form identifier was misread as a form - a binding literally\nnamed `quote` early-returned before its own transformer spec was\nscanned. Iterate the binding pairs and walk only each spec.\n\nVerified end-to-end before committing: the review's predicted\nmiscompilation does not actually reproduce today - its proposed\ntemplate `(set! a b)` holds only pattern variables (nothing literal to\nfind), and with a literal `(set! + -)` template the sibling\n`(+ 5 2)` still isn't folded because a let-syntax body compiles through\nthe passthrough path, while a late-discovered set! target is still\nboxed correctly via the box_local transition. So this is scan hygiene,\nnot a user-visible fix. The new hygiene suite file pins the late-boxing\nself-heal this relies on (it hangs, not fails, if that regresses) plus\nthe quote-named-macro rebinding shape.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-28T10:11:45+05:30",
          "tree_id": "46f30bc26e89b778ba25e1564e4c21b81ce39d5e",
          "url": "https://github.com/kaappi/kaappi/commit/ea71d9a5d04053bd2df83be7fd25b5fd8d5f1303"
        },
        "date": 1785216074884,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.343984,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.460086,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.935018,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.496567,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006335,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.054797,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.521714,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.071824,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.666616,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 2.018021,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.619229,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.431582,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.814259,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.661657,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044358,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "82da81378c730bfd21d68861d6174d3b7ad27c07",
          "message": "Lower apply natively in the LLVM backend (#1803) (#1805)\n\nOne apply anywhere in a body used to send the whole enclosing function to\nthe interpreter (the #1799 fix was correct but all-or-nothing): ~19x on\nthe issue's arithmetic-loop reproducer, hit precisely by idiomatic code\nlike (apply + xs). Only apply itself needs the runtime — the enclosing\nframe can keep its native compilation.\n\nA new C-ABI entry point, kaappi_apply, is primitives.applyFn minus the\nargument shuffling: same procedure validation, same tortoise-and-hare\nproper-list check (a circular list raises instead of hanging), same\ntypeError texts, then callWithArgs on the spliced arguments.\nemitPassthrough routes an (apply …) head inside a lexical scope to\nemitApplyForm, which mirrors the interpreter's dispatch case for case:\ntail + unshadowed + ≥2 operands is structural builtin apply (the\ntail_apply opcode ignores a top-level rebinding of apply, so the fast\npath deliberately does too — an earlier draft that honored the rebinding\neverywhere diverged from the interpreter); tail with too few operands\nabandons native compilation so the interpreter raises its compile-time\nInvalidSyntax; every other resolvable shape is an ordinary indirect call\nthrough whatever apply denotes in scope. Tail sites balance the frame's\nGC roots before the ret, as emitCallNode does.\n\nFlipping apply out of eval_fallback_form_names exposed a latent trap:\nthe free-variable analyses treated every .passthrough node as\ncapture-free, sound only while all passthrough keywords also declined\nthe enclosing scope. Both walks now descend into apply operands, so a\nclosure capturing a variable used inside one gets its upvalue instead\nof a silent global lookup — #1799's failure mode in a new spot.\n\nThe #1799 parity suite passes unchanged, as designed. The new 1803 suite\nadds rebinding/shadowing/error/GC-stress shapes plus the structural\nconvergence check (zero eval fallbacks in the reproducer's IR); the\nissue's heavy pair now times identically (0.12s vs 0.12s, was ~19x).\nThe 1376 callback test's case 8 gets a transparent (letrec ()) wrapper:\napply no longer forces the eval fallback it relied on to exercise\nbytecode tail_apply against a NativeClosure (do stopped forcing it back\nin #1496), so the wrapper restores the documented coverage.\n\nCloses #1803\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-28T10:25:56+05:30",
          "tree_id": "b9c6be37e0c710d8e6a4b000ca9f22c23d9b5322",
          "url": "https://github.com/kaappi/kaappi/commit/82da81378c730bfd21d68861d6174d3b7ad27c07"
        },
        "date": 1785217240742,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.620529,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.602131,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.949782,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.665131,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006392,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.055096,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.547801,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.071313,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.489774,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 2.067353,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.607374,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.436683,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.806248,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.632656,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044128,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "ff6cffd5f9fb375a04e2db435657c7d90b6051a0",
          "message": "Add SRFI 148 (eager syntax-rules), completing issue #1699's portable set (#1806)\n\nlib/srfi/148.sld is a pure portable port of the reference implementation\n(Marc Nieper-Wisskirchen, 2016, MIT): the CK-machine core, the portable\nidentifier-comparison helpers, and ~110 em- combinators combined into one\n134-definition library body. em-syntax-rules and several combinators\nresolve through SRFI 147's begin-wrapped define-syntax mechanism - this\nSRFI is why 147 was implemented. No engine changes ship here; the six\nengine bugs 148 surfaced were fixed separately (#1776/#1779 template\nunwrap gaps, #1787/#1790 usertext-marker spine gaps, #1796/#1797 the\nhead-position chain depth wall, #1802/#1804 the compile-cost cliff that\nmade the bare import cost 87 seconds - it now costs ~0.07s).\n\nThe port fixes 4 real, confirmed bugs in the reference implementation\nitself, none covered by its own test suite (em-append-map's stray `map`\ntoken; em-set-intersection and em-set-difference dropping 'compare in\ntheir 3+-list recursions; em-set= vacuously #t for 3+ arguments) - all\ndocumented with evidence in the library header, alongside the\n:call/:prepare workaround for Kaappi's zero-clause syntax-rules\nrestriction.\n\ntests/scheme/srfi/srfi148.scm is the reference's own test.sld ported\nverbatim (134 expected passes, 0.9s), with 8 test-expect-fail entries\nciting the two remaining general engine bugs #1800 and #1801. The\nfeatures/cond-expand surface needs no listing anywhere: the build-time\nlib/srfi scan and the derived srfi-<n> probe pick the new file up on\nrebuild (verified: `kaappi features` reports portable (160) including\n148, and (cond-expand (srfi-148 ...)) selects it).\n\nRefs #1699 (72, 211, 213 remain tracked there).\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-28T11:05:43+05:30",
          "tree_id": "00c6c043f04ee729ea98c5eb6ed2bea84345141c",
          "url": "https://github.com/kaappi/kaappi/commit/ff6cffd5f9fb375a04e2db435657c7d90b6051a0"
        },
        "date": 1785219482633,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.520862,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.531307,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.933436,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.574719,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006415,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.053633,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.508907,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.07046,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.536592,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.960708,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.605763,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.440773,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.830052,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.680032,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044315,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "1fdb18b46d253cfa4e6bfbad5fb5f0fff13b4202",
          "message": "Add SRFI 211 and 213 on a procedural-macro mechanism, resolving issue #1699 (#1811)\n\n* Add SRFI 211 and 213 on a procedural-macro mechanism, resolving issue #1699\n\nIssue #1699's remaining trio (72, 211, 213) all needed one engine\ncapability the portable slices couldn't provide: macro transformers that\nare Scheme procedures run at expansion time. This adds that mechanism and\nuses it to ship SRFI 211 (as the three sub-libraries this engine can\nprovide whole: explicit-renaming, define-macro, syntax-parameter — the\nSRFI explicitly permits a subset of libraries, each complete) and SRFI 213\n(define-property with the capture-lookup re-entry protocol; capture-lookup\nis the identity, which the spec explicitly sanctions).\n\nSRFI 72 is excluded rather than implemented: the issue table's \"explicit\nrenaming macros\" note was a mislabel — 72 is van Tonder's *replacement*\nmacro system (arbitrary transformer expressions evaluated over a\nsyntax-object type with its own hygiene rule and phase tower), which would\nchange the semantics of every existing define-syntax and conflicts with\nthe structural transformer-spec direction SRFI 147 already established\nhere. The ER facility the issue actually wanted is exactly\n(srfi 211 explicit-renaming). SRFI 150 moves the other way: its exclusion\nrationale (needs SRFI 147+148) went stale when both shipped, so it is now\ntracked in #1810 instead — the excluded count stays 30, implemented goes\n175 -> 177.\n\nMechanism notes (details in CLAUDE.md's new paragraph and the .sld\nheaders): Transformer gains a kind tag + GC-traced proc; transformer-spec\nrecognition is structural with the argument evaluated at definition time\nin the global environment (phase separation); ER rename reuses\nrenameForHygiene under a fresh per-invocation scope, giving procedural\nmacros exactly the hygiene strength syntax-rules templates have (verified\nequivalent, including the shared use-site-redefinition limitation); and\nvm_library's import-time free-reference copying gains a whole-def-env mode\nfor procedural transformers, whose references are computed by running code\n— without it, (rename 'lib-helper) resolved at the definition site but\ndied \"undefined variable\" at the use site.\n\nCONFORMANCE.md's portable table was also reconciled while adding the new\nrows: it had silently drifted six SRFIs behind lib/srfi/ (139, 147, 148,\n149, 231 were missing — four of them this same issue's earlier slices).\n\nCloses #1699.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n* Record the procedural-transformer path in the understanding map\n\nThe expander-hygiene core-tier entry's theory now includes the SRFI\n211/213 mechanism PR #1811 adds — it is new mandatory model for anyone\njudging macro bugs there.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-28T13:52:57+05:30",
          "tree_id": "3b9023cda62ff2bb56cad1c1e75c4e4f3240e72f",
          "url": "https://github.com/kaappi/kaappi/commit/1fdb18b46d253cfa4e6bfbad5fb5f0fff13b4202"
        },
        "date": 1785229482993,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.384986,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.68495,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.922153,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.552233,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006357,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.053839,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.519883,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068995,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.595461,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 2.005348,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.617643,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.435055,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.832394,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.636874,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.04296,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "4e03b6100c3a0bb0b9a9f119e6fc57c4a94299bd",
          "message": "Keep a macro-expanded body-position define's local alive (#1800) (#1815)\n\nA macro use whose expansion is a bare (define x v) in body position\nraised \"undefined variable\" for later references to x. Root cause:\nexpandAndCompileMacroUse's post-expansion cleanup unconditionally\npopped every compiler local added while compiling the macro's final\nexpanded form, on the assumption that everything added during a\nmacro-use compile is transient chain bookkeeping (hygienic aliases).\ncompileDefine's in_body_scope branch adds a real, sibling-visible\nlocal when the expansion is a definition, and that local needs to\nsurvive the call returning; only the aliases injected earlier in the\nchain (for R7RS 4.3.1 referential transparency) are truly transient.\n\nFixes 6 SRFI 148 assertions previously quarantined behind\ntest-expect-fail and one SRFI 251 \"known gap\" test that turned out to\nbe the same underlying bug reached via a nested lambda scope.\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-28T14:52:18+05:30",
          "tree_id": "12b6abd2a056d8136f593b49fa5543d851eb45d0",
          "url": "https://github.com/kaappi/kaappi/commit/4e03b6100c3a0bb0b9a9f119e6fc57c4a94299bd"
        },
        "date": 1785232879334,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.357095,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.318527,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.898703,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.431105,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006332,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.053826,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.505236,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069682,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.562518,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.924202,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.612222,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.434651,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.822359,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.66723,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044568,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "8ada9e7f3ccc4edf5005d9cc894d50fb7478ed9c",
          "message": "Reclaim per-iteration alloca stack growth in native loops (#1808) (#1813)\n\nLLVM's alloca frees its stack space only at function return, never at\n\"next loop iteration\" — but the native backend compiles self-tail-call\nloops and do-loops as backward branches within a single function, and\nseveral paths (emitRootPush's shadow-stack slots, the generic n-ary\ncall path's argument-array alloca, let/do-bound variable slots) emit\nalloca instructions inside that repeatable loop body. Every pass adds\nmore stack that's never reclaimed, so a long-running loop eventually\noverflows the OS thread stack — independent of whether bignums are\ninvolved, despite the issue's reproducer happening to cross into\nbignum range partway through (confirmed by reproducing the identical\ncrash with a pure-fixnum loop and with a plain do-loop).\n\nBracket each native loop's body with llvm.stacksave/llvm.stackrestore:\ncaptured once at the loop header, restored right before the back-edge,\nreclaiming that pass's allocas without needing to rewrite every\nindividual alloca-emitting call site.\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-28T14:51:58+05:30",
          "tree_id": "b10447aa537f95a8ac9ce0892780e742c52c5889",
          "url": "https://github.com/kaappi/kaappi/commit/8ada9e7f3ccc4edf5005d9cc894d50fb7478ed9c"
        },
        "date": 1785233091608,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.980724,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.821688,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.913838,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.402091,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006651,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.052532,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.506253,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.06837,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.397947,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.945088,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.518912,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.474984,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.707082,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.776107,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044327,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "adbb59a1f6656900e9f349d19a0f1ff5b82ef6a4",
          "message": "Skip GC/VM teardown while a thread-start!ed child is still alive (#1792) (#1814)\n\nmain.zig unconditionally freed the parent's shared symbol table and\nglobals map at exit, racing a still-running (or still-finishing) child\nthread that aliases them through its own GC/VM. This corrupted the heap\nallocator's metadata (observed as glibc's \"corrupted size vs. prev_size\"\n+ SIGABRT). thread-join! is optional in SRFI-18, so this was reachable\nfrom ordinary code that fires off a background thread.\n\nlive_child_threads already tracked exactly what was needed — its\ndecrement is the outermost defer in threadEntryFn, so it only reaches\nzero once a child is done touching shared parent state. Expose it as\nprimitives_srfi18.hasLiveChildThreads() and skip vm.deinit()/gc.deinit()\nentirely while it's true, leaking harmlessly instead of racing (the\nprocess is exiting anyway).\n\nReproduced the exact reported corruption on native aarch64 Linux/glibc\n(19/30 and 3/30 aborts across the two shapes) and confirmed 0/200\nfailures with the fix, on the same box. Added a regression test looping\nboth shapes 50x each.\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-28T11:27:19Z",
          "tree_id": "d5be1b299240ae45b67fa2aaa045a1cc9e2522cb",
          "url": "https://github.com/kaappi/kaappi/commit/adbb59a1f6656900e9f349d19a0f1ff5b82ef6a4"
        },
        "date": 1785240444891,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.004386,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.104548,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.934469,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.42704,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006633,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.052332,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.50862,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068228,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.367804,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.950065,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.522004,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.476932,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.722647,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.80271,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045284,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "180d1e26a5ebfa4a526487f2ec9eb1c1fe87a438",
          "message": "Stamp cache_version in call_global/tail_call_global so the global cache can hit (#1817)\n\n`call_global` and `tail_call_global` populated a Function's global inline\ncache but never assigned `cache_version`, leaving it at its `types.zig`\ndefault of 0. `global_version` is bumped past 0 before any user code runs --\nby `vm_bootstrap.install` and by every library import (`vm_library.zig`) --\nso the fast-path guard `func.cache_version == self.global_version` was false\nforever. Every call to a global therefore fell through to a full hash-map\nlookup, and the cache could never hit even once.\n\n`get_global` already self-healed (memset the cache, then re-stamp) at\nvm_dispatch.zig:220; the two call opcodes were missed. Apply the same\npattern: heal a stale cache before refilling a slot, and stamp when the\ncache is first allocated. The memset-before-stamp preserves #812's rule\nthat a version bump must not re-bless entries cached before the rebinding.\n\nMeasured on x86_64 Linux, a 20M-iteration call-dense loop, external wall\nclock: 2.45s -> 1.72s (1.42x). Instrumented cache counters over the same\nloop went from 0 hits / 40,000,000 misses to 40,000,000 hits / 1 miss.\n\nChild SRFI-18 threads masked this: `VM.initForThread` leaves the child's\n`global_version` at 0, which accidentally matches the un-stamped default,\nso child threads hit the cache while the main thread never did. That\ndiscrepancy -- a child OS thread running identical bytecode ~1.5x faster\nthan the main thread -- is how the bug surfaced, during a parallelism audit.\n\nRegression tests assert the stamp directly rather than timing anything, and\ncover the heal path against #812's stale-callee rule.\n\n\nClaude-Session: https://claude.ai/code/session_01UooWXnqjfoy7HmCoY8kovD\n\nCo-authored-by: Claude <noreply@anthropic.com>",
          "timestamp": "2026-07-28T18:59:02+05:30",
          "tree_id": "78775dfe3aa7c84a4de3ac1f0c4ed4ffc14bdb94",
          "url": "https://github.com/kaappi/kaappi/commit/180d1e26a5ebfa4a526487f2ec9eb1c1fe87a438"
        },
        "date": 1785247247810,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.338903,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.174796,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.597738,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.108078,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006308,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046338,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.319121,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057661,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.555689,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.231911,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.676587,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.439386,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.787239,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.695773,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045505,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "15f40ed07e674a2dc692334f629b3839b9e10e25",
          "message": "Hygiene-rename identifiers inside quote, fixing SRFI 148's em-gensym (#1801) (#1816)\n\n* Hygiene-rename identifiers inside quote, fixing SRFI 148's em-gensym (#1801)\n\nrenameForHygiene stripped hygiene from a template-introduced identifier the\ninstant it saw QUOTE_FLAG, before any per-expansion distinguishing info\ncould be recorded -- so two separate expansions of e.g. `'g` were\nstructurally identical as syntax, not just as data. This broke any\nbound-identifier=?/free-identifier=?-style macro trick built out of further\nexpansion, including SRFI 148's em-gensym, which relies on hygiene alone\n(no counter) for uniqueness per its own `(em-gensym) => 'g` definition.\n\nFixed by hygiene-renaming a quoted, template-introduced identifier exactly\nlike a non-quoted one, then stripping that rename back off wherever the\ncompiler turns a quoted datum into a literal Value\n(expander.stripHygieneFromDatum, called from quote and quasiquote\ncompilation) -- so ordinary macros that quote a fixed tag symbol still\nproduce eq? results once the code runs.\n\nA pre-existing, unrelated reuse of QUOTE_FLAG (re-walking a usertext-marker\nsplice from a macro-generating-macro in substitute-only mode, e.g. SRFI\n257's accumulator rebinds) needed a new VERBATIM_FLAG to keep its\nnever-rename behavior, since it used to be indistinguishable from the\nem-gensym case now that QUOTE_FLAG itself renames.\n\nlowerQuote needs a GC to strip hygiene; threading it through the LLVM\nnative backend's standalone IR lowering surfaced that memory.gc_instance\nis unsafe there (tests_native.zig builds its own short-lived GC without\npointing the threadlocal at it), so IR/LLVMEmitter gained an explicit gc\nfield instead.\n\nRemoves the now-stale em-gensym/em-generate-temporaries test-expect-fail\nentries in tests/scheme/srfi/srfi148.scm and adds regression coverage in\ntests_macros.zig, tests_pipeline.zig, and\ntests/scheme/hygiene/quote-identifier-1801.scm.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* Fix SRFI 211 test that accidentally depended on the #1801 quote-hygiene bug\n\ntests/scheme/srfi/srfi211.scm's \"two invocations rename to distinct\ngensyms\" test built `(list (rename 'quote) (rename 'fresh-name-uvw))` and\ncompared two invocations with eq?. Before #1801's fix, quote never\nstripped hygiene renames at all, so this happened to observe two distinct\n__hyg_N_ symbols and pass -- but for the wrong reason. With #1801 fixed,\nquote correctly strips the rename back to the plain `fresh-name-uvw`\nsymbol both times (matching real quote semantics: quote always yields the\nplain datum), so the two invocations are now eq? as intended, and the\nold assertion fails.\n\nFixed the test itself rather than the engine: convert with symbol->string\nbefore returning from the transformer, since stripHygieneFromDatum only\never touches symbols. This still correctly verifies that `rename` produces\na genuinely fresh identifier per invocation, without depending on quote\npreserving that difference into a runtime symbol value -- which no real\nScheme's quote does.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-28T13:47:44Z",
          "tree_id": "44fb3954e054affd64148d60dde4543ea6eaad19",
          "url": "https://github.com/kaappi/kaappi/commit/15f40ed07e674a2dc692334f629b3839b9e10e25"
        },
        "date": 1785249096124,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.09171,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.631459,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.568834,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.923238,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006631,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.044682,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.297676,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.05584,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.339485,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.16363,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.522106,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.477189,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.711516,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.825922,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045028,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "218429300be8c949d615a43f067abccb535dda63",
          "message": "Gate native let/lambda lowering on macro use, fixing miscompiled expansion (#1807) (#1819)\n\nemitLet and the lambda closure tiers (tryCompileNativeClosure,\ntryCompilePureLambdaAsNativeClosure, tryCompileDefineFunction) re-lower\ntheir raw bindings/body via a scratch IR instance with no macro table,\nso a macro use anywhere inside compiled as a call to a same-named\nglobal instead of expanding. A let body's macro use was unconditionally\nbroken; a lambda/function body's macro use was usually saved by\naccident (free-variable analysis rejects an unrecognized name) unless\nthe macro shadowed an existing global (e.g. `(define-syntax car ...)`),\nin which case it silently called the real primitive.\n\nAdds sexprHasMacroUse, mirroring sexprNeedsEvalFallback's raw-sexpr\ntraversal but checking self.isMacroName (the same gate #1496 added for\ncond/case/do), and wires it into all four gates so any macro use\nanywhere in the scope declines native compilation of the whole\nenclosing form rather than splitting it across the native/interpreted\nboundary. #1803's apply-operand emission inherits the same protection\nwith no separate fix, since it only runs after a gate has already\naccepted the enclosing scope.\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-28T22:06:58+05:30",
          "tree_id": "50b22991844675db65436279200a5c703abcdf7a",
          "url": "https://github.com/kaappi/kaappi/commit/218429300be8c949d615a43f067abccb535dda63"
        },
        "date": 1785258706108,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.973363,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.347983,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.566838,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.846169,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00669,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.04508,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.299733,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.055987,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.353912,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.160461,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.524225,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.477227,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.709742,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.749391,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044175,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "8c1b1431649a2913c819a514ab9e8d80892d5824",
          "message": "Surface the real cause behind cross-thread channel/thread failures (#1742) (#1820)\n\nThe cross-thread channel mechanism itself is correct: a channel only\ncrosses a thread boundary when lexically captured by the thread's thunk,\nand a top-level define (a shared, pointer-shared global) is rightly\nrejected rather than promoted. Two diagnostics bugs made that hard to\nsee, both traced in #1742's own investigation comment:\n\n1. thread-join! wraps a child's failure in a generic \"uncaught exception\n   in thread\" ErrorObject and stashes the real cause in its\n   uncaught_reason field -- a field the default top-level report never\n   looked at, so the one sentence that explains everything (e.g. \"channel\n   belongs to another thread; pass it through the thread thunk to share\n   it\") was reachable only via `(error-object-message\n   (uncaught-exception-reason e))` inside a guard.\n   VM.noteUncaughtException now unwraps uncaught_reason (bounded, for\n   nested thread-join! chains), gated strictly on error_type ==\n   .uncaught_exception so it never fires for the unrelated io_decoding/\n   io_encoding error types that reuse the same field slot.\n\n2. channel-receive/channel-send's deadlock message for a channel that was\n   never shared with another thread read \"...and all fibers are blocked\"\n   even when another OS thread was alive and well, implying fiber\n   scheduling was the whole story. The four local (unpromoted-channel)\n   deadlock sites now name that thread explicitly via a new\n   localChannelDeadlockMsg helper, reusing the existing\n   crossThreadWaitPossible() predicate the sibling shared-channel path\n   already relies on for the same distinction. Pure wording change: a\n   local channel's deadlock decision was already immediate regardless of\n   crossThreadWaitPossible(), traced through fiber.zig's parkOnReactor/\n   runSchedulerStep.\n\nRegression coverage: unit tests in tests_shared_channel.zig and\ntests_fibers.zig, plus end-to-end shell assertions in error-format.sh\ncovering the issue's exact repro.\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-28T22:41:42+05:30",
          "tree_id": "019b05148a0c1fbc4a623d2bd3e110e0fe54bae6",
          "url": "https://github.com/kaappi/kaappi/commit/8c1b1431649a2913c819a514ab9e8d80892d5824"
        },
        "date": 1785261916986,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.070491,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.768923,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.461313,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.220488,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00536,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.034756,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.231135,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.043184,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.614463,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.889634,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.186344,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.376403,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.323158,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.376923,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.035513,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "a4fd71032b33cd7be4dfb7cf71c08e2941683055",
          "message": "Make nstore prefixes byte-prefix-free, fixing tuple leaks across stores (#1717) (#1818)\n\n* Make nstore prefixes byte-prefix-free, fixing tuple leaks across stores (#1717)\n\nSRFI 168's %all-tuples prefix-scanned the packed key bytes directly, and\nengine-pack concatenates items with no \"prefix ends here\" marker. Two\nnstores sharing an engine/store whose prefixes were initial subsequences\nof each other (e.g. (list 0) vs (list 0 0)) would have the shorter\nprefix's scan also match the longer prefix's tuples.\n\nEvery nstore's packed prefix is now wrapped in a length header (the\npacked prefix's own byte length, itself packed via engine-pack) before\nuse as a key prefix or scan key. engine-pack's integer encoding is\nprefix-free across distinct non-negative integers, so this guarantees\none nstore's tag can never be a byte-prefix of a different nstore's tag.\nConfined to 168.sld; 167.sld's engine-pack/unpack are unchanged.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* Qualify the CHANGELOG isolation claim for identical nstore prefixes\n\nPer CodeRabbit review on #1818: the prior wording (\"regardless of how\ntheir logical prefixes relate\") overclaimed — two nstores given the\nexact same logical prefix are still indistinguishable by design, as the\n168.sld header comment already notes. Narrow the claim to distinct\nprefixes and state that limitation explicitly.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-28T23:14:11+05:30",
          "tree_id": "059e5969e6e89571734523987eb7576262c426ea",
          "url": "https://github.com/kaappi/kaappi/commit/a4fd71032b33cd7be4dfb7cf71c08e2941683055"
        },
        "date": 1785263915861,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.364288,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.056709,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.592597,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.18654,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006371,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.047801,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.325845,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.058991,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.570497,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.239449,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.579008,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.43841,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.81338,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.670125,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044184,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "4f84c3a36a2b43c60dc17900c4883e9c9c7392dc",
          "message": "Route case-lambda's arity dispatch through an internal %length alias (#1821)\n\ncase-lambda's compiled dispatch code called the global `length` by name\nto count arguments, so a scope that legitimately shadows `length` (e.g.\na library providing its own for a non-standard list-like type, as SRFI\n101 needs) broke every case-lambda defined within it. Adds a %length\nprimitive using the same %-prefixed internal-primitive convention as\n%record-set! etc., immune to ordinary user shadowing, and dispatches\nthrough it instead.\n\nFixes #1714",
          "timestamp": "2026-07-29T00:23:23+05:30",
          "tree_id": "3959f81cf28a68c9836d1602cfecc92d962eeba7",
          "url": "https://github.com/kaappi/kaappi/commit/4f84c3a36a2b43c60dc17900c4883e9c9c7392dc"
        },
        "date": 1785269177307,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.355042,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.911722,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.583961,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.175343,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006311,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.047116,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.320254,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.058278,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.50702,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.24154,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.595291,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.431643,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.804936,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.604545,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042693,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "67b32bd109dc9d6aeca4a4ba9b58d8c486649d79",
          "message": "Raise an error for a syntax-rules ellipsis with no driving pattern variable (#1822)\n\nA template subform followed by `...` whose element contains no pattern\nvariable bound under an ellipsis in the pattern previously expanded\nsilently to zero copies instead of erroring (R7RS 4.3.2). The common\ntrigger is a typo'd bare `...` where the literal-ellipsis escape\n`(... ...)` was meant -- exactly what happened in #1787, where the\nresulting malformed expansion failed far away with a misleading \"not a\nprocedure\" error instead of pointing at the real problem.\n\ninstantiateEllipsis now raises EllipsisNoPatternVariable instead of\nsilently falling through with repeat_count 0. This is safe against the\nlegitimate \"ellipsis belongs to a nested syntax-rules template's own\ngrammar\" case (the SRFI 147/148 macro-generating-macro pattern): both\ncall sites already gate on `NESTED_SR_FLAG and !ellipsisReferencesOuter`\nbefore calling here, and ellipsisReferencesOuter is exactly the same\npredicate, over the same elem_template/bindings, as the count_set\ncomputation -- so reaching `!count_set` here is only possible when that\ncarve-out does not apply.\n\nThis also closes an adjacent gap lib/srfi/149.sld had documented and\ndeliberately deferred: a single pattern variable asked for more ellipsis\nnesting in the template than its own matched depth, with no sibling\nvariable to drive the extra level, hits the same code path one recursion\nlevel down.\n\nVerified against the full test suite (all SRFI test files, R7RS suite,\nhygiene tests): 2007 pass, 0 fail -- no library anywhere in the ecosystem\ndepended on the old silent-swallow behavior.\n\nFixes #1791\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-29T00:53:22+05:30",
          "tree_id": "d86f8009bf9e093d3986a1bba748b3039f0d7cc5",
          "url": "https://github.com/kaappi/kaappi/commit/67b32bd109dc9d6aeca4a4ba9b58d8c486649d79"
        },
        "date": 1785269208827,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.378576,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.287525,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.609055,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.190545,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006533,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.047063,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.32476,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.05891,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.542245,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.237148,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.599384,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.438228,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.811546,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.737392,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044536,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "34774bf4d0fcc48e24962a275b66bd16ba1fadc1",
          "message": "Reserve begin-internal define-syntax names during lowering, fixing #1772 (#1823)\n\nA literal begin used outside real top level or a macro-expansion result\n(e.g. a non-first body form, or an if branch) lowered every child eagerly\nvia ir.lowerBegin before any of them compiled. A define-syntax sibling's\nregistration into the macro table is a side effect of *compiling* its\nnode, not of lowering it, so a later sibling lowered in the same pass\nnever saw it via lookupMacro — its macro use compiled as a plain call to\nan unbound global instead of deferring to real expansion.\n\nlowerBegin now reserves a literal define-syntax sibling's name the\nmoment its form is reached, before lowering the next sibling, mirroring\nhow compiler_lambda.scanBodyDefs already resolves the identical problem\nfor a body's own leading definitions. The reservation never overwrites a\nname already visible (a real transformer from this scope or an\nenclosing one), and rolls itself back if a later sibling fails to lower.\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-28T19:40:56Z",
          "tree_id": "6528211d11615f606389a4c3312c373bc4937acf",
          "url": "https://github.com/kaappi/kaappi/commit/34774bf4d0fcc48e24962a275b66bd16ba1fadc1"
        },
        "date": 1785270241401,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.350526,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.173684,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.601917,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.039383,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006335,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.047234,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.316345,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057487,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.574898,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.247229,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.612498,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.443902,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.811295,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.65011,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043621,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "8dbe0342812f417582aba85e9cbb9289eab62945",
          "message": "Resolve a macro's def-env-bound free references through their own library (#1824)\n\n* Resolve a macro's def-env-bound free references through their own library, fixing issue #1812\n\nA macro's free reference to a name its own defining library binds (exported\nor not) previously resolved by bare name against the use site's mutable\nglobals table: a procedure reference was left completely unrenamed, and a\nnon-procedure reference was only protected against lexical (let/lambda)\nshadowing at the use site, not against a genuine top-level redefinition of\nthe same name — since that protection still read the importer's own\nvm.globals at the injected instruction's execution time. An unrelated\ntop-level `(define helper2 ...)` in the importing file could silently\ncorrupt an already-imported macro's expansion.\n\nGeneralizes #1715's `__kaappi_base__` mechanism (routing a compiler-\nsynthesized reference through a stable registry instead of vm.globals) to a\nnew, per-transformer `__kaappi_defenv__<libname>\\x1f<origname>` prefix that\nget_global/call_global/set_global resolve through that specific library's\nown environment at runtime — never touching the use site's globals table for\nthese names. Values stay unbaked (a plain symbol, not a `load_const`\nconstant): embedding a resolved Closure/NativeFn as a bytecode constant\nsilently downgrades to nil on a `.sbc` cache round-trip, the same mistake\n#1715's own first draft made and abandoned.\n\nExcludes true `(scheme base)` bindings merely re-exported by a library\n(call-with-values, raise-continuable, with-exception-handler, etc.) from the\nnew mechanism — several compiler spots (compileCallWithValuesTail's is_tail\ndispatch, chief among them) recognize these by exact bare name, and a real\nregression in SRFI 248's guard macro during development confirmed the\ntail-call dispatch silently breaks otherwise. Also teaches\ntypes.stripHygienicPrefix to recognize the new prefix alongside the existing\n__hyg_ one, fixing two more real regressions found the same way: SRFI 41's\nstream-match (a macro whose template defines another macro via\nletrec-syntax, which must not re-wrap an already-prefixed reference) and\nSRFI 211's define-macro (whose lisp-transformer/er-macro-transformer\nkeywords are SRFI 211 primitives, not scheme-base ones, so the scheme-base\nexclusion alone didn't cover them).\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* Also exclude tail_call_global from caching a def-env resolution (#1812 follow-up)\n\nget_global/call_global/set_global were each guarded against caching a\n__kaappi_defenv__-prefixed resolution (self.global_version doesn't catch a\nlibrary's own internal set! on its def_env), but tail_call_global — the\ntail-position counterpart of call_global, populating the same\nfunc.global_cache from the same lookupGlobalLocked — was missed. Found by\nre-auditing every func.global_cache populate site after rebasing onto\n#1817, which touches the same cache machinery in call_global/\ntail_call_global.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-28T19:40:43Z",
          "tree_id": "36f1f193e53db828f51b426e2e197fb87baba200",
          "url": "https://github.com/kaappi/kaappi/commit/8dbe0342812f417582aba85e9cbb9289eab62945"
        },
        "date": 1785270935355,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.351355,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.268028,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.578822,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.008159,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006351,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046924,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.315281,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057326,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.46505,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.251948,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.605648,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.435969,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.79819,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.692177,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044675,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "3d9dae15ac0bbac2e74ceae16cfc0fe3ebfdd754",
          "message": "Drop stale cross-thread concurrency limitation docs, fixing #1793 (#1825)\n\nREADME.md, lib/kaappi/parallel.sld, and benchmarks/gate/ still described\n#1487, #1489, and #1520 as open -- all three were fixed 2026-07-13/14/15\nand have regression tests. This understated a working feature (README\ntold readers not to use cross-thread channels in production) and left\nthe gate harness's self-containment rationale reading like a live engine\nbug report instead of a completed benchmark's historical protocol note.\n\nReplaced the stale caveats with the constraint that's actually still\ntrue: a channel (or a pool containing one) must reach the other thread\nthrough lexical capture in the thunk, not a shared top-level define\n(#1742).\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-28T20:42:48Z",
          "tree_id": "a683312c38023a86fa062019aafd848220761197",
          "url": "https://github.com/kaappi/kaappi/commit/3d9dae15ac0bbac2e74ceae16cfc0fe3ebfdd754"
        },
        "date": 1785274549326,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.034926,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.42476,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.572354,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.880802,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006715,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.045598,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.302395,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.055591,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.373733,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.190613,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.559658,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.47289,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.730701,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.704533,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045445,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "5d9c38fefd0443641edb311d0cb49f05af9354c6",
          "message": "Split src/types.zig into 11 domain files, fixing #1731 (#1827)\n\ntypes.zig had grown to 1871 lines (already 1605 before #1730, both over\nthe 1500-line policy), one heap-type addition at a time across 105\ncommits. Splits struct/enum definitions by domain (types_ffi.zig,\ntypes_port.zig, types_continuation.zig, ...) while types.zig re-exports\nevery name (`pub const Foo = types_x.Foo;`), so the dozens of existing\n`types.Foo` call sites across primitives_*.zig, vm*.zig, gc_collect.zig,\ngc_deep_copy.zig, and printer.zig need no changes. Object.expectedTag()'s\nswitch is also untouched — it already referenced bare names, which now\nresolve through the re-export aliases.\n\ntypes.zig drops to ~1200 lines; each new file is 35-190 lines. Verified\nwith zig build, zig build test, the full Scheme suite (2008 pass), and\nzig build test -Dgc-stress=true, per the issue's own re-verification\nchecklist for the GC mark/sweep switches.\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-28T21:12:31Z",
          "tree_id": "311a2f08ec9f5cbf0f3e0bd9c60a43262728ebfe",
          "url": "https://github.com/kaappi/kaappi/commit/5d9c38fefd0443641edb311d0cb49f05af9354c6"
        },
        "date": 1785275449153,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.774613,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.015899,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.543421,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.667183,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006797,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.044669,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.286428,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.054396,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.679593,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.085522,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.489511,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.404505,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.637716,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.939072,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.040679,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "55e1bf32cd510d33f21db3c28dac84b5c3b25ca0",
          "message": "Bypass ReleaseSafe allocator 0xAA fill on hot, size-proportional buffers (#1830)\n\n* Bypass the ReleaseSafe allocator fill for GC object payload buffers\n\nZig 0.16's std.mem.Allocator.alloc/.free/.dupe unconditionally\nmemset(..., 0xAA) new and freed memory in ReleaseSafe, inside their\nown generic bodies rather than the vtable functions they call into.\nThis makes the fill unavoidable via a backing-allocator swap or\n@setRuntimeSafety(false) at the call site (confirmed by disassembly)\n- the only way around it is to call rawAlloc/rawFree directly.\n\nAdd allocSliceNoFill/freeSliceNoFill/dupeSliceNoFill to memory.zig\nand use them for every GC object's variable-length payload: vector,\nstring, and bytevector data, closure/native-closure upvalues, record\ninstance fields, continuation backing buffers, multiple-values\narrays, hash table entries (including rehash's growth), numeric\nvectors, and fiber register/frame arrays. Both the constructors in\nmemory.zig and the matching frees in gc_collect.zig's freeObject are\nconverted together, since a mismatched pair would silently keep\npaying the tax on whichever end was missed.\n\nKaappi's own Debug-mode poisoning, FREED_OWNER stamping, and\ngc-stress quarantine are unaffected - they're implemented\nindependently of whatever the underlying allocator does.\n\n* Bypass the ReleaseSafe allocator fill for bignum arithmetic buffers\n\nEvery bignum add/sub/mul/quotient/remainder allocates a scratch\nlimbs buffer, uses it briefly, then frees it - paying the\nalloc-fill and free-fill back to back on every operation. Convert\naddMagnitude/subMagnitude/mulMagnitude/divMagnitudeBySingleLimb/\ndivMagnitudeMulti and their call sites, plus the bignum-to-string\ndupe sites, to the allocSliceNoFill/freeSliceNoFill/dupeSliceNoFill\nhelpers from memory.zig.\n\nparseBignumString is deliberately left alone: it's a cold,\nnumber-literal-parsing path (not the arithmetic hot loop) built\naround realloc, which would need a fourth helper for one path that\ndoesn't earn it.\n\n* Bypass the ReleaseSafe allocator fill for VM growth and call/cc capture\n\nensureFrameCapacity/ensureRegisterCapacity double the register file\nand call frame stack on overflow, copying live data into a fresh\nbuffer before freeing the old one - both ends were paying the\nallocator fill. captureContinuation's scratch SavedFrame buffer is\nsimilar: allocated, copied into the continuation's own backing\nbuffer, and immediately freed.\n\nvm_continuations.zig didn't previously import memory.zig directly\n(it only reached it transitively through vm.zig, which doesn't\nre-export it), so add that import alongside the two converted call\nsites.\n\n* Bypass the ReleaseSafe allocator fill for string/bytevector builders\n\nTwo recurring shapes in these files pay the allocator fill: a\nmutation primitive (string-set!, string-copy!, string-fill!) that\nrebuilds and frees a string's backing buffer when the new content's\nUTF-8 byte width changes, and a \"double-alloc\" builder pattern where\na primitive fills a scratch buffer and immediately hands it to\ngc.allocString/allocBytevector, which copies it again. Convert both\nshapes wherever the buffer size is proportional to the string or\nbytevector being built, across string, make-string, list->string,\nstring-set!, string-copy!, string-fill!, string->list's >4096\ncodepoint fallback, string->vector, the SRFI-13 join/concatenate/pad/\nreverse/replace family, and the bytevector constructor, append, and\nread-bytevector paths.\n\n* Bypass the ReleaseSafe allocator fill for vector builders\n\nSame double-alloc builder pattern as the string/bytevector\nprimitives: list->vector, vector-append, vector->string,\nvector-reverse-copy, vector-unfold(-right), vector-concatenate,\nvector-cumulate, vector-partition, reverse-list->vector, and\nvector-append-subvectors each fill a scratch buffer before handing\nit to gc.allocVector, which copies it again.\n\nThe ~14 call sites gated behind \"only allocate past a 256-element\nstack buffer\" (vector-count, vector-any, vector-every, etc.) are\ndeliberately left alone: converting them is safe but their hot path\nnever touches the allocator, so there's no measurable benefit.\n\n* Document the allocator-fill finding and measured results\n\nExtend performance.md's \"when the profile bottoms out in memset\"\nsection with the second, distinct fill source this issue found\n(allocator convenience methods, not stack declarations) and why the\nexisting declaration-scope fix doesn't apply to it. Add a\nlessons-learned.md #11 entry with the measured benchmark deltas.",
          "timestamp": "2026-07-29T08:29:49+05:30",
          "tree_id": "10559fc909ec86234fb8833288f98d8fdb7a382b",
          "url": "https://github.com/kaappi/kaappi/commit/55e1bf32cd510d33f21db3c28dac84b5c3b25ca0"
        },
        "date": 1785296389432,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.358271,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.066969,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.58685,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.986204,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00469,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.047266,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.315617,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057174,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.657842,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.258564,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.613749,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.283593,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.831632,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.61627,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043424,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "26334d245d9316529485ceed693cf50be343dfdd",
          "message": "Fix syntax-rules wholesale re-collection of sibling ellipsis variable, fixing #1721 (#1833)\n\nA template like `(list (list formal (list binding ...)) ...)` where\n`formal` and `binding` come from independent pattern groups\n`(_ (formal ...) (binding ...))` failed with EllipsisCountMismatch when\nthe groups had different lengths, and silently consumed `binding`\nper-iteration (instead of replicating it wholesale) when lengths matched.\n\nRoot cause: `templateReferencesVar` recurses into ALL sub-expressions\nincluding inner `(x ...)` sub-templates, so it wrongly marked inner-only\nbindings as driving the outer repeat count.\n\nFix: two-pass repeat-count determination. Pass 1 finds \"direct\" drivers\nvia `templateReferencesVarDirectly` (which skips sub-expressions consumed\nby inner ellipses) and deep (depth > 1) bindings. Pass 2 classifies\nremaining indirect-only bindings using `sharesInnerEllipsisWithDriver`:\nif a binding shares an inner `(elem ...)` sub-template with a Pass-1\ndriver, it belongs to the same pattern group and is consumed per-iteration\n(SRFI 149 excess-ellipsis replication); otherwise it's from an independent\ngroup and is passed through wholesale with its full list state intact.\n\nAlso tightens `ellipsisReferencesOuter` to use the same direct-reference\ncriterion, so a binding appearing only inside an inner ellipsis of a\nnested syntax-rules doesn't wrongly claim the ellipsis for the outer macro.\n\nCo-authored-by: Claude Opus 4.6 <noreply@anthropic.com>",
          "timestamp": "2026-07-29T10:50:36+05:30",
          "tree_id": "a5dc876a82b46de62a3b54c4c53d26e0775ec50e",
          "url": "https://github.com/kaappi/kaappi/commit/26334d245d9316529485ceed693cf50be343dfdd"
        },
        "date": 1785304857018,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.344853,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.543324,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.612053,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.000421,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004796,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046801,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.316304,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057665,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.665755,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.23366,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.59588,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.286026,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.831379,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.623996,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043457,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "1ef8268df43960aa38758a2746c032d93e77e1a0",
          "message": "Implement SRFI 150 (Hygienic ERR5RS Record Syntax), fixing #1810 (#1834)\n\nBuilds on SRFI 131's runtime substrate: a type name is bound directly to\nan ordinary SRFI 237 record-type-descriptor, with inheritance and\nfield/accessor/mutator resolution handled at run time by SRFI 237's own\nby-name introspection. The one piece SRFI 131 lacks -- hygienic\nfield/accessor-name matching for named constructor specs -- uses SRFI\n213 (identifier properties) instead of a query macro, so\ndefine-record-type itself is a SRFI 211 er-macro-transformer rather than\nan em-syntax-rules macro.\n\nTwo earlier designs (porting the reference's own SRFI 137 make-subtype\nclosures, then a from-scratch rewrite using a :secret descriptor macro\nover SRFI 237) both broke once more than one cross-expansion query\nrelationship existed side by side in the same program, isolated to\nem-syntax-rules engine bugs kaappi#1828 and kaappi#1829. This design\navoids that whole pattern by never threading anything across separate\ndefine-record-type expansions via a macro call.\n\n21 of 25 tests ported from the reference suite pass; the other 4 are\nmarked test-expect-fail/annotated, hitting a precise, minimal,\nrecord-free reproduction (kaappi#1832) of the already-documented\n\"top-level redefinition reaches the expansion\" hygiene limitation. A\nsecond new engine quirk (kaappi#1831) was found and worked around:\ncadar specifically fails when called from a helper function invoked\nduring an er-macro-transformer's expansion.\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-29T10:50:53+05:30",
          "tree_id": "96c5f9a89acc11c428968eda72321dba0d5991f7",
          "url": "https://github.com/kaappi/kaappi/commit/1ef8268df43960aa38758a2746c032d93e77e1a0"
        },
        "date": 1785305368206,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 2.801842,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 5.202766,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.386289,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.039391,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004223,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.034061,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.212214,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.040091,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.005934,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.840427,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.126569,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.221222,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.23975,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.696117,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.032836,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "b83f4c249d757257f76758ff59c58b4a9026fa2d",
          "message": "Isolate -Dbundle test builds from the shared kaappi binary (#1826)\n\ncompile-import-error-703.sh and compile-preamble-gc-700.sh rebuilt\nzig-out/bin/kaappi in place to embed test bytecode, then rebuilt it a\nsecond time to restore the plain interpreter for later tests in the\nsame run-all.sh pass. run-all.sh and every other sequential test read\nthat same fixed path, so a test executed right after either of these\ncould race the restoring rebuild and observe a not-yet-settled binary.\n\nBoth invocations now install to a --prefix inside the test's own\ntmpdir instead, so the shared binary is never touched -- and the\nrestoring rebuild is no longer needed at all.\n\nFixes #1748\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-29T07:01:41Z",
          "tree_id": "a5a9f6a1cc86666147c66238c96fe18343c71d82",
          "url": "https://github.com/kaappi/kaappi/commit/b83f4c249d757257f76758ff59c58b4a9026fa2d"
        },
        "date": 1785310708270,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.417951,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.757462,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.583902,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.9967,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004631,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046701,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.315781,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057292,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.670374,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.237658,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.594862,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.277852,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.812756,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.65037,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043299,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "07adabaf2211c8c8b2388c6ba49dcc4bca09069e",
          "message": "Bound fuzz generator gates by instruction count on Debug builds (#1835) (#1836)\n\n`zig build test -Doptimize=Debug` is its own ubuntu-latest CI leg, and the\n`portable-subset generator: programs evaluate without error` gate fails on it.\nThe gate bounds each generated program by a 100 ms wall clock, which stops\ntracking work done as soon as the whole pipeline runs unoptimized.\n\nMeasured over the gate's own 60 fixed seeds under Debug: the in-`vm.eval`\nwindow is 35 ms min / 91 ms median / 435 ms max against that 100 ms budget --\nthe median *correct* program already sits at the threshold. 9 of 60 seeds\nmissed, every one as `.resource_limit`, none as a compile or runtime error.\nTwo structural details make the miss set jitter rather than a real\nslow-program signal: the deadline is only checked inside `runUntil`, so the\nfixed leading `(import (scheme base) (scheme char) (scheme lazy)\n(scheme write))` -- ~26 ms, a quarter of the budget -- spends it without ever\nbeing able to trip it, and read/expand/lower/emit are unchecked for the same\nreason. Consecutive runs of the same fixed seeds disagree about which seeds\nmiss, which is what made this look nondeterministic.\n\nThis is the same wall-clock-vs-slow-execution class already fixed for\ngc-stress (#1447/#1449) and for emulated cross-compiled targets (#1573), where\nthe gates bound by instruction count instead -- speed-independent, identical\nno matter how fast each instruction runs. Debug was never added to that list.\n\nFold `builtin.mode == .Debug` into `speed_independent`, so Debug takes the\nexisting 2M-instruction bound and 120 s wall-clock backstop unchanged. The\nchange is confined to `src/tests_fuzz.zig`; the shipped binary is unaffected.\n\nThe existing regression guard could not have caught this: its two branches are\nself-consistent with whatever `speed_independent` evaluates to, so a mode\nmissing from the definition just takes the other branch and passes. Add an\nexplicit `if (debug_build) try expect(speed_independent)` ahead of them.\nMutation-tested: dropping the `or debug_build` term makes the guard fail on\nthat exact assertion under Debug.\n\nThe issue also reported a second failure mode -- a native stack overflow with\na repeating `eval -> compile -> lower -> eval` cycle and \"445+ additional stack\nframes skipped\". That is not a stack overflow and not a second bug. The message\nis emitted only by `writeErrorReturnTrace` (std/debug.zig, `skipped =\net.index - len`), so it is an accumulated *error return trace*, not a call\nstack; the \"cycle\" is ~50 repetitions of one 9-frame CompileError propagation\npath. The Debug run that produced it ended in an ordinary test failure\n(1377 pass, 4 skip, 1 fail), with no panic. Its `--seed` dependence was also\nillusory: in non-fuzz mode Zig replays only the fixed corpus, and these gates\nuse hardcoded seeds 0..59, so the 60 programs are byte-identical every run.\n\nVerified: full unit suite green under both `-Doptimize=Debug` and ReleaseSafe;\n`-Dtest-filter=generator` under Debug goes from 1 fail to clean.\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-29T08:13:39Z",
          "tree_id": "be4a83135112401f4c161ba7fccbe6a72338b758",
          "url": "https://github.com/kaappi/kaappi/commit/07adabaf2211c8c8b2388c6ba49dcc4bca09069e"
        },
        "date": 1785314913189,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.086798,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.097804,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.413152,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.195082,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004327,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.03481,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.229714,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.04209,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.092697,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.932788,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.201289,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.234582,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.317626,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.739714,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.034441,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "6e9043b3f3e2faf8f03b8a0e14507943faaf4374",
          "message": "Hygiene-rename free-global macro references to avoid arg collisions (#1839)\n\nexpandAndCompileMacroUse implemented R7RS 4.3.1 referential\ntransparency for a template's free reference to a global that already\nexisted at the macro's definition time by temporarily marking that\nglobal VOID, signaling renameForHygiene to leave the reference\nunrenamed so an injected register alias could pierce use-site\nshadowing under that bare name.\n\nA bare, unrenamed reference is indistinguishable from any other\nidentifier of the same spelling introduced elsewhere in the same\nexpansion -- including a pattern-variable argument the caller supplied\nwith that exact spelling. `(def a)`, where `def`'s own template\nfree-referenced a pre-existing global `a` while also taking `a` as an\nargument, collapsed both to the same bare symbol: `(let ((a 5)) (def2\na))` returned `(999 999)` instead of `(999 5)`, and a set!-based\nvariant could overwrite an unrelated use-site local instead of leaving\nit untouched.\n\nThe reference is now hygiene-renamed like any other\ntemplate-introduced identifier (mirroring what a set!-target prescan\nalready did, and how injectHygienicCapturedLocals already handles the\nanalogous captured-local case from #1288), and its\nreferential-transparency alias is injected under that renamed name --\nfound by walking the expansion, in injectHygienicGlobalAliases --\ninstead of the bare one. compileSet's write-through (both the legacy\nand IR compile paths) now targets the real global name via a new\nLocal.alias_global_name field rather than assuming the alias local's\nown name matches it.\n\nFixes #1832\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-29T15:02:17+05:30",
          "tree_id": "eef0e2eb41b2a93876a602c273fad9e0674b6ee6",
          "url": "https://github.com/kaappi/kaappi/commit/6e9043b3f3e2faf8f03b8a0e14507943faaf4374"
        },
        "date": 1785319783802,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.839922,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.03053,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.548895,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.743858,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00494,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.04479,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.28397,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.053472,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.766567,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.11009,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.485242,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.263151,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.665809,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.921716,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.04088,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "5f74d6663b888e7dff3f672873d87050d4027c85",
          "message": "Comptime-gate lever-D bytevector checks in gc_collect.zig, fixing #1794 (#1838)\n\n`Bytevector.shared` is only ever set by `allocBytevectorShared`, called\nsolely from gc_deep_copy.zig's `if (comptime instrument.enabled)` block\n(KEP-0002 Phase 7 lever D, kaappi#1472). In a shipped build the field is\nprovably always null, but `freeObject` and `objectSize` in gc_collect.zig\nstill branched on it at runtime. Wrap both in the same `comptime\ninstrument.enabled` gate gc_deep_copy.zig already uses, so a shipped\nbinary never loads the field and a reader can tell from the code that\nthe branch is dead there.\n\nBehavior is unchanged in both build modes -- verified via `zig build\ntest` under the default and -Dchannel-instrument=true configs (including\ntests_shared_channel.zig's lever-D test, which exercises both changed\nsites), plus the full `tests/scheme/run-all.sh` suite (2009 pass, 0\nfail). This is a comptime dead-code-elimination clarity fix with no\nbehavioral change, so no new regression test is added.",
          "timestamp": "2026-07-29T15:02:39+05:30",
          "tree_id": "05f766564c8d5773e840fbf30f6d3f034972ff9b",
          "url": "https://github.com/kaappi/kaappi/commit/5f74d6663b888e7dff3f672873d87050d4027c85"
        },
        "date": 1785320365649,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.037525,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.282572,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.57214,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.841028,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004951,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.045263,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.302667,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.054359,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.338138,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.181388,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.525819,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.310515,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.729496,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.769617,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.047117,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "70450499b7bc80cee6656bcea021f8a265fe1120",
          "message": "Add Markdown linting to CI, fixing #1837 (#1840)\n\n* Add Markdown linting to CI\n\nThe repo had 82 Markdown files and no linter, while .zig was enforced three\nways. The gap was not theoretical: CodeRabbit -- not CI -- caught an MD018\nviolation in docs/dev/fuzzing.md (#1836), where prose wrapping left an issue\nreference at the start of a line, which Markdown reads as a malformed heading.\nThat failure mode is silent -- the doc renders wrong on GitHub and nothing\nerrors anywhere.\n\nMeasuring the fallout first changed the approach. The default rules give 2792\nviolations, but MD013 (line-length, 1032) and MD060 (table pipe padding, 997)\nalone are 73% of that noise. With those and nine other cosmetic rules off, 507\nremain -- few enough to clear entirely rather than start from a deliberately\nnarrow rule set and widen it over time. Every structural rule is therefore on,\nand the repo is left at zero findings.\n\nTwo of those rules must never be autofixed blindly, which is why the five\naffected sites were corrected by hand before running --fix:\n\n  - MD018 \"fixes\" a line-initial issue reference by inserting a space,\n    promoting prose to a real top-level heading -- making the very bug that\n    motivated this check worse. Doing so newly surfaced three MD025, one\n    MD026, and one MD001 as the phantom headings took effect.\n  - MD038 strips the space from the space-character literal in\n    docs/dev/fmt.md, corrupting the Scheme literal that paragraph exists to\n    document.\n\nBoth hazards are recorded in CONTRIBUTING.md so a later --fix cannot quietly\nreintroduce them.\n\nGlobs, ignores, and the rule set live together in .markdownlint-cli2.jsonc so\na bare `npx markdownlint-cli2` lints exactly what CI lints. AGENTS.md is\nignored because it is a symlink to CLAUDE.md and would double-report every\nfinding.\n\nFixes #1837\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Fix the MD018 violation the new check caught on main\n\nThe first CI run of the markdownlint step failed -- on a real violation,\nin the exact file and of the exact class that motivated this work.\n\ndocs/dev/fuzzing.md carried `#1573),` at the start of a line, which\nMarkdown reads as a malformed ATX heading. CodeRabbit flagged it during\nreview of #1836 and issue #1837 was filed about it, but the line merged\nto main unfixed. CI lints the pull-request merge commit, so the check\nsaw it even though this branch's own base predates that merge.\n\nFixed by rewrapping, never by MD018's autofix, which would have inserted\na space and promoted the prose to a real heading. The first rewrap\nattempt merely moved the problem to the following line (`#1835).`),\nwhich the check also caught -- the wrap point has to be chosen so that no\nline begins with the reference. The paragraph's word sequence is\nbyte-identical to main's.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-29T15:03:03+05:30",
          "tree_id": "ea76b813c4281128cc8379ea27f23f5fb25dac6c",
          "url": "https://github.com/kaappi/kaappi/commit/70450499b7bc80cee6656bcea021f8a265fe1120"
        },
        "date": 1785320959688,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.006945,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.368754,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.573906,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.843908,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004933,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.045208,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.302195,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.054352,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.367794,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.18058,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.519851,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.302982,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.723025,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.699176,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045383,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "9b1c479c0a8070e40d326394e707308e48da1762",
          "message": "Add regression tests for #1716's recursive generated-macro quote (#1841)\n\n#1716 reported that a macro-generating macro whose generated helper is\nself-recursive and quotes one of its own pattern variables substituted\nthe literal pattern-variable name instead of the captured identifier:\n`(collect a b c)` yielded `(nm nm nm)`.\n\nBisecting the repro against builds of 55e5bc6 (the commit that added\nSRFI 209, where the bug was found) and 76d6012 shows the defect was\nalready fixed by #1773 -- renameForHygiene used to skip the hygienic\nrename for any quoted identifier, splitting a nested syntax-rules\ntemplate's quoted occurrence of a pattern variable from the rename its\nown pattern side had already claimed. #1773 landed its own test for the\nnon-recursive shape only, so the recursive shape #1716 actually\ndescribed was left unpinned.\n\nAdd that coverage: three unit tests in tests_macros_nested_sr.zig\n(self-recursive, mutually recursive, and a quoted pattern variable\ninside a larger quoted list/vector datum) and an end-to-end Scheme\nsuite. Verified as real regression tests -- 11 of the Scheme suite's 13\nassertions fail on a pre-#1773 build and all pass now.\n\nAlso refresh the SRFI 209 comment that documented the workaround: the\nconstructor still routes through `type-name` rather than quoting `nm`\ndirectly, but now because `type-name`'s literals list rejects a name\noutside the enum type at expansion time instead of failing later inside\n`enum-set-adjoin` -- not because the expander can't handle the quote.\n\n\nClaude-Session: https://claude.ai/code/session_01KRP1wxfAwqVubfSW5TMK7Y\n\nCo-authored-by: Claude <noreply@anthropic.com>",
          "timestamp": "2026-07-29T17:06:42+05:30",
          "tree_id": "8c1e2ea0c6c20476facd9c07063f78c8c0e4506f",
          "url": "https://github.com/kaappi/kaappi/commit/9b1c479c0a8070e40d326394e707308e48da1762"
        },
        "date": 1785327979871,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.365796,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.795365,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.577292,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.973045,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004732,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.047016,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.315232,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057001,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.615204,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.238539,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.617288,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.280132,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.799592,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.613621,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044097,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "425c5d8f348b203cf2458401e22b31f68a7466a1",
          "message": "Cover macro-generated top-level define read-back, fixing #1829 (#1842)\n\nAn em-syntax-rules macro whose expansion defined a fresh top-level\nbinding and read it back in the same generated `begin` got a previous\nexpansion's same-spelled binding instead of its own. The issue was filed\nbefore #1839 landed and is already fixed by it -- A/B confirmed against\n07adabaf (fails) and 70450499 (passes) -- but nothing in the suite\ncovered the shape, so a future change to the free-global alias mechanism\ncould silently reintroduce it.\n\nThe issue's own hypothesis (a global inline cache keyed more coarsely\nthan binding identity) was not the cause. Because the CK machine builds\nits output as plain data, a macro-generated top-level define lands under\nits BARE name -- unlike a syntax-rules template, whose introduced define\nis hygienically renamed. That makes the bare name a real global, so the\nnext expansion's own reference to it is a free reference to an\nalready-bound non-procedure global, which the pre-#1839 code left\nunrenamed so an injected alias could pierce use-site shadowing (R7RS\n4.3.1). The bare reference was then indistinguishable from the parent's\nown symbol threaded back in by the `=>` query: the collision of #1832,\nreached through a generated define rather than a pattern variable.\n\nThe test asserts both the reported four-use sequence and a tighter case\nfound while isolating it -- pre-binding the storage name makes the\npre-fix build fail on the very FIRST parent-having use rather than the\nfourth. Read-backs are recorded through a procedure, which the alias\nmechanism excludes, so the recorder cannot perturb what it measures.\nBoth assertions were verified to fail pre-fix and pass post-fix.\n\nCLAUDE.md and lib/srfi/150.sld both described #1829 as a live bug;\nthey now record it as fixed with the real mechanism. #1828, re-checked\nand still reproducing, is untouched by that fix and on its own still\nrules out the query-macro approach SRFI 150 rejected, so no design note\nbelow it changes.\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-29T17:29:30+05:30",
          "tree_id": "fb8c8b038244ccdcb15a3f20b1e533267105aaef",
          "url": "https://github.com/kaappi/kaappi/commit/425c5d8f348b203cf2458401e22b31f68a7466a1"
        },
        "date": 1785328451325,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.004731,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.456413,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.566613,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.834439,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004893,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.04518,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.302746,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.054359,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.371465,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.182313,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.51821,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.302276,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.717729,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.739912,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044865,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "a251304138e761f239a50b1a28eb78bc1253d28e",
          "message": "Resolve library globals identically in all three global-ref opcodes (#1843)\n\nA library body's reference to a global that lives in vm.globals but not\nin its own lib_env resolved in tail position only. The compiler picks a\nglobal-reference opcode purely by syntactic position -- get_global plus\na plain tail_call for a tail call's operator, the call_global\nsuperinstruction for every other call -- but only get_global carried the\nvm.globals fallback library code has needed since 455f5cc2. So a library\nimporting just (scheme base) could call `(cadar x)` as its body's last\nform and got \"undefined variable 'cadar'\" for the identical call one\nsyntactic position over, which surfaced as a bare \"invalid syntax\" when\nthe caller ran at macro-expansion time.\n\nRoute get_global, call_global, and tail_call_global through one\nlookupGlobalLocked helper that takes the Function rather than a\npre-picked env, so all three see the same chain: the function's own\nenvironment, then vm.globals when it runs in a library (or eval)\nenvironment and is not restricted, then both again with any hygienic\nrename prefix stripped. The restricted_globals gate keeps a restricted\n(environment ...) as tight for a non-tail call as #1253 already made it\nfor a tail call.\n\nThis is also the \"unrooted-out compiler quirk\" documented for the SRFI\n237 primitives: a %-prefixed internal primitive is a vm.globals-only\nname, so it looked ambient in some positions and not others. Restore the\nidiomatic `cadar` in lib/srfi/150.sld's field-alist-ref and correct both\nCLAUDE.md notes -- `cadar` was never special, it was just the one\n(scheme cxr) name that file calls from a library-body helper.\n\nFixes #1831\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-29T17:30:55+05:30",
          "tree_id": "49f81e6a27feda3e726b94051192461098ae1e07",
          "url": "https://github.com/kaappi/kaappi/commit/a251304138e761f239a50b1a28eb78bc1253d28e"
        },
        "date": 1785329278888,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.207275,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.784655,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.444489,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.290458,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004574,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.035444,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.234637,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.046186,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.202524,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.927404,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.178374,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.25413,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.37079,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.771885,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.035485,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "4f0e04165903f96704c1ea8a9ede4085d4dfb2a3",
          "message": "Use list? instead of pair? for user-supplementary-gids audit test (#1845)\n\nSRFI 170 only promises user-supplementary-gids returns a list, not a\nnon-empty one. pair? fails for any process with no supplementary\ngroups, such as root in a minimal container image. The two other\ntests of this primitive (src/tests_filesystem.zig, coverage/\nfilesystem-coverage.scm) already use list?; this brings the audit\ntest in line with them.\n\nFixes #1844\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-29T12:52:04Z",
          "tree_id": "44ceb0e5a1e83dd91dd133b93297aa0b7c810e5a",
          "url": "https://github.com/kaappi/kaappi/commit/4f0e04165903f96704c1ea8a9ede4085d4dfb2a3"
        },
        "date": 1785332436286,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.262318,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.344864,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.585604,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.017051,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004642,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.045906,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.313121,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057236,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.731045,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.224679,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.575115,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.282595,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.778713,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.714679,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.046558,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "f5fefdd98f6ab54f4f6eacff3e142aa175e6639b",
          "message": "Surface procedural macro transformer errors instead of bare \"invalid syntax\" (#1847)\n\nA Scheme-level condition raised inside a SRFI 211 er-macro-transformer/\nlisp-transformer was computed, stored on the VM, and discarded before the\ncompiler's TransformerFailed collapsed to a generic InvalidSyntax -- #1831\nwas a one-line resolution bug whose real message was \"undefined variable\n'cadar'\", none of which reached the user, so it was chased for days as a\ncadar-specific primitives bug instead.\n\nglobals.error_detail_for_macro exposes the VM's last error detail to the\ncompiler (which cannot import vm.zig), and compiler_macro.zig's two\nTransformerFailed arms copy it into the same syntax_error_detail channel\nsyntax-error already reports through. vm.callProcForMacro also now calls\nnoteUncaughtException on failure: callReentrant (used to invoke the\ntransformer's own closure) preserves last_error_detail across its cleanup\nbut never populates it from current_exception the way execute()'s\ntop-level boundary does, so a plain (error \"msg\" ...) raised with no\nactive handler left last_error_detail empty -- confirmed with a throwaway\ndebug print before writing the real fix. A primitive's own type error\n(e.g. (car 7)) already set the detail directly and needed no VM change.\n\nFixes #1846.\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-29T19:34:59+05:30",
          "tree_id": "3e25d8b6cac716966277cac77537ad3788f4aa8f",
          "url": "https://github.com/kaappi/kaappi/commit/f5fefdd98f6ab54f4f6eacff3e142aa175e6639b"
        },
        "date": 1785336095846,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 5.052888,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.049565,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.572425,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.465807,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004673,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.049463,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.368885,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.056292,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.650948,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.422637,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.619859,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.28025,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.955041,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.556314,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.046612,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "85eb70ad47e31c833af1c2bccb200ccfd2fa2f3b",
          "message": "Close #1828 as not-a-bug: unquoted em-syntax-rules template, not chaining (#1849)\n\nThe reported \"variable bound by one => step can't be used as the operator\nof a later chained step\" symptom is fully explained by the repro's own\nfinal template being unquoted while calling an ordinary procedure\n(display) -- SRFI 148's spec documents that as an error case (\"It is an\nerror if the expanded output is not an eager macro use or a self-quoting\nsyntax element\"). The issue's exact repro, with only the final template\nquoted, already works correctly. Adds a regression test locking in the\ncorrect (already-working) operator-position chaining at 2 and 3 levels,\nand corrects the three places that cited #1828 as a confirmed, still-open\nengine bug.\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-29T17:15:08Z",
          "tree_id": "da74a46e2f02dc2360d76d6397309619c17bf50a",
          "url": "https://github.com/kaappi/kaappi/commit/85eb70ad47e31c833af1c2bccb200ccfd2fa2f3b"
        },
        "date": 1785347566928,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.046965,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.626059,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.566426,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.835356,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004886,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.044353,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.297311,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.054829,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.336662,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.173455,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.515401,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.304926,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.701495,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.771019,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044671,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "0822034d6d86cea9ac665ef3eb99a0f8c98e350a",
          "message": "Reclassify digit-led glued identifiers from KP1002 to KP1004 (#1848)\n\n* Reclassify digit-led glued identifiers from KP1002 to KP1004\n\n`3-state`, `5foo`, `1.2.3`, and similar tokens are correctly rejected --\nR7RS identifiers can never begin with a digit -- but the reader had\nalready committed to parsing a number on the leading digit, so the\ngeneric KP1002 (\"unexpected character\", whose explanation talks about\nstray '#'-syntax) named the wrong category, gave no hint, and pointed\nthe caret one column past the token's actual start.\n\nSuch a token now reports KP1004 (\"invalid number literal\"), the\naccurate code since the reader already committed to a number, with the\ncaret at the token's start and a message that echoes the offending\ntoken and states the rule. Surfaced consistently across the CLI's text\noutput, `kaappi check`, `kaappi compile`, and `--diagnostics=json` via a\nnew reader detail-message channel mirroring the compiler's existing one.\n\nFixes #1723.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* Address CodeRabbit review findings on the digit-led-identifier fix\n\n- readNumber's wrapper reclassified to KP1004 whenever any non-delimiter\n  followed a number, not just an identifier-continuation character. A\n  stray backtick or comma (e.g. `3\\``) is neither a delimiter nor an\n  R7RS <subsequent> char, so it wrongly took the new path and reported\n  \"invalid number literal '3': ... cannot begin with a digit\" -- both\n  mislabeling the valid number '3' and dropping the actual offending\n  character. Now only reclassifies when consumeGluedIdentifierChars\n  actually consumes at least one character; otherwise it falls through\n  to the original, accurate UnexpectedChar (KP1002).\n\n- setReadErrorDetail's bufPrint-overflow fallback claimed the full\n  256-byte buffer as valid content without knowing how much a failed\n  write actually populated. Rebuilt on Io.Writer + buffered().len --\n  the same pattern compiler.formatSyntaxError already uses -- so a\n  pathologically long malformed token (the format string embeds it\n  twice) truncates to a clean prefix instead of risking a stale tail.\n\n- Strengthened the \"valid numbers are unaffected\" test to assert each\n  case's actual type/value (fixnum/complex/flonum/rational) rather than\n  just that reading succeeded, and added regression tests for both\n  fixes above plus the equivalent CLI-level cases.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-29T17:26:19Z",
          "tree_id": "36ee992365ae3d5ee4934aa12b56146634115bb2",
          "url": "https://github.com/kaappi/kaappi/commit/0822034d6d86cea9ac665ef3eb99a0f8c98e350a"
        },
        "date": 1785348131357,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.08385,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.791491,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.436813,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.17329,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.003767,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.034303,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.227202,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.041663,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 1.772529,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.888564,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.170878,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.238203,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.314515,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.40522,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.035602,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "784bcc9954f55443add315f8c19eafb096d9bc88",
          "message": "Add /create-announcement skill for release announcements (#1851)\n\n* Add /create-announcement skill for release announcements\n\nPosting a release to the org forum was an undocumented manual task, and\nthe one non-obvious fact it depends on was written down nowhere: org-level\ndiscussions at github.com/orgs/kaappi are backed by the kaappi/kaappi\nrepository, not by kaappi/.github, which has discussions disabled entirely.\nA skill that guessed the obvious repo would fail on every run, so the repo\nand category ids are pinned in the file for the GraphQL fallback that\ncovers `gh discussion` still being a preview command.\n\nThe skill carries the editorial half as well as the mechanics. Release\nnotes are exhaustive by design; an announcement is not a second copy of\nthem, so the file specifies how to pick 3-6 highlights (what a user can now\ndo, not what changed), a body template, and a rule that every claim trace\nback to the notes. Posting stops for explicit approval first: it publishes\npublic content in a maintainer-restricted category and notifies every org\nwatcher.\n\nRunning it against v0.21.0 surfaced a defect in the skill itself that also\naffects skill authoring generally, hence the harness-doc section. A dollar\nsign followed by a digit inside a SKILL.md is rewritten by slash-command\nargument expansion before the body is ever read, so a snippet in the file\nis not necessarily the snippet that runs. The numbering is zero-indexed --\nthe zeroth token takes the *first* argument -- an absent argument leaves the\ntoken untouched rather than emptying it, and code fences do not protect\nanything. All of that is measured from probe invocations at 0, 2, and 3\narguments rather than inferred; an earlier inference here was wrong in a way\nthat would have caused three unnecessary edits.\n\nThe awk field variables in the DigitalOcean skills are therefore left alone:\nthey read the third argument, those skills take none, and they were never\nbroken. Their cost notes were the real exposure, since a dollar sign followed\nby zero claims the first argument and a single stray argument is enough to\ngarble the figure.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Address review: harden duplicate detection and fix two contradictions\n\nDuplicate detection listed the 30 newest announcements, which is exactly\nbackwards for the case that needs it most: announcing an older release, where\na duplicate is by definition not among the newest. Searches by tag instead --\nverified it returns the v0.21.0 announcement and nothing for an unannounced\ntag.\n\nThe GraphQL fallback fired on any non-zero exit from `gh discussion create`.\nThat mutation is a non-idempotent write, and a lost response -- posted server\nside, reply never arrived -- is indistinguishable from an outright failure at\nthe call site, so the fallback could publish a second announcement and notify\nevery watcher twice. It now re-runs the tag search first and only proceeds on\na zero count.\n\nTwo contradictions were self-inflicted. The troubleshooting row still claimed\nthe `@` and `*` forms get substituted, contradicting the measured table added\nin the same branch, which records that they never do. And the harness guide\nsaid \"seven steps\" for a skill that numbers eight, 0 through 7.\n\nThe link checker's character class excluded whitespace but not `>`, so an\nangle-bracket autolink contributed a URL with the delimiter attached and\nreported a spurious failure -- which blocks approval on a phantom defect,\nthe one failure mode a pre-flight check must not have. Also narrowed the\nmaintainer-restriction note: `kaappi/kaappi` is public, so a read-only token\ngets through both read steps and fails only on the write.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-29T23:33:24+05:30",
          "tree_id": "7558634fc17729f8435095fec0415861482ed320",
          "url": "https://github.com/kaappi/kaappi/commit/784bcc9954f55443add315f8c19eafb096d9bc88"
        },
        "date": 1785351459760,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.301584,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.509072,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.575373,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.945859,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004666,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046999,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.312916,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057159,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.650102,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.216049,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.598656,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.276192,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.794445,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.60208,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042692,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "distinct": true,
          "id": "ca18ae69c906ea598462a9d4a92438048f1ee880",
          "message": "Release v0.22.0\n\n93 new SRFIs (85 -> 178), closing the #1694 numeric-vector/array family,\n#1695 records, #1699 macros and syntax, plus #1702/#1703/#1810. The\nengine work behind them: procedural macro transformers (SRFI 211/213),\nnative apply lowering, and the types.zig split into 11 domain files.\n\nAlso refreshes counts that had drifted: built-in procedures 641 -> 690,\nprimitives files 26 -> 31, SRFI count 177/174 -> 178, and the R7RS suite\n1,391 -> 1,395 (what run-all.sh actually reports). SRFI 150 was missing\nfrom the CONFORMANCE table entirely; the table now cross-checks exactly\nagainst `kaappi features`.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-30T00:06:54+05:30",
          "tree_id": "d57dfad572decd1c4e313321ce9a5aefa255a8f8",
          "url": "https://github.com/kaappi/kaappi/commit/ca18ae69c906ea598462a9d4a92438048f1ee880"
        },
        "date": 1785352837302,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.948831,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.041143,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.560853,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.809119,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00488,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.044525,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.293782,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.054496,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.343196,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.160104,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.505738,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.305107,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.696183,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.803528,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045322,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "65743ab14c4cf2aec12de89182ebb9b45d38ea61",
          "message": "Split six oversized source files along their natural seams (#1853)\n\n* Split six oversized source files along their natural seams\n\nmemory.zig (2112 lines), expander.zig (1982), llvm_emit.zig (1710),\nvm_library.zig (1573), compiler_macro.zig (1530), and gc_collect.zig\n(1512) had all grown past the 1500-line file size policy through\ntangled coupling rather than breadth, so each is split at the seam\nwhere two domains shared one file:\n\n- memory.zig keeps the GC machinery (lifecycle, rooting, write\n  barrier, quarantine); the 61 allocXxx constructors move to\n  gc_alloc.zig, aliased back into GC so gc.allocXxx(...) call sites\n  are untouched (the existing gc_collect/gc_deep_copy precedent).\n- expander.zig keeps macro-use entry points, pattern matching, and the\n  hygiene-strip walks; template instantiation + renameForHygiene move\n  to expander_instantiate.zig, sharing the threadlocal expansion\n  context through qualified references.\n- llvm_emit.zig keeps the emitter core; the special-form and\n  eval-fallback emitters join the existing cond/case/do satellite\n  llvm_emit_forms.zig, aliased back into LLVMEmitter.\n- vm_library.zig keeps library definition/loading/SRFI 261/features;\n  the import-set algebra (only/except/prefix/rename) moves to\n  vm_imports.zig and is re-exported under its old names.\n- compiler_macro.zig keeps the macro-use path; the macro-defining\n  forms, SRFI 147 transformer-spec resolution, and syntax-rules\n  parsing move to compiler_define_syntax.zig, re-exported through the\n  same names so compiler_forms dispatch is unchanged.\n- gc_collect.zig keeps orchestration/marking/weak refs; the sweep\n  phase with the objectSize and freeObject per-tag switches moves to\n  gc_sweep.zig.\n\nPure code motion — no behavior change; same-name aliases keep every\ninternal and external call site compiling as-is. CLAUDE.md tables, the\nheap-type checklist, docs/dev (architecture, adding-features, harness),\nand the gc-safety rule globs (now src/gc_*.zig and src/expander*.zig)\nupdated to match. Remaining >1500-line files are the policy-exempt\nkinds: primitives_* and tests_* breadth, and generated unicode_tables.\n\nVerified: zig build test, full tests/scheme/run-all.sh (2013 pass,\n0 fail), and x86_64-linux / aarch64-windows / wasm cross-compiles.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n* Address PR #1853 review findings\n\nThe one reachable bug: compileLetSyntax registered its root-stack\ncleanup defer only after the binding loop, so a mid-loop InvalidSyntax\n(malformed later binding) or a failing resolveTransformerSpec returned\nwith earlier iterations' roots still pushed — permanently, since\nnothing resets the root stack on compile errors. The defer now\nregisters before the loop (still after tx_vals's deinit defer, so the\npops keep running first). Regression test fails without the fix.\n\nAlso from review: substitutePatternVarsOnly was caller-less (already\ndead before the split) and is removed, with the renameForHygiene doc\ncomment it had swallowed moved to the function it describes; gc_collect\ndrops the imports and type aliases only the moved sweep code used;\nstale gc_collect attributions in gc_alloc.zig/memory.zig comments now\nsay gc_sweep; the compiler table heading says 11 files (it had been\noff by one since before this PR); adding-features.md gains the\ntypes.zig typeName step.\n\nThe remaining review findings are deliberately not fixed here: the\nthree expander_instantiate push/pop sites are OutOfMemory-unwind-only\n(every user-reachable ExpandError path unwinds balanced) and match the\ndocumented canonical pattern used codebase-wide, and the native-backend\ninternal-define rooting question predates the split byte-for-byte —\nboth filed as issues instead.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-30T10:00:34+05:30",
          "tree_id": "d03d5c0fbf275c546dc0c8a575f244c9413a3bf4",
          "url": "https://github.com/kaappi/kaappi/commit/65743ab14c4cf2aec12de89182ebb9b45d38ea61"
        },
        "date": 1785388109052,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.255285,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.606989,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.561826,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.967353,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004648,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.04594,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.309985,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.056846,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.619017,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.217186,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.58321,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.282746,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.776658,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.646559,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.04271,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "1ecf1c4cd41701054b8c7e2766bb1c5b30062a1e",
          "message": "Root internal-define slots in native let bodies (#1854) (#1857)\n\n* Root internal-define slots in native let bodies (#1854)\n\nThe LLVM backend gave an internal `define` in a `let` body its own alloca\nbut never pushed it on the GC shadow stack, so the binding held the only\nreference to a freshly allocated value across every later allocation in\nthat body. A collection freed it and the memory was recycled into\nwhatever the body allocated next — a wrong answer in a compiled binary,\nwith no crash and no divergence in the interpreter:\n\n  (let ((a 1))\n    (define xs (list 11 22 33))\n    (do ((i 0 (+ i 1))) ((= i 200000)) (list i i i))\n    (car xs))            ; => 198492, not 11\n\nWhen the define held a procedure it was worse: calling the collected\nclosure died with \"not a procedure\".\n\nMove ownership of these slots to emitLet, which already owns the scope's\nroot accounting. Before emitting the body it walks the leading run of\n`(define <symbol> <expr>)` forms — R7RS's position for internal\ndefinitions — and for each mints an alloca, stores VOID, pushes it, and\ncounts it into the same binding_root_count the let's own bindings use.\nemitDefine's internal path now only evaluates the initializer and stores\ninto that slot, recognizing it through the new\nLLVMEmitter.scope_define_names.\n\nemitLet has to be the owner because the scope pops a fixed n at exit, so\nevery push it counts must execute exactly once. Pushes at the head of the\nbody dominate it; one emitted at a define nested inside an `if` would run\non one path only. Those are exactly the defines scope_define_names omits,\nand emitDefine answers UnsupportedNodeType for them so the enclosing let\nabandons and the interpreter — which binds a non-head define correctly —\ntakes the whole form.\n\nPre-creating every slot before any initializer runs is also letrec*\nsemantics, which is what a body of internal definitions means: a forward\nor self reference now reads VOID (bound but not yet assigned) instead of\nthe uninitialized alloca it read before.\n\nNo musttail interaction (#1499): mustTailSafe already requires\nself.locals == null, never true inside a let body.\n\nThe new compile test diffs native output against the interpreter for\nhead defines under GC pressure (single, multiple, nested lets, let*,\n`(let () ...)`, a procedure-valued define, redefinition, letrec*\nordering), pins the fallback shapes (a define inside `if`, after an\nexpression, begin-spliced), keeps #819's shadowing guard, and asserts\nthe emitted push/pop counts in @main balance. Nine of its cases fail\nagainst the pre-fix binary; the balance assertion catches a dropped\nroot count.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Address CodeRabbit review on the #1854 regression test\n\nTwo real problems in the new test driver, both flagged in review of #1857:\n\n- The runtime-archive setup hard-coded `zig-out/lib/libkaappi_rt.a` and\n  called `zig build lib` directly, copied from the older compile tests.\n  `shell-common.sh` has `ensure_runtime_lib` for exactly this: it knows\n  the archive's per-platform name (`rt_lib_name`) and accepts a prebuilt\n  one on a box with no Zig toolchain, so a machine running\n  cross-compiled binaries still exercises the compile+link path instead\n  of dying at `zig: not found`.\n\n- `--emit-llvm` was invoked with `|| true`, so a failed emission (or a\n  missing `.ll`) parsed as zero `kaappi_eval_cached` calls — which is\n  what a `native` case asserts. The one check meant to keep a silent\n  interpreter fallback from making a case pass vacuously could itself\n  pass vacuously. It now fails loudly; mutation-tested by replacing the\n  invocation with `false`.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-30T14:09:40+05:30",
          "tree_id": "4f28fdf7862de077935dcbf6570130467890429c",
          "url": "https://github.com/kaappi/kaappi/commit/1ecf1c4cd41701054b8c7e2766bb1c5b30062a1e"
        },
        "date": 1785403178859,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.274031,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.563857,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.567699,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.849652,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004425,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.045187,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.303359,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.056609,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.504615,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.156775,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.59125,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.273202,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.764437,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.511801,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044747,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "5ac7369522e55d0bf4d5269079d1ab488548069d",
          "message": "Stop (scheme base) from exporting %-prefixed internals (#1859)\n\n* Stop (scheme base) from exporting %-prefixed internals\n\n`(scheme base)` exported 22 `%`-prefixed internal primitives. Since v0.22.0\nalso began enforcing R7RS 5.2 (#1726), any user library that defined one of\nthose names and imported `(scheme base)` failed to load outright — the\ndocumented C-extension walkthrough, whose example exported `%length`, was\none such casualty. `%` is this codebase's own private-helper marker, so\nuser code has good reason to treat that namespace as its own.\n\nThe 22 names move off the `scheme.base` tag, and a comptime check in\nprimitives.zig now rejects any `%` name tagged with a `scheme.*` library.\nWhere they went depends on who names them:\n\n  - Only Zig-generated code names them (`%make-promise-lazy`,\n    `%parameter-set!`, `%parameter-convert`, the record substrate and its\n    `/inherit` variants): `.internal` — registered in vm.globals, exported\n    by nothing.\n  - A portable `.sld` names them in its own Scheme source (SRFI 27's\n    random-source accessors, SRFI 74's endianness probe, SRFI 271's random\n    ports, the record substrate SRFI 57/131/136/150/237 build on): also\n    `.internal`, plus a new `(kaappi primitives)` library those `.sld`s\n    import, so each declares the dependency it actually has.\n\nUnexporting them alone would have converted a loud error into a silent\nwrong answer: a library defining its own `%record-ref` would load, and its\n`define-record-type` accessors would then call it. Compiler-synthesized\nreferences therefore go through `Compiler.trueBuiltinRefOrSymbol` /\n`globals_mod.baseBindingSymbol`, resolving against a pristine startup\nsnapshot (`LibraryRegistry.internal_bindings`) rather than vm.globals —\nthe mechanism #1715 already used for let-values.\n\n`%length` is deleted rather than relocated: case-lambda's arity dispatch\nnow references `length`'s pristine `(scheme base)` binding directly, which\nis what the alias existed to approximate (#1714) and is strictly stronger,\nsince a top-level `(define (%length x) ...)` could overwrite the alias but\ncannot touch the export table.\n\nTwo adjacent fixes fall out:\n\n  - `kaappi check` no longer reports KP4001 on base-binding-prefixed\n    references. This was already wrong for let-values' synthesized\n    `call-with-values`; case-lambda, define-record-type, parameterize and\n    delay would have made it common.\n  - The globals drift guard now tests the invariant it meant to\n    (`vm_bootstrap.internal_helpers` are purged) instead of assuming every\n    `.internal` spec is purged, which only held while the two sets\n    coincided.\n\nFull suite: 2014 Scheme tests pass, 0 fail; unit suite green; sandbox,\nWASM, and x86_64-linux cross-compile verified.\n\nCloses #1856\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Fix stale primitive-registration docs (CodeRabbit)\n\n`reg()` has had no caller outside `registerAll`/`registerSandboxed` looping\nover `all_specs` for some time, but CLAUDE.md and src/CLAUDE.md still told\ncontributors to call it from a `registerXxx` function — which, after the\nprevious commit added the spec-table step beside it, left CLAUDE.md\ndescribing two registration workflows, one of which does not exist.\nBoth now describe the spec table alone.\n\nThe /add-builtin skill only mentioned `INTERNAL`; it now distinguishes it\nfrom `INTERNAL_PUBLIC` the way CLAUDE.md and docs/dev/adding-features.md\nalready do.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-30T14:10:13+05:30",
          "tree_id": "2c48981d86056b3b6c5e5f355dff2deaf3da8be4",
          "url": "https://github.com/kaappi/kaappi/commit/5ac7369522e55d0bf4d5269079d1ab488548069d"
        },
        "date": 1785403553400,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.227755,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.265657,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.599782,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.984523,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004969,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.04676,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.311196,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057363,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.654206,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.223407,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.586201,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.290857,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.809233,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.59505,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043186,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "ed5255ec942b95fe3601dc043e00e1249ad3b244",
          "message": "Unwind the GC root stack when an error escapes the pipeline (#1858)\n\nThe canonical pushRoot/try/popRoot rooting pattern leaks its root when the\n*protected* allocation is the one that fails: the error unwinds past the\npopRoot, and nothing else ever lowers root_count. The stack was left holding\nthe address of a local in a frame that no longer exists, which the next\ncollection dereferences — usually a garbage flonum under NaN-boxing,\noccasionally a plausible heap pointer. The extra entry also shifts the stack,\nso every `defer popRoot()` still to fire on the unwind path removes the wrong\nentry.\n\nThis is a property of the pattern, not of any one function, so fix it once at\nthe boundaries that hand a pipeline error back to a caller which keeps\nrunning: the four compileExpression* entry points, vm_eval.eval, and\nvm_calls.execute snapshot gc.root_count on entry and truncate back to it on\nerror. execute truncates inside its error branch rather than by errdefer\nalone, because that branch runs pending dynamic-wind after-thunks — which\nallocate — before returning. Per-site errdefers were the alternative: ~340\nedits of exactly the defer-near-a-loop LIFO footgun gc-safety.md warns about,\nwhich is how the compileLetSyntax bug fixed in #1853 happened.\n\nTruncation only ever shrinks. A depth below the snapshot is an over-pop, and\nre-rooting those slots would resurrect pointers into frames that have since\nreturned — the very bug this removes.\n\nReaching these sites needed a new test lever. gc.memory_limit is an absolute\nwatermark that only trips once a form *retains* more than its headroom, so it\nfails within the first few allocations and never reaches the expander (46\nfailures over 12,500 tries, zero leaks); FailingAllocator has its own\ndocumented deep-pipeline limitation. gc.oom_countdown fails the n-th\nallocation instead, gated on builtin.is_test so it compiles out everywhere\nelse. Sweeping it found the leak in exactly the two expander_instantiate.zig\nellipsis sites flagged in the #1853 review — 10 of 54 and 12 of 48 injected\nfailures — while every other shape swept (records, libraries, let-syntax,\nquasiquote, guard-caught primitive errors, dynamic-wind unwinding, call/cc)\nwas already balanced. Post-fix all are zero, and 3 of the 6 new tests fail\nwithout the fix.\n\nRecovery within a still-running form stays uncovered at primitive\ngranularity: snapshotting per native call would load the interpreter's\nhottest path for a hazard no primitive currently has. Documented in\ngc-safety.md and docs/dev/gc-safety-and-error-handling.md so a future\nunbalanced primitive is recognized as a real hazard.\n\nCloses #1855\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-30T09:35:31Z",
          "tree_id": "01b0d834ac52bd7e7e2f696144c97487e325ba9c",
          "url": "https://github.com/kaappi/kaappi/commit/ed5255ec942b95fe3601dc043e00e1249ad3b244"
        },
        "date": 1785406535845,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.940655,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.439171,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.561309,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.848459,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004935,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.044399,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.296764,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.054947,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.293547,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.166536,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.507953,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.30455,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.721641,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.63592,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044514,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "138857555a5aa83d8f1a5231e52a913d7a3154a1",
          "message": "Correct the three \"add a built-in procedure\" docs (#1863) (#1865)\n\n* Correct the three \"add a built-in procedure\" docs (#1863)\n\nAll three drifted far enough that two of them taught code that cannot\ncompile, so a contributor following them hit errors before reaching a\nreview. Rather than repeat the same content three times, make\ndocs/dev/adding-features.md the one detailed reference and reduce\nCLAUDE.md and the /add-builtin skill to checklists that defer to it.\n\nThe symbol names were the load-bearing errors. `primitives.gc_instance`\nand `primitives.vm_instance` do not exist and never did; the real\ndeclarations are the `memory.gc_instance` and `vm_mod.vm_instance`\nthreadlocals that all 31 primitives files already reach through those\nmodule names. The skill had a third spelling, bare unqualified\n`gc_instance`, which resolves in no primitives file at all.\n\nThe higher-order sample was wrong in a way the issue did not catch:\n`vm.callValue(proc, args_slice)` has no such method on VM, and the free\nfunction `vm_calls.callValue` is register-based — `(vm, callee, base,\nnargs)`. The slice-taking entry point is `vm.callWithArgs`. Since\nPrimitiveError and VMError are both aliases of errors.KaappiError, the\nsample now propagates the callee's error instead of flattening it to a\nTypeError and discarding the detail.\n\nThe skill also taught `return PrimitiveError.TypeError`, which the format\nCI job exists to prevent, so following the documented pattern broke the\nbuild. All three now teach `primitives.typeError(proc, expected, got)`\nand mention the expect* wrappers and the `// bare-ok:` opt-out. That\nguard's baseline was 91 against a current count of 20, leaving room for\n71 regressions; re-tighten it to 20 so it bites again.\n\nRemaining fixes: tests go in one of the 44 src/tests_*.zig files via the\ntesting_helpers (`th.`) API, not the \"src/vm.zig test section\" — vm.zig's\nsingle test block only pulls sibling modules into the test build and\nholds no assertions. Drop the step pointing at STATUS.md, deleted in\ncfe013ce. Correct the primitives table from 26 to 31 and add the 9 files\nit never listed, the stale src/vm.zig:37 and src/primitives.zig:182\nthreadlocal citations, and src/CLAUDE.md's test-file count.\n\nEvery sample was verified by compiling it: each was added verbatim as a\nreal primitive plus a th.expectEval test, built, run, and then reverted.\nThe documented error text is the observed output.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Address review: undeclared `result` in sample, domain-file count\n\nThree findings from CodeRabbit, all valid.\n\nThe skill's step-1 sample returned `types.makeFixnum(result)` with no\n`result` in scope — inherited from the old skill and carried forward\nunexamined, which is precisely the non-compiling-sample defect #1863 is\nabout. Replaced with the computed body already verified in\ndocs/dev/adding-features.md, and compiled it the same way: added verbatim\nas a real primitive plus a th.expectEval test, built, ran (6/6), reverted.\n\n`primitives_*.zig` is 30 files; the 31st is `primitives.zig` itself, which\nall three docs explicitly exclude in the same sentence that claimed 31 —\ninternally contradictory. Prose now says 30 domain files. The table header\nstays at 31: it counts rows, and the table lists `primitives.zig` as one.\n\nListing `IndexOutOfBounds` among tags \"returned directly\" contradicted the\npreceding recommendation of `indexError(proc, index, len)` for exactly\nthose failures, for the same attach-the-detail reason typeError exists.\nDropped it from that list and made the preference explicit.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-30T16:54:12+05:30",
          "tree_id": "e7982b0d61ddd19078d5b4f1911a36efb25c2583",
          "url": "https://github.com/kaappi/kaappi/commit/138857555a5aa83d8f1a5231e52a913d7a3154a1"
        },
        "date": 1785413943358,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.266495,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.827828,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.56789,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.004717,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004666,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046518,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.309417,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.056888,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.636908,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.208337,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.636028,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.279357,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.77862,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.611433,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043665,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "5c8480beb583d5e2ec155224bb533fb5e3d76f45",
          "message": "Let a library body reference an unimported global from its top level (#1866)\n\n#1831 gave get_global, call_global, and tail_call_global one resolver\ncarrying a vm.globals fallback, so a library body can reach a global that\nlives there but not in its own lib_env. The fallback is gated on\nFunction.restricted_globals, which compileExpressionInEnv derived from the\ncompile-time restricted_env flag it sets for both of its callers -- and it\nset it on the outer function of the form only, leaving every closure inside\nwith the field's false default.\n\nSo the same reference still resolved by syntactic position, one level up\nfrom what #1831 fixed: a library's (define v (cadar ...)) raised \"undefined\nvariable\" while the identical reference inside a lambda in the same body\nworked. It had the mirror hole too, which is why the flag could not simply\nbe flipped: for a restricted (environment ...), where withholding\nvm.globals is the point, those nested closures got false as well, so the\nrestriction held at the eval'd expression's top level and leaked through a\nlambda.\n\nMake it a property of the environment instead. compileExpressionInEnv takes\nan EnvKind naming which caller it serves -- a library body, which must keep\nthe fallback, or an R7RS restricted environment, which must not; the two\nhand it structurally identical env maps, so the distinction is not\nrecoverable from the map itself -- sets the flag before compiling, and\ninitChild copies it onto every nested function alongside the env it\nqualifies. gc_deep_copy carries it too, so a closure crossing a thread\nboundary is no leakier than the original.\n\nCompiler.restricted_env keeps its separate, compile-time-only meaning:\nglobals is a partial map, so IR.isRedefined must not read a missing name as\na known primitive. True for both kinds -- its comment claimed otherwise,\nwhich had been wrong since library bodies started setting it.\n\nCloses #1860.\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-30T17:15:11+05:30",
          "tree_id": "41068b345a7918405ec9615ba5fbaa1d42ea33f0",
          "url": "https://github.com/kaappi/kaappi/commit/5c8480beb583d5e2ec155224bb533fb5e3d76f45"
        },
        "date": 1785415059004,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.276233,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.768727,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.617116,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.020453,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004994,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.0475,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.319253,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057818,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.695021,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.223145,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.630102,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.289365,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.848658,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.688833,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045795,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "053282aeda7cb7f0e80a6ebd9765434bafd0dba7",
          "message": "Free the fiber scheduler when its setup allocation fails (#1869)\n\nensureScheduler takes the FiberScheduler from the raw allocator, then runs\ntwo more fallible steps — the main fiber's allocFiber and addFiber — before\nvm.scheduler is assigned. Until that assignment nothing owns the struct, so\na failure in either step returned with it neither destroyed nor stored,\nleaking both the struct and the managed waiter_index map init() built inside\nit. The reactor block directly below already cleaned up after itself; this\nmakes the scheduler block symmetric with its own neighbour.\n\nThe errdefer is block-scoped deliberately. It is discarded when the block\nexits normally, so it cannot fire for a later failure in the reactor block —\nby then vm.scheduler owns the pointer and freeing it would be a double free\nrather than a leak.\n\nSeverity is low on its own (a real OOM during the first spawn, one struct),\nbut the leak blocked writing any OOM-sweep test that reaches a fiber path:\nthe leak check aborts the test before its own assertions run.\n\nTwo regression tests. The first fails the allocation deterministically —\nthe scheduler comes from the raw allocator, which the injector does not\ncount, so oom_countdown 0 lands exactly on the main fiber's allocFiber — and\npins the bug in every build config. The second is the end-to-end sweep over\nthe first spawn; it asserts successes as well as failures, so a future spawn\nthat allocates more fails the test loudly instead of quietly sweeping past\nthe ensureScheduler window and going vacuous.\n\nFixes #1864\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-30T18:18:37+05:30",
          "tree_id": "c933b3d2ccee9d42b10d35247abf12ba73904592",
          "url": "https://github.com/kaappi/kaappi/commit/053282aeda7cb7f0e80a6ebd9765434bafd0dba7"
        },
        "date": 1785418072826,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.21046,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.86628,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.583619,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.982115,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004665,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.04628,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.316775,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057317,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.64402,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.225685,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.596481,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.2746,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.785316,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.56789,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045434,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "5400229c25e5e0e0a864e9aeeb0e02bea3f0ad24",
          "message": "Hand the whole enclosing scope to the interpreter when a nested let abandons (#1862) (#1867)\n\n* Hand the whole enclosing scope to the interpreter when a nested let abandons (#1862)\n\nA `let` nested in another `let` that gave up on native compilation\nmid-emission was handed to `kaappi_eval` on its own. That eval resolves\nnames in the global environment, so the outer `let`'s bindings were\ninvisible: the compiled binary died with `undefined variable` on code the\ninterpreter runs fine, or — with a same-named global in scope — silently\nread that global instead, which is worse.\n\n#827 already fixed this class for anything an up-front syntactic scan can\nsee, by declining native compilation of the whole enclosing scope. The\ntriggers here are only discoverable mid-emission and no scan can pre-empt\nthem: more than 32 bindings, more head defines than the scope roots, or an\n`ir.lowerSingleExpr`/`emitNode` failure on a binding initializer or body\nform. #1854 added the last of those, which is what surfaced this.\n\n`bindParamsAsGlobals` is the one chokepoint every whole-form eval fallback\ngoes through, and params, the rest parameter, and upvalues are the whole of\nwhat it can reach — a `let`-local lives in an `alloca` it has no name for.\nIt now refuses when `self.locals != null`, the way it already refuses a\nboxed param it cannot honestly publish. The error abandons the enclosing\n`let` in turn, so the interpreter gets that whole lexical scope in one\npiece. Publishing the locals instead was the other option and is worse: a\nboxed local hits the same by-location problem as a boxed param (#1422), and\nboth of that helper's documented weaknesses — it aliases across\nactivations, and it permanently clobbers a same-named global — would extend\nto let-locals.\n\n`emitLambdaViaEval`'s own locals check is now that same gate one line\nlater, so it is dropped rather than duplicated.\n\nVerified against a pre-fix binary: 11 of the new test's 13 cases diverge\nwithout this and pass with it. The two that pass either way are the\ncoverage guard (a fallback inside a plain lambda frame, where params *are*\npublishable, must still compile the lambda natively — its emitted IR is\nbyte-identical) and the shadow-stack balance check. A 34-program sweep over\nthe shapes this touches moved 7 cases from diverging to agreeing with the\ninterpreter, regressed none, and changed no program's eval-fallback or\nnative-function count: the eval widens from the inner let to the enclosing\nscope rather than replacing native code.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Fix a stale cross-reference in the #1862 backend note\n\nThe paragraph pointed at \"the mid-emission escape hatch below\", but the\nabandon path is not described further down this document — name\n`abandonLetForFallback` and its triggers directly instead.\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-30T14:01:29Z",
          "tree_id": "8ad26633e9cbbfc5d395b6974f558abaf4149d81",
          "url": "https://github.com/kaappi/kaappi/commit/5400229c25e5e0e0a864e9aeeb0e02bea3f0ad24"
        },
        "date": 1785422173386,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.946785,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.537929,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.584867,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.852584,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004924,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.044643,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.294229,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.054633,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.280049,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.163007,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.503969,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.307724,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.696324,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.798772,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.04564,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "a1301270410a98872534c481387ef84df7d8ff13",
          "message": "Name the expected type, and the right argument, in every type error (#1868) (#1871)\n\nThe `format` job's bare-TypeError ratchet stood at 20. Those 20 were not one\nthing, so this works through them in the four groups the issue identified: 9\ninfrastructure guards gain a `// bare-ok:` reason, 11 become real diagnostics.\nWith none left the ratchet loses its baseline and becomes a plain grep-and-fail,\nso there is no longer a number in CI to keep in step with the source.\n\nA bare return was never as anonymous as it looked, which is what made the\nbacklog easy to leave alone: `vm_calls.mapNativeError` already fills in\n`type error in '<primitive>': got <args[0]>` for any primitive that set no\ndetail. The procedure name survives. What is lost is the *expected* type -- and\nwhenever the offending value is not the first argument, the report confidently\nnames the wrong one. A string-keyed hash table handed a bad key blamed the\ntable itself:\n\n    -  type error in 'hash-table-set!': got #<hash-table size=0>\n    +  type error in 'hash-table-set!': expected string key\n         (this table compares with string=?), got 1\n\nReporting the key instead of the table means the hash-table key path has to know\nwhich procedure it is serving, so `proc` is threaded through equalForTable /\nhashForTable / findKey / findSlot / rehash / growIfNeeded. A fixed \"hash-table\"\nlabel would have been cheaper and nearly worthless: every call site already\nholds the exact literal one line above, in its own `getHashTable` call.\n\nTwo of the 20 were not type errors at all. R6RS's \"parent is sealed\" and a uid\ncollision both reject an argument whose type is perfectly good, which is what\n`invalid-argument` (KP3007) already describes -- \"a value a procedure explicitly\nrejects\", per its own registry entry. They now report that, via a new\n`primitives.argError(proc, fmt, args)` alongside `typeError`/`indexError`. The\nunknown-elision-lever check joins them for a second reason: `typeError` routes\nits value through `safeValueDescription`, which deliberately never dereferences\nheap payloads, so it renders every symbol as a bare `#<symbol>` and could not\nhave named the one passed.\n\nRegression tests assert the message text, since asserting that an error was\nraised -- or even that it names the procedure -- passes against the pre-fix\nbuild too. That is not hypothetical: the first version of the hash-table\nassertion did exactly that and had to be replaced with a pair that pins both\nthe old wrong answer and the new right one.\n\nWhile placing a `bare-ok` marker on threadStartFn's WASM branch, its comment\nclaimed the `else` was what kept std.Thread.spawn out of the wasm32 build. It\nis not. A `@compileError` canary in threadStartImpl fires under neither\n`if/else` nor a plain early return, though one in threadStartFn itself does\nfire: the pruning comes from the comptime-true branch returning\nunconditionally, not from the branch structure. Comment corrected, `else` kept.\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-30T21:28:21+05:30",
          "tree_id": "3efdccc8c2a3b74a8f43b5eee6905a6047e2ff52",
          "url": "https://github.com/kaappi/kaappi/commit/a1301270410a98872534c481387ef84df7d8ff13"
        },
        "date": 1785429660408,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.323705,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.046186,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.597107,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.017648,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.005077,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.047193,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.311865,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057113,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.789,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.225132,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.616054,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.287421,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.782857,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.675602,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043959,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "eed2ea6fc8eb9a42f7209d7f2531af66a30e61f2",
          "message": "End a timed wait whose deadline the dispatch tick already popped (#1870) (#1873)\n\n`runSchedulerStep` evaluates `!ctx.isDone() and !me.timed_out`, then calls\n`scheduleForDispatch()`, whose own per-tick `runReactorTick()` pops expired\ntimers. When that tick pops *this* fiber's deadline, `wakeReadyFiber` sets\n`me.timed_out` and the entry leaves the timer heap — but the loop guard has\nalready been spent on the pre-tick state, so the idle branch went straight\ninto `parkOnReactor` with nothing left to bound `reactor.poll()`. The\nfiber's own `shared_waiters` entry keeps `hasRunnableFibers()` true, so the\n\"nothing can ever happen\" early return is skipped too, and the poll blocks\nuntil some unrelated cross-thread notify arrives. The loop guard never gets\nits turn, because the park never returns.\n\nThat is the srfi120.scm flake: a timer thread parked on its control channel\nfor a 30 ms task would sleep indefinitely and only wake when the caller's\nown `timer-cancel!` message rang its notifier seconds later — by which point\ndelivery-wins hands it the `stop` message and the task never runs at all.\nWindows is where it showed up because `WaitForMultipleObjects` returns\nspuriously often enough (an auto-reset notify event left signalled by an\nearlier `SetEvent`) to put a loop iteration exactly where it needs to be:\npast the guard, with the deadline expiring during the tick.\n\nMeasured on the Windows ARM64 reference VM, one `(srfi 120)` timer per\niteration: 4 wedges in 13,500 iterations before, 0 in 9,000 after. macOS\nnever reproduced it in 7,000.\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-30T21:52:14+05:30",
          "tree_id": "71c991a9c4b1e000442a702a133f95ee60802fb9",
          "url": "https://github.com/kaappi/kaappi/commit/eed2ea6fc8eb9a42f7209d7f2531af66a30e61f2"
        },
        "date": 1785431274194,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.036862,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.295983,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.433564,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.249385,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.003781,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.034661,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.227601,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.042621,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 1.853378,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.885467,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.178073,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.233648,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.301973,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.365367,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.035083,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "6b1f4b9c20761581a51434dcd42e81063e140b03",
          "message": "Scope the procedure shorthand's internal define to its enclosing body (#1861) (#1872)\n\n* Scope the procedure shorthand's internal define to its enclosing body (#1861)\n\n`(define (f …) …)` inside a natively compiled `let` or lambda body compiled to\na global define, so an internal definition overwrote an outer one of the same\nname instead of shadowing it — and a helper referencing an enclosing binding\ncompiled to a global function whose body looked that binding up as a global,\nkilling the binary on code the interpreter runs:\n\n    (let ((a 3)) (define (h n) (* n a)) (h 5))   ; undefined variable 'a'\n\n#819 fixed this class for the symbol form and #1854 gave it a rooted slot, both\nin `emitDefine`. `lowerDefine` turns a pair target into a `.passthrough`, so the\nshorthand never reaches that path; it landed in `emitPassthrough`, whose two\npaths both define a global — `kaappi_define_global` when the body compiles\nnatively, and otherwise an `emitEvalExpr` that runs in the global environment.\n\nDecline the form whenever a lexical scope is active, so the enclosing scope goes\nto the interpreter whole (#827's rule). The gate is `inLexicalScope()`, not\n`locals != null`: a lambda body has no locals map and is lexical because of its\nparams, and had the identical bug. A `let` body abandons via `emitLet`; a\nfunction body fails `emitLambdaFunction` so the whole define falls back.\n\nDeclining also drops the name from `native_fns`/`rebound_globals` first. This\ninterpreter rebinds a body define that is *not* at the head of its body as a\nglobal, and a later call site that kept its direct call to the top-level\nfunction of the same name cannot observe that.\n\nCompiling it as a native local binding is the fuller fix, but it needs the\nclosure value in a rooted slot (#1854's machinery extended to a lambda-valued\ndefine) plus a way to keep the inner name out of the module-wide `native_fns`\nmap, where it would capture direct call sites outside its own scope.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Assert the direct-call binding without assuming the tailcc fast entry\n\nThe #1861 direct-call test matched only `call tailcc i64 @`, which exists only\nwhere `llvm_emit.fast_tailcalls_supported` — aarch64 and x86_64. On the\nQEMU-tier arches every direct call is the uniform array ABI instead, so the\nassertion passed vacuously and its own positive control failed, breaking\nppc64le-test, riscv64-test and s390x-test.\n\nMatch the callee position against all three spellings instead: the fast entry\n`@r{i}.fast`, and the uniform entry under a reserved name (`@r{i}`) or an\nunreserved one (`@lambda_{i}`). Anchoring on what follows `call [tailcc ]i64 `\nkeeps the `ptr @r0` *argument* of a kaappi_create_native_closure — present in\nboth the fixed and control programs — from being read as a call to it.\n\nVerified both ways by forcing `fast_tailcalls_supported` to false locally: the\ntest passes under either ABI, and still fails under either when the invalidation\nit guards is removed.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-30T22:26:06+05:30",
          "tree_id": "6a3844a99afc11b09419532e540e51ccc0d35412",
          "url": "https://github.com/kaappi/kaappi/commit/6b1f4b9c20761581a51434dcd42e81063e140b03"
        },
        "date": 1785432971533,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.973066,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.302041,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.573159,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.864319,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004874,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.044883,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.300815,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.055648,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.381858,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.167287,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.510843,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.299486,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.694847,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.618973,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044446,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "9f47679a7a0b1dede740a84280be47e3af5cb640",
          "message": "Settle the vm_instance/gc_instance guard tag, and write the rule down (#1875)\n\nThe ~450 threadlocal guards had drifted into a 46/34 TypeError/OutOfMemory\nsplit for the same \"the runtime is not initialized\" failure — two lines apart\nin primitives_hashtable.zig, and arbitrary in both directions (21 TypeError\nsites allocate; 13 OutOfMemory sites never do). There was already an implicit\nrule holding most of them together, but it was nowhere written down, which is\nhow the rest drifted.\n\nBoth halves of the fix:\n\nRule 1, unchanged and now stated: a guard returns the tag the function was\ngoing to return anyway, just without the formatted detail. That covers\ntypeError/indexError/argError/raiseDivByZero and the arity helpers, and — at\nscale — the 348 gc_instance guards in allocating functions, where no GC means\nthe allocation the function exists to perform cannot happen, so OutOfMemory\n*is* its error. None of those change.\n\nRule 2, the decision this issue asked for: with no natural tag, InvalidBytecode.\nA null threadlocal is an implementation-invariant violation, and that is the one\nKaappiError variant that means so. runtimeErrorCode already maps it to\n.internal_error (KP9001), whose registry template is the whole message the user\nsees since these guards set no detail — \"internal error … please report it\".\nOutOfMemory would send the reader after heap size; a bare TypeError is worse,\nbecause mapNativeError dresses it up as `type error in '<proc>': got <args[0]>`\nand so blames a real argument (the trap #1868 was about).\n\n82 sites move. The one-offs go with them: primitives_control's two no-VM\nfallback blocks retag whole rather than one return of four, and expander.zig's\nodd `error.TypeError` spelling becomes `error.InvalidBytecode`, which is a tag\nthat file can use honestly. Sites the issue blessed keep theirs, including\nbootstrapStub, whose guard mirrors its function's own tag.\n\nKP9001's template said \"internal compiler error\"; KP9xxx is stage .internal and\nthe code is now reached from the runtime too, so it is \"internal error\", with\nthe uninitialized-runtime path named in the explanation. One assertion pins\nruntimeErrorCode(InvalidBytecode) → .internal_error, since ~80 sites depend on\nthat arm and losing it would silently downgrade every one of them to the\nuncategorized catch-all.\n\nThe rule itself lands in docs/dev/gc-safety-and-error-handling.md, with the\nrejected alternatives named and one seam flagged: the raise* helpers ending in\nExceptionRaised split across both rules, because ExceptionRaised is the one tag\na guard cannot borrow — it promises vm.current_exception was set, and the guard\nfired precisely because there is no VM to set it on. adding-features.md, the\nadd-builtin skill, .claude/rules/gc-safety.md and the CI gate's own help text\nall taught the retired pattern by example, so they move too.\n\nNo behavior change: the threadlocals are set during VM init, before registerAll,\nso none of these guards fires in a working build.\n\nCloses #1874\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-30T23:39:46+05:30",
          "tree_id": "f793cadf890fe52bd056b5af462cbf871d89b081",
          "url": "https://github.com/kaappi/kaappi/commit/9f47679a7a0b1dede740a84280be47e3af5cb640"
        },
        "date": 1785437290587,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.275755,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.730863,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.573825,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.976157,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004688,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046403,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.314943,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057281,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.650338,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.231441,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.589625,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.27321,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.792627,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.596818,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.04317,
            "unit": "seconds"
          }
        ]
      }
    ]
  }
}