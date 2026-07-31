window.BENCHMARK_DATA = {
  "lastUpdate": 1785539638001,
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
          "id": "d529fdcc8d584641f05c69b0d7bedbd530af85be",
          "message": "Report an uninstalled bootstrap as KP9001, not a caller type error (#1877)\n\n`primitives.bootstrapStub` stands in for the 9 procedures whose real bodies\nare Scheme installed by `vm_bootstrap.install()`. It fired `TypeError`, which\n`diagnostics.runtimeErrorCode` maps to KP3002 — telling `--diagnostics=json`,\nthe LSP and `error-object-code` that the caller passed a bad argument type.\nThe truth is the opposite: Kaappi is mis-initialized, and nothing the user\ndoes to their program will help. That is KP9001's job, and its registry text\n(\"please report it with the program that triggered it\") is the right\ninstruction. Both lines are `InvalidBytecode` now.\n\nThe two were not equally wrong. The second sets a detail first, so only the\ncode misled. The first — the no-VM guard — set none, so `mapNativeError`\nsynthesized `type error in 'map': got <args[0]>`, naming a real list element\nas the culprit: wrong code *and* wrong message, the exact trap #1868 closed\neverywhere else. Both `bare-ok` annotations go away with the tag.\n\n#1874 left this alone for a good reason: its rule is that a guard returns the\ntag its function was going to return anyway, and the guard did mirror the\nfunction. The function's own tag is a separate question, and this answers it.\nBoth prose sites that recorded bootstrapStub as a settled Rule 1 keeper are\nupdated, with the distinction written down — a correct guard on a wrongly\ntagged function reads exactly like a site the rule has already cleared.\n\nThe stub is unreachable from every shipped entry point (every one calls\n`install()`; `runtime_exports` bails out if it fails), so this is a tripwire\nfor a new embedding that forgets the call — precisely when a code pointing at\nKaappi rather than at the user's arguments is worth the most. The existing\n#1375 regression test is kept and retargeted, and now also derives the\ndiagnostic code from the error the eval actually returned, so a silent\nre-tagging fails it; `runtimeErrorCode`'s own table stays pinned separately\nin tests_diagnostics.zig.\n\nCloses #1876\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-31T05:54:19+05:30",
          "tree_id": "2e1d8cfe47b9df35d8b96d4cfc768a8aabdb8371",
          "url": "https://github.com/kaappi/kaappi/commit/d529fdcc8d584641f05c69b0d7bedbd530af85be"
        },
        "date": 1785459831428,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.059243,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.600001,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.437131,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.232096,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.003879,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.034503,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.228697,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.042366,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 1.793723,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.888163,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.179701,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.243072,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.309579,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.415215,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.034944,
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
          "id": "7bd728d4a102b667ef52b211e2c4e4a635749bb9",
          "message": "Report a missing VM as an internal error in the last four guards (#1878)\n\nkaappi#1874 settled what a `vm_instance orelse` guard should return, but four\nsites kept `TypeError` through the sweep. Rule 1 vets a guard against its own\nfunction and never vets the function, so a correct-looking guard on a\nwrongly-tagged function reads exactly like a site the rule has already cleared\n-- the same trap kaappi#1876 hit with `bootstrapStub`.\n\nThe three `vm.zig` hooks are the easy half: they return `anyerror`, so there\nwas never a tag they were going to return anyway. `applyFn` is the one worth\narguing. `apply` does raise real type errors, for a non-procedure and for an\nimproper final list, which is why its guard looked settled. It isn't: Rule 1\ncovers a helper that fetches the VM only to attach a message to an error it\nwas already committed to raising, and `apply` fetches it in order to call the\nprocedure. A null threadlocal means `apply` cannot run at all. The\n`gc_instance` line under it keeps `OutOfMemory` -- two adjacent guards, one per\nrule.\n\nOnly `apply`'s tag is user-visible. It is a primitive, so a bare `TypeError`\nreached `--diagnostics=json`, the LSP and `error-object-code` as KP3002 \"you\npassed a bad argument type\" for a condition no program can cause; it is KP9001\n\"please report it\" now. The three hooks' callers collapse everything but\n`OutOfMemory` into `InvalidSyntax`/`TransformerFailed`, so their tag is read by\nthe next maintainer rather than by a diagnostic -- which is precisely why it\nneeded pinning, an unpinned readability-only tag being what drifted here in the\nfirst place.\n\nThe doc gains both decisions and the CI gate's two blind spots, with one\ncorrection to how they have been described: there are three spellings of this\nerror in `src/`, not two. `ffi.zig` declares inline `error{TypeError}` sets and\nuses neither the `PrimitiveError` nor the `VMError` alias, and it holds 27 of\nthe 35 out-of-scope sites -- so a grep widened from the two-alias description\nmisses all of them, which is the same blind-spot class the warning is about.\nWidening the gate stays out of scope; those 35 are real error conditions\nneeding triage, not threadlocal guards.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-31T01:18:07Z",
          "tree_id": "801ea451e4eb32d3cf37a2254a5787852c401962",
          "url": "https://github.com/kaappi/kaappi/commit/7bd728d4a102b667ef52b211e2c4e4a635749bb9"
        },
        "date": 1785463138959,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.243356,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.830061,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.583153,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.963405,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004711,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.04671,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.314667,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057662,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.66787,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.230955,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.589988,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.279296,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.797338,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.625157,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042974,
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
          "id": "9f1c323f402bd5265086faa059bd861df592c4c4",
          "message": "Say what R6RS rejected, instead of raising a bare type error (#1880)\n\n`define-record-type`'s R6RS clause syntax had two conditions that reported\n`error[KP3002]: type error` and nothing else -- no procedure, no expected\ntype, no value, the three things KP3002's own registry entry promises. Both\nreproduce in five lines: a sealed parent rtd, and a `nongenerative` uid\nalready bound to a non-equivalent type.\n\nNeither is a type error. Both arguments are of a perfectly good type and the\nprocedure rejects them anyway, which is what KP3007 (invalid-argument) is\nfor -- and R6RS's own wording for the first is \"an exception is raised if\nparent is sealed\", nothing about types.\n\nThe procedural half of the same two rules (`%make-record-type-descriptor`)\nhas been getting this right since #1868, so the fix is to stop stating the\nrule twice: `RtdShape`, `sealedParentError` and `reuseNongenerativeRtd` in\nprimitives_srfi237.zig now hold both the equivalence test and its wording,\nand the syntactic and procedural routes share them. Only the procedure name\ndiffers -- a caller who wrote `define-record-type` should not be told about\nthe internal primitive it desugars to. A uid collision now names the one axis\nthat actually differs rather than listing every axis it might have been.\n\nReading those two functions turned up a third condition of the same shape\nthat #1880's census could not see, because it is spelled as a `return switch`\narm rather than a bare return: more than 255 fields once a parent's are\ncounted. Its procedural half was the worse of the two -- a bare TypeError out\nof a primitive is not anonymous, `mapNativeError` fills the detail in from\n`args[0]`, so it confidently blamed the type's *name* for a limit the field\nlist broke.\n\nAlso folds `callFfi`'s four call sites into one `vm_calls.mapFfiError`. Two\nof them supplied a fallback message when callFfi returned without setting a\ndetail and two did not, and the two that did not are the hot ones. That is\nlatent today -- callFfi guarantees a detail on every path it can currently\nfail through -- but one shared mapper is cheaper than separate copies of the\nsame guard staying in sync. Worth knowing for anyone testing this: the four\nsites are *not* reached by direct call / apply / map, which all land in\nvm_calls.zig; the two vm_dispatch.zig sites are the tail-call and tail-apply\nopcodes, so the regression test uses tail-position forms.\n\nThe two remaining bare returns outside ffi.zig already call `setErrorDetail`\non the line above and are now annotated as such, leaving every non-FFI site\nin src/ either fixed or carrying a stated reason.\n\nNot done: ffi.zig's 27 sites (the issue's Group D), which are internal\npass/fail signalling behind `validateArgsDetailed` -- retagging them would\nchange nothing a user sees and would break the caller's switch. The\n`format` job's grep is unchanged; widening it is now a single question about\nthose 27 rather than a mixed bag.\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-31T08:52:21+05:30",
          "tree_id": "7ea2e112ab6fae5ee525bfdd6b07ff6533a21058",
          "url": "https://github.com/kaappi/kaappi/commit/9f1c323f402bd5265086faa059bd861df592c4c4"
        },
        "date": 1785470289832,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.300079,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.89231,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.580175,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.981307,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004642,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046457,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.311103,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057056,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.616138,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.232008,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.578073,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.280976,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.797544,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.486603,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.046708,
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
          "id": "3fbfc0a575efff60ad66152ef7b62e5b3e799268",
          "message": "Let a record's constructor be named `fields` or `parent` (#1882)\n\nSRFI 237's R6RS clause grammar is ambient — `(scheme base)`'s\n`define-record-type` accepts it with no `(import (srfi 237))` — so the two\nsyntaxes are told apart structurally. The detector inspected only the head\nof the form's 2nd element, which in R7RS syntax is the *constructor's*\nname, so `(define-record-type point (fields x y) point? (x point-x) (y\npoint-y))` was parsed as R6RS and rejected. Nothing in such a program\nsignals that the R6RS grammar is in play, and the diagnostic was a bare\nKP2001 whose follow-on `undefined variable 'fields'` pointed away from the\ncause.\n\nThe 3rd element separates the grammars unambiguously: R7RS always has one\nand it is always the bare-symbol `<predicate>`, while an R6RS `<record\nclause>` is always a list — or absent, when there is at most one clause.\nAdding that as a second condition is a pure narrowing, so every R6RS form\nkeeps its path and every malformed form keeps its diagnostic; only valid\nR7RS forms move.\n\nTwo paths beyond the top-level handler shared the misdetection. In a body\nit aborted the internal-define scan, so sibling `define`s written after\nthe record lost their mutual visibility. In a library body, where the R6RS\ngrammar is rejected outright as a documented top-level-only feature, the\nwhole library failed to load.\n\nTests: a compliance suite with a library fixture (18 assertions, 8 of them\nfailing before the fix) plus three unit tests — the R7RS one demonstrates\nthe fix, the R6RS-detection and malformed-form ones bound it.",
          "timestamp": "2026-07-31T11:20:10+05:30",
          "tree_id": "998eea705c31025c9b6744147610e7f0e8726ec9",
          "url": "https://github.com/kaappi/kaappi/commit/3fbfc0a575efff60ad66152ef7b62e5b3e799268"
        },
        "date": 1785479085311,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.055786,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.203136,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.43785,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.215485,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.003795,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.034516,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.231392,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.042579,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 1.774703,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.917524,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.175114,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.237565,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.312865,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.381513,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.035481,
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
          "id": "40f04a6db595e198ccd8008a513184ab9ddd798a",
          "message": "Release v0.22.1\n\nBug fixes and diagnostics. Three native-backend correctness fixes: an\ninternal define in a `let` body was never GC-rooted (#1854), the procedure\nshorthand `(define (f ...) ...)` compiled to a global define (#1861), and a\nnested `let` falling back to the interpreter lost the enclosing scope\n(#1862). Plus the `(srfi 120)` Windows wedge (#1870) and a library body that\ncould not reference an unimported global from its own top level (#1860).\n\nThe user-visible surface change is #1856: `(scheme base)` no longer exports\n22 `%`-prefixed internal primitives, so a user library defining its own\n`%name` loads again under v0.22.0's R7RS 5.2 enforcement. The ones portable\n`.sld` files need move to a new `(kaappi primitives)`.\n\nDiagnostics: every type error now names the expected type and the right\nargument (#1868), an uninitialized runtime reports KP9001 instead of a\ncaller type error (#1874/#1876/#1878), and two R6RS record conditions\nreport KP3007 rather than a bare KP3002 (#1880).\n\nBuilt-in procedures 690 -> 689 (`%length` deleted). The count command in\nthe release skill was undercounting by 2 -- it greps only for literal\n`.name = \"...\"`, and two entries converted to named constants this cycle --\nso it now resolves those too.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-31T11:50:24+05:30",
          "tree_id": "dc5bbbf2a11807643f675b30b34648ed25440706",
          "url": "https://github.com/kaappi/kaappi/commit/40f04a6db595e198ccd8008a513184ab9ddd798a"
        },
        "date": 1785482014724,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.3059,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.582863,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.571659,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.978246,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004648,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046357,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.310691,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057033,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.602668,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.231199,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.572815,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.278719,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.800123,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.620418,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043836,
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
          "id": "261fde5fad3c3d65cda83fdd507ce5d14cee729a",
          "message": "Gate publishing on CI, and ask for a changelog entry while it is cheap (#1885)\n\nv0.22.1 went public at 06:35:24 with ci.yml still running on the same\ncommit, and would have published identically had CI failed. The tag push\nand the branch push start release.yml and ci.yml as two independent runs\nwith nothing between them, so they race and publishing wins. The only\nthing that actually gated that release was a local test run.\n\nA new `ci-gate` job polls for the ci.yml run on the tagged SHA and only\nthe `release` job depends on it, so the 14 platform builds still run in\nparallel with CI -- gating costs no wall clock unless CI is the long pole.\nAbsence of a run is retried rather than treated as failure, since a tag\npushed alongside its branch can beat its own CI run into existence; a\nconcluded-but-not-successful run (including `cancelled`) refuses to\npublish. The workflow gains `actions: read`, without which the poll would\n403 -- declaring any `permissions:` block zeroes every scope not listed.\n\nThe changelog half addresses a different recurring miss: `[Unreleased]` is\nreconstructed from `git log` at release time rather than written as the\nwork lands, and had 14 of 100 commits at v0.22.0 and 5 of 16 at v0.22.1.\nA PR touching src/ or lib/srfi/ without touching CHANGELOG.md now fails,\nwith a `no-changelog` label for changes that are genuinely not\nuser-visible. Labels are read live via the API rather than from\ngithub.event, because re-running a job replays the original event payload\n-- a label added in response to the failure would otherwise be invisible\nto the re-run, making the documented escape hatch a dead end.\n\nAlso corrects two things the v0.22.1 run surfaced in the release skill:\nthe build-target list said 12 where the matrix ships 14 (s390x and\nppc64le were missing, both present in the released assets), and the\nNetBSD denormal probe imported (srfi 144), which needs ~/.kaappi/lib and\nso fails on a fresh VM as `undefined variable 'fl-least'` -- reading as a\ndenormal regression on the one platform whose FPCR fix it guards. The\nlibrary-free `5e-324` spelling tests the same thing with no import.\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-31T13:08:23+05:30",
          "tree_id": "b2a7bbed1d42d32efd3baa3a2e7685fb4d8c6579",
          "url": "https://github.com/kaappi/kaappi/commit/261fde5fad3c3d65cda83fdd507ce5d14cee729a"
        },
        "date": 1785485901359,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.318459,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.998063,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.582215,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.982443,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004751,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046463,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.311828,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057339,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.604341,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.231106,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.580214,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.278186,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.797204,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.626622,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044503,
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
          "id": "12588782c29762552483fa03b64786a3232e731b",
          "message": "Rewrite the audit strategy for a codebase that now has fuzzers (#1889)\n\nThe v1 campaign (#1137) closed on 2026-07-05 and its document still\ndescribes what it audited: ~39k lines, 578 procedures, 21 primitives\nfiles, 72 SRFIs. Since its base commit that is 417 commits and +67k\nlines ago. 132 of 162 .sld files and 166 of 200 SRFI tests postdate it,\nso for most of the tree a second campaign is a first audit, not a\nre-audit — and ten primitives files have no audit test at all.\n\nTwo things change the shape of the work rather than just its size.\n\nThe project now runs nightly differential fuzzing with three oracles\n(opt-vs-no-opt, VM-vs-native, Kaappi-vs-Chibi). v1 predates all of it,\nso v2 is scoped explicitly as the complement: fuzzers own crashes and\ntier divergence inside a generated subset, the audit owns breadth and\nanything whose oracle is a document rather than the implementation's\nother half. Without that split the obvious next campaign would spend\nits budget rebuilding harnesses that already run every night.\n\nAnd a large fraction of the remaining work is documentation truth, not\ntesting. Five of the six expander limitations CLAUDE.md lists as open\nare fixed; the eval_fallback_form_names hazard it warns about has\nmigrated to a different, still hand-maintained list; the SRFI 58/163\nexclusions rest on two statements that are now false. An auditor\ntrusting the docs today loses sessions to bugs fixed months ago, which\nis why the truth pass is Phase 0 and not an afterthought.\n\nA seven-agent reconnaissance pass fed the rewrite and is recorded in\nit: 13 reproduced findings against a fully green suite (624/624 Scheme\nfiles, 1395/1395 R7RS assertions). That gap is the campaign's\njustification — the suite is green because it does not ask these\nquestions, not because the answers are right.\n\nThe audit-primitives skill is updated in the same commit because every\nPhase 2 session loads it and it had drifted onto the old\n`try reg(vm, ...)` registration and a 18-of-31 file list.\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-31T15:02:02+05:30",
          "tree_id": "6cb49d8cb3805204fa855918b2bda28f91a115f7",
          "url": "https://github.com/kaappi/kaappi/commit/12588782c29762552483fa03b64786a3232e731b"
        },
        "date": 1785493530297,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.935647,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.864529,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.562005,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.832828,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004842,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.044575,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.293627,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.054868,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.284727,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.158065,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.511626,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.301755,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.68899,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.783272,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.046638,
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
          "id": "c6040f1802c2e54b7068a0d632a36bb99cfedbb4",
          "message": "Tick Phase 0A and point the tracker at the filed issues (#1904)\n\nThe document calls its progress tracker the single source of truth for\nwhat is done, so leaving 0A unticked after running it contradicts the\nrule the campaign is meant to enforce — the first session to read it\nwould have re-run the baseline and re-filed thirteen issues.\n\nRecords the green baseline, the tracking issue, and the twelve issue\nnumbers. Also notes that reproducing F12 before filing corrected it: a\nflat cdr-cycle prints its label correctly, and only a car-nested cycle\npast the depth limit loses one. The reconnaissance table keeps the\nrepro recipes, since those are what a fixer needs and the issues\nduplicate rather than replace them.\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-31T15:42:35+05:30",
          "tree_id": "4d609c6de114ec2e3a4175b0615a4302f7baae5e",
          "url": "https://github.com/kaappi/kaappi/commit/c6040f1802c2e54b7068a0d632a36bb99cfedbb4"
        },
        "date": 1785500102341,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.942564,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.072483,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.560011,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.844202,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.0049,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.044633,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.293514,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.054836,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.29169,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.157576,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.519576,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.299184,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.685114,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.732877,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044263,
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
          "id": "6d621fc7f3afe0e9bf713c9810475bf35758014c",
          "message": "Correct six documentation claims that no longer describe the code (#1905)\n\nPhase 0B of the v2 audit campaign (#1901). Every claim was re-verified\nagainst v0.22.1 before being edited, which matters more than usual here:\nthe point of the pass is to stop propagating unverified statements, so\ntaking the reconnaissance report on faith would have reproduced the\nfailure mode it was meant to fix. Two findings changed under that check.\n\nThe native-backend warning was aimed at the wrong list.\neval_fallback_form_names is comptime-derived and self-maintaining; the\nhand-maintained array that can actually cause a silent miscompilation is\nisRejectedFormHead, which is already missing define-property (#1896).\nAnyone adding a form was being pointed at the safe list.\n\nSRFI 148 was recorded as 134 passing with 8 test-expect-fail. It is 142\npassing with none. The reconnaissance also called the test file's header\ncitations dead comments; reading it showed the opposite — the header\ndocuments both fixes accurately and is worth keeping, so the note now\nsays to read it rather than distrust it. Repo-wide there are 6\ntest-expect-fail calls, 4 of them in srfi150.scm, which matches that\nfile's reported count exactly and disproves the claim that two never\nexecute.\n\nThree limitations documented as open are fixed: the let-syntax chain\nproducing define-syntax, library-body shadowing of define-record-type,\nand (already noted elsewhere) the ellipsis leniency. The shadowing note\nnow records the trap that made it look broken — bind a name from the\nmacro's pattern, not one introduced by its template, or hygiene renames\nit and the test fails for an unrelated reason.\n\nThe SRFI 120 corruption claim does not reproduce. Both documented entry\npaths now fail cleanly and deterministically across 10 runs, because a\n<timer> holds a Fiber that gc_deep_copy rejects outright, so the\nsingle-thread constraint is engine-enforced rather than a hazard to\ndesign around. The re-check's limits (macOS, ReleaseSafe, no gc-stress)\nare recorded alongside it — stale claim, not proof the bug never existed.\n\nThe SRFI 58 and 163 exclusions rested on \"SRFI 160 has no implementation\nat all\" and \"SRFI 4 is a purely portable wrapper\". Both are false now, so\neach entry drops to a single reader-ambiguity blocker and both SRFIs\nbecome re-considerable.\n\nFinally, tests/scheme/CLAUDE.md's directory table was missing six suites\nthat exist and run, and said nothing about run-all.sh's globs being\nnon-recursive — the reason tests/scheme/srfi/slow/ has never run (#1900).\nThat stale table is what sent a reconnaissance agent chasing a\n\"tests exist but never run\" headline that turned out to be false.\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-31T15:45:08+05:30",
          "tree_id": "59aac2a19d1c488ca2527790782f66af787d2428",
          "url": "https://github.com/kaappi/kaappi/commit/6d621fc7f3afe0e9bf713c9810475bf35758014c"
        },
        "date": 1785504205910,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.388724,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.202274,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.597258,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.048954,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004692,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.047007,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.318063,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.059108,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.624791,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.251477,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.612267,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.29035,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.821671,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.624745,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.047755,
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
          "id": "61f6e8c48003b4674677737513f975a7eed71233",
          "message": "Phase 2.1: internal-primitive audit — 239 assertions over a 51-procedure surface with no prior tests (#1918)\n\n* Audit the %-prefixed internal-primitive surface (audit v2, Phase 2.1)\n\nEvery registered primitive spec lands in vm.globals regardless of its\n`libs` tag -- only *export* is gated -- so all 60 `%`-prefixed specs in a\ndefault build are callable from a plain top-level script with no import\nat all. 51 of them are reachable that way today; the other 9 are the\npurged `internal_helpers` (8) plus the instrument-only build hooks.\nBetween them they had close to zero mention anywhere in tests/.\n\n239 assertions across the record substrate (R7RS and R6RS/SRFI 237),\nSRFI 160 numeric vectors, SRFI 271 random ports, SRFI 181 transcoded\nports, SRFI 248 unwind handlers, the parameter internals, the SRFI 27\nsubstrate, and the sysinfo probes. Each procedure is probed for arity at\nboth bounds, wrong types in *each* argument position independently, and\nboundary values (negative and just-past-the-limit indices, empty inputs,\nper-kind numeric range ends).\n\nDiscovery only -- no source is changed. 14 assertions are commented out\nbehind `;; FAIL: TBD` markers covering seven distinct defects, each\npaired with an enabled discriminating control that proves the failure is\nspecific rather than a whole-codebase convention. The three cross-tier\nassertions marked \"(fails on wasm32)\" pass natively and fail under\nwasmtime, pinning an index-truncation divergence.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Point Phase 2.1 FAIL markers at the filed issues\n\nCommitted with placeholders before the issues existed; each now names the\nissue whose fix re-enables it.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-31T16:08:10+05:30",
          "tree_id": "9d84885761abdb3c4ab8d665babb6ddece93b148",
          "url": "https://github.com/kaappi/kaappi/commit/61f6e8c48003b4674677737513f975a7eed71233"
        },
        "date": 1785505306939,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.944945,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.379032,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.564248,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.844358,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004882,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.0445,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.293462,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.054817,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.309844,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.158526,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.513685,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.30613,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.697198,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.803746,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.046008,
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
          "id": "1c3dec04c7ed3571f4a526d2c0fdca6d104abd96",
          "message": "Run the test suites in parallel, and stop sleeping through them (#1887)\n\n* Run the test suites in parallel, and stop sleeping through them\n\n`bash tests/scheme/run-all.sh` took 17.8 min on a 4-core box to do about\n90s of actual work. Two independent causes, fixed here.\n\n**The poll interval.** `wait_with_timeout` polled a spawned child with\n`sleep 1`, so every one of the ~620 spawned units cost a full second of\nwall clock no matter how fast it really was — and 381 of the 566 .scm\nfiles finish in under 50ms. That single sleep was ~93% of the script's\nruntime. The tick is now 0.05s, counted in 20ths of a second so the\ntimeout keeps its exact meaning, with an integer fallback if a platform's\n`sleep` rejects fractions.\n\n**No parallelism.** Each .scm file is already a fresh interpreter with no\nshared state, so `run_suite` now dispatches KAAPPI_TEST_JOBS at a time\n(default: one per CPU; 1 restores strictly-sequential). Workers write\ntheir verdict to a slot and the parent tallies and prints afterwards in\nglob-sorted order, so output ordering and the counters are unchanged. An\naudit of the corpus found no cross-file collisions on fixed paths or\nports before turning this on.\n\nShell suites stay sequential: several call `ensure_runtime_lib`, which\nruns `zig build lib` into the shared zig-out/lib, so concurrent scripts\nwould race over one output archive. They are now the larger half of the\nremaining wall time.\n\n`kaappi test` gets the same treatment via `-j`/`--jobs`, which its own\ndocs already anticipated. Worker threads claim files from an atomic\ncounter while the main thread reports the completed prefix in file order,\nso verdicts and output ordering are identical at any job count. The emit\npath now travels in the child's own envp: setenv on the parent before\neach fork is a single mutable global shared by every in-flight worker,\nand two concurrent spawns would have sent both children to the same path\nand lost a result. Windows stays at one job, where that env is still\ninherited from the parent.\n\nMeasured on 4 cores, all three producing identical results\n(2019 pass, 0 fail):\n\n    run-all.sh, before                1070s\n    run-all.sh, KAAPPI_TEST_JOBS=1     425s   2.5x\n    run-all.sh, default (4 jobs)       279s   3.8x\n    kaappi test tests/scheme/srfi     18.5s -> 4.6s   4.0x\n\ntests/scheme/test-runner/jobs.sh pins the parity down by diffing whole\ntranscripts between --jobs 1 and --jobs 4, including a deliberately\nslow-first fixture so a reporter that emitted in completion order would\nfail even though its totals stayed correct.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\nClaude-Session: https://claude.ai/code/session_01Qk6ip9ctt9dJANetqdwDMm\n\n* Address review: validate KAAPPI_TEST_JOBS, cover resolveJobs, sharpen docs\n\nThree findings from CodeRabbit on #1887, all valid.\n\n`KAAPPI_TEST_JOBS` was never validated — only `detect_jobs`'s own output\nwas. `[[ $running -ge $JOBS ]]` evaluates its operands arithmetically, so\na non-numeric value is silently 0: `KAAPPI_TEST_JOBS=abc` did not fail,\nit quietly serialised the run with a spurious `wait` per file, and still\nreported success. A typo in a CI env var should not cost a 4x-slower\nsuite that looks fine. Bad values now exit 2 with the offending value\nnamed. `0` is rejected in `detect_jobs` too, where it would have been\npassed through as a valid count.\n\n`resolveJobs` is pure and encodes the platform policy the rest of the\nfeature rests on, so it gets direct unit coverage: zero and one file,\na request above the file count, an explicit `--jobs 1`, and auto —\nwith the Windows and single-threaded expectations gated on the same\ncomptime conditions the function itself uses.\n\nThe `--jobs` doc claimed output is identical at any job count without\nnoting that durations obviously are not; it now says the test normalises\nthe `…ms` fields and then requires a byte-for-byte match, which is what\njobs.sh actually does.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\nClaude-Session: https://claude.ai/code/session_01Qk6ip9ctt9dJANetqdwDMm\n\n* Add the CHANGELOG entry the `changelog` CI job requires\n\nThe PR touches src/, and `kaappi test --jobs` is a new user-facing flag,\nso this is a real entry rather than the `no-changelog` escape hatch.\n\nRecords the flag itself and, under Fixed, the emit-path race it required\nclosing — worth stating separately because it was a latent correctness\nbug in shipped code, even though nothing could reach it while spawns\nwere serialised.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\nClaude-Session: https://claude.ai/code/session_01Qk6ip9ctt9dJANetqdwDMm\n\n---------\n\nCo-authored-by: Claude <noreply@anthropic.com>",
          "timestamp": "2026-07-31T16:19:37+05:30",
          "tree_id": "9a209b851b025a51669a094eae25d72bc844b930",
          "url": "https://github.com/kaappi/kaappi/commit/1c3dec04c7ed3571f4a526d2c0fdca6d104abd96"
        },
        "date": 1785506313723,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.346949,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.970683,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.590433,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.982932,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004741,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.047208,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.318695,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.05739,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.661153,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.231094,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.616613,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.284512,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.79793,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.611677,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044051,
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
          "id": "2903f3532d14576629b5dcd949643a81aea2371d",
          "message": "Phase 1A: reader exactness audit — 128 assertions, 5 new bugs including a process-abort panic (#1917)\n\n* Add Phase 1A reader-exactness audit tests\n\nAudit v2 Phase 1A: `#e`/`#i` over the i64 boundary and reader vs\n`string->number` parity, against R7RS 6.2.5, 6.2.7 and 7.1.1.\n\n128 assertions pass; 39 are commented out with `;; FAIL:` markers — 7 for\nthe known #1891 and 32 for six findings this pass reproduced. Every\ndisabled group keeps an enabled discriminating control beside it, so the\nfile still proves the neighbouring path works.\n\nThe findings share one cause: `applyExactness` exists twice, in\n`reader_tokens.zig` and `primitives_numeric.zig`, with different\nstrategies. `string->number` rebuilds the value exactly from the decimal\ndigits; the reader parses to f64 first and then tries to un-round it with\na tolerance-based continued fraction, so it loses at both ends of the\nrange. Past fixes (#79, #419, #604, #751) each landed in one copy only.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Point Phase 1A FAIL markers at the filed issues\n\nThe disabled assertions were committed with placeholder markers before the\nissues existed. Each now names the issue whose fix re-enables it.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Address review: declare (scheme inexact), unpin a non-conforming control\n\nTwo review findings on #1917, both valid, though the first for a different\nreason than stated.\n\nfinite?/infinite?/nan? are registered to (scheme inexact), so the import\nbelongs there. The claim that omitting it made the file fail was wrong --\nit ran 128 assertions green, because a top-level script reaches vm.globals\ndirectly whether or not the import is declared. That ambient reachability\nis exactly what kaappi#1831 documents, and relying on it in a test would\nhave made the file pass here while the same code failed inside a library\nbody. Declared explicitly.\n\nThe second finding was right outright, and investigating it found a bug the\ncontrol was hiding. Asserting (not (string->number ...)) pinned #f as the\ncorrect answer for a valid R7RS numeric string, so fixing string->number\nwould have looked like a regression. Rewritten to assert only the non-crash\nproperty. Probing why it returned #f showed the UNPREFIXED spelling of 2^63\nfails too, with the reader parsing it correctly -- the opposite parity from\nevery other divergence in this file. Filed as #1921 with four enabled\ncontrols and one disabled assertion.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-31T18:38:54+05:30",
          "tree_id": "86756ff19d7512557562d4326426a804332b910b",
          "url": "https://github.com/kaappi/kaappi/commit/2903f3532d14576629b5dcd949643a81aea2371d"
        },
        "date": 1785506432457,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.352054,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.889947,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.582048,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.028709,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004766,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.047001,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.31841,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057403,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.647567,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.23114,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.614311,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.281133,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.812327,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.63892,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044207,
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
          "id": "3dbd0b5bcdcca2f412e0a75e7d67556e74f082b3",
          "message": "Make (srfi 14) a character set, not a multiset that stops at z (#1895) (#1928)\n\nThe library was three defects at once, and the third made the first two\nworse: `(char-set #\\a #\\a #\\b)` kept the duplicate, `char-set:full` was\ncode points 0-127 so `#\\λ` was not in it, and 23 of the SRFI's 64 names\nwere exported -- while `(cond-expand (srfi-14 ...))` answered yes, so\nportable code was told the library was there and then handed a multiset.\n\nA char set is now an inversion list: a sorted, disjoint, non-adjacent list\nof `(lo . hi)` code-point pairs. That is what makes it a set structurally\nrather than by filtering -- duplicates cannot be represented -- and what\nmakes `char-set:full` and `char-set-complement` two pairs instead of 1.1\nmillion list cells. `equal?` on two canonical range lists decides\n`char-set=` outright, which `char-set-hash` then rides on. All 64 spec\nnames are implemented; none is omitted.\n\nThe standard `char-set:*` constants come from generated Unicode general-\ncategory tables rather than from a scan over `(scheme char)`'s predicates.\nScanning was the obvious approach and two things ruled it out. It costs\n~0.14s per predicate, which is too much at every import; and making it\nlazy and memoised is unsafe in this engine, not merely inelegant. Globals\nare shared between SRFI-18 threads by pointer while heaps are per-thread,\nso a child thread forcing a memo writes a child-heap value into a\nparent-heap record, and the parent reads freed memory after the join.\nThat reproduces with no char sets involved -- a record box, `set!` from a\nchild, read from the main thread -- and a field holding a fixnum survives\nwhere one holding a fresh pair does not. So nothing here is ever mutated\nafter construction, and the tests pin that a constant read first from a\nchild thread is still sound in the parent.\n\nDeriving from categories is also what the SRFI asks for, but it means two\nvisible disagreements with `(scheme char)`, both intentional and both\ntested: `char-set:letter` is L* while `char-alphabetic?` answers for the\nbroader Alphabetic property, and `char-set:digit` is all 680 of Nd while\n`char-numeric?`'s hand-written 36-entry table covers only the 370 in the\nBMP. Each predicate is right for its own spec except the last, which is a\nseparate bug in `isUnicodeNumeric`.\n\nThe suite is written against the spec rather than the implementation: on\nthe pre-#1895 library it reports 17 passes and 144 failures. Beyond the\nspec's own worked examples it property-checks every range operation\nagainst a brute-force list-of-code-points model over a 121-character\nalphabet, which is what catches the overlap and adjacency cases hand-\nwritten tests reach only by luck -- four of five seeded mutations in the\nrange algebra are caught, the fifth being an equivalent mutant.\n\n`tools/gen_srfi115_charsets.py` becomes `tools/gen_srfi_charsets.py` with\na `--target {115,14}` selector, since it now feeds both libraries.\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-31T18:38:58+05:30",
          "tree_id": "c194d0a1470722fc624ecafce71616e0468a0922",
          "url": "https://github.com/kaappi/kaappi/commit/3dbd0b5bcdcca2f412e0a75e7d67556e74f082b3"
        },
        "date": 1785507139505,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.962166,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.328717,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.559231,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.835603,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00494,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.044587,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.29722,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.055244,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.298687,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.158115,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.510861,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.298699,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.690756,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.763706,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044462,
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
          "id": "8cb776be89da98a9c82728d0f93c01d5e8eeffe5",
          "message": "Phase 1C: port refill sweep — 1714 configurations, a silent-split class, and a correction to #1893 (#1946)\n\n* Pin the reader's port-refill boundary with a token x offset sweep\n\n`(read port)` on an fd-backed port reads 4096-byte chunks and re-parses\nthe accumulated buffer after each one, treating only\n`ReadError.UnexpectedEof` as \"incomplete, read more\". A token straddling\na chunk boundary therefore survives only if its scanner happens to\nreport truncation with that exact error.\n\nSweeping 26 token kinds against every interior split point at both the\n4096 and 8192 boundaries -- against a string-port oracle over the same\nbytes, which cannot refill -- shows 12 kinds that do not, in two modes:\na hard `KP3000: read error` (strings, raw strings, `#u8\"...\"`, `#u8(`,\n`|sym\\x41;|`, and a multi-byte UTF-8 codepoint split anywhere, even\ninside a list) and a silent truncation with no error at all (bare\nsymbols, numbers, `#\\space`, `#\\x41`, `#true`, and line comments, whose\nremaining body is then read as program data).\n\nThe passing kinds are enabled and swept; the failing ones are commented\nout with a `;; FAIL:` marker. Fixtures are generated at run time and\ndeleted, so no 4 KB blobs are committed.\n\nWorth recording: #1893's own stated discriminating control -- \"the same\nfile with a bare symbol payload reads all 1024 datums\" -- does not hold.\nThe symbol only survived because it was wrapped in a list, which does\nrefill, and because the check counted datums instead of comparing them.\nAt top level the same symbol splits in two, silently.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Point port-refill FAIL markers at the filed issues\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-31T18:42:38+05:30",
          "tree_id": "14d1054f4c209b7d0452ed420c561133b5d348ef",
          "url": "https://github.com/kaappi/kaappi/commit/8cb776be89da98a9c82728d0f93c01d5e8eeffe5"
        },
        "date": 1785508159081,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.354779,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.93978,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.583787,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.979059,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004746,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.047034,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.318927,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057266,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.62904,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.234423,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.605772,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.28174,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.803356,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.649718,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043638,
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
          "id": "5dcf4e3776e00eae9b64a70f3cc550d528aa5646",
          "message": "Phase 4B: differential harness for the opt-off and cache tiers — 557 files, one real divergence (#1923)\n\n* Turn the execution-tier differential into a repeatable gate\n\nThe reconnaissance pass ran tiers (b) `--no-ir-opt` and (d) cold-vs-warm\n`.sbc` cache once, across 333 files, and found nothing. A one-off green\nrun is not a gate, and — for tier (b) — it was not even much of a\nnegative: only 3 of the 550 pre-existing corpus files make the IR\noptimiser do anything at all, because every `define`/`lambda` body lowers\nto an opaque `passthrough` node and the five passes only ever reach\ntop-level expression position. The other 547 compile identically with the\noptimiser off, so the comparison was vacuous for 99.5% of the corpus.\n\nSo the harness does three things the one-off sweep did not.\n\nIt measures its own vacuity. The summary reports how many files change IR\nunder `--no-ir-opt` and how many populated the bytecode cache (40 of 330\nby default; a program that imports is never cached), so a regression that\nsilently disables either shows up as a count collapsing rather than as a\nstill-green run.\n\nIt ships probes that the passes actually reach. `probes/` puts foldable,\ndead-branch, `not`-rewrite, identity and nested-`begin` shapes at top\nlevel, where the passes live, and leans on the cases where the rewrite is\nonly conditionally sound: `(if 0 ...)` is true in Scheme, `(* 1.5 0)` is\nnot `1.5`, and a shadowed `+`/`*`/`not` must suppress the rewrite\nentirely. Six of the seven are verified non-vacuous, tripling the number\nof corpus files that exercise the optimiser.\n\nIt decides nondeterminism by measurement instead of by a guessed skip\nlist. A tier mismatch has to survive three controls before it is\nreported: the file must actually be cached (otherwise cold and warm are\nthe same configuration, so a tier-(d) mismatch cannot be a cache effect),\ntwo cold baselines must agree, and the divergence must reproduce. The\nfirst control is what distinguishes a real finding from\n`nested-wait-under-sleep-dirty-snapshot-1490.scm`, which hung once under\nload and read as a cache divergence until the check was added. The static\nskip list is consequently empty.\n\nOne real divergence, found by the probes and suppressed via KNOWN_DIFFS\nso the suite stays green: on a cache HIT a runtime error loses its source\nline and snippet whenever the location comes from `Function.source_line`\nrather than the line table, because `vmErrorLocation`'s `fallback_line`\nis a hardcoded 0 on the cache-HIT path where the fresh-compile path\npasses the top-level datum's line. Exit code and stdout agree; only the\ndiagnostic degrades. `probes/cache-error-location.scm` carries the repro\nand its control side by side — `vector-ref` out of range, located by the\nline table, prints identically in both runs.\n\nUnlike the `;; FAIL: #1234` convention, that suppression cannot rot\nquietly: when a listed entry stops diverging the summary says so and asks\nfor it to be deleted. It is a note rather than a failure, because a gate\nthat goes red the moment someone fixes a bug teaches people to distrust\nit.\n\nWired into run-all.sh over the smoke+compliance+audit corpus plus the\nprobes: 330 files, 116s, inside the 300s shell-suite budget.\n`KAAPPI_DIFF_FULL=1` adds continuations/, hygiene/ and srfi/ — 557 files,\n210s — and is opt-in rather than the default because the extra 227 files\nbuy no additional tier coverage: zero of them change the IR, and they add\nseven cached files.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Point the known cache divergence at kaappi#1922\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Reduce the differential corpus to probes/ on a Debug build\n\nCI's Debug leg killed the suite at run-all.sh's 300s SHELL_TIMEOUT. Debug\nruns the whole pipeline unoptimised and is ~500x slower on allocation-heavy\nwork, and the harness is ~1000 interpreter invocations, so the same sweep\nthat takes 110s on ReleaseSafe does not finish.\n\nReducing to probes/ rather than skipping the suite or raising the budget,\nbecause the census the harness itself reports says probes/ is where the\nsignal is: 9 of 331 corpus files make the optimiser do anything and 6 of\nthose 9 are the probes. Debug now runs 7 files in 15s and still covers 6 of\nthe 9 discriminating ones, so what it drops is the part that was vacuous by\nconstruction.\n\nDetected from {\"version\":\"0.22.0\",\"build_id\":\"ca18ae6\",\"target\":\"aarch64-macos-none\",\"build_mode\":\"ReleaseSafe\",\"gc_stress\":false,\"sandbox_available\":true,\"features\":[\"r7rs\",\"kaappi\",\"ieee-float\",\"exact-closed\",\"exact-complex\",\"kaappi-fibers\",\"kaappi-reactor\",\"kaappi-diagnostics\",\"posix\",\"kaappi-threads\"],\"srfis\":{\"builtin\":[1,9,13,18,39,69,133,170,192,254,258,260],\"portable\":[0,2,4,5,6,7,8,11,14,16,17,19,23,25,26,27,28,29,30,31,34,35,36,37,38,41,42,43,44,45,46,48,51,54,57,59,60,61,62,63,64,66,67,70,71,74,78,86,87,90,94,95,98,101,111,112,113,115,116,117,118,120,123,125,126,127,128,129,130,131,132,134,135,136,137,139,140,141,143,144,145,146,147,148,149,150,151,152,153,156,158,161,162,164,165,166,167,168,169,171,173,174,175,178,180,181,185,188,189,190,193,194,195,196,197,201,202,203,207,209,210,213,214,215,216,217,219,221,222,223,224,225,227,228,229,231,232,233,234,235,236,237,238,239,240,241,242,244,247,248,250,251,252,253,255,257,259,263,264,267,270,271]},\"limits\":{\"initial_frame_capacity\":480,\"initial_register_capacity\":2048,\"gc_initial_threshold\":8192}} rather than an env var, so it is\nright whether the build came from CI, a local -Doptimize=Debug, or a stale\nzig-out. KAAPPI_DIFF_FULL=1 still forces the whole corpus.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-31T19:39:36+05:30",
          "tree_id": "8976b3f277bc70b7a9d4ba341d32f72610c96978",
          "url": "https://github.com/kaappi/kaappi/commit/5dcf4e3776e00eae9b64a70f3cc550d528aa5646"
        },
        "date": 1785509657923,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.973515,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.444874,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.566195,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.842375,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004866,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.044536,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.297518,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.055164,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.305599,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.158962,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.507275,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.302923,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.833881,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.777322,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044957,
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
          "id": "cbbf0f94087cbaa7a6d1055f2cbb12fec58bff12",
          "message": "Phase 1B: delimiter sweep — 494 cells, 382 splits, and a guard that has never executed (#1931)\n\n* Sweep trailing-delimiter checking across every numeric prefix\n\nR7RS 7.1.1 requires a number to end at a <delimiter> or end of input.\n`Reader.readNumber` (src/reader.zig:366) enforces that, but only for\nun-prefixed decimals: `readNumberPrefixed` (src/reader_tokens.zig:481)\ncalls the unguarded `reader_tokens.*` functions directly, so any `#`\nprefix at all disables the check and one token silently reads as two\ndatums.\n\nThe systematic 19x26 sweep (19 prefix spellings x 26 trailing characters)\nsplits 382 of 494 cells; all 26 un-prefixed cells are correct, which is\nthe control axis. `string->number` rejects every failing cell, so each\ndisabled assertion is paired with an enabled oracle assertion. Chibi 0.12\nand Guile 3 raise on all of them too.\n\n148 assertions pass; 58 are disabled (55 under #1892, 3 under TBD for two\nnon-delimiter reader/string->number divergences the same sweep surfaced).\nThe enabled groups also pin the syntax a fix must not regress: SRFI 270\nhex floats, SRFI 169 digit separators, rationals, complex tails, and hex\n`e`/`d` as digits rather than exponent markers.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Point delimiter FAIL markers at #1929\n\n#1892 reported the radix-prefix case; the sweep showed one bypassed call\nsite produces all 382 failing cells across every prefix spelling, so the\nmarkers name the wider issue that a fix will actually close.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-31T19:40:15+05:30",
          "tree_id": "f355651720339ada74bc4939f6ba72a5663ff21d",
          "url": "https://github.com/kaappi/kaappi/commit/cbbf0f94087cbaa7a6d1055f2cbb12fec58bff12"
        },
        "date": 1785509664474,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.358727,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.57382,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.5796,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.009405,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004694,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.047051,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.319169,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057043,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.636414,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.230923,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.61636,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.276379,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.804693,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.58907,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042981,
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
          "id": "c5ddfe48acfbf8af321b798530fc53b24821b4bb",
          "message": "Phase 5C: cross-thread boundary audit — 49 assertions, six new findings including a read-direction UAF (#1938)\n\n* Map the cross-thread heap boundary, and pin the half of it that works\n\nPhase 5C of the v2 audit campaign. #1924 established that a child thread\nmutating a heap object reachable from a top-level binding leaves the parent\nreading freed memory. This maps how far that reaches, and — as importantly —\nwhere the boundary is actually sound, so those parts need not be re-audited.\n\n49 enabled assertions pin the working boundary: immediates (fixnum, char,\nboolean, flonum) survive every container; raw-byte content does too\n(string-set! including the widening rebuild, string-copy!, bytevector and\nf64vector elements); interned symbols survive because a child stamps them\nwith the parent's GC id; a child may store a parent-heap value into a\nparent-heap object and keep eq?; a child may grow a parent hash table across\na rehash; parameters are per-thread; a mutex left locked by a dead child\nreads as abandoned; join deep-copies results, nested objects included; and\nall seven reachable uncopyable tags are refused in both directions.\n\n24 assertions are commented out behind `;; FAIL:` markers rather than\ntest-expect-fail, because reading freed memory can take down the runner.\nSeventeen are #1924's shape across every mutable heap type — including the\nshared globals map itself and promise memoisation, which its own matrix\ndoes not cover. Seven are new and are marked TBD:\n\n  * the read direction, which #1924 does not cover: the parent's collector\n    reclaims an object a LIVE child still references, since markVMRoots\n    returns early unless vm.gc == gc. Under -Dgc-stress=true this escalates\n    to the engine's own UAF panic, 3/3, with the no-drop control clean 3/3.\n  * a plain R7RS record returned through thread-join! arrives as a\n    DIFFERENT record type: pt? answers #f and every accessor raises. The\n    supported worker-thread path, no globals and no mutation involved. A\n    SRFI 237 nongenerative type is the control and is enabled — its uid\n    registry is the one identity-preserving path in gc_deep_copy.\n  * gc_deep_copy's .channel arm skips the ownership check for an\n    already-promoted channel, so a grandchild that only ever reached a\n    channel through a shared global gets a working stub. The unpromoted\n    control is enabled and refuses.\n  * symbol interning is one level deep: at thread depth >= 2 a grandchild's\n    string->symbol no longer dedupes against the process table.\n  * a continuation invoked cross-thread returns a value satisfying no type\n    predicate at all.\n\nCLAUDE.md's claim that top-level bindings are shared by pointer while\nlexical captures are deep-copied-and-re-owned is confirmed, and both halves\nare now asserted directly.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Point cross-thread FAIL markers at the filed issues\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-31T19:40:55+05:30",
          "tree_id": "4aa2be03e1a6302c71fd7fd1dfa0dfcaea17a740",
          "url": "https://github.com/kaappi/kaappi/commit/c5ddfe48acfbf8af321b798530fc53b24821b4bb"
        },
        "date": 1785510205407,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.335597,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.604451,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.450512,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.416965,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004082,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.034737,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.230712,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.042794,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 1.831192,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.896954,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.172455,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.237944,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.305979,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.440092,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.035719,
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
          "id": "912b1e6246e05b822fe3968f982e614c1b8fe19a",
          "message": "Phase 2.2: primitives_io audit — 49 → 197 assertions, all 45 specs covered, one process-abort panic (#1947)\n\n* Phase 2.2: cover the 1100 lines primitives_io.zig grew after its audit\n\nThe audit test for src/primitives_io.zig was written against a version of\nthat file that predates custom ports, transcoded ports, the write-buffering\nlayer, and SRFI 192 — 112 lines of assertions against 1941 lines of code.\nThis takes it to 197 passing assertions covering all 45 spec entries, and\nleaves 8 disabled assertions marking defects the coverage found.\n\nFour defects, each paired with an enabled discriminating control so the\nmarker says *because of what*, not just *that it fails*:\n\n- A custom-port read! that re-enters a read on its own port trips\n  std.debug.assert(port.read_buf == null) and ABORTS the process — the\n  single-slot read buffer assumes no re-entrancy. Reachable at two sites\n  (readOneByteFromCustomPort, readOneByteFromTranscodedPort). Control: the\n  same shape returning one byte per call never populates read_buf and\n  completes cleanly. Its non-aborting sibling silently reorders the byte\n  stream.\n- SRFI 192's string-port branch ignores the port's own peek-byte read-ahead,\n  which the fd branch corrects for: port-position over-reports by one after\n  a pushed-back byte, and set-port-position! does not discard the stale byte,\n  so a seek is followed by a read of data from the old position. Controls:\n  the identical cases on a file port are both right.\n- port-has-set-port-position!? is registered to the same function as\n  port-has-port-position?, so it answers about get-position instead of\n  set-position! — wrong in both directions for a custom port with only one\n  of the two. Controls: ports with both, and with neither, answer correctly.\n- flush-output-port on a transcoded port is a silent no-op; it has custom-\n  backend and buffered-fd branches but no transcode branch, and a transcoded\n  port carries the fd -1 sentinel. Controls: flushing the wrapped port works,\n  and close-port does cascade.\n\nConfirmed correct along the way: the 8 KiB high-water drain and its\nflush/close/read triggers, fd-port positions corrected for read-ahead and\nwrite-behind, the freshly-re-read UTF-8 byte-offset conversion after a\nwidth-changing string-set! inside read!, CRLF decode and encode, both\ndecoding error modes, close-port's flush-and-cascade discipline, the\nblocking-callback rejection, and gc_deep_copy's refusal to carry a port\nacross a thread boundary.\n\nFound by: systematic audit v2, Phase 2.2 (docs/audit-strategy.md).\nDiscovery only — no source changes.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Point primitives_io FAIL markers at the filed issues\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-31T19:41:33+05:30",
          "tree_id": "dcf0c4b87487858c011e4a12cc7ad5a6041cbef6",
          "url": "https://github.com/kaappi/kaappi/commit/912b1e6246e05b822fe3968f982e614c1b8fe19a"
        },
        "date": 1785511043172,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.945213,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.399424,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.56213,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.853622,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.005031,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.044442,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.297564,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.055146,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.299306,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.157885,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.510634,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.305477,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.695136,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.760242,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044976,
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
          "id": "6114398ba48db971cd17792170b82d92e3f439fd",
          "message": "Tick the eight units landed in the first two batches (#1948)\n\nThe tracker read 2 of 53 while eight units were merged, because each\nunit's PR added its test file without touching the tracker. The document\ncalls that tracker the single source of truth, so a stale one is the same\nfailure Phase 0B existed to fix: the next session to open it would have\nre-run work already done and re-filed issues already filed.\n\nEach entry records its PR and the issues it produced, so the tracker\nanswers what a unit found without needing eight PRs opened alongside it.\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-31T20:49:37+05:30",
          "tree_id": "3994183ec5106eb2bdac9eda445056deddab5073",
          "url": "https://github.com/kaappi/kaappi/commit/6114398ba48db971cd17792170b82d92e3f439fd"
        },
        "date": 1785512696769,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.352258,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.083364,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.59766,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.981369,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004997,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.047616,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.319096,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057249,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.645299,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.231968,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.619376,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.284556,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.815246,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.648532,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043738,
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
          "id": "93fa575717d4339d84e008953104d530adc3b622",
          "message": "Stop a VM limit from arriving as a catchable condition (#1919)\n\nA recursive procedure that wraps its own recursive call in `guard` is\nordinary code, and past 64 levels it was silently incorrect: it returned\na plausible wrong value and exited 0.\n\nThe exception-handler and dynamic-wind stacks were fixed 64-entry inline\narrays. `with-exception-handler` relabelled the overflow as OutOfMemory\nand then converted it into an ordinary Scheme error object, so the\n*enclosing* guard caught it and its `(#t ...)` clause returned. A case\nthat must return 0 at every depth returned `(0 1 37)` for 63/64/100.\n`with-exception-handler` had it worse -- the overflow was invisible, the\nhandler simply receiving a bare `#<error \"error\">`.\n\nBoth stacks now grow on demand like the frame and register stacks\n(`-Dmax-handlers`/`-Dmax-winds`, hard cap 32768), and `errors.isUncatchable`\nkeeps VM limits and control-flow signals out of a user's `guard`: a limit\nof the implementation is not something the program raised, so it unwinds\nto the top level under its own code. `thread-terminate!` likewise no\nlonger runs the terminated thread's guard clauses on its way out.\n\nTwo error tags turned out to be overloaded, and only the suites said so.\n`OutOfMemory` is real exhaustion but equally the payload-size cap for\n`(make-vector 100000000000000)`, so it stays catchable. `StackOverflow`\ncovered `apply`'s 255-argument ceiling -- which is the bound that ends\nthe walk of a *circular* argument list, and has to stay recoverable --\nso those three sites become KP3007 with a message that names the real\nlimit, instead of sending readers to hunt for runaway recursion.\n\nFixes #1886\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-31T15:30:28Z",
          "tree_id": "6ad812fa1bd824b3379e7100f27d2705bd03360c",
          "url": "https://github.com/kaappi/kaappi/commit/93fa575717d4339d84e008953104d530adc3b622"
        },
        "date": 1785513593298,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.423656,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.619933,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.462667,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.548192,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.005039,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.04156,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.254491,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.048371,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.472071,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.039077,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.365679,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.271626,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.499003,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.83458,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.038942,
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
          "id": "3de5281fede1fbbdb530005faa9bcc902479cc30",
          "message": "Phase 1D: printer audit — 79 assertions, five hangs, and a legal-but-wrong datum at depth 1023 (#1956)\n\n* Audit v2 Phase 1D: sweep the printer's structural round-trip\n\n`src/printer.zig` had no Scheme-level test of its own beyond a handful of\nZig unit tests.  Sweep it against the round-trip oracle -- (equal? x (read\n(open-input-string <written x>))) -- across every printable type and every\nstructural shape, with the four `write`-family contracts checked against\ntheir own R7RS 6.13.3 text rather than against each other.\n\n79 enabled assertions, 16 disabled.  Each disabled assertion is paired with\nan enabled control -- a near-identical input that behaves differently -- so\nthe file keeps proving the neighbouring path still works.\n\nBeyond the three symptoms already filed as #1902, the sweep separates that\nissue's single \"1024\" into three independent mechanisms with three distinct\ncliffs (markShared's cdr-spine depth; the seen[] cap, which makes detection\ndepend on an object's *position*; and the shared[] cap), and turns up five\nfindings it does not cover:\n\n- `write-simple` is registered as `.func = &write`, so it emits datum labels\n  on circular structure, which R7RS says it never may.\n- All four output procedures loop forever on a cycle reachable only through\n  a container the cycle pre-pass does not walk (error objects, mutex and\n  condition-variable names).  #1713 fixed this shape for record instances\n  and left the other arms behind.\n- An exact rational at nesting depth 1023 prints as \".../...\" and reads back\n  as a *symbol*: the printer's depth counter outruns the reader's nesting\n  count for that one arm, and the plain printer's truncation sentinel \"...\"\n  is itself a legal identifier.\n- `write-shared` becomes exponential once seen[] is full, so the same two\n  objects in a two-element vector print instantly one way round and never\n  terminate the other.\n- Closed issue #859 (REPL prettyPrint hang) still reproduces; the fix that\n  closed it removed the unbounded memory growth but not the hang, which now\n  lives in `exactFlatLen`.\n\nFindings only -- no printer changes.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Point printer FAIL markers at the filed issues\n\nAlso drops the claim that #859 still reproduces. A properly constructed\npty test -- one that checks whether the REPL still services later input,\nrather than whether the process is merely alive -- shows it responding at\nboth COLUMNS=200 and COLUMNS=12, so that closed issue stays closed.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-31T22:46:53+05:30",
          "tree_id": "1ec2247abc3ba02ae0a922b3488a7df7d6aea9c4",
          "url": "https://github.com/kaappi/kaappi/commit/3de5281fede1fbbdb530005faa9bcc902479cc30"
        },
        "date": 1785519951230,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.302085,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.678265,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.57334,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.981789,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004664,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046303,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.310848,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.055927,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.61012,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.230189,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.55831,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.280802,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.772434,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.5987,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045189,
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
          "id": "1c6b02f3115b2b4f910a0bcdf8ee1a59142b5fb3",
          "message": "Stop three diagnostics from misdescribing what they are about (#1958)\n\nEach of these sent a reader looking at the wrong thing.\n\nAn integral flonum rendered without its `.0`, so a type error on 1.0 read\n\"expected exact integer, got 1\" -- and 1 is an exact integer, so the message\nargued against itself. `safeValueDescription` formatted flonums with a bare\n`{d}` instead of the printer, so this affected every type error in the\ncodebase, not just the numeric-vector ones it was found in. It now goes\nthrough `printer.formatFlonum`, which is safe in this deliberately-defensive\nhelper: a flonum is inline under NaN-boxing, so nothing heap-shaped is read.\n\nA multi-limb bignum handed to a (srfi 160) constructor was reported as\n\"expected exact integer, got #<bignum>\". It is an exact integer; its only\nfault is not fitting s8..u64. `magnitudeAndSign` returned a plain `?MagSign`,\nwhich gave \"too wide\" and \"not an integer at all\" the same answer. Splitting\nthem into `ExactMag.too_wide` / `.not_exact` lets an out-of-range bignum say\n\"in-range\", matching what an out-of-range fixnum has always said -- and say\n\"non-negative\" instead when it is negative, since then the sign is the real\ncomplaint.\n\n`%record?` and `%transcoded-port` reported their errors as `record?` and\n`transcoded-port`. Those are not cosmetic truncations: both are real,\ndifferent procedures, exported by (srfi 237) and (srfi 181), with different\nargument lists -- `(record? 5 5)` is an arity error, not a type error. Both\nnow use the shared-constant convention primitives_srfi237.zig's MAKE_RTD\nalready documented for exactly this reason, so the name cannot drift again.\n\nThe audit that found these (#1890, Phase 2.1) had already written the\nassertions and commented them out as known failures; they are enabled here,\nalongside their original controls and three cases the audit did not cover\n(a negative multi-limb bignum, a signed-kind overflow, and a genuine\nnon-integer, which is what keeps \"in-range everywhere\" from passing). One\nof the four could not be enabled as written: `(not (has-substring? msg\n\"got 1\"))` cannot pass whatever the code does, since \"got 1\" is a prefix of\nthe correct \"got 1.0\" -- it is stated positively instead, which is fully\ndiscriminating because the buggy message was exactly \"got 1\".\n\nMutation-tested: reverting each of the three fixes in turn fails exactly the\nassertions belonging to it and no others.\n\nFixes #1916\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-31T22:47:11+05:30",
          "tree_id": "4e4667e4a449d0e129efd701cdcc4272bc647d0f",
          "url": "https://github.com/kaappi/kaappi/commit/1c6b02f3115b2b4f910a0bcdf8ee1a59142b5fb3"
        },
        "date": 1785520126466,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.115725,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.261311,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.443981,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.183069,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004164,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.035738,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.225216,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.041166,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.147257,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.96069,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.211298,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.23357,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.281543,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.81746,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.04029,
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
          "id": "589aba141046e3b8544cf84787b4cb1b8a1579ad",
          "message": "Phase 2.4: SRFI 160 audit — 1066 assertions across 12 element kinds, one hang (#1952)\n\n* Phase 2.4: audit primitives_srfi160 across all 12 element kinds\n\nsrc/primitives_srfi160.zig is 280 lines and six %-prefixed generic\nprimitives, but those six are the entire native surface under 12 element\nkinds and ~732 exported names across 13 .sld files. It had no audit test,\nand the existing tests/scheme/srfi/srfi160.scm is 75% s8.\n\nAdds tests/scheme/audit/primitives_srfi160-audit.scm: 1066 assertions,\nevery 12-kind sweep generated from one kind table rather than written out\nper kind.\n\nConfirmed correct, systematically rather than by spot check: the 8\ninteger kinds at min/min+1/min-1/max/max-1/max+1 and against nine\ntype/exactness rejection classes; the two independent range checks\n(%uvec-elt-valid? in Scheme, expectSignedInRange/expectReal in Zig) agree\non a 12x23 corpus; f32 really truncates to single precision; -0.0, +-inf.0\nand NaN survive; c64/c128 pack two components independently and at the\nright width; a rejected set! never leaves a half-written element; the\nu8-as-bytevector seam holds in both directions; every per-type wrapper\nfixes its own kind symbol (12x12 predicate matrix plus every\nkind-constructing entry point); and callback errors propagate out of all\n18 higher-order generics, with an out-of-range callback result rejected\nrather than truncated.\n\nThree findings, disabled with a marker and an enabled control each:\n\n- Uvector-segment with n = 0 never terminates. %uvec-segment advances by\n  (min len (+ start n)), so start never moves while a fresh zero-length\n  copy is consed each iteration. All 12 kinds, both dispatch branches.\n  SRFI 160 makes n = 0 \"an error\", so a raise would conform; a hang does\n  not. Controls: n = -1 raises, n = 1 and n = 3 work, empty vector with\n  n = 0 returns ().\n\n- c64/c128 comparator hash raises on every value. %uvec-hash folds with\n  number-hash, which is (abs x)-based and rejects a complex. c64/c128\n  elements always decode to a Complex, so this fires even when every\n  imaginary part is zero. SRFI 160 requires the comparator to provide\n  hashing. Controls: the s8, f64 and u8 comparator hashes all work.\n\n- A zero-imaginary c64/c128 element writes as a form that reads back as a\n  different type: real? is #f, yet write emits \"1.5\", which reads as a\n  flonum. Affects the default fill, so every fresh c64/c128 vector has\n  such elements. Only decodeElement can produce them -- make-rectangular\n  normalises a zero imaginary part away. The vector printer prints\n  \"1.5+0.0i\" for the same bytes, so the two printer paths disagree.\n\nByte order is host-native by design and, on this evidence, not observable\nfrom Scheme: there is no NumericVector-to-bytes view, and NumericVector\nis not .sbc-serialisable. The printer and the primitives are two separate\nhand-written native-endian decoders, so the section 8 assertions use\nvalues whose byte-reverse is a different in-range number -- they assert\nencoder/decoder agreement rather than a little-endian layout, so they\npass on any host and would fail on s390x only if the two drifted apart.\n\nFound by: systematic audit v2, Phase 2.4\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Point SRFI 160 FAIL markers at the filed issues\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-31T23:11:25+05:30",
          "tree_id": "c2c96809d17d13065b03b09200c18c067ea72f26",
          "url": "https://github.com/kaappi/kaappi/commit/589aba141046e3b8544cf84787b4cb1b8a1579ad"
        },
        "date": 1785521556195,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.140581,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.408456,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.447896,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.214184,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004263,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.036742,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.228824,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.041613,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.243518,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.981944,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.252776,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.241359,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.35194,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.763942,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.034544,
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
          "id": "e24e594ed8a650edb6b09d9216b16594a78610ad",
          "message": "Parallelise run-all.sh's shell suites, and stop rebuilding twice (#1957)\n\nThe shell suites were the larger half of run-all.sh's wall time and ran\nstrictly sequentially, because several scripts build into the one shared\nzig-out/ and would race each other's install. Two separate things had to\nchange: the race (which blocked concurrency) and the cost (which was\nsomewhere else entirely).\n\nThe cost was two full interpreter rebuilds. `zig build -Dbundle=…`\nrecompiles everything, since the embedded bytecode is part of the compiled\nmodule graph, and the two scripts that need a standalone binary each paid\nfor one — 85% of the shell suites' entire wall time for two tests. They\nneeded different embedded bytecode only because each carried its own\nfixture, so they now share one, in\ntests/scheme/compile/fixtures/bundle-replay/. Identical bytes make the\nsecond build a ~0.2s hit in Zig's own content-addressed cache. The .sbc is\nregenerated on every call rather than cached: unchanged sources give\nidentical bytes and the hit, while an edit under src/ changes them and\nforces exactly the rebuild it must — a cached .sbc of our own would go\nstale against the new binary's build id instead.\n\nThe race is closed at both ends. run-all.sh builds the runtime archive once\nup front and exports KAAPPI_RT_LIB_READY, which ensure_runtime_lib treats as\n\"already fresh\"; the marker is advisory, so a script run standalone (the\nWindows CI legs invoke each one directly) still builds its own. What builds\nremain take a mkdir-based lock — atomic on POSIX and Git Bash alike, where\nflock is Linux-only and macOS has none — and a lock whose holder was killed\nis stolen by the next waiter via the recorded pid. Six scripts had their own\ninline copy of the archive build, checking only for the file's existence;\nthey go through ensure_runtime_lib now, so one guard covers all 18.\n\nDispatch inside a suite is longest-first, found by grep rather than a list\nof names. Reporting still walks glob order, so a transcript diff between two\nruns stays meaningful at any job count.\n\nFull suite on a 12-core box: 475s -> 245s, same 2026 pass / 0 fail. The\nparallel and KAAPPI_TEST_JOBS=1 transcripts differ only in the line that\nreports the job count.\n\nCloses #1926",
          "timestamp": "2026-07-31T23:27:09+05:30",
          "tree_id": "a44f3a0ad9e71998d6a8746749f3433472bc0dba",
          "url": "https://github.com/kaappi/kaappi/commit/e24e594ed8a650edb6b09d9216b16594a78610ad"
        },
        "date": 1785523328128,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.327595,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.23971,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.603549,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.968196,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004676,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.047056,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.314084,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057826,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.69526,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.222003,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.648019,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.28591,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.802526,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.679759,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043003,
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
          "id": "db8e3d074fe64ead9d14b6b389d913e1a9dff132",
          "message": "Test what is inside each per-tag GC arm, not just that one exists (#1963)\n\nZig's exhaustiveness check guarantees markObjectContents, markValueInner,\nreferencesYoung, objectSize and freeObject each have an arm for all 41\nObjectTag members. Nothing guarantees the arm traces the tag's Value\nfields: one that forgets a field compiles cleanly and silently frees a\nlive object. Port's satellites are hand-written at five sites, and\nmarkValueInner deliberately duplicates markPortValues rather than calling\nit, so a third Value-bearing Port field would be invisible in up to five\nplaces at once.\n\nTwo runtime shapes, because the three mark-graph switches are reached by\ntwo different paths. Rooting a container makes markValueInner the only\nthing that can keep a referent alive. Promoting a container to the old\ngeneration, repointing a field through writeBarrier, then dropping the\nroot before a minor collection makes the remembered-set walk\n(markObjectContents, its only caller) the only route, and exposes\npruneRememberedSet's referencesYoung decision directly. Every rooted case\nends by dropping the root and asserting the referents die: an assertion\nthat cannot fail is not a test.\n\nLiveness is decided by walking the GC's own object lists for the\nreferent's address, never by dereferencing it -- reading back a swept\nreferent would be the use-after-free this file exists to detect.\n\nThe comptime inventory pins the exact field list of every heap struct\nthese switches dispatch on, plus the satellites they reach through\n(CustomBacking, TranscodeState, HashEntry, GuardEntry, WindRecord,\nExceptionHandler, SavedFrame, CallFrame). Value is u64, so no comptime\ntype test can tell a real Value from profile_calls -- pinning the whole\nlist is what makes the guard sound. Adding a field is now a build error\nnaming all five switches until someone has looked at them.\n\nMutation-tested: eight deliberate single-field deletions across\nmarkValueInner, markPortValues, referencesYoung and markFiberState each\nfailed exactly the intended case and nothing else, and a seventh Value\nfield on CustomBacking fails the build with the inventory error.\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-01T00:04:40+05:30",
          "tree_id": "0b6e9a3003744e22473bbbb692aae9841479b758",
          "url": "https://github.com/kaappi/kaappi/commit/db8e3d074fe64ead9d14b6b389d913e1a9dff132"
        },
        "date": 1785526087883,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.058264,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.199712,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.432448,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.27726,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.003749,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.03479,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.229581,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.042564,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 1.803694,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.898721,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.181508,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.239669,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.307003,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.380815,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.037203,
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
          "id": "e58801829acda296b6fcddb1f86d945d9af05ff1",
          "message": "Stop piping into grep -q under pipefail (#1966)\n\n`grep -q` exits the moment it matches. When the match is on an early line\nof the output, the writer on the left of the pipe can still be mid-write\nand dies of SIGPIPE — and `set -o pipefail`, which every one of these\nscripts sets, then reports the whole pipeline as failed even though the\nmatch succeeded. The assertion fails while printing the very text it was\nlooking for.\n\nIt is a race, so it passes locally and on 16 of 17 CI legs, then fails on\nthe slowest one. #1957 made run-all.sh dispatch the shell suites\nconcurrently, which raised the load enough to fire it: three assertions in\ntests/scheme/errors/ failed on freebsd-test, each matching the first or\nsecond line of a multi-line output, each with the expected text visible in\nthe failure it printed. In every case the assertion beside it matching the\n*last* line passed, because grep then reads to EOF and the writer never\nsees a closed pipe.\n\nReproduced directly: with an early match and a large output, `echo \"$x\" |\ngrep -q PATTERN` under pipefail reports no-match 20 times out of 20, and\nthe here-string form 0 times out of 20. At the real ~3-line size it is\nabout 1 in 16,000 on an idle machine — rare enough to have gone unnoticed,\ncommon enough to bite three times in one run on an emulated 4-core VM.\n\nA here-string has no pipeline for pipefail to judge: same grep, same\npattern, same exit status, no second process whose death can be mistaken\nfor a failed match. Converted all 29 sites rather than the three that\nfailed, since they are one latent bug and the rest would surface next.\n\nTwo piped `grep -q` uses remain, in errors/reader-*-errors.sh: those have a\ncommand on the left rather than a variable, and neither script sets\npipefail, so neither can hit this.",
          "timestamp": "2026-08-01T01:18:44+05:30",
          "tree_id": "41a345cc698f8dd2d6924bd845d24699e9a8d1ad",
          "url": "https://github.com/kaappi/kaappi/commit/e58801829acda296b6fcddb1f86d945d9af05ff1"
        },
        "date": 1785529566020,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.959296,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.117832,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.595535,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.829967,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004863,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.044767,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.296501,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.05944,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.504309,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.16581,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.524644,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.308806,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.687212,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.817554,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044673,
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
          "id": "db0533161a6b1294321bf611b13206ca6504472b",
          "message": "Tick the third batch, and mark 5B as landed-but-blocked (#1968)\n\n1D, 2.4 and 7B are merged. 5B is ticked as complete work with its PR\nstill open, because it is blocked by a CI regression on main (#1967)\nrather than by anything in the unit -- leaving it unticked would imply\nthe work is outstanding when what is outstanding is someone else's\nFreeBSD failure.\n\nEach entry records what the unit found AND what it confirmed correct.\nThe two units that found no bugs in their target are the ones most at\nrisk of being read as wasted, so their entries say what they closed:\nnine untested false rows in the unwind asymmetry, and a 41-tag mark\ngraph whose arm contents nothing could check.\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-01T02:00:15+05:30",
          "tree_id": "10d24394df48e68650b6ebf4b7772864a79c6d27",
          "url": "https://github.com/kaappi/kaappi/commit/db0533161a6b1294321bf611b13206ca6504472b"
        },
        "date": 1785533974500,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.961673,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.607652,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.557629,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.834074,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004867,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.044936,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.295251,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.059248,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.510185,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.15452,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.613622,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.302184,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.764885,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.783166,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045887,
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
          "id": "2b2027b1d8c95e9e7932da541ad37edc2af9da14",
          "message": "Phase 5B: waitForFd park-vs-drive — 26 tests for a protocol that had zero direct coverage (#1960)\n\n* Assert which branch waitForFd took, not just that the read worked\n\n`waitForFd`, `driving_waits` and `anyAncestorWaitResolved` had zero direct\nreferences in any src/tests_*.zig. The park-vs-drive branch was reached only\nincidentally, through Scheme programs that happened to block, and incidental\ncoverage cannot say which branch ran: a change that made every caller drive in\nplace — or every caller park — would have left the whole suite green.\n\nsrc/tests_waitforfd.zig (26 tests) asserts the branch. The selector,\n`my_idx != 0 and vm.dispatched_from_scheduler`, is plain VM state, so all four\ncells are set up directly rather than raced into; the two that must DRIVE are\ndiscriminating controls for the two terms of the conjunction. The park cells\nuse an fd that is already readable, which separates \"parks because it was told\nto\" from \"parks because the fd was not ready\".\n\nThree gaps this closes beyond the branch itself:\n\n- The #1625 unwind asymmetry. `IoWait` is the only wait kind setting\n  `unwind_on_resolved_ancestor`, and runSchedulerStep gates on `@hasDecl`, so\n  opting a join/channel/mutex/condvar wait in — or IoWait out — compiles\n  cleanly and silently changes blocking semantics. A comptime table over all\n  ten production Ctx types pins it; the nine `false` rows had no coverage at\n  all. `anyAncestorWaitResolved` gets direct tests for its identity filter,\n  its timed_out disjunct, and its whole-stack scan.\n\n- The yield-retry contract. A parked primitive re-executes from scratch, so\n  progress in a Zig local is lost. Five tests reach a *confirmed* park with the\n  stream torn mid-item (mid-UTF-8, mid-line, mid-CRLF, mid-datum) and assert\n  both that the prefix landed in port.read_buf and that the resumed primitive\n  produces the whole item, plus a control at an item boundary where nothing\n  may be stashed. The write side takes the other route — drain before append,\n  progress in write_buf_start — and is checked for loss and duplication.\n\n- Which frames actually force the drive branch. `guard` does; `map` and\n  `dynamic-wind` do not, because both are bootstrapped in Scheme\n  (vm_bootstrap.zig) and their thunk call stays in the same runUntil. All\n  four fibers in that test run the identical `(read-char rp)`. README section\n  Fibers already says this; two Zig doc comments still name dynamic-wind and\n  map/for-each as re-entrant native frames, including the user-visible\n  \"port I/O abandoned\" message text.\n\nDeterminism, rather than sleeping, comes from FIFO dispatch: a trivial\n`(fiber-join (spawn ...))` dispatches every already-spawned fiber to its first\nblocking point first. 6/6 identical runs; unchanged under -Dgc-stress=true.\n\nThe production diff is visibility only — nine wait-context types go `pub` so\nthe asymmetry table can name them — plus the vm_tests.zig registration.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Gate the write-side parking assertions to POSIX\n\nWindows CI reached .completed where the test expected .io_waiting: the\n20 KB write is accepted outright, so the flush never EAGAINs and there is\nnothing to park on. Shrinking SO_SNDBUF is what forces the park on\nkqueue/epoll hosts and it does not have that effect there.\n\nWhy the mechanism is not stated in the comment: I could not establish\nwhether the reduced SO_SNDBUF is ignored or the socket layer simply\nbuffers past it, and this cannot be checked from the dev machine. The\ncomment records the observed outcome and says so, rather than asserting a\ncause that was never verified.\n\nThe gate covers only the three parking assertions. The lossless-resume\nassertions -- 20000 bytes arriving exactly once, nothing lost to a park\nand nothing duplicated by a re-execution -- are the property the test\nexists for, and they still run on every platform whether or not a park\noccurred.\n\nVerified: 30/30 on macOS with the gate in place (so it does not silently\ndisable the test here), and `zig build test -Dtarget=x86_64-windows`\ncompiles clean -- the same command CI's windows-cross job runs.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-01T02:13:39+05:30",
          "tree_id": "d08a5fccaf4ff34f7ba9e8882d7536c6c8f468dd",
          "url": "https://github.com/kaappi/kaappi/commit/2b2027b1d8c95e9e7932da541ad37edc2af9da14"
        },
        "date": 1785536810385,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.24768,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.674911,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.45735,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.24858,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004612,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.037616,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.24723,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.045303,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.279681,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.015743,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.262393,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.254601,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.35284,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.833433,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.03751,
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
          "id": "9a82cd4d90d32a2c8e7d0d5f5b4b0680a39238e3",
          "message": "Say which kind of failure a port error is (#1944) (#1969)\n\nprimitives_io.zig had 44 typeError sites and zero indexError/argError\nsites, so every non-type failure in the file arrived mislabelled.\n\nSeeking a string port past its end raised a detail-less \"invalid\nargument in 'set-port-position!'\" — no index, no length — while the\nsibling non-seekable path three branches down did set detail. It reports\nindex and length now (KP3006).\n\nwrite-string's range check blamed args[0]: `(write-string \"abc\" p 5)`\nsaid \"expected valid range, got #<string>\", naming the one argument that\nwas valid. The offending index is named now, following substring, the\nhouse precedent for a start/end pair. An inverted-but-in-range pair is\nneither a type nor a range fault, so `(write-string \"abc\" p 2 1)` is\nargError: \"start 2 is greater than end 1\".\n\nA closed port was \"type error: expected open input port, got #<port>\".\nA closed port is a port, and the direction check has already run, so\nnothing about its type is wrong — that is argError (KP3007). A genuine\nnon-port, and an input port where an output port is wanted, are still\ntype errors; both are pinned as controls.\n\nThree internal guards carried the tag .claude/rules/gc-safety.md\nforbids: waitPortFd and raisePortClosedDuringIo reported a missing VM or\nGC as KP3007, blaming the program for a broken interpreter. #1874\nblessed these as Rule 1 keepers on the grounds that they \"already\ncarried a tag of their own\" — but InvalidArgument is not a tag either\nfunction returns for any other reason, and raisePortClosedDuringIo is a\nbyte-for-byte twin of raiseWrappedPortClosed 950 lines down the same\nfile, which Rule 2 had already moved. Both are settled the same way now,\nand the doc's seam paragraph says why the Rule 1 side is narrower than\nit read.\n\nThe audit file's existing assertions only ever asked whether a bad call\nraises, which is how all of this drifted; 13 new assertions pin the\nmessage text, 9 of which fail without this change. The guard tags are\nunreachable from Scheme, so they get a Zig test where the private\nhelpers live.\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-01T02:25:15+05:30",
          "tree_id": "3d6c4b566c2864f447d18282ec13a6ece5c07ca8",
          "url": "https://github.com/kaappi/kaappi/commit/9a82cd4d90d32a2c8e7d0d5f5b4b0680a39238e3"
        },
        "date": 1785536944840,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.287284,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.785897,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.570462,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.952305,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004713,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.04671,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.31136,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.056612,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.686396,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.24324,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.582693,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.286477,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.771485,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.50433,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042888,
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
          "id": "fab1e9e9864d8b9b0caf98df3609801924cefe37",
          "message": "Bump vmactions/netbsd-vm from 1.4.3 to 1.4.4 in the github-actions group (#1970)\n\nBumps the github-actions group with 1 update: [vmactions/netbsd-vm](https://github.com/vmactions/netbsd-vm).\n\n\nUpdates `vmactions/netbsd-vm` from 1.4.3 to 1.4.4\n- [Release notes](https://github.com/vmactions/netbsd-vm/releases)\n- [Commits](https://github.com/vmactions/netbsd-vm/compare/fac0a63f3e5244c600cb9ca532d27ee774ecdb4b...bf34bcd909bb50856f934a67d09a8fbe2b966a1b)\n\n---\nupdated-dependencies:\n- dependency-name: vmactions/netbsd-vm\n  dependency-version: 1.4.4\n  dependency-type: direct:production\n  update-type: version-update:semver-patch\n  dependency-group: github-actions\n...\n\nSigned-off-by: dependabot[bot] <support@github.com>\nCo-authored-by: dependabot[bot] <49699333+dependabot[bot]@users.noreply.github.com>",
          "timestamp": "2026-08-01T02:31:30+05:30",
          "tree_id": "0e04d110683f4745caedbdc00e29ef9edc2bcc65",
          "url": "https://github.com/kaappi/kaappi/commit/fab1e9e9864d8b9b0caf98df3609801924cefe37"
        },
        "date": 1785537513088,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.927184,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.157308,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.560264,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.816146,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004844,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.045731,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.295585,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.054657,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.31871,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.157812,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.577712,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.296566,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.675182,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.765222,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044383,
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
          "id": "775890947add3c041dcaa46606f654797330ec9f",
          "message": "Document what may actually cross a thread boundary (#1964)\n\nThe uncopyable-tag list in gc_deep_copy.zig reads as the authoritative\nanswer to \"what can cross a thread boundary\". It is not: it governs the\n*copy* route only — the thread-start! thunk closure, the thread-join!\nresult, a channel message. A value reached through the shared globals map\n(VM.initForThread shares the parent's map by pointer) is never copied and\nnever reaches that switch.\n\nThirteen of the fourteen tags are freely usable through a top-level\ndefine, and for mutexes and condition variables a global is the *only*\nsupported way to share one — exactly inverted from a channel, which must\nbe captured lexically. Nothing anywhere noted that the two differ, and\nthey appear side by side in every concurrency example.\n\nThe globals route is defended per-type inside individual primitives, and\ntwo types do so: channels and thread handles. Extending that to the rest\nuniformly is not possible — it would remove the sole way to synchronise\nthreads — so the honest model is documented instead, with the two\nknown-unsound rows left to their own issues (#1924, #1936).\n\nCLAUDE.md's \"threads cannot share mutable heap state\" was the false\nguarantee in its most compact form; it now describes both routes.\n\ndocs/dev/thread-value-sharing.md holds the per-type matrix.\nsrfi18-sharing-model.scm pins both routes for the nine types covering\nevery distinct enforcement shape, as a characterisation test, so a change\nto any row fails visibly instead of widening the gap silently.\n\nCloses #1937\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-31T21:10:49Z",
          "tree_id": "d2444d938a890c0924bc2a6909420c9b4f7d7cae",
          "url": "https://github.com/kaappi/kaappi/commit/775890947add3c041dcaa46606f654797330ec9f"
        },
        "date": 1785539453227,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.272862,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.045469,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.580243,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.954901,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004639,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.047974,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.312345,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.056273,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.677575,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.230175,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.571281,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.282839,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.767409,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.611099,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044674,
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
          "id": "ea2e2e4988014e8fdcd40e9a0e1d957a96366918",
          "message": "Stop the \"port I/O abandoned\" error naming dynamic-wind as unparkable (#1965)\n\nThe message named \"guard, dynamic-wind, callbacks\" as frames a fiber cannot\nsuspend under. dynamic-wind is bootstrapped Scheme: its body runs in the\nbytecode dispatch loop and a fiber parks inside it like a bare read, so the\nerror sent users to move blocking I/O out of a dynamic-wind for no reason and\nleave it inside the guard that actually caused the drive.\n\nIt now names what genuinely opens a nested native frame: guard, and the native\nhigher-order drivers (SRFI-1 fold/filter/find, hash-table-walk, assoc/member\nwith a custom predicate, string-index, eval).\n\nSix comment copies of the same misclassification are corrected alongside,\nincluding raiseDeadNativeReturn's \"(map, for-each, sort, apply, ...)\", which\nnames sort — portable Scheme in lib/srfi/95.sld. README's list dropped sort\nfor the same reason.\n\nRegression test: readers blocking inside dynamic-wind, a map callback, and a\nsort comparator must all reach .io_waiting when dispatched before any writer\nexists, contrasted with the adjacent #1625 test where guard drives.\n\nCloses #1959",
          "timestamp": "2026-08-01T03:18:44+05:30",
          "tree_id": "bfe137901e3db835719f43581031bc920923d102",
          "url": "https://github.com/kaappi/kaappi/commit/ea2e2e4988014e8fdcd40e9a0e1d957a96366918"
        },
        "date": 1785539635941,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.254348,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.736404,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.596318,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.947722,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004738,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.04658,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.31624,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057427,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.69308,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.160761,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.587188,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.284167,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.775336,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.640932,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044048,
            "unit": "seconds"
          }
        ]
      }
    ]
  }
}