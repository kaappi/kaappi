window.BENCHMARK_DATA = {
  "lastUpdate": 1783025724846,
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
          "id": "bbe7d318f75a2168a3558b00213b1f8e36f2e8f8",
          "message": "Fix bare lambda internal define register clobbering (#601) (#615)\n\nIn compileLambdaWithIR, the body loop freed exactly one register after\neach non-final expression. When compileDefineFromIR allocated an extra\nregister for a local variable, that local's slot was reused by the next\nexpression, causing wrong values or runtime type errors.\n\nTrack whether compileFromNode allocated extra registers (for locals) and\nskip freeReg when it did, preserving the local's slot.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-01T01:51:33+05:30",
          "tree_id": "e683ef80de6dc5d2292545e186055e766355712e",
          "url": "https://github.com/kaappi/kaappi/commit/bbe7d318f75a2168a3558b00213b1f8e36f2e8f8"
        },
        "date": 1782851542821,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.290064,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.220745,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.806455,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.16915,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006945,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.03206,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.452847,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 1.145877,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.94287,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.764609,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.135508,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.219603,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.480891,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "5d85dcc4bdc91fdcc5f1a2d4c014c6b4ffc7b212",
          "message": "Fix string->number \"#e<large>\" process abort (#604) (#616)\n\napplyExactness used unchecked @intFromFloat(trunc) to i64 for the exact\ninteger path, panicking when the float exceeded i64 range. Use\nsafeFloatToExactInt which promotes to bignum for large values.\n\nAlso guard the non-integer rational path against i64 overflow on the\nscaled numerator.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-01T02:07:24+05:30",
          "tree_id": "4bd93ff65678eb5e1081ea4645519f8de30c1ada",
          "url": "https://github.com/kaappi/kaappi/commit/5d85dcc4bdc91fdcc5f1a2d4c014c6b4ffc7b212"
        },
        "date": 1782852555102,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.280017,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.398782,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.803834,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.126977,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006905,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.03288,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.451942,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 1.147251,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.914398,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.762804,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.105122,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.218831,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.412188,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "9721f5150e41bbbd68273cd41e3c5577e31d60a3",
          "message": "Fix floor-quotient/truncate-quotient fixnum overflow (#603) (#617)\n\nBoth procedures used types.makeFixnum for the quotient result, which\nsilently truncates values outside i48 range. The only triggering case\nis minInt(i48) ÷ -1 = 2^47, which wraps to the most-negative fixnum.\n\nUse arith.makeFixnumChecked which promotes to bignum on overflow.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-01T02:22:29+05:30",
          "tree_id": "b6271456d05033a96c56ba910565b1157eaeaab1",
          "url": "https://github.com/kaappi/kaappi/commit/9721f5150e41bbbd68273cd41e3c5577e31d60a3"
        },
        "date": 1782853392170,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.291792,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.910723,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.855784,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.134798,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007035,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032974,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.45204,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 1.151492,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.958152,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.765264,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.097302,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.226681,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.419597,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "97cf45868d645130bf92f55e0a79c017b76ba769",
          "message": "Fix constant folding ignoring redefined primitives (#600) (#618)\n\nThe IR constant folding and boolean simplification passes folded calls\nto + - * = < > <= >= zero? not by symbol name without checking whether\nthe user had redefined those bindings at the top level.\n\nAdd a globals field to the IR struct and check whether each operator\nis still bound to its original NativeFn before folding. Thread the\ncompiler's globals map through to all IR construction sites.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-01T02:42:31+05:30",
          "tree_id": "af69a099f5c225918e2b6eed977b816269be994f",
          "url": "https://github.com/kaappi/kaappi/commit/97cf45868d645130bf92f55e0a79c017b76ba769"
        },
        "date": 1782854660088,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.768732,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.651305,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.749468,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.713156,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006954,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.031298,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.409207,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 1.070329,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.998459,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.601257,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.070799,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.218283,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.251927,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "33c04050c252a875f19be4ba9eda4daeb9e7fe0c",
          "message": "Fix -o flag stripped from (command-line) in normal runs (#602) (#619)\n\nThe post-file-path argument loop unconditionally intercepted -o and\nswallowed it along with its value, even during normal script execution.\nGuard -o stripping with compile/disassemble/emit-llvm mode flags so\nscripts that accept -o as their own option can see it.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-01T02:57:32+05:30",
          "tree_id": "0502ffbda6eb53853a1d95b2742b6a554e913ef9",
          "url": "https://github.com/kaappi/kaappi/commit/33c04050c252a875f19be4ba9eda4daeb9e7fe0c"
        },
        "date": 1782855481690,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.982589,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.621045,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.840716,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.319973,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007228,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032187,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.445759,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 1.271716,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.886788,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.708867,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.109454,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.239555,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.360516,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "a862510cc9147b1a3b39c21911139bc35bcb7acf",
          "message": "Fix deepCopyValue record_instance missing cycle guard (#606) (#620)\n\nThe .record_instance arm was the only compound arm that never registered\nin the visited map, causing infinite recursion (stack overflow) on cyclic\nrecords and broken sharing on DAGs during cross-thread deep copy.\n\nAllocate the new instance with empty fields first, register in visited,\nthen deep-copy fields into the pre-allocated instance — matching the\npattern used by .pair, .vector, .closure, and all other compound arms.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-01T03:12:35+05:30",
          "tree_id": "d25185b14d3ef19bf1ff47a6d179cf3d58aea7df",
          "url": "https://github.com/kaappi/kaappi/commit/a862510cc9147b1a3b39c21911139bc35bcb7acf"
        },
        "date": 1782856398185,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.301084,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.905477,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.806341,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.071405,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00703,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032132,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.450828,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 1.143958,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.959639,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.757745,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.131186,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.216239,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.404597,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "7110c9742af24a4cd2ab4ece5b411e2d7f0e1524",
          "message": "Fix deepCopyValue dropping transformer fields on cross-thread copy (#605) (#621)\n\nThe .transformer arm of deepCopyValue only reconstructed literals,\npatterns, and templates — silently dropping custom_ellipsis,\ncaptured_locals, and def_env. Macros using these fields would\nproduce wrong results after crossing a thread boundary.\n\nReconstruct all three fields: dupe custom_ellipsis and captured_locals,\nshare def_env (part of shared library infrastructure).\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-01T03:28:25+05:30",
          "tree_id": "37f5e30afb9cc3d2696cfd57a1c924f76f3d072c",
          "url": "https://github.com/kaappi/kaappi/commit/7110c9742af24a4cd2ab4ece5b411e2d7f0e1524"
        },
        "date": 1782857346241,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.934035,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.078016,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.817321,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.083117,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007309,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.031941,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.446184,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 1.266447,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.823905,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.71369,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.092668,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.235331,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.363482,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "5060ba647fd05fea337a4e424aededbaf738684b",
          "message": "Reject denormalized bignum in bytecode reader (#607) (#622)\n\nreadConstant's TAG_BIGNUM branch accepted bignums with a zero top limb,\nviolating the normalization invariant. Downstream comparisons and\narithmetic would produce wrong results for such values.\n\nAdd a check that the most-significant limb is non-zero, rejecting\ncorrupt .sbc files that contain denormalized bignums.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-01T03:43:12+05:30",
          "tree_id": "5e846be7f95434a25711c118b0005c36a7b1f581",
          "url": "https://github.com/kaappi/kaappi/commit/5060ba647fd05fea337a4e424aededbaf738684b"
        },
        "date": 1782858214643,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.72289,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.763132,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.760534,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.607777,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006989,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.031279,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.409562,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 1.071558,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.988581,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.559614,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.083833,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.222061,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.248547,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "41c36da6dfd1017a14d9f32273ecf755ecf9582a",
          "message": "Fix bytecode symbol name length write/read mismatch (#609) (#623)\n\nThe writer used unchecked @intCast(sym.name.len) to u16 for symbol and\nfunction name lengths, panicking on names > 65535 bytes in ReleaseSafe.\nThe reader rejects names > MAX_SYMBOL_BYTES (4096), creating a\nwrite/read mismatch for names 4097-65535 bytes.\n\nAdd MAX_SYMBOL_BYTES validation on the write side for both symbol\nconstants and function names, matching the reader's limit and\npreventing the @intCast panic.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-01T04:03:23+05:30",
          "tree_id": "5d7554c6fb0229f17c836375292208c06feba3cc",
          "url": "https://github.com/kaappi/kaappi/commit/41c36da6dfd1017a14d9f32273ecf755ecf9582a"
        },
        "date": 1782859451478,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.299026,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.214066,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.80275,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.114234,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006872,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.033777,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.451519,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 1.146434,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.955723,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.761095,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.173383,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.215993,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.406879,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "0f6dab1dafafb65a7e3d0c789f1d40134600b34f",
          "message": "Fix macro import leaking entire def_env into importer (#608) (#624)\n\nimportBinding copied the macro's entire definition-site environment\n(def_env) into the importing namespace, leaking all private library\nbindings — even those never referenced by any template.\n\nNow uses collectFreeRefs/collectSymbols to compute which names the\ntemplates actually reference, and only copies those from def_env.\nUnreferenced private helpers are no longer visible in the importer.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-01T04:25:36+05:30",
          "tree_id": "d6ca31acfbe0e92072c42365fa2a5d181f799aa7",
          "url": "https://github.com/kaappi/kaappi/commit/0f6dab1dafafb65a7e3d0c789f1d40134600b34f"
        },
        "date": 1782860771435,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.076912,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.958762,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.762294,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.826171,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006295,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.030661,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.422829,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 1.074203,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.814122,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.638099,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.027224,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.202926,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.241188,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "27701f330e24c010e12052b8e1bc9ab539298ea8",
          "message": "Fix git argument injection in thottam package manager (#614) (#625)\n\nCustom source URLs from ::url specs and kaappi.pkg manifest source:\nfields were passed to git clone/ls-remote as positional arguments\nwithout a '--' separator. A URL starting with '-' would be parsed\nas a git option, enabling argument injection.\n\nAdd '--' end-of-options separator before user-controlled URLs in\ngit clone and git ls-remote invocations. Also reject source URLs\nstarting with '-' at parse time in both parsePkgSpec and manifest\nparsing.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-01T04:40:13+05:30",
          "tree_id": "acb2773b7e4ff8739daadc0175a23cd293de1bec",
          "url": "https://github.com/kaappi/kaappi/commit/27701f330e24c010e12052b8e1bc9ab539298ea8"
        },
        "date": 1782861609674,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.934002,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.007077,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.828833,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.127833,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007287,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032104,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.445251,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 1.267293,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.83112,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.714138,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.100581,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.234551,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.370796,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "d9ae2cb0b718512ed96298d815bc4c9359d1906d",
          "message": "Fix isConstraintSpec panic on empty-after-trim version (#613) (#626)\n\nisConstraintSpec checked ver.len == 0 but then trimmed quotes and\nindexed clean[0] without rechecking length. A version like @\"\"\nproduced an empty slice after trim, panicking on the index.\n\nAdd a clean.len == 0 check after trimming.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-01T04:51:16+05:30",
          "tree_id": "aa1b624f1f8dbfea4a879112aa4a3634155d5c86",
          "url": "https://github.com/kaappi/kaappi/commit/d9ae2cb0b718512ed96298d815bc4c9359d1906d"
        },
        "date": 1782862238901,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.337738,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.735064,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.812484,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.097224,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007047,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032656,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.448938,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 1.14696,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.021738,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.763251,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.113738,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.222006,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.412035,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "015f79b5c2f8056385b9fd8d11749f3c07cb89b3",
          "message": "Fix toRationalParts calling toFixnum on bignum fields (#627)\n\n* Fix toRationalParts calling toFixnum on bignum fields (#611)\n\ntoRationalParts called types.toFixnum on rational numerator/denominator\nwithout checking if they were bignums. Bignums truncated to garbage i64\nvalues, causing wrong results from arithmetic and comparison on rationals\nlike (exact 0.1) whose fields exceed i48 range.\n\nReturn null from toRationalParts when fields are bignums, and fall back\nto float arithmetic at all 8 call sites (matching the existing bignum\nfallback pattern).\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Add bare-ok markers for bignum fallback error returns\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-01T05:18:38+05:30",
          "tree_id": "24c509ce9dd63b0de2f99a771fc02a254d94e1dd",
          "url": "https://github.com/kaappi/kaappi/commit/015f79b5c2f8056385b9fd8d11749f3c07cb89b3"
        },
        "date": 1782863961801,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.322651,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.695586,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.80549,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.122708,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007254,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032362,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.453226,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 1.145806,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.974887,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.773316,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.08429,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.218928,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.392797,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "2a0aa067d47e9f6eda3a6c56523ca072909eadb1",
          "message": "Fix makeRationalFromReader using unchecked makeFixnum (#610) (#628)\n\nmakeRationalFromReader used unchecked types.makeFixnum for numerator\nand denominator, silently truncating values outside i48 range. Rational\nliterals like 200000000000000/3 would parse to the wrong value.\n\nUse makeFixnumChecked which promotes to bignum when the value exceeds\ni48 range.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-01T05:33:35+05:30",
          "tree_id": "dbe20ff8fa193a2802477f504bbe2672e7222b5d",
          "url": "https://github.com/kaappi/kaappi/commit/2a0aa067d47e9f6eda3a6c56523ca072909eadb1"
        },
        "date": 1782864915165,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.289522,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.979513,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.835522,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.484702,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006833,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032081,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.457592,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 1.14897,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.971325,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.788414,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.100293,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.226291,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.409527,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "e04b06a898728c19602adae030efa479a1d90ea5",
          "message": "Fix exact division with bignums returning flonum instead of rational (#612) (#629)\n\nTwo paths in divFn silently degraded exact results to flonum when\nbignums were involved:\n\n1. Single-arg reciprocal (/ bignum) fell through to the float path\n   instead of producing an exact rational 1/bignum.\n\n2. Multi-arg bignum division only handled the args.len==2 exact-divide\n   case; non-even division fell through to float.\n\nAdd bignum case to single-arg reciprocal using makeRationalReduced,\nand extend multi-arg bignum path to produce exact rationals when\ndivision is not even.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-01T05:46:59+05:30",
          "tree_id": "1ec1a382e6fe33c1d355cc4f7ede74ba57729175",
          "url": "https://github.com/kaappi/kaappi/commit/e04b06a898728c19602adae030efa479a1d90ea5"
        },
        "date": 1782865647537,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.726466,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.760755,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.761779,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.956502,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007232,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.030926,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.412124,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 1.074722,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.987335,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.568858,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.091656,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.218687,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.225906,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0,
            "unit": "seconds"
          }
        ]
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
          "id": "9ae0cca1874d8816c1a7ccf4acc1ff21dd0e8ca2",
          "message": "Release v0.9.1",
          "timestamp": "2026-07-01T06:17:51+05:30",
          "tree_id": "9d4922c6b7d890183345793b42978b9442a3ae73",
          "url": "https://github.com/kaappi/kaappi/commit/9ae0cca1874d8816c1a7ccf4acc1ff21dd0e8ca2"
        },
        "date": 1782867673638,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.931141,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.345162,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.829258,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.447235,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00724,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032498,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.445777,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 1.265114,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.829556,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.726059,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.09341,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.239784,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.37417,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "97d32d73a479e0e1426e53d30ce697615803788a",
          "message": "Fix emitDirectCall skipping arity validation in native backend (#636) (#652)\n\nThe LLVM native backend's emitCallNode resolved statically-known calls\nto natively-compiled functions via emitDirectCall without checking that\nthe call site's argument count matched the callee's arity. This caused\nover-application to silently compute wrong results and under-application\nto read out-of-bounds stack memory.\n\nAdd arity validation before using the direct-call and self-tail-call\nfast paths: fixed-arity functions require exact match, variadic functions\nrequire at least the fixed parameter count. Mismatched calls fall through\nto kaappi_call_scheme which raises proper arity errors.\n\nAlso fix two call sites that overwrote native_fns entries (with correct\narity from emitLambdaFunction) with arity=0, which would have broken the\nnew arity checks.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-01T07:13:44+05:30",
          "tree_id": "8e01acbec08c0c88982cc681bd81efb5ce9fd755",
          "url": "https://github.com/kaappi/kaappi/commit/97d32d73a479e0e1426e53d30ce697615803788a"
        },
        "date": 1782870889534,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.925724,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.590044,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.857306,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.167181,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007276,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032448,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.455971,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 1.267064,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.849869,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.74017,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.103536,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.242734,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.368682,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "1b14fa3384b8718835dfc1653b92a5bc22d60fe5",
          "message": "Fix markVMRoots iterating shared libraries map in child threads (#634) (#653)\n\nmarkVMRoots correctly gated globals/macros marking on owns_globals to\nprevent child thread GC from iterating the parent's shared maps without\nsynchronization. However, vm.libraries.libraries was marked\nunconditionally despite being shared the same way via initForThread.\n\nGate library marking on owns_globals to match globals/macros treatment.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-01T07:29:06+05:30",
          "tree_id": "e7213ae2dbd9b630f4975f82e3e50e246209438f",
          "url": "https://github.com/kaappi/kaappi/commit/1b14fa3384b8718835dfc1653b92a5bc22d60fe5"
        },
        "date": 1782871878797,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.929088,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.101289,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.836618,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.17059,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007313,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032221,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.450705,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 1.265232,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.875575,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.746552,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.100246,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.23727,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.36895,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "54f43c84e0f957491f720f9b79d0ceeb42223e01",
          "message": "Fix VM.initForThread sharing parent's Port objects by raw pointer (#635) (#654)\n\nChild threads created via thread-start! shared the parent VM's\nstdin/stdout/stderr Port heap objects by copying the raw Value pointer.\nThis meant both threads' I/O primitives mutated the same Port struct\nwithout synchronization, and the child GC had no knowledge of these\ncross-heap pointers.\n\nAllocate fresh Port objects in initForThread using the child's GC,\nwrapping the same underlying fds (0/1/2). Each thread now has its own\nindependent Port state, matching the documented thread-isolation model.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-01T07:44:30+05:30",
          "tree_id": "5cdf34286812273713cb000612fe86b9f11031e3",
          "url": "https://github.com/kaappi/kaappi/commit/54f43c84e0f957491f720f9b79d0ceeb42223e01"
        },
        "date": 1782872754431,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.311573,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.752895,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.812258,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.088971,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006782,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.03278,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.451091,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 1.145527,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.866819,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.760153,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.09409,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.219175,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.391093,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "c57cd2ca0f3e190b0621ba94de0d98ee23e3b8b4",
          "message": "Fix parseBignumString CHUNK_DIGITS overflow for radix 12-36 (#631) (#655)\n\nparseBignumString hardcoded CHUNK_DIGITS=18 for all radices except\n2, 8, and 16. For radix 12+, an 18-digit chunk exceeds u64 max,\ncausing std.fmt.parseInt to overflow and crash with a runtime error\ninstead of returning the correct bignum value.\n\nReplace the hardcoded value with a precomputed lookup table that gives\nthe largest d such that radix^d fits in a u64 for each radix 2-36.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-01T08:00:34+05:30",
          "tree_id": "f2ad829bef2b24d06629e73ae122e689418cacdb",
          "url": "https://github.com/kaappi/kaappi/commit/c57cd2ca0f3e190b0621ba94de0d98ee23e3b8b4"
        },
        "date": 1782873697402,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.916551,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.363094,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.843564,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.156906,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007294,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032088,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.450673,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 1.266395,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.817129,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.746406,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.092842,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.243948,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.371597,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "7a7eedb80566fbe5afb27d939dea7d9855d86721",
          "message": "Fix toCString silently truncating strings with embedded NUL bytes (#630) (#656)\n\ntoCString copied Scheme string bytes into a buffer and appended a NUL\nterminator without checking for interior NUL bytes. Since C string\nsemantics treat the first NUL as the string end, this silently\ntruncated the string passed to the C callee.\n\nAdd a scan for interior NUL bytes before copying. If found, return null\nwhich propagates as a TypeError to Scheme code, giving callers a clear\nerror instead of silently-wrong data crossing the FFI boundary.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-01T08:15:30+05:30",
          "tree_id": "2e73be997d38123f0fac1e1279763b5081c7f17c",
          "url": "https://github.com/kaappi/kaappi/commit/7a7eedb80566fbe5afb27d939dea7d9855d86721"
        },
        "date": 1782874591607,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.333232,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.763928,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.826134,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.275586,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006861,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.033166,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.460783,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 1.156751,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.882886,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.802343,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.129039,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.223149,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.442806,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "2d95b9f5bb21ef63937843bb66b121e309d60f35",
          "message": "Fix Complex number printing dropping -0.0 components (#637) (#657)\n\nThe printer used == 0.0 and != 0.0 to decide whether to omit complex\ncomponents. Since IEEE 754 defines -0.0 == 0.0, a -0.0 imaginary part\nwas silently dropped (printing as a bare real) and a -0.0 real part was\nomitted (printing as just the imaginary part with a sign).\n\nUse std.math.signbit to detect negative zero: preserve the imaginary\npart when it's -0.0, include the real part when it's -0.0, and emit\n'-' instead of '+' for a -0.0 imaginary part.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-01T08:31:24+05:30",
          "tree_id": "fa309ef16bb1eee8acb27ebc037dd46a4ee91155",
          "url": "https://github.com/kaappi/kaappi/commit/2d95b9f5bb21ef63937843bb66b121e309d60f35"
        },
        "date": 1782875572444,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.304664,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.408815,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.799512,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.144232,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006863,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032158,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.449691,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 1.144912,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.89249,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.766148,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.082595,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.217781,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.402526,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "c5934c0d9ca1dbf7a67a84e37fec3e46d2a393af",
          "message": "Fix highlightCallback misparses character literals (#633) (#658)\n\nhighlightCallback had no special-casing for #\\ character literals.\nCharacters like #\\; triggered the line-comment branch (painting the\nrest of the line gray), and #\\( / #\\) triggered the paren branch\n(producing extra colored spans).\n\nAdd a #\\ case that consumes the character literal as a single token\n(either one non-alpha character or an alphabetic run for named chars\nlike #\\space), mirroring parenDepth's existing handling.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-01T08:46:30+05:30",
          "tree_id": "ca24318ab1125819dd8dfde732241ba25d692019",
          "url": "https://github.com/kaappi/kaappi/commit/c5934c0d9ca1dbf7a67a84e37fec3e46d2a393af"
        },
        "date": 1782876440734,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.335746,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.604252,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.818687,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.177203,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006864,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032294,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.452172,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 1.146198,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.999244,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.761837,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.109618,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.23155,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.435521,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "a051a2398ef618bc69ae20c771bbfc086cb38876",
          "message": "Fix create-temp-file raising uninformative bare TypeError (#632) (#659)\n\ncreate-temp-file returned a bare PrimitiveError.TypeError when the\nprefix was too long, producing \"type error in 'create-temp-file'\" with\nno irritants. Every other error path in this file uses raiseFileError\nto produce descriptive messages.\n\nReplace with raiseFileError(\"temp file prefix too long\", args[0]) to\ngive callers a clear message with the prefix as the irritant.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-01T09:01:32+05:30",
          "tree_id": "1af7a6f2f5e69adabe824cd91cab21fc38d17344",
          "url": "https://github.com/kaappi/kaappi/commit/a051a2398ef618bc69ae20c771bbfc086cb38876"
        },
        "date": 1782877334272,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.964873,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.783237,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.743659,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.866665,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006885,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032294,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.415296,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 1.064491,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.670926,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.634268,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.027396,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.201584,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.238171,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "015dfe4e7a54da6bbf816ef8c60b5e632e2e9be4",
          "message": "Fix tail call passing pointer to caller's stack alloca (#639) (#660)\n\nemitCallNode and emitDirectCall were marking calls as `tail call` even\nwhen arguments were passed via an alloca in the caller's stack frame.\nLLVM tail calls may reuse the caller's stack, invalidating the alloca\npointer and corrupting arguments. Only use `tail call` for zero-argument\ncalls where no stack alloca is needed; calls with arguments use regular\n`call` + `ret` which preserves correct semantics.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-01T09:19:46+05:30",
          "tree_id": "10fdb2b17d8db3201cbf9bcbc1315b33a401961c",
          "url": "https://github.com/kaappi/kaappi/commit/015dfe4e7a54da6bbf816ef8c60b5e632e2e9be4"
        },
        "date": 1782878513385,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.328567,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.156608,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.807296,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.188098,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006756,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032196,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.451215,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 1.144765,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.863641,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.771908,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.093119,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.218586,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.407438,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "bcc7acebcfcb1e32f324231157e86e6b518e82d4",
          "message": "Fix read-bytevector allocating full k-byte buffer upfront (#638) (#661)\n\nread-bytevector was allocating a buffer of the full requested size k\nbefore reading any data. A large k (e.g. 10^12) caused the process to\nhang attempting the allocation, even when only a few bytes were available.\nThis was exploitable under --sandbox.\n\nSwitch to incremental ArrayList growth (matching read-string's approach)\nso only actually-read bytes are buffered.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-01T09:35:38+05:30",
          "tree_id": "9ab5392bd87690e2494071a59856f36a0772290c",
          "url": "https://github.com/kaappi/kaappi/commit/bcc7acebcfcb1e32f324231157e86e6b518e82d4"
        },
        "date": 1782879406721,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.918063,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.932419,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.851486,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.162615,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007652,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032317,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.451681,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 1.266802,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.908556,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.738665,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.097706,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.246291,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.383023,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "fcc61d4bdf7ad11b74085ad092f1860f02b7b781",
          "message": "Fix string-for-each/string-map byte cursor desync on mutation (#645) (#662)\n\nBoth functions tracked iteration position as raw byte offsets, which\nbecame stale when the callback mutated the string (via string-set!)\nat a position that changed UTF-8 byte widths. Switch to codepoint\nindex tracking, recomputing the byte offset from the index each\niteration to correctly handle buffer layout changes from mutations.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-01T09:49:17+05:30",
          "tree_id": "85bdf7f1ffa5a9f9ecfe02ca2536b2d4864b4f38",
          "url": "https://github.com/kaappi/kaappi/commit/fcc61d4bdf7ad11b74085ad092f1860f02b7b781"
        },
        "date": 1782880298028,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.344543,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.906904,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.811172,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.129752,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006814,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032379,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.451332,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 1.149541,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.926256,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.768503,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.081334,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.217183,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.468821,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "e8a73ab43178a2cfd3db9d680375450303ef6cee",
          "message": "Fix SRFI-13 parseStartEnd and string-take/-drop silently clamping out-of-range indices (#640) (#663)\n\nparseStartEnd, string-take, string-drop, string-take-right, and\nstring-drop-right used `orelse data.len` when utf8IndexToByteOffset\nreturned null for out-of-range indices, silently clamping instead of\nraising an error. Change all sites to return IndexOutOfBounds, matching\nsubstring/string-copy/string-ref behavior.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-01T10:05:29+05:30",
          "tree_id": "449fd55148b76d32a0b6896705408a83b56929ef",
          "url": "https://github.com/kaappi/kaappi/commit/e8a73ab43178a2cfd3db9d680375450303ef6cee"
        },
        "date": 1782881225966,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.309525,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.173091,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.811054,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.014254,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007219,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032751,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.445258,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 1.145833,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.971431,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.752166,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.100065,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.220191,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.421784,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "1047a09e39260270090da9ca5e08d013d711c0a1",
          "message": "Fix LSP crash on negative or oversized line/character position (#641) (#664)\n\nhandleCompletion, handleHover, handleDefinition, and handleReferences\nused @intCast to convert i64 position values to u32, which panics on\nnegative or >u32::MAX values in ReleaseSafe. Add clampToU32 helper\nthat safely clamps to [0, maxInt(u32)], preventing the server from\ncrashing on malformed position inputs.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-01T10:16:16+05:30",
          "tree_id": "ce312327f19effbf3e424a224dfe70e38ae6d9ff",
          "url": "https://github.com/kaappi/kaappi/commit/1047a09e39260270090da9ca5e08d013d711c0a1"
        },
        "date": 1782881777745,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.326998,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.23011,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.808058,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.03305,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007013,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032267,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.452566,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 1.146928,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.965816,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.764691,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.100546,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.219072,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.387557,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "18440e549cb969665ab9d449b4bdfb6e3b36246a",
          "message": "Fix PR Benchmark Comparison workflow always failing (#665)\n\nFix PR Benchmark Comparison workflow:\n- Use 'raw' tool type (not 'customSmallerIsBetter') for openpgpjs action compatibility\n- Fork action to kaappi/github-action-pull-request-benchmark with PR comment support (upsert), visualization (Unicode bars + color indicators), and node20 runtime\n- Add self-trigger path for workflow file changes",
          "timestamp": "2026-07-01T12:29:24+05:30",
          "tree_id": "f7f1355c1005adbc5a5af68a0e8cb73c335011f5",
          "url": "https://github.com/kaappi/kaappi/commit/18440e549cb969665ab9d449b4bdfb6e3b36246a"
        },
        "date": 1782889883880,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.945866,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.73744,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.84549,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.172057,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007295,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032081,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.453497,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 1.265954,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.845076,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.761666,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.099173,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.24187,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.414421,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "8efa3e55a36695ab0251aa57208c40501c978283",
          "message": "Fix zig build bench failing and call_cc/call_ec showing 0 in PR benchmarks (#667)\n\nThe bench module was the only build target missing the build_options import,\ncausing compilation failure. The benchmark runner silently swallowed the error\nand defaulted to 0.\n\nEven after fixing the build, the output parser would fail: data rows contain\nonly numbers (no \"call/cc\" text), and the format uses zero decimal places\nso the float regex never matched.\n\nFix by adding machine-readable summary lines to bench.zig (matching the\ncommon.scm format) and rewriting run_callcc_bench to use extract_field.\n\nFixes #666\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-01T13:08:11+05:30",
          "tree_id": "a33a0735e50357928bbba1bfd3bcc1691c28db08",
          "url": "https://github.com/kaappi/kaappi/commit/8efa3e55a36695ab0251aa57208c40501c978283"
        },
        "date": 1782892143022,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.962698,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 10.280699,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.85818,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.178928,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007829,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032115,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.452219,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 1.268337,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.833201,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.743757,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.101104,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.248348,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.421627,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.834839,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044012,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "9646b8cb5b18e20911d9c52f5aa1b6af235450e7",
          "message": "Fix referencesYoung .fiber case missing handler_stack, wind_stack, param_overrides, and frame.native (#646) (#668)\n\nThe remembered-set pruning logic checked fewer fiber fields than\nmarkFiberState, which could cause premature eviction of fibers from the\nremembered set when their only young references were through these\nunchecked fields.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-01T13:45:23+05:30",
          "tree_id": "7975859e2874d7f9ed32ceb33c6d4bdaf4675065",
          "url": "https://github.com/kaappi/kaappi/commit/9646b8cb5b18e20911d9c52f5aa1b6af235450e7"
        },
        "date": 1782894470460,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.538379,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.863921,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.639517,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.1508,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007103,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.028374,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.35266,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 1.183803,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.641877,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.361391,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 0.992042,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.226418,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.935347,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.030478,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.03603,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "0f120bdc88b7e217aee7178f2cf518214afdbad1",
          "message": "Merge pull request #669 from kaappi/fix/648-equal-dag-hang\n\nFix equal? exponential blowup on shared DAGs deeper than 128 nodes (#648)",
          "timestamp": "2026-07-01T14:06:07+05:30",
          "tree_id": "eaba0c3398ce2a8ac5918317fed63967ecefb2c4",
          "url": "https://github.com/kaappi/kaappi/commit/0f120bdc88b7e217aee7178f2cf518214afdbad1"
        },
        "date": 1782895681082,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.913554,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.862007,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.844891,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.211001,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007455,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.031957,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.450971,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.067127,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.867161,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.741939,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.108537,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.244995,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.401654,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.71103,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044238,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "bd06f83c6c2a997de13cd1db03c0ca9b6e96ffb6",
          "message": "Merge pull request #670 from kaappi/fix/647-reader-peculiar-identifiers\n\nFix reader truncating peculiar identifiers like ->foo to just the sign",
          "timestamp": "2026-07-01T14:27:23+05:30",
          "tree_id": "fc7e555e01972af987b7307940d2fd588bdfb399",
          "url": "https://github.com/kaappi/kaappi/commit/bd06f83c6c2a997de13cd1db03c0ca9b6e96ffb6"
        },
        "date": 1782897003592,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.36429,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.235116,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.81116,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.174496,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006801,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032241,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.454345,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.066723,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.937902,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.802487,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.097203,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.215456,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.400988,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.605616,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.040826,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "85a5cc41edab6e68747b18dcf0d8814a94c3d3fa",
          "message": "Merge pull request #671 from kaappi/fix/651-internal-define-syntax-scope\n\nFix internal define-syntax inside let/letrec body leaking macro binding",
          "timestamp": "2026-07-01T14:55:50+05:30",
          "tree_id": "668fb039ab58ceb8ae43720c86e05820e95b78e9",
          "url": "https://github.com/kaappi/kaappi/commit/85a5cc41edab6e68747b18dcf0d8814a94c3d3fa"
        },
        "date": 1782898686652,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.355475,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.484149,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.844971,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.198119,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007175,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032417,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.460295,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068405,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.972629,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.780648,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.114067,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.220238,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.436323,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.636747,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.041709,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "3ad06e1ad7107c997e72b55fdc1274a30e551277",
          "message": "Merge pull request #672 from kaappi/fix/649-apply-large-arglist\n\nRemove 256-argument cap from apply by using heap-allocated ArrayList",
          "timestamp": "2026-07-01T15:12:49+05:30",
          "tree_id": "01d07f32c3e503d5608dd710eac39f6b95b886ac",
          "url": "https://github.com/kaappi/kaappi/commit/3ad06e1ad7107c997e72b55fdc1274a30e551277"
        },
        "date": 1782899688080,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.304785,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.662472,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.827839,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.187661,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006899,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032764,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.456977,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.06875,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.923349,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.787183,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.105082,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.222937,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.456871,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.626846,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.04162,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "069ad033571bdd8daf81549c2ca1e714da706263",
          "message": "Merge pull request #673 from kaappi/fix/644-case-bytecode-bloat\n\nReduce case per-datum bytecode from ~39 to ~21 bytes, raising clause limit",
          "timestamp": "2026-07-01T15:32:17+05:30",
          "tree_id": "dbab56a24b1bf2f01e374c4b30653022c38c8c85",
          "url": "https://github.com/kaappi/kaappi/commit/069ad033571bdd8daf81549c2ca1e714da706263"
        },
        "date": 1782900856710,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.926255,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.248305,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.826325,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.132032,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007273,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032368,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.450205,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.066075,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.853403,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.737828,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.095638,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.235373,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.366697,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.78322,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.04535,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "bab7a5e0d6da321e7ee839fe6e9663a856e4d728",
          "message": "Merge pull request #674 from kaappi/fix/643-thread-self-join\n\nDetect thread-join! on current thread and raise error",
          "timestamp": "2026-07-01T15:51:40+05:30",
          "tree_id": "91a43cdbdb09204575bf0da50519c540e0bac646",
          "url": "https://github.com/kaappi/kaappi/commit/bab7a5e0d6da321e7ee839fe6e9663a856e4d728"
        },
        "date": 1782902183949,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.688396,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.619687,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.767358,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.658906,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007137,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.031233,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.406682,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.065923,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.958474,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.535949,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.080391,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.216788,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.243282,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.905532,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.038223,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "cdd00fbe50e72d5395f6cf506b62d67c628d3b33",
          "message": "Abandon mutexes held by terminated fibers (#642) (#675)\n\nSRFI-18 requires that when a thread terminates while holding a mutex,\nthe mutex becomes unlocked and abandoned. The read side (mutex-state,\nmutex-lock!) already handled the abandoned flag correctly, but nothing\never set it to true.\n\nAdd abandonFiberMutexes() which walks the GC object lists to find and\nmark mutexes owned by a given fiber. Call it from thread-terminate!,\nthreadEntryFn (OS thread exit), and all three cooperative scheduler\nloops (runSchedulerUntilDone/Mutex/CondVar) on fiber completion/error.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-01T16:27:18+05:30",
          "tree_id": "a2e4c80a02219b0d7b65dab34b97b1405d7b4ca1",
          "url": "https://github.com/kaappi/kaappi/commit/cdd00fbe50e72d5395f6cf506b62d67c628d3b33"
        },
        "date": 1782904164738,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.971054,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.557509,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.836696,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.17799,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007333,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032283,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.451861,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.066951,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.849613,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.744707,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.099788,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.239293,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.369102,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.792915,
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
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "distinct": true,
          "id": "84148985079576f48a5ca79bd770e76187a20288",
          "message": "Add dev doc for Claude Code harness setup\n\nDocuments hooks, permissions, path-scoped rules, skills, and the\nkaappi-dev ecosystem plugin with their configuration, interaction\nmodel, and extension guide.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-01T16:41:35+05:30",
          "tree_id": "03b0192402cbabe0c289bff202f55aa318213247",
          "url": "https://github.com/kaappi/kaappi/commit/84148985079576f48a5ca79bd770e76187a20288"
        },
        "date": 1782905094071,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.286471,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.369657,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.827619,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.301921,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007009,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.03284,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.458845,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069492,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.000269,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.775052,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.105369,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.222777,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.411092,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.650194,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042018,
            "unit": "seconds"
          }
        ]
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
          "id": "cdff9571b81aba51faafccdf4c33bbcafccc45e1",
          "message": "Add SessionStart hook, enforcement sections, and harness doc updates\n\n- SessionStart hook: prints branch, Zig version, warns about stale worktrees\n- Enforcement map tables in CLAUDE.md mapping rules to mechanisms\n- Updated harness dev doc with new hook documentation\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-01T16:54:09+05:30",
          "tree_id": "a09eb2a4d4270fce154989c501cc7ef732c004ac",
          "url": "https://github.com/kaappi/kaappi/commit/cdff9571b81aba51faafccdf4c33bbcafccc45e1"
        },
        "date": 1782905634719,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.301654,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.207635,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.821185,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.108282,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006977,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032575,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.456279,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068597,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.946671,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.773999,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.094273,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.220141,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.404316,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.650678,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.041531,
            "unit": "seconds"
          }
        ]
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
          "id": "210ac11306f9bf4484208d276339c6fbde99dae3",
          "message": "Release v0.10.0",
          "timestamp": "2026-07-01T16:59:05+05:30",
          "tree_id": "d12c818e60d1b3eb49ce239c75e902bf32f339ad",
          "url": "https://github.com/kaappi/kaappi/commit/210ac11306f9bf4484208d276339c6fbde99dae3"
        },
        "date": 1782906100811,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.292446,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.214087,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.846293,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.104526,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007799,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032674,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.457266,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068848,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.987544,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.776202,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.10164,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.232415,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.431733,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.684631,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.041793,
            "unit": "seconds"
          }
        ]
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
          "id": "c603d837d6affb31bdf40e1b96fa185d395dec5c",
          "message": "Document manual post-release workflow trigger in release skill\n\nThe post-release workflow won't auto-trigger because the release is\ncreated by github-actions[bot] using the default GITHUB_TOKEN, and\nGitHub suppresses workflow triggers from GITHUB_TOKEN events.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-01T17:09:15+05:30",
          "tree_id": "5e12bda9bf6c9d9a4626c1c81591bfb16228683a",
          "url": "https://github.com/kaappi/kaappi/commit/c603d837d6affb31bdf40e1b96fa185d395dec5c"
        },
        "date": 1782906617883,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.307948,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.69469,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.844343,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.411213,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00697,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032662,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.455612,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068754,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.979654,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.775906,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.094425,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.226242,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.408016,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.700741,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.04193,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "bcee57c1851cb327dce0cb25bed652687c5f22f1",
          "message": "Fix REPL tab completion for Scheme identifiers (#676)\n\nThe completion callback was matching global names against the entire\ninput line, so it only worked when the identifier started at position 0.\nExtract the last identifier token by scanning backwards for Scheme\ndelimiters, then match against just that token and reconstruct the full\nline for linenoise.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-01T17:39:56+05:30",
          "tree_id": "ea96112fe5dcc2686a5df1828d9acfc54a66f9a1",
          "url": "https://github.com/kaappi/kaappi/commit/bcee57c1851cb327dce0cb25bed652687c5f22f1"
        },
        "date": 1782908511197,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.32513,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.423232,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.83013,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.102661,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006862,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.03227,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.455923,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068453,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.91827,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.773433,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.084402,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.222759,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.40171,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.590929,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.040128,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "6acfb198d3f2b9b3eb251647da55dd9be391b743",
          "message": "Merge pull request #701 from kaappi/fix/compile-file-preamble-gc-699\n\nFix compileFile preamble skip and GC safety",
          "timestamp": "2026-07-01T23:23:55+05:30",
          "tree_id": "5a07c0cc08fb2bc4620b084cda4796aff71905c7",
          "url": "https://github.com/kaappi/kaappi/commit/6acfb198d3f2b9b3eb251647da55dd9be391b743"
        },
        "date": 1782929205583,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.284543,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.438707,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.841655,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.360958,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006903,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.033053,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.460731,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.067944,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.978866,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.776718,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.084244,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.225177,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.429693,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.641361,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.041717,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "be492c90575a136dcdcf3cc8e54818a6845ddc65",
          "message": "Merge pull request #702 from kaappi/fix/preamble-replay-gc-700\n\nFix preamble replay GC root and resilient library imports",
          "timestamp": "2026-07-02T00:59:05+05:30",
          "tree_id": "ff225c3b3c69f52db8cdb54c5104dab76b7db77a",
          "url": "https://github.com/kaappi/kaappi/commit/be492c90575a136dcdcf3cc8e54818a6845ddc65"
        },
        "date": 1782934947895,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.936612,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.854788,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.832371,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.128476,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007252,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.03225,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.450968,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.067325,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.861506,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.742095,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.100046,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.234834,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.402552,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.742226,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043144,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "29325b65edf7c2a2acb0ec22eabee82167295cb3",
          "message": "Merge pull request #704 from kaappi/fix/define-library-import-error-703\n\nFix handleDefineLibrary import abort and bundled file paths",
          "timestamp": "2026-07-02T02:17:32+05:30",
          "tree_id": "72cb2e6dfcdc337f765cdade344893dcd819fbee",
          "url": "https://github.com/kaappi/kaappi/commit/29325b65edf7c2a2acb0ec22eabee82167295cb3"
        },
        "date": 1782939652022,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.383219,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.259685,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.81524,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.203753,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006956,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032187,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.457,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.067852,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.959426,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.787924,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.075291,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.21726,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.409048,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.615897,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.040691,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "e075bc037ce97590165b7f8ed01233af20b211bd",
          "message": "Merge pull request #706 from kaappi/fix/gc-closure-func-mark-705\n\nFix generational GC: mark Closure.func in minor collections",
          "timestamp": "2026-07-02T07:51:09+05:30",
          "tree_id": "2428e5e1703e0ec58193c1328d50092d4c31ab07",
          "url": "https://github.com/kaappi/kaappi/commit/e075bc037ce97590165b7f8ed01233af20b211bd"
        },
        "date": 1782959663390,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.914159,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.825672,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.837485,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.212637,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00721,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032418,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.451031,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.067278,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.832124,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.742637,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.106352,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.240905,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.381832,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.884105,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044384,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "cdb110dc7d352cd90eb598893dfd338973eda296",
          "message": "Merge pull request #707 from kaappi/fix/load-library-source-gc-root-705\n\nRoot expr in loadLibrarySource before handleTopLevelForm",
          "timestamp": "2026-07-02T08:24:53+05:30",
          "tree_id": "53e94782dcb284cc1492cb8ceda98cd5a6a7873a",
          "url": "https://github.com/kaappi/kaappi/commit/cdb110dc7d352cd90eb598893dfd338973eda296"
        },
        "date": 1782961692665,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.34445,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.801096,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.82582,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.111884,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006875,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032309,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.456568,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069091,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.989646,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.791706,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.092541,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.223517,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.420228,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.741455,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.041773,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "37eddd451d9f8973461b946511c620bf59db4ba8",
          "message": "Merge pull request #709 from kaappi/fix/gc-record-type-mark-708\n\nFix generational GC: mark RecordInstance.record_type in minor collections",
          "timestamp": "2026-07-02T08:54:27+05:30",
          "tree_id": "5d1b94d62b17397c22484f5f69ff660b12a6b905",
          "url": "https://github.com/kaappi/kaappi/commit/37eddd451d9f8973461b946511c620bf59db4ba8"
        },
        "date": 1782963494766,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.346879,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.507032,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.830392,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.11498,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007032,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032528,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.457364,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.067321,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.017058,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.788376,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.107728,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.228576,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.41844,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.695214,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.041802,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "3a720c79399b33806e45e8432eec1f98bf8fa2d4",
          "message": "Merge pull request #710 from kaappi/fix/hash-table-walk-fold-uaf-690\n\nFix hash-table-walk/fold use-after-free when callback triggers rehash",
          "timestamp": "2026-07-02T09:22:13+05:30",
          "tree_id": "fcfc167b14d9fed9392d1a97edf1f9675f37f627",
          "url": "https://github.com/kaappi/kaappi/commit/3a720c79399b33806e45e8432eec1f98bf8fa2d4"
        },
        "date": 1782965159846,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.917384,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.986636,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.834447,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.139456,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007277,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.031982,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.45071,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.066989,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.91385,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.738881,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.108109,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.235107,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.376913,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.732191,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043564,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "bbe94b530daa5911e202d9a513ead86461638cf4",
          "message": "Merge pull request #712 from kaappi/fix/llvm-call-shadowing-684\n\nFix LLVM backend: respect local parameter shadowing in call position",
          "timestamp": "2026-07-02T09:49:49+05:30",
          "tree_id": "98696614c19a32ed4ebdbc289b550e71b3f4f654",
          "url": "https://github.com/kaappi/kaappi/commit/bbe94b530daa5911e202d9a513ead86461638cf4"
        },
        "date": 1782966839699,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.317937,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.191905,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.811156,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.119621,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006908,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032748,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.453038,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.067626,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.952613,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.776169,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.084564,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.223503,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.404937,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.692975,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042716,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "49714b6475c16d61a38f4df0afda7c9250eefaa6",
          "message": "Merge pull request #711 from kaappi/fix/define-values-register-corruption-687\n\nFix define-values register corruption with 2+ names in lambda body",
          "timestamp": "2026-07-02T09:58:21+05:30",
          "tree_id": "0009a6c31a0c80bfaefe6c76445eea7b9e8c6306",
          "url": "https://github.com/kaappi/kaappi/commit/49714b6475c16d61a38f4df0afda7c9250eefaa6"
        },
        "date": 1782967382185,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.375057,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.919361,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.851167,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.209583,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.0074,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.033458,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.462059,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070208,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.104614,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.78763,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.136156,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.231973,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.467582,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.741011,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.046543,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "121c84f4d07973062f17dabdaedc3747e9b548c9",
          "message": "Merge pull request #714 from kaappi/fix/llvm-variadic-closure-arity-685\n\nFix LLVM backend: bail out of native closure for variadic lambdas",
          "timestamp": "2026-07-02T09:59:17+05:30",
          "tree_id": "b153ddc6d7ddc9d88596f4fe0e4f864d0210c388",
          "url": "https://github.com/kaappi/kaappi/commit/121c84f4d07973062f17dabdaedc3747e9b548c9"
        },
        "date": 1782967452354,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.31773,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.634279,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.8231,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.169299,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006901,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032105,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.452867,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.067964,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.907801,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.770253,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.099019,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.218847,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.427323,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.607504,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.041828,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "2b55a6ac19f20f5eb3ba31f1090fef824df0c06b",
          "message": "Merge pull request #713 from kaappi/fix/hashtable-sentinel-collision-694\n\nFix hash-table sentinel collision with eof-object and void keys",
          "timestamp": "2026-07-02T10:40:12+05:30",
          "tree_id": "abbe7a3755221e840f2b00ce930bf93327c9c812",
          "url": "https://github.com/kaappi/kaappi/commit/2b55a6ac19f20f5eb3ba31f1090fef824df0c06b"
        },
        "date": 1782970616461,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.904355,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.588297,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.848322,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.168177,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007386,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032332,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.452034,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.067948,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.850046,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.743418,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.091241,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.244286,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.389366,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.740639,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043103,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "119d2f057f87667db107c711e28eed4acebcbc7f",
          "message": "Merge pull request #716 from kaappi/fix/read-bytevector-zero-length-692\n\nFix read-bytevector! EOF for zero-length target and bytevector I/O error names",
          "timestamp": "2026-07-02T10:47:02+05:30",
          "tree_id": "7022207f36d8c890e5c016f4e141b0c4a97b5b29",
          "url": "https://github.com/kaappi/kaappi/commit/119d2f057f87667db107c711e28eed4acebcbc7f"
        },
        "date": 1782971998637,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.488639,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.810527,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.820538,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.226829,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006879,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.033398,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.460122,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.071936,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.939321,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.817539,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.103509,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.219614,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.408188,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.687591,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.041518,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "b5a077358582849709fea43257902939c349698b",
          "message": "Merge pull request #717 from kaappi/fix/json-escape-control-chars-677\n\nFix writeJsonEscaped: escape 0x08 and 0x0C control characters",
          "timestamp": "2026-07-02T10:50:06+05:30",
          "tree_id": "8f491fe7960f90dc9354c4561cc4f77d05c5ed62",
          "url": "https://github.com/kaappi/kaappi/commit/b5a077358582849709fea43257902939c349698b"
        },
        "date": 1782972850658,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.327907,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.675051,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.836993,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.177766,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006884,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032126,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.452673,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068768,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.874466,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.755155,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.089725,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.222873,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.438837,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.690909,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042019,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "569a55db25571ba8d9d014e3a4871f18aa973ee5",
          "message": "Merge pull request #718 from kaappi/fix/passthrough-constfold-redefine-698\n\nFix passthrough constant folding: check globals for redefined primitives",
          "timestamp": "2026-07-02T10:57:31+05:30",
          "tree_id": "7c41554685134b422db2400203ddc5deddd96bf2",
          "url": "https://github.com/kaappi/kaappi/commit/569a55db25571ba8d9d014e3a4871f18aa973ee5"
        },
        "date": 1782972939744,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.34031,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.314336,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.819156,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.187156,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00694,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032848,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.453645,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068981,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.958149,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.75712,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.104057,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.225479,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.425849,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.562052,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042347,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "d0f85fcae74b35d5dc7a4baa1222bc49b8192387",
          "message": "Merge pull request #721 from kaappi/fix/get-env-vars-696\n\nImplement get-environment-variables using POSIX environ",
          "timestamp": "2026-07-02T11:04:14+05:30",
          "tree_id": "a7902f9c0f812e825be41b13b1d2bcb95a87c3c6",
          "url": "https://github.com/kaappi/kaappi/commit/d0f85fcae74b35d5dc7a4baa1222bc49b8192387"
        },
        "date": 1782972958611,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.324692,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.655496,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.835694,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.259524,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00688,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032545,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.461962,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069816,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.907574,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.780093,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.103295,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.224936,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.43122,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.65074,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042757,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "6d80cab547a1ac34036296c0a88ea4033fe5639d",
          "message": "Merge pull request #719 from kaappi/fix/prescan-names-overflow-686\n\nFix internal-define pre-scan: use dynamic list instead of fixed 64-entry buffer",
          "timestamp": "2026-07-02T11:07:58+05:30",
          "tree_id": "8fd2f289d405c5a2c6b66fe934382620f66495fe",
          "url": "https://github.com/kaappi/kaappi/commit/6d80cab547a1ac34036296c0a88ea4033fe5639d"
        },
        "date": 1782972969901,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.327602,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.041099,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.835998,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.203009,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00698,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032485,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.457338,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069767,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.839675,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.77709,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.105783,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.225499,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.43747,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.737176,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042446,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "e54a2d23b860946a17d57683ed621556f3729589",
          "message": "Merge pull request #715 from kaappi/fix/circular-list-hang-688\n\nAdd cycle detection to member/memq/memv/assoc/assq/assv/list-copy",
          "timestamp": "2026-07-02T11:13:13+05:30",
          "tree_id": "16788ceebd694088996f8c9278cf4283fb535812",
          "url": "https://github.com/kaappi/kaappi/commit/e54a2d23b860946a17d57683ed621556f3729589"
        },
        "date": 1782973351525,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.921309,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.3734,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.832388,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.155947,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007379,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032278,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.450825,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068264,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.854873,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.74271,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.095305,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.242669,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.361999,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.881948,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043365,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "80e7b3d751f8eec80788832aa8196f7d4fb978b0",
          "message": "Merge pull request #722 from kaappi/fix/expander-patvar-limit-683\n\nRaise syntax-rules pattern variable limit from 16 to 128 per ellipsis",
          "timestamp": "2026-07-02T11:15:46+05:30",
          "tree_id": "810a413876f61c91bac8b818bdca386b8858fb78",
          "url": "https://github.com/kaappi/kaappi/commit/80e7b3d751f8eec80788832aa8196f7d4fb978b0"
        },
        "date": 1782973599833,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.960282,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 10.023793,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.840746,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.172997,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007275,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032056,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.451248,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.067672,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.827836,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.741348,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.115467,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.240966,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.375821,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.898095,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043802,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "90c83381759241d4f93f52173925ccfd20265cef",
          "message": "Merge pull request #725 from kaappi/fix/exit-dynamic-wind-693\n\nImplement exit with dynamic-wind cleanup, separate from emergency-exit",
          "timestamp": "2026-07-02T11:22:10+05:30",
          "tree_id": "99f30165d4c0ed7ae1362f2dd276aff0c70529b9",
          "url": "https://github.com/kaappi/kaappi/commit/90c83381759241d4f93f52173925ccfd20265cef"
        },
        "date": 1782973701883,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.287636,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.423517,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.814811,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.180869,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006975,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032785,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.457318,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069607,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.90395,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.772665,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.11521,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.21498,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.42311,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.670272,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.041263,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "36335ad2ed9cfadf9ea44f3a9e259350d5a6bd02",
          "message": "Merge pull request #724 from kaappi/fix/char-alphabetic-unicode-678\n\nFix char-alphabetic? misclassifying non-letter codepoints",
          "timestamp": "2026-07-02T11:24:29+05:30",
          "tree_id": "e85b055822e9c892c2d7ea458849c97add0dc004",
          "url": "https://github.com/kaappi/kaappi/commit/36335ad2ed9cfadf9ea44f3a9e259350d5a6bd02"
        },
        "date": 1782973808704,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.030207,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.652867,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.671522,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.231495,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.005574,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.024902,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.35674,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.052834,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.294255,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.34767,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 0.855895,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.182351,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.833118,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.240076,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.033528,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "46133c006e81d3e3abf8db43256beff72abfd91d",
          "message": "Merge pull request #726 from kaappi/fix/structural-hash-689\n\nAdd structural hashing for pairs, vectors, and bytevectors",
          "timestamp": "2026-07-02T11:24:35+05:30",
          "tree_id": "4b393646e86bc5a21204ddf2ed8a4b7dcb8bff7b",
          "url": "https://github.com/kaappi/kaappi/commit/46133c006e81d3e3abf8db43256beff72abfd91d"
        },
        "date": 1782974131105,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.714941,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.643314,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.750611,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.711641,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006967,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.030901,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.406988,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.066041,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.000084,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.549915,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.085415,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.216572,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.237363,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.904987,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.037933,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "323e984d854c5f921ccd8d5d4754b53ba15ea92b",
          "message": "Merge pull request #727 from kaappi/fix/expander-vector-patterns-680\n\nAdd vector pattern and template support to syntax-rules",
          "timestamp": "2026-07-02T11:54:15+05:30",
          "tree_id": "f1a29fae4502042f768843f1039d83ead8fea57c",
          "url": "https://github.com/kaappi/kaappi/commit/323e984d854c5f921ccd8d5d4754b53ba15ea92b"
        },
        "date": 1782974258453,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.954144,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.766438,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.829511,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.145083,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007849,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032039,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.451203,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.067403,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.886271,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.741466,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.10974,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.246496,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.38319,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.872852,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043795,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "f15af2825abe32111e09b25a570cf6b0ec9d0e5b",
          "message": "Merge pull request #723 from kaappi/fix/numeric-delimiter-679\n\nRequire delimiter after numeric tokens in the reader",
          "timestamp": "2026-07-02T11:59:32+05:30",
          "tree_id": "d691aa5fdc3f166c5d2237371f00edbb52a2636f",
          "url": "https://github.com/kaappi/kaappi/commit/f15af2825abe32111e09b25a570cf6b0ec9d0e5b"
        },
        "date": 1782974629744,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.330465,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.096297,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.814762,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.167139,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00693,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032303,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.454818,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069942,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.867841,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.769717,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.107189,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.21507,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.428716,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.594102,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.041709,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "11e3cccbbe539bee168523445bb75fc68ee9ab0a",
          "message": "Merge pull request #720 from kaappi/fix/command-line-format-697\n\nFix command-line: remove hardcoded \"kaappi\" prefix",
          "timestamp": "2026-07-02T12:04:49+05:30",
          "tree_id": "b53b09a59cc37748324cc5b4435701700dd6d14d",
          "url": "https://github.com/kaappi/kaappi/commit/11e3cccbbe539bee168523445bb75fc68ee9ab0a"
        },
        "date": 1782974910169,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.303431,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.50892,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.825011,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.255863,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006851,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032512,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.455483,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070449,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.872771,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.769234,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.078942,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.217725,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.435021,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.706069,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042179,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "bce120a495603e1296c4ad52ec3be36cdd7f91d1",
          "message": "Merge pull request #728 from kaappi/fix/hygiene-well-known-bindings-681\n\nFix macro hygiene for template-introduced bindings named after built-ins",
          "timestamp": "2026-07-02T14:12:10+05:30",
          "tree_id": "1ad6232abd759deea54f27668b2b15098e599c8e",
          "url": "https://github.com/kaappi/kaappi/commit/bce120a495603e1296c4ad52ec3be36cdd7f91d1"
        },
        "date": 1782982554482,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.307495,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.579283,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.825794,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.132175,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00692,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032201,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.453717,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069841,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.923879,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.78038,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.079902,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.225037,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.39964,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.705803,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.041668,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "73c0bab53400bb072684a5768e26dbcdcf51e135",
          "message": "Merge pull request #730 from kaappi/fix/ellipsis-depth-validation-682\n\nAdd ellipsis-depth validation to syntax-rules templates",
          "timestamp": "2026-07-02T14:40:08+05:30",
          "tree_id": "2913bdb77264d05071ba4c306daac5a9ac329fa7",
          "url": "https://github.com/kaappi/kaappi/commit/73c0bab53400bb072684a5768e26dbcdcf51e135"
        },
        "date": 1782984262721,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.33364,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.102242,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.846822,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.201585,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007292,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032408,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.453551,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070508,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.994749,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.777488,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.104595,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.22921,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.442369,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.710963,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.041644,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "9039b9bd31be2839d4d94f03cf2d1c8865e4bc49",
          "message": "Merge pull request #731 from kaappi/fix/eval-environment-691\n\nImplement eval environment-specifier and environment procedures",
          "timestamp": "2026-07-02T14:57:25+05:30",
          "tree_id": "44d3f4307a639523d56d29c821d44d41bb627170",
          "url": "https://github.com/kaappi/kaappi/commit/9039b9bd31be2839d4d94f03cf2d1c8865e4bc49"
        },
        "date": 1782985337449,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.025842,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.909044,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.854735,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.17815,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007281,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032198,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.45158,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.067721,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.875921,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.769721,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.097727,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.248871,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.466544,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.737687,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044111,
            "unit": "seconds"
          }
        ]
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
          "id": "de6afd864d587eb35eb6e1e8d525f833f1c27a35",
          "message": "Release v0.11.0",
          "timestamp": "2026-07-02T15:05:08+05:30",
          "tree_id": "120134b6fdec50039ce1da42ada0b6a0ec160d6b",
          "url": "https://github.com/kaappi/kaappi/commit/de6afd864d587eb35eb6e1e8d525f833f1c27a35"
        },
        "date": 1782985770621,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.037128,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.982089,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.8612,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.203038,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007489,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032064,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.451859,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.067689,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.920175,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.769728,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.094357,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.247221,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.444686,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.912491,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043651,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "e105a9f4ed1e58cacf4f45630cd67cc59aa0d4dc",
          "message": "Split large source files to stay within 1500-line policy (#732)\n\nExtract self-contained subsystems from main.zig, ir.zig, and memory.zig\ninto dedicated files, following existing codebase patterns:\n\n- main.zig (1493→1173): LLVM emission + native compilation → native_compiler.zig\n- ir.zig (1457→1178): standalone bytecode Emitter → ir_emitter.zig\n- memory.zig (1435→1213): cross-thread deep copy → gc_deep_copy.zig\n\nAll public APIs preserved via re-exports or delegation. CLAUDE.md file\ntables updated to document new files.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-02T15:57:56+05:30",
          "tree_id": "e81cd64a09c4f6743f7fdcef54a38ef0eaa3b5f5",
          "url": "https://github.com/kaappi/kaappi/commit/e105a9f4ed1e58cacf4f45630cd67cc59aa0d4dc"
        },
        "date": 1782988957020,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.335063,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.210927,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.797634,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.130767,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006827,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032267,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.448133,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069358,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.967179,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.772818,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.117854,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.222577,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.399284,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.663396,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.041447,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "11739e2d8f83563d62d431af12ca2558f9a699f4",
          "message": "Merge pull request #762 from kaappi/fix/750-symbol-table-data-race\n\nFix data race in symbol table marking during SRFI-18 threading",
          "timestamp": "2026-07-02T16:54:09+05:30",
          "tree_id": "d6260db0f9ff20357c0d434e0069cedb0a3ea709",
          "url": "https://github.com/kaappi/kaappi/commit/11739e2d8f83563d62d431af12ca2558f9a699f4"
        },
        "date": 1782992318822,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.347325,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.167486,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.809202,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.154391,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006924,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032776,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.452729,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068688,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.054155,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.780425,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.106407,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.215237,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.404556,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.544435,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.040424,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "6d1e35accd69ed91ce79ba44a6c2c3fcbbdd7c57",
          "message": "Merge pull request #763 from kaappi/fix/747-gc-safety-rational-arithmetic\n\nFix GC safety violations in rational arithmetic paths",
          "timestamp": "2026-07-02T17:14:22+05:30",
          "tree_id": "619bc395fdb30a3c2812ef9135b5c674ee5a90be",
          "url": "https://github.com/kaappi/kaappi/commit/6d1e35accd69ed91ce79ba44a6c2c3fcbbdd7c57"
        },
        "date": 1782993445225,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.14574,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.149654,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.650383,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.039568,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00568,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.024568,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.354096,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.052425,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.297497,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.346018,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 0.862947,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.193276,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.854496,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.379998,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.036411,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "1540b39536391575d0f671e702697255006a5802",
          "message": "Merge pull request #764 from kaappi/fix/738-bytecode-vector-write-barrier\n\nAdd GC write barrier in vector constant deserialization",
          "timestamp": "2026-07-02T17:31:19+05:30",
          "tree_id": "cc832526386d8d7968402cbd8c477d7875c66cf4",
          "url": "https://github.com/kaappi/kaappi/commit/1540b39536391575d0f671e702697255006a5802"
        },
        "date": 1782994519225,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.360054,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.764725,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.843077,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.528675,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007107,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032022,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.453924,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070386,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.975268,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.773088,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.083003,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.227958,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.43747,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.660326,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043486,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "a38fe8d5a148b2c7a296ca28259b911d3a5b1854",
          "message": "Merge pull request #765 from kaappi/fix/754-757-759-vm-library-gc-safety\n\nFix GC safety in vm_library: root AST, write barrier, root includes",
          "timestamp": "2026-07-02T17:48:48+05:30",
          "tree_id": "755a3f7d38f9284b25ff895f589fe83fa91ab87b",
          "url": "https://github.com/kaappi/kaappi/commit/a38fe8d5a148b2c7a296ca28259b911d3a5b1854"
        },
        "date": 1782995546353,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.38308,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.269825,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.79666,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.179318,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007103,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.03232,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.452496,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069126,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.949517,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.752596,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.109162,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.224448,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.398286,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.677412,
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
          "id": "a0cb415334eb05681c0eb7629e5abcfacb2ed3c2",
          "message": "Merge pull request #766 from kaappi/fix/758-let-syntax-malformed-binding\n\nValidate let-syntax bindings have transformer spec",
          "timestamp": "2026-07-02T17:59:59+05:30",
          "tree_id": "6f38bfc11e1c0eaa62f1e4954670f65dcfe1986d",
          "url": "https://github.com/kaappi/kaappi/commit/a0cb415334eb05681c0eb7629e5abcfacb2ed3c2"
        },
        "date": 1782996239276,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.085542,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.63492,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.842555,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.236986,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007354,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.03174,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.449683,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068463,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.882544,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.731987,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.095151,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.245178,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.414579,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.893307,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043625,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "de46a5001f4fd585b2596aead08cba71c31d13df",
          "message": "Merge pull request #767 from kaappi/fix/753-deep-copy-visited-registration\n\nFix deep copy: register in visited before recursing, use allocMultipleValues",
          "timestamp": "2026-07-02T18:17:16+05:30",
          "tree_id": "62a0c97808338975e655c5a4c6858174e46e84a7",
          "url": "https://github.com/kaappi/kaappi/commit/de46a5001f4fd585b2596aead08cba71c31d13df"
        },
        "date": 1782997261934,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.512465,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.516953,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.830673,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.174437,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006966,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032003,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.452539,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.06979,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.936718,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.777235,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.086369,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.229303,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.392614,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.728887,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.0414,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "ea840f439ac4c086033bb4a1fc54034a1540500c",
          "message": "Merge pull request #768 from kaappi/fix/739-bignum-division-remaining-args\n\nFix multi-arg bignum division to process all divisors",
          "timestamp": "2026-07-02T18:35:10+05:30",
          "tree_id": "63218596afcc16a46c3a664f8217272fdd71d167",
          "url": "https://github.com/kaappi/kaappi/commit/ea840f439ac4c086033bb4a1fc54034a1540500c"
        },
        "date": 1782998438013,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.852748,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.451669,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.769898,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.874245,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007058,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.031236,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.415919,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.066316,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.977299,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.654523,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.066534,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.220076,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.287624,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.963797,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.04018,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "c39666762db2fce8d1112de933b858c9eade4733",
          "message": "Merge pull request #769 from kaappi/fix/741-toRationalParts-type-check\n\nFix toRationalParts to return null for non-numeric types",
          "timestamp": "2026-07-02T18:52:33+05:30",
          "tree_id": "d7216b929b5c8661be7c90a9d542ec7036c9e32a",
          "url": "https://github.com/kaappi/kaappi/commit/c39666762db2fce8d1112de933b858c9eade4733"
        },
        "date": 1782999429981,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.07035,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.499165,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.837135,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.20506,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007413,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.031991,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.453595,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.067819,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.847524,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.739223,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.094877,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.24348,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.405332,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.872201,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043396,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "0f6077ea8bf113f90d448599d502f4c41e7828e0",
          "message": "Merge pull request #770 from kaappi/fix/744-749-minint-negation-overflow\n\nFix minInt negation overflow in abs, unary minus, and magnitude",
          "timestamp": "2026-07-02T19:10:16+05:30",
          "tree_id": "fb9a02317f492691012d5e424dcc231d0911451f",
          "url": "https://github.com/kaappi/kaappi/commit/0f6077ea8bf113f90d448599d502f4c41e7828e0"
        },
        "date": 1783000503746,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.378545,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.63294,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.7967,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.210395,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007019,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.031866,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.455989,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070265,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.900664,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.769213,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.091136,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.217188,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.398314,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.657373,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042194,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "f7c3a7b05060c2d04a565d4ed971a9240d4da0ba",
          "message": "Merge pull request #771 from kaappi/fix/748-angle-negative-zero\n\nFix angle to return pi for -0.0",
          "timestamp": "2026-07-02T19:27:54+05:30",
          "tree_id": "021d599d05b36c3c27701aa3a21eea631fca32a7",
          "url": "https://github.com/kaappi/kaappi/commit/f7c3a7b05060c2d04a565d4ed971a9240d4da0ba"
        },
        "date": 1783001554990,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.418419,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.042608,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.805739,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.274766,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006919,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.03177,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.454665,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070073,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.924884,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.762921,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.093588,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.218324,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.395217,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.591051,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.04061,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "884c76b23c5e45d279aa0485f4ee6fe02b9a8804",
          "message": "Merge pull request #772 from kaappi/fix/752-two-arg-log-negative\n\nFix two-argument log to return complex for negative first argument",
          "timestamp": "2026-07-02T19:45:23+05:30",
          "tree_id": "59bb21beffcb966c0041a7ab81be88c9a6178183",
          "url": "https://github.com/kaappi/kaappi/commit/884c76b23c5e45d279aa0485f4ee6fe02b9a8804"
        },
        "date": 1783002653956,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.396435,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.468965,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.805278,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.203312,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006895,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.03182,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.453741,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069901,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.94429,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.765651,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.089122,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.220136,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.388811,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.622514,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.040907,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "17f47a2540e2ca89dfe4f47df1d235c2e08f05e8",
          "message": "Merge pull request #773 from kaappi/fix/756-760-761-compiler-bugs\n\nFix three compiler bugs: constant limit, apply upvalue, no_collect leak",
          "timestamp": "2026-07-02T20:03:07+05:30",
          "tree_id": "a71b89af1f089d7db1a8720a3a4ca7216613d72e",
          "url": "https://github.com/kaappi/kaappi/commit/17f47a2540e2ca89dfe4f47df1d235c2e08f05e8"
        },
        "date": 1783003655452,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.40733,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.158243,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.817077,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.166064,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006906,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032026,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.451482,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068845,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.956683,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.755262,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.125567,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.229886,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.403078,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.72918,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043533,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "e9909f1ffcb729c2614e06e668bcedb15ebb642f",
          "message": "Merge pull request #774 from kaappi/fix/746-rational-bignum-exact\n\nFix exact rational + bignum arithmetic to preserve exactness",
          "timestamp": "2026-07-02T20:21:24+05:30",
          "tree_id": "d1f9378b75af74cc2c16ce1f4464d3e0449bc0ac",
          "url": "https://github.com/kaappi/kaappi/commit/e9909f1ffcb729c2614e06e668bcedb15ebb642f"
        },
        "date": 1783004654699,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.189668,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.256914,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.666391,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.039243,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006163,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.02451,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.357061,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.053106,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.328882,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.35112,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 0.84503,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.193858,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.855652,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.41965,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.034633,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "763b7528ccb59a790ae8727ee4ad0e9dd7774831",
          "message": "Merge pull request #775 from kaappi/fix/751-string-to-number-complex-exactness\n\nApply exactness prefix to complex number parsing in string->number",
          "timestamp": "2026-07-02T20:39:06+05:30",
          "tree_id": "aa7f4be8f333f8ae16a5462c00a2c4bac92b396e",
          "url": "https://github.com/kaappi/kaappi/commit/763b7528ccb59a790ae8727ee4ad0e9dd7774831"
        },
        "date": 1783005796626,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.368776,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.691094,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.831147,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.182093,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007054,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032879,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.450923,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068754,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.938963,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.747131,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.141208,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.228016,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.397006,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.657555,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042149,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "7e8e606ae76f0c5a8a0bc265b9862e9dd4cfd53e",
          "message": "Merge pull request #776 from kaappi/fix/743-745-bytecode-file-bugs\n\nFix bytecode serialization: handle EOF/UNDEFINED, fix test header",
          "timestamp": "2026-07-02T20:56:50+05:30",
          "tree_id": "e1b026e7a1ac8180e2037e31593b170ef317e369",
          "url": "https://github.com/kaappi/kaappi/commit/7e8e606ae76f0c5a8a0bc265b9862e9dd4cfd53e"
        },
        "date": 1783006889149,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.077227,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.322485,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.839034,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.407076,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.008165,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.0319,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.454301,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.067627,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.94721,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.773229,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.091379,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.235536,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.384362,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.82369,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043503,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "854b35b7f6522af703227e8b49a7c8166a4495dc",
          "message": "Merge pull request #777 from kaappi/fix/733-737-thottam-bugs\n\nFix five thottam package manager bugs",
          "timestamp": "2026-07-02T21:13:43+05:30",
          "tree_id": "29aee9861549401d66870157c62d962cf23450ff",
          "url": "https://github.com/kaappi/kaappi/commit/854b35b7f6522af703227e8b49a7c8166a4495dc"
        },
        "date": 1783007799776,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.343166,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.093269,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.813548,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.239676,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007042,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032993,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.454665,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068651,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.905666,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.766579,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.133409,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.216254,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.394627,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.664218,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.041276,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "366d47d5e827132ae5567a1b31a14ed27e7e61ef",
          "message": "Merge pull request #778 from kaappi/fix/740-cli-missing-arg-validation\n\nReport missing arguments for CLI flags",
          "timestamp": "2026-07-02T21:30:37+05:30",
          "tree_id": "4f64ee65a07a9ab4c76c076a35b40692909d33f7",
          "url": "https://github.com/kaappi/kaappi/commit/366d47d5e827132ae5567a1b31a14ed27e7e61ef"
        },
        "date": 1783008815973,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.371873,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.579844,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.835918,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.130124,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00711,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.033114,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.450807,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068561,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.951821,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.76098,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.134204,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.219826,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.380485,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.662825,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043641,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "ad1c37212a50379cd6b03ecad6290810162c055f",
          "message": "Merge pull request #779 from kaappi/fix/742-repl-ctrl-c-behavior\n\nMake REPL Ctrl-C show fresh prompt instead of exiting",
          "timestamp": "2026-07-02T21:47:02+05:30",
          "tree_id": "61cc331d48db0517dafdf8b028a391bba45ae0cc",
          "url": "https://github.com/kaappi/kaappi/commit/ad1c37212a50379cd6b03ecad6290810162c055f"
        },
        "date": 1783009898118,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.333023,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.247848,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.803822,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.094411,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006928,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032159,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.449361,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068566,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.925906,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.748824,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.161697,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.220219,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.377162,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.668132,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.040597,
            "unit": "seconds"
          }
        ]
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
          "id": "716416be7f38d1b262ba8d3c309380dd31487490",
          "message": "Release v0.11.1",
          "timestamp": "2026-07-02T21:53:21+05:30",
          "tree_id": "00bc94f4ee21f03a8a979e47f07ca508b92afd1a",
          "url": "https://github.com/kaappi/kaappi/commit/716416be7f38d1b262ba8d3c309380dd31487490"
        },
        "date": 1783010308906,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.072728,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.366358,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.839702,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.186237,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007323,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.031861,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.456099,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068133,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.907205,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.747278,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.087109,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.237555,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.397501,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.841148,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043805,
            "unit": "seconds"
          }
        ]
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
          "id": "d46986f0d06ba330f89809acc9eb2ba13d60a863",
          "message": "Update release skill for mkdocs-macros version sync\n\nStep 4 now bumps kaappi_version in mkdocs.yml instead of\nediting download.md directly. Step 10 stages mkdocs.yml.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-02T22:07:19+05:30",
          "tree_id": "cb9fdbf0b29243fc431bd0802ff024e5dd00db64",
          "url": "https://github.com/kaappi/kaappi/commit/d46986f0d06ba330f89809acc9eb2ba13d60a863"
        },
        "date": 1783011105296,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.355773,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.027501,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.84185,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.096089,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007027,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.03351,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.452477,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069574,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.954109,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.749107,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.153937,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.229201,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.41425,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.832269,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043391,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "147f66f56a1685e95dcefa43daf54f7f19fbceaa",
          "message": "Root intermediate values across allocations in primitives_numeric.zig (#861) (#881)\n\nMultiple functions held unrooted heap Values across GC-triggering\nallocations — if maybeCollect fired between allocations, the earlier\nvalues were swept, leading to corrupted rationals or crashes under\nmemory pressure. Fixed by registering intermediates in gc.extra_roots\nbefore any subsequent allocation.\n\nFunctions fixed: rationalFloor, rationalCeiling, rationalRound, exactFn\n(flonum and complex branches), exptFn (rational branch), squareFn\n(rational branch), exactIntegerSqrt (bignum branch — Newton loop,\ndownward/upward adjustments, final allocMultipleValues), floorQuotient,\nfloorRemainder, floorDivide, and truncateDivide.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-03T00:00:31+05:30",
          "tree_id": "3cba80bc878b319aa95456dad45bf8fbf908bd64",
          "url": "https://github.com/kaappi/kaappi/commit/147f66f56a1685e95dcefa43daf54f7f19fbceaa"
        },
        "date": 1783017905847,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.09884,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.475029,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.84557,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.189513,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007462,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.03183,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.456783,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.067662,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.844206,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.741782,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.093629,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.238195,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.39618,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.772031,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044159,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "866067e364b0fa542fa0cc06997dbdf09e786461",
          "message": "Replace fixed-size export arrays with dynamic ArrayLists in define-library (#862) (#882)\n\nThe 128-entry stack arrays for export_names/export_renames silently\ndropped any exports past the cap. Libraries with >128 exports (like\nscheme.base with ~250) would lose the tail entries. Switched to\nstd.ArrayList in handleDefineLibrary, extractExportsAndImports, and\nincludeLibraryDeclarations so libraries can export arbitrarily many\nidentifiers.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-03T00:24:42+05:30",
          "tree_id": "dda475e06f7ca2629270f144d62ce82d9e55cf6f",
          "url": "https://github.com/kaappi/kaappi/commit/866067e364b0fa542fa0cc06997dbdf09e786461"
        },
        "date": 1783019374925,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.371118,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.471331,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.80772,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.162128,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006806,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032052,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.450735,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069982,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.927631,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.76315,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.080364,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.221564,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.391285,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.683312,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.041081,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "222eafcfd8a9cff9f764c1b2c2547da070f1d6f4",
          "message": "Add missing separator before dotted tail in pretty-printer (#863) (#883)\n\nppValue's dotted-tail branch wrote \". \" directly after the previous\nelement with no newline/indent, fusing the dot with the preceding\ntoken (e.g. \"symbol. 3\" reads back as symbol \"symbol.\" not a dotted\npair). Now emits newline + indent before \". \" in multi-line mode,\nmatching the separator used between regular elements.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-03T00:45:18+05:30",
          "tree_id": "8ffd81145d011c120ce207432ffd24877a0d38ac",
          "url": "https://github.com/kaappi/kaappi/commit/222eafcfd8a9cff9f764c1b2c2547da070f1d6f4"
        },
        "date": 1783020595048,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.404462,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.504334,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.80948,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.185307,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007149,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.03207,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.453482,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069728,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.025847,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.776839,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.093213,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.217169,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.400619,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.522748,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.04132,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "53f786ed3b11e852dbfbe635aa7bab297ba25e03",
          "message": "Trace environment Value in Function/Transformer to prevent use-after-free (#867) (#884)\n\nFunction.env stores a raw pointer to a SchemeEnvironment's hashmap, but\nmarkValue never traced the SchemeEnvironment — once unreachable, the GC\nfreed the map while live closures still referenced it. Add env_val (and\ndef_env_val for Transformer) fields that hold the GC-managed Value, and\ntrace them in all three marking functions (hasYoungRefs, minor-GC, full-GC).\n\nFixes #867\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-03T01:21:21+05:30",
          "tree_id": "af4b54c2a6c8f12f5aa32452a9d53a285bc32113",
          "url": "https://github.com/kaappi/kaappi/commit/53f786ed3b11e852dbfbe635aa7bab297ba25e03"
        },
        "date": 1783022721663,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.319565,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.644688,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.812332,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.146265,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00692,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.03233,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.454222,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.07002,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.926441,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.753928,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.089639,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.221289,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.399843,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.712467,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.041505,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "269901be085746ed594e744f23d904725f697071",
          "message": "Root bignum intermediates in Euclid loops to prevent use-after-free (#843) (#885)\n\nThe GCD loops in gcdFn, makeRationalReduced, and lcmFn held unrooted\nbignum intermediates across allocating bignum_mod calls. When GC\ntriggered inside the loop, freed limbs produced silently wrong results\nat default threshold. Root b_val/abs_num/g via extra_roots and keep\nthem updated each iteration.\n\nFixes #843\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-03T01:41:10+05:30",
          "tree_id": "a738630ff194b19440b7d7fe3b84ad97872bd8ea",
          "url": "https://github.com/kaappi/kaappi/commit/269901be085746ed594e744f23d904725f697071"
        },
        "date": 1783023954364,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.403191,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.378606,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.811537,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.144946,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006977,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032222,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.453859,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069819,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.93457,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.748918,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.150095,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.217368,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.418883,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.702608,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042165,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "455db2bdddd72f0f313327e8dd1afa1ab0bafa84",
          "message": "Clean up child function roots after single-expression compilation (#832) (#886)\n\ninitChild appends every child function (one per lambda, case-lambda\nclause, delay, named-let) to gc.extra_roots, but nothing removed\nthem on the single-expression compile path. Record extra_roots.len\nafter Compiler.init and shrink back in the defer block of all three\ncompileExpression* wrappers, matching the pattern compileMultiple\nalready uses.\n\nFixes #832\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-03T01:41:15+05:30",
          "tree_id": "695f7869f0bef39914dcb69ecd79a78b60df1b3d",
          "url": "https://github.com/kaappi/kaappi/commit/455db2bdddd72f0f313327e8dd1afa1ab0bafa84"
        },
        "date": 1783023962013,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.310725,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.384861,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.830756,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.468741,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00704,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.031824,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.458402,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070224,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.916975,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.778384,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.082814,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.216779,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.415502,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.684399,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.040961,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "d4f638ead29755f8a0dae005a29957b70f414d57",
          "message": "Fix round on negative exact rationals with fraction < 1/2 (#837) (#888)\n\nWhen 2*|remainder| < denominator the closest integer is the truncated\nquotient q for both signs. The cmp<0 branch incorrectly subtracted 1\nfor negative remainders, rounding away from zero.\n\nFixes #837\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-03T01:59:08+05:30",
          "tree_id": "fd03601f3c439f87a8b51e4cd08e32227be3aa60",
          "url": "https://github.com/kaappi/kaappi/commit/d4f638ead29755f8a0dae005a29957b70f414d57"
        },
        "date": 1783025724402,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.117446,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.844013,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.84776,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.202937,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.008186,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032679,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.452491,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.06913,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.867547,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.724983,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.108497,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.249494,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.420686,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.884664,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044678,
            "unit": "seconds"
          }
        ]
      }
    ]
  }
}