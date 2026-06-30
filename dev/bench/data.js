window.BENCHMARK_DATA = {
  "lastUpdate": 1782862240243,
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
      }
    ]
  }
}