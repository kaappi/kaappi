window.BENCHMARK_DATA = {
  "lastUpdate": 1783490522023,
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
          "id": "bd2ea1d8e2562b7295523649dedb6f8d4bb3c9f1",
          "message": "Assert expected values in IR behavioral tests instead of ignoring results (#1073) (#1101)\n\nThe 29 `expectBehavioralParity` tests evaluated source but discarded\nthe result, so a wrong return value would pass silently. Replace with\n`expectEvalFixnum`, `expectEvalBool`, and `expectEvalVoid` assertions\nthat verify the actual result. Tag the 11 bytecode-parity tests with\ntheir legacy compileExpr form so each is deleted with #1038.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-04T21:33:56+05:30",
          "tree_id": "e84272b4ef2414a52eb595bb7f67e999d89bf838",
          "url": "https://github.com/kaappi/kaappi/commit/bd2ea1d8e2562b7295523649dedb6f8d4bb3c9f1"
        },
        "date": 1783184030990,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.273256,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.096407,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.915897,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.248163,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012614,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.210796,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.474712,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070577,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.451876,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.818446,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.909201,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.951454,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.278244,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.694364,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043807,
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
          "id": "9d642b08338f4726c68e584d7d368d330550699a",
          "message": "Dedup handleDefineLibrary declaration loop and extract openIncludeFile (#1048) (#1102)\n\nhandleDefineLibrary had an inline 6-branch declaration dispatch loop\nthat duplicated processLibDeclaration almost verbatim. Worse, its\ncond-expand branch destructively mutated the AST via setCdr — a\ncorrectness hazard for bundled sources and include-library-declarations\nre-entry. Replace the inline loop with a call to processLibDeclaration,\nwhich handles cond-expand cleanly via recursion.\n\nAlso extract the path-resolution + readFileOrBundled boilerplate\n(duplicated 3x across handleTopLevelInclude, compileLibInclude, and\nincludeLibraryDeclarations) into openIncludeFile.\n\nPreserve import error-detail printing by adding it to\nprocessLibDeclaration's import branch (was silently swallowed before).\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-04T21:35:28+05:30",
          "tree_id": "e053b7e4a0d4853ba57389b5d71516ac610a52e8",
          "url": "https://github.com/kaappi/kaappi/commit/9d642b08338f4726c68e584d7d368d330550699a"
        },
        "date": 1783184114022,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.323777,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.476439,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.990066,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.262837,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.013404,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.211827,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.474028,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069681,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.601906,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.857496,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.952532,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.9609,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.314484,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.713408,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044502,
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
          "id": "33f2f171e2592130540ab374093c0f1be8bd6637",
          "message": "Deduplicate export lists and add drift test (#1053) (#1104)\n\nHoists all library export name arrays from inside registerStandardLibraries()\nto file-scope pub const declarations, shared by both standard and sandboxed\nregistration. Adds a unit test that asserts every non-syntax name in every\nexport list resolves in globals after registerAll — converting silent export\ndrift into a test failure.\n\nPhases 1 and 2 of #1053. Net -156 lines (13 duplicate arrays removed).\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-04T21:42:20+05:30",
          "tree_id": "7535f9dd3c0d7ae39576fa860aa87db79dc996a0",
          "url": "https://github.com/kaappi/kaappi/commit/33f2f171e2592130540ab374093c0f1be8bd6637"
        },
        "date": 1783184416436,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.490087,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.118902,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.987723,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.307496,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012887,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.213379,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.479543,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.071099,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.689815,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.877598,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 10.046945,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.957069,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.437307,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.572195,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043737,
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
          "id": "6d7a96322e1206619373ec7429258a2191fd63ae",
          "message": "Deduplicate compiler body, closure, debug, and arrow helpers (#1042) (#1105)\n\nExtract shared helpers from near-clone code across the compiler:\n\n- compileBodyForms: unifies compileBody (~190 lines) and compileLetBody\n  (~180 lines) into a single parameterized function. Also fixes a latent\n  bug where compileLetBody silently dropped prescan names past 64.\n- populateDebugLocals: replaces 4 identical 8-line copies.\n- emitClosureEpilogue: replaces 3 copies of the 15-line box-upvalues +\n  emit-closure + emit-descriptors sequence.\n- emitArrowCall: replaces 3 copies of the => arrow-clause call emission.\n\nNet: -239 lines. All 1701 tests pass including GC stress and hygiene.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-04T21:39:45+05:30",
          "tree_id": "f31a8fdbbd6ebea6ea50722a072ed8bb7bfdb722",
          "url": "https://github.com/kaappi/kaappi/commit/6d7a96322e1206619373ec7429258a2191fd63ae"
        },
        "date": 1783184464483,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.084241,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 10.468223,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.9441,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.317363,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.013939,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.235406,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.47819,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068257,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 13.665509,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.839732,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 11.110285,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.061126,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 9.093885,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.887808,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045289,
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
          "id": "958009075c07e2758fb983f03e1b1f9d8641696a",
          "message": "Delete dead forwarding wrappers in vm.zig; move re-entrant call machinery to vm_calls.zig (#1103)\n\nMove callHandler, callThunk, and callWithArgs from vm.zig to vm_calls.zig\nwhere they belong per the VM file split. Factor shared computeReentrantBase\nand callReentrant helpers to eliminate the duplicated base-calculation,\nframe-push, runUntil, and unwind-on-error blocks.\n\nDelete 19 zero-caller forwarding wrappers left behind when the dispatch\nloop and call machinery were extracted, plus the dead callWithCC in both\nvm.zig and vm_continuations.zig. Also remove a dead restoreContinuation\nforwarding function in vm_calls.zig.\n\nvm.zig: 1232 → 780 lines. vm_calls.zig: 532 → 816 lines.\n\nCloses #1049\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-04T21:37:04+05:30",
          "tree_id": "3cb6be6a9d4329049956a079d4e13e5453851374",
          "url": "https://github.com/kaappi/kaappi/commit/958009075c07e2758fb983f03e1b1f9d8641696a"
        },
        "date": 1783184503741,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.04373,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 10.223778,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.954436,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.339609,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.013724,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.235304,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.4763,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068991,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 13.468425,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.839124,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 11.110338,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.061887,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 9.098955,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.819588,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045071,
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
          "id": "8502aadb86ca1c244f818540a47e5228122a8014",
          "message": "Extract MultiListIter and buildList helpers in SRFI-1 primitives (#1059) (#1107)\n\nTwo tangled repeats lived in primitives_srfi1.zig: multi-list iteration\nboilerplate (11 copies) and reverse-iterate-allocPair list building\n(~20 copies). Extract both as file-local helpers.\n\nMultiListIter encapsulates the currents array, all-pairs check,\ncar/pair gathering, and cdr advance. Supports car mode (default) and\npairs mode for pair-for-each/pair-fold.\n\nbuildList always roots the accumulator, fixing three GC bugs where\nsplitAtFn, spanFn, and breakFn were missing pushRoot — allocPair\nduring the build phase could trigger collection with the partially-built\nlist unreachable.\n\nNet: 140 insertions, 546 deletions (2185 → 1778 lines).\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-04T21:49:10+05:30",
          "tree_id": "9dad5095305abe81ff88820adc5c1af727ee0a6d",
          "url": "https://github.com/kaappi/kaappi/commit/8502aadb86ca1c244f818540a47e5228122a8014"
        },
        "date": 1783184558078,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.049798,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.623132,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.948485,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.37447,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.013599,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.234705,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.473691,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068756,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 13.560236,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.849509,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 11.127742,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.068273,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 9.099886,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.847919,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045304,
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
          "id": "d8ddf236b780457092d93d34dd5c8c5cd9b5d169",
          "message": "Generate FFI call-signature matrix with comptime inline-for (#1058) (#1106)\n\nReplace 6 hand-enumerated callFfiN functions (~750 lines, 87 curated\nbranches) with a comptime-generic callFfiGeneric that uses nested\ninline-for over the 7 canonical types to generate exhaustive dispatch\nfor arities 0-3. Arities 4-5 remain curated but use shared marshalArg/\nmarshalRetValue helpers for consistency.\n\nCoverage: arities 1-3 go from 47%/7%/0.5% to 100% (2,800 branches).\nPreviously-unsupported signatures like (float,int)->double now work.\nBinary +13%, compile time +11%, file -37% (877 vs 1384 lines).\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-04T21:56:29+05:30",
          "tree_id": "278391f29b9aa357473dcd93c01078dd7ef9149e",
          "url": "https://github.com/kaappi/kaappi/commit/d8ddf236b780457092d93d34dd5c8c5cd9b5d169"
        },
        "date": 1783185098220,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.293771,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.7968,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.914258,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.319295,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012478,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.211894,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.473622,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.071863,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.456724,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.818356,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.987746,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.952011,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.245163,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.705732,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044757,
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
          "id": "aaa28f3be8f91b7c50318fa792d461b5a8da5237",
          "message": "Add arena allocator and helpers to LLVM emitter, remove 256-slot panic cliffs (#1071) (#1108)\n\nThe LLVM IR text emitter leaked every freshTemp/label/interned string\nallocation and used fixed [256][]const u8 stack arrays that panicked on\n>256-arg calls during compilation.\n\n- Add ArenaAllocator that frees all emitter-lifetime strings in bulk\n  at deinit, with backing_alloc for containers needing prompt cleanup\n- Add emitImm(), startBlock(), emitOrphanAfterTail(), freshLabel()\n  helpers to deduplicate 6 inline materialization patterns, 3 orphan-\n  label blocks, and ~10 manual current_block updates\n- Replace all [256] stack arrays in emitCallNode, emitSelfTailCall,\n  emitDirectCall, emitOr with arena-allocated slices sized to actual\n  argument count\n- Remove discarded freshTemp() call in emitAnd that wasted an\n  allocation and burned an SSA number per and-form\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-04T21:56:49+05:30",
          "tree_id": "bf5e7b1d8b950fd6b575765c69f87806e71c9982",
          "url": "https://github.com/kaappi/kaappi/commit/aaa28f3be8f91b7c50318fa792d461b5a8da5237"
        },
        "date": 1783185204936,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.374975,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.12806,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.916206,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.55456,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012665,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.211767,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.478056,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.071249,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.47941,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.821126,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 10.00797,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.963047,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.282326,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.763993,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044705,
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
          "id": "62d616a3dac3ecd55052fcc9247fcd1609e1695a",
          "message": "Extract buildRestList, lookupGlobalLocked, and raiseUndefinedVariable helpers (#1047) (#1109)\n\nDeduplicate three patterns in the hot dispatch loop:\n\n- buildRestList: variadic rest-arg cons-list building (5 copies across\n  vm_dispatch.zig, vm.zig, vm_calls.zig → 1 pub fn + 5 callsites)\n- lookupGlobalLocked: global lookup with hygienic-prefix fallback and\n  shared lock (3 identical copies in call_global/tail_call_global → 1\n  inline fn)\n- raiseUndefinedVariable: \"undefined variable\" error with did-you-mean\n  suggestion (5 copies → 1 noinline fn)\n\nAlso marks raiseDeadNativeReturn as noinline to keep error-path code out\nof the instruction cache.\n\nThe finishFrameReturn helper (7 copies of the frame-return epilogue) was\nbenchmarked but dropped: extracting it changed the dispatch loop's code\nlayout enough to cause a 12% regression on fib(35) from instruction\ncache alignment effects, even though fib uses no tail calls. The other\nthree helpers pass the <3% benchmark gate.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-04T22:25:19+05:30",
          "tree_id": "6983fbee4801444f18c7154355bbfa05fbfbbfd4",
          "url": "https://github.com/kaappi/kaappi/commit/62d616a3dac3ecd55052fcc9247fcd1609e1695a"
        },
        "date": 1783185434449,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.418565,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.67086,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.905061,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.253515,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012912,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.211742,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.476262,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070575,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.559017,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.807379,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.994399,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.958083,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.295075,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.559001,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043953,
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
          "id": "146b88374fed679ecebc27f7e3451a43e121b5f1",
          "message": "Remove dead code: unused fn, unreachable logic, dead param, doubled comment (#1075) (#1110)\n\n- Delete unused `emitSexprEvalValue` (zero callers) in llvm_emit.zig\n- Remove unreachable rest-param handling in llvm_emit_lambda.zig\n  (early `return null` at line 51 makes extra/allowed logic dead)\n- Remove dead `_: bool` discriminator from `compileLetrecImpl`\n  (compileLetrec and compileLetrecStar passed different bools,\n  but the parameter was always discarded)\n- Remove doubled `// Optimization passes` comment in compiler.zig\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-04T22:57:29+05:30",
          "tree_id": "a54f313c4dafc209f8d79e7d7919bc640124b21a",
          "url": "https://github.com/kaappi/kaappi/commit/146b88374fed679ecebc27f7e3451a43e121b5f1"
        },
        "date": 1783187901393,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.424914,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.61582,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.902873,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.398411,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012577,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.211251,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.464715,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070517,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.521551,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.810633,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 10.033681,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.958778,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.279785,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.518787,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043099,
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
          "id": "db2f7dd32b75c4bda9124b7da88321408330e767",
          "message": "Add TestContext and expectEval helpers to testing_helpers (#1074) (#1111)\n\nReduce the 4-line GC+VM setup dance repeated across test files by\nadding TestContext (bundles GC+VM with in-place init/deinit) and four\neval assertion helpers (expectEval, expectEvalTrue, expectEvalBool,\nexpectEvalVoid). Migrate tests_ir.zig and tests_core_eval.zig as the\nfirst two files. Fix doc drift in src/CLAUDE.md (non-existent\nmakeTestGc, wrong test file count, vm.run→vm.eval) and\ntests/scheme/CLAUDE.md (removed deferred/, added compile/).\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-04T23:31:25+05:30",
          "tree_id": "e01a3ce79b9dcdade896abc2c5c4f785aa073f80",
          "url": "https://github.com/kaappi/kaappi/commit/db2f7dd32b75c4bda9124b7da88321408330e767"
        },
        "date": 1783190299694,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.487258,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.74244,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.899711,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.350768,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012686,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.213661,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.470815,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070688,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.690393,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.838174,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 10.111789,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.968537,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.381808,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.69763,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.047182,
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
          "id": "ec3209b4ee1ee20ef0cd3b452ab732054b431a65",
          "message": "Remove dead opcodes and extract CallFrame.frameWindow helper (#1052) (#1112)\n\nRemove get_local, set_local, close_upvalue from OpCode — never emitted\nby any compiler, get_local/set_local fell through to InvalidBytecode,\nclose_upvalue dispatched as a no-op. Bump bytecode cache VERSION 7→8.\n\nExtract the duplicated frame-register-window formula (locals_count or\n256) into CallFrame.frameWindow(), replacing 4 identical inline copies\nacross vm.zig, gc_collect.zig, vm_continuations.zig, and fiber.zig.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-04T23:31:56+05:30",
          "tree_id": "5537e996e76586575e02d0f0e57516319431465c",
          "url": "https://github.com/kaappi/kaappi/commit/ec3209b4ee1ee20ef0cd3b452ab732054b431a65"
        },
        "date": 1783190381400,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.987444,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.631207,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.944573,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.180827,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.014019,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.234361,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.470236,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.067436,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 13.53212,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.806112,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 11.086333,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.064279,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 9.068195,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.910851,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044725,
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
          "id": "f7ef22ccff4ed822ec808731e99876f4d8591d3b",
          "message": "Extract ratPartsVal helper to deduplicate rational num/den extraction (#1055) (#1115)\n\nThe 6 identical ~15-line blocks that extract numerator/denominator as\nValues from fixnum/bignum/rational in add, sub, mul, and div are replaced\nby a single ratPartsVal() helper returning a RatPartsVal struct. Net -69\nlines with identical behavior.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-04T23:41:29+05:30",
          "tree_id": "47b414f4ed947eba5494fdfbedf768305543f904",
          "url": "https://github.com/kaappi/kaappi/commit/f7ef22ccff4ed822ec808731e99876f4d8591d3b"
        },
        "date": 1783190777909,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 2.282679,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.040033,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.502815,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.914021,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.009037,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.145163,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.250536,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.03498,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 7.888099,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.930511,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 7.011569,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.681764,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 5.590755,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.184773,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.025882,
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
          "id": "eeb32cb8b364aaf469b89b8ab1287fd90a5e6689",
          "message": "Deduplicate file-reading and SLD-path resolution (#1064) (#1114)\n\nreporting.zig cloned vm_library's resolveLibraryPath with a smaller\nbuffer and hardcoded 18-path cap — if library search order ever changed,\ncoverage XML would silently resolve different files than the loader.\nFive private readFileContents copies existed across the interpreter tree\nwith inconsistent EINTR handling and max-size limits.\n\nAdd file_utils.zig with a shared readWholeFile(allocator, path, max)\nand make resolveLibraryPath pub. Delete all clones; thottam keeps its\nown copy (separate binary).\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-04T23:41:15+05:30",
          "tree_id": "dc9b1a93c5858bc40e7d5f30c2faf04996cb94f8",
          "url": "https://github.com/kaappi/kaappi/commit/eeb32cb8b364aaf469b89b8ab1287fd90a5e6689"
        },
        "date": 1783190819418,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.265155,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.958462,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.894952,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.154228,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012388,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.211185,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.469172,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070484,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.473388,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.807514,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.955299,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.953464,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.325887,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.725146,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045889,
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
          "id": "503118fa54e1627f27ad99527cf0fe5ead260059",
          "message": "Add native backend unit tests, .sbc equivalence tests, and fix OOM error paths (#1072) (#1117)\n\n- Add 28 golden .ll snapshot tests for the LLVM emitter (tests_native.zig),\n  covering preamble, constants, globals, calls, inline primitives, control\n  flow, definitions, lambda, let/let*, and begin\n- Add 6 .sbc serialize-deserialize-execute equivalence tests over\n  representative programs (arithmetic, conditionals, let, booleans, lists,\n  tail recursion)\n- Fix silent OOM corruption in runtime_exports.zig: kaappi_cons,\n  kaappi_create_native_closure, callPrimitive, and kaappi_gc_push_root\n  now abort with a message instead of returning 0\n- Enable LLVM native e2e tests on macOS CI\n- Wire tests/scheme/coverage/*-coverage.scm into the CI coverage job\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-04T23:43:59+05:30",
          "tree_id": "7d0ac36f29311a18528a196f6c7bd9057b75dd80",
          "url": "https://github.com/kaappi/kaappi/commit/503118fa54e1627f27ad99527cf0fe5ead260059"
        },
        "date": 1783191087271,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.307031,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.740736,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.890525,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.151278,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012555,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.211315,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.469695,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070716,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.459688,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.82058,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.982986,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.955819,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.282574,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.702256,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042764,
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
          "id": "374d7cb286be0a8d7e5d385b9e264f2846fd60e5",
          "message": "Replace inline state-restore copies with saveScope/restoreScope (#1070) (#1116)\n\ntryCompileNativeClosure had 7 inline copies of an 8-field restore block,\nand emitLambdaFunction used a 10-positional-parameter restoreState helper\ncalled 8 times. Any new emitter field had to be threaded through every\ncopy, and the two functions saved different field sets (closures omitted\nlocals/rest_param_alloca/rest_param_name).\n\nAdd a SavedScope struct capturing all 11 per-function fields with\nsaveScope()/restoreScope() methods on LLVMEmitter. Both functions now\nuse `defer self.restoreScope(saved)` in a block scope, eliminating all\nmanual restore sites and fixing the field-set asymmetry.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-04T23:46:11+05:30",
          "tree_id": "c2504bb43d6a583b17cd4d4c81ef37c18cabe6c6",
          "url": "https://github.com/kaappi/kaappi/commit/374d7cb286be0a8d7e5d385b9e264f2846fd60e5"
        },
        "date": 1783191333672,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.009079,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.490958,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.926781,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.215402,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.013588,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.234572,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.467622,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068486,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 13.404773,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.816937,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 11.082821,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.05774,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 9.060615,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.843902,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.04412,
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
          "id": "9fc5ecde5cf823be697efd7de9ea3906724cdf26",
          "message": "Extract shared error reporting helpers into toplevel_driver.zig (#1061) (#1118)\n\nThe same read→compile→execute→report error formatting was duplicated\nacross 5 call sites (runFile, runStdin, disassembleFile, compileFile in\nmain.zig, evalInputInner in repl.zig).  The stack trace printer was\nbyte-identical in 3 places, and the getErrorDetail→format→reset pattern\nappeared ~10 times.\n\nAdd src/toplevel_driver.zig with 6 public helpers:\n- reportReadError, reportCompileError, reportRuntimeError\n- vmErrorLocation, printStackTrace, printSourceSnippet\n\nEach call site keeps its own loop and control flow but delegates error\nformatting to the shared helpers.  Net -85 lines, all error message\nformats preserved (verified by tests/scheme/errors/*.sh).\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-04T23:57:50+05:30",
          "tree_id": "7dceafbaa0cb157aae24dd3ea3db86759e142fda",
          "url": "https://github.com/kaappi/kaappi/commit/9fc5ecde5cf823be697efd7de9ea3906724cdf26"
        },
        "date": 1783191576322,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.026865,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.421491,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.924124,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.240871,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.013766,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.234655,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.473205,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.067596,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 13.441908,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.817165,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 11.096568,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.062432,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 9.133368,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.917993,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045638,
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
          "id": "4934610328d60c867dedc327cb94b68bbc66e5c3",
          "message": "Break memory→vm circular dependency, add finishAlloc helper (#1050) (#1119)\n\nMove CallFrame, ExceptionHandler, and capacity constants from vm.zig\nto types.zig so that memory.zig and gc_collect.zig no longer import\nvm.zig — breaking the memory↔vm circular dependency through fiber.\n\nAdd GC.finishAlloc() to consolidate the bytes_allocated/profileAlloc/\ntrackObject bookkeeping repeated in every allocator (~70 lines saved).\nThis also fixes three profileAlloc size mismatches:\n- allocNativeClosure: was missing upvalues size\n- allocContinuation: was missing profileAlloc call entirely\n- allocHashTable: was using initial_capacity instead of rounded cap\n\nDelete unused primitives_hashtable.zig import from memory.zig.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-05T00:04:46+05:30",
          "tree_id": "b713b820e9dbcb18dd88c4c2915fed1502ec1af2",
          "url": "https://github.com/kaappi/kaappi/commit/4934610328d60c867dedc327cb94b68bbc66e5c3"
        },
        "date": 1783191660885,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.248561,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.787249,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.931415,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.182419,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012378,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.211357,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.464016,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070356,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.484502,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.815194,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.963211,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.958039,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.255029,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.668237,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042412,
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
          "id": "1a63d356851bd40bf38e9e74a9d3b56aeca2cc7d",
          "message": "Add compileDesugared() helper to centralize sexpr rooting discipline (#1044) (#1121)\n\nSeven form compilers repeated the same pushRoot/compileExpr/popRoot\npattern after building desugared S-expressions. Extract a single\ncompileDesugared() method on Compiler that owns the rooting, replacing\n6 call sites. This closes the surface where the next #1010-class GC\nbug could appear in new desugaring forms.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-05T06:18:39+05:30",
          "tree_id": "4d4d23e6b6fde193e114d8f42b856ada36b5c0d5",
          "url": "https://github.com/kaappi/kaappi/commit/1a63d356851bd40bf38e9e74a9d3b56aeca2cc7d"
        },
        "date": 1783214034266,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.952224,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.821491,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.979703,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.183009,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.014522,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.234905,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.46439,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.067982,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 13.772014,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.805236,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 11.141411,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.072611,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 9.129728,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.686406,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044339,
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
          "id": "5a522f2ff0f04a0ec84adcade19f42b63c2263b9",
          "message": "Generate native backend declares from shared table, add comptime drift test (#1069) (#1120)\n\nReplace 21 hand-mirrored LLVM IR declare lines in emitPreamble and the\nif-else chains in tryEmitInlineBinary/tryEmitInlineUnary with a single\nshared table in native_decls.zig. A comptime block validates every table\nentry against the actual Zig signatures in runtime_exports.zig using\n@typeInfo reflection — a signature mismatch now fails the build instead\nof silently producing UB at link time.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-05T06:18:24+05:30",
          "tree_id": "fa22e143e768050ecb2a315828ec5a5f1c9b5338",
          "url": "https://github.com/kaappi/kaappi/commit/5a522f2ff0f04a0ec84adcade19f42b63c2263b9"
        },
        "date": 1783214061474,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.354243,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.788757,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.939169,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.210013,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012553,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.212236,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.474763,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070687,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.453853,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.838024,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.982312,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.957889,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.362391,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.698379,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042525,
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
          "id": "d88137b6999d65f8a4b8b8f9244816583d84c5b5",
          "message": "Extract ir.lowerAndOptimize() to deduplicate the IR pipeline (#1122)\n\nThe 9-step sequence (lower → 3 analysis passes → 5 optimization passes)\nwas copy-pasted across 12 call sites in 5 files. A single entry point\nensures the bytecode and native backends stay in sync and makes adding\nnew optimization passes a one-line change.\n\nAlso fixes a latent pass-order bug in lowerSingleExprTail where\nidentifyPrimitives/markConstants ran before markTailPositions, unlike\nevery other site.\n\nCloses #1037\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-05T06:18:55+05:30",
          "tree_id": "1f8073e17211fe951413994beea1e395dae4a680",
          "url": "https://github.com/kaappi/kaappi/commit/d88137b6999d65f8a4b8b8f9244816583d84c5b5"
        },
        "date": 1783214261993,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.893122,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.699429,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.87676,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.881282,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012652,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.198022,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.428425,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.06581,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.024333,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.637818,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.370901,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.88868,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 7.69165,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.966653,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.040123,
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
          "id": "677a3322e737b1d591341ec1aae458b5fe2803c2",
          "message": "Extract CLI parsing into src/cli.zig with table-driven flag parser (#1062) (#1123)\n\nThree divergent flag parsers in mainImpl (sandbox pre-scan, standalone\nembedded-bytecode parser, full flag loop) are replaced by a single\ntable-driven parser in cli.zig consulted by all three call sites.\n\nAdding a new flag now requires one table entry instead of updating\nthree hand-written if/else chains plus completions.zig plus printUsage.\n\nAlso fixes: --profile-json now appears in --help output (was\nundocumented), dead sandbox_mode local removed, standalone binaries\nnow handle all flags (--timeout, --max-memory, --lib-path, etc. were\nsilently swallowed before).\n\nmain.zig: 1155 → 901 lines. cli.zig: 504 lines (incl. 20 unit tests).\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-05T06:19:14+05:30",
          "tree_id": "0bf7b12c205b6326f2174c947739b841edcf96d1",
          "url": "https://github.com/kaappi/kaappi/commit/677a3322e737b1d591341ec1aae458b5fe2803c2"
        },
        "date": 1783214531852,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.307863,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.196631,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.936901,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.202492,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012792,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.212768,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.462906,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070505,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.570078,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.812553,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.999057,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.971039,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.338814,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.749643,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.04383,
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
          "id": "c7dbbc1638a57a42449c2d85f36aae7dcd06cd01",
          "message": "GC safety by construction: arg_roots, infallible pushRoot, stress mode (#1045) (#1125)\n\nEliminate the recurring \"unrooted fresh value\" bug class structurally:\n\n1. arg_roots — allocXxx functions that take Value arguments (allocPair,\n   allocErrorObject, allocRational, etc.) now root them in a fixed [4]Value\n   buffer before maybeCollect(). markRoots traces this buffer first.\n\n2. Infallible pushRoot — replace the growable ArrayList with a fixed\n   [1024]*Value buffer. pushRoot is now void (panics on overflow),\n   removing ~181 catch-return / try noise sites across 35 files.\n\n3. GC stress mode — -Dgc-stress=true forces collect() on every\n   maybeCollect() call regardless of threshold growth. In Debug builds,\n   freed objects are poisoned with 0xAA via poisonAndDestroy() to surface\n   use-after-free immediately.\n\nAll 602 unit tests and 1702 Scheme tests (including 1395 R7RS) pass.\nStress mode exposes pre-existing unrooted-value bugs as expected.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-05T06:46:36+05:30",
          "tree_id": "d0d6fd442d58050da787727bad7c1c19e5987e44",
          "url": "https://github.com/kaappi/kaappi/commit/c7dbbc1638a57a42449c2d85f36aae7dcd06cd01"
        },
        "date": 1783215615816,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.304436,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.887075,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.915126,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.14513,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012522,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.211799,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.466692,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070759,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.43773,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.835396,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.970582,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.951888,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.300162,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.705734,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043015,
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
          "id": "88720ac566abb3e404e7027fb7e3e4a4a9887b22",
          "message": "Delete dead identifyPrimitives/markConstants IR passes (#1041) (#1127)\n\nThe is_primitive_call, primitive_name, and is_constant annotations were\nproduced by ~140 lines of analysis passes but consumed by no backend:\ncompiler_ir.zig explicitly discarded is_primitive_call, foldConstants\nre-derived everything from node tags, and is_constant had zero downstream\nreaders. Remove both passes, their annotation fields, the dead parameter\nin compileCallFromIR, and the test-only assertions. Keep the primitives\nlist and isKnownGlobal (used by the LLVM backend) and the live is_tail\nand source_line annotations.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-05T07:33:02+05:30",
          "tree_id": "8296f4e4894a8ede8e08a1a0dbec62bb82001ba7",
          "url": "https://github.com/kaappi/kaappi/commit/88720ac566abb3e404e7027fb7e3e4a4a9887b22"
        },
        "date": 1783218463703,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.907944,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.86476,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.948455,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.199248,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.013722,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.234867,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.47051,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068089,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 13.445745,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.820031,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 11.107483,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.069214,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 9.124251,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.861821,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044143,
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
          "id": "a7d8e7f1a69d10e35c84ac1d866f81bb59aeb8cf",
          "message": "Centralize LLVM native/eval-fallback boundary in one comptime table (#1068) (#1126)\n\nThe native-vs-fallback classification was duplicated in four places across\ntwo files. A single `llvm_node_table` in ir.zig now drives all four sites:\nemitNode dispatch, emitSexprEval args/form-name extraction,\nisEvalFallbackForm string matching, and nodeHasFreeVars/collectNodeFreeVars.\nAdding a new NodeTag without classifying it is now a compile error.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-05T07:33:58+05:30",
          "tree_id": "0caac031f4ae8caaf9b79b71ebd925ea7dd79dd8",
          "url": "https://github.com/kaappi/kaappi/commit/a7d8e7f1a69d10e35c84ac1d866f81bb59aeb8cf"
        },
        "date": 1783218653659,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.327973,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.813661,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.916237,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.136581,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012863,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.211891,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.468046,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070727,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.555891,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.834862,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.957044,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.960042,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.316815,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.743447,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044855,
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
          "id": "cd1e307f7d7917078a4bd2dc05b5b6930cbf9d13",
          "message": "Unify VMError/PrimitiveError and collapse 8 inline error switches (#1046) (#1128)\n\nDefine one KaappiError in dependency-free src/errors.zig; alias VMError and\nPrimitiveError to it. Delete mapVMError (now identity) and its 39 call sites.\nReplace 8 drifted inline anyerror→VMError switches with one mapNativeError()\nthat owns detail-defaulting for TypeError, IndexOutOfBounds, InvalidArgument.\n\nFixes three drift bugs: CALL_NATIVE_VARIADIC path gains detail-defaulting,\ncallHandler/callThunk/callWithArgs handle all 16 error variants (were silently\nmapping 7-9 to InvalidBytecode), and InvalidArgument detail respects the\nlast_error_detail_len guard.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-05T07:41:06+05:30",
          "tree_id": "5546a28daee93f56b3003a61288e81f41391a77a",
          "url": "https://github.com/kaappi/kaappi/commit/cd1e307f7d7917078a4bd2dc05b5b6930cbf9d13"
        },
        "date": 1783218944478,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.229931,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.858833,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.928423,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.155491,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.01261,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.211745,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.466643,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070293,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.568875,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.815083,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.988437,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.953934,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.304834,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.715072,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042529,
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
          "id": "9c84a769cd88395642f00c9a2643ecf666bf6e1e",
          "message": "Extract macro-expansion machinery into compiler_macro.zig (#1043) (#1129)\n\nMove macro expansion, definition forms (define-syntax, let-syntax,\nletrec-syntax), syntax-rules parsing, and hygiene free-ref collection\nfrom compiler.zig and compiler_passthrough.zig into a new\ncompiler_macro.zig module. Consolidate duplicated tables:\n\n- stripHygienicPrefix (5 copies → 1 in types.zig)\n- isContinuationBarrier (3 copies → 1 in types.zig)\n\ncompiler.zig drops from 1254 to 889 lines; compileForm() shrinks from\n269 to ~95 lines. compiler_passthrough.zig drops from 562 to 341 lines\nand now contains only passthrough compilation (quote/if/call).\n\nPure refactoring — no behavioral changes.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-05T07:55:39+05:30",
          "tree_id": "9ca9d7aedb8fa7dab9c4da039ea0b14ae567eb2a",
          "url": "https://github.com/kaappi/kaappi/commit/9c84a769cd88395642f00c9a2643ecf666bf6e1e"
        },
        "date": 1783219841800,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.913856,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 10.154161,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.96621,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.168928,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.013907,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.234737,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.466386,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.067823,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 13.713192,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.817973,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 11.130926,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.092171,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 9.23761,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.912339,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045637,
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
          "id": "7ad56d23246e7c103c1e30e695c7af8474dcd36e",
          "message": "Delete ir_emitter.zig — duplicate emitter kept alive by obsolete parity tests (#1039) (#1130)\n\nThe standalone Emitter duplicated compiler_ir.zig's emission nearly\nbyte-for-byte, with copy drift (addConstant off-by-one at 65535 vs\n65536). Its only consumer was 11 Stage-1 bytecode-parity tests whose\npurpose is obsolete now that Compiler.compile() itself goes through IR.\n\n- Delete src/ir_emitter.zig (282 lines)\n- Convert all 11 parity tests to behavioral tests with expected values\n- Remove dead helpers (compileViaIR, compileViaDirectCompiler,\n  expectBytecodeParity)\n- Drop CompileError.NotImplemented (only used by deleted emitter)\n- Remove re-export from ir.zig and import from main.zig\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-05T08:59:05+05:30",
          "tree_id": "54a4b0dc289d96b480623c455e1e7200a6d1bf1c",
          "url": "https://github.com/kaappi/kaappi/commit/7ad56d23246e7c103c1e30e695c7af8474dcd36e"
        },
        "date": 1783223508418,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.277544,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.899919,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.915749,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.187928,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.0124,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.211453,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.467259,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070968,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.531141,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.825374,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 10.007991,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.958473,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.39564,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.740552,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.046942,
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
          "id": "baf276b9ffde181939239ccb82630cdef01306d7",
          "message": "Consolidate writeToFd/writeStdout/writeStderr into reporting.zig (#1067) (#1131)\n\nNine copies of the write-with-retry loop existed across the interpreter,\nwith thottam.zig missing EINTR handling entirely. Consolidate to one pub\nimplementation in reporting.zig, re-exported through vm.zig and\nprimitives_io.zig for backward compat. Fix thottam's own copy (separate\nbinary) to retry on EINTR. Also replace an inline write loop in\nreporting.zig's XML coverage output with a writeToFd call.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-05T08:59:19+05:30",
          "tree_id": "9dc6bc9f9c3a11c7c2c864f6c94a438371e38491",
          "url": "https://github.com/kaappi/kaappi/commit/baf276b9ffde181939239ccb82630cdef01306d7"
        },
        "date": 1783223520379,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.937268,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.959489,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.957216,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.215701,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.013817,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.235287,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.467778,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.067686,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 13.493247,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.814305,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 11.12702,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.067095,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 9.118356,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.762608,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044712,
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
          "id": "4a9ccba03fa888b2e00f2b5b54c4e5011526280f",
          "message": "Add RootedSlot/RootedScope helpers, migrate 36 manual extra_roots sites (#1054) (#1132)\n\nReplace fragile manual gc.extra_roots index-poke patterns with two small\nhelpers on GC: rootedSlot(val) returns a RootedSlot with get/set/release,\nand rootedScope() returns a RootedScope that shrinks back on release.\n\nMigrated all 31 index-poke sites in primitives_arithmetic.zig and\nprimitives_numeric.zig from raw items[len-N] to named slot handles,\neliminating a class of off-by-one rooting bugs. Migrated 9 manual\nsnapshot/shrinkRetainingCapacity sites in primitives_vector.zig and\nprimitives_srfi1.zig to rootedScope().\n\nVerified: 1702/1702 Scheme tests, arithmetic+numeric audit, unit tests,\nand GC stress mode all pass.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-05T08:59:37+05:30",
          "tree_id": "c41a58ad11edeaefff1d1d11bbe5274501d05207",
          "url": "https://github.com/kaappi/kaappi/commit/4a9ccba03fa888b2e00f2b5b54c4e5011526280f"
        },
        "date": 1783224240385,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.956287,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.458297,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.945198,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.168642,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.013616,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.234917,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.467529,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.06894,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 13.464958,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.816386,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 11.119498,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.06145,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 9.103443,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.797722,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.046331,
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
          "id": "c8cd856c3b22d099f94fb6eaefd285bdd4ab0c6e",
          "message": "Replace registration/export bookkeeping with comptime spec tables (#1053) (#1133)\n\n* Replace registration/export bookkeeping with comptime spec tables (#1053)\n\nEach primitive is now declared once as a PrimSpec with name, function\npointer, arity, library membership (LibSet), and sandbox/WASM flags.\nBoth registerAll and registerStandardLibraries consume the same\nall_specs array, eliminating the 3-way bookkeeping between reg() calls,\nname arrays, and sandbox variant functions.\n\n- Add Lib enum (24 libraries), LibSet, PrimSpec types to primitives.zig\n- Convert all 21 primitives files to pub const specs arrays\n- Derive registerAll/registerSandboxed from all_specs iteration\n- Derive registerStandardLibraries/registerSandboxedLibraries from specs\n- Delete 25 hand-maintained name arrays from library.zig (~400 lines)\n- Delete registerIOSandboxed, registerR7RSSandboxed variants\n- Add comptime collision and orphan-spec checks\n- Update drift test to iterate all_specs\n\nNet: -787 lines. All 1702 tests pass (307 Scheme + 1395 R7RS).\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Gate WASM-unavailable module specs behind is_wasm\n\nThe WASM build (single-threaded, no dlopen) fails when the compiler\nresolves function pointers in srfi18/filesystem/ffi specs. Gate these\nmodules with `if (is_wasm) no_specs` so the compiler never sees their\nfunction bodies on wasm32-wasi.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-05T09:27:03+05:30",
          "tree_id": "3ade7ec34c0076aaffa0482c06d7d3dde434909e",
          "url": "https://github.com/kaappi/kaappi/commit/c8cd856c3b22d099f94fb6eaefd285bdd4ab0c6e"
        },
        "date": 1783225245793,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.295489,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.795561,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.909097,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.918995,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012592,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.21144,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.474011,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069803,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.369555,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.844032,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.957627,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.978337,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.290325,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.701322,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043618,
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
          "id": "0d91e8db70beddda42091853a68ec2672da3856c",
          "message": "Collapse 17 SexprArgs NodeTag variants into .sexpr_form with FormKind (#1040) (#1134)\n\nReplace 17 identical SexprArgs NodeTag variants with a single .sexpr_form\ntag carrying a FormKind discriminant. Replace string-comparison chains in\nlowerFormWithMacros and isSpecialForm with StaticStringMap lookups. Adding\na new delegating compiler form now takes ~4 edits instead of 8+.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-05T10:38:06+05:30",
          "tree_id": "db492030693c959a60aefcc17904e7e44e8d627f",
          "url": "https://github.com/kaappi/kaappi/commit/0d91e8db70beddda42091853a68ec2672da3856c"
        },
        "date": 1783229394692,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.348399,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.73238,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.895534,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.836651,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012516,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.211747,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.476449,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070648,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.382618,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.800922,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.965699,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.954128,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.257149,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.690229,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042814,
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
          "id": "521cf6e1c4b13f37f69abc63db2f628a3f772f89",
          "message": "Add expect* typed accessors and eliminate bare TypeErrors (#1057) (#1135)\n\nEvery bare PrimitiveError.TypeError now carries a \"type error in\n'proc': expected X, got Y\" message, matching the quality already\nprovided by caddr/car/vector-ref.  Six new typed accessors\n(expectPair, expectVector, expectFixnum, expectChar, expectString,\nexpectPort) combine the type check and cast into one call.\n\n- primitives.zig: add 6 expect* accessors, fix 28 bare TypeErrors\n- primitives_arithmetic.zig: fix 19 bare TypeErrors, 2 dead arity→assert\n- primitives_string.zig: parameterize getStringSlice with proc name,\n  fix 2 dead arity→assert\n- primitives_string_ext.zig: update ~35 getStringSlice callsites with\n  proc names, fix 4 bare TypeErrors\n- primitives_char.zig: replace private getStringSlice with expectString\n- primitives_ffi.zig: fix 15 bare TypeErrors\n- primitives_io.zig: fix 5 bare TypeErrors\n- primitives_numeric.zig: fix 3 bare TypeErrors\n- primitives_r7rs.zig: fix 3 bare TypeErrors\n- primitives_lazy.zig: fix 1 bare TypeError\n- primitives_list.zig: 2 dead arity→assert\n- primitives_srfi1.zig: 13 dead arity→assert\n- vm_calls.zig: add FFI error detail at 2 call sites\n- error-format.sh: 12 new assertions for consistent error messages\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-05T05:20:54Z",
          "tree_id": "7dcefba500c31fdb814113e8a91e57cb63df7ffe",
          "url": "https://github.com/kaappi/kaappi/commit/521cf6e1c4b13f37f69abc63db2f628a3f772f89"
        },
        "date": 1783230282371,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.330075,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.869357,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.951425,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.930424,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012574,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.211683,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.472877,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070514,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.365805,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.825743,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.975447,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.970532,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.296831,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.741761,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042685,
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
          "id": "803b62a8c816fc0c58d9ab4118debbfdfa3fb8a2",
          "message": "Route sub-expression compilation through the IR pipeline (#1038) (#1136)\n\nAdd compileExprViaIR bridge so sub-expressions compiled by legacy form\ncompilers (let, do, cond, etc.) re-enter the IR pipeline and receive\noptimization passes (constant folding, dead branch elimination, boolean\nsimplification). Converts 48 compileExpr call sites across 7 compiler\nfiles; keeps compileExpr for the passthrough→macro expansion path.\n\nAlso fixes three bugs exposed by the routing change:\n- IR macro lookup used stripped hygienic prefix, missing macros defined\n  under renamed identifiers in nested let-syntax\n- compileSetFromIR lacked is_global_alias write-through handling,\n  causing macro template set! to silently lose global updates\n- Five IR optimizer passes used fixed 256-element buffers, panicking\n  on begin/and/or forms with >256 children\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-05T12:18:06+05:30",
          "tree_id": "86ddf4b3e83b9c767c1a404c6acbe28c295e83d1",
          "url": "https://github.com/kaappi/kaappi/commit/803b62a8c816fc0c58d9ab4118debbfdfa3fb8a2"
        },
        "date": 1783235516126,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.328156,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.025239,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.926949,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.058737,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012464,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.211231,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.470195,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.06964,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.372899,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.823011,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.964273,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.957214,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.369952,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.720767,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042842,
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
          "id": "b2317e8c37b3993dcc094187c6a37dc014e00ddc",
          "message": "Add systematic R7RS conformance and SRFI audit strategy\n\nPhased plan for auditing all 21 primitives files, 72 SRFIs, and R7RS\nspec coverage gaps. Sized for parallel Claude Code sessions (~33 units,\n~4hr wall-clock at 4-way parallelism). Includes session protocol,\nprogress tracker, issue templates, and community test resources.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-05T12:20:18+05:30",
          "tree_id": "2b94ee495f826a6eca57e48864b38da6f2b78e0f",
          "url": "https://github.com/kaappi/kaappi/commit/b2317e8c37b3993dcc094187c6a37dc014e00ddc"
        },
        "date": 1783235719127,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.326435,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.597324,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.934001,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.056906,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012369,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.21135,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.471674,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069594,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.383114,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.824523,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.943872,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.955123,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.30077,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.704861,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042785,
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
          "id": "4ecde30b4f047f38b1d3ce0d8ed8eb169ed35dce",
          "message": "Add audit-baseline.sh and record Phase 0 baseline results (#1138)\n\nPhase 0 of the audit campaign (docs/audit-strategy.md): the committed\nbaseline script reruns unit tests, the R7RS suite, run-all.sh, and each\nSRFI file individually. The script uses a portable timeout helper\nbecause stock macOS lacks GNU timeout — this footgun is now documented\nin the strategy doc.\n\nBaseline at b2317e8 is fully green (unit tests pass, R7RS suite 0 fail\nin every section, run-all.sh 1702 pass / 0 fail, all 35 SRFI files\npass), so no issues were filed. Tracking issue: #1137.\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-05T13:15:55+05:30",
          "tree_id": "0a05a7a277eae0368bcd8796f892bc2d554122b7",
          "url": "https://github.com/kaappi/kaappi/commit/4ecde30b4f047f38b1d3ce0d8ed8eb169ed35dce"
        },
        "date": 1783238816950,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.328045,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.847616,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.921948,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.067876,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012357,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.211616,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.477825,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069877,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.349987,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.820543,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.950489,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.957699,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.340882,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.768056,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043465,
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
          "id": "7e2153a83437f9dfcf958a06523e8af1c5e742a3",
          "message": "Add R7RS 6.1-6.5 conformance gap tests (audit Phase 1B) (#1150)\n\n40 assertions covering spec corners the R7RS suite misses: eqv? on\nmixed exactness, negative zero, bignums, and records; equal?\ntermination on circular lists, circular vectors, and mixed\npair/vector cycles; number->string/string->number radix round-trips\nand prefix combinations; #true/#false long literals; append identity\nand structure sharing; list-ref on circular lists; and write/read\nsymbol round-trips through pipe notation.\n\nAll pass - no bugs found in these sections. Part of the #1137 audit\ncampaign.\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-05T13:41:20+05:30",
          "tree_id": "6763ba1e59605076097283443b23ed724f3d2ccb",
          "url": "https://github.com/kaappi/kaappi/commit/7e2153a83437f9dfcf958a06523e8af1c5e742a3"
        },
        "date": 1783240247160,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.336214,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.210039,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.954386,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.081163,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.013146,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.211795,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.470888,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069627,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.469611,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.824134,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.953027,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.961651,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.349424,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.5977,
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
          "id": "5ae7e1b799878a91cc0bc927700860a1eb0be9ab",
          "message": "Add R7RS 4.1-4.3 and 5.6 conformance gap tests (audit Phase 1A) (#1143)\n\n34 new assertions covering spec requirements the R7RS suite misses:\nunquoted self-evaluating vectors/bytevectors, include/include-ci, cond\ntest-only clauses, multiple values through and/or, let* duplicate\nbindings, let-values formals variants and init scoping, do with omitted\nstep, expression-level cond-expand, parameterize converter semantics,\nimproper quasiquote templates, constant patterns, literal hygiene, and\nlet-syntax vs letrec-syntax keyword scoping. Library-system tests (5.6)\ncover numeric name components, export rename, nested import sets,\nimport merging, and single instantiation - all passing.\n\nThree assertions are disabled with FAIL markers pending fixes:\n#1139 (literal matching ignores lexical bindings), #1140 (let-syntax\nsibling keyword scoping), #1141 (include-ci does not fold case).\nsyntax-error diagnostics filed as #1142 (needs an error-format.sh\ncase, no in-file test). Part of the #1137 audit campaign.\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-05T13:37:04+05:30",
          "tree_id": "8103afefc280b19198968b0ed6a4ee5b4f3916de",
          "url": "https://github.com/kaappi/kaappi/commit/5ae7e1b799878a91cc0bc927700860a1eb0be9ab"
        },
        "date": 1783240277273,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.575686,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.298351,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.777686,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.356718,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012969,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.216157,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.386037,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.058533,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.636149,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.525649,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 10.312462,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.004396,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.507119,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.956265,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.037478,
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
          "id": "1a9e5aea40a44e487e063c28d264c90d15b96710",
          "message": "Add R7RS 6.6-6.9 conformance gap tests (audit Phase 1C) (#1151)\n\n43 assertions covering spec corners the R7RS suite misses: digit-value\nfor non-ASCII decimal digits, char classification against Unicode\nproperties, string literal escapes and line continuation, full Unicode\nstring casing (length-changing sharp-s), -ci comparison via foldcase,\noverlap guarantees for string/vector/bytevector-copy!, ranged\nfill/copy/conversion variants, and UTF-8 conversions where string\nindices are codepoints but bytevector indices are bytes.\n\nFour assertions disabled with FAIL: #1145 markers - char-upper-case?/\nlower-case?/alphabetic? classify titlecase (U+01C5, U+1FBC), sharp-s,\nand ordinal indicators (U+00AA/BA) wrongly because classification is\nderived from simple case mappings instead of Unicode Uppercase/\nLowercase/Alphabetic properties. Part of the #1137 audit campaign.\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-05T13:42:08+05:30",
          "tree_id": "bf43a20781048a513ec6789b4891570cd14839a0",
          "url": "https://github.com/kaappi/kaappi/commit/1a9e5aea40a44e487e063c28d264c90d15b96710"
        },
        "date": 1783240911442,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.310345,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.587509,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.921639,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.070202,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012925,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.212464,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.472477,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069983,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.382856,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.831192,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.950347,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.953224,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.311738,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.533107,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042677,
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
          "id": "3422197e9d72a1dc970932bca35f705035446bf7",
          "message": "Add R7RS 6.10-6.14 conformance gap tests (audit Phase 1D) (#1152)\n\n30 assertions covering spec corners the R7RS suite misses:\nshortest-list termination for map/vector-map/string-map, apply with\nspread arguments, call-with-values spec examples, raise-continuable\nhandler-value semantics, error-object accessors, file-error?/\nread-error? predicates, eval environment isolation and import-set\nrestriction, cyclic write with datum labels, read-line CR/CRLF/LF\nhandling, peek-char/peek-u8 non-advancement, port lifecycle\npredicates, parameterized current-output-port, bytevector ports,\nranged write-string, and system interface types.\n\nTwo assertions disabled with FAIL: #1147 markers - define/set! into\nan immutable (environment ...) silently succeeds instead of\nsignaling an error (isolation itself is correct). Deep continuation\ninteractions are deferred to Phase 4B. Part of the #1137 audit\ncampaign.\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-05T08:34:45Z",
          "tree_id": "907997e57d5d2c9db31bc82b0f62c7e22c6a21bc",
          "url": "https://github.com/kaappi/kaappi/commit/3422197e9d72a1dc970932bca35f705035446bf7"
        },
        "date": 1783241745295,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.278111,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.700162,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.920778,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.083317,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012552,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.211234,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.472143,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069835,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.336581,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.839048,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.998511,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.952429,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.290279,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.677878,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043055,
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
          "id": "d270c399d249c6be32226a11d6aad979f82f6505",
          "message": "Phase 2.1: SRFI-18 primitives audit tests (#1157)\n\n* Add primitives_srfi18.zig audit tests (audit Phase 2.1)\n\n73 assertions covering the SRFI-18 surface beyond the existing\nsrfi18*.scm suite: type-error catchability for every accessor,\nthread lifecycle rules (double-start, self-join, timeout-val,\njoin-timeout exceptions), thread-sleep! edge cases (zero, negative,\nrational, past time objects), mutex state transitions, condvar\nno-waiter signal/broadcast, time conversion round-trips, and\nexception predicate discrimination.\n\nFour assertions disabled with FAIL markers:\n- #1153 mutex-lock! with timeout on a locked mutex steals the lock\n  (and the same scheduler-dry bug makes timed condvar waits in\n  mutex-unlock! return #t immediately)\n- #1154 explicit #f thread argument assigns current thread as owner\n- #1155 make-thread rejects native procedures\n\nAlso filed #1156: this file crashes with a deterministic SIGSEGV in\nminor-GC marking under -Dgc-stress=true (stale root after thread\nstart/join cycles); it passes 73/0 on the default build. Part of\nthe #1137 audit campaign.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n* Check off Phase 2.1 in the audit tracker\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-05T08:40:06Z",
          "tree_id": "2c5bf445b824abcf413b18fec46ecaf583580b09",
          "url": "https://github.com/kaappi/kaappi/commit/d270c399d249c6be32226a11d6aad979f82f6505"
        },
        "date": 1783242066376,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.321337,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.741155,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.936911,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.058831,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012572,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.211579,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.469972,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070111,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.387336,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.821625,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.948298,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.972851,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.31276,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.699261,
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
          "id": "83718b6706d4c1bcb47267b9ce15ef19bec300e2",
          "message": "Phases 2.2-2.4: SRFI-13, char, and IO primitives audit tests (#1160)\n\n* Add primitives_string_ext.zig audit tests (audit Phase 2.2)\n\n84 assertions covering the SRFI-13 surface: codepoint indexing in\ncontains/take/reverse/pad, left-only trim semantics, pad truncation\ndirections, criterion-first filter/delete, every/any return values,\nunfold/unfold-right base and make-final placement, callback error\npropagation, and type-error catchability. gc-stress clean.\n\nSix assertions disabled with FAIL markers: #825 (string-join grammar\nstill ignored - reopened), #826 (default trim misses Unicode\nwhitespace - reopened), #1158 (string-contains ignores start2/end2,\nstring-replace rejects them), #1159 (wrong-typed optional args\nsilently ignored). Part of the #1137 audit campaign.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n* Add primitives_char and primitives_io audit tests (Phases 2.3, 2.4)\n\nPhase 2.3 (primitives_char.zig, 59 assertions): no new bugs. The\nhard Unicode paths all conform - contextual final-sigma downcasing,\nligature expansion in string-upcase, Cherokee case pairs, sigma\nfoldcase equivalence, Numeric_Type=Decimal discrimination in\nchar-numeric?/digit-value. Three property-based classification\nassertions stay disabled pending #1145 (filed in Phase 1C).\n\nPhase 2.4 (primitives_io.zig, 49 assertions): no bugs. Closed-port\nerrors, read-string boundaries, write/write-shared/write-simple\ndatum-label semantics, write escape behavior, textual and binary\nfile round-trips, and file-error discrimination all conform.\n\nChecks off 2.2-2.4 in the tracker (2.2's test file is the previous\ncommit on this branch). Part of the #1137 audit campaign.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-05T08:53:24Z",
          "tree_id": "b1d397955f6afc5eae2e15d8c9d502a473205943",
          "url": "https://github.com/kaappi/kaappi/commit/83718b6706d4c1bcb47267b9ce15ef19bec300e2"
        },
        "date": 1783242892946,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.338501,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.543303,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.923249,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.080603,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012516,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.211345,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.471181,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069609,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.367369,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.823383,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.946592,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.948013,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.344881,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.65661,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042739,
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
          "id": "5b5a4e8f6c15dcd223bbbb707e5e4f852adc0055",
          "message": "Add primitives_filesystem.zig audit tests (audit Phase 2.5) (#1165)\n\n65 assertions covering the SRFI-170 surface: directory-files dotfile\nhandling, file-info follow? (stat vs lstat) semantics, symlink and\nhard-link operations, create-directory permission bits, rename\noverwrite, truncate, fifo creation, self-chown, temp files, directory\nstreams, umask round-trip, user/group database dispatch, environment\nvariable write-side, and error catchability. gc-stress clean. Also\nserves as Phase 3.1's SRFI-170 coverage per the strategy doc.\n\nThree assertions disabled with FAIL markers:\n- #1161 group-info by name returns gid 0 (root cause is an upstream\n  Zig 0.16 stdlib misdeclaration: std.c.getgrnam returns ?*passwd)\n- #1162 posix-time/monotonic-time return bare fixnums, not SRFI-19\n  time objects\n- #1163 owner/unchanged and group/unchanged constants not exported\n\nFound in passing and filed as #1164: (srfi 60) exports only the log*\nnames; the bitwise-* aliases and second-tier procedures are missing.\nPart of the #1137 audit campaign.\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-05T09:20:04Z",
          "tree_id": "f4492b0184bf7b7768878f4a22954698af695fd8",
          "url": "https://github.com/kaappi/kaappi/commit/5b5a4e8f6c15dcd223bbbb707e5e4f852adc0055"
        },
        "date": 1783244380312,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.314755,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.947184,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.92825,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.081141,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012573,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.211436,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.471514,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069643,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.41174,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.820349,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.945805,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.955383,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.301048,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.677498,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042249,
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
          "id": "f271b4b0d8363e04dfe521cd7a25eeb78d69b574",
          "message": "Add primitives_srfi1.zig audit tests (audit Phase 2.6) (#1167)\n\n105 assertions covering the SRFI-1 surface beyond srfi1*.scm: fold\nfamily argument order and multi-list forms, reduce ridentity\nsemantics, pair-fold tail walking, unfold/unfold-right with optional\ntails, iota variants, dotted-list handling in take/drop, two-value\nreturns from span/break/partition/split-at/car+cdr/unzip2,\ndelete-duplicates first-kept ordering with custom equality, lset\noperation result shapes, length+ on circular lists, structure\npredicates, alist pair copying, mapping variants, callback error\npropagation, and type-error catchability. gc-stress clean.\n\nTwo assertions disabled with FAIL markers: #1166 take-right and\ndrop-right reject dotted lists (spec requires proper-or-dotted;\ntake/drop already conform - the -right variants' length-counting\nloop demands proper lists). Part of the #1137 audit campaign.\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-05T09:58:37Z",
          "tree_id": "fd4d7af5f9f5091089de20a42c6e14cab1107779",
          "url": "https://github.com/kaappi/kaappi/commit/f271b4b0d8363e04dfe521cd7a25eeb78d69b574"
        },
        "date": 1783246685129,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.410331,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.429005,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.920849,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.124588,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.01244,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.211261,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.471596,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069725,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.332033,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.8237,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.940004,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.952386,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.294906,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.661447,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.04234,
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
          "id": "96ce73b03a84fe0330e8000cb03465037b58901a",
          "message": "Add primitives_control.zig audit tests (audit Phase 2.7) (#1170)\n\n33 assertions covering exceptions, call/cc, call/ec, dynamic-wind,\nand values: raise vs raise-continuable semantics, secondary\nexceptions when a raise handler returns, handler-runs-in-outer-env,\nerror-object accessors and predicate discrimination, escape and\nre-entry behavior including the R7RS 6.10 dynamic-wind spec example,\nafter-thunk execution on escape and on raise, multi-values through\ndynamic-wind, and type-error catchability. gc-stress clean.\n\nTwo assertions disabled with FAIL markers:\n- #1168 re-entrant call/cc rolls back set! mutations of non-captured\n  locals (register snapshot violates R7RS store semantics; the\n  disabled test HANGS without the fix). Heap-cell and closure-\n  captured counters work - those contrasts are committed enabled.\n- #1169 invoking a continuation with multiple arguments drops all\n  but the first value.\n\nPart of the #1137 audit campaign.\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-05T11:17:23Z",
          "tree_id": "4a294f0e4e07824172752c73b17056d270a6e680",
          "url": "https://github.com/kaappi/kaappi/commit/96ce73b03a84fe0330e8000cb03465037b58901a"
        },
        "date": 1783251511880,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.995166,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.537263,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.980942,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.000805,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.014488,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.234716,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.474359,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068233,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 13.707412,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.808522,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 11.128486,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.067331,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 9.335849,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.92305,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044815,
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
          "id": "76f67a31f1d48aac6c3543a02cc53baf7cafecf6",
          "message": "Add random, lazy, and cxr audit tests (audit Phases 2.15-2.17) (#1197)\n\nBatched audit of the three smallest primitives files per the strategy\ndoc: primitives_random.zig (SRFI-27), primitives_lazy.zig, and\nprimitives_cxr.zig. 125 assertions pass; 6 are disabled with FAIL\nmarkers pending fixes:\n\n- #1191 direct re-entrant force panics (GC root stack overflow; also\n  reproducible with nested map at depth 2000 - general VM issue)\n- #1192 default-random-source is a procedure, spec requires a variable\n- #1193 random-integer / %rs-next-int / pseudo-randomize! reject bignums\n- #1194 random-source-make-reals ignores the unit argument\n- #1195 random-real uses a [0,1) generator (code inspection, no test)\n- #1196 chibi-test shim lets errors escape test, undercounting failures\n\nprimitives_cxr.zig is fully conforming (self-labeling complete trees\nverify all 24 accessors); primitives_lazy.zig conforms apart from the\nshared crash class (delay-force chains force in bounded space, SRFI-45\ncycle detection works).\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-05T19:51:19+05:30",
          "tree_id": "093f1b92b96f7b1c0d470e03b780642d2af19e9b",
          "url": "https://github.com/kaappi/kaappi/commit/76f67a31f1d48aac6c3543a02cc53baf7cafecf6"
        },
        "date": 1783262835064,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.332062,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.399123,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.950164,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.080215,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012374,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.211442,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.469381,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069691,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.391296,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.831984,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 10.001812,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.960228,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.316581,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.691317,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042241,
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
          "id": "9914ac450947acdc8b1dc91a1ebc236991cca621",
          "message": "Add primitives audit tests for 7 files (audit Phases 2.8–2.14) (#1175)\n\n* Add primitives_vector.zig audit tests (audit Phase 2.8)\n\n175 chibi-test assertions covering all 34 procedures in\nprimitives_vector.zig: R7RS 6.8 spec examples, boundary and type\nerrors, overlapping vector-copy!, UTF-8 vector->string, callback\nerror propagation, escape continuations, and every SRFI-133 spec\nexample. Clean under -Dgc-stress=true.\n\nFour findings filed instead of fixed (campaign separates discovery\nfrom fixing): #1171 vector-skip/-right reject the multi-vector form,\n#1172 nine SRFI-133 procedures missing, #1173 vector literals are\nmutable while strings enforce immutability, #1174 only/except/rename\nimport sets don't validate identifiers. Failing assertions are\ndisabled with ;; FAIL: #NNN markers so run-all.sh stays green.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n* Add primitives_list.zig audit tests (audit Phase 2.9)\n\n114 chibi-test assertions covering the 17 procedures in\nprimitives_list.zig: all R7RS 6.4 spec examples, circular-list\nhandling (list-ref on circular spines works per spec; memq/member/\nassq/list-copy raise catchable errors instead of hanging), memv/assv\neqv? consistency across flonums/bignums/rationals, comparator\nargument order, callback error propagation, and escape continuations.\nClean under -Dgc-stress=true.\n\nFindings filed instead of fixed: #1176 map/for-each with >256 lists\npanic uncatchably (fixed [256]Value buffers without bounds checks),\n#1177 (features) disagrees with both cond-expand evaluators on\nexact-closed/exact-complex, and #1173 widened to pair/list literals.\nAlso verified the unbarriered setCdr in mapFn is safe (minor GC marks\ntransitively from roots through old-gen objects).\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n* Add primitives_bytevector.zig audit tests (audit Phase 2.10)\n\n116 chibi-test assertions covering the 21 procedures in\nprimitives_bytevector.zig: all R7RS 6.9 spec examples, overlapping\nbytevector-copy! in both directions, byte-value boundaries,\nutf8->string/string->utf8 byte-vs-codepoint range indexing with\nastral chars, and full binary-port coverage (peek/read sequencing,\nEOF objects, partial reads, read-bytevector! ranges, output-\nbytevector round trips, closed-port and wrong-direction errors,\ndefault-port path via parameterize). Clean under -Dgc-stress=true.\n\nFindings filed instead of fixed: #1178 utf8->string skips UTF-8\nvalidation and manufactures corrupt strings that break string-ref\nfar from the cause, #1179 u8-ready? returns #f at EOF where R7RS\nrequires #t (the #280 fix inverted the spec — its quote was wrong),\nand #1173 widened to bytevector literals.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n* Add primitives_hashtable.zig audit tests (audit Phase 2.11)\n\n71 chibi-test assertions covering the 23 SRFI-69 procedures: key-type\ncoverage (immediates, strings, shallow structures), growth to 100\nentries, tombstone reuse, first-occurrence-wins alist->hash-table,\nmerge/copy/self-merge, snapshot semantics under mutation, hash\nfunction bounds, and case-insensitive string-ci-hash incl. Greek.\nClean under -Dgc-stress=true.\n\nFindings filed instead of fixed: #1180 bignum/rational/deep keys are\nsilently unfindable (valueHash pointer-hashes what deepEqual compares\nby value; aligned-ptr x odd-const = 0 mod 8 masks it at capacity 8),\n#1181 walk/fold snapshot is invisible to the GC — use-after-free when\nthe callback deletes entries and allocates (29/30 entries corrupted\nunder gc-stress), #1182 hash-table-update! missing from (srfi 69),\n#1183 custom equivalence/hash functions silently ignored.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n* Add primitives_fiber.zig audit tests (audit Phase 2.12)\n\n31 chibi-test assertions covering the 8 fiber/channel procedures:\nFIFO channels with reference-preserving sends, deadlock detection\n(empty receive without fibers, joining permanently-blocked fibers,\ncyclic joins — all catchable errors, no hangs), memoized joins,\nexception re-raise on every join of an errored fiber, nested spawns,\npipelines, and the MAX_FIBERS=64 limit error. Clean under\n-Dgc-stress=true. Test order documented: deadlock tests leak parked\nfibers by design, so the slot-filling limit test runs last.\n\nFindings filed instead of fixed: #1184 top-level yield raises a\ncontentless \"error\" when all 64 slots hold parked fibers (yield is\nadvisory; the main fiber can still run), and #1155 widened — spawn\nrejects native procedures the same way SRFI-18 make-thread does.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n* Add primitives_ffi.zig audit tests (audit Phase 2.13)\n\n47 chibi-test assertions covering the 7 FFI procedures and the\ncall-time marshaling behind them: open/close lifecycle (double\nclose, use-after-close), dlopen/dlsym error detail, type-list\nvalidation, numeric coercions (fixnum/rational→double accepted,\nlossy flonum→int rejected), NULL string returns → #f, NUL-in-string\nrejection, pointer round trips via memset into a bytevector,\ncallback slot exhaustion at 32 with release/reuse, and a working\nqsort comparator. Clean under -Dgc-stress=true.\n\nFindings filed instead of fixed: #1185 errors raised in FFI\ncallbacks are silently swallowed (vm.last_callback_error is\nwrite-only), #1186 the char FFI type rejects character values and\nreturns fixnums (a uint8 alias in disguise), #1187 call-time\nmarshaling errors carry no detail (bare \"error\").\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n* Add primitives_r7rs.zig audit tests (audit Phase 2.14)\n\n41 chibi-test assertions covering the 17 procedures in\nprimitives_r7rs.zig: (scheme time) invariants, command-line and\nenvironment variables, eval/environment/interaction-environment/\nnull-environment/scheme-report-environment behaviors, load round\ntrips with file-error? and catchable reader errors, parameter\nconverters at creation and parameterize time, and disassemble type\nerrors. Plus tests/scheme/errors/exit-wind.sh (8 shell assertions):\nexit runs dynamic-wind afters inside-out, emergency-exit skips them,\nand the exit-code mapping (#f->1, #t/absent->0, fixnum->low byte) —\nprocess-terminating semantics that cannot live in a .scm test.\nClean under -Dgc-stress=true.\n\nFindings filed instead of fixed: #1188 eval silently ignores a\nnon-environment specifier (evaluates in the interaction environment),\n#1189 environment rejects only/except/prefix/rename import sets\n(Phase 1D's guard-wrapped test masked this), #1190 load rejects the\noptional environment-specifier with an arity error.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n* Make exit-wind.sh executable\n\nrun-all.sh requires the executable bit on shell tests; the previous\ncommit added it as 644 and the errors suite reported \"not executable\".\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-05T20:19:21+05:30",
          "tree_id": "58a86ba52f53f7d4a0725f2756f3ccb7cc8582a9",
          "url": "https://github.com/kaappi/kaappi/commit/9914ac450947acdc8b1dc91a1ebc236991cca621"
        },
        "date": 1783264223852,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.310987,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.549362,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.921414,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.04795,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012544,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.211186,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.471622,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.06959,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.344552,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.822887,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.945793,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.949681,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.344952,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.664112,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042371,
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
          "id": "063744f7f85f88d9eb118208f1b43a0d8c037955",
          "message": "Add primitives.zig core audit tests (audit Phase 2.18) (#1200)\n\nAudits the core primitives file: pairs/lists, 13 type predicates, the\nequivalence trio, not, core string ops, apply, and the internal record\nprimitives. 196 assertions pass; 4 are disabled with FAIL markers\nawaiting the referenced issues:\n\n- see #1198: reverse, append (non-last args), and the native applyFn\n  hang with unbounded allocation on circular lists, while length/list?\n  use Floyd detection and tail-position apply compiles to a bounded\n  tail_apply opcode - same-expression behavior differs by position\n- see #1199: record accessors/mutators omit the record-type check, so\n  cross-type access silently reads/writes another type's field\n  (non-record arguments do raise)\n\nEverything else conforms: R7RS 6.2.6 predicate examples, eqv?/equal?\nacross the numeric tower (bignum/rational/complex, NaN, -0.0), circular\nequal? termination, append tail sharing, symbol->string immutability,\nUTF-8 codepoint string-length, and apply argument flattening.\n\nThe tracker also re-applies the 2.15-2.17 lines byte-identically to\nPR #1197 so the two PRs merge cleanly in either order.\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-05T20:19:33+05:30",
          "tree_id": "6ad7bf18f9fa70bda998e01dbe90b3c1ab9c1852",
          "url": "https://github.com/kaappi/kaappi/commit/063744f7f85f88d9eb118208f1b43a0d8c037955"
        },
        "date": 1783264235391,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.35215,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.88116,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.951541,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.059431,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012599,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.211228,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.470711,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069765,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.4381,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.824428,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.980423,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.959384,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.541072,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.733384,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043634,
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
          "id": "5d0aeeb710cac4b7d58aafefd8a71d89625b6606",
          "message": "Check off audit Phase 3.0: all 35 SRFI test files validated, no failures (#1201)\n\nRan every file in tests/scheme/srfi/ individually with a 30-second\ntimeout at 96ce73b, reading printed counts rather than exit codes (the\nchibi-test shim and SRFI-64 both exit 0 on assertion failures):\n\n- chibi-test files: all print \"N pass, 0 fail\"\n- SRFI-64 files (srfi64, srfi189, srfi18-atomic-stress): 0 unexpected\n  failures; srfi64.scm's single \"expected failure\" is an intentional\n  test-expect-fail case\n- exit-code files: all print their final OK markers (no silent aborts)\n- no hangs, no timeouts, no escaped top-level errors\n\nNo issues to file; matches the Phase 0 baseline. Tracker lines for\nPhases 2.15-2.18 are re-applied byte-identically to PRs #1197/#1200 so\nall three PRs merge cleanly in any order.\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-05T20:19:36+05:30",
          "tree_id": "6ad7bf18f9fa70bda998e01dbe90b3c1ab9c1852",
          "url": "https://github.com/kaappi/kaappi/commit/5d0aeeb710cac4b7d58aafefd8a71d89625b6606"
        },
        "date": 1783264318549,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.374477,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.679283,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.951195,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.094211,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012499,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.211381,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.471098,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069532,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.415048,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.827902,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.971198,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.954635,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.360955,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.715151,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042965,
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
          "id": "419836ad7ef67093c7eb3f16eb1cc6fca27c9271",
          "message": "Add SRFI-9 and SRFI-39 conformance tests (audit Phase 3.1) (#1204)\n\n* Add SRFI-9 and SRFI-39 conformance tests (audit Phase 3.1)\n\nDedicated test files for the two built-in SRFIs that had no direct\ncoverage (SRFI-170 was covered by Phase 2.5). 68 assertions pass; 6 are\ndisabled with FAIL markers awaiting the referenced issues:\n\n- see #1202: parameterize installs bindings sequentially, so later\n  value expressions observe earlier bindings - the normative SRFI-39\n  example (parameterize ((radix 8) (prompt (f 10))) (prompt)) returns\n  \"12\" instead of \"1010\", and results depend on clause order\n- see #1203: record-type redefinition retargets previously-created\n  constructors and predicates because the desugar resolves the hidden\n  __record_type_ global at call time instead of capturing the type\n- see #560 (reopened): define-record-type inside lambda/let bodies is\n  compiled as an expression; the earlier fix covered only begin\n- see #1199: cross-type accessor check (known, one disabled line)\n\nEverything else conforms: constructor field tags map by name and may\nlist a subset in any order, records are disjoint from all R5RS types,\nconverters run at creation/assignment/parameterize (never on restore),\none-argument parameter assignment works, and non-local exits restore\nouter parameter values.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n* Check off audit Phase 3.1 in the tracker\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-05T20:58:38+05:30",
          "tree_id": "917e9be97be551b597bbc3dea7e7c66db2be01a9",
          "url": "https://github.com/kaappi/kaappi/commit/419836ad7ef67093c7eb3f16eb1cc6fca27c9271"
        },
        "date": 1783266566341,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.356177,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.912402,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.955908,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.057314,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012565,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.211198,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.472038,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069715,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.367002,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.821458,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.943394,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.955366,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.302512,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.690323,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043361,
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
          "id": "ffb4ae293afb0ed3d39fa4720b2e41bdb1b9571c",
          "message": "Add conformance tests for 28 portable SRFIs (audit Phases 3a-3e) (#1227)\n\nConformance test files for the portable-SRFI units 3a-3e of the audit\ncampaign (tracking: see #1137):\n\n- 3a: SRFI 0, 6, 17, 23, 26\n- 3b: SRFI 37, 38, 43, 116, 117, 134\n- 3c: SRFI 41, 42, 45, 143, 144\n- 3d: SRFI 60, 61, 78, 87, 197, 210, 227\n- 3e: SRFI 4, 127, 130, 233, 235\n\n549 passing assertions total; ~63 assertions disabled with FAIL markers\nreferencing the 22 issues filed during this phase (see #1205 through\n#1226) plus the earlier reader issue (see #1164). Highlights: bitwise\nops use magnitude semantics for negative operands (see #1214, affects\nSRFI 60/143/151), SRFI-4 integer vector kinds are bare bytevector\naliases (see #1225), SRFI-210 value/set!-values are broken (see #1218,\nsee #1224), SRFI-233 parser calls unbound char-whitespace? (see #1223).\n\nTracker updated: 3a-3e checked in docs/audit-strategy.md.\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-05T16:06:00Z",
          "tree_id": "90c5b0ba79c3481a0189495086575dc700506d3a",
          "url": "https://github.com/kaappi/kaappi/commit/ffb4ae293afb0ed3d39fa4720b2e41bdb1b9571c"
        },
        "date": 1783268713243,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.314296,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.627799,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.929017,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.064612,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012453,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.211451,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.469748,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069635,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.364279,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.822387,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.938557,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.956734,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.295738,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.694856,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042493,
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
          "id": "451455defddfb4a057dde68ac86b28447e52f901",
          "message": "Add matching parenthesis highlighting to REPL (#1228)\n\nWhen the cursor is right after a closing ) or ], both the closing\ndelimiter and its matching opening delimiter are highlighted in bold\nbright yellow. This provides visual feedback for balanced expressions\nwhile typing, similar to paren-matching in Emacs and other Lisp editors.\n\nThe matching is lexically aware — it correctly skips parens inside\nstrings, line comments, block comments, character literals (#\\(), and\npipe-quoted symbols (|...|). Multi-line input is supported: on\ncontinuation lines, the matcher considers accumulated previous lines\nto confirm balance even when the opening delimiter is on an earlier line.\n\nImplementation extends the vendored linenoise highlight callback to\nreceive cursor position, adds a forward-scanning paren matcher, and\nintegrates it into the existing syntax highlighting pipeline.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-05T16:27:16Z",
          "tree_id": "8c4b4d00131691482ac71c1d66fd9dfc784390b3",
          "url": "https://github.com/kaappi/kaappi/commit/451455defddfb4a057dde68ac86b28447e52f901"
        },
        "date": 1783270360199,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.354055,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.537352,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.919999,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.094855,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012405,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.211717,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.471032,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070311,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.34488,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.810715,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 10.024542,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.956644,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.325894,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.698782,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043147,
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
          "id": "71d6624fa4b7de0ef0c4f01ee8fb92536381bfce",
          "message": "Add behavioral tests for 12 smoke-only SRFIs (audit Phase 3.4) (#1239)\n\nUpgrades SRFIs 98, 125, 128, 132, 141, 151, 152, 174, 175, 195, 219,\nand 232 from load-only smoke checks to behavioral conformance suites\n(tracking: see #1137).\n\n402 passing assertions; ~60 disabled with FAIL markers referencing the\n10 issues filed during this phase (see #1229 through #1238) plus the\nbitwise magnitude bug (see #1214). Highlights: SRFI-219 is dead on\narrival because an imported define macro cannot shadow the built-in\nspecial form (see #1237, core expander bug); SRFI-232 currying only\naccepts one argument at a time (see #1238); balanced/ is aliased to\nround/ (see #1232); the SRFI-128 default comparator is not a total\norder and eq/eqv comparators are unhashable (see #1230); SRFI-125's\nhash-table-ref/find drop the success/proc result (see #1229);\nstring-every discards the final predicate value (see #1234);\nascii-digit-value treats letters as digits (see #1236). SRFI-98 and\nSRFI-195 conform fully.\n\nTracker updated: 3.4 checked in docs/audit-strategy.md.\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-05T22:09:57+05:30",
          "tree_id": "30dfe04be5adf75690bf218312dd6d176680658d",
          "url": "https://github.com/kaappi/kaappi/commit/71d6624fa4b7de0ef0c4f01ee8fb92536381bfce"
        },
        "date": 1783271103460,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.983054,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.89246,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.95316,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.96363,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.013545,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.234352,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.47312,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068632,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 13.356003,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.806118,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 11.060598,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.063709,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 9.110631,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.830209,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044326,
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
          "id": "c1526aa3ded71a3c1938f296e8bc32ee89381f82",
          "message": "Release v0.13.0",
          "timestamp": "2026-07-05T22:20:05+05:30",
          "tree_id": "dc10578603da2fde24317cbac963fa85336ef918",
          "url": "https://github.com/kaappi/kaappi/commit/c1526aa3ded71a3c1938f296e8bc32ee89381f82"
        },
        "date": 1783271735819,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.373419,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.542624,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.920285,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.17693,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012404,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.211466,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.471926,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.07046,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.340675,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.812137,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.980701,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.955982,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.33986,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.787822,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044137,
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
          "id": "27e610b089e19e69fd01718fe6016752c8f5bf06",
          "message": "Phase 5 synthesis: harden run-all.sh, check final tracker box (#1247)\n\nCloses out the audit campaign (tracking: see #1137). The synthesis\ndeliverables live on the tracking issue: 87 findings grouped into 9\nroot-cause clusters, priority order (crashes > wrong results > missing\nfeatures > edge cases), a 197-marker disabled-test inventory, and two\nepics (see #1245 native VM re-entrancy, see #1246 portable SRFI\nquality). Six issues already fixed still have stale FAIL markers to\nre-enable.\n\nrun-all.sh now inspects each passing file's output for chibi-test\n\"N fail\" and SRFI-64 \"unexpected failures\" counts: the chibi shim exits\n0 even when assertions fail (see #1196), so exit codes alone silently\npassed failing files. Verified: a failing chibi file is now caught,\nsrfi64.scm's intentional expected-failure still passes, and the full\nsuite is green (373 files + 1395 R7RS assertions).\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-05T23:40:10+05:30",
          "tree_id": "42b78d0c750408d97c39b90fd53163471c0a4fde",
          "url": "https://github.com/kaappi/kaappi/commit/27e610b089e19e69fd01718fe6016752c8f5bf06"
        },
        "date": 1783276367146,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.373492,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.173682,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.918152,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.077662,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012427,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.211586,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.471555,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070426,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.313531,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.809301,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.960267,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.951579,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.353927,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.515903,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042428,
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
          "id": "acb409b038185941ba8731e584cebf1daceec001",
          "message": "Add compiler/VM edge-case tests (audit Phases 4A-4C) (#1244)\n\nPhase 4 of the audit campaign (tracking: see #1137): five compliance\nfiles covering proper tail recursion in every R7RS 3.5 context,\nthin-coverage forms, continuation interactions, syntax-rules edges, and\nmacro exports through import sets. 99 passing assertions, 8 disabled\nwith FAIL markers.\n\nFour new issues (see #1240 through #1243):\n- call-with-values consumer, call/cc receiver, and eval are not\n  tail-called as 3.5 requires - each panics uncatchably at native\n  re-entry depth ~1024 (see #1240; crash mechanism is #1191's)\n- let*-values body is not a tail context, even with one binding\n  clause; let-values is fine (see #1241)\n- force caps promise chains at 100,000 iterations and reports longer\n  legitimate delay-force chains as circular (see #1242)\n- doubled-ellipsis templates (x ... ...) expand to garbage containing\n  a literal ... instead of flattening (see #1243)\n\nEverything else conforms: all syntactic 3.5 tail contexts at 1e5-1e6\ndepth, the R7RS 6.10 dynamic-wind re-entry example, multi-shot\ncontinuations, parameterize across re-entry, guard/raise-continuable\nsemantics, be-like-begin, custom ellipsis, vector patterns, macro\nexports through prefix/only/rename/except, cond-expand library\ndeclarations, and circular-import detection.\n\nTracker updated: 4A-4C checked in docs/audit-strategy.md.\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-05T18:09:53Z",
          "tree_id": "2210db112f7467503c5c7274142fee896af81098",
          "url": "https://github.com/kaappi/kaappi/commit/acb409b038185941ba8731e584cebf1daceec001"
        },
        "date": 1783276422511,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.355125,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.497679,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.946921,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.083963,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012704,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.212281,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.469117,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070515,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.350501,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.810185,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.998305,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.957054,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.40985,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.682381,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042936,
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
          "id": "04e2ee1abb76ad62f346152a36724b0dd9e640e6",
          "message": "Box set!-mutated locals for R7RS store semantics (#1168) (#1249)\n\n* Box set!-mutated locals for R7RS store semantics (#1168)\n\nR7RS §3.4 requires that set! modifies the store (a heap location), not\nthe continuation. The compiler previously boxed locals only when they\nwere closure-captured as upvalues, leaving set!-mutated-but-uncaptured\nlocals in plain registers. Since captureContinuation snapshots the\nregister file, restoring a continuation rolled back those mutations,\ncausing infinite loops in idiomatic generator/counter patterns.\n\nFix: introduce boxIfSetTarget — after defining a local (in let, let*,\nlambda parameters, or do), if its name appears in the top-level form's\nset_targets map, box it immediately. The register then holds a pointer\nto a heap-allocated pair whose car is the mutable value; set! writes to\nthe car via set_box_local, and continuation restore puts back the same\npointer without affecting the car.\n\nApplied to all four binding paths: compileLet, compileLetStar,\ncompileLambdaWithIR, compileLambda, and compileDo.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Add FAIL-marked tests for macro-introduced set! gap (#1250)\n\ncollectSetTargets scans pre-expansion, so set! introduced by macros\nbypasses boxing. Document the two reproduction cases from review and\nreference follow-up issue #1250.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Add #1250 to FAIL markers for grep discoverability\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-06T10:54:37+05:30",
          "tree_id": "122f7db37958a06dbca5d54b44a1ddb3bc112037",
          "url": "https://github.com/kaappi/kaappi/commit/04e2ee1abb76ad62f346152a36724b0dd9e640e6"
        },
        "date": 1783316957925,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.246994,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.868581,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.980394,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.150447,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012422,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.212118,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.481353,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.071602,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.479547,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.86354,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.994366,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.975361,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.327273,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.580645,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043407,
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
          "id": "c9dc81af0c007014e609fe460ce6b3b100d7b068",
          "message": "Deliver multiple values when continuation invoked with != 1 arg (#1251)\n\n* Deliver multiple values when continuation invoked with != 1 arg (#1169)\n\nContinuation invocation (both call/cc and call/ec) was silently dropping\nall but the first argument. When nargs != 1, wrap the args in a\nMultipleValues object — mirroring `values` semantics — so\ncall-with-values consumers receive the correct argument count.\n\nFixed in all three dispatch sites: vm_dispatch.zig (regular call and\nflat-args paths) and vm_calls.zig (callValue fallback).\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Fix missed callWithArgs site, extract continuationArgValue helper\n\nAddress review feedback: the callWithArgs continuation branch still had\nthe old single-value logic, reachable via apply and first-class\ncall-with-values. Extract continuationArgValue() to a shared helper so\nall four dispatch sites use the same wrap, preventing future divergence.\n\nAdd three regression tests covering the callWithArgs path (non-tail\napply multi-arg, zero-arg apply, first-class call-with-values).\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-06T12:14:33+05:30",
          "tree_id": "5bb200e2ba6b37c59c99ae2baf0f66374fb0dfe6",
          "url": "https://github.com/kaappi/kaappi/commit/c9dc81af0c007014e609fe460ce6b3b100d7b068"
        },
        "date": 1783321810014,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.082698,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.02201,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.772698,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.095799,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.010714,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.182096,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.372693,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.054309,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 9.729624,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.42952,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 8.606802,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.826741,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 7.143777,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.470395,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.035241,
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
          "id": "f13e806f71e3b9682bfbc2889f8cbc6f6a6db8c7",
          "message": "Add CodeRabbit AI code review configuration (#1252)\n\nConfigures CodeRabbit with project-specific review instructions:\n- GC safety rules for primitives, memory, and VM files\n- Compiler form checklist for compiler and IR files\n- R7RS compliance guidance for reader and SRFI files\n- Assertive profile for thorough correctness-focused reviews\n- Path filters to skip vendored/generated files\n- Relevant linters enabled (shellcheck, actionlint, yamllint, gitleaks)\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-06T12:15:19+05:30",
          "tree_id": "3fc22cf91e9a154c25a82efb67fd7f0a3e4a3a7a",
          "url": "https://github.com/kaappi/kaappi/commit/f13e806f71e3b9682bfbc2889f8cbc6f6a6db8c7"
        },
        "date": 1783321956215,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.051227,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.993742,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.983247,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.07457,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.013672,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.235628,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.483464,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068231,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 13.394271,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.840235,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 11.106949,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.083699,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 9.118242,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.820902,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.04466,
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
          "id": "66e4389d7b180140f8ffd0161e2b6f967125a529",
          "message": "Improve parallel-issues skill: label filter, triage rules, body-based grouping (#1255)\n\nThe skill grouped issues by title alone, so it could not actually verify\nits core no-file-overlap rule, and it happily batched epic/tracking\nissues, assigned issues, and issues with fixes already in flight.\n\n- Accept an optional label argument ($ARGUMENTS) to scope the batch\n- Fetch issue bodies and assignees; bodies are where file paths live\n- Skip epics/tracking/meta, assigned, linked-PR, and not-actionable issues\n- Raise the list limit to 500 and rerun when the count hits the limit\n- Cap sets at ~8 issues so output matches launchable parallelism\n- Explain the why behind the strict set-line output format\n\nValidated with the skill-creator eval loop against the live tracker:\nnew skill 11/11 assertions vs old skill 9/11 — the baseline batched\nmeta-issues 1137/1245/1246 and produced sets of up to 18 issues.\nEval definitions live in evals/evals.json for future iterations.\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-06T11:15:03Z",
          "tree_id": "726a50d16780fffdb3ea7073d86841e99f48f014",
          "url": "https://github.com/kaappi/kaappi/commit/66e4389d7b180140f8ffd0161e2b6f967125a529"
        },
        "date": 1783337901754,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.339632,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.772768,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.937033,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.369152,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012437,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.212749,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.489712,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.071526,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.398432,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.939092,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.967806,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.962243,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.302429,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.695209,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042026,
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
          "id": "088472e4afdded322963cc08cd3407f854a2deb7",
          "message": "Fix GC crash on stale VM registers after thread start/join cycles (#1254)\n\n* Fix GC crash on stale VM registers after thread start/join cycles (#1156)\n\nThe GC could SIGSEGV under -Dgc-stress=true when scanning VM registers\nthat held stale pointers to freed objects. Between execute() calls,\nframe_count drops to 0 and a GC cycle can free objects that stale\nregister values still reference. The next execute() re-covers those\nregisters, and the GC hits the dangling pointers.\n\nThree fixes:\n1. Clear local registers in execute() and callClosure() so the GC never\n   scans stale values from a previous frame at the same base.\n2. Remove dead frame setup from makeThreadFn — OS thread fibers create\n   their own VM and never use the parent fiber's frames[0].\n3. Add missing write barriers and defensive frame_count=0 in\n   reapOsThread after joining the OS thread.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Address review: clear stale registers in callReentrant, use SRFI-64 test\n\n- Factor register clearing into clearFrameLocals() helper and call from\n  all three frame-push sites: execute(), callClosure(), callReentrant()\n- Add missing write barrier for fiber.name in makeThreadFn\n- Convert regression test to SRFI-64 assertions\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-06T17:24:07+05:30",
          "tree_id": "0b70e3e88d83c0dd91161e1b57c89d7f12003d33",
          "url": "https://github.com/kaappi/kaappi/commit/088472e4afdded322963cc08cd3407f854a2deb7"
        },
        "date": 1783340574786,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.343,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.483513,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.942575,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.267671,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012464,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.212182,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.485703,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070962,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.521916,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.871418,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.962163,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.953857,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.372773,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.713448,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044359,
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
          "id": "16706095d64347dc148812bfcf5f16e69d44f9a1",
          "message": "Remove iteration cap from force trampoline for unbounded delay-force chains (#1242) (#1259)\n\nThe forcing trampoline had a hardcoded 100,000 iteration limit as a\nheuristic cycle detector, but it cannot distinguish genuine cycles from\nlong legitimate chains (SRFI-41 streams, SRFI-45 iterative algorithms).\nR7RS 4.2.5 requires delay-force chains to force in bounded space with\nno limit on length. The existing `forcing` flag already detects\nre-entrant cycles.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-06T18:30:14+05:30",
          "tree_id": "175b4bb981769c63bf57426311ca87b6f72b6179",
          "url": "https://github.com/kaappi/kaappi/commit/16706095d64347dc148812bfcf5f16e69d44f9a1"
        },
        "date": 1783344437098,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.08132,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.618434,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.969854,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.023014,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.013863,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.235076,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.491535,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068348,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 13.428781,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.855936,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 11.124398,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.070079,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 9.142134,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.852498,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045481,
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
          "id": "1567d33d47ea953fe2d8b839a11873e1b47fcdd4",
          "message": "Fix parameterize to evaluate all values before binding (#1202) (#1260)\n\nR7RS §4.2.6 and SRFI-39 require that all value expressions in a\nparameterize form are evaluated before any parameter cell is mutated.\nThe previous desugaring used a single let* which installed bindings\nsequentially, causing later value expressions to observe earlier\nsibling bindings.\n\nSplit the desugaring into an outer let (evaluates all param and value\nexpressions in the original dynamic environment) and an inner let*\n(saves old values and installs new converted values sequentially).\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-06T18:32:51+05:30",
          "tree_id": "15600d0c5dadb8f96c11c6dae7829d1fdf4c49a5",
          "url": "https://github.com/kaappi/kaappi/commit/1567d33d47ea953fe2d8b839a11873e1b47fcdd4"
        },
        "date": 1783344845714,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.389962,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.075563,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.957157,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.271643,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012462,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.213275,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.489897,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.071319,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.461513,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.895896,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 10.045804,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.977412,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.349921,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.75348,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043574,
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
          "id": "01b971a3b4ca1f78eaa6f405177ca3d28f3b183e",
          "message": "Fix u8-ready? returning #f at EOF (R7RS requires #t) (#1258)\n\n* Fix u8-ready? returning #f at EOF (R7RS requires #t) (#1179)\n\nR7RS §6.13.3: \"If the port is at end of file then u8-ready? returns #t.\"\nThe #280 fix incorrectly inverted this for string ports. Remove the\nstring-port branch so u8-ready? always returns #t, matching char-ready?.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Address review: remove dead peek_byte check, add comment, fix #280 test\n\n- Collapse u8ReadyP to discard the port and return TRUE directly, removing\n  the dead peek_byte branch (both CodeRabbit and reviewer nit).\n- Add \"For simplicity\" comment mirroring charReadyP in primitives_io.zig.\n- Remove the stale #280 section from bytevector-port-fixes.scm that still\n  documented the inverted EOF behavior this PR reverts.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-06T18:50:02+05:30",
          "tree_id": "042fc57b2530cb16b4a91faea6f9caf1fd4ef938",
          "url": "https://github.com/kaappi/kaappi/commit/01b971a3b4ca1f78eaa6f405177ca3d28f3b183e"
        },
        "date": 1783345636674,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.040391,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.219987,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.963687,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.048182,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.013594,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.235068,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.481331,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068124,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 13.369553,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.842512,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 11.088204,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.063145,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 9.127692,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.868349,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045186,
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
          "id": "e88c757495cef053c91f0a7e5d39446a84c91223",
          "message": "Patch datum-label references inside vectors (#1213) (#1257)\n\n* Patch datum-label references inside vectors (#1213)\n\nThe reader resolved #n# forward references in pair cells but never\nwalked vector slots, so `#0=#(1 #0#)` left the placeholder unpatched.\nAdd an iterative patchPlaceholder walk (pairs + vectors, cycle-safe via\nvisited set) for non-pair labeled datums.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Address review: write barriers, OOM propagation, hash-set visited\n\n1. Add gc.writeBarrier after every patch store (setCar, setCdr, vector\n   slot) — containers may be promoted to old gen during mid-read minor\n   GCs while datum is young. Also fixes the pre-existing gap in the\n   pair branch (L65-66).\n2. Change patchPlaceholder to return error{OutOfMemory} and propagate\n   it as ReadError.OutOfMemory at the call site — no more silent\n   partial patching.\n3. Replace O(n²) visited ArrayList with AutoHashMap for O(1) cycle\n   detection.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-06T19:01:18+05:30",
          "tree_id": "b26abc1c03fe5e6ea39223c6a3c0b8f1ad6109f0",
          "url": "https://github.com/kaappi/kaappi/commit/e88c757495cef053c91f0a7e5d39446a84c91223"
        },
        "date": 1783346403385,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.525935,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.343141,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.752682,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.32105,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.01334,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.216078,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.37433,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057248,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.576404,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.419496,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 10.253394,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.977308,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.291572,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.046583,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.037697,
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
          "id": "18063843170e95d0054bc93abacbf25ab4086bd4",
          "message": "Use Unicode derived properties for char classification (#1145) (#1263)\n\n* Use Unicode derived properties for char classification (#1145)\n\nchar-upper-case?, char-lower-case?, and char-alphabetic? were deriving\nclassification from case mappings instead of the Unicode Uppercase,\nLowercase, and Alphabetic derived properties. This caused titlecase\nletters (Lt) to report as both upper and lower, sharp-s (U+00DF) to\nmiss lowercase, and ordinal indicators (U+00AA/U+00BA) to miss\nalphabetic/lowercase.\n\nGenerate proper property range tables from DerivedCoreProperties.txt\nand use binary-searched range lookups instead of case-mapping inference\nand hardcoded script block ranges.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Fix string-titlecase and final-sigma regressions with Cased property\n\nstring-titlecase and string-downcase final-sigma detection used\nisUnicodeUppercase/isUnicodeLowercase as a proxy for the Unicode Cased\nproperty. Titlecase (Lt) characters are Cased but neither Uppercase nor\nLowercase, and combining marks are Alphabetic but not Cased.\n\nAdd a cased_ranges table from DerivedCoreProperties.txt and use it at\nall four word-boundary/final-sigma sites in primitives_char.zig and\nprimitives_string_ext.zig.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-06T13:37:12Z",
          "tree_id": "83004391a110f23ee43d48445aedc98cf9e8178b",
          "url": "https://github.com/kaappi/kaappi/commit/18063843170e95d0054bc93abacbf25ab4086bd4"
        },
        "date": 1783346940822,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.329733,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.846771,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.932537,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.12575,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012513,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.212744,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.487792,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.07197,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.500333,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.878508,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 10.023654,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.962618,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.417692,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.689454,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044306,
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
          "id": "9e04a667cb1aeee5ac4bae29ef167ba6e8a36f81",
          "message": "Support optional environment-specifier in load (R7RS §6.14) (#1262)\n\n* Support optional environment-specifier in load (R7RS §6.14) (#1190)\n\nR7RS specifies that load accepts an optional second argument specifying\nthe environment in which to evaluate the loaded expressions. Previously,\nload was registered with exact arity 1, rejecting the two-argument form\nwith an arity error.\n\nChange load's arity to variadic (minimum 1) and compile expressions via\ncompileExpressionInEnv when an environment is supplied, following the\nsame pattern as eval.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Address review: use SRFI-64, add positive custom-env assertion\n\n- Rewrite smoke test to use SRFI-64 (test-begin/test-equal/test-end)\n  instead of manual pass/fail counters per project conventions\n- Add positive assertion that load into a custom environment actually\n  defines the variable there (eval in that env returns it)\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-06T19:41:46+05:30",
          "tree_id": "813319ada7476bf7e929b6649b3e19f93845b277",
          "url": "https://github.com/kaappi/kaappi/commit/9e04a667cb1aeee5ac4bae29ef167ba6e8a36f81"
        },
        "date": 1783348589586,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.307061,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.700151,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.972396,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.317149,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012812,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.212403,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.481844,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.071102,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.617104,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.867097,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.99791,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.95856,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.373615,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.763171,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044103,
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
          "id": "1102effb0bf51ca423ecc48574509128775a7dfd",
          "message": "Error on unknown identifiers in import only/except/rename (#1261)\n\n* Error on unknown identifiers in import only/except/rename (#1174)\n\nR7RS §5.2 says it is an error if identifiers listed in only, except, or\nrename are not found in the library's exports. Previously these were\nsilently ignored, which masked typos and missing exports (e.g. probing\nSRFI-133 for vector-fold appeared to succeed).\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Address review: syntax keywords, define-library propagation, atomic only\n\n- Accept syntax keywords (define, if, when, case-lambda, define-record-type,\n  etc.) in only/except/rename by checking ir.isSpecialForm; add VM-level\n  syntax forms (define-record-type, import, include) to the special form\n  table so they pass validation too\n- Propagate import errors from define-library instead of swallowing them\n  (fixes the main use site for import filters)\n- Make only validate all identifiers before importing any (atomic, consistent\n  with except/rename)\n- Use fetchRemove in except/rename for validate+exclude in one hash op,\n  eliminating the O(n*m) excluded_list scan\n- Fix message wording: \"import set\" instead of \"library exports\" (accurate\n  for composed sets like prefix)\n- Expand tests: 20 shell tests covering syntax keywords, define-library\n  propagation, composed sets, error messages; 4 unit tests in\n  tests_libraries.zig\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Fix rename corruption on colliding names (parallel semantics)\n\nInterleaved fetchRemove+put in the rename pass corrupted colliding\nrenames like (rename lib (a b) (b c)) — the put for \"b\" clobbered\nthe original \"b\" entry before its own fetchRemove ran. Split into\ntwo phases: remove all old entries first, then insert under new names.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Add auxiliary syntax to special forms, swap regression test\n\nAdd else, =>, _, ..., unquote, unquote-splicing to the special form\ntable so they pass import filter validation (R7RS Appendix A lists\nthem as (scheme base) exports). Add swap rename regression test.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-06T20:58:15+05:30",
          "tree_id": "031ccc18f650eca4c2aa8ffed51fc3e916734c8e",
          "url": "https://github.com/kaappi/kaappi/commit/1102effb0bf51ca423ecc48574509128775a7dfd"
        },
        "date": 1783353305976,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.337575,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.789321,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.956878,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.283788,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.01261,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.212519,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.480694,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070978,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.442999,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.876474,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.972748,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.955576,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.335685,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.731007,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043709,
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
          "id": "a10759f1a07bc188d025d24e549210abc601d5e9",
          "message": "Check lexical bindings when matching syntax-rules literals (#1265)\n\n* Check lexical bindings when matching syntax-rules literals (#1139)\n\nR7RS 4.3.2 requires that a literal identifier in a syntax-rules pattern\nmatches an input identifier only when both have the same lexical binding,\nor both are unbound. Previously matchPattern compared names only, so\n(let ((lit 42)) (has-lit lit)) incorrectly matched lit as a literal.\n\nPass use-site local names from the compiler into expandMacro and check\nthem against the transformer's captured_locals (definition-site bindings).\nIf binding status differs — one bound, one not — the literal does not\nmatch and the next pattern clause is tried.\n\nAlso record captured_locals in compileDefineSyntax and the body-scan\ndefine-syntax path (previously only compileLetSyntax did this), so that\nmacros defined inside let/lambda bodies correctly know which literals\nwere lexically bound at their definition site.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Redesign literal binding check: per-literal flag + on-demand callback\n\nReplace the snapshot-based approach (captured_locals reuse + use_locals\narray) with two independent mechanisms:\n\n  1. Per-literal def-site flag: parseSyntaxRules records a literal_bound[]\n     array in the Transformer, checked via isLexicallyBound at definition\n     time.  Body-prescan define names are passed as extra_bound so sibling\n     body defines are visible.\n\n  2. On-demand use-site callback: expandMacro receives a UseSiteBindingCheck\n     whose check_fn walks the full Compiler parent chain (isLexicallyBound)\n     and skips is_global_alias entries injected by the hygiene machinery.\n\nThis avoids the regressions from v1 (populating captured_locals activated\nthe injection machinery and corrupted body-defined macro expansions),\neliminates the 256-local silent cap, and correctly handles closure\nbindings and nested expansions.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Compare binding identity (slot), not just bound/unbound\n\nAddress review findings 3 and 6:\n\nFinding 3 (forward-reference): The body prescan now does a first-pass\nname scan to collect ALL leading define names before processing any\ndefine-syntax.  This ensures forward-declared body defines are visible\nin the literal_bound array regardless of textual order (letrec* semantics).\n\nFinding 6 (binding identity): literal_bound stores per-literal slot\nnumbers (u16) instead of booleans.  The use-site callback also returns\nthe resolved slot.  Two bindings with the same name but different slots\n(e.g. outer let vs inner let) are correctly distinguished.\n\nAlso fixes resolveLocalSkipAliases to iterate locals from the end (most\nrecent first), matching resolveLocal's behavior — the forward iteration\nwas finding the outer binding instead of the innermost shadowing one.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Handle define-syntax in lambda body prescan (compileLambdaWithIR)\n\ncompileLambdaWithIR had its own body prescan that only handled define,\nbreaking on any other form including define-syntax.  This meant define-\nsyntax in a lambda body fell through to compileDefineSyntax which has no\nbody-define context, causing forward-referenced define literals to appear\nunbound — a regression vs main.\n\nAdd a first-pass name scan and define-syntax processing to the\ncompileLambdaWithIR prescan, mirroring the two-pass pattern already used\nin compileBodyForms.  Lambda bodies, procedure bodies, and let bodies\nnow all see the complete letrec* region when resolving literal bindings.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-06T21:28:01+05:30",
          "tree_id": "6cec4b7d8ba66d87506205b2bf8e2b6ea618e108",
          "url": "https://github.com/kaappi/kaappi/commit/a10759f1a07bc188d025d24e549210abc601d5e9"
        },
        "date": 1783355327237,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.298222,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.502861,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.929237,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.154408,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012347,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.212778,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.476035,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.06993,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.447497,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.850973,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 10.010509,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.953443,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.397933,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.685087,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042537,
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
          "id": "a6a20dcc44179fd9fe890f4fbaa7dd7697de6d30",
          "message": "Honor fold-case flag in include-ci (R7RS 4.1.7) (#1274)\n\n* Honor fold-case flag in include-ci (R7RS 4.1.7) (#1141)\n\nThe ci parameter was discarded in both the top-level and library-context\ninclude paths, so include-ci read files case-sensitively. Set\nreader.fold_case from the ci flag in handleTopLevelInclude and\ncompileLibInclude.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Add test for #!no-fold-case inside include-ci'd file\n\nPins down the \"as if it began with #!fold-case\" semantics: an explicit\n#!no-fold-case directive inside an included file restores case sensitivity\nfor the remainder of that file.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-06T23:44:13+05:30",
          "tree_id": "254d44a17acb57e901920014db81bf1626f662ea",
          "url": "https://github.com/kaappi/kaappi/commit/a6a20dcc44179fd9fe890f4fbaa7dd7697de6d30"
        },
        "date": 1783363411848,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.340729,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.179798,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.987511,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.168097,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.013219,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.214984,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.479891,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.071299,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.69096,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.853029,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 10.021597,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.955432,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.299912,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.712118,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043091,
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
          "id": "0f688e055cd975b6dd5a0daf749194a58713330d",
          "message": "Report syntax-error message and irritants (#1273)\n\n* Report syntax-error message and irritants (#1142)\n\nsyntax-error was returning a bare CompileError.InvalidSyntax, discarding\nthe message string and irritants that macro authors provide for diagnostics.\nNow formats them into a threadlocal buffer and reportCompileError includes\nthe detail in the output.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Clear stale syntax-error buffer at compile entry; avoid report overflow\n\nFixes two review issues:\n- The threadlocal syntax_error_detail buffer was only cleared in\n  reportCompileError, so a syntax-error caught via guard/eval leaked\n  into the next unrelated CompileError.InvalidSyntax. Now cleared at\n  the start of every compile entry point.\n- reportCompileError wrote prefix+detail into a single 768-byte buffer\n  that could overflow with long paths. Now writes prefix and detail as\n  separate writeStderr calls.\n\nAdds regression test for the cross-form stale-buffer case.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-06T23:44:48+05:30",
          "tree_id": "f5e0d6e4af4774b35c977cee859c7386fed065ac",
          "url": "https://github.com/kaappi/kaappi/commit/0f688e055cd975b6dd5a0daf749194a58713330d"
        },
        "date": 1783363542984,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.0352,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.921744,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.960385,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.060144,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.013653,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.234813,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.48074,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068202,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 13.396218,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.834518,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 11.090588,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.058596,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 9.103243,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.813635,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044686,
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
          "id": "b3a7e0303a957a158395feb28e1167cb9f80d531",
          "message": "Handle consecutive ellipses in syntax-rules templates (#1243) (#1278)\n\n* Handle consecutive ellipses in syntax-rules template instantiation (#1243)\n\nR7RS 4.3.2 allows a depth-N pattern variable to appear in a template\nfollowed by N ellipses, flattening nested matches into a single list.\nThe expander only consumed the first ellipsis and passed the rest as\nliteral template text, producing garbage output with a literal `...`\nsymbol.\n\nTeach instantiateEllipsis to detect and strip extra leading `...`\ntokens from rest_template.  When extra ellipses are present, each\nouter iteration builds a synthetic template with the remaining\nellipses and recurses through instantiateTemplate, then splices the\nresulting list into the output.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Hoist synthetic template out of loop, simplify guard, add custom-ellipsis test\n\nAddress review feedback:\n- Build the synthetic (elem ... ...) template once before the loop\n  instead of on every iteration — it is invariant across iterations.\n  Root it with defer so popRoot runs on all exit paths.\n- Drop redundant `!= NIL` in the true_rest loop guard (NIL is never\n  a pair).\n- Add a custom-ellipsis test case (syntax-rules ::: ...) for the\n  synthetic template path.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-06T23:45:35+05:30",
          "tree_id": "2fb36a5c1d1abfbd2fb1d46ab72f98c942c90c17",
          "url": "https://github.com/kaappi/kaappi/commit/b3a7e0303a957a158395feb28e1167cb9f80d531"
        },
        "date": 1783363747753,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.330432,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.871209,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 1.023189,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.383738,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012532,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.212674,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.490295,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.071511,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.450741,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.896845,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 10.165032,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.959,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.385138,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.711668,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043304,
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
          "id": "920e41a3d026593c980629fb1031d2c7d5a14c9c",
          "message": "Signal error on define/set! in immutable environments (#1147) (#1275)\n\n* Signal error on define/set! in immutable environments (#1147)\n\nR7RS 6.12 requires that environments created by (environment ...),\n(null-environment), and (scheme-report-environment) are immutable.\nPreviously, define and set! in these environments silently succeeded\n(as a mutable private copy). Now the VM signals an error, which is\ncatchable by guard/with-exception-handler.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Update tests for immutable environment semantics\n\nenv-uaf.scm: use let instead of define (GC safety path is the same —\nfunc.env still points to the env map regardless of binding mechanism).\n\nload-env-1190.scm: verify that load into an immutable (environment ...)\nsignals an error, matching R7RS 6.12.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Block define-syntax in immutable environments and deduplicate guard\n\nAddress review feedback:\n- define-syntax in an immutable environment now errors at compile time\n  and macros are no longer copied back to vm.macros (preventing global leak)\n- Factor duplicate immutability check in set_global/define_global into\n  rejectImmutableEnv helper, resolving duplicate sym lookup\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-06T23:55:29+05:30",
          "tree_id": "cb5047dc032d6ca079608a6cdf3fd583f9e49167",
          "url": "https://github.com/kaappi/kaappi/commit/920e41a3d026593c980629fb1031d2c7d5a14c9c"
        },
        "date": 1783364299527,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.349365,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.022647,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.959743,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.287784,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012483,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.212297,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.483169,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.072148,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.596962,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.905235,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.999352,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.952445,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.325968,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.714318,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042857,
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
          "id": "2f18fe3a8dc9d50470e1c42e850d6e361100221c",
          "message": "Desugar define-record-type in body contexts (R7RS §5.5) (#1276)\n\n* Desugar define-record-type in body contexts (R7RS §5.5) (#560)\n\ndefine-record-type was only handled at top-level via the VM interpreter.\nInside let/lambda/letrec bodies, the body scanners didn't recognise it\nas a definition form, causing \"undefined variable\" errors.\n\nExpand define-record-type into equivalent define forms (using existing\n%make-record-type, %make-record, %record?, %record-ref, %record-set!\nprimitives) during the body-scanning phase. The desugared defines enter\nthe existing letrec* machinery so scoping works correctly in all contexts.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Address review feedback: general dispatch, error propagation, shared parser\n\n- Add compileDefineRecordType general dispatch in compiler.zig so\n  define-record-type works in let-values, let*-values, and begin-\n  spliced body positions (not just leading-define regions)\n- Propagate OutOfMemory/TooManyLocals from body-scanner catch sites\n  instead of silently breaking on all errors\n- Refactor handleDefineRecordType to call parseRecordSpec (single\n  source of truth for record grammar parsing)\n- Add let-values and let*-values test cases\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-07T00:06:24+05:30",
          "tree_id": "4985588b1d1790361a4c1b1731f0a23db6ccc4a7",
          "url": "https://github.com/kaappi/kaappi/commit/2f18fe3a8dc9d50470e1c42e850d6e361100221c"
        },
        "date": 1783364741014,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.345059,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.150689,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.923391,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.166264,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012452,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.211899,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.473719,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070481,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.398523,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.865821,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.951384,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.948085,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.294196,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.672422,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042397,
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
          "id": "93a3c2a971ac2bcf7749c538b23cb46f6ececc0c",
          "message": "Separate let-syntax from letrec-syntax scoping (#1140) (#1277)\n\n* Separate let-syntax from letrec-syntax scoping (#1140)\n\nlet-syntax was giving letrec-syntax semantics: sibling macro bindings\ncould see each other's keywords. R7RS 4.3.1 specifies that let-syntax\ntransformer specs are evaluated in the outer syntactic environment.\n\nParse all transformer specs before registering any bindings, store each\nkeyword's outer macro value on the Transformer, and temporarily swap\nmacros during expansion result compilation so template free references\nresolve to the definition-site environment.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Address review feedback: remove 32-binding cap, extract helpers\n\n- Replace fixed stack arrays with ArrayLists so let-syntax accepts\n  arbitrarily many bindings (matching letrec-syntax behavior).\n- Extract captureLocalsOnTransformer, compileSyntaxBody, and\n  restoreMacros helpers to deduplicate let-syntax / letrec-syntax.\n- Use dynamically allocated saved_peer in expandAndCompileMacroUse\n  instead of a fixed [32]?Value array.\n- Fix gc_deep_copy.zig: propagate OOM from peer_names dupe instead\n  of silently substituting &.{}, add errdefer for peer_vals.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Fix GC-safety and OOM handling in let-syntax\n\n- Pre-allocate tx_vals to exact capacity before the parse loop so\n  pushRoot pointers into its backing buffer stay valid across appends.\n- Propagate OOM from captureLocalsOnTransformer instead of silently\n  dropping captured locals.\n- Propagate OOM from saved_peer allocation in expandAndCompileMacroUse\n  instead of silently skipping the peer swap.\n- Add debug assert for peer_names/peer_outer slice length equality.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-07T00:44:39+05:30",
          "tree_id": "e7bc80eae3e2db4a5f03496fce73dda933625c09",
          "url": "https://github.com/kaappi/kaappi/commit/93a3c2a971ac2bcf7749c538b23cb46f6ececc0c"
        },
        "date": 1783366865845,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.351732,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.726059,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 1.069504,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.498487,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012375,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.212961,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.560104,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.073288,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.352747,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 2.01817,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.948937,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.948797,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.291323,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.667548,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042554,
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
          "id": "08f07191252b549bc18c29bf6a7b5a4e171a8004",
          "message": "Compile eval body in tail position per R7RS 3.5 (#1279)\n\n* Compile eval body in tail position per R7RS 3.5 (#1253)\n\nEach nested eval consumed one VM call frame because Compiler.compile()\nhardcoded is_tail=false when lowering IR and emitting bytecode. Even\nthough the tail_eval opcode correctly replaced the current frame, the\ncompiled expression used call+return instead of tail_call, pushing a\nframe per iteration and hitting StackOverflow at the 32768 cap.\n\nThread an is_tail parameter through compile() → compileExpressionWithMacrosAt()\n→ compileExpressionInEnv() so the tail_eval opcode handler can compile\nwith tail-position awareness. All other callers pass false.\n\nAlso add Function.restricted_globals to suppress the get_global fallback\nto VM globals for restricted environments (null-environment), which was\nexposed by tail-position compilation routing global calls through\nget_global instead of call_global.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Address review feedback: test, timing, comment\n\n- Add regression test for restricted_globals: null-env eval in tail\n  position (via guard desugaring) must error on car, not leak VM globals\n- Lower N from 50000 to 40000 to keep headroom within the 60s Debug CI\n  timeout (40000 still exceeds the 32768 frame cap)\n- Add comment explaining why the hygienic-prefix fallback in get_global\n  is intentionally ungated by restricted_globals\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-07T00:56:51+05:30",
          "tree_id": "d0bc3b086fba6baed9af7088df91b659af8bbbee",
          "url": "https://github.com/kaappi/kaappi/commit/08f07191252b549bc18c29bf6a7b5a4e171a8004"
        },
        "date": 1783367602624,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.373965,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.005653,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 1.05766,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.47844,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012408,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.213271,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.539571,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.072223,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.455749,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 2.002769,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.9823,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.956407,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.329721,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.723451,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044163,
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
          "id": "6f383b80cf337a7ef9be698c0eb32b2f010b31c5",
          "message": "Follow redirect chain in force for delay-force intermediates (#1280)\n\n* Follow redirect chain in force for delay-force intermediates (#1264)\n\nAfter a delay-force chain completes, the SRFI-45 merge step redirects\nintermediate promises to point at the chain head. The force trampoline\nreturned these redirect pointers directly instead of following them to\nthe memoized value. Continue trampolining at all three return sites\n(memoization check, re-entrant check, inner-already-forced) so the\nchain is always resolved to its final value.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Add comment explaining redirect-follow invariant in force\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-07T02:52:42+05:30",
          "tree_id": "bae8539fcba3b941bba87fb7d6e064b7f79ebd34",
          "url": "https://github.com/kaappi/kaappi/commit/6f383b80cf337a7ef9be698c0eb32b2f010b31c5"
        },
        "date": 1783374591333,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.037863,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.607385,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.992398,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.04558,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.013836,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.23466,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.477102,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068186,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 13.485789,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.824943,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 11.082968,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.08017,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 9.173954,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.87295,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.048062,
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
          "id": "d0bd85603ef64adbfecc984c150f28a39f532ae0",
          "message": "Use globally-unique binding IDs for syntax-rules literal identity (#1272) (#1284)\n\nReplace per-frame slot numbers (u16) with monotonic binding IDs (u32)\nwhen comparing literal identities in syntax-rules. Slot indices are\nscoped to their owning Compiler frame, so two different bindings in\nnested lambdas occupying the same register falsely compared as equal.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-07T07:46:17+05:30",
          "tree_id": "212c97b9f62ebcb386205c76ae382434f51db09f",
          "url": "https://github.com/kaappi/kaappi/commit/d0bd85603ef64adbfecc984c150f28a39f532ae0"
        },
        "date": 1783392160459,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.029627,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.276326,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.96394,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.053865,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.013844,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.235044,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.475433,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069048,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 13.503269,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.835768,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 11.176586,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.066743,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 9.124309,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.82944,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044498,
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
          "id": "c0fb97145a66e78db1e6f4f9328c558e029068a1",
          "message": "Unify platform feature lists across (features) and cond-expand (#1177) (#1283)\n\nThree call sites hardcoded divergent feature lists: (features) lacked\nexact-closed and exact-complex, expression-level cond-expand lacked\nexact-complex, while library-level cond-expand had both. R7RS §6.14\nrequires (features) to return exactly the identifiers cond-expand\ntreats as true. Introduce a single types.platform_features constant\nconsulted by all three sites.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-07T07:45:00+05:30",
          "tree_id": "5bcd5eb7912b52bc2b7a27e03f2e9aef3e29bbde",
          "url": "https://github.com/kaappi/kaappi/commit/c0fb97145a66e78db1e6f4f9328c558e029068a1"
        },
        "date": 1783392209447,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.326123,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.175948,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 1.041455,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.655409,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012499,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.21367,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.522317,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.072414,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.464631,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 2.024833,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 10.010231,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.955567,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.357876,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.777324,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044318,
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
          "id": "4ccbf0f45f2f9d438419f17557480a4c305eeae8",
          "message": "Check record type in accessors and mutators (#1199) (#1281)\n\n* Check record type in accessors and mutators (#1199)\n\nRecord accessors and mutators desugared from define-record-type now\nverify that the argument is an instance of the correct record type,\nnot just any record. Previously, passing a record of a different type\nwith enough fields would silently read/write the wrong field — a data\ncorruption hazard.\n\nThe fix passes the expected record type as an additional argument to\nthe internal %record-ref and %record-set! primitives, which compare\nit against the instance's record_type pointer. All three desugaring\npaths (VM top-level, body-context expansion, and compiler dispatch)\nare updated.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Guard record-type argument before downcast in %record-ref/%record-set!\n\nAdd isRecordType checks before the toObject().as(RecordType) downcast\nso that passing a non-record-type value (e.g. a fixnum) raises a\nproper Scheme error instead of dereferencing a bogus pointer. Also\nupdate audit tests to exercise the 3-arg %record-ref and add a\n%record-set! bad-type-arg test.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-07T10:02:40+05:30",
          "tree_id": "8b80d11ea45ad6625141f42827806f4a9e1af61c",
          "url": "https://github.com/kaappi/kaappi/commit/4ccbf0f45f2f9d438419f17557480a4c305eeae8"
        },
        "date": 1783400386116,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.302654,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.528741,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.931223,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.11007,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012482,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.211994,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.471203,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069851,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.361487,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.820717,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.969643,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.943727,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.280719,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.71956,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043239,
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
          "id": "3d54b53a075e39c85b30ae12c40a4acb9b3d7a3f",
          "message": "Reject non-environment second argument to eval (#1270) (#1282)\n\n* Reject non-environment second argument to eval (#1270)\n\nBoth code paths for eval (the evalFn native function and the tail_eval\nbytecode opcode) silently ignored a non-environment second argument,\nfalling through to the global-environment path. Now they raise a type\nerror, matching load's behavior per R7RS §6.12.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Address review: collapse redundant check, add tail-position test, match error message\n\n- evalFn: fold guard + isEnvironment into single branch (redundant re-check)\n- tail_eval: include offending value in error message for parity with native path\n- Add test where eval is in tail position to exercise the tail_eval opcode\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Add trailing #f to tail-position test so it fails without the fix\n\nWithout the #f, the guard body returns 3 (truthy) when the bug is\npresent, making the test-assert a tautology.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-07T04:52:13Z",
          "tree_id": "080797ef6127f57cbccd2dd9a2d96233f010a145",
          "url": "https://github.com/kaappi/kaappi/commit/3d54b53a075e39c85b30ae12c40a4acb9b3d7a3f"
        },
        "date": 1783401520094,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.044428,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.013211,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.956265,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.041892,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.013686,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.235028,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.477587,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068319,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 13.36456,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.835907,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 11.093378,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.060432,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 9.145984,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.821689,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044496,
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
          "id": "f68f43faa08b28eab8d4b30c73ceb7c2b811769f",
          "message": "Enforce immutability on literal vectors, pairs, and bytevectors (#1173) (#1285)\n\n* Enforce immutability on literal vectors, pairs, and bytevectors (#1173)\n\nR7RS §3.4 requires literal constants to be immutable. Strings already\nenforced this via SchemeString.immutable, but vectors, pairs, and\nbytevectors allowed silent mutation of shared literals — causing\nself-modifying code across calls.\n\nMirror the string pattern: add an `immutable` flag to Vector, Pair, and\nBytevector structs, mark reader-produced literals, and guard all 13\nmutating primitives (vector-set!, vector-fill!, vector-copy!,\nvector-swap!, vector-reverse!, set-car!, set-cdr!, list-set!,\nbytevector-u8-set!, bytevector-copy!, read-bytevector!).\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Address review feedback: pack immutable into Object header, read returns mutable data\n\n- Pack marked/generation/survive_count/immutable into a single\n  Object.Flags(u8) packed struct — keeps Object at 16 bytes and makes\n  the immutable bit free for all heap types (Pair, Vector, Bytevector\n  stay at 32 bytes; SchemeString drops from 48 to 40).\n\n- Add Reader.mark_immutable flag (default true). The 4 Reader sites in\n  primitives_io.zig (the `read` procedure) set it to false, so data\n  returned by `(read ...)` is mutable per R7RS §6.13.2 while source-code\n  literals remain immutable per §3.4.\n\n- Migrate SchemeString.immutable to the header flag for consistency.\n\n- Rewrite smoke test to SRFI-64; add 3 tests verifying read returns\n  mutable pairs, vectors, and strings.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-07T05:13:41Z",
          "tree_id": "282e5dcca884c803d9f10d7265c96eedb0ed6eec",
          "url": "https://github.com/kaappi/kaappi/commit/f68f43faa08b28eab8d4b30c73ceb7c2b811769f"
        },
        "date": 1783402789129,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.376321,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.610198,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.924007,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.14654,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012495,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.212209,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.470933,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070969,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.448054,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.845875,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.958997,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.949906,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.311644,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.522281,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043056,
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
          "id": "138405792348afb54d9872a37a2297ebf20864e2",
          "message": "Capture let/lambda locals in define-syntax transformers (#1271) (#1287)\n\ndefine-syntax did not call captureLocalsOnTransformer, so free\nreferences to let/let*/lambda-bound variables in syntax-rules\ntemplates were hygienically renamed but never aliased back,\nproducing \"undefined variable '__hyg_N_var'\" errors.\n\nAdd the same captureLocalsOnTransformer call that let-syntax\nalready uses to all three define-syntax code paths (top-level,\nbody scan in compileBodyForms, and IR body scan).\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-07T06:06:08Z",
          "tree_id": "5fb21c496a5254c264823f17b903ae39b2127d5f",
          "url": "https://github.com/kaappi/kaappi/commit/138405792348afb54d9872a37a2297ebf20864e2"
        },
        "date": 1783405883731,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.283668,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.750866,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.916016,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.13528,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012521,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.212313,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.463503,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070279,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.47823,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.816599,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.974129,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.954891,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.289591,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.707503,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042795,
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
          "id": "9b8fb278de10a0e1ce1f52170fe40d4b16959227",
          "message": "Move parameterize converter application outside dynamic-wind extent (#1266) (#1286)\n\nThe inner let* was mutating parameter cells (via the set-then-read idiom)\nbefore dynamic-wind was entered. This caused converters to observe\nearlier bindings' new values, converter errors to permanently leak\nmutations, and duplicate params to restore wrong values.\n\nAdd %parameter-convert primitive that applies a parameter's converter\nwithout mutating the cell, and use it in the parameterize desugaring so\nall mutation happens inside dynamic-wind's before/after thunks.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-07T06:03:16Z",
          "tree_id": "770042ed8aeee4bae07003401494adce3d78e4fb",
          "url": "https://github.com/kaappi/kaappi/commit/9b8fb278de10a0e1ce1f52170fe40d4b16959227"
        },
        "date": 1783405927553,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.288536,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.499376,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.89305,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.073926,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012664,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.21202,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.462713,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069936,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.49279,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.81498,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.971696,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.96105,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.323578,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.708358,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.046314,
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
          "id": "8680c99bdd1fe57c4d5cc611e6b7269c9447aa4a",
          "message": "Accept multiple comma-separated labels in /parallel-issues skill (#1290)\n\nPreviously the skill accepted a single label. Now labels can be\ncomma-separated (e.g. \"bug,macros\"), each becoming a --label flag\nso gh issue list AND-filters them. The no-fallback rule applies to\nthe full label set.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-07T12:39:23+05:30",
          "tree_id": "42aaae2ca7f4af1a492c7111f9096be875074582",
          "url": "https://github.com/kaappi/kaappi/commit/8680c99bdd1fe57c4d5cc611e6b7269c9447aa4a"
        },
        "date": 1783409708109,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.277771,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.730941,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.90506,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.129825,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012607,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.212113,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.463144,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070502,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.519609,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.828182,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.972544,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.960718,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.284503,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.69751,
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
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "c0ae1aecd207bd8ca3ec5881634203e95a7b33ca",
          "message": "Support import-set modifiers in environment (#1189) (#1289)\n\nRoute environment's arguments through processImportSet (the same path\nused by import) instead of manually calling libraryNameToString, which\nonly accepted plain library names. This adds support for only, except,\nprefix, rename, and nested combinations.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-07T13:49:33+05:30",
          "tree_id": "c7731a9f2ab023f306153101560fb33461ac88bc",
          "url": "https://github.com/kaappi/kaappi/commit/c0ae1aecd207bd8ca3ec5881634203e95a7b33ca"
        },
        "date": 1783414019739,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.373544,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.846645,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.929209,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.186819,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012509,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.212337,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.469579,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070325,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.581109,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.820197,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 10.005867,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.956699,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.326387,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.588792,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.04333,
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
          "id": "1679510915730eb84056d9b978ac7c761d8164a3",
          "message": "Root hash-table-walk/fold snapshot entries to prevent use-after-free (#1181) (#1294)\n\n* Root hash-table-walk/fold snapshot entries to prevent use-after-free (#1181)\n\nsnapshotLiveEntries copies live entries into a raw allocator buffer that\nthe GC cannot see. When the callback deletes entries and allocates, the\ncollector frees the snapshot's keys/values; subsequent iterations pass\ncorrupted objects to the callback. Root all snapshot keys/values via\ngc.extra_roots within a rootedScope so they survive collection.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Add comment explaining why snapshot rooting is a separate pre-pass\n\n---------\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-07T10:47:36Z",
          "tree_id": "af1f19a4a4eab25907bc079f56bed3f0c4df12be",
          "url": "https://github.com/kaappi/kaappi/commit/1679510915730eb84056d9b978ac7c761d8164a3"
        },
        "date": 1783422884632,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.171736,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.608299,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.730849,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.135274,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.010725,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.183847,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.367289,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.05279,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 9.748294,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.419664,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 8.689023,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.834876,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 7.126707,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.365142,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.035245,
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
          "id": "d397ceb087172e2263e0ae06c3b945428bb5f2e1",
          "message": "Clear stale registers in tail-call window extension (#1256) (#1293)\n\n* Clear stale registers in tail-call window extension (#1256)\n\nThe three tail-call opcodes (tail_call, tail_call_global, tail_call_cc)\nmutate the frame in place but never cleared registers beyond the copied\nargs. When the new callee has a larger locals_count than the old one,\nthe GC scan window extends over registers that may hold stale pointers\nfrom previously-popped child frames, causing SIGSEGV under gc-stress.\n\nFix: call clearFrameLocals at each tail-call closure site, matching what\ncallClosure already does for regular calls.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Address review: fix tail_apply/tail_eval, add Zig unit test\n\n- Add clearFrameLocals to tail_apply and tail_eval closure paths\n  (same stale-register bug class, caught by CodeRabbit)\n- Add Zig unit test that directly asserts the mechanism: pollutes\n  high registers with heap objects, then tail-calls into a larger\n  frame and verifies extension registers are not stale pointers\n  (per reviewer feedback that the Scheme test passes on unfixed builds)\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Rewrite Zig test to fail without the fix\n\nThe previous test passed on unfixed builds because big's body wrote\nfixnums to the same extension slots clearFrameLocals targets. Use a\nbranching callee whose locals_count is large (from the false branch)\nbut whose taken branch doesn't touch the high registers — leaving\nthem in whatever state the tail-call handler left them.\n\nVerified: 659/660 tests pass on unfixed vm_dispatch.zig (this test\nfails), 660/660 pass with the fix.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-07T11:07:23Z",
          "tree_id": "427befb6cbb00e4ae8289244dd5e10eb83484a92",
          "url": "https://github.com/kaappi/kaappi/commit/d397ceb087172e2263e0ae06c3b945428bb5f2e1"
        },
        "date": 1783424023533,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.290162,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.886978,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.939347,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.250463,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.01245,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.20064,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.475528,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070937,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.519804,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.837215,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 10.006695,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.953466,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.295263,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.637444,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.04236,
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
          "id": "f1cfea2787256200b33708a009c77e488f1d43c9",
          "message": "Increase CI timeout for Debug test job (#1295) (#1296)\n\nDebug builds are ~500x slower for allocation-heavy workloads, so the\nScheme test suite barely finishes within 20 minutes, leaving no headroom\nfor the post-job Zig cache upload (~982 MB). Bump the Debug matrix entry\nto 30 minutes while keeping the default 20 minutes for other variants.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-07T16:57:11+05:30",
          "tree_id": "5fc0f19d213c68041d33612cbbebfaa002d4fb13",
          "url": "https://github.com/kaappi/kaappi/commit/f1cfea2787256200b33708a009c77e488f1d43c9"
        },
        "date": 1783425198932,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.006242,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.887214,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.949378,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.021352,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.013897,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.22096,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.476789,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069349,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 13.510786,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.826423,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 11.124792,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.084873,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 9.115968,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.933636,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045718,
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
          "id": "0f4f2ffe6c3a224c94e433474393da30a09394f2",
          "message": "Add GC write barriers to readListTail setCdr calls (#1267) (#1292)\n\n* Add GC write barriers to readListTail setCdr calls (#1267)\n\nThe two in-place pair mutations in readListTail (dotted-tail and\nproper-list append) lacked generational-GC write barriers, creating\nuntracked old→young edges that could cause use-after-free during\nminor collections when reading long lists.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Reframe reader tests as GC-stress smoke tests, add car-payload checks\n\nThe write barriers can't be regression-tested at the reader level because\nmarkRoots traces transitively through old objects, so the rooted result\nkeeps the entire spine alive regardless of remembered-set state. Reframe\nthe tests honestly as smoke tests and add car-value assertions per review.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-07T18:53:23+05:30",
          "tree_id": "e7a0c9dfbb21b956978677084adfa9895d5ad678",
          "url": "https://github.com/kaappi/kaappi/commit/0f4f2ffe6c3a224c94e433474393da30a09394f2"
        },
        "date": 1783432367960,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.013557,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.987853,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.938874,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.168075,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.013716,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.220872,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.47305,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068054,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 13.436248,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.82848,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 11.132329,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.070307,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 9.109936,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.860202,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045327,
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
          "id": "6d33cb0701042533918f9a24710ccfc3a0b2aeaa",
          "message": "Make GC root buffer growable to handle deep native re-entrancy (#1191) (#1298)\n\n* Make GC root buffer growable to handle deep native re-entrancy (#1191)\n\nThe fixed-size root buffer (4096 entries) panicked on deeply nested\nnative→Scheme→native re-entrancy (e.g. recursive map at depth 2000).\nThe panic was uncatchable, violating R7RS's expectation that resource\nexhaustion can be intercepted by guard.\n\nChange the root buffer from a fixed array to a heap-allocated slice\nthat starts at 1024 entries and doubles on demand up to 65536.  This\nlets legitimate deep recursion succeed while the existing\nnative_reentry_depth guard (3000) still catches infinite re-entrancy\nwith a catchable StackOverflow error.\n\nAlso fix the callReentrant root-count guard to compare against the\nabsolute MAX_ROOT_CAPACITY rather than the current buffer length, so\nit doesn't fire prematurely during buffer growth.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Address review: clamp root growth, fix tests for Debug mode\n\n- growRootBuffer now clamps to MAX_ROOT_CAPACITY before reallocating\n  instead of panicking on overshoot (CodeRabbit)\n- Deep-recursion tests accept either success or caught error, so they\n  pass in both Release (cap 3000) and Debug (cap 200) builds (baijum)\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-07T20:24:08+05:30",
          "tree_id": "eb1bac26ba28bacf1c28c83c20d67ec073509524",
          "url": "https://github.com/kaappi/kaappi/commit/6d33cb0701042533918f9a24710ccfc3a0b2aeaa"
        },
        "date": 1783437665548,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.102858,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.71033,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.945949,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.179818,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.013695,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.222695,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.478717,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068273,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 13.471456,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.839392,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 11.167731,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.05962,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 9.15255,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.853577,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.046321,
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
          "id": "370d9d4b83710b08bc786cd2087e98f10eb9ea69",
          "message": "Move entitlements plist from repo root to .github/ (#1299)\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-07T15:46:12Z",
          "tree_id": "f8aaa9f1c7a51cea70b2aaa609b8ee7c0bcd508d",
          "url": "https://github.com/kaappi/kaappi/commit/370d9d4b83710b08bc786cd2087e98f10eb9ea69"
        },
        "date": 1783440638654,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.097328,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 10.509981,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.963547,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.10943,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.014631,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.221883,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.4803,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068399,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 13.449092,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.834661,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 11.146377,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.064411,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 9.130676,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.725798,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.046087,
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
          "id": "d435ee868c976f29c510b559d564df754c428e54",
          "message": "Fix hygiene: use-site arg no longer captured by same-name def-site local (#1288) (#1301)\n\nTemplate free references are now hygienically renamed to __hyg_N_<name>\ninstead of being kept bare via VOID sentinels. This lets\ninjectHygienicCapturedLocals map them to the correct captured slot while\nuse-site argument symbols keep their original binding. Also fix\ninjectHygCapturedWalk to use last-match (innermost scope) when multiple\ncaptured locals share a name.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-07T16:08:47Z",
          "tree_id": "92d2bbfdba74237f795ba650b3e7a897ccc6eae3",
          "url": "https://github.com/kaappi/kaappi/commit/d435ee868c976f29c510b559d564df754c428e54"
        },
        "date": 1783442265758,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.401621,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.570831,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.774411,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.343406,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.013966,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.208609,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.382255,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.058766,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 13.023705,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.441838,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 10.535288,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.014078,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.486272,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.20803,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.039481,
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
          "id": "337fb517deeab958f113f92f209fdc2a702ce4fb",
          "message": "Honor timeout deadlines when no fibers are runnable (#1153) (#1300)\n\n* Honor timeout deadlines when no fibers are runnable (#1153)\n\nWhen schedule() returned null (no runnable fibers), runSchedulerUntilMutex,\nrunSchedulerUntilCondVar, and runSchedulerUntilDone broke out of their loops\nwithout honoring the fiber's deadline. This caused mutex-lock! with a timeout\non a locked mutex to steal the lock (return #t immediately instead of #f),\nand mutex-unlock! with a condvar+timeout to falsely succeed.\n\nSleep until the deadline when the scheduler runs dry, then report timeout.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Clear stale deadline_ns after timed waits and restore comments\n\nAfter runSchedulerUntilMutex/CondVar, the fiber's deadline_ns was left\nset from the previous timed wait. A later untimed wait on the same fiber\nwould inherit the expired deadline and spuriously time out. Clear it in\nboth callers after the wait returns.\n\nAlso restore the yield_retry and fiber-0 explanatory comments that were\naccidentally removed in the previous commit.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Extract scheduleOrTimeout helper and fix stale-deadline test\n\nExtract the duplicated deadline-fallback logic from all three\nrunSchedulerUntil* functions into a shared scheduleOrTimeout helper.\n\nFix the stale-deadline regression test to actually exercise the blocking\npath: the previous version called mutex-unlock! before the untimed lock,\nso the fast path was taken and deadline_ns was never read. Now spawns a\nfiber to hold the mutex so the untimed lock must block through the\nscheduler.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-07T16:49:19Z",
          "tree_id": "f700c7bbcc6ac7c45dfc71cafbccdfed6fdd4e69",
          "url": "https://github.com/kaappi/kaappi/commit/337fb517deeab958f113f92f209fdc2a702ce4fb"
        },
        "date": 1783444586123,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.108259,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.664776,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.973014,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.225792,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.013803,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.221152,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.478721,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068942,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 13.445404,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.832269,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 11.150682,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.065689,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 9.152058,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.909619,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045646,
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
          "id": "c42805aabe756fcc0b28c66067d505cdf970745d",
          "message": "Let imported macros shadow built-in special forms (#1237) (#1302)\n\n* Let imported macros shadow built-in special forms (#1237)\n\nThe compiler dispatched special form keywords (define, set!, etc.)\nbefore consulting the macro table, so a syntax-rules macro exported\nunder a special form name — like SRFI-219's curried `define` — was\ndead on arrival.\n\nMove the macro lookup ahead of the special form string comparisons in\nboth the IR lowering path (ir.zig) and the legacy compiler path\n(compiler.zig).  Add fixed-point detection in expandAndCompileMacroUse\nso that identity rules (e.g. SRFI-219 rule 3: (define x e) → (define\nx e)) terminate by falling through to the built-in handler instead of\nlooping.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Address review: consume suppress flag once, add let/begin tests\n\n- Clear suppress_macro_name the moment compileForm matches it, so the\n  flag only guards the single immediate re-dispatch and does not leak\n  into nested let/begin bodies compiled inline in the same Compiler.\n- Add regression tests for curried define inside let and begin bodies.\n- Add doc comment explaining why the depth-128 bound in\n  valuesStructurallyEqual is safe (structure sharing).\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-07T18:09:43Z",
          "tree_id": "e109e9fcb97edd2559ce75dda25e59f7ccc03e06",
          "url": "https://github.com/kaappi/kaappi/commit/c42805aabe756fcc0b28c66067d505cdf970745d"
        },
        "date": 1783449474338,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.333033,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.209177,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.952184,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.196329,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012428,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.200932,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.47864,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.071937,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.511193,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.869152,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.992549,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.957284,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.351318,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.707549,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.04347,
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
          "id": "4fdb4eb12e9d633265781ec9537474bb9e607530",
          "message": "Isolate macro tables for custom environments in eval/load (#1269) (#1304)\n\n* Isolate macro tables for custom environments in eval/load (#1269)\n\ndefine-syntax forms compiled through compileExpressionInEnv were leaking\ninto the global vm.macros table because all callers passed &vm.macros\ndirectly as the merge-back target. Move isolation to the callers: when\nthe environment is not the interaction environment (se.env != vm.globals),\ncreate a local copy of vm.macros and pass that instead. The local copy\nis discarded after compilation, preventing any macro leak.\n\nFor load, the local table lives outside the expression loop so macros\nfrom earlier expressions remain visible to later ones in the same file.\n\nRemove the immutability guard from compileExpressionInEnv (added in #1275)\n— it is now redundant since callers control which table receives the\nmerge-back.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Add mutable non-global env test as genuine regression guard (#1269)\n\nThe previous tests only exercised immutable environments (which already\nerror on define-syntax) and the interaction environment (which is\ncorrectly global). This test constructs a mutable non-global environment\nvia the internal Zig API — the exact case the caller-side isolation\ntargets — and verifies that define-syntax succeeds but does not leak\ninto vm.macros.\n\nConfirmed: fails without the fix (macro count increases by 1),\npasses with it.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-07T19:25:03Z",
          "tree_id": "56d13c1064ecf8cc73fb71b9745af274a655d4af",
          "url": "https://github.com/kaappi/kaappi/commit/4fdb4eb12e9d633265781ec9537474bb9e607530"
        },
        "date": 1783453868424,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.08881,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.905652,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 1.011462,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.405065,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.01371,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.222898,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.512141,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070944,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 13.435567,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 2.013937,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 11.143989,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.060675,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 9.1577,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.844286,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.046209,
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
          "id": "bf5d5813d33cc72386b39e2fb1f5b2c7fa6e8631",
          "message": "Fix group-info by name returning gid 0 (#1161) (#1307)\n\nZig 0.16's std.c.getgrnam is misdeclared as returning ?*passwd instead\nof ?*group. Reading .gid through the wrong struct layout always yielded\n0. Declare a local extern with the correct return type.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-08T10:48:09+05:30",
          "tree_id": "9b98490c0268dfb64185896d3cda77fc57f084d4",
          "url": "https://github.com/kaappi/kaappi/commit/bf5d5813d33cc72386b39e2fb1f5b2c7fa6e8631"
        },
        "date": 1783489897842,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.421279,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.184628,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.768483,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.450076,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012821,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.202567,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.391444,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.058584,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.574101,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.50246,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 10.239117,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.969953,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.238536,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.012129,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.04154,
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
          "id": "bbac070145333eca311ecb0f3bbba7a29bbaa2f7",
          "message": "Honor explicit #f thread arg in mutex-lock! as locked/not-owned (#1154) (#1306)\n\nSRFI-18 specifies that when the thread argument to mutex-lock! is #f,\nthe mutex becomes locked/not-owned. The owner assignment logic treated\nany non-fiber value as \"absent\" and fell back to the current thread.\nAdd an explicit check for #f in all three owner-assignment sites\n(abandoned path, fast path, contended path).\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-08T10:47:40+05:30",
          "tree_id": "990ad62630a64c202175480002a26c5f6dc21ca1",
          "url": "https://github.com/kaappi/kaappi/commit/bbac070145333eca311ecb0f3bbba7a29bbaa2f7"
        },
        "date": 1783489937562,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.33734,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.341494,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.971673,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.442243,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012581,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.201556,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.503789,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.072292,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.500748,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.955419,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 10.071645,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.951036,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.332446,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.720042,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.04409,
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
          "id": "21e581abb45adb51304333aacbff5d9c18563607",
          "message": "Make default-random-source a variable, not a procedure (#1192) (#1305)\n\nSRFI-27 specifies default-random-source as a variable bound to a random\nsource object. Kaappi was exporting it as a zero-argument native procedure,\nso portable code like (random-source-state-ref default-random-source) would\nfail with a type error.\n\nRename the primitive to %default-random-source (internal) and define the\npublic binding in lib/srfi/27.sld as a variable that calls it once at\nlibrary load time.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-08T10:45:36+05:30",
          "tree_id": "151475e0f9e08f61ea836eb175b0e85f20097c75",
          "url": "https://github.com/kaappi/kaappi/commit/21e581abb45adb51304333aacbff5d9c18563607"
        },
        "date": 1783489985893,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.349141,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.253153,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.996399,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.405182,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012845,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.201375,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.501185,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.072105,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.498921,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.949765,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 10.014938,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.951448,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.309655,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.687586,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044144,
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
          "id": "2ac9c16ac9061650674f78a3abab700ef1091d4b",
          "message": "Fix bitwise and/ior/xor for negative operands in SRFI-151/143 (#1214) (#1310)\n\nThe bit-walking helpers used truncating quotient and terminated only at\nzero, ignoring the two's-complement fixed point at -1.  This produced\nwrong results for every bitwise operation involving a negative operand.\narithmetic-shift right had the same truncation bug.\n\nFix: add -1 base cases to and/ior/xor recursion, switch quotient →\nfloor-quotient in the recursive step and in arithmetic-shift right.\nSRFI-60 inherits the fix via its SRFI-151 re-exports.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-08T10:54:09+05:30",
          "tree_id": "7e298a4a3ba8b6e3081f6248bf951258f43d27d6",
          "url": "https://github.com/kaappi/kaappi/commit/2ac9c16ac9061650674f78a3abab700ef1091d4b"
        },
        "date": 1783490521362,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.361436,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.829021,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.975712,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.393753,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012498,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.201222,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.502235,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.071977,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.447869,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.940495,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 10.039837,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.95437,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.334826,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.683233,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043735,
            "unit": "seconds"
          }
        ]
      }
    ]
  }
}