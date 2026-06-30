window.BENCHMARK_DATA = {
  "lastUpdate": 1782855482381,
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
      }
    ]
  }
}