window.BENCHMARK_DATA = {
  "lastUpdate": 1784140152056,
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
          "id": "e965c1bab1118b4b936f6c678cbc72a4183cbc0b",
          "message": "Fix non-exported library macros leaking to importers (#1332) (#1372)\n\ncopyTransformerFreeRefs copies free references of exported macros into\nthe importing environment so expansion chains work at the use site.\nWhen a free ref was itself a transformer, it was put into both vm.globals\n(as a value binding) and vm.macros (as a macro keyword), making\nnon-exported helper macros accessible via e.g. (display helper).\n\nSkip putting transformer free refs into vm.globals — they only need to\nbe in vm.macros for the compiler to expand them when the exported macro\nproduces code containing the helper keyword.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-09T11:41:51Z",
          "tree_id": "500c69ca09c8de9df8e8399dc0b7f6e2848f0f4a",
          "url": "https://github.com/kaappi/kaappi/commit/e965c1bab1118b4b936f6c678cbc72a4183cbc0b"
        },
        "date": 1783599275307,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.323339,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.023677,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.994178,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.384313,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012583,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.207109,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.504567,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070018,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.664344,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.936869,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 10.243939,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.00673,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.484902,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.719277,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043356,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "f75588de4b34f117138abb003f0325fc74572a6c",
          "message": "Fix SRFI-9 record-type redefinition retargeting old procedures (#1203) (#1371)\n\n* Fix record-type redefinition retargeting old procedures (#1203)\n\nThe desugared constructors/predicates/accessors/mutators referenced the\nrecord type through a global name resolved at call time.  Redefining the\nsame record type overwrote that global, silently retargeting every\npreviously created procedure to the new type.\n\nWrap each generated procedure in (let ((__rt <global>)) (lambda ...)) so\nthe record-type object is captured at definition time via closure.\nApplied to both the top-level path (handleDefineRecordType) and the body\ncontext path (expandRecordTypeDefines).\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Update stale comment in SRFI-9 test to reflect the fix\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-09T17:32:45+05:30",
          "tree_id": "81770361e9307bbba42f74f8198ea059886a5546",
          "url": "https://github.com/kaappi/kaappi/commit/f75588de4b34f117138abb003f0325fc74572a6c"
        },
        "date": 1783600207052,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.326211,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.066385,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.984779,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.380743,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012817,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.204798,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.505951,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069381,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.672672,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.950852,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 10.219527,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.0044,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.458626,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.701472,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043811,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "53034d9c9022375e8945ccd54b98bcab5b2bde82",
          "message": "Fix yield raising inside with-exception-handler after spawn (#1314) (#1369)\n\n* Fix yield raising inside with-exception-handler after spawn (#1314)\n\nTwo fixes:\n- yield is now a no-op when no other fibers are runnable (checks\n  scheduler.schedule() instead of just scheduler != null)\n- with-exception-handler propagates VMError.Yielded instead of\n  catching it and converting to a Scheme exception\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Drop with-exception-handler Yielded propagation\n\nReverts the withExceptionHandlerFn change per review: propagating\nVMError.Yielded through callReentrant discards the thunk's frames\n(native-frame limitation), producing a silent wrong value. The\nyieldFn schedule() check alone fixes #1314.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-09T17:31:37+05:30",
          "tree_id": "11fd4f7715a2632ade5728a5190f7064bec6beda",
          "url": "https://github.com/kaappi/kaappi/commit/53034d9c9022375e8945ccd54b98bcab5b2bde82"
        },
        "date": 1783600264906,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.273671,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.308032,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.965494,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.464661,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012604,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.204438,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.501082,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069016,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.69045,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.945853,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 10.193762,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.003445,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.424818,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.693697,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043464,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "569b698297c785290629a49fe89239dd5147296c",
          "message": "Add feasibility note on fuzzing Kaappi with Fuzzilli (#1373)\n\nFuzzilli is a recurring \"can we use this?\" question, but it generates\nJavaScript exclusively and Kaappi has no JS front-end, so it can't be\npointed at the interpreter directly. Record the analysis so the question\nresolves quickly next time, and redirect the energy: Kaappi already has\ncoverage-guided std.testing.fuzz targets and a fast in-process eval\nharness, so the payoff is applying Fuzzilli's ideas (CI wiring, seed\ncorpus, structure-aware generation, differential testing) rather than\nadopting the tool.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-09T18:02:19+05:30",
          "tree_id": "8751c2c53f4831920a7deeb42ef3ee97687a4d78",
          "url": "https://github.com/kaappi/kaappi/commit/569b698297c785290629a49fe89239dd5147296c"
        },
        "date": 1783603170993,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.320058,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.793162,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 1.041975,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.460919,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.013348,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.206061,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.505955,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069658,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.870785,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.966591,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 10.199743,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.005729,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.64652,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.76543,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045296,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "c7747d31714699542e6cb848db6e8c335462a046",
          "message": "Add descriptive FFI call-time error messages (#1187) (#1370)\n\n* Add descriptive error messages for FFI call-time marshaling errors (#1187)\n\nFFI call-time rejections (wrong arg type, arity mismatch, NUL-in-string,\nclosed library, out-of-range) previously raised a bare \"error\" with no\ndiagnostic detail. Now every failure path sets vm.setErrorDetail with the\nFFI function name, argument position, and expected/actual types.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Address review feedback and fix Linux CI failure\n\n- Fix arity test: use abs (libc) instead of sqrt (libm) for portability\n- Handle toIntArgOpt null for c_int range check (multi-limb bignum)\n- Clear vm.last_error_detail_len at start of callFfi (stale detail)\n- Add vector/procedure to schemeTypeName for better diagnostics\n- Add closed-library and out-of-range regression tests\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-09T12:47:58Z",
          "tree_id": "a6f74d7749fb380ca28efd82dac84ca4706f93d0",
          "url": "https://github.com/kaappi/kaappi/commit/c7747d31714699542e6cb848db6e8c335462a046"
        },
        "date": 1783603657175,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.385169,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.737516,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.970039,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.423552,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012558,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.204202,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.502201,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068832,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.75873,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.934535,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 10.219352,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.994735,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.431896,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.556184,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.0434,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "a94cce8d2225937e95e8ae3970a68b4b0cd3fdec",
          "message": "Trampoline map/for-each/dynamic-wind/force callback family (#1347) (#1374)\n\n* Trampoline map/for-each/dynamic-wind/force callback family (#1347)\n\nRewrite map, for-each, vector-map, vector-for-each, string-for-each,\nstring-map, dynamic-wind, and force as Scheme closures compiled at VM\ninit time, replacing the native Zig implementations that used\ncallReentrant. Callbacks now execute as regular bytecode calls in the\ndispatch loop, lifting two documented limitations:\n\n- Fibers can park inside callbacks (channel-receive in a for-each\n  callback no longer deadlocks when other fibers are available)\n- Continuations captured inside map/for-each can be reinvoked after\n  the iteration returns\n\nThe Scheme implementations are bootstrapped between registerAll() and\nregisterStandardLibraries(), overwriting the native versions in\nvm.globals before library export. Internal helpers (%push-wind,\n%pop-wind, %promise-* accessors) expose low-level VM operations\nwithout re-entering Scheme.\n\nTwo dispatch-loop fixes support the new architecture:\n- callReentrant error path now calls after-thunks for winds pushed\n  during the re-entrant call (instead of silently resetting wind_count)\n- Return opcode's caller-wind-cleanup only fires for returns_to_native\n  callers, preventing premature unwind of Scheme-managed winds\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Print which benchmarks failed verification in run-benchmarks.sh\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Halve closures benchmark iterations to fit CI timeout\n\nThe closures benchmark does 10K map calls over 1000-element lists.\nWith map now a Scheme closure (bytecode dispatch instead of native\nloop), this exceeds the 120s timeout on slow CI runners. Reduce to\n5000 iterations — still exercises the same closure allocation and\nGC patterns.\n\nAlso print which specific benchmarks failed in run-benchmarks.sh.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Raise benchmark alert threshold for callback trampoline PR\n\nThe list benchmark uses map in its hot loop. With map now a Scheme\nclosure (bytecode dispatch per callback instead of tight native loop),\nthe microbenchmark is ~1.6x slower. This is expected — the tradeoff\nis correctness (fibers can park, continuations can resume) over raw\ncallback throughput. Real-world programs are dominated by callback\nwork, not the loop overhead.\n\nRaise the alert threshold to 200% for this PR. The threshold should\nbe lowered back to 120% after merge.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Address review feedback: missing init paths, force error handling, export hygiene, tests\n\nM1: Add vm_bootstrap.install() to all init paths that were missed:\n    runtime_exports.zig, kaappi_lsp.zig, bench.zig, tests_fuzz.zig.\n\nm2: Unwind pending dynamic-wind after-thunks in execute()'s error\n    path so (dynamic-wind before thunk after) calls after even when\n    thunk raises an uncaught exception that escapes to the top level.\n\nm3: Wrap force's (thunk) call with with-exception-handler to reset\n    the forcing flag on error, then re-raise. Prevents promise from\n    getting stuck in the forcing state after an exception.\n\nm5: Add Lib.internal tag for primitives that live in globals but must\n    not be exported by any standard library. Move %push-wind, %pop-wind,\n    and %promise-* helpers to .internal. Keep %make-promise-lazy in\n    scheme_base since the compiler emits references to it from library\n    contexts where restricted_globals blocks the globals fallback.\n\nT1: Add continuation re-entry test in tests_continuations.zig that\n    captures a full continuation inside a map callback and reinvokes\n    it from a separate eval, proving generator-style re-entry works.\n\nT2: Add 257-list map error assertion to primitives_list-audit.scm.\n\nT7: Add yield calls between channel-sends in the fiber for-each test\n    to force the fiber to park before data is available.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Preserve error detail across dynamic-wind after-thunk unwind\n\nAfter-thunks that make native calls (e.g. display) clear\nlast_error_detail as a side effect. Save/restore the detail\nacross the wind unwind loop in execute()'s error path so the\nreal exception message survives.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Preserve error detail in callReentrant wind unwind loop\n\nMirror the save/restore pattern from execute()'s error path so\nafter-thunks that do native I/O don't clear the exception message\nduring callReentrant's wind cleanup either.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Fix force cycle detection: clear forcing at exit points, not via wrapper\n\nThe with-exception-handler wrapper cleared the forcing flag before the\ncycle detection check could examine it. After a merge-and-loop, the\nresult promise could be the same object as current, but forcing was\nalready false — so the (%promise-forcing? result) check never triggered,\ncausing an infinite loop on cyclic delay-force chains.\n\nFix by removing the wrapper and clearing forcing explicitly at each\nnormal exit path, matching the native algorithm. The forcing flag now\npersists across loop iterations until force returns or errors.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Clear promise forcing flag on abnormal thunk exit via dynamic-wind\n\nThe native forceFn cleared `forcing` in its `catch |err|`, which fires\non any error return — including ContinuationInvoked from a call/cc\nescape. The Scheme force lost that: 2627a2cb's with-exception-handler\nwrapper only caught raises (and, being a native primitive, drove the\nthunk through callReentrant — breaking continuation re-entry through\npromise thunks), while 80125b29 removed the wrapper and left `forcing`\nstuck on both raises and escapes, so a later delay-force chain over the\npromise raised a spurious \"re-entrant forcing of promise\".\n\nWrap the thunk call in a flag-based dynamic-wind instead: the after\nthunk clears `forcing` only when the body did not complete normally,\nso raises and call/cc escapes both reset the flag while normal returns\nkeep it set for the SRFI-45 cycle-detection check. dynamic-wind is\nitself Scheme-bootstrapped, so force stays pure bytecode — fibers can\nstill park and continuations captured in thunks can still be reinvoked.\n\nRegression tests cover the raise path, the escape path, and\ncontinuation re-entry through a forced thunk; the first two fail on the\nprevious commit.\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-09T21:18:23Z",
          "tree_id": "3fcb6fcd05bd5a7e39db2f6601e09fd05637eb6e",
          "url": "https://github.com/kaappi/kaappi/commit/a94cce8d2225937e95e8ae3970a68b4b0cd3fdec"
        },
        "date": 1783633683057,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.393525,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.851065,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.80824,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.446949,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.013881,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.345795,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.398804,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.058006,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 13.784998,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.532447,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 10.498444,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.061574,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.84807,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.039205,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.039335,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "091ddbf9d4c4ec91bf4b6427da87c95f5c2ee6a2",
          "message": "Polish the bootstrapped map/for-each/dynamic-wind/force family (#1375) (#1378)\n\n* Polish the bootstrapped map/for-each/dynamic-wind/force family (#1375)\n\nFollow-up to the #1374 trampoline rewrite, addressing all seven review\npolish items:\n\nWrap each vm_bootstrap.zig definition in a let that captures its\ndependencies as closure upvalues at install time. This restores the\nredefinition immunity the native implementations had (a top-level\n(define reverse ...) no longer changes map's behavior) and lets\ninstall() remove the eight %-helpers (%push-wind, %pop-wind,\n%promise-*) from vm.globals entirely — misusing them could corrupt\nthe wind stack or promise state, and they are now unreachable without\nany change to the global-visibility model.\n\nGive the lambdas explicit minimum arities ((proc list1 . lists)) so\nzero-sequence misuse reports \"'map': expected at least 2 arguments,\ngot 1\" instead of leaking internals (\"type error in 'cdr'...\"), and\ntype-check the procedure argument up front so (map 5 ...) names map.\ndynamic-wind validates all three arguments before running before, so\nside effects no longer leak on bad-argument calls and the error names\ndynamic-wind rather than %push-wind.\n\nRetire the eight dead native implementations (~460 lines). Their spec\nentries remain for arity metadata and library exports but now point at\nprimitives.bootstrapStub(), which raises a descriptive error — a future\nmissing install() fails loudly instead of silently reverting to\ndivergent native behavior. install() likewise reports which definition\nfailed to eval instead of aborting startup with a bare exit code.\n\nRe-add the README fibers limitation narrowed to the still-native\ndrivers (SRFI-1 folds, sort, hash-table-walk, ...), verified by repro:\na fiber blocking in a fold callback still deadlocks where map parks.\nRestore the benchmark alert threshold to 120% (list microbenchmark\nmeasures +4.7% vs main, well inside the threshold).\n\nVerifying this change surfaced two pre-existing #1374 regressions,\nfiled separately: native-backend calls to the bootstrapped procedures\n(#1376) and dynamic-wind inside SRFI-18 threads (#1377).\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n* Make string-map/string-for-each linear via char-list traversal\n\nDriving the loops with (string-ref s i) is O(n^2): strings are UTF-8\nand codepoint indexing rescans from byte 0 on every call. The retired\nnative implementations had the same index-driven cost, so this predates\nthe trampoline — but the fix belongs with it. Convert each string to a\nchar list once (one O(n) pass) and walk pairs, the same shape the\nlist-based map/for-each already use: 50k ASCII chars drop from 2.04s\nto 0.006s, and doubling the input now doubles the time instead of\nquadrupling it.\n\nThe smoke test gains 300k-char calls that finish instantly when linear\nand trip the suite's per-file timeout if quadratic behavior returns.\n\nAddresses the CodeRabbit review finding on PR #1378.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-10T05:49:35+05:30",
          "tree_id": "4af720ab8e6f0c66c5d49c1001d0340ae8ad4264",
          "url": "https://github.com/kaappi/kaappi/commit/091ddbf9d4c4ec91bf4b6427da87c95f5c2ee6a2"
        },
        "date": 1783644487375,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.420027,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.113523,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 1.023561,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.588176,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.013292,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.338742,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.526457,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069956,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 13.580227,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 2.067714,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 8.75386,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.038128,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.569762,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.742816,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045078,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "a4e2779f432c027081b8aab038254de90b1e8b55",
          "message": "Fix native backend calls to bootstrapped procedures (#1376) (#1379)\n\nSince #1374 rewrote map/for-each/dynamic-wind/force as Scheme closures\ninstalled at VM init, natively compiled programs reach them as bytecode\nthrough kaappi_call_scheme — and the bytecode then has to invoke the\nnatively compiled callback, a NativeClosure, from inside the dispatch\nloop. Every dispatch site (callValue, callThunk, callHandler, and the\ntail_call/tail_apply/tail_call_global/tail_call_cc opcodes) only knew\nClosure/NativeFn/Continuation/FfiFunction/Parameter, so the first\ncallback invocation died with NotAProcedure (\"runtime error in call\").\nPre-#1374 this never mattered: NativeClosures were only ever called by\nthe Zig primitives via callWithArgs, the one place that handled them.\n\nAdd a native_closure arm to each of those sites, routed through a new\nvm_calls.callNativeClosure helper. The helper copies the arguments into\na stack buffer before the call: emitted native functions read their\nparameters lazily from the args pointer, and re-entering the VM can\ngrow (realloc) vm.registers, so a pointer into the register file could\ndangle. The originals stay reachable through the caller's storage, so\nthe copies need no GC roots (verified with KAAPPI_GC_THRESHOLD=1).\n\nAlso report vm.last_error_detail plus the Zig error name in the\nkaappi_call_scheme / callPrimitive / kaappi_eval exit paths, instead of\na bare \"runtime error in call\" — uncaught Scheme exceptions are\nformatted via noteUncaughtException first, so e.g. (error \"boom\" 1)\ninside a callback now prints \"runtime error in call: boom 1\n(ExceptionRaised)\".\n\nRegression tests: unit tests drive a hand-built NativeClosure through\neach dispatch path (call, tail_call, tail_apply, tail_call_global,\ncall/cc receiver, with-exception-handler thunk/handler, dynamic-wind\nthunks, upvalues, catchable arity errors), and\ntests/scheme/compile/native-bootstrap-callbacks-1376.sh compiles and\nruns the whole bootstrapped family natively, including the error-detail\noutput.\n\nFixes #1376.\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-10T05:49:56+05:30",
          "tree_id": "87ce17e8fe19d2f891307efe4e5c199201d99549",
          "url": "https://github.com/kaappi/kaappi/commit/a4e2779f432c027081b8aab038254de90b1e8b55"
        },
        "date": 1783644574626,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 5.008924,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.625093,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.988717,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.641203,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012987,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.338582,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.510757,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069739,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 13.533028,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 2.283344,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 8.750137,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.038819,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.57487,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.693962,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.04551,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "547f7cab4f69854ddc6088a006a6f838edb43c16",
          "message": "Fix spurious wind unwind on return into native-callback frames (#1377) (#1380)\n\nSince #1374, dynamic-wind is a Scheme closure whose bytecode manages\nthe wind stack via %push-wind/%pop-wind. When a callback is invoked\nfrom native code through callWithArgs — an SRFI-18 thread thunk, a\nmember/sort predicate — its frame is pushed with returns_to_native\nset, and a tail call to dynamic-wind reuses that frame. The Return\nopcode's caller-wind cleanup then mistook the frame's own live wind\nrecord (pushed after frame entry, so above saved_wind_count) for an\norphaned native wind: as soon as the wound thunk returned, it ran the\nafter-thunk and popped the record, so dynamic-wind's closing\n%pop-wind underflowed. In a thread that surfaced as \"uncaught\nexception in thread\"; the same failure was reproducible without\nthreads from any callWithArgs-driven predicate.\n\nDelete the cleanup. A callee's return never exits the caller's\ndynamic extent, so unwinding the caller's winds at that point is\nnever correct. The cleanup existed for winds pushed by the pre-#1374\nnative dynamic-wind, which could be orphaned when a continuation\nrestore discarded the native's Zig frame; since #1374 every wind is\npushed and popped by bytecode, and unbalanced frames are still\nunwound at the frame's own return, the scope-root return, and the\ncallReentrant/execute error paths.\n\nCI missed this because no test exercised dynamic-wind inside\nmake-thread, and the existing callback tests either called\ndynamic-wind in non-tail position (own frame, returns_to_native\nfalse) or ended their thunks in native calls, which return through\nthe tail-call native fast path and never execute a Return opcode.\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-10T05:50:17+05:30",
          "tree_id": "29d8ac2328427cd2bf1cdca4bd304fef44bbf88e",
          "url": "https://github.com/kaappi/kaappi/commit/547f7cab4f69854ddc6088a006a6f838edb43c16"
        },
        "date": 1783644647215,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.584114,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.230091,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 1.036535,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.53708,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.01376,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.319761,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.480229,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.06654,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 13.320268,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.909211,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 8.230125,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.966101,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.269604,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.98044,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.040799,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "6c8e50dd7bdf38029ff80314287ad7a8a0a3df6b",
          "message": "Migrate (chibi test) tests to SRFI-64 (#1313) (#1382)\n\nThe (chibi test) shim exists only to run the upstream R7RS suite, but 55\nother test files had adopted it. SRFI-64 is the standardized framework\nthe rest of the suite uses, has richer assertions, and — unlike the shim,\nwhich always exits 0 — its exit-on-fail epilogue lets run-all.sh detect\nfailures from the exit code instead of grepping output.\n\n- tests/scheme/{srfi,audit,compliance}: (chibi test) -> (srfi 64),\n  test -> test-equal, runner-grab epilogue with (exit 1) on failure;\n  test-values forms (srfi152) become test-equal + call-with-values;\n  commented-out ;; FAIL: #NNN assertions renamed so they still work\n  when un-commented after fixes\n- r7rs-tests.scm stays on the shim (upstream suite, out of scope)\n- audit-primitives skill template and audit-strategy.md session\n  protocol now prescribe SRFI-64 for new test files\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-10T06:32:43+05:30",
          "tree_id": "e0b5479c7b0740bd783f8fa7a8263e9c42800e55",
          "url": "https://github.com/kaappi/kaappi/commit/6c8e50dd7bdf38029ff80314287ad7a8a0a3df6b"
        },
        "date": 1783646902636,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.539062,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.748696,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 1.005804,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.639852,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012924,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.339225,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.512108,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070221,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 13.66317,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 2.07954,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 8.756625,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.037119,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.630738,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.715128,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045588,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "0c93734e159f46a28260c9ab10e9dc310c6b36a4",
          "message": "Re-enable stale FAIL-marked assertions for six fixed issues (#1381)\n\n* Re-enable stale FAIL-marked assertions for six fixed issues\n\nAn epic #1246 verification sweep found FAIL: #NNNN markers whose issues\nwere closed with the fix landed, but whose disabled assertions were never\nre-enabled: #1199 (record accessor type checks), #1202 (parameterize\nsimultaneous binding), #1169 (multi-value continuations), #1180\n(heap-boxed numeric hash keys), #1188 (eval environment validation),\nand #826 (Unicode whitespace in string-trim). All six now pass against\nHEAD, so they become live regression tests.\n\nMarkers for #1178, #1184, and #1185 are left disabled: those issues were\nclosed as completed but the behavior is still broken (verified against\nHEAD).\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n* Strengthen re-enabled hash-key assertions to compare stored values\n\nReview feedback on the #1180 regression loops: checking only for the\n'missing sentinel would pass if a lookup returned the wrong entry's\nvalue. Compare against the inserted value instead, matching the\nfixnum/string growth tests later in the file.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-10T01:25:23Z",
          "tree_id": "2b07887ce35f3e2fe79255617c1fb7dce35a3e04",
          "url": "https://github.com/kaappi/kaappi/commit/0c93734e159f46a28260c9ab10e9dc310c6b36a4"
        },
        "date": 1783648103000,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.549313,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.114443,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 1.003715,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.615904,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012917,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.338894,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.513989,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070166,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 13.630052,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 2.253556,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 8.761559,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.037919,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.587607,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.518142,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044573,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "2a5206f1466fd44ee935d79cf1f368e590520736",
          "message": "Validate UTF-8 in utf8->string (#1178) (#1383)\n\nutf8->string copied bytes into a string unchecked, so invalid UTF-8\n(bad lead bytes like #xFF, overlong encodings, surrogates, truncated\nsequences) produced a corrupt string: write and string-length worked,\nbut string-ref on the same string raised \"expected valid UTF-8 string\".\nStrings are codepoint-indexed and assume valid UTF-8, so R7RS 6.9's\n\"it is an error\" case must be rejected at construction, where the\ncaller can guard it.\n\nValidation covers the selected start/end byte range only: invalid\nbytes outside the range are fine, and a range that splits a multi-byte\ncharacter raises.\n\nRe-enables the ;; FAIL: #1178 assertions in the bytevector audit and\nadds range-variant coverage.\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-10T01:32:44Z",
          "tree_id": "54f6c03f246990812024540811b1ebd801f821bf",
          "url": "https://github.com/kaappi/kaappi/commit/2a5206f1466fd44ee935d79cf1f368e590520736"
        },
        "date": 1783649370037,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.264765,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.735845,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 1.033958,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.524406,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.015367,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.380857,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.515037,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068818,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 14.682558,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 2.003737,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.950278,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.163945,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 9.456741,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.856504,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044681,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "ae8cb244ec9bd074c03b284c770cce7e093c3fa1",
          "message": "Make advisory yield a no-op under re-entrant native frames (#1184) (#1384)\n\nWith another fiber schedulable, (yield) sets vm.yielded and the dispatch\nloop raises VMError.Yielded, expecting it to unwind to a scheduler loop\n(runWithScheduler / runSchedulerUntil). But when the yield executes under\na re-entrant native frame — most commonly the thunk of guard, which\ndesugars to with-exception-handler and re-enters via callThunk /\ncallReentrant — the native's generic error conversion intercepts the\nin-flight signal and surfaces it as a contentless \"error\" exception.\n\nThe audit file hit exactly this: the spawn-limit test leaves the\nscheduler full of never-dispatched fibers, so a later (yield) inside the\ntest macro's guard armed the signal and the test recorded a bogus caught\nerror. A fiber can never be resumed across a returned native call anyway\n(the same invariant as the native-frame continuation limit), so the only\nsound behavior for an advisory yield in that context is a no-op: arm\nvm.yielded only when native_reentry_depth is 0. Apply the same guard to\nSRFI-18 thread-yield!, which had the identical defect.\n\nRe-enables the FAIL-marked assertion in primitives_fiber-audit.scm and\nadds a smoke regression test plus a unit test.\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-10T01:43:50Z",
          "tree_id": "f905537fb8c915cc95a5fd2e3c59e49f0db49af9",
          "url": "https://github.com/kaappi/kaappi/commit/ae8cb244ec9bd074c03b284c770cce7e093c3fa1"
        },
        "date": 1783649544369,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.358907,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.108754,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 1.028469,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.449801,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.013123,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.338144,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.530921,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069998,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 13.608457,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.992383,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 8.744285,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.047495,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.610993,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.702614,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043859,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "72da4981008b24b7cb5dacd6d42ae772274052c4",
          "message": "Re-raise errors from FFI callbacks when the C call returns (#1185) (#1385)\n\nErrors raised inside an ffi-callback invoked from C vanished: the\ntrampolines set vm.last_callback_error, but nothing ever read the flag,\nso the callback handed a default 0 to C and the enclosing FFI call\nreported success. A callback returning a non-integer where the\nsignature declares int was coerced to 0 with the same silence.\n\nA Scheme exception cannot unwind the C frames between the FFI call and\nthe trampoline, so park it instead: trampolines stash the pending\nexception in the new GC-traced vm.callback_error_value (synthesizing an\nerror object from the recorded detail for VM-level errors), and callFfi\nre-raises it once the C call returns — the C result is garbage at that\npoint and must not be delivered as a success. First error wins; later\ncallback invocations by the same C call run on already-poisoned state.\nControl-flow signals (ContinuationInvoked/Yielded/Terminated/\nExecutionTimeout) keep their existing handling. Int-returning\ntrampolines now stash the same way for non-fixnum or out-of-c_int-range\nresults.\n\nThe four FFI dispatch sites propagate ExceptionRaised instead of\ncollapsing every callFfi failure to TypeError, so guard receives the\noriginal condition object with its message intact.\n\nCloses #1185\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-10T01:50:37Z",
          "tree_id": "72fb8221d4c01fd78849937ba681cedc3705ebfc",
          "url": "https://github.com/kaappi/kaappi/commit/72da4981008b24b7cb5dacd6d42ae772274052c4"
        },
        "date": 1783649899306,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.114908,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 10.111516,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 1.038225,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.43624,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.014264,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.374887,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.514277,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.067797,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 14.533113,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.981337,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.670075,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.173706,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 9.400328,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.898239,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045816,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "2919e4edf3b90d468316a9ed9cdf5c674225cbb6",
          "message": "Assert the utf8->string rejection is the type error, not any condition (#1386)\n\nReview feedback on #1383: the re-enabled assertions catch every\ncondition, so an unrelated failure would still pass. Add one assertion\npinning error-object? and the \"type error in 'utf8->string'\" message\nprefix on the representative bad-lead-byte case.\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-10T02:11:57Z",
          "tree_id": "feab4b487e0d84172d5021510bd3022a3439e911",
          "url": "https://github.com/kaappi/kaappi/commit/2919e4edf3b90d468316a9ed9cdf5c674225cbb6"
        },
        "date": 1783650763891,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.095745,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.608805,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 1.025891,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.419736,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.014324,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.374525,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.514245,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.06784,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 14.521534,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.981546,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.665206,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.16862,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 9.397752,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.854503,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044967,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "a4ac8c3811fc868a5a489d5a7cd4259fce5b9134",
          "message": "Document practical fuzzing strategy (#1387)",
          "timestamp": "2026-07-10T07:39:56+05:30",
          "tree_id": "324ea0d8b816e66254b0796b08fa2a8ca7d248dc",
          "url": "https://github.com/kaappi/kaappi/commit/a4ac8c3811fc868a5a489d5a7cd4259fce5b9134"
        },
        "date": 1783650906572,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.125202,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.804315,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 1.050203,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.429547,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.014634,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.375196,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.513607,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.067858,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 14.569918,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.981219,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.705819,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.165506,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 9.431347,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.852996,
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
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "distinct": true,
          "id": "46fcc6998f0d54011854d9150c9f1cfb86cd5028",
          "message": "Release v0.14.0",
          "timestamp": "2026-07-10T07:50:38+05:30",
          "tree_id": "32e75ce700980c4a5292f35482906bfee732b730",
          "url": "https://github.com/kaappi/kaappi/commit/46fcc6998f0d54011854d9150c9f1cfb86cd5028"
        },
        "date": 1783651912466,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.424017,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.972357,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.998658,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.846673,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012952,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.338358,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.507908,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.071151,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 13.658624,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.969261,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 8.779419,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.044148,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.567926,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.715096,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043519,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "6a4034f9a6f4329b6b45ce08f6f9680dd86ca696",
          "message": "Ground fuzzing feasibility note in the research literature (#1388)\n\n* Ground fuzzing feasibility note in the research literature\n\nThe note argued from Fuzzilli's design alone; the same conclusions are\nthe central findings of ~15 years of compiler/interpreter fuzzing\nresearch, so cite the primary sources and let them sharpen the plan:\n\n- New \"What the research literature says\" section surveying 18 verified\n  papers (grammar-based fuzzing, differential compiler testing, the\n  Fuzzilli line, functional-language testing, LLM generation), each\n  mapped to a concrete Kaappi decision.\n- Key find: Zig's std.testing.Smith is exactly Zest's parametric-\n  generator architecture (ISSTA 2019), so the Tier 2 grammar generator\n  is a published, validated design.\n- Tier 3 restructured: a Kaappi-vs-itself variant (bytecode VM vs LLVM\n  native backend, per Midtgaard et al. ICFP 2017 and FuzzJIT) now\n  precedes the external-oracle variant, since it needs no reference\n  Scheme installed.\n- Operating guidance: pair fuzz runs with -Dgc-stress=true builds.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n* Address review precision findings on the research survey\n\n- classfuzz/classming: describe their actual oracle (diff across multiple\n  JVM implementations); present the .sbc-mutation idea as our own\n  adaptation, since Kaappi has no second VM to diff against.\n- Tier 3 external oracle: pin one reference interpreter at a fixed\n  version (Chibi first) with fixed invocation/normalization, instead of\n  an open-ended implementation list.\n- Fuzz4All: state the throughput comparison as a qualitative expectation\n  with its reason, not a bare figure.\n- gc-stress: \"attempts collection at every allocation\" — maybeCollect\n  skips when no_collect is held or the GC is disabled (memory.zig).\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-10T08:19:31+05:30",
          "tree_id": "6a0b680b73693b357c845a4b9e97338ea4eba9f0",
          "url": "https://github.com/kaappi/kaappi/commit/6a4034f9a6f4329b6b45ce08f6f9680dd86ca696"
        },
        "date": 1783653452765,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.09246,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.250543,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 1.02487,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.09221,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.01416,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.374417,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.516703,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.067819,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 14.63726,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.982034,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.659503,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.16524,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 9.386769,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.846059,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.04496,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "ea008c6b5bc484d6a64beb46cbedad18fca849f9",
          "message": "Fuzzing roadmap Phase 1: seed corpora, token target, scheduled CI job (#1398)\n\n* Add fuzz seed corpora and a token-vocabulary fuzz target (#1389, #1391)\n\nThe four fuzz targets started from nothing: no seed corpus, and\nbyte-oriented Smith inputs that rarely got past the lexer, so the\ncompiler, VM, and GC were barely exercised.\n\nCorpus entries for std.testing.fuzz are serialized Smith decision\nstreams, not raw inputs — a seed() helper encodes source text as\n<4-byte LE length><bytes> and rejects seeds that exceed the target's\nbuffer at compile time. Each target gets a curated corpus: lexical\nvariety for the reader, one expression per core form for the compiler,\nsmall self-contained programs for eval, and a checked-in valid .sbc\nfixture (plus truncated/bit-flipped variants) for the bytecode loader.\nThe fixture's compiler-version hash is patched at comptime so releases\ndon't stale it; a sanity test fails when a format VERSION bump does.\nThe fixture needs a .gitignore exception: *.sbc normally means a local\ncompile cache.\n\nThe new \"fuzz tokens\" target mutates token sequences instead of bytes\n(Salls et al., USENIX Security 2021): 76% of its inputs get past the\nfirst readDatum vs 33% for random bytes, without being confined to\ngrammatically valid programs.\n\nThe shared eval harness silences fd 1 while evaluating: the test\nbinary's stdout is the build-runner IPC pipe, and a generated\n(display ...) call would deadlock the run.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n* Add scheduled bounded fuzzing job to CI (#1390)\n\nThe fuzz targets were never run in fuzzing mode — no --fuzz invocation\nexisted anywhere, so each target only ever executed once with a fixed\nseed under plain zig build test.\n\nfuzz.yml runs a bounded pass daily at 02:47 UTC (away from the 05:17\necosystem nightly) in two variants: default, and -Dgc-stress=true with\na smaller budget, which converts latent GC rooting bugs into immediate\nfailures. Limits are per fuzz test and sized from measured local rates\n(the eval-based targets build a full VM per input at ~20-50 ms).\n\nZig 0.16's bounded fuzz mode does not propagate a fuzz-found crash into\nthe build's exit code — verified with a locally planted panic — so the\njob treats .zig-cache/f/crash (the encoded crashing input) as the\nauthoritative failure marker, fails the run, and uploads it with the\nlogs.\n\ndocs/dev/fuzzing.md is the operating runbook: running locally, the CI\njob, and the failure workflow (minimise, regression test, corpus entry).\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n* Address PR #1398 review: sandboxed eval harness, workflow hardening\n\nevalOne now uses the sandboxed registration path (registerSandboxed +\nregisterSandboxedLibraries + sandbox_mode), so fuzz inputs that reach\nfilesystem, process, FFI, or thread forms get an ordinary undefined-\nvariable error instead of touching the host — including (exit), which\nwould have killed the fuzz worker. It also clears the GC threadlocal on\nteardown instead of leaving it pointing at a dead stack frame.\n\nThe workflow passes dispatch inputs via env (never interpolated into\nBash source), sets pipefail explicitly (shell: bash already implied it,\nbut explicit survives someone removing that line), removes a stale\ncrash marker before each run, and persists the fuzzer's corpus and\ncoverage across runs with a rolling actions/cache key — saved only on\nsuccess so crash state never leaks into the next run.\n\nRunbook: document the token target's u64 decision-stream encoding for\ncrash reproduction, the corpus persistence, and two wording fixes.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-10T06:23:25Z",
          "tree_id": "db94295e6fb146599be58a14a151342db3138496",
          "url": "https://github.com/kaappi/kaappi/commit/ea008c6b5bc484d6a64beb46cbedad18fca849f9"
        },
        "date": 1783666386909,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.939807,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.763901,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.955306,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.291141,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012575,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.316102,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.477444,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.067816,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.895503,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.85224,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 8.182146,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.96539,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 7.899045,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.996521,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.04127,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "3f25edbc8c4d3c65493fb87aab00d18ad08a7b20",
          "message": "Disable the gc-stress fuzz variant pending #1401 (#1402)\n\nThe variant's first execution (workflow_dispatch run 29073769556) found\nthat ~440 of 690 unit tests crash under -Dgc-stress=true on both x86_64\nLinux and aarch64 macOS, instrumented or not. Since `zig build test\n--fuzz` runs the whole suite before fuzzing, the variant can never pass;\nits job hung after the test-phase failures until the 55-minute timeout.\n\nThe default variant is unaffected (green in ~4 minutes on the same run).\nRe-enable gc-stress once the suite is stress-clean.\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-10T13:20:53+05:30",
          "tree_id": "d2f38750f16775c80bfaec801c5cba711e70310d",
          "url": "https://github.com/kaappi/kaappi/commit/3f25edbc8c4d3c65493fb87aab00d18ad08a7b20"
        },
        "date": 1783671365811,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.103022,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.794009,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 1.05224,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.424674,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.014333,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.37645,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.516556,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.067974,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 14.5665,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.981941,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.713461,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.164854,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 9.415765,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.861985,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044867,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "2400a3697f0f0b9a24867776c0cd615b387c26cf",
          "message": "Add a Smith-driven grammar generator for valid R7RS forms (#1403)\n\n* Add a Smith-driven grammar generator for valid R7RS forms (#1392)\n\nFuzzing roadmap Phase 2 (Tier 2, epic #1397). The existing fuzz targets\nfeed the VM raw bytes or token soup, so they rarely get past the reader:\nover equal 30-input sets, random bytes cover 11.1% of src/ while\ngenerated programs cover 24.3% — vm_dispatch 480 vs 156 lines, memory\n255 vs 144, and compiler_macro, compiler_advanced, expander, and\nvm_continuations go from zero lines to hundreds.\n\nsrc/fuzz_gen.zig is a Zest-style parametric generator (the architecture\nstd.testing.Smith natively supports): every structural decision is a\nSmith choice, so the fuzzer's byte mutations on the decision stream\nbecome structural program mutations. Design constraints, each from a\nresearch lesson documented in docs/dev/fuzzing-feasibility.md:\n\n- Well-bound (PolyGlot): a scope stack tracks identifiers with a\n  type-ish Kind (numbers, procedures with arity, vectors with length and\n  element kind, strings/lists with length and mutability), so references\n  resolve, calls match arities, and indices stay in range. A `reserved`\n  kind hides skeleton binders (letrec procs) that would otherwise let a\n  generated reference resolve to a shadowing binder of another type.\n- Bounded by construction: expression depth, literal sizes, loop\n  iteration counts, and program bytes are capped; loop-carried integer\n  accumulators are modulo-clamped so repeated squaring cannot build\n  million-digit bignums whose single multiplication outlives the 100 ms\n  VM deadline.\n- No ambient effects: filesystem, process, FFI, network, and thread\n  forms are never emitted (the sandboxed harness stays as backstop).\n- Form coverage weighted toward the interesting paths: closures, tail\n  calls, named let/do loops, call/cc, dynamic-wind, guard/raise,\n  quasiquote (incl. splices and nested templates), syntax-rules\n  definition + use (fixed and ellipsis rules), and\n  vector/string/bytevector mutation for the GC write-barrier paths.\n\nThe generator is driven through a Chooser that is Smith under the\nfuzzer and a seeded PRNG in unit tests — Smith replays out-of-range\ndecisions as the range minimum, so a PRNG is what gives fixed-seed\ntests real variety. Unit tests assert that 2000 fixed-seed programs\nall parse, compile, and stay under the size bound, and that generation\nis deterministic. A tests_fuzz.zig gate asserts a majority of programs\nevaluate cleanly (measured: 98% over 300 seeds; the rest are expected\nguard re-raises and deadline hits). The new \"fuzz grammar\" target needs\nno corpus — any decision stream decodes to a valid program — and the\nraw-bytes and token targets stay for parser robustness.\n\nData-kind generators (chars, strings, lists, quasiquote, vectors,\nbytevectors, reals, mutation statements) live in fuzz_gen_data.zig,\nsplit along the grammar-domain seam for the 1500-line file policy and\nre-exported as Gen methods.\n\nThe eval-rate gate skips under -Dgc-stress builds: stress slows\nevaluation by orders of magnitude, so deadline hits would measure GC\noverhead instead of generator quality (and gc-stress unit tests are\nbroken anyway, #1401).\n\nCloses #1392\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n* Address PR #1403 review: three-state list mutability, Cands asserts\n\nReview found a real well-boundness hole: ListInfo carried a single\nmutable flag meaning \"first cell is fresh\", but cdr moves onto the\ntail's cells, so (cdr (cons x '(1 2 3))) — the immutable quoted spine —\nwas marked mutable and set-car! through it failed at runtime.\n\nReplace the flag with Mut { none, head, all }: constructors that\nallocate every cell (list, reverse, map, vector->list, rest args)\nreturn .all; quoted data and quasiquote templates .none; cons is .all\nonly when its tail is, else .head; cdr keeps .all or drops to .none;\nappend now models R7RS 6.4 sharing (copies all but the last argument)\ninstead of being blanket-immutable. set-car! gating needs != .none.\n\nAlso add the requested capacity/non-empty asserts to Cands and reword\nthe eval-rate comment to say the 294/300 figure is an offline 300-seed\nmeasurement while the gate samples 60 seeds for CI cost (re-measured\nafter this change: still 294/300, same six misses — all deadline or\nguard re-raise outcomes, none mutability-related).\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-10T09:01:32Z",
          "tree_id": "80e864d9314b774d929785de2efa8126a119cc5f",
          "url": "https://github.com/kaappi/kaappi/commit/2400a3697f0f0b9a24867776c0cd615b387c26cf"
        },
        "date": 1783675893286,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.359373,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.844502,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 1.000164,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.508795,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.013254,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.338108,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.509888,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069986,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 13.609378,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.968724,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 8.749087,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.040253,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.532678,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.713234,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043204,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "64c327b2532c140bfc651261e79d4449ededb863",
          "message": "Record the AFL++ analysis in the fuzzing feasibility note (#1404)\n\nSecond recurring tool question after Fuzzilli, so it gets the same\ntreatment: a section mapping AFL++'s feature set onto what Phase 1\n(#1398) built and what the tiered plan covers — persistent mode is the\nin-process vm.eval harness, dictionaries are the token target, grammar\nmutators are Tier 2's Smith generator. The blocker is instrumentation:\nafl-cc cannot compile Zig, leaving only the slow QEMU/FRIDA modes or\nthe SanitizerCoverage work already scoped and deferred for Fuzzilli.\n\nThe one AFL-shaped niche — CMPLOG against the .sbc loader's binary\nformat — is noted as a deferred complement alongside the Fuzzilli fork\nand Fuzz4All.\n\nAlso annotate the Gaps section with the items Phase 1 closed, so the\nnote no longer contradicts the sections that reference that work.\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-10T14:35:49+05:30",
          "tree_id": "c2fa8ead65951801dcc0eb084b49e9ed49634196",
          "url": "https://github.com/kaappi/kaappi/commit/64c327b2532c140bfc651261e79d4449ededb863"
        },
        "date": 1783676018184,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.344013,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.862316,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 1.052046,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.518759,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.013029,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.338394,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.508276,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070282,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 13.650081,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.980104,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 8.754219,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.038043,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.560173,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.706858,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043526,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "c59275ef02081caac90f69ee85a19641c5d9a760",
          "message": "Fuzzing roadmap Phase 3: IR optimization switch + opt-vs-no-opt differential oracle (#1405)\n\n* Add --no-ir-opt switch to disable IR optimization passes\n\nThe five IR optimization passes and the AST-level constant folder ran\nunconditionally, so there was no way to diff optimized against\nunoptimized execution — the correctness oracle from the fuzzing roadmap\n(Tier 3) and a useful tool for triaging miscompilation reports.\n\n`ir.optimize_enabled` (threadlocal, like vm_instance, so SRFI-18 child\nthreads keep the default) now gates foldConstants through simplifyBegin\nand tryFoldFromAST; markTailPositions still runs since it is analysis\nrequired for correctness, not an optimization. Exposed as --no-ir-opt\non the CLI.\n\nNo-opt runs skip the .sbc cache entirely — cache keys don't include the\nflag, so reusing or writing cached bytecode would mix the two paths.\nFor the same reason --no-ir-opt --compile without -o (whose default\noutput path IS the cache location) is refused.\n\nVerified: full Scheme suite passes under --no-ir-opt (1821/0), and\n--disassemble on (if #t 1 2) shows one constant load with optimization\nvs the full branch structure without.\n\nCloses #1393\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n* Add differential fuzz target: optimized vs unoptimized evaluation\n\nCrash-only fuzzing never surfaces silently wrong values — the majority\nclass of compiler bugs per the EMI authors. This is the cheapest\ncorrectness oracle (Pałka et al., FuzzJIT): evaluate each\ngrammar-generated program twice, IR optimizations on and off, and any\ndivergence is a bug in an optimization pass or the baseline.\n\nThe normalized observable is the printed final value (write mode) plus\nthe generator's globals g0-g2, and the error class — never message\ntext. The globals matter: vm.eval returns only the last top-level\nvalue, so a wrong fold inside (define g1 ...) is invisible in the\nfinal value alone. With them, an off-by-one planted in the `*`\nconstant fold is caught at fixed seed 30 (and 3 more within 500).\nTimeout, out-of-memory, and stack-overflow outcomes make a pair\nincomparable rather than a divergence, since the two compilation paths\nlegitimately do different amounts of work.\n\nA 60-seed deterministic gate runs on every `zig build test`; the fuzz\ntarget itself is picked up automatically by the scheduled CI fuzz job.\nBounded --fuzz=200 pass on current sources: no crash marker, no\nmismatch.\n\nCloses #1394\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n* Close the -o cache-poison hole and address review nits\n\nReview on #1405 spotted that the --no-ir-opt --compile guard only\nrefused a MISSING -o, while the natural explicit choice\n(-o program.sbc) is exactly getSbcPath(program.scm) — so forced -o\nstill let unoptimized bytecode land where plain runs load their cache.\nRefuse any output that lexically resolves to the source's cache path\n(symlink aliases excepted; the natural spellings are covered).\n\nAlso from review: the folded-patterns test now uses one th.TestContext\nper the test guidelines, and a new regression case proves self-tail-\ncalls still compile as loops when optimization is disabled\n(markTailPositions is analysis and must survive the switch).\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-10T11:01:37Z",
          "tree_id": "5fb9b84708e3dad45a67f41cf564e9ac654fd0c7",
          "url": "https://github.com/kaappi/kaappi/commit/c59275ef02081caac90f69ee85a19641c5d9a760"
        },
        "date": 1783682993397,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.385207,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.760923,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 1.028497,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.453192,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012922,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.338848,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.51081,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069798,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 13.706356,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 2.065026,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 8.766113,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.039156,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.55263,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.715553,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043039,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "1e922abc19a426af8537955cfa1679d92437b8d6",
          "message": "Harden the --no-ir-opt compile guard from post-merge review of #1405 (#1406)\n\nThree findings from the re-review of PR #1405 after it merged:\n\n- The collision check failed OPEN: an allocation or normalization\n  failure in outputIsBytecodeCache returned \"no collision\", letting an\n  unoptimized cache write proceed. Now any failure counts as a\n  collision — the worst case is a spurious usage error, never a\n  poisoned cache.\n- A symlinked -o (alias.sbc -> prog.sbc) bypassed the lexical path\n  comparison and the write followed the link into the real cache.\n  Symlinked outputs are now refused outright under --no-ir-opt\n  --compile; symlinked parent directories remain undetected (noted in\n  the doc comment).\n- The opt-switch tests and the differential fuzz harness restored\n  ir_mod.optimize_enabled by assigning `true` instead of the saved\n  value, and the optimized baselines assumed it was already enabled.\n  All toggles now save/restore and set their baseline explicitly.\n\nVerified end-to-end: -o through a symlink exits 2 with the usage\nerror; a distinct real file compiles. New unit tests cover the\nsymlink case (via std.testing.tmpDir) and the failing-allocator\nfail-closed path.\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-10T17:28:23+05:30",
          "tree_id": "bcf36293ee5da7f0ec9459f2a3a8a2f1fb120106",
          "url": "https://github.com/kaappi/kaappi/commit/1e922abc19a426af8537955cfa1679d92437b8d6"
        },
        "date": 1783686488892,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.431016,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.728599,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.978071,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.404993,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.013033,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.338293,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.504838,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069274,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 13.550643,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.93088,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 8.78254,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.051257,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.611618,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.77439,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044145,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "542e3a93f7f174f09cd4751e1f649fa96841ae44",
          "message": "Fuzzing roadmap Phase 3: VM vs LLVM native backend differential harness (#1408)\n\n* Fuzzing roadmap Phase 3: VM vs LLVM native backend differential harness\n\nCrash-only fuzzing and the opt-vs-no-opt oracle both run everything on the\nbytecode VM; nothing diffed the LLVM native backend against it, even though\ndiffing two evaluation paths of the same language is the highest-yield\ncorrectness oracle available (Midtgaard et al., ICFP 2017) and known\nregressions (#1376) prove the bug surface exists.\n\nThe pieces, and why each exists:\n\n- src/fuzz_gen_native.zig: a native-compilable-subset generator mode. The\n  backend falls back to kaappi_eval for forms it cannot compile, so an\n  unrestricted program degrades the diff to VM-vs-VM. The subset encodes\n  the backend's structural rules learned from llvm_emit_lambda.zig:\n  function bodies reference only their own parameters and primitives\n  (anything else is a free variable that rejects native compilation),\n  global defines use literal or lambda values (compound inits route\n  through kaappi_eval), computed set! only inside lexical scopes, no\n  lambdas inside let (#827 capture check), no set! inside inline-lambda\n  bodies (#819 blanket scan), and every top-level form void-valued with\n  explicit (write ...) output — the VM echoes non-void top-level values\n  but native binaries do not.\n\n- zig build fuzz-gen (src/fuzz_gen_main.zig): seeds must be replayable\n  from a shell script, so the generator gets a standalone driver binary.\n  Installed only by its own step, so it stays out of releases.\n\n- tests/fuzz/native-diff.sh: generate + interpret + compile-and-link +\n  run per seed (~1 s, dominated by linking), so this is an offline batch,\n  not a std.testing.fuzz target. Both-nonzero exits match without\n  comparing stdout (the VM continues past top-level errors, native halts\n  at the first). The script probes the toolchain with a trivial program\n  because kaappi compile reports link failures on stderr but exits 0.\n\n- Gates: tests_native.zig asserts fixed-seed programs emit no unexpected\n  kaappi_eval calls AND that every defined function gets a named native\n  definition (the eval count alone cannot see a rejected function — its\n  define-time eval is emitted either way); tests_fuzz.zig asserts the\n  programs evaluate cleanly (measured 100% over 300 seeds).\n\n- fuzz.yml native-diff job: 300 programs nightly, seed base rotates per\n  run (printed and replayable), divergences uploaded as artifacts.\n\nFirst 500-seed batch found a real miscompilation: the closure tiers'\nfree-variable analysis does not descend into let/let*, so a lambda that\ncaptures an enclosing binding only through a let is compiled as closed and\nthe reference becomes a global lookup — an undefined-variable exit, or a\nsilently wrong value if a same-named global exists. Filed as #1407 (5 of\n500 seeds hit it); the nightly native-diff job is expected red until it is\nfixed.\n\nCloses #1395\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n* Harden native-diff exit classification, timeouts, and artifacts (review)\n\nReview on #1408 found three holes in the harness, all fixed here:\n\n- Both-nonzero exits were accepted as a match unconditionally, so a\n  native segfault (exit 139) against an ordinary VM error (exit 1) was\n  invisible — the loudest class of native-backend bug this oracle exists\n  for. Any exit >= 128 (death by signal) is now a divergence even when\n  both sides errored; ordinary-error matching applies only to 1..127.\n\n- The per-seed `kaappi compile` ran unbounded, so a hung linker on one\n  seed stalled the whole batch instead of being classified. Compilation\n  now has its own 60 s timeout (longer than the 10 s execution budget —\n  it forks the system linker), a timed-out compile is reported as a\n  divergence, and the startup probe gets a generous budget while warming\n  the compiler-rt cache so per-seed compiles fit the tighter limit.\n\n- save_divergence could attach a previous seed's nat.out/nat.err on the\n  compile-failure path (those files are only written after a successful\n  compile). All per-seed transients are cleared at the top of each\n  iteration.\n\nAlso from the same review: the generator's stdout loop now follows\nreporting.writeToFd's errno handling (EINTR retry, hard exit on failure —\na silently truncated program must never be diffed as a real seed), both\nfuzz workflow jobs set persist-credentials: false on checkout since they\nexecute fuzzer-generated programs, and the comparison-rules documentation\nin the script header and docs/dev/fuzzing.md matches the implementation.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-10T12:47:08Z",
          "tree_id": "0113bf7508d9fda1fd28db30d65e00aa3d9bc44f",
          "url": "https://github.com/kaappi/kaappi/commit/542e3a93f7f174f09cd4751e1f649fa96841ae44"
        },
        "date": 1783689461614,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.427994,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.186839,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.993993,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.460898,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.013131,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.339204,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.512454,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.07173,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 13.619108,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.931074,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 8.853122,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.047647,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.605648,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.762759,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043781,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "81f95506f6112dcccf0fac0c7ce4c35af54805ea",
          "message": "Descend into let/let* in the native closure free-variable analysis (#1409)\n\n* Descend into let/let* in the native closure free-variable analysis\n\nThe closure tiers in llvm_emit_lambda.zig treated .let_form/.let_star\nas opaque in both nodeHasFreeVars and collectNodeFreeVars, so a lambda\nthat captures an enclosing binding only through a let compiled as a\nclosed native closure and the reference degraded to\nkaappi_global_lookup — an \"undefined variable\" exit at runtime, or a\nsilently wrong value when a same-named global existed. Found by the\nVM-vs-native differential harness (#1395) at roughly 1% of generated\nprograms.\n\nWalk the raw let/let* S-expression with proper binder scoping (let\nbinders, nested lambda formals, let-vs-let* init visibility), feeding\nboth hasFreeVars and collectFreeVars, so tier 1 captures let-hidden\nreferences as upvalues — the emission side already resolves upvalues\ncorrectly, so the reproducer now compiles natively. The collectors also\nreport when the analysis cannot stay exact (name-buffer overflow, a\nform the walk cannot scope) so the tiers reject and fall back instead\nof emitting with an incomplete capture set.\n\nFixes #1407\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n* Rank enclosing lexical bindings above known globals in the closure analysis\n\nReview of #1409 found that every classification site in the closure-tier\nfree-variable analysis consulted ir.isKnownGlobal before asking whether\nan enclosing lexical binding shadows the name. A param named after a\nprimitive was therefore read as the primitive and its capture silently\ndropped: ((lambda (car) ((lambda () (let ((x car)) x)))) 5) compiled the\ninner lambda as a closed closure and returned #<builtin car> instead of\n5 — through the new let/let* walk and equally through the plain\n.global_ref path.\n\nThread the emitter into the analysis helpers and check isNameShadowed\n(which mirrors emitGlobalRef's resolution order) before isKnownGlobal in\nnodeHasFreeVars, collectNodeFreeVars, FreeNameWalk.noteRef, and\nvalueIsBoundOrLiteral. Harden tier 1's capture-source check to match:\nupvalues are copied out of the enclosing %args array, so a collected\nname that an enclosing let-local or rest parameter binds (they outrank\nparams) or that lives only in the enclosing closure's upvalue array\n(#1410) must reject rather than capture the wrong slot or degrade to a\nglobal.\n\nAlso assert the closure-creation call site (not just the runtime\ndeclaration preamble) in the closed-native-closure regression test,\nper review.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n* Add list-ref to the known-global primitives list\n\nThe native-subset differential generator (#1408, now on main) emits\n(list-ref b i) in function bodies, and its contract requires every\nbody op to be in ir.isKnownGlobal so calls do not count as free\nvariables. list-ref was the one body op missing: once the let/let*\nwalk (#1409) made references inside lets visible, a generated body\nlike (let ((e (list ...))) (list-ref e 0)) reported list-ref as a\nfree name and the whole function fell back to the interpreter,\nfailing the no-unexpected-eval oracle on the CI merge ref (seed 6 of\nrun seed 0xf3c8bc08).\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-10T19:53:35+05:30",
          "tree_id": "f0e2057e0dd85251ceb258bc5cd5bcb2926c72d6",
          "url": "https://github.com/kaappi/kaappi/commit/81f95506f6112dcccf0fac0c7ce4c35af54805ea"
        },
        "date": 1783695364853,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.149039,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.747485,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 1.028889,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.431129,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.014204,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.375801,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.50906,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068301,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 14.612022,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.989093,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.693258,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.162083,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 9.430894,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.897883,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.048257,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "9a9230d10e232e35e9020e0b40cbef52a7de01f6",
          "message": "Fix nested syntax-rules substitution and template let ellipsis bindings (#1411)\n\n* Fix nested syntax-rules substitution and template let ellipsis bindings\n\nTwo expander bugs broke Alex Shinn's portable match and any macro using\nthe classic Kiselyov/Campbell let-syntax identifier/ellipsis detection\ntricks:\n\n1. R7RS template semantics substitute pattern variables everywhere in\n   the template, including nested syntax-rules patterns and literals —\n   that substitution is what makes the \"is this an identifier?\" trick\n   work. The expander instead filtered colliding outer bindings out of\n   nested syntax-rules forms (instantiateNestedSyntaxRules), leaving\n   the outer pattern variable behind as an inner catch-all pattern\n   variable, so probes matched everything. Remove the special case;\n   ordinary substitution plus hygiene renaming does the right thing.\n\n2. instantiateLetBindings had no ellipsis handling, so the common\n   template shape (let ((var value) ...) . body) failed to expand.\n   Delegate repetitions to instantiateEllipsis (including\n   ((var value) ... ...) depth-2 flattening per R7RS 4.3.2) and resume\n   let-binding processing after the ellipsis tokens.\n\nEven where such macros worked, expansion was pathologically slow:\nevery pattern-match attempt and ellipsis repetition safety-filled a\n~1MB [128]Binding buffer (8KB ellipsis_values per entry), and the\ncompiler's post-expansion set!-target scan (#1250 Part B) recursively\nre-expanded nested macro uses, making depth-N macro towers quadratic.\nHoist the binding buffers and write fields explicitly; expand macros\nonly in the top-level pre-scan — each nested use is scanned when\ncompilation actually expands it. A macro-expansion stress test that\ndid not finish in 5 minutes now completes in ~43s.\n\nAlso give library-load failures precise error names: reader failures\nsurface as LibrarySourceReadError instead of a vague InvalidSyntax,\nand compile failures of library body forms record the underlying\nerror name in the error detail.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n* Address #1411 review: inner ellipses, binder hygiene, error propagation\n\nFixes the findings from PR review:\n\n- Preserve a generated nested syntax-rules transformer's own ellipses.\n  Inside a nested syntax-rules template, an ellipsis whose element\n  references no outer list binding belongs to the inner macro; the\n  outer instantiation expanded it to zero repetitions (this also\n  affected main via the old filtering path, which recursed with plain\n  instantiateTemplate). New NESTED_SR_FLAG context bit, set for the\n  subtree when a syntax-rules head is encountered.\n\n- Keep binding-position hygiene for repeated template-introduced let\n  binders. The ellipsis path in instantiateLetBindings instantiated\n  each (var init) repetition generically, so a binder named after a\n  global procedure (e.g. exp) skipped the binding-position rename and\n  captured use-site references to the builtin. New LET_PAIR_FLAG tags\n  the repetition element; instantiateTemplate splits it var/init with\n  the binding flag applied to the var.\n\n- Skip unreferenced list bindings in instantiateEllipsis' sub-binding\n  loop. With two ellipsis groups of different lengths in one template,\n  the unreferenced group's ellipsis_values was indexed past its own\n  count — an uninitialized read, and a potential garbage-pointer\n  dereference in the depth>1 branch.\n\n- Propagate OutOfMemory from library body compilation instead of\n  mapping it to InvalidSyntax (and thus \"library not found\").\n\n- Hoist the intro_scope flag bits to file-scope constants and mask\n  context flags in renameForHygiene so the same template identifier\n  renames consistently inside and outside those contexts.\n\nAdds 6 regression assertions (file now has 25).\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-10T15:00:45Z",
          "tree_id": "4e4ec988a7d6a6d9b486e3d71ee24223f7e69a7b",
          "url": "https://github.com/kaappi/kaappi/commit/9a9230d10e232e35e9020e0b40cbef52a7de01f6"
        },
        "date": 1783697502788,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.376576,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.669135,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 1.041231,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.432499,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.013491,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.342045,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.512072,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070165,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 13.766828,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.961634,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 8.790902,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.047601,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.59336,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.765727,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044039,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "e04a2ea1f501388b8b6dc2696dcda40498b5c299",
          "message": "Harden GitHub Actions: pin actions by SHA and disable persisted checkout credentials (#1413)\n\n* Harden GitHub Actions: pin actions by SHA, disable persisted credentials\n\nMutable tags like @v7 let a compromised upstream repoint what our\nworkflows execute with our tokens and secrets; a full commit SHA cannot\nbe repointed. Persisted checkout credentials sit in git config where\nevery later step (including fuzzer-generated programs and benchmark\nruns) can read them, and no step in this repo relies on them: gh uses\nGH_TOKEN, github-action-benchmark and action-gh-release authenticate\nthrough their explicit token inputs.\n\n- Pin all 10 distinct actions across the 5 workflows to full commit\n  SHAs, each with a comment naming the resolved version.\n- Set persist-credentials: false on all 17 checkout steps (fuzz.yml\n  already had it from #1398).\n- Add a top-level contents: read permissions block to post-release.yml,\n  which previously inherited the repository default token scope.\n- Add .github/dependabot.yml (weekly, grouped) so pins are bumped with\n  the version comments kept in sync instead of going stale.\n- Document the conventions in docs/dev/github-actions.md.\n\nCloses #1400\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n* Repin PR benchmark action to the v1 tag, not the shadowing v1 branch\n\nkaappi/github-action-pull-request-benchmark has both a v1 tag (master\ntip, posts PR comments) and a stale v1 branch (v1.4.0, posts commit\ncomments requiring contents: write). The Actions runner resolves @v1 to\nthe tag, but the commits/<ref> API endpoint used to resolve the pin\nreturned the branch head, so the first pin captured the wrong code and\nthe comment step failed with \"Resource not accessible by integration\".\n\nPin the tag's commit instead, and fix the resolution recipe in\ndocs/dev/github-actions.md to use refs/tags (with annotated-tag\npeeling), which cannot be shadowed by a branch.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-10T21:26:54+05:30",
          "tree_id": "5d1699beaf4eb6582d268aee88ad9214dd47444e",
          "url": "https://github.com/kaappi/kaappi/commit/e04a2ea1f501388b8b6dc2696dcda40498b5c299"
        },
        "date": 1783700460840,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.37484,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.086216,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.997703,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.428406,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012902,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.338997,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.509711,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070272,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 13.481729,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.949904,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 8.766212,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.037736,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.638949,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.681068,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042861,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "3fa6b12ebcbf90c8cbc1592bfdcf102202c19d54",
          "message": "Return exact results from sqrt for rational and bignum perfect squares (#1415)\n\n(sqrt 9/4) returned inexact 1.5 even though the exact result 3/2 is\nrepresentable, and (sqrt <bignum perfect square>) returned a flonum that\ncan even be wrong in the last digit (f64 rounding). R7RS 6.2.6 encourages\nexact results for exact arguments when representable, and Chez, Chibi,\nGauche, and Guile all return 3/2 for (sqrt 9/4).\n\nExtract the integer square root logic (fixnum fast path + bignum Newton\niteration) from exact-integer-sqrt into a shared isqrtNonNegative helper,\nand use it in sqrt: a non-negative exact integer whose root has zero\nremainder returns the exact root, and an exact rational returns an exact\nrational when both numerator and denominator are perfect squares. All\nother cases (mixed squares, negatives, inexact arguments) keep the\nexisting inexact/complex behavior.\n\nFixes #1412\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-10T21:30:55+05:30",
          "tree_id": "acf54202690ebb1a11b3a5d3d5849e812fc9c37a",
          "url": "https://github.com/kaappi/kaappi/commit/3fa6b12ebcbf90c8cbc1592bfdcf102202c19d54"
        },
        "date": 1783701521024,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.135815,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.854814,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 1.040495,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.421609,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.014318,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.375897,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.512645,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068527,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 14.622387,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.989845,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.712994,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.165434,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 9.430766,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.864038,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045053,
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
          "id": "51128e3c283b839a7ac1e6f0d16a16d3a5538f1f",
          "message": "Bump the github-actions group with 2 updates (#1416)\n\nBumps the github-actions group with 2 updates: [codecov/codecov-action](https://github.com/codecov/codecov-action) and [actions/cache](https://github.com/actions/cache).\n\n\nUpdates `codecov/codecov-action` from 5.5.5 to 7.0.0\n- [Release notes](https://github.com/codecov/codecov-action/releases)\n- [Changelog](https://github.com/codecov/codecov-action/blob/main/CHANGELOG.md)\n- [Commits](https://github.com/codecov/codecov-action/compare/0fb7174895f61a3b6b78fc075e0cd60383518dac...fb8b3582c8e4def4969c97caa2f19720cb33a72f)\n\nUpdates `actions/cache` from 4.3.0 to 6.1.0\n- [Release notes](https://github.com/actions/cache/releases)\n- [Changelog](https://github.com/actions/cache/blob/main/RELEASES.md)\n- [Commits](https://github.com/actions/cache/compare/0057852bfaa89a56745cba8c7296529d2fc39830...55cc8345863c7cc4c66a329aec7e433d2d1c52a9)\n\n---\nupdated-dependencies:\n- dependency-name: codecov/codecov-action\n  dependency-version: 7.0.0\n  dependency-type: direct:production\n  update-type: version-update:semver-major\n  dependency-group: github-actions\n- dependency-name: actions/cache\n  dependency-version: 6.1.0\n  dependency-type: direct:production\n  update-type: version-update:semver-major\n  dependency-group: github-actions\n...\n\nSigned-off-by: dependabot[bot] <support@github.com>\nCo-authored-by: dependabot[bot] <49699333+dependabot[bot]@users.noreply.github.com>",
          "timestamp": "2026-07-10T22:03:59+05:30",
          "tree_id": "6085da6f1991a4e85d27cb347ba4c7338622ab5d",
          "url": "https://github.com/kaappi/kaappi/commit/51128e3c283b839a7ac1e6f0d16a16d3a5538f1f"
        },
        "date": 1783702834351,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.366575,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.80611,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 1.014503,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.434886,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.013193,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.338884,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.506759,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069901,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 13.509531,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.947059,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 8.754261,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.041762,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.590679,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.742085,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042929,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "24fa6651ac6ec6fe439f2bb9eaaa1d5ab4286c29",
          "message": "Exit non-zero on every kaappi compile / --emit-llvm failure (#1417)\n\nkaappi compile printed diagnostics for a missing libkaappi_rt.a, a\nmissing C compiler, or a failing linker, but then exited 0 with no\noutput binary, so exit-code-checking callers (CI, differential fuzz\nharnesses) treated the failure as success. Missing input files were\nworse: silent and exit 0.\n\ncompileNative and emitLlvmFile now return errors on every failure\npath, which mainInner already turns into exit code 1. A failed link\nis also reported as \"Linking failed\" instead of the misleading \"No C\ncompiler found\" when a compiler was present, and the temp .ll file\nis cleaned up on failure too.\n\nThe exit-code.sh regression suite gains hermetic coverage for all of\nthese: missing/unreadable input for both compile and --emit-llvm, a\nmissing runtime library (isolated binary copy so every lookup\nmisses), a missing C compiler (empty PATH dir), and a failing linker\n(stub cc that always exits 1). All seven new assertions fail against\na pre-fix build.\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-10T22:04:35+05:30",
          "tree_id": "e2086b2fc78fc49eeb70122be3e9248ab9e5b5db",
          "url": "https://github.com/kaappi/kaappi/commit/24fa6651ac6ec6fe439f2bb9eaaa1d5ab4286c29"
        },
        "date": 1783703006225,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.3646,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.86548,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 1.031767,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.506604,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012953,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.338368,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.518956,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070173,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 13.490573,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.9822,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 8.734262,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.044079,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.576265,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.764439,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043917,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "b54431c7b660de8a8c3f9f8a7c11a3077a3d6f80",
          "message": "Fuzzing roadmap Phase 3: Kaappi vs external reference Scheme differential harness (#1418)\n\n* Fix register leak when macro expansions reference globals\n\nexpandAndCompileMacroUse loads each non-procedure global free variable\nof a template into a fresh register and aliases it as a local (R7RS\n4.3.1 referential transparency, #935). Those registers were never\nfreed after the expansion compiled, breaking the balanced-register\ncontract call compilation relies on: argument registers are allocated\ncontiguously, so the leak shifted every argument after the expansion\none slot up while the call still read the original window. The call\nthen saw the alias value in later argument slots — with (define g1 41)\nand (define-syntax m0 (syntax-rules () ((_) g1))):\n\n    (+ (m0) 1)    => 82\n    (list (m0) 1) => (41 41)\n\nor a spurious \"type error in 'arithmetic'\" when the global held a\nchar or procedure.\n\nFound by the Kaappi-vs-Chibi differential oracle (#1396) on its first\nbatch: all 28 divergences in 1900 seeds trace to this one leak. Both\ninternal oracles (opt-vs-no-opt, VM-vs-native) are structurally blind\nto it because every internal evaluation path shares this compiler.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n* Fuzzing roadmap Phase 3: Kaappi vs external reference Scheme harness\n\nImplements #1396 (Tier 3, last item): run generated programs through\nkaappi and a pinned Chibi Scheme and diff normalized observables — the\nonly oracle that catches conformance bugs where both of Kaappi's own\nevaluation paths agree but are wrong. Its first batch caught exactly\nsuch a bug (the macro-expansion register leak fixed in the previous\ncommit): 28/1900 seeds diverged, all one root cause, invisible to the\nopt-vs-no-opt and VM-vs-native oracles since every internal path\nshares the compiler.\n\nThe portable-subset generator mode (src/fuzz_gen_portable.zig, with\ndata-kind productions split into fuzz_gen_portable_data.zig per the\nfile size policy) emits only fully-specified, deterministic R7RS-small\nprograms — Csmith's \"fully-specified subset only\" lesson. One rule per\nunspecified zone, each probed against real Chibi during development:\npure expressions (effects only in statement slots whose order the\nreport fixes; Midtgaard et al.'s effect discipline simplified), total\nby construction (guard always has else, single structured raise site,\nsingle structured call/cc escape), exact integers only, ASCII only,\nexplicit four-library import (Chibi enforces boundaries — delay/force\nlive in (scheme lazy)), void-valued top-level forms with explicit\n(write ...) observables, bytevectors echoed byte-wise (Chibi writes\nthem with hex bytes).\n\ntests/fuzz/oracle-diff.sh mirrors native-diff.sh: stdout byte-for-byte\nwhen both exit 0, error class otherwise (never message text), signal\nexits always divergent, timeouts skipped, oracle version recorded with\nany divergence, triage protocol (Kaappi bug / oracle bug / generator\nleak) in the header. A nightly oracle-diff job runs 1000 programs with\na rotating, replayable seed base. With the leak fixed, a 2000-seed\nbatch runs clean against Chibi 0.12.0.\n\nCloses #1396.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-10T16:36:42Z",
          "tree_id": "e7fed72659c8c6e56a1aaf799a0b3e385625e13a",
          "url": "https://github.com/kaappi/kaappi/commit/b54431c7b660de8a8c3f9f8a7c11a3077a3d6f80"
        },
        "date": 1783703476506,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.087137,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 10.016095,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 1.024986,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.407253,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.014234,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.374698,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.509771,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068387,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 14.571317,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.982624,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.669633,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.167482,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 9.464136,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.91424,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045464,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "dd71851272a4a0f6d35ab3537e7dc89750a6bb4d",
          "message": "Chain nested-lambda captures in the native closure tiers (#1410) (#1419)\n\nThe closure tiers' free-variable analysis treated nested .lambda IR\nnodes as opaque, so a lambda whose only reference to an enclosing\nbinding lived inside an inner lambda was misclassified as a closed\nclosure, and the inner lambda's eval fallback then resolved the capture\nas an (undefined) global at run time.\n\nThree-part fix:\n\n- The analysis descends into nested lambda bodies via the same\n  scope-tracking raw-sexpr walk that #1409 added for let/let*.\n- Tier 1 can chain a capture out of the enclosing closure's %upvalues\n  (not just its %args), so nested captures of any depth stay native\n  with correct per-instance copy semantics.\n- Every eval-fallback boundary (emitLambdaViaEval, emitFormEval, and\n  now emitLetFallback) republishes the full frame - fixed params, the\n  rest parameter, and upvalues - as globals, closing the sibling holes:\n  variadic inner lambdas, rest-parameter captures, and let fallbacks\n  that lost the enclosing params.\n\nAlso hardened on the same paths: an abandoned native let now pops the\nGC roots it had pushed (each execution of that path leaked root-stack\nslots before), a lambda in a let binding init falls back instead of\naborting the whole native compilation, and emitLambdaFunction / tier-1\nemission no longer leak the enclosing scope's upvalues/locals/rest\nstate into nested function emission.\n\nVerified: VM-vs-native differential on ten reproducer shapes, unit +\nScheme + e2e suites, and a 300-seed native-diff fuzz sweep with zero\ndivergences. All new regression tests fail without the fix.\n\nFixes #1410\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-10T16:49:47Z",
          "tree_id": "4fd718b76ef4c1b877a51579ee496d5e1ac50971",
          "url": "https://github.com/kaappi/kaappi/commit/dd71851272a4a0f6d35ab3537e7dc89750a6bb4d"
        },
        "date": 1783703980924,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.366782,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.292588,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 1.015247,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.458677,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.013259,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.338544,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.505021,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070105,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 13.533191,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.981104,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 8.753461,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.043261,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.571334,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.783649,
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
          "id": "b1629ca5ce4a13c7417d5a928bf50d2cdfc9fe9e",
          "message": "Root bignum intermediates in rational arithmetic and string->number (#1421)\n\nThe rational accumulator loops in +, -, *, / stored each fresh bignum\nresult in a Zig local and updated the GC root slots only after both\naccumulator updates. A collection triggered inside the second update\nfreed the first result and the following allocation reused its memory,\nso the numerator aliased the denominator: under -Dgc-stress=true builds\n(and, rarely, whenever the GC threshold fired between the two calls)\nbignum/bignum division and multiplication collapsed to 1, addition\ndoubled one operand, and subtraction returned 0. string->number's\nrational parse held the numerator bignum unrooted across the\ndenominator parse with the same effect.\n\nRoot each fresh value in its slot before the next allocating call,\nroot the t1/t2 cross-multiplication temporaries in + and -, and root\nstring->number's parsed numerator across the denominator parse.\n\nFixes #1414\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-10T22:52:31+05:30",
          "tree_id": "a526135f86c264f0b60204e21437a180d28545a0",
          "url": "https://github.com/kaappi/kaappi/commit/b1629ca5ce4a13c7417d5a928bf50d2cdfc9fe9e"
        },
        "date": 1783706129841,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.367647,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.570998,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 1.010001,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.491252,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012869,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.339592,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.506018,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069793,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 13.559082,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.970953,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 8.7864,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.051716,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.586997,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.762582,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044423,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "efa04eef45e36028bced6dfe082e91aee6d21cef",
          "message": "Read rational literals with bignum numerators or denominators (#1423)\n\nThe tokenizer parsed rational parts as i64 with no bignum fallback, so\nvalid R7RS literals like 36893488147419103232/18446744073709551616\n(2^65/2^64) failed with a read error at the slash — or, with a radix\nprefix, silently split into a bignum and a stray symbol datum.\nstring->number already accepted the same syntax.\n\nDigit runs that overflow i64 now produce a big_rational token; datum\nconstruction parses each side with parseBignumString (rooting the\nnumerator across the second parse) and reduces via makeRationalReduced,\nso 2^65/2^64 reads as exact 2. Exactness and radix prefixes apply as\nfor fixnum rationals. Also frees the limbs buffer parseBignumString\nleaked on all-zero digit strings, previously unreachable.\n\nVerified under -Dgc-stress=true.\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-10T17:59:22Z",
          "tree_id": "686991e5f4c3fb313836d525dd2968b59b9d7c08",
          "url": "https://github.com/kaappi/kaappi/commit/efa04eef45e36028bced6dfe082e91aee6d21cef"
        },
        "date": 1783708397878,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.864606,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.979752,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.974277,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.144737,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.013475,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.316503,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.461224,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.064819,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 13.182948,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.755974,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 8.224557,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.977398,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 7.934851,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.979703,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042893,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "d67d05fad2120ae9798cb93619ed8ddfabd20677",
          "message": "Extend the native-subset fuzzer to chained nested-lambda captures (#1424)\n\nSince #1410 (PR #1419) the native closure tiers chain captures through\nnested lambdas and republish the full frame at eval-fallback boundaries,\nbut the generator still restricted inline lambdas to one capture level,\nso the chaining code ran only under hand-written test shapes.\n\n- Inline lambdas may now nest: non-variadic inline-lambda bodies can\n  emit further inline lambdas whose free references reach int parameters\n  of any enclosing level. Chained shapes stay fully native and sit under\n  the VM-vs-native differential oracle permanently.\n- Inline VARIADIC lambdas are emitted occasionally: no closure tier\n  accepts a rest parameter, so each one exercises the emitLambdaViaEval\n  fallback that republishes the enclosing frame (params, rest parameter,\n  upvalues) as globals, at the cost of exactly one kaappi_eval. Their\n  bodies suppress nested lambdas — the body is eval'd as one source\n  string, so a lambda inside it would be interpreted without reaching\n  the emitter, breaking the gate's accounting.\n- set! is banned inside inline-call argument subtrees in function\n  bodies: arguments run between closure creation (which snapshots\n  captured params by value, or republishes them as globals) and the\n  call, so a set! of a captured param there is visible to the VM's\n  location-based capture but not to the native snapshot. That divergence\n  predates this change and was reachable by the old generator; the\n  backend semantics are tracked as #1422.\n\nThe tests_native.zig gate now expects one eval per inline variadic\nlambda on top of one per define — exactly on unoptimized emission\n(dead-branch elimination legitimately deletes variadic lambdas from\nconstant-test branches, which the generator emits on purpose) and as a\nbound under the production pass pipeline. The 2000-seed sweep asserts\nboth new shape families actually occur in the corpus.\n\nVerification: zig build test; a set!-in-argument scan over 2000 seeds is\nclean; bash tests/fuzz/native-diff.sh 300 0 reports 300 compared,\n0 divergent, with organic chained-capture and variadic-inline seeds in\nrange.\n\nFixes #1420.\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-10T23:56:11+05:30",
          "tree_id": "c7c21bde2551c5b512faf3074684b11480ffd36d",
          "url": "https://github.com/kaappi/kaappi/commit/d67d05fad2120ae9798cb93619ed8ddfabd20677"
        },
        "date": 1783710020039,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.378394,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.996143,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 1.073381,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.423721,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.01327,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.340888,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.506148,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070766,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 13.744696,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.952852,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 8.772347,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.052583,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.630388,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.751333,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044426,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "f211bacb145b55c92a53560a8831cc168cf24f1a",
          "message": "Auto-file GitHub issues for scheduled fuzz findings (#1426)\n\n* Auto-file GitHub issues for scheduled fuzz findings\n\nA failing scheduled fuzz run was only visible as a red run in the\nActions tab, plus a notification email that goes solely to whoever\nlast touched the cron line — findings could sit unnoticed for days\nwhile their artifacts aged toward the 90-day expiry.\n\nAdd a trailing `report` job to fuzz.yml that files findings into the\nissue tracker: one open issue per failed job (bounded fuzzing,\nnative-diff, oracle-diff), labeled `fuzz-finding`, containing the run\nlink, a bounded artifact excerpt (first divergent program plus both\nsides' output, or the fuzzer transcript tail), and replay\ninstructions. While an issue stays open, repeat failures append\ncomments instead of opening duplicates. Issues are never auto-closed:\nseed bases rotate nightly, so a green run does not mean a finding is\nfixed.\n\nThe report job is separate so the write-capable token never coexists\nwith execution of fuzzer-generated programs: the three fuzzing jobs\nkeep contents:read tokens and persist-credentials: false, while the\nreport job gets issues:write + actions:read and runs no generated\ncode.\n\nAlso fix two latent problems noticed in passing: the fuzz crash\nartifact silently excluded `.zig-cache/f/crash` and `libfuzzer.log`\n(upload-artifact skips hidden directories unless\ninclude-hidden-files: true — the artifact contained only\nfuzz-run.log), and the oracle-diff job's checkout/setup-zig steps\nwere the only ones in the file not SHA-pinned.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n* Gate finding issues on finding markers to avoid false positives\n\nif: failure() fires on any step failure in the needed jobs, so an apt\nflake, a toolchain download failure, or a broken build on main would\nhave filed an issue titled as a crash or divergence with nothing in it.\n\nA real finding always ships in the artifact (the encoded crash input\nfor the fuzz job, seed-<N>.scm divergences for the diff jobs), so the\nreport job now checks for that marker: with it, the finding issue is\nfiled as before; without it, the failed jobs are collected under a\nsingle deduped \"Fuzz CI: infrastructure or build failure\" issue that\nsays plainly it is not (necessarily) a finding. Marker-less failures\nstill get reported rather than dropped because a job-level timeout can\nbe a genuine hang — every generated program is individually bounded,\nso a whole job hitting its timeout is itself suspicious.\n\nThe fuzz job's issue title narrows from \"failed (crash or test\nfailure)\" to \"found a crash\"; a pre-fuzz build or unit-test failure now\nroutes to the infrastructure issue (with the fuzz-run.log tail\nexcerpted) instead of duplicating regular CI's failure under a finding\ntitle.\n\nRouting verified by dry-running the script against a stubbed gh in\nfour scenarios: no artifacts at all, a divergence marker, a crash\nmarker, and a mixed run (oracle finding deduped into an existing open\nissue while the fuzz build failure files the infrastructure issue).\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-11T01:10:17+05:30",
          "tree_id": "437752874e2ddbf57b354a8f3f95944e8586014f",
          "url": "https://github.com/kaappi/kaappi/commit/f211bacb145b55c92a53560a8831cc168cf24f1a"
        },
        "date": 1783714279455,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.33874,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.609409,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 1.000709,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.437285,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012946,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.338437,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.507384,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.071021,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 13.588017,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.954432,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 8.753327,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.046184,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.573821,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.715159,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044625,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "929f90b26ce90bd3b3e4000215ae35aa9b3cd869",
          "message": "Reject native compilation when a set! param is captured by a nested lambda (#1425)\n\n* Reject native compilation when a set! param is captured by a nested lambda (#1422)\n\nThe native closure tiers copy captured variables by value into an upvalue\narray at closure-creation time, so a set! of the captured binding after\ncapture is invisible to the closure — diverging from the VM's by-location\nsemantics.  Add a guard in tryCompileDefineFunction that scans the raw\nbody S-expressions for this conflict and falls back to the interpreter\nwhen detected.  Update the native-subset fuzz generator to mark function\nparams as non-settable so it does not produce programs that trigger the\nnew guard.\n\nCloses #1422\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Address review: guard tier 2, pin native/fallback in tests, extract helper\n\n- Add the #1422 guard to tryCompilePureLambdaAsNativeClosure (tier 2) so\n  inline lambdas like ((lambda (u) ...) 1) also fall back when a param is\n  both set! and captured.\n- Pin compilation tier in the test script via --emit-llvm: cases 1-4\n  assert no native fn definition (fallback), cases 5-6 assert a native fn\n  definition (stays native).  Add the tier-2 inline-lambda reproducer as\n  case 4.\n- Extract pushNonSettable helper in fuzz_gen.zig and use it from all five\n  call sites in fuzz_gen_native.zig.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-10T20:32:14Z",
          "tree_id": "88dc4beb61c34ab9e01a177cfd54c031445afa8b",
          "url": "https://github.com/kaappi/kaappi/commit/929f90b26ce90bd3b3e4000215ae35aa9b3cd869"
        },
        "date": 1783717471152,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.10262,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.961395,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 1.025461,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.424044,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.014227,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.374444,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.509255,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068321,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 14.580133,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.971175,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.664939,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.164728,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 9.413675,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.866266,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045309,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "0abf3c34824db0571ad304d30f8505786b5d4835",
          "message": "Make the unit suite run green under -Dgc-stress=true (#1427)\n\n* Make the unit suite run green under -Dgc-stress=true (#1401)\n\nThe gc-stress build was never green: the test harness itself held the\nVM in a moved-from stack copy, so every collection between bootstrap\nand the first execute() swept the globals being registered, crashing\n~440 of 690 tests and masking a layer of real rooting bugs underneath.\n\nHarness:\n- makeTestVM returns a heap-allocated *VM (heap_owned); vm_instance is\n  registered before registerAll so the root marker sees the globals map\n  while it is being populated. Same bootstrap order in bench and LSP.\n- vm_eval.eval registers the VM on entry so compile-phase allocations\n  mark the right VM's roots in multi-VM tests.\n- New -Dtest-filter build option for narrowing a test run.\n\nRuntime/compiler rooting bugs the harness was masking:\n- GC allocators copy caller slices before maybeCollect() and root Value\n  slices across the collection via the new slice_roots hook; previously\n  e.g. negate/abs freed the source bignum and reused its limbs (the\n  \"@memcpy arguments alias\" crash).\n- maybeCollect's stress branch now honors no_collect/memory_limit\n  deferral like the normal path.\n- Body-local define-syntax transformers live only in compiler-local\n  macro maps the GC cannot see; they are now rooted in extra_roots for\n  the duration of the top-level compile (all four registration sites).\n- emitLlvmFile defers collection across its read -> lower -> emit\n  batch: IR nodes reference sexpr values nothing roots (latent in\n  normal builds for files that cross the GC threshold mid-compile).\n\nTests: root locals held across allocations and eval results held\nacross a second eval; scale loop-heavy churn tests down under stress\n(the 5000-iteration string loop peaked ~19.7 GB RSS under the testing\nallocator and got the suite OOM-killed; the production allocator runs\nthe same loop at 4 MB); skip the 300-capture #809 width test and the\nframe-depth #1253 test on stress builds; the #958 mark-bit scan forces\none full cycle and keeps the parent GC quiescent while the child\nthread's GC still stresses.\n\nRe-enables the gc-stress fuzz variant (fuzz.yml) with a 300-minute\ntimeout — the pre-fuzz unit-test phase dominates wall time (~40 min\nlocally at 100% CPU). Documents the invariants in gc-safety.md,\ntesting.md, and fuzzing.md.\n\nFixes #1401\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n* Address PR #1427 review comments\n\n- VM.initForThread: root each standard port before allocating the next,\n  mirroring init() (#1013) — a fresh child thread has no vm_instance\n  registered, so a stress collection during the second allocPort swept\n  the first port.\n- build.zig: apply -Dtest-filter to thottam-tests too.\n- tests_deepcopy: root copied_fn across the second deepCopy (it only\n  survives because deepCopyValue holds no_collect; follow the rule).\n- compiler_ir/compiler_macro: correct the transformer-root release-point\n  comments — body-scope roots are released by the enclosing lambda\n  compile's truncation, not compileExpression*.\n- docs/dev/testing.md: complete the example's imports.\n\nNot taken: the CLAUDE.md -Dtest-filter=tests_io example is correct\n(qualified test names include the module prefix; verified — the filter\nmatches all 30 tests_io tests), and rooting `neg` in the bignum tests\nis unnecessary (it is never held across a subsequent allocation).\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n* Add /do-stress-test skill: gc-stress suite on a 3-hour DO droplet\n\nCompanion to /do-linux-test for the -Dgc-stress=true unit suite, which\nruns for hours, not minutes: the suite is launched detached on the\ndroplet and polled (no SSH command may outlive the Bash tool timeout),\nthe self-destruct timer is 3h05m instead of 55 minutes, and the droplet\ngets 8 GB RAM plus swap because the testing allocator's metadata churn\nunder stress inflates RSS by gigabytes (#1401 postmortem). A plain\nbuild+test sanity check runs first so a broken commit fails in minutes\ninstead of after a multi-hour stress run.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-11T12:08:45+05:30",
          "tree_id": "ecfdde2b8d6fa9f86c398704b62934f764afbb38",
          "url": "https://github.com/kaappi/kaappi/commit/0abf3c34824db0571ad304d30f8505786b5d4835"
        },
        "date": 1783754074111,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.345636,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.941855,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.984527,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.375308,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.01306,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.337274,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.502807,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070313,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 13.422723,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.943686,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 8.744402,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.039783,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.531775,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.690753,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042949,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "fae98918f9548ae2c2243e69fdce2f9ee75b1202",
          "message": "Fix correctness gaps in the /do-stress-test skill (#1430) (#1433)\n\n- Split sanity check into separate SSH commands with direct exit code\n  capture instead of piping through tail (which masked build failures)\n- Pin exact commit SHA in pre-flight and fetch by SHA on the droplet\n  so reports are attributable to a specific commit\n- Add explicit substitution instruction for the quoted heredoc\n- Move self-destruct timer to after provisioning and sanity check so\n  it doesn't eat the stress suite's 3-hour budget\n- Add /do-stress-test and /do-linux-test entries to harness docs\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-11T12:15:13+05:30",
          "tree_id": "c11299f1fccbe9b6171a4316733f26c081b2d3cc",
          "url": "https://github.com/kaappi/kaappi/commit/fae98918f9548ae2c2243e69fdce2f9ee75b1202"
        },
        "date": 1783754242970,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.332236,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.665299,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.989477,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.362535,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.013118,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.337898,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.502284,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070103,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 13.425168,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.947435,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 8.748699,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.036082,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.553135,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.695493,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043242,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "18a26cb3aeddfd87b3f6ea8f846f56dbb8dd923e",
          "message": "Security-harden the DigitalOcean test skills (#1431) (#1435)\n\nThree hardening changes to both /do-linux-test and /do-stress-test:\n\n1. SSH host-key pinning: ssh-keyscan on first contact saves to a temp\n   known_hosts file; all subsequent SSH commands use\n   StrictHostKeyChecking=yes against the pinned key (TOFU model).\n\n2. Token not on command line: the DO API token is written to\n   /root/.do-token (mode 0600) via stdin; the self-destruct timer reads\n   it from the file instead of interpolating it into the process argv.\n\n3. Unprivileged test user: a dedicated \"tester\" user runs git clone,\n   zig build, and all tests. Root handles system provisioning and the\n   token file, which tester cannot access. This prevents a malicious\n   branch from reaching the API token.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-11T12:23:34+05:30",
          "tree_id": "c0891b1bd203c3b79017e9b7ee62e510d0a1f394",
          "url": "https://github.com/kaappi/kaappi/commit/18a26cb3aeddfd87b3f6ea8f846f56dbb8dd923e"
        },
        "date": 1783754931850,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.372253,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.024906,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 1.003892,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.402044,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.013181,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.34109,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.50457,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070405,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 13.467842,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.945451,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 8.766173,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.045453,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.59977,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.755314,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044575,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "1f7f3e7c9ab2ce43fde9472ede7b5ffc3ee58603",
          "message": "Store a persistent mark worklist on the GC struct (#1436)\n\n* Store a persistent mark worklist on the GC struct (#1428)\n\nmarkValue allocated and freed a fresh 8 KB ArrayList on every invocation,\ncausing megabytes of allocator churn per collection. Under gc-stress with\nstd.testing.allocator the metadata retention amplified this to ~19.7 GB RSS.\n\nMove the worklist to a GC struct field so capacity persists across calls.\nA re-entrancy guard lets fiber marking (markFiberState → gc.markValue)\nshare the buffer safely — re-entrant calls push items and return, the\noutermost call owns the drain loop.\n\nRSS on the \"GC stress:\" filter drops from ~19.7 GB to ~1.15 GB.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Cap mark worklist retention at 512 KB after drain\n\nA pathologically wide object (e.g. 10M-element vector) can grow the\nworklist to ~80 MB in a single mark pass. Free the buffer when it\nexceeds 64K entries (512 KB) so it regrows on demand rather than\nretaining peak capacity for the GC's lifetime.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-11T13:32:42+05:30",
          "tree_id": "b25ef57f5659ca52f2c5f9e2d850cbf1a4e45b28",
          "url": "https://github.com/kaappi/kaappi/commit/1f7f3e7c9ab2ce43fde9472ede7b5ffc3ee58603"
        },
        "date": 1783758553220,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.363781,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.511535,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.921074,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.382286,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006433,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.053919,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.509137,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069802,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.382453,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.962269,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.578182,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.426753,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.845681,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.6271,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044506,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "78b9d0232963a695979fc221ed6196c8bd6fcb85",
          "message": "Build chibi-scheme from source in oracle-diff CI (#1434)\n\n* Build chibi-scheme from source in oracle-diff CI (#1429)\n\nUbuntu noble's apt ships chibi-scheme 0.9.1 which is too old for the\nportable-subset programs the fuzzer generates, causing 985/1000 false\ndivergences (exit 0 vs exit 70 on nearly every seed). Build from source\nat the 0.11 tag instead.\n\nAlso pin upload-artifact to v7.0.1 (SHA) to match the other upload steps\nin the same workflow — the unpinned @v7 tag resolved to a newer version\nwhose archive-mode default prevented the report job from finding the\n.scm marker files, misclassifying real divergences as infrastructure\nfailures.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Address review comments: SHA-pin chibi, match validated version\n\n- Pin chibi to tag 0.12 + SHA assertion (matches the 0.12.0 validated\n  locally; 0.11 was never exercised against the fuzz programs)\n- Add fail-closed SHA check after checkout so a re-pointed tag breaks\n  the build instead of silently changing the oracle\n- Add comment explaining why upload-artifact must stay at v7.0.1 (later\n  versions default to archive:true which hides seed-*.scm markers from\n  the report job)\n- Update oracle-diff.sh header to stop recommending the too-old apt\n  package\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-11T13:46:07+05:30",
          "tree_id": "726582866647ce9e52f0556a6ad4f320a8531a53",
          "url": "https://github.com/kaappi/kaappi/commit/78b9d0232963a695979fc221ed6196c8bd6fcb85"
        },
        "date": 1783759279435,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.372955,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.651231,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.917155,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.385663,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00638,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.054111,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.508765,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069886,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.375706,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.964051,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.577811,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.429893,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.830146,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.707884,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044519,
            "unit": "seconds"
          }
        ]
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
          "id": "2a68ce7dc920bd10ba8a97b3344827c31a2b77a1",
          "message": "Release v0.14.1",
          "timestamp": "2026-07-11T13:50:24+05:30",
          "tree_id": "e77af6ec5e70539e2e2b6ec0f17875929d40e1d2",
          "url": "https://github.com/kaappi/kaappi/commit/2a68ce7dc920bd10ba8a97b3344827c31a2b77a1"
        },
        "date": 1783759749255,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 2.983611,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.575408,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.62159,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.014707,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.005697,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.040594,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.341668,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.049059,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.602242,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.325664,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.152215,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.366774,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.291349,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.792088,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.033993,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "488eaed277814b61e1b2445491869fa7daa60ba2",
          "message": "Deduplicate the lambda body scan between compiler_ir and compiler_lambda (#1437)\n\n* Deduplicate the lambda body scan between compiler_ir and compiler_lambda (#1432)\n\nExtract the shared R7RS 5.3.2 body-scan logic (globals prescan, define\nname collection, define/define-syntax/define-record-type processing) into\na BodyScan struct and scanBodyDefs() function in compiler_lambda.zig.\nBoth compileLambdaWithIR and compileBodyForms now call the shared helper,\neliminating ~250 lines of near-identical code that previously required\nevery GC-safety or letrec*-semantics fix to be hand-applied twice.\n\nThe IR path's compilation phase also switches from an inline IR pipeline\nto compileExprViaIR + compileExprSequence (functionally identical),\nretaining only the function-name propagation that is specific to it.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Use CPU-optimized droplets for the GC stress test skill\n\nSwitch from shared-CPU s-4vcpu-8gb to dedicated c5-4vcpu-8gb (gen 5\nCPU-optimized). The stress suite is single-threaded, so per-core speed\nmatters more than core count. Dedicated cores at full clock speed cut\nwall time from ~2.5h to ~1–1.5h at comparable total cost.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Address PR review: errdefer cleanup, VOID init, GC-safety comments\n\n- Make scanBodyDefs failure-atomic: hoist roots_base/beginBodyMacroScope\n  before the prescan and add errdefer so mid-scan errors clean up VOID\n  sentinels, extra_roots, and body macro scope (baijum review).\n- Initialize result register to VOID for macro-only lambda bodies where\n  scan.def_count is 0 and remaining is NIL (CodeRabbit review).\n- Restore the #1010 and #1401 GC-safety comments explaining why\n  def_inits and define-syntax transformers are mirrored into\n  extra_roots (baijum review).\n- Drop unused re-exports from compiler_forms.zig — compiler_ir.zig\n  imports compiler_lambda directly (baijum review).\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-11T10:15:14Z",
          "tree_id": "d80f4a9e3eccf561ed81eea4a79645f69980f5b8",
          "url": "https://github.com/kaappi/kaappi/commit/488eaed277814b61e1b2445491869fa7daa60ba2"
        },
        "date": 1783766587614,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.532794,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.888423,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.913073,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.472764,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007256,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.052585,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.500186,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.065884,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.371146,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.909183,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.44571,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.398036,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.902902,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.018756,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042146,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "28f1a3375d388589706fa8323860ae3d95a44d00",
          "message": "Reactor core: kqueue/epoll backends with a userspace timer heap (KEP-0001 P1) (#1446)\n\n* Add reactor core: kqueue/epoll backends with a userspace timer heap\n\nPhase 1 of KEP-0001 (event-loop reactor for fiber I/O). Adds\nsrc/reactor.zig: a per-OS-thread Reactor with kqueue and epoll backends\nand a shared userspace timer min-heap, so deadline logic is identical\nacross platforms. No scheduler caller yet — that's Phase 2 — so this\nhas no behavior change; it's unit-tested in isolation against real\npipe/socketpair fds in tests_reactor.zig.\n\nImplements the five design decisions already resolved in the KEP:\nwake-all waiter lists per fd direction, epoll ms-granularity timeouts\nwith ceil-rounding (never fire early), ONESHOT arming on both\nbackends, and fd-keyed registration (safe here since no user code runs\nbetween poll() returning and the scheduler's status flips, per the\nper-OS-thread cooperative model).\n\nThe trickiest correctness point is a platform asymmetry: kqueue treats\nread/write as independent filters, so firing one never disturbs the\nother, but epoll's EPOLLONESHOT disarms the *whole* fd registration on\nany fire, including a direction that didn't fire. Reactor.poll\nre-arms the remaining direction after a partial fire (a harmless\nredundant EV_ADD on kqueue); a socketpair-based test exercises this\ndirectly to guard against silently losing a still-parked waiter.\n\nAdds Reactor.removeTimer beyond the KEP's interface sketch — needed by\nPhase 2 to cancel a stale timer entry when a fiber is woken some other\nway before its deadline, so a reused fiber slot can't get a spurious\nwake later.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n* Address PR #1446 review feedback\n\nFixes two bugs flagged as should-fix-before-merge:\n\n- KqueueBackend.disarmAll batched both EV_DELETEs into one kevent()\n  call with a zero-length eventlist, so the first ENOENT (expected\n  whenever a direction was never armed) aborted the changelist and\n  left the other filter's knote behind. Verified independently with a\n  standalone C repro. Now issues each delete as its own call.\n- EpollBackend.init used epoll_create1(0), leaking the reactor's fd\n  into every subprocess the core spawns (thottam_proc.zig,\n  native_compiler.zig). Now passes EPOLL.CLOEXEC.\n\nAlso, from the same review:\n\n- Drop the dead Reg.fd field (never read; the hashmap key is the fd\n  source everywhere else).\n- Reserve ready's capacity before draining a fd's waiters in poll(),\n  so a mid-drain allocation failure can't strand the remaining\n  waiters after their ONESHOT event was already consumed.\n- Saturating-add in msFromNs to avoid a theoretical overflow panic on\n  a near-u64::MAX timeout.\n- Document that poll()'s ready list may contain a fiber twice when an\n  fd wake and its timer both land in the same call, for Phase 2 to\n  read.\n- tests_reactor.zig: assert single-byte writes actually land instead\n  of discarding the return value, so a short write fails at the\n  syscall rather than as an unrelated timeout.\n- Add a peer-close test covering the EOF/HUP-to-broken mapping\n  (kqueue EV_EOF, epoll EPOLLHUP|EPOLLERR), previously untested.\n\nFull suite: 746/746 (was 745/745 before the added test). gc-stress:\n740/746, 6 pre-existing skips, 0 failures.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-11T13:12:28Z",
          "tree_id": "326498926d101cdd2b4be45b508038102631fd95",
          "url": "https://github.com/kaappi/kaappi/commit/28f1a3375d388589706fa8323860ae3d95a44d00"
        },
        "date": 1783777199422,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.335915,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.699178,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.887775,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.439993,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006401,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.054148,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.50648,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069329,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.56241,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.963116,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.592035,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.437807,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.811339,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.734325,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.04395,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "54706a0c92b8ed81b4370fd67eb4dfb0512627ee",
          "message": "Scheduler integration: io_waiting, runSchedulerStep, reactor park (KEP-0001 P2) (#1453)\n\n* Scheduler integration: io_waiting, runSchedulerStep, reactor park (KEP-0001 P2)\n\nWires the Phase 1 reactor (kaappi/kaappi#1446) into the fiber scheduler.\nCollapses the four structurally identical scheduler-dispatch loops\n(channel-receive/fiber-join, thread-join!, mutex-lock!, condition-variable\nwaits) into one shared runSchedulerStep, whose idle branch parks in the\nreactor instead of a bare break or a whole-thread nanosleep. thread-sleep!\nis reimplemented as a timed reactor park, so it no longer stalls sibling\nfibers. The fixed 64-fiber table becomes a growable list, and per-fiber\nsave/restore is bounded to the live register/frame window instead of\nmemcpying the VM's entire register file on every switch.\n\nAlso fixes two bugs surfaced by this refactor:\n- Object.as() relied on every GC-tracked struct's `header: Object` field\n  sitting at byte offset 0, which Zig's auto struct layout does not\n  guarantee; adding fields to Fiber broke it for that type. Switched to\n  @fieldParentPtr and pointer-to-header encoding, which is layout-independent.\n- Native-primitive args slices point into vm.registers, which\n  runSchedulerStep can reallocate while recursively dispatching other\n  fibers; reading args[] after that point was a use-after-free. Values\n  needed post-dispatch are now captured into locals beforehand.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* Add a timer-only WASI reactor backend to fix the wasm build\n\nreactor.zig's Backend switch only handled kqueue (macOS) and epoll\n(Linux); everything else, including wasm32-wasi, hit a @compileError.\nPhase 1 left Reactor completely unreferenced, so this never surfaced —\nPhase 2 added a reactor field to VM, and VM.deinit() calls\nreactor.deinit(), which now forces the compiler to fully resolve\nReactor's type (including Backend) for every target the VM compiles\nfor, wasm included.\n\nFull poll_oneoff-based fd support is KEP-0001 Phase 4 work. Nothing\nregisters a port's fd with the reactor before Phase 3, so the only path\nthat needs to work on wasm today is a plain wait bounded by the timer\nheap's nearest deadline — what thread-sleep! and timed mutex/join/\ncondvar waits need. Verified locally: zig build wasm succeeds, the CI\nsmoke test (wasmtime run ... tests/wasm/smoke.scm) passes unchanged,\nand spawn/channel-send/channel-receive/fiber-join all work correctly\nunder wasmtime, exercising this backend's wait() path end to end.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* Fix scheduler review findings: timer starvation, OOM safety, deadlock detection\n\n- schedule() now pops expired reactor timers every tick (not just when\n  idle), fixing a regression where a timed mutex-lock!/thread-join!/\n  condvar wait next to a busy sibling fiber missed its deadline by up\n  to a full timeout period instead of firing promptly.\n- threadJoinFn's fiber path clears me.deadline_ns after its wait\n  resolves, matching the other three wait sites — a stale deadline\n  previously carried an unrelated addTimer entry into a fiber's next,\n  untimed wait, which could hang forever or resolve on the wrong event.\n- mutex-lock!, thread-join!, and condvar wait now check\n  runSchedulerStep's return value and raise a deadlock error instead\n  of silently assuming success when nothing could ever wake them.\n  Also fixes runSchedulerStep itself: it read ctx.isDone() after\n  already forcing the fiber back to .running, which made CondVarWait's\n  isDone() (keyed on fiber status) always report true.\n- saveCurrentFiber/restoreFiber (and their grow helpers) now propagate\n  allocation failure instead of swallowing it and continuing to memcpy\n  into a buffer that silently stayed too small.\n- thread-terminate! cancels the victim's pending reactor timer, and\n  Reactor.markRoots's doc comment now reflects that this makes the\n  timer heap a load-bearing GC root, not just belt-and-braces.\n- WasiBackend.wait propagates a non-EINTR nanosleep failure as\n  error.Unexpected instead of silently treating it as a normal wakeup.\n\n* Fix popExpiredTimers OOM ordering bug, add regression tests for prior fixes\n\n- popExpiredTimers popped a timer off the heap before appending its\n  fiber to the ready list; if the append allocation failed, that fiber\n  was dropped from both places and would never wake. Append first, pop\n  only on success (CodeRabbit finding on the previous commit).\n- Add two smoke tests for the two confirmed regressions fixed earlier\n  (timer starvation next to a busy sibling; stale deadline_ns causing\n  a false non-deadlock read). Verified both fail against the pre-fix\n  code (643c50f1) before being added, per repo policy that bug fixes\n  ship with a test that fails without them.\n\n---------\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-11T18:47:50Z",
          "tree_id": "ff9b213148b9c630f74f0a1e68561115bac6d496",
          "url": "https://github.com/kaappi/kaappi/commit/54706a0c92b8ed81b4370fd67eb4dfb0512627ee"
        },
        "date": 1783797249078,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.36703,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.92416,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.907571,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.472935,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006471,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.054194,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.510899,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069925,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.425548,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 2.010707,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.564048,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.429739,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.880032,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.675291,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044309,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "a840bd6364b105b39002e68a3940dca5e44cf085",
          "message": "Add configurable REPL syntax highlighting with dark/light presets (#1457)\n\n* Add configurable REPL syntax highlighting with dark/light presets (#1456)\n\nIntroduce ~/.kaappi/config for user preferences, starting with REPL\ntheme configuration. Support NO_COLOR env var, dark/light presets\noptimized for terminal background contrast, per-token color overrides,\nconfigurable prompts, and full R7RS token coverage in the highlighter.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Address PR review: fix precedence, validation, and add token tests\n\n- Two-pass config loading: repl.theme applied first, repl.color.*\n  overrides always win regardless of file order\n- NO_COLOR=\"\" no longer disables colors (per no-color.org spec)\n- Color names validated even under NO_COLOR (typos always warn)\n- repl.history-length rejects 0 (linenoise requires >= 1)\n- Prompt length error says \"bytes\" not \"chars\"\n- Default prompt uses shared constant (no manual sync)\n- Add 13 highlighter token tests (#true/#false, #(, #u8(, radix\n  prefixes, ,@, #;, #!, |...|, infnan)\n- Add config tests for NO_COLOR validation and history-length: 0\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Fix pass-1 theme detection with spaces around colon, suppress test noise\n\n- Pass-1 repl.theme scan now uses colon-splitting (not startsWith),\n  so \"repl.theme : light\" with whitespace around the colon works\n- Suppress stderr warnings during unit tests via comptime is_test\n  guard — tests assert config state, not message text\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-12T01:39:41+05:30",
          "tree_id": "0ad505a82a970c3d0b2d9aac52580bbb40ad517b",
          "url": "https://github.com/kaappi/kaappi/commit/a840bd6364b105b39002e68a3940dca5e44cf085"
        },
        "date": 1783802100631,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.391201,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.897543,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.918887,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.512568,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006341,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.054154,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.529814,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070074,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.428353,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 2.003532,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.61674,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.432101,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.853417,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.726335,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.046421,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "852737ae21749fd6aa9e43b51eaaa686d0c7f402",
          "message": "Fix mutex-lock!/mutex-unlock!+condvar giving up instantly across OS threads (#1455)\n\n* Fix mutex-lock!/mutex-unlock!+condvar giving up instantly across OS threads\n\nEach OS thread runs its own independent FiberScheduler, so mutex-lock! and\nmutex-unlock!+condition-variable-wait had nothing to do the moment nothing\nwas locally schedulable -- which is always true for a real OS thread whose\nonly fiber is its own top-level thunk. Both then unconditionally reported\nsuccess without re-checking whether the guarded state had actually changed,\nsilently corrupting the lock (two threads could believe they both hold it)\nor returning before any signal had happened.\n\nPoll the shared state (Mutex.locked / a new ConditionVariable.signal_\ngeneration counter) at a short interval instead of giving up immediately,\nbut only when another OS thread could plausibly still change it -- a\ngenuine local-only fiber deadlock still gives up right away, otherwise it\nwould hang forever instead of terminating. The condvar generation is\nsnapshotted before releasing the mutex in mutex-unlock! to avoid a\nlost-wakeup race against a signaler that acquires the mutex in the gap.\n\nAlso updates the stale coverage/srfi18-coverage.scm tests that captured a\nmutex/condvar in a thread thunk closure -- unsupported by design, since OS\nthreads run on isolated heaps -- to use the same-heap fiber pattern that\nsrfi18.scm already demonstrates works.\n\nFixes #1454.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* Address review: CAS-based mutex claim, owner-clear ordering, test hardening\n\nTwo review passes (CodeRabbit + a maintainer) found that the previous commit's\nfix, while correctly diagnosing and solving the give-up-too-early bug, made\nsome pre-existing races in the same code load-bearing rather than moot:\n\n- mutex-lock! claimed the mutex via a plain load-then-store; two threads\n  polling the same freshly-unlocked mutex could both observe `false` and\n  both set it `true`. Replaced with @cmpxchgStrong throughout (fast path,\n  abandoned-mutex path, and the post-wait retry), looping back into\n  runSchedulerUntilMutex on a lost race instead of assuming success.\n- mutex-unlock!/abandonFiberMutexes cleared `owner` *after* the release\n  store of `locked`, so a cross-thread acquirer that won the race in that\n  gap could have its own owner write silently stomped back to VOID.\n  Reordered so owner (and abandoned) are published before the release.\n- live_child_threads was incremented after std.Thread.spawn, leaving a\n  window where a fast-exiting child's decrement could race ahead of it.\n  Moved the increment before spawn, with rollback on spawn failure.\n- mutex-state read `m.locked`/`m.abandoned` non-atomically even though\n  they're now genuinely cross-thread fields; made those reads atomic too.\n\nAlso hardens the tests these changes touch:\n- The new cross-thread regression test's broadcast section issued the\n  broadcast without holding the mutex, so a slow-starting waiter thread\n  could snapshot its generation after the bump and then poll forever for a\n  signal that already happened. Added a bounded per-waiter timeout and\n  asserts the wait actually succeeded, turning a possible CI hang into a\n  reported failure.\n- The coverage file's rewritten broadcast test used two fibers parked on\n  the same condition variable with nothing else locally runnable, which\n  resolves via the (separate, pre-existing, out-of-scope) fiber-only\n  give-up path rather than the broadcast itself -- confirmed empirically\n  that it passed even with the broadcast call removed. Switched to a\n  single waiter, mirroring the already-correct signal test's structure.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* Fix lost timeout timer on mutex retry and missing GC write barrier\n\nTwo issues from the maintainer's re-review of the rebased fix:\n\n- mutexLockFn's retry loop re-armed after losing the tryClaimMutex race\n  (or after a cross-thread poll) without re-registering the reactor timer\n  a local wake had already canceled. me.deadline_ns stayed set, so a timed\n  mutex-lock! could block well past its deadline, and in the worst case\n  (the thread that stole the lock exits without unlocking, dropping\n  live_child_threads to 0) ends in an unbounded reactor poll instead of\n  ever timing out. Both re-arm sites now remove-then-add the timer so a\n  real deadline stays live regardless of how many times the loop retries.\n\n- Both sites that store a Fiber pointer into Mutex.owner were missing the\n  GC write barrier every other heap-field write in this file already has\n  (mutexSpecificSetFn, threadSpecificSetFn, condvarSpecificSetFn). Without\n  it, a generational minor collection can miss the reference from an\n  old-generation Mutex to a young owner Fiber.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-11T20:44:23Z",
          "tree_id": "95d153634075af8ae9f0867495fbf623d6924d00",
          "url": "https://github.com/kaappi/kaappi/commit/852737ae21749fd6aa9e43b51eaaa686d0c7f402"
        },
        "date": 1783804480223,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.083389,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.783157,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.923817,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.462512,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006815,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.053223,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.51442,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068337,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.205991,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 2.001339,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.519698,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.471471,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.731572,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.888555,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.046324,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "bff0886568d5832ef26229c103a96c5a71fda2c0",
          "message": "Port layer: non-blocking reads/writes, write buffering, (read) EAGAIN path (KEP-0001 P3) (#1459)\n\n* Port layer: non-blocking reads/writes, write buffering, (read) EAGAIN path (KEP-0001 P3)\n\nPort I/O that would block now suspends the calling fiber on the reactor\ninstead of the OS thread, so fibers reading different connections\ninterleave (closes #1441; builds on #1446/#1453).\n\nfiber.waitForFd has two modes, mirroring the channel protocol: a fiber\ndispatched directly by a scheduler loop parks (.io_waiting + yield-retry\nre-execution — read sites stash partial progress into port.read_buf via\npropagateReadErr so the retry is lossless, including read-line's\nconsumed-but-unappended \\r, mid-sequence UTF-8 prefixes, and (read)'s\npartial datum text); the main fiber or one under re-entrant native\nframes drives the scheduler in place instead, keeping siblings running\nwhile preserving blocking-read semantics. schedule() gains a per-tick\nzero-timeout reactor poll whenever any fiber is io_waiting so a\nbusy/yielding sibling cannot starve parked I/O (the Phase 2\nexpired-timer argument applied to fds).\n\nreadOneByte is the single EAGAIN choke point and now also serves the\nbinary primitives — primitives_bytevector's private reader/writer\nduplicates are gone, which also fixes read-u8 silently skipping bytes a\nprior (read) had buffered. Ports on fd > 2 buffer writes (8 KiB high\nwater) with a real flush-output-port; the drain runs before new bytes\nappend, so parked retries cannot duplicate output. Buffers flush at\nclose-port, reads on the same port, GC finalization, and exit. fd 0/1/2\nare never flipped to O_NONBLOCK and stay unbuffered — REPL and\ndiagnostics unchanged; O_NONBLOCK is set lazily and only once a\nscheduler exists, so sequential programs keep their exact syscall\nprofile.\n\nclose-port wakes fibers parked on the fd (their retry sees is_open ==\nfalse and raises cleanly) and unregisters before the fd can be\nrecycled; register() asserts (Debug) that listed waiters are still\nparked. Two adjacent holes fixed: thread-terminate! now pulls an\nio_waiting victim out of the waiter lists (mirroring removeTimer), and\nepoll's arm() self-heals CTL_MOD/CTL_ADD after a GC-freed port's fd is\nrecycled — the GC closes fds without unregistering, and close silently\ndrops them from the epoll set (kqueue is immune).\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n* Address PR #1459 review: fix (read) read_buf loss on write-drain park\n\nThe confirmed data-loss bug (review comment on readDatumFn): the entry\ncode moves peek_byte/peek_extra/read_buf into the local accumulation\nbuffer — freeing read_buf — before draining pending writes. A park in\nthat drain unwound with a bare `try`, so the Yielded propagated without\nstashing and the retry re-executed with those bytes gone, parsing\nwhatever arrived next on the fd instead. Route the drain error through\npropagateReadErr like the fd-read path; the reviewer's socketpair repro\n(buffered 20 KB request + read_buf holding the next datum) is included\nas a regression test and fails without the one-line fix.\n\nAlso from review:\n- Rewrite the port-write-buffer smoke test on SRFI-64 per the Scheme\n  test guideline (manual pass/fail counters removed).\n- Document exit's flush scope: gc_instance is threadlocal, so only the\n  calling thread's ports flush — another OS thread may be mid-write on\n  its own ports, and walking its heap without stopping it would race\n  (share-nothing model: each thread flushes or closes its own ports).\n- waitForFd: a kernel-level register failure (EBADF, resource limits)\n  now surfaces as a detailed error instead of masquerading as OOM.\n- peekCharFn: collapse the two adjacent stash slices into one.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-12T06:53:39+05:30",
          "tree_id": "cb4bd492e4961c1579fd8e02ce46d4e84f5aac5f",
          "url": "https://github.com/kaappi/kaappi/commit/bff0886568d5832ef26229c103a96c5a71fda2c0"
        },
        "date": 1783821116009,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.42869,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.172487,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.945882,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.516522,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006581,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.054004,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.508994,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069072,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.433733,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.984987,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.57827,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.436103,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.87585,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.722139,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.04312,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "10137698404f561312614634b2517358b23315c3",
          "message": "WASI backend: poll_oneoff reactor (KEP-0001 P4) (#1461)\n\n* WASI backend: poll_oneoff reactor (KEP-0001 P4)\n\nReplace the timer-only WASI stopgap in src/reactor.zig with a real\nWasiPollBackend. poll_oneoff is stateless, so the backend keeps the\nkernel's job in userspace: arm() records armed directions per fd, and\nevery wait() rebuilds the subscription list from that map — one\nFD_READ/FD_WRITE subscription per armed direction plus one CLOCK\nsubscription bounding the wait (the mio wasi model). Events map back to\nregistrations by fd via userdata, wake both directions defensively on\nper-subscription errors or HANGUP, and disarm the direction they report\n(ONESHOT parity with kqueue/epoll, per-filter like kqueue). The CLOCK\nsubscription is relative rather than the KEP sketch's ABSTIME: the\nreactor core already reduces the timer heap's nearest deadline to a\nrelative bound in effectiveTimeout(), so ABSTIME would only re-derive\nthe deadline it came from and couple the backend to clockNs()'s clock\ndomain.\n\nFd readiness is best-effort per the KEP's cross-platform section, with\nthe capability probe in maybeSetNonblocking: on WASI it now attempts\nfd_fdstat_set_flags(NONBLOCK), and a refusing host (the playground's\nbrowser shim, which also only accepts single CLOCK-subscription\npoll_oneoff calls) keeps ports on blocking fds — no EAGAIN, no fd\nregistrations, CLOCK-only waits — degrading to single-fiber blocking\nI/O exactly where the host can't do better. The three is_wasm EAGAIN\ngates in primitives_io.zig are gone, so a host that does deliver EAGAIN\nparks the fiber on the reactor like any other platform. (No fd>2 ports\ncan currently exist on WASM — open-input/output-file are native-only —\nso the fd path is dormant there until file/socket ports land.)\n\nTimers become Scheme-visible on WASM by registering thread-sleep!\n(spec .wasm = true), the one SRFI-18 entry point with no OS-thread\ndependency; the (srfi 18) library itself stays native-only. The WASM\nspec table is a comptime-filtered wasm_specs subset, which forces the\nwhole file to compile on wasm32-wasi: threadStartFn's std.Thread.spawn\nmoves behind a comptime is_wasm branch, and the u64 signal_generation\natomics (wasm32 has no 64-bit atomics; the build is single-threaded)\ntake a plain-access branch via loadSignalGeneration/\nbumpSignalGeneration.\n\ntests/wasm/timers.scm runs under wasmtime in the CI wasm job: main-\nfiber sleep duration, zero/negative fast path, deadline ordering across\nfibers, and a sleeping fiber not stalling a runnable sibling. Timing of\nthe run (0.03s CPU over 0.4s wall) confirms the process blocks in\npoll_oneoff during sleeps instead of spinning.\n\nCloses #1442\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n* Reserve ready capacity before consuming events in WasiPollBackend\n\nReview finding on #1461: the per-event try-append in wait() could fail\n(OOM) after clearInterest already disarmed the direction — the event\nconsumed but never delivered, stranding the parked fiber with no re-arm\nand turning parkOnReactor into a busy spin (isEmpty() still false via\nthe listed waiter, wait() forever returning empty). That is precisely\nthe consumed-but-undelivered invariant Reactor.poll guards with its\nup-front ensureUnusedCapacity; the fixed-array kqueue/epoll backends\nnever had a fallible step there. Reserve nevents entries before the\ntranslation loop (dedup only shrinks the count) and appendAssumeCapacity\ninside it. The remaining fallible allocations (subs build, events\nbuffer) all happen before the poll_oneoff syscall, with interests\nintact.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-12T09:19:00+05:30",
          "tree_id": "dfcdaf64e53e072ee5cfc0f28f7d2552b0e15a99",
          "url": "https://github.com/kaappi/kaappi/commit/10137698404f561312614634b2517358b23315c3"
        },
        "date": 1783829660551,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.253493,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.998361,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.680273,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.301387,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006315,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.045336,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.376227,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.054687,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.977187,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.463101,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.301371,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.416558,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.414767,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.857756,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.036505,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "6cc34beb8bdd6d9d10eab029d073bf71c42e24ca",
          "message": "KEP-0001 Phase 7: performance evaluation, edge-triggered go/no-go, thread-sleep! fix (#1476)\n\n* Fix thread-sleep! unbounded stack growth under concurrent fibers (#1463)\n\nthreadSleepFn always drove the scheduler via a nested runSchedulerStep\ncall, unlike fiber.waitForFd's dispatched_from_scheduler-aware flat\nunwind. Two or more fibers each retrying through many short\nthread-sleep! calls nested one more native stack frame per hand-off,\ngrowing without bound until the underlying condition resolved -- this\nis exactly the poll-then-sleep pattern kaappi-http's http-listen-fiber\nuses, and it needed fixing before KEP-0001 Phase 7 could safely\nbenchmark the fiber server at any real concurrency.\n\nRegression test confirmed to segfault (stack overflow) without the fix\nand pass with it.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* Add per-fiber and reactor benchmarks (KEP-0001 Phase 7)\n\n- src/bench_fibers.zig (zig build bench-fibers): per-fiber switch time\n  and RSS at 100/1k/10k concurrently-live fibers, plus a check for\n  whether the 256-register native-frame frameWindow() fallback\n  inflates saved register/frame arrays in practice.\n- src/bench_reactor.zig (zig build bench-reactor): direct epoll/kqueue\n  benchmarks independent of the VM/Scheme layer -- ONESHOT re-arm cost\n  vs. adjacent read(2)/write(2) (Q3), wake-all fan-out cost (Q1), and\n  timer deadline drift (Q2).\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* Document KEP-0001 Phase 7 benchmark results and edge-triggered decision\n\nRecords Q1/Q2/Q3 confirmations, Q5 per-fiber memory/switch-time\nmeasurements (including the FiberScheduler O(n) scan finding), the\nedge-triggered migration go/no-go (no-go for now -- re-arm cost is\nalready cheaper than the adjacent I/O syscall on both kqueue and\nepoll), ecosystem server benchmark numbers, and two bugs found while\nbenchmarking (http-listen-threaded hang, http-listen-fiber's 1ms\npoll-then-sleep floor).\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* Harden thread-sleep! against OOM leaving stale redispatch state\n\nIf addTimer or the scheduler drive fails (OOM-only today), the fiber\nkept me.deadline_ns set with no timer actually pending -- the next\nthread-sleep! call on that fiber would misread its fresh call as a\nredispatch and wait on a stale deadline forever. errdefer now clears\ndeadline_ns and removes the timer on any error other than\nerror.Yielded, which is the intentional flat-unwind signal the\ndiscriminator exists to survive, not a real error to clean up after.\n\nReview suggestion from PR #1476.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* Fix regression test's assertions and scale it under gc-stress\n\n- (>= waiter-result 0) was vacuously true for any non-negative\n  starting value and proved nothing; require > 0 so the test actually\n  exercises repeated thread-sleep! redispatch.\n- (<= waiter-result 3000) baked in a round-robin scheduling guarantee\n  (the setter is always dispatched before the waiter each wake round)\n  that isn't a property of the #1463 fix -- once #1477 replaces the\n  O(n) scheduler scan with a ready queue, dispatch order within a wake\n  round is no longer guaranteed, and this would flake in the exact PR\n  that fixes the scheduler. Loosened to a sanity ceiling.\n- Scale the retry count down under -Dgc-stress=true, matching the\n  pattern in tests_robustness.zig.\n\nReview from PR #1476.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* Fix bench_fibers.zig: correct native-frame test, allocator, RSS API\n\n- The native-frame comparison used for-each, which is bootstrap Scheme\n  (src/vm_bootstrap.zig) rather than a Zig primitive -- its callback\n  never pushed a native frame, so both \"bytecode\" and \"native\" cases\n  were exercising identical bytecode paths regardless of depth.\n  Replaced with with-exception-handler, a genuine native primitive\n  that calls its thunk via callReentrant. yield no-ops under\n  native_reentry_depth (the #1184 limitation), so thread-sleep! is\n  used as the suspension point in both cases instead.\n- Found in the process: thread-sleep! inside with-exception-handler's\n  thunk always drives the scheduler recursively rather than\n  flat-unwinding (nested runUntil clears dispatched_from_scheduler for\n  its extent, same mechanism that makes yield no-op there), so\n  concurrently-dispatched fibers doing this chain-nest the native\n  stack -- confirmed crashing at just N=2 fibers with deep-enough\n  recursion. Kept N=1 and shallow depth as the only safe combination;\n  documented the result as inconclusive rather than a clean negative.\n- Replaced std.heap.DebugAllocator with std.heap.c_allocator in main()\n  -- DebugAllocator's bookkeeping (stack-trace capture, canaries)\n  directly contaminated the timing and RSS numbers being measured.\n- Replaced the hand-rolled RUsage extern struct with\n  std.posix.getrusage(std.posix.rusage.SELF), which ships a correct\n  per-OS layout in Zig 0.16 (verified compiling and running on both\n  macOS and a Linux cross-compile target).\n- Documented that RSS is a process-lifetime high-water mark\n  (ru_maxrss), not an independent per-N peak.\n\nReview from PR #1476.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* Harden bench_reactor.zig: validate I/O, preallocate, verify timer fired\n\n- Check read(2)/write(2) return values in the Q3 arm-vs-io loop; a\n  short or interrupted transfer would otherwise accumulate unread\n  bytes or skew the timing silently.\n- Preallocate the Q1 wake-all fan-out benchmark's result list before\n  starting the clock, so the timed region measures poll()'s own\n  dispatch work rather than ArrayList growth.\n- Verify the Q2 timer-granularity benchmark's result list actually\n  contains the fiber before computing lateness, instead of trusting\n  any poll() return to mean the timer fired.\n\nReview from PR #1476.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* Update Phase 7 write-up with corrected data and review fixes\n\n- Re-ran all benchmarks with the corrected native-frame test,\n  c_allocator, and hardened bench_reactor.zig; refreshed every\n  number in the doc to match (all conclusions held).\n- Rewrote the native-frame section to describe the actual\n  investigation honestly: the for-each approach was methodologically\n  invalid, and the corrected with-exception-handler approach's result\n  is inconclusive (blocked by the 256-register initial floor at safe\n  depth, and by a newly-found native-stack-overflow risk at deeper\n  recursion), not a clean \"no inflation\" finding.\n- Removed a stray leftover table row in the Q3 section.\n- Relinked \"Follow-ups to file\" as \"Follow-ups (filed)\" now that\n  #1477-#1480 exist.\n- Documented that RSS is a high-water-mark delta, not a per-N peak.\n- Linked the now-committed kaappi-http/benchmarks/ reproduction\n  scripts (kaappi-http#3) instead of describing them as unreproducible\n  scratch files.\n- Labeled the reproduction shell fence.\n\nReview from PR #1476.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* Document the new bench-fibers/bench-reactor build steps\n\nReview suggestion from PR #1476.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-12T09:38:18Z",
          "tree_id": "a911c519717e9512196c911027b44f515aabd7ee",
          "url": "https://github.com/kaappi/kaappi/commit/6cc34beb8bdd6d9d10eab029d073bf71c42e24ca"
        },
        "date": 1783850564975,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.397546,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.602364,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.910076,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.556306,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006399,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.053867,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.512152,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070422,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.378439,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.984942,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.578445,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.432156,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.827731,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.696347,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042535,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "6d4d7a11379fe86c707cb61c8139b11402bfd306",
          "message": "Fix epoll stale-fire stranding of opposite-direction waiters (#1481)\n\nReactor.poll() gated the re-arm step behind `if (!fired) continue;`, so a\nstale ONESHOT fire (an event for a direction whose waiter list was already\nemptied by removeWaiter) skipped re-arming. On epoll, that stale fire still\ndisarms the whole fd, permanently stranding any waiter left on the opposite\ndirection — a silent hang invisible to isEmpty(). Re-arm unconditionally\nwhenever waiters remain after the drain.\n\nVerified on real Linux/epoll via podman: the new regression test fails\nwithout the fix and passes with it; kqueue is immune (independent\nper-direction knotes) so this is a no-op guard on macOS.\n\nFixes #1462.\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-12T10:15:03Z",
          "tree_id": "4fd51eb0a48884690ebfe6ae962116803c2993c6",
          "url": "https://github.com/kaappi/kaappi/commit/6d4d7a11379fe86c707cb61c8139b11402bfd306"
        },
        "date": 1783852830609,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.415682,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.881712,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.912764,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.529929,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006455,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.054808,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.510752,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069211,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.476762,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.984158,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.616468,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.436849,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.86987,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.701503,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043168,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "58036d9d793812cb141d8c559f7d2b6c251a40a3",
          "message": "SharedChannel core: shared-object protocol, promotion, reservation send/receive (KEP-0002 P1) (#1482)\n\n* SharedChannel core: shared-object protocol, promotion, reservation send/receive (KEP-0002 P1)\n\nAdds the generic refcounted shared-object protocol (src/shared_object.zig)\nand its first instance, SharedChannel (src/shared_channel.zig): a\nheap-independent, mutex-protected queue of envelopes (private mini-heaps\nfilled by the existing deepCopy) that a Channel promotes into on demand.\n\ntypes.Channel gains a `shared` field; deepCopy's `.channel` arm promotes\nan owned, unpromoted channel (or aliases an already-shared one) instead of\nerroring; freeObject releases a stub's refcount on every teardown path.\nchannel-send/channel-receive gain a foreign-owner check, which turns the\nshared-globals memory corruption described in KEP-0002's Motivation into a\ndescriptive error.\n\nPhase 1 is single-thread-testable only: thread-start!/thread-join! are\nunchanged (their deepCopy calls run on the destination thread, never the\nchannel's owner) until Phase 2 moves the thunk copy to the parent thread.\n\nVerified: full unit/gc-stress/Scheme/R7RS suites green; local fast-path\nbenchmark shows no regression vs. baseline; the KEP's TLA+ suite\n(kaappi/keps@8aa2f1fc) passes all 9 configs at their expected outcome.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* Address review: fix two refcount/memory leaks, harden park-path notifiers\n\nTwo error-path bugs found in review (both CodeRabbit and a human pass\nflagged them independently):\n\n- Envelope.create leaked the Envelope struct itself when gc.deepCopy(payload)\n  failed (e.g. an uncopyable payload) -- the errdefer only covered the mini\n  GC. Every failed send leaked one Envelope.\n- gc_deep_copy.zig's .channel arm called sc.retain() before\n  gc.allocChannelStub(sc); if the allocation then failed, the retained\n  refcount had no matching stub to release it, pinning the SharedChannel\n  (and its whole queue) forever. Reordered: allocate first, retain only on\n  success.\n\nAlso:\n- shared_channel.send/receive's park branches force-unwrapped `notifier`\n  even though every real caller passes null; handle null by skipping\n  registration instead of panicking (CodeRabbit: Major).\n- unreachable -> @panic in the two Phase-4-only switch arms in\n  primitives_fiber.zig -- unreachable is UB under ReleaseFast, @panic fails\n  loudly in every build mode.\n- Documented the deliberate KEP-0002 §1 deviation (envelopes use a private\n  per-envelope symbol table, not GC.initForThread's shared one) directly on\n  Envelope.create, with the use-after-free reasoning that makes it the\n  right call.\n- Merged raiseChannelError/raiseDeadlockError (byte-identical) into one\n  raiseFiberError.\n- bench_channel.zig: bigger source buffer (avoid NoSpaceLeft on large\n  iteration counts), iters as a Workload field instead of a name-string\n  comparison.\n- New tests: the *received* half of the KEP §1 reply-to worked example\n  (rc 1->2->3->2, identity surviving the round trip, exercising the alias\n  arm against an envelope-owned stub whose owner isn't the current\n  gc_instance); a white-box test that promotes a channel and then drives\n  channel-send/channel-receive through vm.eval to actually exercise\n  primitives_fiber.zig's shared-path dispatch (previously only exercised\n  via direct shared_channel.send/receive calls).\n- Test hygiene: restore memory.gc_instance via defer (not a plain\n  end-of-test assignment) so a failed `try` can't leave it dangling for\n  later tests; use th.TestContext instead of manual GC/VM setup in the\n  Motivation Path 2 regression test.\n- Fixed a gc-stress crash in the new reply-to test itself (not library\n  code): the \"tasks\" channel's Value wasn't rooted across the second\n  allocation on the same GC, so a stress collection could sweep it and\n  freeObject would release+destroy its SharedChannel out from under the\n  test -- classic \"root fresh results between allocations\".\n\nVerified: zig build test and zig build test -Dgc-stress=true green (5x\nrepeated runs of the shared-channel suite under both, since this class of\nbug is exactly what caused the gc-stress crash above); full Scheme/R7RS\nsuite 1834/0; zig fmt clean.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-12T21:31:46+05:30",
          "tree_id": "8bed54451d406af2ec72891d12a09e4907b64dac",
          "url": "https://github.com/kaappi/kaappi/commit/58036d9d793812cb141d8c559f7d2b6c251a40a3"
        },
        "date": 1783873915068,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.319944,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.232585,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.688377,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.38349,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006467,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.045164,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.387001,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.055718,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.094685,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.491836,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.298333,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.429087,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.437015,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.932833,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.038025,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "55ccff0b61fcecac2a108309f838563cf5a769fc",
          "message": "Envelopes at thread boundaries: thread-start!/join! via envelopes (KEP-0002 P2) (#1483)\n\n* Envelopes at thread boundaries: thread-start!/join! via envelopes (KEP-0002 P2)\n\nthread-start! now copies the thunk into a shared_channel.Envelope on the\nparent thread, before ever calling std.Thread.spawn, instead of letting\nthe child deepCopy fiber.thunk out of the still-running parent heap\nasynchronously. The child copies out of that envelope into its own fresh\nheap. This closes the old concurrent-copy race (a mutation racing the\ncopy could tear a captured structure) and is the only place a channel\ncaptured by the thunk can legally promote, since promotion requires\ngc_instance to match the channel's owner -- true only on the parent\nthread, now, before spawn.\n\nthread-join!'s result/exception cross the same way: built into an\nenvelope on the child thread right before it exits, instead of being\ndeep-copied directly out of the child's still-allocated heap by the\nparent at join time. This retires child_registry's raw-Value special\ncase and, symmetrically, is what makes a channel created and returned\nby the child promote correctly (the same ownership requirement, now\nsatisfied on the child's own thread instead of the parent's at join).\n\nThe process-global live-thread counter KEP-0002 Phase 2 calls for\nalready exists (live_child_threads, added in #1455's cross-thread\nmutex/condvar fix) -- no new code needed there.\n\nAlso fixes a double-free the envelope model exposes: child_registry's\nresult/exception lookup was a peek (get), so two racing thread-join!\ncalls on the same fiber -- reachable via a shared global, since fiber\nownership is otherwise unchecked -- could both retrieve and free the\nsame *Envelope. Replaced with an atomic take (takeResult) that clears\nboth fields under the registry lock.\n\nMotivation Path 1 (a channel captured in the thread thunk) now works\nend to end; Motivation Path 2 (a channel reached through a shared\nglobal) is unaffected and still raises the foreign-owner error.\n\nNew tests: thunk-snapshot (parent mutation after thread-start! not\nvisible to the child), Path 1 end-to-end, a channel created and\nreturned by the child, reply-channel identity across two\npromotion/alias hops, 20-thread churn with no refcount leak\n(-Dgc-stress=true clean), and the synchronous (never-spawns-an-OS-\nthread) shape of an uncopyable-thunk error.\n\nVerified: zig build test and -Dgc-stress=true green; full Scheme/R7RS\nsuite 1835/0; zig fmt clean; thread-start!/join! overhead for a trivial\nthunk is within measurement noise of the pre-Phase-2 baseline (~34-38us\neither way, dominated by OS thread creation, not the extra copy).\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* Address review: preserve exception-envelope failures, message clarity, test gaps\n\nReview of #1483 (both CodeRabbit and a manual pass) found real gaps:\n\n- The exception path collapsed both \"uncopyable exception content\" and\n  \"OOM building the envelope\" into a silent null, unlike the result path's\n  `.failed` (which raises a specific error). Since R7RS `raise` permits\n  raising arbitrary values, an exception carrying a port or a foreign-\n  owned channel is a realistic case, not a corner one. `exception` is now\n  the same `JoinResult` shape as `result`; a `.failed` build synthesizes a\n  diagnostic error instead of leaving the join reason void.\n\n- Both the thunk and result-path \"uncopyable type\" messages were\n  misleading for one real cause: gc_deep_copy.zig's `.channel` arm returns\n  UncopyableType for a genuinely uncopyable value AND for a channel owned\n  by neither thread (reached via a shared global instead of the thunk/\n  message that would have legally handed it over) -- the same error for\n  two different reasons. Broadened both messages to name the second cause\n  (verified against an A/B repro from review: a shared-global channel\n  raised or returned by the thunk).\n\n- Comment fix: \"the usual child_registry.storeResult path used by every\n  post-spawn failure\" overstated -- only the callWithArgs-failure path\n  actually stores a result; the earlier post-spawn failures set .errored\n  directly, same as the pre-spawn path being commented on.\n\n- Test-quality fixes: th.expectEval for two one-shot fixnum tests;\n  types.isChannel instead of a raw .tag comparison; the exception-envelope\n  test now receives and checks the drained 'irritant-marker value instead\n  of only checking that promotion happened; the 20-iteration thread-churn\n  test scales to 5 under -Dgc-stress=true (matches tests_robustness.zig's\n  pattern); new regression test pinning the .failed -> \"thread-join!:\n  result contains...\" path specifically (a thunk returning a port).\n\nDeliberately deferred to a follow-up issue (both reviewers frame these as\nnon-blocking): the deeper \"should a shared-global channel forwarded\nthrough an exception/result regain exact main-branch parity\" question,\nand the residual concurrent-double-join hazards (thread.join() called\ntwice on the same handle, a result-read race) that predate this PR and\nare best closed by giving fiber operations the same foreign-owner check\nchannels already have, rather than patching thread-join! point by point.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-12T18:47:22Z",
          "tree_id": "e3489bcd1568df13844f2c3cda76b0f6ebcc3a77",
          "url": "https://github.com/kaappi/kaappi/commit/55ccff0b61fcecac2a108309f838563cf5a769fc"
        },
        "date": 1783883846059,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.350855,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.047066,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.987968,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.565634,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006545,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.055023,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.543095,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070188,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.377668,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 2.100511,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.564963,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.437464,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.871535,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.720003,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043176,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "e4510f96d50b49c46a02b723f6e5c9eacd607523",
          "message": "Cross-thread wakeup: ThreadNotifier, unconditional sweep, shared-waiter registry (KEP-0002 P3) (#1485)\n\n* Cross-thread wakeup: ThreadNotifier, unconditional sweep, shared-waiter registry (KEP-0002 P3)\n\nImplements KEP-0002 Phase 3 (#1468): the reactor-backed cross-thread\nwakeup that Phases 1/2 (#1482/#1483) left as an unwired @panic. This\ncloses a real, already-reachable crash: a channel captured as a true\nlexical closure upvalue in a thread-start! thunk promotes in place on\nboth sides (parent and child), and either side calling channel-receive\non the still-empty promoted channel before the other sends hit the\nPhase 1 placeholder panic and SIGABRT'd the process. Verified against\na pre-fix build before writing any code.\n\n- src/reactor.zig: ThreadNotifier (kqueue EVFILT.USER / epoll eventfd /\n  WASI no-op), one per Reactor. Base refcount owned by the creating\n  Reactor; registrations are additive on top. Kernel-resource closing\n  is concentrated entirely in releaseNotifier's zero-transition (not\n  split with backend deinit), since kqueue's notifier knote shares `kq`\n  with ordinary fd polling -- splitting it would risk a double-close\n  race on whichever release happens last. wait()'s event loop filters\n  the notifier's own event out of the ordinary ReadyEvent stream on\n  both backends. New notifierLiveCount() leak-check counterpart to\n  shared_object.liveCount() (ThreadNotifier is deliberately not a\n  shared_object.Header instance).\n- src/fiber.zig: the per-scheduler shared-waiter registry and its\n  UNCONDITIONAL sweep -- a readiness-filtered sweep is the exact\n  model-checked lost-wakeup from kaappi/keps#12 (\"finding 1\"), not a\n  style choice. The wake_pending consume-protocol swap-loop is wired\n  into both schedule() (every tick) and parkOnReactor() (before\n  blocking and again after poll() returns, since a notify arriving\n  mid-block is what interrupted it). hasRunnableFibers() extended so\n  the deadlock check doesn't fire while a fiber still has a live\n  cross-thread wakeup path.\n- src/shared_channel.zig: ring() now actually calls notify(); §7\n  opportunistic dead-notifier pruning folded into the existing\n  register*Waiter dedup walk; promoteChannel gains §2 step 4's\n  local-waiter migration (a fiber parked on the local representation\n  before promotion is registered + enrolled so the first remote\n  send/receive can reach it).\n- src/primitives_fiber.zig: channelReceiveFn's shared-path @panic\n  replaced with channelReceiveShared -- always calls\n  shared_channel.receive() first each loop iteration (registration is\n  a side effect of .would_park) and only then parks, never the other\n  way around; parking before registering would leave nothing to ever\n  ring the fiber awake. This ordering also directly implements the\n  required \"a rung receiver that loses the pop race re-parks,\n  re-registers\" regression. The deadlock heuristic\n  (sharedWakeupPossible) reuses primitives_srfi18's existing\n  crossThreadWaitPossible rather than duplicating it.\n- src/pct_stress.zig + src/stress_channel.zig (new) + `zig build\n  stress-channel`: PCT-style randomized yield injection at\n  SharedChannel's lock wrappers and shared_object's retain/release,\n  off by default. Confirmed effective by deliberately reintroducing\n  the \"finding 1\" bug and verifying both the harness and the\n  deterministic unit test catch it, then reverting.\n\nDeferred to a follow-up (documented, not silently dropped): UQ3\n(thread-join!'s 1ms poll -> notifier) needs a structurally distinct\nregistration relationship from SharedChannel's, and isn't \"cheap\" per\nthe KEP's own bar for in-scope-now work.\n\nTest plan:\n- Required regressions: park locally -> promote -> remote send wakes\n  (§2 step 4); a rung receiver that loses the pop race re-parks and\n  re-registers (§5, model finding 1) -- both as automated tests.\n- zig build test and zig build test -Dgc-stress=true: full suite green\n  (832 tests; 824 pass + 6 scaled-down skips under gc-stress).\n- bash tests/scheme/run-all.sh: 1835/0.\n- zig build stress-channel across multiple seeds and heavier\n  producer/consumer/message-count configurations: all pass.\n- zig build wasm still compiles (WASI notifier backend is a no-op).\n- zig fmt --check clean.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* Address review: fix confirmed VM corruption and false-deadlock regression\n\nTwo confirmed, repro'd bugs from review, both in channelReceiveShared's\npark decision:\n\n- VM corruption: a dispatched (non-main) fiber that set .waiting and\n  then kept driving other fibers in the same native frame became\n  visible to schedule()'s round-robin (via shared_waiters) while its\n  own call was still live on the Zig stack. An unrelated fiber's own\n  nested runSchedulerStep could dispatch that mid-call snapshot and\n  resume bytecode past the in-flight receive() call, with the\n  destination register never written -- confirmed via a repro where\n  the second of two fibers parked on separate promoted channels\n  \"received\" the stale callee register instead of its real value.\n  Fixed: a dispatched fiber now always parks via the flat yield_retry\n  unwind (KEP-0002 §4 receive step 8), exactly like blockOrDeadlock's\n  existing behavior for every non-main fiber -- never a nested drive\n  after setting .waiting.\n\n- False deadlock: the sharedWakeupPossible() gate was applied to the\n  dispatched-fiber path too, so a channel that was EVER transiently\n  promoted (e.g. a thread captured a stub and exited without sending)\n  permanently broke ordinary local fiber-to-fiber use of that channel,\n  since refCount()/crossThreadWaitPossible() both correctly report\n  \"nothing remote\" afterward -- but a local sibling was one form away\n  from sending. Fixed: the gate now only applies to the main-fiber\n  path, where it's genuinely load-bearing (self-enrollment in\n  shared_waiters defeats parkOnReactor's own \"nothing can ever happen\"\n  detection). A dispatched fiber parks unconditionally, matching\n  blockOrDeadlock; whether that's a genuine deadlock is detected\n  elsewhere, same as the local-channel path already works.\n\nAlso drives local siblings once (SharedChannelPoll, `me` stays\n.running throughout) before deciding to park at all, so purely local\nchannel activity is tried first -- this is what makes the\ntransiently-promoted-channel case above work correctly end to end.\n\nOther review findings addressed:\n- shared_channel.zig: promoteChannel's migration loop no longer\n  swallows enrollSharedWaiter's OOM via `catch {}` (a silently dropped\n  registration was a permanent, undetectable hang); registerRecvWaiter\n  is now called once per promotion, not once per migrated fiber.\n- reactor.zig: Reactor.init allocates the notifier before the backend\n  (not after) -- the previous order leaked the backend's raw kq/\n  notify_fd on a notifier-allocation OOM, since KqueueBackend.deinit is\n  now a no-op (closing kq is releaseNotifier's job). notify()'s kevent/\n  eventfd syscalls retry on EINTR instead of silently dropping the\n  wakeup.\n- primitives_fiber.zig: enrollSharedWaiter failures roll back .waiting/\n  waiting_on and propagate instead of leaving a dangling park state;\n  runSchedulerStep errors in the main-fiber park path get the same\n  scoped cleanup.\n- tests_scheduler.zig: the 4 new scheduler tests use th.TestContext\n  instead of manual GC/makeTestVM setup, per this repo's coding\n  guidelines for tests needing multiple evals/result inspection.\n- tests_shared_channel.zig + stress_channel.zig: both stress tests now\n  use an identity-aware delivery oracle (one flag per (producer,\n  offset) pair) instead of aggregate count+sum, which could in\n  principle mask a lost delivery balanced by a duplicate elsewhere;\n  plus a bounded stall-detection deadline so a genuinely lost message\n  fails loudly (with the seed, for stress_channel.zig) instead of\n  spinning consumers forever.\n\nNew regression tests reproduce both confirmed bugs directly (two\nspawned fibers on separate promoted channels; a local sibling send\nafter a transient promotion) using the reviewer's own repro shapes.\n\nVerified: zig build test and -Dgc-stress=true green (834 tests, 6\nscaled-down skips under gc-stress); full Scheme/R7RS suite 1835/0;\nzig build stress-channel across several seeds and a heavier\nproducer/consumer/message-count configuration; zig build wasm still\ncompiles; zig fmt clean. Both original repro scripts (SIGABRT and the\ntwo new ones from review) now behave correctly end to end.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-13T10:55:58+05:30",
          "tree_id": "a53a2b9bd2b66a616051785a4cb6a96531461990",
          "url": "https://github.com/kaappi/kaappi/commit/e4510f96d50b49c46a02b723f6e5c9eacd607523"
        },
        "date": 1783922071052,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.555803,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.161484,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.919339,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.440744,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00678,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.053173,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.513628,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.067936,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.187052,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.986452,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.517998,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.470076,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.732319,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.833448,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.047626,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "e98846412302163dfcbc54a381281301b31d5eb2",
          "message": "Address PR #1485 review nits: stale comment, timed_out hoist, peer-death doc (#1486)\n\nThree non-blocking items carried over from the KEP-0002 P3 (#1468) review\nthat landed as PR #1485:\n\n- promoteChannel's migration-loop comment claimed registerRecvWaiter ran\n  \"above\" the loop; it actually runs once, after it. Corrected, and noted\n  the OOM-mid-loop corner this creates (stale-but-self-healing enrollments\n  vs. unreached fibers left with no wake path) rather than un-enrolling on\n  that error path.\n- channelReceiveShared reset me.timed_out after the SharedChannelPoll local-\n  sibling drive instead of before it. runSchedulerStep's generic loop bails\n  whenever timed_out is true regardless of Ctx, so a stale flag from an\n  unrelated earlier timed wait could silently skip the drive and let the\n  park decision run with the world still active. Hoisted the reset above\n  the drive.\n- Documented the KEP-0002 §5 accepted liveness gap on sharedWakeupPossible:\n  a receiver parked after this returned true hangs forever if the peer\n  exits without sending, since a stub release rings nothing and the parked\n  fiber's own registry entry keeps the deadlock detector disarmed. Go-style\n  hang, accepted by design; §6's planned per-call timeout is the escape\n  hatch.\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-13T13:15:41+05:30",
          "tree_id": "77b2cc46d1280c43a24d1a708748628b39f68a8c",
          "url": "https://github.com/kaappi/kaappi/commit/e98846412302163dfcbc54a381281301b31d5eb2"
        },
        "date": 1783930416490,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.37971,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.430871,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.672718,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.317269,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006411,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.043726,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.380355,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.05563,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.955922,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.474842,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.287663,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.414862,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.426963,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.101245,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.038916,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "d54c45c2b9d864ff6b033e34b19f87fdbffa168b",
          "message": "KEP-0004 Phase 0/1: unify cond-expand library checks, add subsystem features (#1488)\n\n* KEP-0004 Phase 0/1: unify cond-expand library checks, add subsystem features\n\nPhase 0 (cleanup): evalFeatureReq's hardcoded known_libs array in\ncompiler_conditionals.zig never listed any kaappi.* library or srfi.18,\nbut callers never noticed because it silently fell through to the\nglobals.libraryExists callback, which already checked the live registry\ncorrectly. Deleted the redundant array outright and extracted the\nduplicated \"does this library exist\" check (previously hand-written\nseparately in vm.zig's checkLibraryExists and vm_library.zig's\nevalLibFeatureReq) into one shared vm_library.libraryIsAvailable(),\ncalled from both entry points.\n\nPhase 1: added kaappi-fibers, kaappi-reactor (all targets, including\nwasm32-wasi per KEP-0001 Phase 4), and kaappi-threads (omitted on wasm,\nmatching Lib.wasmAvailable()'s existing srfi_18 => false gate) as bare\ncond-expand feature identifiers, so portable library code has a short\nway to detect these subsystems instead of spelling out (library ...)\nrequirements.\n\nVerified: 839/839 Zig unit tests, 1395/1395 R7RS suite, 440/440 Scheme\ntest files, plus manual end-to-end checks against a built binary for\nboth the new identifiers and the known_libs-removal regression risk.\n\nSee keps/keps/0004-discoverable-deviations.md.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* Address review: honor sandbox mode in libraryIsAvailable\n\nCodeRabbit flagged, and I independently confirmed against a built\nbinary, that libraryIsAvailable fell through to a disk probe\n(libraryFileExists) even under --sandbox, while tryLoadLibraryFromFile\nrejects every file-backed load there (vm_library.zig:428). Result:\n(cond-expand ((library (srfi 41)) ...)) reported the library available\nwhile the matching (import (srfi 41)) then failed — a behavioral\nmismatch, and a way for sandboxed code to probe host filesystem state\nthrough cond-expand.\n\nPre-existing in both call sites this PR unified (checkLibraryExists and\nevalLibFeatureReq had the identical get()-then-libraryFileExists()\nsequence on main already) — not a regression introduced here, but this\nPR's consolidation is the natural single place to close it.\n\nAlso extends features-consistency.scm (#1177) with the three KEP-0004\nPhase 1 identifiers for Scheme-level parity with the new Zig tests, per\nthe review's optional suggestion.\n\nLeft two other review comments as-is per triage: the new tests'\nGC/VM setup duplication matches the existing style in this file (no\nth.expectEval* helper covers symbol-result assertions), and the wasm\nbranch of platform_features isn't unit-testable from a native test\nbinary (already noted inline in types.zig).\n\nVerified: 840/840 Zig unit tests, 1395/1395 R7RS suite, 440/440 Scheme\ntest files. Manually reproduced the sandbox mismatch against a built\nbinary before the fix and confirmed it's closed after.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-13T08:02:16Z",
          "tree_id": "1270eadf2910b2a65b9a777a102d838144645190",
          "url": "https://github.com/kaappi/kaappi/commit/d54c45c2b9d864ff6b033e34b19f87fdbffa168b"
        },
        "date": 1783931403516,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.39606,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.845261,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.963455,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.545601,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006437,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.056393,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.520186,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070448,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.462565,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 2.009258,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.656881,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.434867,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.866668,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.748023,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043986,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "413c1b823ef993eac2c90c6d1080db8be4e83c3c",
          "message": "docs: refresh LLVM backend Lambda Strategy for the tiered emitter (#1501)\n\nThe \"Lambda Strategy\" section and the node-output table described lambdas as\nalways serialized to source and evaluated via kaappi_eval at runtime. That has\nbeen stale since the native closure tier landed: named/top-level and\nclosed/capturing lambdas now compile to real LLVM functions.\n\nRewrite the section to match src/llvm_emit_lambda.zig's three tiers (capturing\nclosure, closed/named native function, eval fallback), and document what is\ncompiled natively (fixed arity, variadic rest params, by-value closures,\nself-tail-call loops) and the precise eval-fallback triggers. Also de-stale the\nadjacent table rows for call/define/set!/let so let/let* are no longer lumped\nwith the genuinely eval-only forms.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-13T15:42:16+05:30",
          "tree_id": "76806f3d39d55b919ca714d5be9dd1c969a5f415",
          "url": "https://github.com/kaappi/kaappi/commit/413c1b823ef993eac2c90c6d1080db8be4e83c3c"
        },
        "date": 1783939012288,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.057551,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.8119,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.924796,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.451033,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007267,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.052844,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.513238,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069509,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.178395,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.987491,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.514285,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.47496,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.747629,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.882975,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045575,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "ce6656c7ecef5201dd009d04e454c4ef4b889732",
          "message": "KEP-0002 Phase 4: capacity, timeouts, close for cross-thread channels (#1502)\n\n* Capacity, timeouts, close: bounded channels, drain-then-EOF (KEP-0002 P4)\n\nImplements the amended §6 close semantics from KEP-0002 (kaappi/keps#12):\nEOF outwaits reservations and the failure path rings receivers on a\nclosed channel. Adds make-channel's optional capacity argument,\n[timeout [timeout-val]] on channel-send/channel-receive (SRFI-18\nshape), and channel-close!/channel-closed?, for both the local\n(unpromoted) and shared (cross-thread) channel representations.\n\nThe §4-6 protocol was already model-checked in Phase 1-3 (re-verified\nagainst the KEP's exact pseudocode with the TLA+ suite before writing\nany code); this phase wires it up end to end and adds the local-channel\nequivalent.\n\nFixes #1469\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* Fix shared-channel timeout swallowed by a spurious wake-all retry\n\nchannelSendShared/channelReceiveShared's main-fiber (and redispatched\ndispatched-fiber) loop can re-enter its local-sibling poll drive with\n`me.status == .running` while a previously-armed reactor timer is\nstill live: sweepSharedWaiters (the wake-all discipline §5 requires)\nflips a .waiting fiber to .suspended on *any* notify, with no per-\nwaiter targeting, and never cancels its timer. If that timer then\npops while the poll drive is running, wakeReadyFiber silently drops\nit (it only sets timed_out for a .waiting/.io_waiting fiber) --\npermanently losing the timeout for the rest of the wait.\n\nFix: detach the timer from the reactor's heap (not `me.deadline_ns`,\nwhich stays the single record of the original absolute deadline)\nbefore every poll-drive iteration, and re-arm from that preserved\nvalue at the next park step. Clearing the field too, as an earlier\nversion of this fix did, would make every re-arm fall through to a\nfreshly re-parsed relative timeout and silently extend it on each\nspurious wake instead.\n\nAlso tightens a Phase 4 regression test's leak-check discipline to\nmatch its neighbors (explicit baselines, non-deferred reactor\nteardown before the assertions).\n\nFound in PR #1502 review.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-13T21:02:55+05:30",
          "tree_id": "d57a1211c98c1abbdd10e233e41c4774e3b04dea",
          "url": "https://github.com/kaappi/kaappi/commit/ce6656c7ecef5201dd009d04e454c4ef4b889732"
        },
        "date": 1783958617139,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.354451,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.802242,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.90259,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.557304,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006474,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.053304,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.507013,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069939,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.388379,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.977181,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.567285,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.427448,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.842838,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.712226,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043644,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "c8f8549f5e5dee13fc37ba96eb5c5a858f814a27",
          "message": "docs: add Machine legibility section and correct GC description in vision.md (#1519)\n\n* docs: add Machine legibility section to vision.md\n\nRecords the machine-legibility strategic direction — making Kaappi the most\nlegible Scheme for humans and AI agents to understand, diagnose, and\nautomate — in the canonical vision doc, framed as the third core value\n(Transparency over magic) turned outward: from a runtime transparent to\ncontributors to a toolchain transparent to the programs that drive it.\n\nCaptures the falsifiable operational test (an agent goes from failing\nprogram to verified fix using only documented CLI output), the three pillars\n(Diagnose / Understand / Automate), and the non-goals that keep this as\nextension where R7RS-small is silent rather than deviation where it speaks —\nnotably the declined static type system. Cross-references KEP-0005 (the\ndiagnostic contract) and the tracking epic kaappi#1503.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n* docs: correct the GC description in vision.md to match the implementation\n\nThe \"Simplicity over abstraction\" value and the GC design-decision section\nstill described a pre-generational collector — \"no generational promotion, no\nwrite barriers,\" and a heading arguing against generational GC. The collector\nhas since become generational (young/old split, minor vs. full collections,\nold→young write barrier feeding a remembered set, promotion after surviving\nrepeated collections; see memory.zig, gc_collect.zig, and the Object header in\ntypes.zig).\n\nRewrite both passages to describe that accurately while keeping the doc's\nframing: the collector is still comprehensible, and the write barrier is\npresented as deliberate, earned machinery rather than something avoided. The\nstill-true points (no copying, no compaction, fragmentation not a problem in\npractice) are retained.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-13T22:06:04+05:30",
          "tree_id": "560ecf3603a8871bb0b258a5d461d3c89bc5700c",
          "url": "https://github.com/kaappi/kaappi/commit/c8f8549f5e5dee13fc37ba96eb5c5a858f814a27"
        },
        "date": 1783961919218,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.429727,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.011852,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.929102,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.508571,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006437,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.053769,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.506232,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070178,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.385618,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.980549,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.583547,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.432434,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.842238,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.714618,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044626,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "c008bac7b9a304f00e78997742700221d57b46f6",
          "message": "KEP-0002 Phase 5: (kaappi parallel) pools, parallel-map, processor-count (#1522)\n\nPure Scheme worker pools (make-pool/pool-submit/task-wait/pool-shutdown!)\nand parallel-map/parallel-for-each over (srfi 18) + (kaappi fibers),\ndegrading to fiber workers under --sandbox and on WASM where real threads\nare unavailable. processor-count is the one new native primitive.\n\nThe library is embedded into the binary (build.zig + vm_library.zig) so\nit stays importable under --sandbox, which otherwise blocks every\nfile-backed library load outright -- a plain portable .sld would be\nunimportable there at all, not just degraded.\n\nFound and filed two pre-existing runtime gaps while building this:\n- #1520: a closure that crosses thread-start! and then calls a\n  separately-defined library procedure hangs. Worked around throughout\n  by inlining (matches the KEP's own reference pseudocode).\n- Confirmed #1489 (lost cross-thread wakeup) is reachable through\n  ordinary parallel-map usage past a few hundred concurrent submissions,\n  not just synthetic repros. Documented; parallel-primes (kaappi-examples)\n  demonstrates the chunked-pool workaround.",
          "timestamp": "2026-07-14T01:10:06+05:30",
          "tree_id": "4089689a5344781b83f290e1fc917840ab5fe669",
          "url": "https://github.com/kaappi/kaappi/commit/c008bac7b9a304f00e78997742700221d57b46f6"
        },
        "date": 1783973346604,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.236898,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.989179,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.648194,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.219391,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00646,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.042433,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.357723,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.05387,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.862656,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.459348,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.285076,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.416622,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.39543,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.854535,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.038173,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "1da7cf32ba3b235d896a6abe9e997b4b4b73e834",
          "message": "Fix dirty-snapshot dispatch hazard in mutex-lock!/condition-variable-wait (#1521)\n\n* Fix dirty-snapshot dispatch hazard in mutex-lock!/condition-variable-wait (#1487)\n\nmutex-lock!, condition-variable-wait (mutex-unlock! with a condvar),\nthread-join!'s fiber path, and timed local channel-send/receive all set a\nfiber .waiting and then call runSchedulerStep recursively from the same\nnative frame -- the identical shape already fixed for shared channels in\nPR #1485. If something wakes that fiber (flips it .suspended) while its\nown nested drive is still live deeper on the Zig call stack, a different\nfiber's own nested schedule() call can dispatch it from a stale, mid-\nnative-call register snapshot, resuming bytecode past the in-flight\nprimitive call with the destination register never written. Confirmed via\na 3-fiber nested mutex-contention repro (git-stash A/B).\n\nRather than rewriting each call site to use PR #1485's yield_retry\ndiscipline, this lands the issue's alternative suggestion: a generic\n`driving` guard on Fiber, set for the whole extent of any\nrunSchedulerStep call and excluded from dispatch-selection regardless of\nstatus. A per-site rewrite would have silently broken cross-OS-thread\nmutex/condvar polling (which depends on the specific waiting loop's own\nperiodic recheck) and reintroduced the exact lost-wakeup race the condvar\ngeneration-snapshot-before-unlock ordering exists to prevent. The generic\nguard sidesteps both and, as a bonus, also closes the identical hazard in\nthread-join! and timed local channel-send/receive, which weren't named in\nthe issue but turn out to have the same bug.\n\nFirst attempt at the guard baked the exclusion into schedule() itself,\nwhich broke yieldFn/threadYieldFn's \"is yielding worthwhile\" advisory\ncheck -- a busy sibling's (yield) calls stopped seeing a driving ancestor\nwhose wait had just resolved, turning yield into a no-op and reproducing\nissue #1440's starvation symptom by a different path (caught by the\nexisting fiber-timed-mutex-lock-not-starved-by-busy-sibling.scm test).\nFixed by splitting schedule() (unchanged, used by advisory checks and\nvm_calls.zig's non-nested switchTo dispatch) from a new\nscheduleForDispatch() (excludes driving fibers, used only by\nrunSchedulerStep's own dispatch loop).\n\nVerified: zig build test and -Dgc-stress=true green; full Scheme/R7RS\nsuite 1839/0; zig build wasm and -Dtarget=x86_64-linux still build; zig\nfmt clean.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* Address PR #1521 review nits: stale schedule() comment, unreachable-guard note, test style\n\n- tests/scheme/smoke/mutex-nested-dispatch-dirty-snapshot-1487.scm: the\n  comment wrongly credited plain schedule() with excluding driving\n  fibers, contradicting the actual schedule()/scheduleForDispatch()\n  split (CodeRabbit + manual review, both flagged the same lines).\n- src/fiber.zig: note that runSchedulerStep's `next_idx == my_idx` guard\n  is now unreachable (driving subsumes it) but kept as defense-in-depth,\n  so it doesn't read as live logic.\n- src/tests_scheduler.zig: convert the three new driving-guard tests to\n  th.TestContext, matching the rest of the file (CodeRabbit).\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-13T20:04:34Z",
          "tree_id": "6260853a71648582dbeb6b49d3a3d07d283827df",
          "url": "https://github.com/kaappi/kaappi/commit/1da7cf32ba3b235d896a6abe9e997b4b4b73e834"
        },
        "date": 1783974829752,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 5.383515,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.230968,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.931462,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.536127,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007151,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.054095,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.500986,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069549,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.505183,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.942854,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.588306,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.435335,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.841356,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.688206,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.04449,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "3e00924a667396a5d406c7998c3e6c64cbfe35d9",
          "message": "Resolve portable SRFI libraries via exe-relative lib/ fallback (#1524)\n\n* Resolve portable SRFI libraries via exe-relative lib/ fallback\n\nresolveLibraryPath only checked cwd-relative paths, --lib-path, the\nrunning script's own directory, and ~/.kaappi/lib — none of which point\nat a `zig build`-produced binary's own source tree. A binary built from\nsource and run from any other directory, with no prior thottam/installer\nsetup, couldn't resolve portable (non-built-in) SRFI .sld libraries.\n\nAdd a shared exe-relative lib-dir lookup (kaappi_paths.getExeRelativeLibDir),\nmirroring the <exe_dir>/../lib search already used to find libkaappi_rt.a\nfor the native backend. build.zig now installs lib/ into zig-out/lib/\nalongside the exe so the two line up, and main.zig adds that directory as\na last-resort fallback after ~/.kaappi/lib so an existing install is never\nshadowed. native_compiler.zig's near-duplicate local copy now delegates to\nthe shared helper instead of duplicating the platform-specific lookup.\n\nFixes #1523.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* Address PR #1524 review nits: macOS realpath, vacuous test, dup import\n\n- kaappi_paths.getExeRelativeLibDir: _NSGetExecutablePath can return a\n  symlinked or relative path (e.g. a Homebrew Cellar symlink), which would\n  derive ../lib from the wrong tree. Resolve it via std.c.realpath first,\n  falling back to the raw path if that fails. Verified against a synthetic\n  symlinked-bin/kaappi -> real/bin/kaappi layout.\n- Reject a Linux readlink(\"/proc/self/exe\") result that exactly fills the\n  buffer, symmetric with the macOS branch's overflow handling.\n- The getExeRelativeLibDir unit test silently passed if the function\n  returned null instead of exercising the /lib suffix check; assert\n  non-null explicitly.\n- main.zig: hoist the two function-local @import(\"kaappi_paths.zig\") in\n  mainImpl's library-path block into one.\n\nFlagged by CodeRabbit and by manual review on PR #1524.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-13T20:27:54Z",
          "tree_id": "e81673c69d8a275585de6441e4bf4eb60914badc",
          "url": "https://github.com/kaappi/kaappi/commit/3e00924a667396a5d406c7998c3e6c64cbfe35d9"
        },
        "date": 1783976212106,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.081547,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.440964,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.946833,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.441979,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006748,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.053019,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.510684,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068134,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.256529,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.991209,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.538011,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.477079,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.7702,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.81156,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.046403,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "7d2a7655aa78adc2a32c21e58769378595909145",
          "message": "Preserve a closure's lib_env when deep-copying across threads (#1479) (#1526)\n\nA procedure defined inside a `define-library` body that `thread-start!`s a\nthunk calling into another library's exported procedure hung (kaappi-http's\n`http-listen-threaded`) or raised \"undefined variable\" (unguarded) on every\nrequest.\n\nRoot cause: `GC.deepCopy`, which copies the thunk closure from the parent GC\nto the child OS thread's GC, set `new_func.env = null`. Runtime name\nresolution uses `func.env orelse self.globals` (vm_dispatch.zig), so nulling\nthe library's `lib_env` silently redirected every lookup in the child to the\nshared globals map — where library-scoped imports don't live. The child then\nfailed to resolve the cross-library name; http's `guard` swallowed the error\nand closed the socket, so the client just saw a hung connection. The same\ncode defined at top level worked because a top-level import lands in globals,\nwhere `env == null` already looks.\n\nFix: preserve `new_func.env = func.env`. `env` is a raw `*StringHashMap`\npointer into the shared library registry — `VM.initForThread` shares\n`vm.libraries` by pointer and the parent keeps every `lib_env` alive, so the\nchild resolving names through it (and running the parent-heap procedures it\nfinds) is exactly how it already runs any shared global. It is not a GC\nValue, so the collector never traverses it and no cross-heap mark-bit is\nwritten. `env_val` (the eval/immutability Environment *object*, a GC Value)\nstays NIL rather than sharing a parent-heap object into the child heap;\nruntime resolution uses `env`, not `env_val`, and a normally loaded library\nhas `env_val == NIL` here anyway.\n\nRegression test `library-thread-cross-call-1479.scm` (+ `lib1479/` fixtures)\ncovers both the plain and guard-wrapped (http-shaped) forms, including the\ncallee resolving its own library-scoped helper; it fails (exit 1) without the\nfix and passes with it. Full unit suite, gc-stress (srfi18 cross-thread copy),\nand Scheme suite (449 files) green.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-14T09:50:32+05:30",
          "tree_id": "383b21a553372260db40f648b5996cba20d73dc3",
          "url": "https://github.com/kaappi/kaappi/commit/7d2a7655aa78adc2a32c21e58769378595909145"
        },
        "date": 1784004511661,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.906324,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.438422,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.925709,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.514686,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006363,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.054591,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.50269,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069455,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.315357,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.957682,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.611079,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.426528,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.833504,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.622483,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043124,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "7177dbb17497500170b60b06afb6e4d49148028e",
          "message": "Make fiber scheduling O(1) with a ready ring and free-slot list (#1477) (#1525)\n\nFiberScheduler did an O(fiber count) linear scan on the dispatch hot path\nand again on every spawn:\n\n- schedule()/scheduleForDispatch() round-robin-scanned the whole `fibers`\n  array (mostly parked io_waiting fibers on a busy server) to find the next\n  runnable fiber, on every dispatch.\n- addFiber() scanned the array for a reusable slot on every spawn, so\n  spawning N live fibers was O(n^2).\n- Two more O(n) scans hid on the same tick: anyIoWaiting() scanned all\n  fibers to gate the reactor poll, and yield's advisory `schedule() == null`\n  check scanned them again.\n\nReplace all four with incremental O(1) bookkeeping:\n\n- A ready ring (FIFO of runnable slot indices) fed by markRunnable at every\n  transition to .created/.suspended, consumed round-robin by the dispatch\n  paths. Each Fiber carries its stable `sched_idx` (so wakes enqueue in O(1))\n  and a `queued` flag (so the ring can't accumulate duplicates).\n- A free-slot list fed by retireSlot at every .completed/.errored\n  transition, so addFiber reuses a vacated slot without scanning (and appends\n  straight away when none is free). Slot 0 (main) is never recycled.\n- anyIoWaiting() now reads the reactor's registration count in O(1).\n- yield's advisory check uses a new non-consuming anyRunnable() peek.\n\nThe ring and free list are pure accelerators: the dispatch paths keep the\noriginal O(n) round-robin scan as an authoritative fallback, so correctness\nnever depends on markRunnable coverage (any status set directly without it —\nmuch test code — still dispatches correctly, just via the scan). The\nadvisory peek is ring-only by design to stay O(1); a missed enqueue there\nonly costs a yield that no-ops when it could have rotated, never correctness.\n\nDriving fibers (#1487) are dropped from the ring rather than dispatched,\nconsistent with \"only the parked fiber's own loop ever consumes its wake\";\nthe fallback scan still finds them for plain schedule()/anyRunnable.\n\nMeasured with a two-worker ping-pong among N channel-blocked siblings\n(ns per real dispatch): baseline 416 / 4143 / 25996 at N=100 / 1000 / 5000;\nafter, a flat ~170 regardless of N — O(n) -> O(1), 154x at N=5000. Full unit\nsuite, R7RS (1395), and Scheme suite (449 files) green, including under\n-Dgc-stress=true for the fiber/scheduler/srfi18/port tests.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-14T09:50:08+05:30",
          "tree_id": "7588c0a63aa6ec8e5107fa7ecba65153d5d2f1ff",
          "url": "https://github.com/kaappi/kaappi/commit/7177dbb17497500170b60b06afb6e4d49148028e"
        },
        "date": 1784004578404,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 5.345646,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.176216,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.971121,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.533747,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006361,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.055437,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.504477,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069805,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.344469,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.967894,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.577242,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.439114,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.841525,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.7046,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043521,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "a3f3618367c489a8390860247d191f597bd2219e",
          "message": "Add fd->port to give a raw fd reactor-integrated I/O (#1478) (#1527)\n\nkaappi-net's TCP sockets never reach the fiber I/O reactor: tcp-recv/tcp-send\nare bare blocking send(2)/recv(2) FFI calls and poll-read/poll-write are a raw\nfcntl+poll(2) wrapper, none of which touch Reactor.register/waitForFd. So\nkaappi-http's http-listen-fiber layers a fixed 1ms poll-then-sleep loop on top\n-- a ~1ms tax on every request even fully uncontended (747 vs 3329 req/s at\nconcurrency=1 in the KEP-0001 Phase 7 benchmarks).\n\nThe blocker was crossing the FFI boundary: the reactor and waitForFd are\nVM-internal, and a standalone \"wait on this fd\" primitive can't work under the\npark/re-execution protocol -- it never drains the fd, so a re-executed park\nre-parks forever. The primitives that do work (readOneByte/portWriteBytes) do\ntry-syscall-then-wait-on-EAGAIN as one unit, and every port fd > 2 already\nflips to O_NONBLOCK lazily and suspends the fiber on the reactor.\n\nSo expose that machinery directly: (fd->port fd) wraps a raw descriptor as a\nbidirectional binary port. A kaappi-net socket fd (from tcp-accept/tcp-connect,\nalready plain integers) becomes a normal reactor-integrated port -- read-u8/\nread-bytevector!/write-bytevector suspend the fiber on EAGAIN instead of\nbusy-polling, no C changes needed. The port owns the fd (close-port closes it,\nwakes parked fibers, unregisters from the reactor); fd 0/1/2 are refused to\npreserve the standard streams' blocking semantics. Lives in (kaappi ffi), which\nFFI socket libraries already import.\n\nTests (tests_port_io.zig): a reader fiber on an fd->port pipe parks on the\nreactor and wakes exactly when the peer writes; fd 0/1/2 and non-fixnums are\nrejected. Green under -Dgc-stress=true and the full unit suite.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-14T04:32:56Z",
          "tree_id": "3ce5e014a2a252341b804fc538d39eabf004d13e",
          "url": "https://github.com/kaappi/kaappi/commit/a3f3618367c489a8390860247d191f597bd2219e"
        },
        "date": 1784005377878,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.086167,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 10.526862,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.931487,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.44145,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006825,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.0528,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.508781,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.067723,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.198317,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.978025,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.514907,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.480214,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.751677,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.819143,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045751,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "5e86f2319532a35b644d9ff9b4ccf1fea284118f",
          "message": "Clear stale gap registers before call/cc continuation capture (#1464) (#1528)\n\n* Clear stale gap registers before call/cc continuation capture\n\nA full call/cc continuation snapshots the contiguous register range\n[0, max_reg), where max_reg is the highest live frame end. That range\nspans \"gap\" registers between live frame windows — slots vacated by\nreturned frames that still hold that frame's last heap pointer.\n\nmarkVMRoots only marks per-frame windows, so it never keeps a gap\ntarget alive; under gc-stress the collector frees it, leaving the gap\nregister dangling. captureContinuation copied the gap verbatim into the\nsnapshot, and marking that continuation later dereferenced the freed\nobject — a GC use-after-free the fuzz workflow hit as a segfault in\nmarkValueInner reading obj.owner (issue #1464).\n\nScrub the dead gap slots to UNDEFINED before the snapshot so it covers\nexactly what the root marker protects. Restore copies the snapshot back\nverbatim and no frame ever reads a gap slot, so this is\nbehavior-preserving.\n\nThe same contiguous-vs-per-frame inconsistency exists in the fiber\nsave/mark path (saveCurrentFiber + markFiberState); that sibling is\ntracked separately.\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>\n\n* Make gap-register clearing allocation-free\n\nThe first cut allocated a per-capture bool bitmap and scanned the full\n[0, max_reg) range, regressing the call_cc benchmark ~1.9x (a tight\ncapture loop pays that cost on every call/cc).\n\nFrame bases are non-decreasing — every call places its callee's frame\npast the caller's base, and continuation restore preserves that order —\nso a single ordered sweep tracking the highest covered register finds\nthe gaps with no scratch buffer and touches only the gap slots. A debug\nassert guards the ordering invariant. The call_cc micro-benchmark is\nnow indistinguishable from baseline; the full suite stays green under\n-Dgc-stress=true.\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-14T13:35:24+05:30",
          "tree_id": "9b8e726da683419e8cfc953937d3c6784ee8c5a8",
          "url": "https://github.com/kaappi/kaappi/commit/5e86f2319532a35b644d9ff9b4ccf1fea284118f"
        },
        "date": 1784017887131,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.446558,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.00399,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.907314,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.55037,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006476,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.053896,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.518164,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069352,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.414555,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 2.011509,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.566264,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.429483,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.861097,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.635428,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042889,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "ef88d7e64596938ddeb87626b9a2b3e6c263e0bc",
          "message": "Bound fuzz eval by instruction count under gc-stress (#1531)\n\nThe grammar/native/portable generator-coverage gates and the differential-\noracle regression gate in tests_fuzz.zig were unconditionally skipped under\n-Dgc-stress=true. A full collection on every allocation slows evaluation by\norders of magnitude, so the fixed 100 ms per-program deadline degenerated\ninto \"did it time out\" rather than measuring whether the generator produces\nvalid programs — a gc-stress build lost these regression gates entirely.\n\nA gc-stress build executes the *same* number of bytecode instructions as a\nnormal build; only wall-clock time changes. So bound by instruction count\nthere instead: evalNormalized sets vm.instruction_limit (2M, ~50x the largest\ncorrect generator program measured over 300 seeds and well under the >10M\nloop-heavy tail the gates intentionally count as misses) and keeps only a\nloose wall-clock backstop. Normal builds are unchanged — the limit stays null\nand the 100 ms deadline applies as before. runUntil checks the limit inside\nthe existing per-1024-instruction block, so the hot path is untouched.\n\nUnder gc-stress the gates now measure generator correctness: grammar 56/60,\nnative 60/60, portable 60/60, and the oracle compares 57/60 fixed-seed pairs\n(3 giant-loop seeds hit the budget on both paths) instead of 0.\n\nCloses #1447, #1448, #1449, #1450\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-14T15:50:16+05:30",
          "tree_id": "b90bf5db44b51db2b29680784a1b70cecd3aefb0",
          "url": "https://github.com/kaappi/kaappi/commit/ef88d7e64596938ddeb87626b9a2b3e6c263e0bc"
        },
        "date": 1784026343314,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.421673,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.804535,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.691257,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.443048,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006437,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.04571,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.391807,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.05657,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.03715,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.503312,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.357821,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.430055,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.498674,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.077451,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.038728,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "9bc79a2a6a20e51807ac61bea798858518b98ae7",
          "message": "Compile the LLVM native backend at -O2 with an IR-verify safety net (#1532)\n\nThe linker was invoked with no -O flag, so LLVM compiled the emitter's\ndeliberately naive IR at -O0 — none of the optimization that is the reason to\nuse LLVM ran. Every immediate was `add i64 0, K`, let-bindings and shadow-stack\nroot slots and args arrays went through alloca/load/store, and if/and/or became\nlong br/phi chains, all left in place.\n\nPass -O2 in tryLink (kaappi compile), the `zig build native` step, the\ndocumented manual flow, and the e2e harness so mem2reg/instcombine/simplifycfg/\nconstant-folding collapse this. Root-slot allocas whose address escapes into\nkaappi_gc_push_root correctly stay in memory for GC scanning.\n\nAdd the paired safety net: hand-written IR that passes -O0 can hide\nwell-formedness bugs that break or miscompile under -O2's stricter verifier and\npasses. tests/e2e/run-e2e.sh now verifies every emitted .ll before linking,\nchoosing opt -passes=verify, llvm-as, or (typical on CI, where neither is on\nPATH) zig cc -c — the same bundled LLVM that links the binary, so the step never\nsilently no-ops. The verifier runs without -w so no malformed-IR diagnostic is\nhidden; -w stays on the user-facing compile, where it only silences cosmetic\nwarnings (a hard verifier error still fails regardless).\n\ne2e stays green (24/24, native output diffs identically against the\ninterpreter); a new tak.scm locks in the -O2 native path on multi-way recursion.\nfib(38) runs 1.11x faster (-O0 1.605s -> -O2 1.441s); the IR shrinks (fib 67 ->\n51 instruction lines, all `add i64 0,K` immediates folded). Larger gains need\nLTO to inline the runtime primitives, tracked separately as #1493.\n\nCloses #1492.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-14T15:50:37+05:30",
          "tree_id": "f3ec57e6f0647c836ad8afe5bc5373b476510bc7",
          "url": "https://github.com/kaappi/kaappi/commit/9bc79a2a6a20e51807ac61bea798858518b98ae7"
        },
        "date": 1784026472921,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.348989,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.339414,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.91493,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.430202,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006338,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.054042,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.501162,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069425,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.348304,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.941458,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.594865,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.438538,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.825884,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.691371,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044627,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "b464e02480147ccf565190f7190d845ac56423bb",
          "message": "Clear stale gap registers before fiber suspension snapshot (#1529) (#1533)\n\nmarkVMRoots marks a running fiber's registers per frame window and skips\nthe dead \"gap\" slots between windows, but saveCurrentFiber copies the\ncontiguous register span and markFiberState marks it contiguously. A gap\nslot's stale pointer — freed during the fiber's run because per-frame\nmarking never protected it — was copied into the fiber's saved snapshot\non suspension, and a later collection while the fiber was parked traced\nthat dangling pointer, a GC use-after-free (sibling of the call/cc bug\nfixed in #1464/#1528).\n\nMove clearGapRegisters (the allocation-free ordered sweep from #1528) to\na shared VM method and call it in saveCurrentFiber before the register\nmemcpy; captureContinuation now calls the same method. Scrubbing dead gap\nslots to UNDEFINED is behavior-preserving because no frame ever reads\nthem. Adds a gc-stress regression test that segfaults without the scrub.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-14T16:08:05+05:30",
          "tree_id": "0d133607e92613c69f7d08c20c1fb4eb90a42780",
          "url": "https://github.com/kaappi/kaappi/commit/b464e02480147ccf565190f7190d845ac56423bb"
        },
        "date": 1784027144602,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.361988,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.204196,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.903569,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.40409,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006334,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.053697,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.499444,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069393,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.41092,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.96064,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.598438,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.432013,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.857396,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.643883,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043938,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "b2043de60a22461ed894e0ec7f6397ac48f2ada0",
          "message": "Add A/B/C/D envelope-cost benchmark matrix (KEP-0002 Phase 7) (#1535)\n\nGrows src/bench_channel.zig from the Phase 1 single-lever harness into the\nfull P3 elision-lever matrix (research/open-problems.md P3) that the Phase 7\nA/B/C/D decision is pre-registered against: (A) per-message GC struct as\nshipped, (B) reusable per-channel arena, (C) immediates skip the envelope,\n(D) refcounted immutable side-heap for large payloads. A counting allocator\nreports true allocations/message and a printer evaluates the pre-registered\ncriteria mechanically.\n\nThe point of the matrix is the decision it records, not the raw numbers:\n\n- (C) ships -- the immediate fast path is 28-120x on fixnums and erases the\n  two fixed allocations (GC struct + ~8 KiB root buffer) that lever A pays\n  per message even for a zero-object fixnum payload.\n- (B) is a ship candidate whose verdict is build-mode sensitive: it clears\n  the >= 30%-on-all-small-messages bar under both safety-on builds\n  (ReleaseSafe 57-98%, Debug 65-99%) but dips the 1 KiB string to ~26% under\n  ReleaseFast. Since the shipped binary is ReleaseSafe (protocol §4.5) the\n  operative reading is \"replace A\", conditioned on the pre-registered second\n  clause -- a real arena in shared_channel.zig surviving gc-stress/leak with\n  no lifetime rule leaking outside that file -- which this micro-benchmark\n  does not settle.\n- (D) is measured only (2.6-2.8x on 64 KiB, 8->2 allocations, no copy-out);\n  its shipping decision belongs to the KEP-0003 gate (#1474).\n\nThis is the envelope-cost half of #1472, at the eyeball benchmark tier (like\nbench-fibers/bench-reactor), on one machine (macOS aarch64). The parallel-map\ngate campaign, the Linux run, the lever-B arena prototype, shipping C, and the\nKEP-0002 UQ 1 amendment remain. Full write-up and caveats in\ndocs/dev/kep-0002-phase7-envelope-benchmarks.md.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-14T16:40:17+05:30",
          "tree_id": "edd187e57f8d6088b2b77ab60a975188edce4c78",
          "url": "https://github.com/kaappi/kaappi/commit/b2043de60a22461ed894e0ec7f6397ac48f2ada0"
        },
        "date": 1784029261248,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.073962,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.77298,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.91355,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.407114,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006943,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.052828,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.507234,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068894,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.263933,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.991257,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.512644,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.470714,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.74841,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.765908,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045608,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "a27d2f82514e1cee900aa5292cdbd6ef40bd65ea",
          "message": "Add stable KP diagnostic codes to every error path (#1534)\n\nA diagnostic's message string was its only identity: a tool — an AI agent,\na CI gate, an editor — had to substring-match prose that is free to be\nreworded, and some paths leaked raw Zig error names straight to the user\n(`read error: error.UnexpectedChar`). This is the keystone of the machine\nlegibility campaign (#1503): give every user-facing diagnostic a stable\n`KP`-prefixed handle so the code is the contract and the message is free to\nimprove.\n\nIntroduce `src/diagnostics.zig`: a comptime registry binding each diagnostic\nto a code (the enum ordinal is the KP number), a message template, a prose\nexplanation for a later `kaappi explain`, and a severity. A comptime gate\nfails the build on any duplicate, missing, or empty-field entry — the KEP's\nregistry-integrity check, enforced at build time. Text output gains the code\n(`error[KP3001]: ...`), keeping the stage word for the human reader.\n\nErrors reach the reporting layer two ways. Native `VMError`s are coded from\nthe escaping error; errors raised as objects (division by zero, `error`,\n`raise`) carry their code on a new `ErrorObject.code` field, stamped at the\nraise site and lifted to the reporter by noteUncaughtException — the robust\nrepresentation the Phase-4 `error-object-code` accessor will reuse. High-\ntraffic diagnostics are coded first; the long tail shows the generic KP3000\nuncaught-exception until migrated, and no path ever regresses to leaking a\nZig name. `error_type` and the R7RS error accessors are untouched.\n\nDesign record: KEP-0005. Policy and contributor guide: docs/dev/diagnostics.md.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-14T11:56:54Z",
          "tree_id": "3e63454ead3f03bb40b6eaf22f5a6bf02fec50bb",
          "url": "https://github.com/kaappi/kaappi/commit/a27d2f82514e1cee900aa5292cdbd6ef40bd65ea"
        },
        "date": 1784031842808,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.055521,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.780565,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.923699,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.435788,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006729,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.052878,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.517498,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.067824,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.257953,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.987178,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.514474,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.479239,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.740906,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.845601,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.048505,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "328ca95ea31a2231a5fdd29bf22520448495e251",
          "message": "Add KEP-0003 acceptance-gate classification worksheet (#1474) (#1538)\n\nThe gate is a \"reading, not an argument\" of the #1472 §6 dataset, which\ndoes not exist yet (only the P3 eyeball benchmark landed in #1535). Build\nthe reading instrument now, from the frozen keps §5-§6 protocol, so that\nwhen the gate campaign produces the CSV the classification is pure\nfill-in-the-blanks with no room for post-hoc judgement: every gate and\nsupporting cell enumerated, each rule wired to its exact cells and CI\nbound, per-machine precedence and two-machine agreement as a mechanical\nprocedure. All data slots are empty placeholders; no numbers fabricated.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-14T18:45:31+05:30",
          "tree_id": "ef88ff92af504dac94bd1da5667615aa0d773147",
          "url": "https://github.com/kaappi/kaappi/commit/328ca95ea31a2231a5fdd29bf22520448495e251"
        },
        "date": 1784036291524,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.062417,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.766881,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.92,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.458791,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006902,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.053479,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.510707,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068104,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.262302,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.983827,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.529656,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.474136,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.754821,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.764479,
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
          "id": "2893437433dbcfc754488624b7a64ed727bc6778",
          "message": "Add regression test for nested-wait dirty-snapshot hazard (#1490) (#1536)\n\nIssue #1490 is the same dirty-snapshot dispatch corruption as #1487, already\nfixed by the generic `driving` guard in #1521 (which merged ~10h after #1490\nwas filed). It reaches the hazard through a distinct trigger, though:\nreactor-timer theft. A spawned fiber's blocking wait, nested inside another\nfiber's live `thread-sleep!` drive, parks in the reactor bounded by the\nnearest timer in the shared heap -- which is the *ancestor's* own sleep\ntimer. That timer pop flips the ancestor `.suspended`; without the `driving`\nguard the nested drive would then re-dispatch the ancestor from its stale,\nmid-native-call snapshot, surfacing as `panic: integer overflow` in\ninvokeEscape.\n\nThe existing regression test (mutex-nested-dispatch-dirty-snapshot-1487.scm)\nonly exercises the mutex-unlock wake trigger, and the local channel wait\npaths #1490 names had no coverage. This adds an end-to-end test over all four\nblocking primitives (channel-receive, full-bounded channel-send, mutex-lock!,\ncondition-variable wait), each nested under a thread-sleep! loop -- also\ncompleting the condvar/channel end-to-end repro deliberately deferred in\n#1521's review.\n\nVerified via A/B (scheduleForDispatch -> scheduleImpl(false)): every scenario\ncrashes without the guard and passes with it.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-14T13:30:55Z",
          "tree_id": "70bc0e816efeb6aad7bbddf90f2911922975ff1b",
          "url": "https://github.com/kaappi/kaappi/commit/2893437433dbcfc754488624b7a64ed727bc6778"
        },
        "date": 1784037340718,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.2898,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.89474,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.911326,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.428838,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006369,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.054086,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.503355,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069699,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.385955,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.955635,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.589243,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.434188,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.881448,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.467774,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045488,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "b52f873f85edaa19e87d0c59292038e32859dbb1",
          "message": "Add --diagnostics=json structured diagnostic output (#1505) (#1537)\n\nAgents driving kaappi have had to scrape human-oriented error text. This\nexposes every read, expand, compile, and runtime diagnostic as JSON Lines\non stderr under `--diagnostics=json`, so tools can match on structure\ninstead of prose. Text mode stays the default and is unchanged.\n\nRather than invent a schema, each line is an LSP `Diagnostic` — the exact\nshape the language server already publishes. The serializer now lives in\none place (src/lsp_diagnostic.zig) that both the CLI reporting funnel and\nkaappi_lsp.zig call, so the two cannot drift; the LSP gains KP codes as a\nresult. `code` comes from the diagnostics registry (#1504), and a \"did you\nmean\" fix maps to `data.suggestions` with kind/replacement, carried\nstructurally on the VM so the JSON message stays clean.\n\nPositions are the LSP-standard zero-based coordinates and are points until\nspan tracking lands (#1506). The text snippet and backtrace are suppressed\nin JSON mode so stderr stays one parseable object per line.\n\nPart of #1503.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-14T14:29:22Z",
          "tree_id": "cfcd9b02a23e9237c26261240ece1a4f90ab32aa",
          "url": "https://github.com/kaappi/kaappi/commit/b52f873f85edaa19e87d0c59292038e32859dbb1"
        },
        "date": 1784041041243,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.055518,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 10.132201,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.930885,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.42145,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00675,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.052808,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.509853,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068161,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.222816,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.980654,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.702139,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.475842,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.768253,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.816284,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045877,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "608b70f765e3c56da4f893fb4499d12efca153ac",
          "message": "Box mutable captured variables in the native backend (#1497) (#1539)\n\nThe LLVM native closure tiers copied captured variables by value into the\n%upvalues array at closure-creation time. This diverged from the interpreter's\nby-location closure semantics whenever a captured binding was mutated after\ncapture (#1422), and forced the tiers to reject any closure body containing a\nset! or internal define — a whole class of counter/accumulator closures fell\nback to the interpreter.\n\nApply classic assignment conversion: a binding that is both captured by a\nnested lambda and mutated (by set!) is represented as a heap box. Closures\ncapture the box pointer by value; reads/writes go through kaappi_box_ref /\nkaappi_box_set. Because the pointer is immutable but the contents are shared,\na set! through any closure over the binding is visible to all of them, matching\nthe VM exactly. Only captured-and-mutated bindings are boxed; everything else\nkeeps the by-value fast path. A box is a pair (value . '()), so the GC needs no\nnew heap type.\n\nTwo latent bugs surfaced and are fixed:\n\n- bindParamsAsGlobals republished captures by value, so a boxed variable\n  captured by a lambda that itself falls back to eval (e.g. a variadic inner\n  lambda) reintroduced the #1422 snapshot. It now aborts native compilation of\n  the enclosing frame so the interpreter handles the whole thing.\n- emitLambdaFunction registered native_fns before body emission (for self-tail\n  resolution) without rolling back on failure, which could leave a call site\n  emitting a direct call to a @lambda_N that was never defined.\n\nBoxed frames disable the self-tail-call loop and lower non-tail so box roots\npop at a single ret. Verified under -Dgc-stress and KAAPPI_GC_THRESHOLD=1.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-14T20:28:18+05:30",
          "tree_id": "0fb199943056f0110116db5c5331672319ff525b",
          "url": "https://github.com/kaappi/kaappi/commit/608b70f765e3c56da4f893fb4499d12efca153ac"
        },
        "date": 1784042984521,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.070574,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 10.510741,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.974172,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.421811,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006862,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.052983,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.513876,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068294,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.278317,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.985839,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.513335,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.485189,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.751981,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.800219,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045454,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "708a660b77b0d616de93be02f421b8a823d7219c",
          "message": "Batch fd reads in readOneByte (#1460) (#1542)\n\nreadOneByte issued one read(2) syscall per byte on fd-backed ports, so\nevery byte-at-a-time consumer (read-bytevector, read-string, read-char,\nread-line, read-u8) paid k syscalls to read k bytes from a file or\nsocket.\n\nThe fd path now reads up to read_chunk_size (4096) bytes in a single\nread(2), returns the first byte, and stashes the remainder in the port's\nexisting read_buf. The consumption drain at the top of readOneByte hands\nthose out on subsequent calls, so a run of byte reads costs one syscall\nper burst instead of one per byte.\n\nThe batched leftovers compose with the existing park/stash machinery\nbecause read_buf is always empty at the fd path: every park point sits\npast the peek/read_buf/string drains, so a caller that parks later does\nso on a subsequent call after this buffer drains, where stashPartialRead\nprepends onto an empty read_buf. The fresh slice is allocated exactly\nn-1 bytes so rb.len == read_buf_len and the \"last read_buf_len bytes\"\nconsumption cursor starts at 0. read(2) short-returns whatever is\navailable, so a 1-byte interactive read never blocks to fill a chunk,\nand an n==1 read allocates nothing (byte-identical to the old path).\nreadDatumFn's incremental-parse loop already batched; it now shares the\nread_chunk_size constant.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-14T22:30:46+05:30",
          "tree_id": "db54086b4a64f2b942ce3d966dabd5a9b7d8e66a",
          "url": "https://github.com/kaappi/kaappi/commit/708a660b77b0d616de93be02f421b8a823d7219c"
        },
        "date": 1784050013895,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.289928,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.438313,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.955238,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.478035,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006683,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.054589,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.516532,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070669,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.637284,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 2.110342,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.581259,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.438559,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.832305,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.672147,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044301,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "ae167d1449fa80ff29df4c678776ead96d13cb9d",
          "message": "Run the #809 300-capture stress test again (#1541)\n\nThe 300-variable-capture regression test for the u8→u16 upvalue_count\nwidening was skipped under -Dgc-stress=true because compiling that\nprogram once peaked ~7 GB RSS and OOM-killed the stress suite.\n\nThat blow-up was not inherent to the test: markValue reallocated its\nmark worklist on every call, and the testing allocator's metadata\nretention amplified the churn. #1436 made the worklist persistent, so\nthe peak is now a few tens of MB (verified: ~32 MB for this test in\nisolation under gc-stress). The skip outlived its cause — remove it so\nthe >255-upvalue boundary is covered under stress again.\n\nFixes #1451\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-14T22:30:26+05:30",
          "tree_id": "34a09af37dbb749bda9298c7f42b74932722699a",
          "url": "https://github.com/kaappi/kaappi/commit/ae167d1449fa80ff29df4c678776ead96d13cb9d"
        },
        "date": 1784050069325,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.319249,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.190716,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.935661,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.51737,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006452,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.054913,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.519199,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.071007,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.719209,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.989005,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.572917,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.427995,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.827404,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.639707,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045152,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "63079083ff2d5d36e7f3d7e6c394a85518338832",
          "message": "Unskip eval tail-call test under gc-stress via frame-depth proxy (#1540)\n\nThe #1253 regression test detected non-tail-called `eval` by forcing a\nframe-limit overflow, which is only decisive past MAX_FRAME_LIMIT (32768)\niterations. Every iteration recompiles the expression through `eval`, so\nunder -Dgc-stress=true that is millions of full collections — hours — and\nthe test was unconditionally skipped there (#1452), leaving no bound on\nwhen it might become practical again.\n\nOverflow-based detection is inherently unaffordable under stress: it needs\n>32768 compile-heavy iterations no matter how the count is tuned. Instead,\nobserve the guarded property (\"constant frame depth\") directly. A test-only\nobserver native records vm.frame_count at the base case of the recursion;\nrunning the loop at two very different iteration counts, a tail-called eval\nreuses its caller's frame so both depths match, while a non-tail-called eval\nwould push a frame per iteration and diverge. This is decisive with a few\nhundred iterations (910ms under gc-stress) and now runs on every build.\n\nVerified decisive by injecting the regression (eval in non-tail position):\ndepth grows 202 -> 2002 across the two counts and the test fails.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-14T22:30:08+05:30",
          "tree_id": "9a3cec2046f7a0eb1928590fffa928fe403c77dd",
          "url": "https://github.com/kaappi/kaappi/commit/63079083ff2d5d36e7f3d7e6c394a85518338832"
        },
        "date": 1784050117185,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.298789,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.477254,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.973109,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.490982,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006524,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.054323,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.518938,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.071087,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.69996,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.983621,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.598785,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.440946,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.836982,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.657527,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045203,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "efc976e3bcff31eb041f5636d16bee9f93b4b1b4",
          "message": "Inline fixnum fast paths for hot native primitives (#1493) (#1544)\n\nInlined primitives in the LLVM backend emit a cross-module call per\noperation (`kaappi_fixnum_add`, `kaappi_car`, …) into `libkaappi_rt.a`.\nPlain -O2 cannot inline across that archive boundary, so trivial\narithmetic in a hot loop pays a real call every iteration.\n\nThe issue proposed LTO as the primary fix, but it is unavailable on the\nprimary dev platform: Zig 0.16 cannot use LLD for Mach-O (\"using LLD to\nlink macho files is unsupported\") and -flto requires LLD, so both the\nruntime lib build and the native link fail with -flto on macOS. It works\nonly when targeting Linux. Rather than ship a per-platform-inconsistent\noptimization, take the issue's sanctioned alternative and emit the hottest\nprimitives as inline IR, which is portable across every target (it is just\ntext the emitter writes) and needs no cross-module inlining.\n\n`+ - * < = null?` now lower to inline fixnum fast paths with a runtime\nslow-path fallback (non-fixnum operands, or overflow out of the i48 range →\nbignum). The fast paths touch only the NaN-boxed Value bits, whose encoding\nis pulled from types.zig at emitter comptime (no hand-transcribed magic\nnumbers). car/cdr/cons stay as direct specialized calls: Pair/Object are\nauto-layout structs whose field offsets Zig does not guarantee, and cons\nallocates regardless.\n\nThe larger win is eliding the shadow-stack rooting the inline path emitted\naround every operation: the push_root/pop_roots pair only exists to keep\nthe first operand alive across the second's evaluation, which is pointless\nwhen the second operand cannot allocate. `nodeMayAllocate` conservatively\ndetects that (immediate constants and variable references never collect),\ndropping both calls for the common `(op var const)` / `(op var var)`\nshapes. fib(38) runs 3.30x faster than -O2-only (1.45s → 0.44s); alloc-\nbound loops are unchanged, as expected.\n\nVerified: e2e 27/27 (new native-inline-primitives.scm diffs overflow,\nnon-fixnum, and sign-extended-negative paths against the interpreter),\nunit suite 897/897, and native binaries stay correct under a forced-\ncollection KAAPPI_GC_THRESHOLD=1 run including the rooting-kept case.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-14T22:31:13+05:30",
          "tree_id": "f0f988b4cea64771d6ba1dacd172ac8bbdc959f4",
          "url": "https://github.com/kaappi/kaappi/commit/efc976e3bcff31eb041f5636d16bee9f93b4b1b4"
        },
        "date": 1784050921015,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.806974,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.30059,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.714514,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.434442,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.005238,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.041006,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.396068,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.052777,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.603374,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.540389,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.170268,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.371557,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.344787,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.423557,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.03757,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "91d63f359ee76220ebfd2e00208825ce69265878",
          "message": "Abandon cross-heap mutexes on fiber death (#1458) (#1545)\n\nabandonFiberMutexes found a dying fiber's held mutexes by scanning that\nfiber's own GC heap. A mutex shared across OS threads via a top-level\nglobal lives in whichever heap allocated it — typically the parent's, not\nthe dying child's — so the scan never found it: the mutex stayed\n'not-abandoned, m.owner dangled at the (soon-freed) dead child fiber, and\na cross-thread mutex-lock! hung or raised the generic deadlock error\ninstead of abandoned-mutex-exception.\n\nTrack held mutexes on the fiber itself (a per-fiber owned_mutexes list\nmaintained by mutex-lock!) so abandonment no longer depends on which heap\nowns the mutex object. The list is pruned-on-lock and deduped rather than\nmaintained at unlock, which bounds it without a cross-thread list-mutation\nrace; the defensive locked/owner guard still skips stale entries. It is\nonly ever mutated and walked on the fiber's own thread. thread-terminate!\nabandons a local fiber's mutexes in place and lets an OS-thread target\nself-abandon when it observes the terminate flag. markFiberState keeps\nheld mutexes alive (foreign ones are skipped by markValue's owner check);\nfreeObject frees the list.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-14T22:31:37+05:30",
          "tree_id": "94d7b13887993f361cfa57a81bb9c0149d0f1abe",
          "url": "https://github.com/kaappi/kaappi/commit/91d63f359ee76220ebfd2e00208825ce69265878"
        },
        "date": 1784050928394,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.422464,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.335765,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.89785,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.405041,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006391,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.053396,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.503517,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069878,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.430537,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.941585,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.587769,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.439019,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.832086,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.547017,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044269,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "df1a3524a429763708133b31d724ec3fa9309f90",
          "message": "Add `kaappi explain <code>` diagnostic documentation command (#1543)\n\nWith stable KP codes, each diagnostic can carry real documentation. Like\n`rustc --explain`, the binary becomes its own diagnostic reference —\noffline, version-matched, and identical for a human reading prose and an\nagent parsing JSON. Everything is read from the one registry in\ndiagnostics.zig, so the command, the --diagnostics=json stream, and the\ngenerated website page can never disagree about what a code means.\n\n`kaappi explain KP3001` prints the entry — meaning, a minimal triggering\nexample, and (woven into the prose) the fix. The code argument accepts the\nKP number in any case, a bare number, or the kebab name. `--json` emits one\nJSON object; `--all` the full text reference; `--all --json` a JSON array,\nthe drift-proof source a docs generator consumes.\n\nRegistry: add an `example` field to every entry (the \"minimal example that\ntriggers it\"), enforced non-empty by the same comptime gate and its runtime\nmirror. 22 of 26 examples are literal one-liners verified to emit their own\ncode; the four that cannot be inlined are representative and say so. The new\n`tests/scheme/errors/explain.sh` reruns every runnable example back through\n--diagnostics=json and asserts it still triggers its documented code, so a\ndrifting example fails CI rather than a user.\n\n`explain` is a pure query over the static registry, so main dispatches it\nbefore any VM/GC/library setup exists. The --json string escaper is shared\nwith --diagnostics=json (lsp_diagnostic.writeJsonString) so both machine\nsurfaces escape identically. tools/gen_diagnostics_reference.py renders the\nkaappi-lang.org page from `explain --all --json`; the page itself lands in\nthe docs repo as a follow-up.\n\nPart of #1503. Closes #1507.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-14T17:49:43Z",
          "tree_id": "76f8f486be0e78160b6ba16d0696617e677d6bc0",
          "url": "https://github.com/kaappi/kaappi/commit/df1a3524a429763708133b31d724ec3fa9309f90"
        },
        "date": 1784052860968,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.399569,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.535401,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.924517,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.433263,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00653,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.054989,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.499243,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068435,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.478838,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.95212,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.597947,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.444508,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.827212,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.69382,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.046381,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "d014dc9c75b6e2b6b45a03e6751817209477545c",
          "message": "Add dependency analysis to parallel-issues skill (#1547)\n\nIssues that depend on each other (via \"depends on #NNN\", \"blocked by\",\nGitHub linked-issues, etc.) shouldn't land in the same or an earlier\nbatch set than what they depend on.\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-14T23:52:08+05:30",
          "tree_id": "dd98f9f193ed6d8eb4b87a25c64880ff25bc350a",
          "url": "https://github.com/kaappi/kaappi/commit/d014dc9c75b6e2b6b45a03e6751817209477545c"
        },
        "date": 1784054840978,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 2.362312,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.957805,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.472646,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.475606,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004038,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.029277,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.268208,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.03426,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 1.91218,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.975685,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 0.846637,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.302072,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 0.914438,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.149521,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.025189,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "b5ce33d76e20e56f1251d84c74c9bf940976f537",
          "message": "KEP-0002 Phase 7 gate-campaign harness + lever D (#1472) (#1546)\n\n* Add KEP-0002 Phase 7 parallel-map gate-campaign harness (#1472)\n\nThe gate that decides KEP-0003 (kaappi#1474) reads the copy+reassembly\noverhead `share` of a parallel-map section, per the frozen protocol at\nkeps research/benchmarks/README.md. This lands the runnable harness for\nthat measurement (levers none/C; lever D follows in a later commit).\n\n- src/channel_instrument.zig: parent-side T_submit_copy / T_result_copy /\n  T_reassembly counters, the runtime elision-lever flag, and the peak-\n  envelope gauge, all behind -Dchannel-instrument (compiled out of the\n  shipped default per protocol §3; also keeps clock_gettime out of WASM).\n- shared_channel.zig: time the real send/receive copy path; lever C skips\n  the envelope heap for immediate payloads (Envelope.gc is now optional).\n- primitives_parallel.zig: %chan-instr-* / %elision-lever-set! harness\n  hooks, registered only in the instrument build so the shipped\n  (kaappi fibers) is unchanged, and tagged .kaappi_fibers (not .internal,\n  which is removed from globals after bootstrap) so they persist.\n- benchmarks/gate/: the six workloads + controls + serial baselines\n  (gate-harness.scm), the Kalibera-Jones driver emitting the §6 CSV\n  (run-gate.py), and README.md documenting the protocol mapping and the\n  pre-freeze findings (the #1489 hang, records not crossing channels,\n  matmul compute cost, an exception-crossing panic).\n\nVerified: unit suite green on normal and -Dchannel-instrument=true builds\n(new lever-C regression test + internal-spec drift guard); channel/fiber/\nparallel Scheme smoke tests green; local pilot on macOS aarch64 produced a\n§6 CSV with well-differentiated share values.\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>\n\n* Implement KEP-0002 Phase 7 lever D in the real channel path (#1472)\n\nLever D of the elision matrix (protocol §2): a refcounted immutable\nside-heap for large bytevectors, so a payload crossing a channel is\nsnapshotted once and shared by refcount instead of re-copied on every\nhop. The gate's C+D cells (kaappi#1474) require it.\n\n- src/shared_buffer.zig: SharedBuffer, the KEP-0002/0003 second\n  shared_object (after SharedChannel) -- a refcounted immutable byte\n  buffer outside every GC heap.\n- types.Bytevector.shared: opaque backing pointer; when set, data is\n  borrowed from a SharedBuffer and the bytevector holds one reference.\n- gc_deep_copy: under lever C+D the send side (envelope build) snapshots a\n  bytevector >= 4 KiB into a fresh SharedBuffer; the receive side (and any\n  re-copy of an already-backed bytevector) aliases by refcount -- zero\n  byte copy. Comptime-pruned in the shipped build.\n- memory.allocBytevectorShared / unshareBytevector: the backed allocator\n  and copy-on-write (a mutator privatizes borrowed bytes and drops the\n  reference before writing). COW wired into bytevector-u8-set!,\n  bytevector-copy!, read-bytevector!.\n- gc_collect: freeObject releases the SharedBuffer reference (freeing the\n  buffer at zero) instead of freeing borrowed bytes; objectSize counts\n  only the struct for a backed bytevector.\n- shared_channel.Envelope.create signals the send-side D mode around the\n  copy.\n\nScope (bytevectors only; no plain-source promotion for fan-out; strings\ndeferred) and rationale are in benchmarks/gate/README.md -- neither\naffects the gate classification (the one affected workload, FO-DIGEST\nfan-out, is compute-dominated).\n\nVerified: new lever-D unit test (backing / alias / copy-on-write /\nrefcount lifecycle) green on the instrument build and under\n-Dgc-stress=true; full unit suite green on normal and instrument builds;\nend-to-end pool test delivers correct bytes across a real thread and COW\nmutates safely; behaviorally, ip-band at C+D drops parent result-copy\ntime ~10x and peak envelope bytes ~40x vs lever none.\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-14T23:50:03+05:30",
          "tree_id": "da4adb009fcf71fc44b9434adebc9dbd43042620",
          "url": "https://github.com/kaappi/kaappi/commit/b5ce33d76e20e56f1251d84c74c9bf940976f537"
        },
        "date": 1784054869136,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 2.484516,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.040462,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.494705,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.545736,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004927,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032103,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.282205,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.041367,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.194208,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.07395,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 0.934043,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.309345,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.04881,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.651952,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.027993,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "b6d349c0cc7207eca648f08588904a593a8712c2",
          "message": "Fix lost cross-thread wakeup in shared channel send/receive (#1489) (#1548)\n\nA fiber receiving on a promoted channel could park permanently even\nthough a live peer thread later sent. A local sibling's channel-send +\nchannel-receive, run during the receiver's SharedChannelPoll drive,\nconsumed the receiver's one-shot recv_waiters notifier registration, and\nthe fall-through check (peekReady) re-derived readiness WITHOUT\nre-registering. The later remote send found recv_waiters empty and rang\nnothing; the parked fiber's shared_waiters entry kept hasRunnableFibers()\ntrue, so the deadlock detector stayed suppressed and the process hung\nforever.\n\nRe-derive readiness after the drive THROUGH receive() itself, not a bare\npeekReady(): receive() re-registers the notifier under the channel lock\nwhen it returns .would_park, so the park is always armed (and returns the\nvalue/eof straight away if the drive produced one). channelSendShared had\nthe identical latent bug for bounded channels -- a sibling receive+send\nduring the drive consuming its send_waiters registration -- fixed the same\nway via send() (the full path enqueues nothing, so there is no\ndouble-send).\n\nRegression test tests/scheme/smoke/fiber-channel-lost-wakeup-1489.scm is\nthe issue's repro, bounded by a receive timeout so a regression FAILs\nrather than hangs (which run-all.sh would SKIP): it fails pre-fix (the\nreceiver is never woken and the timer fires) and passes post-fix.\n\nVerified: repro 20/20 no hangs; the gate-campaign cells that hung ~8% of\nruns are now 90/90 clean; full unit suite green on the normal build and\nunder -Dgc-stress for fiber/channel/scheduler; bounded-channel and\nparallel smoke tests green.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-15T00:55:26+05:30",
          "tree_id": "db77a1108a33c8d26b64bfdfc28f6cf57b1513d4",
          "url": "https://github.com/kaappi/kaappi/commit/b6d349c0cc7207eca648f08588904a593a8712c2"
        },
        "date": 1784058914642,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.460508,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.048332,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.891884,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.464168,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006422,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.054254,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.502708,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069551,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.402909,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.958267,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.616352,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.431513,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.83011,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.858635,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.051373,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "5d6b99e80c15f81a2bd861d0c5226bdddbdc1eb7",
          "message": "KEP-0002 Phase 7 gate: macOS dataset + filled worksheet (#1472, #1474) (#1549)\n\nThe macOS aarch64 reference machine of the KEP-0003 acceptance-gate\ncampaign, collected at commit b6d349c0 (K-J floor 20x10, w=8, both levers,\n920 launches, 0 failures -- the #1489 fix held at scale):\n\n- benchmarks/gate/results/gate-macos-aarch64.csv: the §6 dataset (+ metadata).\n- benchmarks/gate/classify.py: applies the §5 rules mechanically to the\n  CSV(s) -- the \"reading, not an argument\" -- emitting the share tables and\n  per/combined-machine outcomes.\n- benchmarks/gate/run-gate.py: --serial-invocations/--serial-iterations so the\n  non-gating speedup baselines run at reduced counts.\n- docs/dev/kep-0003-acceptance-gate-worksheet.md: filled with the macOS tables,\n  rule evaluations, and outcome.\n\nmacOS reads 4 Between (stays gated): Rule 1 (Racket) fails -- only IP-MAP\nclears the 25% CI-lower bound (at 64 MiB); IP-BAND and IP-MATMUL are\ncompute-bound -- and Rule 2/3 (Erlang/Absent) fail because IP-MAP, FO-TREE,\nFO-SLICE are far above 10%. Lever D barely moves the shares: the high-share\nworkloads are byte-opaque flonum vectors / trees a bytevector side-heap can't\nshare -- the pre-KEP-0003 walk tax.\n\nBecause macOS is Between, the combined two-machine outcome is Between\nregardless of Linux (agreement or disagreement both resolve to Between per\n§5). The Linux x86_64 half is still worth collecting for a published\ntwo-machine dataset (it was not driveable from the collecting session -- no\ndroplet shell); run the same run-gate.py command on an x86_64 >=8-core box at\nb6d349c0 and feed its CSV to classify.py alongside this one.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-15T05:43:58+05:30",
          "tree_id": "a3050a1c8bbd269afda1a0e6ca9ed4be60f07a91",
          "url": "https://github.com/kaappi/kaappi/commit/5d6b99e80c15f81a2bd861d0c5226bdddbdc1eb7"
        },
        "date": 1784075732060,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.451313,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.245255,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.914158,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.471152,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006425,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.054065,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.504156,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070031,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.386996,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 2.00325,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.596768,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.434625,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.886565,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.715828,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045503,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "5e93ee1258175a41c9feb3498540b3128891ff19",
          "message": "Ship envelope elision lever C (immediate fast path) as the default (#1472) (#1550)\n\nThe KEP-0002 Phase 7 P3 micro-benchmark decided lever C — immediate\nmessages skip the per-message envelope heap — ships: it clears the\npre-registered \"immediates >= 2x lever A on fixnums\" bar by an order of\nmagnitude (measured 28x ReleaseFast / 108x ReleaseSafe), and the KEP-0002\nUQ-1 amendment recorded C as ship. Until now the fast path only ran under\n-Dchannel-instrument as the gate lever `c`; production sends still built a\nfull private mini-heap for every fixnum/boolean/char/flonum/nil message.\n\nMake the immediate elision unconditional in the shipped build. It is\nprovably transparent: deepCopy of a non-pointer returns it unchanged\n(gc_deep_copy.zig, `if (!isPointer) return src`), so the full path only\never built an empty heap and stored the same value back — the fast path\ncarries that value inline and skips the GC struct + ~8 KiB root buffer.\nreceive() and deinit() already handle the null-heap envelope.\n\nKeep it lever-selectable under -Dchannel-instrument so the frozen gate\nprotocol's `none` baseline still forces the pre-C full-envelope path and\nstays reproducible; only the shipped (non-instrument) build changes.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-15T06:47:02+05:30",
          "tree_id": "b25ef5b763afeba13bcea3b35c4a03240225d63c",
          "url": "https://github.com/kaappi/kaappi/commit/5e93ee1258175a41c9feb3498540b3128891ff19"
        },
        "date": 1784080187745,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.37258,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.752535,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.936722,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.487064,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006776,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.054918,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.511675,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070385,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.517933,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.955933,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.629986,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.442505,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.979883,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.760123,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045277,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "e806e5568785615f7e6d0f5089f6fd4a6d1b13f1",
          "message": "Cache LLVM eval-fallback compilation per call site (#1494) (#1552)\n\nForms the native backend cannot lower (letrec, cond, case, do, guard,\nquasiquote, named let, and fallback lambdas) are serialized to a source\nstring and run via @kaappi_eval, which re-parses and re-compiles that\nstring on every execution. Inside a loop body or a frequently-called\nnative function — most commonly an inner variadic lambda, which no\nclosure tier accepts and which keeps its enclosing function native —\nthat is a severe, easily-overlooked cliff.\n\nAdd @kaappi_eval_cached: the emitter allocates one global slot per\nfallback call site; the first execution parses and compiles the form\nonce, permanently GC-roots the resulting Function, and stashes it in the\nslot, and every later execution runs the cached Function directly. The\ncompiled bytecode still resolves globals by name at run time, so a\nfallback that first republishes the enclosing frame as globals observes\nthe current values on each execution — behavior is identical to today.\n\nThe cached Function is rooted via extra_roots (which, unlike the LIFO\nshadow stack, holds a program-lifetime root) because the call-site slot\nis a module global the collector never scans. Only the main runtime\nthread touches a slot — the guard precedes both the read and the write —\nso a spawned SRFI-18 thread never caches a Function from a child heap or\nruns a main-heap Function under its own VM. Quoted heap constants stay on\nplain @kaappi_eval; building those once is the separate #1495 change.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-15T06:57:00+05:30",
          "tree_id": "afff88ac6abf20bf0d6bf7fbfd9bb93024ceaf4b",
          "url": "https://github.com/kaappi/kaappi/commit/e806e5568785615f7e6d0f5089f6fd4a6d1b13f1"
        },
        "date": 1784080530225,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.527297,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.171142,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.974894,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.734468,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006326,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.054168,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.509067,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070075,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.424427,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 2.011005,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.581451,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.435266,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.816263,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.716132,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.046214,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "09f083c3b4bed806b6432d577073c61452ef9f46",
          "message": "Index parked fibers by waited-on object for O(1) wakes (#1530) (#1553)\n\nAfter #1525 made fiber dispatch/spawn O(1), the five wake paths\n(wakeWaiters, wakeChannelWaiters, wakeMutexWaiters, wakeOneCondVarWaiter,\nwakeAllCondVarWaiters) still linearly scanned every slot in\n`sched.fibers.items` on each call. On a join-, channel-, or condvar-heavy\nworkload holding thousands of live fibers, each completion/send/close paid\nan O(fiber count) scan — the residual super-linearity #1477 flagged once\ndispatch was already O(1). `wakeWaiters` alone runs on every fiber\ncompletion and scanned all N fibers even with zero joiners, making\nspawn+join O(N^2).\n\nAdd a per-scheduler secondary index `waiter_index` mapping a waited-on\nValue (a fiber to join, a channel, a mutex, a condition variable) to the\nslot indices of the fibers parked on it, so a wake is O(waiters-on-that-\nobject). enrollWaiter feeds it at every local park site; wakeOn is the\nsingle choke point behind all five entry points, with doWake applying the\nper-fiber transition identically on both the index and fallback paths.\n\nDesign points:\n- Store slot indices, not *Fiber. A since-reused or terminated slot is\n  caught by the same validation the ready ring uses at pop (slot still owns\n  its index, still .waiting, still on the key), so a terminated waiter needs\n  no explicit de-index — unlike the pointer-holding shared_waiters registry.\n- The broadcast wakes require a complete index (a \"wake all\" cannot fall\n  back on an empty index the way #1525's lossy ready ring can). Enroll at\n  all nine local park sites; the four shared-channel parks (woken via\n  sweepSharedWaiters) and thread-sleep!'s VOID-keyed timed wait are\n  deliberately excluded, and the mutex/condvar retry spins re-enroll.\n- An enroll allocation failure sets a sticky waiter_index_degraded flag and\n  the wake paths fall back to the exact pre-#1530 scan, so OOM degrades to\n  old behavior instead of a lost-wakeup hang — no per-site park rollback.\n- A tail-check dedup (skip if the list tail is already this slot) bounds the\n  retry spins without a per-fiber flag, which would carry an address-reuse\n  ABA hazard.\n\nSame-machine bench-fibers A/B: spawn+join at 10,000 fibers 18,606 ns ->\n2,309 ns (~8x) and flat across 100/1k/10k instead of super-linear.\n\nAdds six tests_scheduler.zig unit tests (broadcast, hand-off, terminated-\nslot skip, tail-dedup + re-park, join-result hand-off, degraded scan) and\ntests/scheme/smoke/fiber-many-waiters-one-object-1530.scm (500 fibers block\non one channel; close wakes all). Full unit suite, targeted gc-stress on the\nconcurrency tests, and the full Scheme + R7RS suites all green.\n\nhasRunnableFibers and wakeIoWaitersOnFd are left as-is, matching the issue's\nscope: the former early-exits and is O(n) only in the genuine no-progress\ncase, and the latter keys on fd, not waiting_on.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-15T01:32:41Z",
          "tree_id": "62504b0b5aa54df7fcd52d49dedc7328bd79cb3e",
          "url": "https://github.com/kaappi/kaappi/commit/09f083c3b4bed806b6432d577073c61452ef9f46"
        },
        "date": 1784080944473,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.393397,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.805135,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.943831,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.592052,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00746,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.054286,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.513068,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068538,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.52447,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.95959,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.592466,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.433348,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.797703,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.724979,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044637,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "4c8e209b63da89b16fc32cba26b07a044144a747",
          "message": "Thread full source spans through to runtime diagnostics (#1506) (#1557)\n\nReader errors already carried line and column, but compile and runtime\nerrors reported file:line only, and nothing carried end positions.\nStructured diagnostics, precise editor squiggles, and automated fixes\nall need full spans.\n\nTrack (line, col, end_line, end_col) for every datum the reader can key\non heap identity (pairs, vectors) and thread it through the pipeline:\n\n- Reader records a full span per datum in gc.source_spans (was the\n  line-only source_lines), computed in a single scan.\n- IR nodes carry the span (Annotations.span); the compiler emits the\n  start column into the bytecode line table (LineEntry gains col).\n- Runtime errors map the failing instruction offset back to line:col via\n  Function.locForOffset and report file:line:col.\n- Compile errors report the innermost failing form's span through a\n  threadlocal channel, so a nested error points at the inner form (e.g.\n  the (if) in (define (f) (if))), with a full start/end range under\n  --diagnostics=json.\n\nThe .sbc bytecode cache format is bumped to v9 for the new column; a\nversion mismatch makes the loader ignore and recompile stale caches\ncleanly. Runtime debug info carries the start column only — end\npositions stay a reader/compile-time concern, per the acceptance\ncriteria.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-15T09:39:42+05:30",
          "tree_id": "2ef9485be509029b1f158afaf90ab4311115ef49",
          "url": "https://github.com/kaappi/kaappi/commit/4c8e209b63da89b16fc32cba26b07a044144a747"
        },
        "date": 1784090285454,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.339777,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.329826,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.920426,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.459968,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006409,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.054901,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.504753,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.0697,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.437021,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.968079,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.601023,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.43491,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.8664,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.712531,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042947,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "c2de085ae05b10e1a6b7adc004f8c96ab0d49bd7",
          "message": "Build quoted heap constants once via a per-site cache (#1495) (#1556)\n\nQuoted pairs/vectors were emitted as (quote …) strings run through\nkaappi_eval on every execution, re-parsing and re-consing the literal\neach time. This was both a hot-path cliff and a correctness divergence:\nthe interpreter compiles a quote to a single constant-pool entry, so\nevery evaluation of one literal returns the same object, whereas the\nnative backend rebuilt a fresh copy — (eq? (f) (f)) was #f natively but\n#t in the interpreter.\n\nkaappi_quote_cached builds each quoted heap constant once, permanently\nroots it, and memoizes it in a per-call-site global slot; later\nexecutions return the cached object. This is the data analogue of the\n#1494 eval cache (which caches a compiled Function). Per-site slots\nreproduce the interpreter's identity in both directions: one literal\nread twice is eq?, two textually distinct literals are not.\n\nChild SRFI-18 threads build the constant fresh each execution\n(cross-heap safety), the same carve-out as #1494.\n\nCloses #1495.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-15T09:39:20+05:30",
          "tree_id": "cbb7d14193f6cbbfd17ef17e4dcd0a83f820f823",
          "url": "https://github.com/kaappi/kaappi/commit/c2de085ae05b10e1a6b7adc004f8c96ab0d49bd7"
        },
        "date": 1784090469520,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.102104,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.994623,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.936493,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.438595,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00675,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.053029,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.511107,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068243,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.264237,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.994195,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.540385,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.48131,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.751443,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.85062,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.046932,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "8a369b4829afb664127d1d40510624c847236ebe",
          "message": "Lower cond/case/do natively in the LLVM backend (#1564)\n\ncond, case, and do desugar into machinery the emitter already lowers well —\nif-style block/phi chains and a self-branching loop — yet they were routed\nthrough kaappi_eval like any other unlowerable form. That made a plain\n`(define (f n) (cond ...))` serialize the whole function to the interpreter, a\nneedless per-call cliff.\n\nEmit them natively when every sub-form is emittable in the current lexical\nscope, gated by exprNativeEmittable. A form that reaches an unlowerable\nsub-form (a macro use, a passthrough special form, a nested eval-fallback\nform, a lambda, or a => clause) still falls back — at top level as a\nwhole-form eval (correct in the global environment), and inside a native\nlet/lambda body by signalling the enclosing form to abandon native\ncompilation as a unit, so a lexical scope is never split across the\nnative/interpreted boundary (the #827 discipline).\n\nBecause these forms are no longer eval-fallback forms, the closure tiers'\nfree-variable analysis must scope their clauses, or a capture hidden in one\ndegrades to a global lookup; walkSexpr/nodeHasFreeVars/collectNodeFreeVars now\ndescend into cond/case/do with correct binder scoping. The emitter also\nconsults the VM macro table so a macro use inside these forms reaches the\ninterpreter that can expand it.\n\nRejecting lambdas inside do sidesteps its fresh-binding-per-iteration\nsemantics: with no closure able to capture a loop variable, in-place mutable\nallocas are observably equivalent.\n\nVerified: full unit suite, e2e parity (incl. new cond/case/do programs), the\n1857-case Scheme suite, and 110 randomised interp-vs-native programs all pass;\ntail-recursive cond keeps its self-tail-call loop.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-15T12:59:02+05:30",
          "tree_id": "79bcb18ccef5b6009de8bce2c6377ea7a366a648",
          "url": "https://github.com/kaappi/kaappi/commit/8a369b4829afb664127d1d40510624c847236ebe"
        },
        "date": 1784102097796,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 2.48313,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 5.440743,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.49062,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.484527,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004896,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.03202,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.279334,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.041158,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.059399,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.067303,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 0.936405,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.304754,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.053978,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.765834,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.027789,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "5a2acef2006a24341e882901b0bc208347fb91bf",
          "message": "Grow native lambda analysis buffers + loop variadic self-tail-calls (#1498) (#1567)\n\n* Grow native lambda analysis buffers + loop variadic self-tail-calls (#1498)\n\nThe native lambda emitter (src/llvm_emit_lambda.zig) bailed to kaappi_eval\nwhenever a function exceeded a fixed-size stack buffer, and compiled\nself-tail-recursion as a loop only for non-variadic functions. Both were\narbitrary cliffs on otherwise-compilable code.\n\nPart 1 — remove the fixed analysis buffers. The per-function scratch arrays\n([16] params, [64] body nodes, [16] free vars, [17]/[18] name buffers, [32]\nformal names, FreeNameWalk's [64] bound / [16] output, BoxAnalysis's [16]/[17]\nflags) now grow on the emitter's existing arena. The only ceiling left is the\nruntime's real one: a native closure's arity and each upvalue index are u8, so\na function past 255 fixed params or captured upvalues still falls back.\n\nPart 2 — loop variadic self-tail-calls. A self-call in tail position now branches\nback to the body label for variadic functions too, rebuilding the rest list from\nthe args past the fixed arity (reusing the cons idiom) before the branch. The\nrest builder moves to the entry block so the loop does not re-run it.\n\nAlso fixes a pre-existing latent GC bug the loop would hit constantly: the\nvariadic rest list was built in a bare, un-rooted alloca, so a body allocation\nthat did not itself mention the rest list could collect the freshly-consed\nspine (native output diverged from the interpreter under GC pressure). The rest\nslot is now GC-rooted for the frame (frame_box_roots generalized to\nframe_entry_roots) and popped before every ret, including tail-call rets.\n\nTests: new tests_native.zig emit tests for the over-limit cases and the\nvariadic loop; new tests/e2e programs (native-many-params, native-many-captures,\nnative-variadic-tail). zig build test, gc-stress native tests, and\ntests/e2e/run-e2e.sh (35/35) all green.\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>\n\n* ci: raise macos-latest test job timeout to 30 min\n\nThe macOS runner is ~1.5x slower than the Linux ones: unit tests (~6 min) plus\nthe Scheme suites (~11 min) alone take ~17 min, so the job routinely drifts past\nthe default 20-min cap and is cancelled mid-run — a pre-existing flake seen on\nmain, not tied to any one PR. Bump macos-latest/ReleaseSafe to 30 min, matching\nthe timeout already used for the Debug and riscv64 jobs. Applied as an include\nentry that merges the timeout into the existing combination (no extra job).\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>\n\n* ci: set macos timeout via an os-aware expression, not a merged include\n\nThe previous commit added the macOS 30-min cap through a matrix `include` entry\nthat merges into the existing macos-latest/ReleaseSafe combination. Whether such\na merge exposes `timeout` as `matrix.timeout` (vs. being dropped) is a subtle\nmatrix-expansion detail the auto-generated job name did not confirm. Replace it\nwith an explicit `matrix.os == 'macos-latest'` check in the timeout expression,\nwhich is unambiguous and does not depend on include-merge semantics.\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-15T15:42:19+05:30",
          "tree_id": "4851bb46928d76c07f37225544d34bf9d66cebee",
          "url": "https://github.com/kaappi/kaappi/commit/5a2acef2006a24341e882901b0bc208347fb91bf"
        },
        "date": 1784112085116,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.374728,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.821511,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.899459,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.467845,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006345,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.053545,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.507518,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069311,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.463918,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.973989,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.573364,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.432518,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.838532,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.704451,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.04315,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "64d2e5d7c7b76a4fc81dbd1f64b3b2f4a136b060",
          "message": "Add `kaappi doctor` installation and environment self-check (#1513) (#1569)\n\n\"Why doesn't `(import (kaappi json))` work?\" has a fixed set of answers —\nlibrary-path resolution, thottam state, a missing native library, the wrong\nbinary on PATH — that were previously diagnosed by hand. Making the toolchain\ncheck itself lets both new users and agents go from a broken setup to a fix\nusing only documented CLI output, the operational test of the machine-\nlegibility epic (#1503).\n\n`doctor` is a meta-command like `explain` and `test`: it inspects the\nenvironment and runs no user code, so it dispatches before any VM/GC/library\nsetup exists. It reports PASS/WARN/FAIL per check across six groups (binary,\nlibrary search path, package manager, native backend, REPL, FFI), each failure\ncarrying an actionable suggestion, in a human table or one `--json` object.\n\nThe exit code is nonzero only on FAIL. WARN describes a degraded-but-usable\nenvironment (no libraries installed yet, no C compiler) and must not fail\nscripts or CI; the one FAIL is an explicit `KAAPPI_LIB_DIR` that does not\nresolve, an unambiguous misconfiguration. When a compiler and `libkaappi_rt.a`\nare both found, a smoke link against the archive proves the native toolchain\nend to end — run in a private 0700 temp dir, and skipped under the test binary\nso unit tests stay hermetic.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-15T17:17:41+05:30",
          "tree_id": "3fe0bd1dd1724c2173013e7284569ce186d5f1d0",
          "url": "https://github.com/kaappi/kaappi/commit/64d2e5d7c7b76a4fc81dbd1f64b3b2f4a136b060"
        },
        "date": 1784117780260,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.374633,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.941094,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.894415,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.424641,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006302,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.055397,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.495753,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069199,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.509009,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.937368,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.587685,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.433354,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.965359,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.682319,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042603,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "9bb1b63fefab216265286c17e4765d379d527f46",
          "message": "Add `kaappi features` capability-discovery subcommand (#1517) (#1570)\n\n`kaappi features [--json]` answers an agent's first question -- \"what am I\nworking with?\" -- at the CLI boundary, the way KEP-0004 already answers it\ninside Scheme via cond-expand. It reports version + git build id, target\ntriple, build mode, the compiled-in subsystems, built-in vs portable SRFIs,\ninitial VM/GC limits, and whether --sandbox is available. JSON is the primary\ninterface; a human-readable table is the secondary.\n\nThe point is that this output can never drift from the rest of the toolchain,\nbecause every field is derived, never re-typed:\n\n- features = types.platform_features, the exact table cond-expand and R7RS\n  (features) resolve against (a unit test asserts equality; features.sh proves\n  the CLI output equals the runtime (features) procedure).\n- built-in SRFIs come from the library registry -- the srfi_* tags of\n  primitives.Lib plus the new library.extra_std_libraries (which also de-dups\n  the srfi.9 / scheme.case-lambda registration shared by both registrars).\n- portable SRFIs are generated at build time by scanning lib/srfi/*.sld, so a\n  new .sld updates the output automatically.\n- build id is a best-effort git short hash (+ -dirty), \"unknown\" on failure.\n\nDispatched before VM setup (like explain/test), native-only. Wires the new\nsubcommand into --help, the bash/zsh/fish completions, README, and CLAUDE.md;\ndocuments it in docs/dev/features.md.\n\nPart of the machine-legibility epic #1503.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-15T12:24:22Z",
          "tree_id": "c5994c3a0a0a11d07cb95157f4571138bd51a637",
          "url": "https://github.com/kaappi/kaappi/commit/9bb1b63fefab216265286c17e4765d379d527f46"
        },
        "date": 1784120217819,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.314863,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.844526,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.893171,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.426566,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006425,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.053468,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.507451,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068782,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.456172,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.959031,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.580156,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.428406,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.810959,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.703531,
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
          "id": "e95f6b51812e94eae19f5a1b98de85b7a3b685f4",
          "message": "Guaranteed native mutual tail calls via tailcc + musttail (#1499) (#1572)\n\nSelf-tail-recursion in the LLVM backend was already constant-stack (an\narg-overwrite branch loop), but a tail call to *another* function was not:\nthe uniform entry reads its parameters from a caller-frame `%args` array,\nand a real tail call tears that frame down, so the callee would read freed\nstack. `even?`/`odd?`-style mutual recursion therefore grew the stack and\neventually overflowed. Guaranteed TCO needs arguments passed by value, not\nvia a pointer into the caller's frame — an ABI change.\n\nA fixed-arity, non-variadic, non-boxed named function (arity <= 8) now emits\ntwo LLVM functions: a `tailcc` register-argument fast entry holding the body\n(it copies the registers into a local `%args` array, so the existing body\nmachinery is reused unchanged), and an `internal` uniform-ABI trampoline for\nindirect dispatch. Direct tail calls between fast entries emit `musttail call\ntailcc` — LLVM-guaranteed constant stack (`tailcc` relaxes musttail's\nprototype-match rule, so different-arity mutual calls are legal). Self-\nrecursion keeps its loop; variadic/boxed/over-arity/closure functions keep the\nuniform entry unchanged.\n\nForward references (a callee defined later) resolve through a syntactic\npre-scan that reserves stable `@r{i}.fast` names for single-definition\ntop-level functions; a finalization stub covers any reserved name that falls\nback to the interpreter, so every musttail target links. A reference to a\nreserved name counts as a global in free-variable analysis, so the caller\nstill compiles natively.\n\n`musttail` is gated (`mustTailSafe`) on being in a fast entry, in tail\nposition, and outside any rooted `let`, so it never strands shadow-stack\nroots. The whole feature is gated per target on aarch64/x86_64, whose LLVM\nbackends support tailcc/musttail; other hosts keep the prior uniform ABI.\n\nVerified: 50M-deep mutual recursion runs native in flat ~3 MB RSS (would\notherwise overflow); GC-safe under forced collection; full unit suite and\n36/36 e2e programs green, incl. a new native-mutual-tail e2e whose\ninterpreter diff doubles as the constant-stack regression check.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-15T19:48:43+05:30",
          "tree_id": "b36f7ffa43c838d4c6fde4e11402061af20b8569",
          "url": "https://github.com/kaappi/kaappi/commit/e95f6b51812e94eae19f5a1b98de85b7a3b685f4"
        },
        "date": 1784127018206,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.671164,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.889918,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.881979,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.15441,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006686,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.051003,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.461468,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.065116,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.477426,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.775696,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.461,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.40386,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.913235,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.913307,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.041249,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "ebd9235a4588a8a473f776aa33de20991899a63d",
          "message": "Bound fuzz generator gates by instruction count on emulated targets (#1573) (#1574)\n\nThe riscv64-test CI job cross-compiles the unit-test binary to riscv64-linux\nand runs it under QEMU user-mode (~10-30x slower than native). The fuzz\ngenerator \"programs evaluate without error\" gates in tests_fuzz.zig bound each\ngenerated program by a 100 ms wall clock, so under emulation a correct-but-slow\nprogram blows the deadline, lands in the .scheme_error bucket, and pushes the\npass rate below the 90% gate -- a spurious failure that needs a manual rerun\nand, while it flakes, nearly doubles the job's wall time.\n\nThis is the same wall-clock-vs-slow-execution class already fixed for gc-stress\n(#1447/#1449), where the gates bound by instruction count instead -- a\nspeed-independent measure identical no matter how fast each instruction runs.\nThat treatment was never extended to the emulated riscv64 path.\n\nDetect a cross-compiled target in build.zig (resolved target arch/os != host)\nand expose it as build_options.emulated_target, then fold it into the existing\ngc-stress gate: speed_independent = gc_stress or emulated_target now drives both\nthe loose 120 s wall-clock backstop and the 2M-instruction bound. The 2M budget\nis reused unchanged (it clears the largest correct generator program by ~50x).\nemulated_target is consumed only by tests_fuzz.zig; the shipped binary is\nunaffected. Skipping was the alternative, but instruction-count bounding keeps\nthe generator-correctness coverage on the emulated path.\n\nAdds a regression test pinning the invariant: under gc-stress or emulation the\nbound is instruction-count (limit set, deadline loosened); on native builds the\ntight 100 ms deadline and no instruction cap are retained. Without the\nemulated-target half it fails on the riscv64 CI job instead of the gates\nflaking silently.\n\nVerified: native 1037/1037; gc-stress gates green; and a genuinely\ncross-compiled x86_64-macos build under Rosetta (emulated_target=true) runs all\nthree generator gates plus the differential oracle green (12/12) under the\ninstruction-count bound.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-15T20:59:56+05:30",
          "tree_id": "874e80307c4eb4c5bdae8f795219bf77b6e926d6",
          "url": "https://github.com/kaappi/kaappi/commit/ebd9235a4588a8a473f776aa33de20991899a63d"
        },
        "date": 1784131268874,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.314645,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.364966,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.938721,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.450346,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006465,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.054231,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.512432,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068736,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.454546,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.986484,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.566969,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.433295,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.80524,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.723125,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044285,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "807fd64ac9c6e38d4e9d492a0117a8958a8d3a90",
          "message": "Add `kaappi fmt` canonical comment-preserving formatter (#1518) (#1571)\n\nA canonical formatter makes diffs meaningful, ends style review, and gives\nagents format-on-save invariance — the job `zig fmt` does for the compiler's\nown Zig, which nothing did for Scheme. This is the final item of the\nmachine-legibility epic (#1503).\n\nComments are not datums, so the ordinary reader (which discards them) cannot\ndrive a formatter. `fmt` therefore has its own concrete-syntax reader\n(`src/fmt.zig`): a lexer that emits every lexeme — line/block/`#;` comments and\nthe blank-line structure between them — and a parser that builds a CST keeping\natom text verbatim, so number/character/string spellings are never rewritten.\n`src/fmt_print.zig` lays the CST out: 2-space R7RS indentation, single-space\nseparators, closing parens gathered, forms reflowed to 80 columns using the two\nstandard Scheme shapes (body style for define/lambda/let/when/case/…, call\nstyle for calls/cond/vectors/unknown heads).\n\nLayout only rearranges whitespace between lexemes, so the datums a program reads\nare invariant by construction — and that is also checked at runtime: before\nwriting any file, `verifyRoundTrip` re-reads the original and the formatted text\nwith the real reader and compares the datum sequences with `equal?`. On any\nmismatch it refuses to write, so a bug here can never corrupt a source file.\n\n`--check` writes nothing and exits nonzero listing paths that need formatting,\nfor CI; with no files, stdin is formatted to stdout.\n\nVerified over all 558 .scm/.sld files under tests/scheme and lib: zero semantic\ndrift, zero syntax errors, and 558/558 idempotent. Tests: src/tests_fmt.zig\n(exact cases, comment/blank-line preservation, idempotence + round-trip over\ngrammar-fuzzer programs) and tests/scheme/fmt/fmt.sh (CLI behaviour plus the two\ncorpus-wide properties), wired into run-all.sh. Documented in docs/dev/fmt.md.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-15T15:59:54Z",
          "tree_id": "3ec96ad2dae3fb6fb3d1326543572ec1fb4b383a",
          "url": "https://github.com/kaappi/kaappi/commit/807fd64ac9c6e38d4e9d492a0117a8958a8d3a90"
        },
        "date": 1784133184648,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.401971,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.036704,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.920499,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.46445,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006526,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.054155,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.50658,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069704,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.395191,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.989996,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.570437,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.434811,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.849904,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.682599,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043074,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "020289ab9c636ae761ad98d274b6656f09854cbb",
          "message": "Add crash-reporting panic handler with context breadcrumb (#1575)\n\nWhen a bug is in kaappi itself, ReleaseSafe dies with a raw Zig panic and\ntrace. Better than a silent segfault, but the user gets no guidance and no\nversion context, and we get reports that arrive unreproducible or not at all.\n\nAdd a custom panic handler for the user-facing binaries (kaappi, thottam):\neach root file sets `pub const panic = crash.PanicHandler(\"<name>\")`, a\nFullPanic that prints a banner then delegates to defaultPanic so the message\nand full stack trace are preserved. The banner names whose bug it is, the\nexact build (version, arch-os, build mode), the pipeline stage and file in\nflight, and where to report it.\n\nThe `while:` line is driven by a near-zero-cost breadcrumb (a plain enum + a\nslice, read only from the panic handler) updated at reading/expanding/\ncompiling/executing boundaries in runFile, runStdin, the embedded path, the\nREPL, the pipeline dumps, and the native compiler. It is omitted when idle,\nso thottam (no Scheme pipeline) shows only the build + report lines.\n\n`--panic-test[=<stage>]` is an internal, undocumented hook that deliberately\npanics so CI can verify the banner. It is intentionally not Debug-gated: the\nerror suite runs against the shipped ReleaseSafe build, which is the path a\nreal user hits and the mode the banner names.\n\nCloses #1514.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-15T23:26:39+05:30",
          "tree_id": "84f006da0d0a6da8a508cb085e71f31d764fdd0e",
          "url": "https://github.com/kaappi/kaappi/commit/020289ab9c636ae761ad98d274b6656f09854cbb"
        },
        "date": 1784140150277,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.363256,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.415797,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.940195,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.490336,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006469,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.054269,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.50616,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.07021,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.459541,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.994219,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.596976,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.442638,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.867736,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.775098,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044849,
            "unit": "seconds"
          }
        ]
      }
    ]
  }
}