window.BENCHMARK_DATA = {
  "lastUpdate": 1782851543644,
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
      }
    ]
  }
}