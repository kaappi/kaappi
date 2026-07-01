window.BENCHMARK_DATA = {
  "lastUpdate": 1782892143375,
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
          "id": "9389e58b92ee69dd09d59623e9bcc6898fa89b4b",
          "message": "Add PR-level benchmark comparison for pre-merge regression detection (#599)\n\nNew workflow that runs benchmarks on both the PR and base branches,\ncompares results, and posts a delta table as a PR comment. Triggered\nby path filter (src/, benchmarks/, lib/, build.zig) to avoid running\non documentation-only changes.\n\nUses pull_request event (not pull_request_target) so fork PRs run\nwith restricted permissions and cannot write to gh-pages or access\nsecrets. Alert threshold set to 120% (flags >20% regression).\n\nCloses #582\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-06-30T23:14:47+05:30",
          "tree_id": "40f37ec43a1eb6b0120002681e9e45e6bbae7112",
          "url": "https://github.com/kaappi/kaappi/commit/9389e58b92ee69dd09d59623e9bcc6898fa89b4b"
        },
        "date": 1782842031039,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.338687,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.090262,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.795991,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.060658,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006846,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032831,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.447573,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 1.148255,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.904042,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.760621,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.089642,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.21578,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.392735,
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
          "id": "109291ce99338f973d034c3397af17c69dce3b30",
          "message": "Add benchmarks for continuations, tail calls, closures, bignum, and GC pressure (#598)\n\nFive new benchmarks covering previously untested runtime subsystems:\n- continuations: call/cc capture/restore throughput (5M iterations)\n- tailcall: deep tail-recursive loop (10M iterations)\n- closures: closure allocation via map over 1000-element lists (10K rounds)\n- bignum: factorial(5000) with number->string conversion (bignum multiply chain)\n- gc-pressure: rapid short-lived pair allocation forcing minor collections (5M allocs)\n\nAll use the run-r7rs-benchmark harness with warmup and 5 measured runs.\n\nCloses #580\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-06-30T23:04:15+05:30",
          "tree_id": "2fbc82367c781549f3f30bff7cd15932e7036c88",
          "url": "https://github.com/kaappi/kaappi/commit/109291ce99338f973d034c3397af17c69dce3b30"
        },
        "date": 1782842037013,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.343036,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.235963,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.797175,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.384075,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006815,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032683,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.448382,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 1.14746,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.90711,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.760479,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.099905,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.216578,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.396056,
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
          "id": "3b2b51372d2c049c8f6ad839dd6fb9560c719534",
          "message": "Update benchmark dev docs with full suite and CI integration\n\nRewrite the benchmarks section in docs/dev/testing.md to cover:\n- All 13 Scheme benchmarks with subsystem and purpose\n- run-benchmarks.sh usage (table and JSON modes)\n- compare-benchmarks.sh for local comparison\n- CI integration (push-to-main trend tracking, PR comparison)\n- Trend dashboard URL and how to read the charts\n- Guide for interpreting results (noise, step changes)\n- How to add a new benchmark\n\nAlso update CI table to include benchmark-pr workflow.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-06-30T23:17:13+05:30",
          "tree_id": "37ff5acf7c9c3fe7d7c7d9eb4212525cfb807875",
          "url": "https://github.com/kaappi/kaappi/commit/3b2b51372d2c049c8f6ad839dd6fb9560c719534"
        },
        "date": 1782842275451,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.940598,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.868951,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.826699,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.108899,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007276,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.03188,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.445979,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 1.265317,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.832364,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.711074,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.101515,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.235368,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.364011,
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
          "id": "963547cf2dcb3cf78ad5e7052878bdd2a4e6c729",
          "message": "Add benchmark dashboard link to README and fix URL in dev docs\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-06-30T23:32:10+05:30",
          "tree_id": "b2f63cfbcc856b8e088c0265c056c1039eb2b9bd",
          "url": "https://github.com/kaappi/kaappi/commit/963547cf2dcb3cf78ad5e7052878bdd2a4e6c729"
        },
        "date": 1782843206991,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.051828,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.077453,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.644783,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.974102,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.005621,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.025354,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.347045,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.982734,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.308706,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.342052,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 0.858158,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.190826,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.832203,
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
          "id": "e501abd013ff28300824795ababd844a55a7670d",
          "message": "Release v0.9.0",
          "timestamp": "2026-06-30T23:42:35+05:30",
          "tree_id": "21ca6be188ade515c0a695b530d1770a658b000f",
          "url": "https://github.com/kaappi/kaappi/commit/e501abd013ff28300824795ababd844a55a7670d"
        },
        "date": 1782843858252,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.34165,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.614339,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.825836,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.076773,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00692,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032896,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.44738,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 1.149978,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.923137,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.761287,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.101479,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.225567,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.398376,
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
      }
    ]
  }
}