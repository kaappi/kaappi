window.BENCHMARK_DATA = {
  "lastUpdate": 1782842037625,
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
      }
    ]
  }
}