window.BENCHMARK_DATA = {
  "lastUpdate": 1783106874088,
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
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "20b4516b495e2a829f17a5cb94014c8605bb8d51",
          "message": "Evaluate parameterize param expressions exactly once (#860) (#887)\n\ncompileParameterize spliced each raw param expression into five places\nin the desugared let form: save old, set with converter, read back,\nbefore-thunk, and after-thunk. Introduce a %pp_i binding per parameter\nin a let* that evaluates the param expression once and references the\nbinding variable in all five positions.\n\nFixes #860\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-03T02:05:31+05:30",
          "tree_id": "766f94654d34c7260e9cd3abedbd43cde3a0e9c2",
          "url": "https://github.com/kaappi/kaappi/commit/20b4516b495e2a829f17a5cb94014c8605bb8d51"
        },
        "date": 1783026866492,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.063376,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.999015,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.835107,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.14628,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007199,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032289,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.452291,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068119,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.945214,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.721822,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.084664,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.234821,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.3705,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.813472,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043652,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "937a1d2a715d559fbcb980e278ddec71776067d0",
          "message": "Allow empty datum list in case clauses (#854) (#889)\n\nR7RS grammar permits case clauses with an empty datum list like\n(() body). Previously Kaappi rejected these with a syntax error because\nthe isPair check fails on NIL. The clause can never match, so the fix\nsimply skips it as dead code.\n\nFixes #854\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-03T02:05:19+05:30",
          "tree_id": "be8af94f2dc3a83005d93e91245e6e5ccdfe7b6f",
          "url": "https://github.com/kaappi/kaappi/commit/937a1d2a715d559fbcb980e278ddec71776067d0"
        },
        "date": 1783026891098,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.303773,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.01428,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.804079,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.310151,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007007,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032367,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.452369,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070263,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.901575,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.753499,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.130232,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.222801,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.425757,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.706817,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.0417,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "c6937e893bde9d615ea926770850867acd84a070",
          "message": "Fix string-replace index clamping and bignum parse error propagation (#830, #835) (#893)\n\n- string-replace now raises IndexOutOfBounds for out-of-range start/end\n  instead of silently clamping to string length (#830)\n- parseBignumString propagates InvalidCharacter distinctly from\n  OutOfMemory so string->number returns #f for invalid bignum strings\n  instead of raising a runtime error (#835)\n\nFixes #830\nFixes #835\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-03T02:06:26+05:30",
          "tree_id": "adf47791ea319346d40671136194a44844af2872",
          "url": "https://github.com/kaappi/kaappi/commit/c6937e893bde9d615ea926770850867acd84a070"
        },
        "date": 1783026968263,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.332108,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.884146,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.83373,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.133959,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006963,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032641,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.450071,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069964,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.882953,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.745723,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.098574,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.234906,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.427971,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.751613,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043265,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "12209c3454b6aba485860910b4e7df46bcb2668e",
          "message": "Validate operand types in quotient/remainder/modulo/gcd bignum paths (#890)\n\n* Fix case-lambda 32-clause limit, case empty datum, case-lambda hygiene (#840, #854, #836)\n\nThree related fixes in compiler_advanced.zig:\n- Replace fixed 32-element clause_buf array with dynamic ArrayList so\n  case-lambda supports any number of clauses (#840)\n- Allow empty datum list (() body) in case clauses as dead code per\n  R7RS grammar (#854)\n- Use unforgeable %cl_args/%cl_n symbols in case-lambda desugaring to\n  avoid capturing user variables named args or n (#836)\n\nFixes #840\nFixes #854\nFixes #836\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Guard bignum branches against flonum and non-number arguments\n\nquotient, remainder, modulo, and gcd had bignum fast-paths that fired\nwhen either operand was a bignum, but assumed the other operand was\nalso a fixnum or bignum.  When the other argument was a flonum, the\ncode called bignum.viewOf which invoked types.toBignum on the flonum,\npanicking.  Non-number arguments (e.g. strings) produced garbage.\n\nFix by adding flonum exclusion guards to the bignum branches in\nquotient/remainder/modulo (matching the pattern already used by the\ndivision operator), and by moving the anyFlonum check before the\nanyBignum check in gcdFn (matching lcmFn).  Also add explicit type\nvalidation for non-number arguments in all four functions' bignum\npaths.\n\nFixes #841\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-03T02:13:57+05:30",
          "tree_id": "b1219ac8d060e75b25a2d8b178e638f59771b049",
          "url": "https://github.com/kaappi/kaappi/commit/12209c3454b6aba485860910b4e7df46bcb2668e"
        },
        "date": 1783027210027,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.300445,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.300335,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.807237,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.14028,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007996,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032351,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.454989,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070767,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.922368,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.753169,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.084636,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.218449,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.387348,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.712753,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.04153,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "892108bb40dc3561e0016a9aae0f2e5f5229a51a",
          "message": "Fix magnitude on rationals and car/cdr type errors in native backend (#865, #834) (#892)\n\n- magnitude on exact rationals now negates the numerator exactly\n  instead of converting through f64, preserving exactness (#865)\n- runtime_exports car/cdr now abort with a type error message instead\n  of silently returning flonum 0.0 for non-pair arguments (#834)\n\nFixes #865\nFixes #834\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-03T02:17:09+05:30",
          "tree_id": "9d5a9f6c275fa8a6aa36ce09558a717ea0082538",
          "url": "https://github.com/kaappi/kaappi/commit/892108bb40dc3561e0016a9aae0f2e5f5229a51a"
        },
        "date": 1783028089079,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.345942,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.090389,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.806245,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.138378,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006904,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.0323,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.454029,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068789,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.955513,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.759864,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.096628,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.21616,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.395455,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.663158,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.04343,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "c0a0804664ec129cc5e99f7b93f395ef19baba17",
          "message": "Fix LSP: MethodNotFound response, hover newlines, dotted define crash (#873, #871, #869) (#895)\n\n- Reply with JSON-RPC MethodNotFound (-32601) for unrecognized request\n  methods instead of silently dropping them (#873)\n- Use actual newline characters in hover markdown instead of escaped\n  literal \\n sequences (#871)\n- Guard types.car calls on define cdr with isPair check to prevent\n  crash on dotted top-level forms like (define . 5) (#869)\n\nFixes #873\nFixes #871\nFixes #869\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-03T02:34:30+05:30",
          "tree_id": "30909a6c0b947aa8b30fc67c8549f93de66673ad",
          "url": "https://github.com/kaappi/kaappi/commit/c0a0804664ec129cc5e99f7b93f395ef19baba17"
        },
        "date": 1783028586069,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.36426,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.513452,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.812944,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.192829,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006941,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032333,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.452686,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068819,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.941414,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.759291,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.087104,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.22229,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.388879,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.709635,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.041606,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "0eff476573dcbb328fd8ea39b9386d85237da6e1",
          "message": "Fix char literal semicolon and string-prefix?/suffix? argument order (#891)\n\n* Fix char literal semicolon and string-prefix?/suffix? argument order (#855, #829)\n\n- Remove trailing semicolon from unnamed control character hex output\n  in write mode — R7RS char literal syntax is #\\xNN, not #\\xNN; (#855)\n- Apply optional start/end arguments to s1 (prefix/suffix string) per\n  SRFI-13, not to s2 (containing string); accept start2/end2 (#829)\n\nFixes #855\nFixes #829\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Update SRFI-13 prefix/suffix tests for corrected argument semantics\n\nThe tests checked the old incorrect behavior where start/end applied\nto s2. Update to match SRFI-13 semantics where start1/end1 apply to s1.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-03T02:42:16+05:30",
          "tree_id": "1e1b448ec750c19a7a55025419bbb1694e3f65e1",
          "url": "https://github.com/kaappi/kaappi/commit/0eff476573dcbb328fd8ea39b9386d85237da6e1"
        },
        "date": 1783029045130,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.815558,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.861914,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.791712,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.723756,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007512,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.031573,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.416428,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.066495,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.954986,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.6286,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.050832,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.218443,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.326961,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.971674,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.039227,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "dc9183c19ca7848b4664588b13f81469f875b1d4",
          "message": "Rewrite rational arithmetic paths to handle bignums without early return (#894)\n\n* Rewrite rational arithmetic paths to handle bignums without early return (#838, #839)\n\nThe rational paths for +, -, *, / used a fixnum-based accumulator that\nreturned early when encountering bignums, dropping remaining arguments.\nReplace with Value-based accumulation using bignum arithmetic throughout,\nso all arguments are processed correctly regardless of type mix.\n\nFixes #838\nFixes #839\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Add bare-ok annotations to rational type guards\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-03T02:42:21+05:30",
          "tree_id": "d1a0cfbc9f8e5ae7b093c664c00aa78b6f42f341",
          "url": "https://github.com/kaappi/kaappi/commit/dc9183c19ca7848b4664588b13f81469f875b1d4"
        },
        "date": 1783029079113,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.437316,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.709914,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.841897,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.174451,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007066,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032841,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.469577,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070812,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.967133,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.788835,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.161677,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.430956,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.405708,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.704534,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.041686,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "bc69689eef0fd88d20cdd4cea88ab4e48ec02543",
          "message": "Fix exact/numerator/denominator abort on flonum 2^63 and bignum rational parsing (#846, #853) (#896)\n\n- Use strict < instead of <= for i64 max comparison in safeFloatToExactInt,\n  floatToRational, and applyExactness — maxInt(i64) rounds up to 2^63 in\n  f64, so the <= check passed but @intFromFloat panicked (#846)\n- Parse rational numerator/denominator with parseBignumString when\n  parseInt overflows i64, instead of falling through to the integer\n  parser which chokes on the '/' (#853)\n\nFixes #846\nFixes #853\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-03T02:47:47+05:30",
          "tree_id": "aa8575a29f44a50750ff782cc0535c3022a09a8d",
          "url": "https://github.com/kaappi/kaappi/commit/bc69689eef0fd88d20cdd4cea88ab4e48ec02543"
        },
        "date": 1783029150176,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.417239,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.352951,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.828206,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.125884,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006926,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032637,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.46679,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070606,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.009012,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.789051,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.149397,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.431986,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.451426,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.68087,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.041852,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "5ede035daed736f88cd83590c4d4854a19b5caa0",
          "message": "Register ,condition in REPL help, tab completion, and usage table (#828) (#899)\n\nThe command worked but was missing from the completion array,\nthe ,help output, and getCommandUsage, so typing ,condition\nwithout args printed \"unknown command\" instead of usage.\n\nFixes #828\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-03T04:37:57+05:30",
          "tree_id": "82c8e837e62d32a73660e90113be3ede5129db6c",
          "url": "https://github.com/kaappi/kaappi/commit/5ede035daed736f88cd83590c4d4854a19b5caa0"
        },
        "date": 1783035164258,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.117737,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.313768,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.848327,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.173514,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007288,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032403,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.466394,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.06869,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.896626,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.77156,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.139014,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.471481,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.394978,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.876987,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044541,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "e90e67a4c69d0278d5e451806e5d65deb3446b21",
          "message": "Fix exact denominator 2^47 wrapping and inexact NaN on huge rationals (#842, #848) (#898)\n\n- Change denominator threshold in exactFn from <= 47 to < 47: 2^47\n  overflows i48 fixnum range, producing a negative denominator (#842)\n- When inexact conversion produces NaN from inf/inf, fall back to\n  bignum quotient+remainder for the correct f64 result (#848)\n\nFixes #842\nFixes #848\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-03T04:37:52+05:30",
          "tree_id": "8f8ef55419cf41e22bc85ec45885d51fb1a31efc",
          "url": "https://github.com/kaappi/kaappi/commit/e90e67a4c69d0278d5e451806e5d65deb3446b21"
        },
        "date": 1783035180547,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.847137,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.625684,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.808531,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.690892,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007327,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.031611,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.428164,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.066074,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.965717,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.631031,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.09573,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.415896,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.253662,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.099904,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.041987,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "99deadb5da7cbf1184cbe4d3073887c2d469d294",
          "message": "Use raise-continuable for unmatched guard clauses (#845) (#897)\n\nR7RS 4.2.7 requires guard to re-raise unmatched conditions with\nraise-continuable, not raise. The else clause appended by compileGuard\nused raise, making continuable exceptions non-continuable.\n\nFixes #845\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-03T04:37:46+05:30",
          "tree_id": "709442dc77c51c74796f0d8de0226d1f097bddbe",
          "url": "https://github.com/kaappi/kaappi/commit/99deadb5da7cbf1184cbe4d3073887c2d469d294"
        },
        "date": 1783035227980,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.483729,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.23807,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.853116,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.148783,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007187,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.03283,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.468193,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070618,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.970989,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.792576,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.152429,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.435904,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.41284,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.702136,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042616,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "55001b3066b91bc97a9a5ab79c069a2dc9f76c0d",
          "message": "Fix LLVM emitLet fallback to include let/let* keyword (#831) (#900)\n\nThe bail-out paths called emitSexprEvalValue(args) which passed only\nthe let's tail (bindings + body) without the keyword, causing\nkaappi_eval to evaluate a malformed expression. Add emitLetFallback\nthat wraps args with the correct keyword before eval.\n\nFixes #831\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-03T04:38:03+05:30",
          "tree_id": "1b3335eff3dbafc46b5c7193f7922fcefad3bed8",
          "url": "https://github.com/kaappi/kaappi/commit/55001b3066b91bc97a9a5ab79c069a2dc9f76c0d"
        },
        "date": 1783035522530,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.510654,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.633153,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.845912,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.179433,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007188,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032805,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.467257,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070523,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.965983,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.804891,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.128411,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.433214,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.420974,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.706764,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042479,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "084da1e7188029fb421de724f78d2ff6e5995635",
          "message": "Fix LSP positionEncoding rejection and jsonUnescape \\uXXXX (#866, #872) (#901)\n\n- Remove hardcoded positionEncoding:\"utf-8\" from initialize response;\n  vscode-languageclient rejects any encoding other than utf-16 (#866)\n- Decode \\uXXXX escape sequences in jsonUnescape to UTF-8 instead of\n  treating 'u' as a literal character (#872)\n\nFixes #866\nFixes #872\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-03T04:38:09+05:30",
          "tree_id": "e98d2c97c814d3a8ca9969c68276658df70e201a",
          "url": "https://github.com/kaappi/kaappi/commit/084da1e7188029fb421de724f78d2ff6e5995635"
        },
        "date": 1783035527191,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.428522,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.161366,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.829608,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.172501,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006974,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032596,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.465955,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070292,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.973716,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.807573,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.120789,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.42957,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.407308,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.685882,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042078,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "5ce50bba34870b449f74e8605caebe746f27295f",
          "message": "Fix symbolNeedsBars to catch DEL, C1 controls, and non-letter Unicode (#857) (#902)\n\nThe check missed DEL (0x7F), C1 controls (U+0080-U+009F), and\nnon-letter Unicode codepoints (e.g. arrows), printing symbols bare\nthat the reader can't parse back. Add DEL to the explicit switch,\ndecode multi-byte UTF-8 sequences, and check against the reader's\nisUnicodeLetter.\n\nFixes #857\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-03T04:38:14+05:30",
          "tree_id": "329db3d7cc5fc5288db06f14018c95308b0f131e",
          "url": "https://github.com/kaappi/kaappi/commit/5ce50bba34870b449f74e8605caebe746f27295f"
        },
        "date": 1783035548689,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.474053,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.535364,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.83917,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.166719,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006917,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032692,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.46379,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070609,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.948697,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.786734,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.124755,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.434151,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.399373,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.718164,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042681,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "71174a32da54021aeb5685b39aecdde2487b7fb4",
          "message": "Fix numerator/denominator on flonums to use exact dyadic fraction (#858) (#903)\n\nUse exactFn to convert the flonum to its exact rational representation,\nthen extract numerator/denominator from it — instead of using the\napproximate floatToRational which caps the denominator at 10^6.\n\nFixes #858\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-03T04:38:19+05:30",
          "tree_id": "3c3bbf8ca80a298ecbe9087dc34253d23a5408b5",
          "url": "https://github.com/kaappi/kaappi/commit/71174a32da54021aeb5685b39aecdde2487b7fb4"
        },
        "date": 1783035683572,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.41501,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.286739,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.829875,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.109556,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006867,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.033369,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.462347,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069017,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.972698,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.772826,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.193045,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.436442,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.383636,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.689366,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042457,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "54573c293181c6d9500a59942301dc4da7327517",
          "message": "Fix thread-sleep! to use OS nanosleep instead of fiber yield (#876) (#904)\n\nthread-sleep! set vm.yielded=true expecting a fiber scheduler, but\non the main thread this either raised error.Yielded or silently\nabandoned the enclosing form. Use POSIX nanosleep directly for\nactual blocking sleep regardless of scheduler context.\n\nFixes #876\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-03T04:38:24+05:30",
          "tree_id": "e0520df995b2f2b454c2c53fd2784a142e561639",
          "url": "https://github.com/kaappi/kaappi/commit/54573c293181c6d9500a59942301dc4da7327517"
        },
        "date": 1783035869203,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 2.279775,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.111244,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.484282,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.931459,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.005174,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.018149,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.248179,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.036437,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 1.799907,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.936705,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 0.621942,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.321882,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.325833,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.412568,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.026463,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "afd73eb469fa68dffabd61a505a00235a1fe7787",
          "message": "Fix continuation restore escape misdetection and dynamic-wind double-run (#870, #875) (#905)\n\nAdd continuation_generation counter to VM, bumped on every full\ncontinuation restore. callThunk/callHandler/callWithArgs check this\ngeneration to distinguish full restores (which replace the entire VM\nstate) from escape continuations (which unwind the current stack).\nWithout this, dynamicWindFn's normal-return path ran wind_count -= 1\non a replaced wind stack, causing an underflow panic.\n\nAlso fix performWindTransition to decrement wind_count before calling\neach after-thunk, preventing re-entrant wind transitions from running\nthe same after-thunk twice.\n\nFixes #870\nFixes #875\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-03T05:09:07+05:30",
          "tree_id": "61a1df36faba088752b6d528d215bc11ffbac964",
          "url": "https://github.com/kaappi/kaappi/commit/afd73eb469fa68dffabd61a505a00235a1fe7787"
        },
        "date": 1783037914430,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.377735,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.637531,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.853401,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.115428,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007094,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032878,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.476403,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.071322,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.952945,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.811083,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.135253,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.437143,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.449001,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.710761,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043257,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "9349d269a302c4b4be6f50b155306f64a773f160",
          "message": "Fix exact-integer-sqrt to use scale-aware initial guess for large bignums (#851) (#906)\n\nWhen the bignum exceeds f64 range, compute bit length from limb count,\nshift n down by an even number of bits to fit in f64, take the float\nsqrt, then shift back. Newton converges in a handful of iterations\nregardless of size.\n\nFixes #851\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-03T05:11:02+05:30",
          "tree_id": "1669c67f2c3018b1d1549d4948a46eaa23e55960",
          "url": "https://github.com/kaappi/kaappi/commit/9349d269a302c4b4be6f50b155306f64a773f160"
        },
        "date": 1783039182581,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.37957,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.497211,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.846061,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.286224,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007059,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032626,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.473465,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069619,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.967995,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.834461,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.145832,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.436921,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.426511,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.707469,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042482,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "c22cd07b86f59c182bc0914b440ccb5bdd545789",
          "message": "Fix string-join default delimiter from empty to single space (#825) (#909)\n\nSRFI-13 specifies a single space as the default delimiter.\n\nFixes #825\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-03T05:19:18+05:30",
          "tree_id": "066213a4abf96c3f03b0c0bfed34aaf3366ac143",
          "url": "https://github.com/kaappi/kaappi/commit/c22cd07b86f59c182bc0914b440ccb5bdd545789"
        },
        "date": 1783039789344,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.090852,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.292091,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.859427,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.15975,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007311,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032929,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.470387,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.067955,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.864332,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.803554,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.145767,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.479194,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.423506,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.813974,
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
          "id": "2a3fc0445b8dc65a58addd77e367dc7bab0ce9ae",
          "message": "Convert GC markValue from recursive to iterative using explicit worklist (#911)\n\nThe full-GC markValue function recursed per nesting level when both car\nand cdr of a pair were heap pointers, causing native stack overflow on\ndeeply nested structures (100k+ levels). Replace the recursive call\nwith an explicit ArrayList(Value) worklist: when both children are\npointers, push car onto the worklist and iterate cdr. Non-pair object\ntypes also push their contained values onto the worklist instead of\nrecursing. Vectors push all elements except the last and tail-call into\nthe last.\n\nFixes #864\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-03T05:48:00+05:30",
          "tree_id": "4fdc88290c3e8c89e29be4802cd30b349e5478a7",
          "url": "https://github.com/kaappi/kaappi/commit/2a3fc0445b8dc65a58addd77e367dc7bab0ce9ae"
        },
        "date": 1783040251979,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.393446,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.404348,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.82091,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.086802,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006942,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032864,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.469559,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070634,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.012788,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.804694,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.155095,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.427363,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.397883,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.662995,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.041695,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "f065ba9be1fe27880f4751b82c2510d3d2ee434e",
          "message": "Fix bignum toF64 double-rounding by using u128 top-two-limb combination (#833) (#907)\n\nThe old per-limb accumulation rounded to f64 at each step, losing\nguard/sticky bits. Use the top two limbs as a u128 with a sticky\nbit from the rest, convert to f64 once, then scale by the remaining\npower of 2.\n\nFixes #833\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-03T05:50:37+05:30",
          "tree_id": "9e07bd54074d1942bdf9c63095e950e622bc640e",
          "url": "https://github.com/kaappi/kaappi/commit/f065ba9be1fe27880f4751b82c2510d3d2ee434e"
        },
        "date": 1783040315342,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.434473,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.649606,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.843088,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.193471,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006975,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.033518,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.492593,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.073231,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.990049,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.828029,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.135908,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.424291,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.438513,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.649008,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042469,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "bf7ce0eecdea926abcc06d4dc5b81cd9ee9a65e4",
          "message": "Add VT and FF to string-trim default whitespace criterion (#913)\n\n* Add VT and FF to string-trim default whitespace criterion (#826)\n\nThe default isWhitespace only checked space/tab/newline/return,\nmissing vertical tab (0x0B) and form feed (0x0C) which SRFI-13\nand char-whitespace? include.\n\nFixes #826\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Add regression test for VT/FF whitespace in string-trim (#826)\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-03T00:34:13Z",
          "tree_id": "19d281dccfec3fb365325738d946530454bc5f39",
          "url": "https://github.com/kaappi/kaappi/commit/bf7ce0eecdea926abcc06d4dc5b81cd9ee9a65e4"
        },
        "date": 1783040325096,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.126258,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.927293,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.866052,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.166108,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007366,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.03357,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.469414,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069008,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.913027,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.830903,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.172944,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.479187,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.413765,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.874555,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044733,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "bcba05cea8ae18a08e733b9334bc058ba739b827",
          "message": "Stop flattening newlines in REPL history entries (#915)\n\n* Stop flattening newlines in REPL history entries (#821)\n\nReplacing newlines with spaces corrupted entries containing line\ncomments, making recalled history evaluate differently.\n\nFixes #821\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Add regression test for REPL history newline preservation (#821)\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-03T00:36:00Z",
          "tree_id": "5abde1f473ed39df42b73a256f073d8bc41e3c00",
          "url": "https://github.com/kaappi/kaappi/commit/bcba05cea8ae18a08e733b9334bc058ba739b827"
        },
        "date": 1783040618256,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.437748,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.395941,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.865634,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.172208,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007124,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.033528,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.478015,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.071111,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.093852,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.84398,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.168974,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.438039,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.494222,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.724566,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043007,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "a43d8a964d35af0149eeebdd0f50271177480cf4",
          "message": "Merge pull request #908 from kaappi/fix/859-prettyprint-cycle\n\nAdd depth limit to prettyPrint to prevent hangs on cyclic values",
          "timestamp": "2026-07-03T06:07:22+05:30",
          "tree_id": "39c57029e1f04662a46318aef98c8420b1754186",
          "url": "https://github.com/kaappi/kaappi/commit/a43d8a964d35af0149eeebdd0f50271177480cf4"
        },
        "date": 1783040643452,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.072603,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.030833,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.856342,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.334359,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007289,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.033052,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.467706,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068372,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.873222,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.785945,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.160868,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.470918,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.41051,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.811632,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044868,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "38b06874a5c9cd83707d163f4f69e0f25aab05c7",
          "message": "Restore debug_mode after ,step instead of unconditionally disabling (#914)\n\n* Restore debug_mode after ,step instead of unconditionally disabling (#823)\n\n,step was setting debug_mode=false after the expression, which\ncleared breakpoints set via ,break. Save and restore the prior state.\n\nFixes #823\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Add regression test for ,step preserving debug_mode (#823)\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-03T00:42:23Z",
          "tree_id": "f29af25b1ff16e7732963133d096bce598a85a80",
          "url": "https://github.com/kaappi/kaappi/commit/38b06874a5c9cd83707d163f4f69e0f25aab05c7"
        },
        "date": 1783040691767,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.070075,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.944975,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.858913,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.157747,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007288,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.033425,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.469985,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068453,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.877332,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.804636,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.244022,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.472156,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.419222,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.813476,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044186,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "4ce5ca8967c94b24921def30f18445a2ff2570f7",
          "message": "Merge pull request #912 from kaappi/fix/849-850-852-quasiquote\n\nFix quasiquote nesting for unquote-splicing, vectors, and dotted tails",
          "timestamp": "2026-07-03T06:14:04+05:30",
          "tree_id": "4499b2fb74b869a3a4cd8559257e8f584872b40f",
          "url": "https://github.com/kaappi/kaappi/commit/4ce5ca8967c94b24921def30f18445a2ff2570f7"
        },
        "date": 1783040853045,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.389408,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.725127,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.841576,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.140917,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007096,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.033053,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.473233,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069726,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.951412,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.79246,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.16491,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.43481,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.402433,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.719308,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043557,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "389c5e25e3faab50d7a7cbe5e48b10b49a8d3e2a",
          "message": "Fix cond-expand (library ...) and include in library bodies (#917)\n\n* Fix cond-expand (library ...) and include in library bodies (#868, #879)\n\n- cond-expand (library ...) now checks .sld file existence on the\n  library path, not just the already-loaded registry (#868)\n- include inside library begin blocks is routed through\n  handleTopLevelForm which supports it (#879)\n\nFixes #868\nFixes #879\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Add .sld file check to compiler cond-expand and regression tests (#868, #879)\n\nThe compiler-level evalFeatureReq for (library ...) only checked a\nhardcoded list. Now it also checks the VM library registry and .sld\nfiles on the library path, matching the vm_library.zig behavior.\n\nAlso adds include routing in library begin blocks (#879) and\nregression tests for both fixes.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-03T00:45:05Z",
          "tree_id": "077914239bf02fe5f3c6bdd84e1a9b8593a58649",
          "url": "https://github.com/kaappi/kaappi/commit/389c5e25e3faab50d7a7cbe5e48b10b49a8d3e2a"
        },
        "date": 1783040974940,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.160152,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.912282,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.669714,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.989955,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.005755,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.026364,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.367279,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.053499,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.335727,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.388337,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 0.907878,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.37056,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.868015,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.45475,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.03588,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "476462af519546ab884bced18ed6c31779f11354",
          "message": "Merge pull request #910 from kaappi/fix/816-818-exports-clean\n\nAdd missing exports to SRFI-133 and SRFI-1 library definitions",
          "timestamp": "2026-07-03T06:15:25+05:30",
          "tree_id": "dd9d23ad70d285b39b94f19a426b9d39077b7012",
          "url": "https://github.com/kaappi/kaappi/commit/476462af519546ab884bced18ed6c31779f11354"
        },
        "date": 1783041164688,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.39769,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.268624,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.857405,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.154097,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007141,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.033033,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.475674,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.071109,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.004853,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.854187,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.130245,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.436132,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.441955,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.721221,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043156,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "c2d5370c02f537e599a2b621a3c837cf81d5bf46",
          "message": "Rewrite README for OSS suitability; reconcile procedure count to 579 (#918)\n\nThe README opened with a contributor build workflow rather than an install\npath, and carried several stale or self-contradictory facts (v0.5.0 banner,\nwrong history-file path, a data-types table contradicting the NaN-boxing\nsection, and a mismatched procedure count). Restructure it around a new user:\ntry-in-browser, install, taste, features, ecosystem — and move the exhaustive\nsource-tree listing to docs/dev/architecture.md where it already lives.\n\nThe built-in procedure count disagreed across docs (554 vs 632). Neither was\nright: 632 counts raw reg() call sites, inflated by ~47 procedures re-registered\nin the sandbox path; 554 was stale. Standardize on 579 (unique registered\nnames, verifiable from source) everywhere it appears.\n\nAdd a release-skill step that recomputes the count from source and sweeps the\ndocs so it stays honest, and reference the docs-site step by name rather than a\nnumber that had already drifted.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-03T07:13:54+05:30",
          "tree_id": "734e618163646aab1dcdce410e29d12e1a6c5ed3",
          "url": "https://github.com/kaappi/kaappi/commit/c2d5370c02f537e599a2b621a3c837cf81d5bf46"
        },
        "date": 1783043836806,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.400676,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.568445,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.856884,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.140821,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00723,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.03313,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.475254,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070946,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.994379,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.830453,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.177955,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.438186,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.489931,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.752445,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042905,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "9d5d077074a56a3d76d13a402cefedda692932eb",
          "message": "Reorganize dev docs: genre structure, index, staleness fixes, dedup (#922)\n\n* Add dev docs index and fix stale status headers\n\ndocs/dev had 21 files with no entry point and no way to tell evergreen\nguides from point-in-time bug records. Several of those records had\nrotted: bytecode-disassembler.md claimed --disassemble was not yet\nadded (it shipped 2026-06-18 in 96410f9), complex-number-test-precision\n.md said \"not yet fixed\" though its proposed fix landed verbatim the\nsame day it was written (82407ab), and fixnum-overflow-promotion.md\ndescribes the pre-NaN-boxing i63 encoding without saying so.\n\nAdd docs/dev/README.md as a genre index (guides / design decisions /\npostmortems / known issues / reference / policy) with conventions for\nwhere new docs go, correct the stale claims, date every Status header\nso freshness is judgeable, and link the index from README and\nCONTRIBUTING.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n* Reorganize dev docs into decisions/ and postmortems/\n\nThe genre of each doc (evergreen guide vs point-in-time record) was\ninvisible in a flat directory — a reader couldn't tell architecture.md\nfrom a closed bug write-up without opening both. Make the genre part of\nthe filesystem: design decisions move to decisions/, fixed-bug\nwrite-ups move to postmortems/ with a YYYY-MM-DD investigation-date\nprefix so the directory reads chronologically.\n\nEvergreen guides, the open known issue, reference notes, and policy\nstay at the top level, so all inbound links from README, CONTRIBUTING,\nCLAUDE.md, and CHANGELOG remain valid. complex-number-test-precision\njoins the postmortems now that it is confirmed fixed. All cross-links\nbetween docs updated; every relative link in docs/dev verified to\nresolve.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n* Dissolve status docs into references and tracker issues\n\nThe point-in-time \"status\" docs mixed reference material with roadmap\nwishlists, and both halves rot: the wishlists don't get checked off\n(repl-enhancements.md had 9 of 10 items shipped, unicode-case-mapping.md\nstill listed Armenian/Georgian/Cherokee as missing after they shipped\n2026-06-18), and open-bug docs drift from reality. Split each into its\ntwo real parts: current-state reference here, open work in the tracker.\n\n- bytecode-disassembler.md -> bytecode.md: now the single ISA reference\n  (adds the missing self_tail_call opcode, 32 total). The /bytecode-isa\n  skill had its own 19-opcode copy of the table, 13 opcodes stale — it\n  now points at the doc instead of duplicating it.\n- repl-enhancements.md -> repl.md: current-state reference with the\n  verified command list from ,help (repl.zig, not main.zig — the REPL\n  moved). Remaining wishlist item (pretty-printing) filed as #921.\n- unicode-case-mapping.md: rewritten as a coverage reference; the\n  already-shipped \"missing\" sections removed, genuine gaps (Latin\n  Ext-B/IPA, Cyrillic Supplement, six bicameral scripts, non-ASCII\n  #!fold-case) filed as #920.\n- nested-define-syntax-hygiene.md: deleted; full analysis plus the\n  current jabberwocky suite failure migrated to #919. Open bugs live in\n  the tracker so closing the bug closes the record.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n* Deduplicate dev docs and fix drift between paired documents\n\nSeveral documents held second copies of content owned elsewhere, and\nthe copies had drifted:\n\n- lessons-learned.md now works as the narrative index the README\n  convention promises: section 10 shrinks to a summary linking the\n  gc-reachability postmortem, section 3 cross-links the related\n  global-cache postmortem (a distinct bug in the same subsystem), and\n  new sections 12-14 index the three postmortems that had no entry.\n  Section 11 claimed NaN-boxing \"didn't work\" — it shipped 2026-06-25\n  with 48-bit fixnums and bignum auto-promotion; rewritten as a\n  \"rejected, then shipped\" entry with the actual lesson. The\n  tail_call_global entry now defers to the decisions doc, which\n  records the real blocker.\n\n- gc-safety-and-error-handling.md described the GC as plain\n  mark-and-sweep and never mentioned the write barrier, while the\n  enforced rule file (.claude/rules/gc-safety.md) requires it. The doc\n  now covers the generational design, the write barrier with its\n  rationale, Function* rooting before vm.execute(), and -Dgc-threshold=1\n  stress testing; doc and rule file cross-link and declare the rule\n  file the checklist / the doc the rationale.\n\n- CLAUDE.md's harness section now declares itself the summary and\n  points at docs/dev/claude-code-harness.md, whose /bytecode-isa\n  description (still \"19 opcodes\") is corrected to match the skill's\n  new pointer-to-doc form.\n\n- The self-tail-call decision's Key files table pointed at a dead\n  docs/benchmarks.md, pre-VM-split vm.zig line numbers, and a brittle\n  lessons-learned.md:157 reference — replaced with current paths and\n  a heading anchor.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-03T07:45:08+05:30",
          "tree_id": "0895491aa75d18b6ee947bc5456570b4efe5ad81",
          "url": "https://github.com/kaappi/kaappi/commit/9d5d077074a56a3d76d13a402cefedda692932eb"
        },
        "date": 1783045647572,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.381309,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.149337,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.847936,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.138111,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006963,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.033265,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.475398,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070631,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.975347,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.831631,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.12256,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.435561,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.49577,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.53929,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.041986,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "aef9898806209a5b53cc699265c5d91f600fa18f",
          "message": "Fix double hygiene renaming in macro-generating macros (#923)\n\n* Fix double hygiene renaming in macro-generating macros\n\nWhen a macro's template defines another macro, identifiers in the inner\ntemplate that were already hygiene-renamed by the outer expansion (e.g.\n__hyg_369_march-hare) got renamed a second time when the inner macro\nexpanded, producing names like __hyg_373___hyg_369_march-hare that no\nlonger matched the binding the outer expansion created.\n\nRenaming an already-renamed identifier cannot prevent any capture —\ngensyms are globally unique and can never collide with user identifiers.\nIt only severs the reference from its binding. renameForHygiene now\nreturns identifiers carrying the __hyg_ prefix unchanged.\n\nThis fixes the jabberwocky test (r7rs-tests.scm:536), the last\nmacro-hygiene failure tracked in #919; the pattern-variable scoping\nvariant from that issue already worked and now has a guard test.\n\nFixes #919\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n* Clear threadlocal vm_instance in VM.deinit\n\nThe Linux CI runs of PR #923 crashed (SIGSEGV) in the new nested\nsyntax-rules unit test: execute() registers the VM in the threadlocal\nvm_instance, but deinit never unregistered it. In the unit-test binary,\nthe next test's first eval macro-expands at compile time — before its\nown execute() re-registers the threadlocal — so renameForHygiene read\nthe previous test's freed globals map through the stale pointer. The\nuse-after-free predates #923; the new test only shifted heap reuse\nenough for glibc to fault where macOS malloc stayed silent.\n\nDeinit now nulls vm_instance when it points at the dying VM, and a\nlifecycle test asserts the unregistration deterministically instead of\nrelying on platform-dependent memory reuse.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-03T08:30:10+05:30",
          "tree_id": "d6baec9ce4f2d71521d3a3788aae5e6ff7b0659e",
          "url": "https://github.com/kaappi/kaappi/commit/aef9898806209a5b53cc699265c5d91f600fa18f"
        },
        "date": 1783048487386,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.390018,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.073528,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.839651,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.154513,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007063,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.03327,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.474525,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070789,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.942397,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.838112,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.159133,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.427748,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.482564,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.711292,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042043,
            "unit": "seconds"
          }
        ]
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
          "id": "d9aed21d1b7c19c2a3eefc10fa0ce0ee27d16a17",
          "message": "Direct contributors through Discussions first\n\nIssues and PRs are now restricted to org members to reduce\nAI-generated spam. Update CONTRIBUTING.md with a \"How to get\ninvolved\" section and contributor path, update README Contributing\nsection to lead with Discussions.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-03T09:00:17+05:30",
          "tree_id": "3b3a0a6f56acf51ce88a98812bce2943b4ef61c4",
          "url": "https://github.com/kaappi/kaappi/commit/d9aed21d1b7c19c2a3eefc10fa0ce0ee27d16a17"
        },
        "date": 1783050194290,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.401283,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.329645,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.870165,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.172236,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007179,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.033385,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.475494,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070903,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.927792,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.838007,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.154981,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.431251,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.493116,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.596609,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042054,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "e028f6ca4d398bc9c87dbf0b79289740ef39162a",
          "message": "Fix two R7RS suite forms aborted by hygiene and macro-shadowing bugs (#926)\n\nTwo top-level forms in tests/scheme/r7rs/r7rs-tests.scm (lines 580 and\n633) aborted with errors and were counted neither pass nor fail.\n\nLine 580 (forward hygienic refs): the body prescan plants VOID sentinels\nin the globals map for internal defines appearing later in the same\nbody, so the expander keeps template references to them intact. Commit\nd32f475 dropped the VOID case from renameForHygiene's preservation\ncheck, so sibling-define references got renamed to gensyms and severed\nfrom their bindings. Restore it, guarded to non-binding position (keeps\nthe d32f475 fix) and to names this expansion has not already renamed as\ntemplate-introduced bindings (otherwise a template that both binds and\nreferences a name colliding with a non-procedure global would rename\nthe binding but not the references).\n\nLine 633 (InvalidSyntax): a macro-generating macro used mid-body leaks\nthe generated macro past its let body, and a later body's internal\ndefine of the same name did not shadow the keyword, so the call was\nexpanded as a macro use and failed pattern matching. Per R7RS 5.3 a\nvariable binding shadows a syntactic keyword: a local or captured\nbinding now makes the form compile as a procedure call.\n\nR7RS suite: 1395 pass, 0 fail. All four regression tests verified to\nfail without the fixes.\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-03T03:42:17Z",
          "tree_id": "cec3ebed2f83d207461eb4e99bc2422d8471f559",
          "url": "https://github.com/kaappi/kaappi/commit/e028f6ca4d398bc9c87dbf0b79289740ef39162a"
        },
        "date": 1783051054774,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.381638,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.904661,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.861362,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.154675,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007028,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.033138,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.476882,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070597,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.04518,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.822234,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.165073,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.441386,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.414363,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.71904,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042726,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "f1edcbf7ca392d56111577f9ccb82d8853289558",
          "message": "Fix use-after-free of frame pointer after re-entrant natives grow the frames array (#927)\n\nrunUntil captures `frame` as a pointer into self.frames at the top of\neach dispatch iteration. Handlers for tail_call, tail_apply, and\ntail_call_global invoke code that can re-enter the VM — natives that\ncall Scheme callbacks (map, sort, apply, ...), parameter converters via\ncallWithArgs, FFI callbacks — and afterwards read frame.dst. Re-entry\npushes a frame via ensureFrameCapacity, which on growth allocates a new\nframes array and frees the old one, leaving `frame` dangling. Depending\non heap reuse the stale read yielded a spurious InvalidBytecode error or\nsilently wrote the native's return value into the wrong caller register.\n\nRead frame.dst into a local before any potentially re-entrant call, and\nin the .return handler copy the caller's saved_wind_count/base instead\nof holding a pointer across the dynamic-wind after-thunk calls.\n\nThe regression tests shrink the frames array to 8 entries and scan a\ncontiguous nesting-depth range, which guarantees the re-entrant push\nlands exactly on a capacity boundary and forces the reallocation at the\nvulnerable moment.\n\nFixes #817\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-03T10:04:57+05:30",
          "tree_id": "a7b5db7f4c291e93dc2f8fa364e89bbd5d16bebe",
          "url": "https://github.com/kaappi/kaappi/commit/f1edcbf7ca392d56111577f9ccb82d8853289558"
        },
        "date": 1783054250687,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.900831,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.853081,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.789475,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.737369,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007406,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032395,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.433241,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.067071,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.019269,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.622101,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.163656,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.406742,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.264057,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.983262,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.039286,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "06e9e0796d107b78635014d8dcae10f9a7a3e7bb",
          "message": "Scope macro-generated define-syntax to its body (#928)\n\nA define-syntax produced by macro expansion mid-body (e.g. (foo bar x)\nexpanding to (define-syntax bar ...)) escaped its body scope:\ncompileLetBody's leading scan only tracked syntactically-leading\ndefine-syntax forms, while the expanded form reached compileDefineSyntax\nand entered the macro table untracked. The table is copied back into\nvm.macros after every top-level form, so the generated macro leaked into\nall subsequent top-level code, violating R7RS 5.3 (body syntax\ndefinitions are local to the body).\n\nTrack registrations in a body-macro scope stack on the Compiler:\ncompileDefineSyntax records the prior entry whenever a body scope is\nactive, and compileLetBody / compileLetSyntax push/pop scopes that\nrestore entries newest-first on exit. At depth 0 registrations are not\ntracked, preserving top-level persistence — including R7RS 5.1\n(begin ...) splicing. The leading scan now shares this mechanism,\nremoving its fixed 64-macro limit. Lambda bodies need no change: they\ncompile in a per-lambda child compiler whose macro table is discarded.\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-03T10:22:29+05:30",
          "tree_id": "cbdacdcab277b143d4c9e774cca778d4667601c7",
          "url": "https://github.com/kaappi/kaappi/commit/06e9e0796d107b78635014d8dcae10f9a7a3e7bb"
        },
        "date": 1783055255704,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.329367,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.821042,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.808324,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.100595,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007139,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032143,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.45648,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068565,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.993302,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.668685,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.136837,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.405775,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.273673,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.954123,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.03866,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "9fc850558728c7a64407d838c1f1810bcafc5494",
          "message": "Search the script's directory for libraries; unify cond-expand library checks (#930)\n\nTwo library-loading test failures surfaced once uncaught script errors\nstopped exiting 0 (#924). Neither test had ever exercised what it claimed:\n\n1. tests/scheme/compliance/include-lib-decls-exports.scm was never a test.\n   It is the include-library-declarations fixture for include-lib-decls.scm,\n   but living as a loose .scm in a globbed suite directory, run-all.sh\n   executed it standalone and the top-level (export ...) errored. The\n   fixture now lives in compliance/fixtures/, which the glob skips.\n\n2. tests/scheme/smoke/condexpand-include-lib-868-879.scm (from #917) could\n   never load its lib868/ fixture libraries: .sld resolution searched only\n   the working directory, cwd/lib/, --lib-path entries, and ~/.kaappi/lib —\n   never anywhere near the script. runFile already resolved include paths\n   against the script's directory, but library lookup did not. main.zig now\n   appends the script's directory to the library search path (after\n   --lib-path entries, before ~/.kaappi/lib), so programs can import\n   libraries that sit next to them regardless of the working directory.\n\nThe two cond-expand (library ...) feature checks (compiler-side\nevalFeatureReq and VM-side evalLibFeatureReq) each had a hand-rolled\nexistence loop over vm.lib_paths that skipped the cwd and lib/ prefixes\nimport actually uses, so cond-expand could disagree with what import can\nload. Both now call a shared libraryFileExists() in vm_library.zig that\nmirrors import's search order, including bundled files.\n\nBoth Scheme tests now assert with explicit (exit 1) instead of printing\nvalues, so wrong output fails the run even before the #924 exit-code fix\nlands. A new unit test covers cond-expand .sld detection in expression and\ndeclaration contexts.\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-03T11:11:06+05:30",
          "tree_id": "db2a3ed7541af4efb239dd45cc7e794d18039820",
          "url": "https://github.com/kaappi/kaappi/commit/9fc850558728c7a64407d838c1f1810bcafc5494"
        },
        "date": 1783058169052,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.429027,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.005141,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.861356,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.122742,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00705,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.03371,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.476877,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.071113,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.027517,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.838694,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.1486,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.43727,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.486265,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.564963,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042707,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "7c600a874148c4f51e24df789b8ef698c08f358b",
          "message": "Fix nested-ellipsis expansion rejecting depth-2 pattern variables (#931)\n\ninstantiateEllipsis required every referenced ellipsis binding to have\ndepth exactly 1, so any syntax-rules template using variables bound\nunder two ellipses — like SRFI-35's condition construction macro\n((?type1 (?field1 ?value1) ...) ...) — failed with InvalidSyntax\n(EllipsisDepthMismatch). The depth check made the existing depth>1\nunpacking logic directly below it unreachable. Deeper bindings repeat\nthe same number of times as depth-1 bindings at the outer level, so the\nR7RS count-consistency check still applies unchanged.\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-03T11:11:19+05:30",
          "tree_id": "1eefc5aa49c9aadd7ee611611d084b9851ad891e",
          "url": "https://github.com/kaappi/kaappi/commit/7c600a874148c4f51e24df789b8ef698c08f358b"
        },
        "date": 1783058176379,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.382581,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.429785,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.843987,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.249486,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007015,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.033747,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.479406,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070599,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.96339,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.849875,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.125063,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.424904,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.456465,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.627234,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.041548,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "77dda3040c439ce51045ea4f1b518583ed32ced3",
          "message": "Fix wrong vector-partition expectation in SRFI-133 extended tests (#932)\n\nThe test expected (vector-partition even? #(1 2 3 4 5)) to return a\n2-element vector of only the satisfying elements. Per the SRFI 133\nspec, the first value is a vector the same size as the input —\nsatisfying elements first, then the rest, both in original order —\nand the implementation already conforms. The failure surfaced only\nafter script error exit codes were fixed; it had been masked before.\n\nStrengthen the check to compare full vector contents (guarding\nagainst a future regression that truncates the result) and add\nall-satisfying, none-satisfying, and empty-vector edge cases.\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-03T05:49:37Z",
          "tree_id": "ec4dd20ab2959f4fe3e1499547abadec754016d9",
          "url": "https://github.com/kaappi/kaappi/commit/77dda3040c439ce51045ea4f1b518583ed32ced3"
        },
        "date": 1783058612708,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.386059,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.697252,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.862063,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.176371,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00709,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.033552,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.482992,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070623,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.970605,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.849892,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.125868,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.433042,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.453228,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.675099,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042166,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "320b3cb4f3a3189e30147b7b05a3019630000954",
          "message": "Fix thread-terminate! never stopping OS threads, hanging thread-join! (#933)\n\nthread-terminate! only set cooperative-scheduler flags (fiber.terminated,\nwakeWaiters) that a child OS thread spawned by thread-start! never\nobserved, so a looping thunk ran forever and the parent's thread-join!\nblocked indefinitely in pthread_join. This hung tests/scheme/srfi/\nsrfi18.scm with zero output since at least v0.10.0; run-all.sh masked it\nas a 60s-timeout SKIP.\n\nGive child VMs a pointer to the shared fiber.terminated flag and poll it\n(atomically) at the existing 1024-instruction dispatch-loop safepoint,\nso termination adds no hot-path cost. On termination the child unwinds\nwith the new VMError.Terminated, the OS thread exits, and thread-join!\nraises terminated-thread-exception as SRFI-18 specifies.\n\nAlso repair srfi18.scm so it can actually run and fail meaningfully:\n\n- Rewrite the mutex-contention and condvar-signal tests against the\n  cooperative fiber path (spawn). OS threads run on isolated heaps and\n  mutexes/condvars are deliberately uncopyable, so the old OS-thread\n  versions could never pass; add a test pinning that capturing a mutex\n  in a thread thunk raises uncaught-exception at join.\n- Signal failure with (exit 1): a top-level (error ...) exits 0, so the\n  file previously could not fail run-all.sh even when tests failed.\n\nRegression test: tests_srfi18.zig terminates a pure busy-loop OS thread\nand joins it; without the safepoint this hangs zig build test.\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-03T11:43:54+05:30",
          "tree_id": "ef204a5fee45e209425bfc3abd720ab161e995ec",
          "url": "https://github.com/kaappi/kaappi/commit/320b3cb4f3a3189e30147b7b05a3019630000954"
        },
        "date": 1783060046953,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.413808,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.688596,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.836394,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.200471,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00696,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.03293,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.466485,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070334,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.972206,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.816008,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.151927,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.429787,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.421177,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.669209,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042302,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "04e79a2f521c5d202af010da72ef34c5a70dfae7",
          "message": "Fix call/cc escapes lost inside re-entrant native calls (#934)\n\nRestoring a continuation captured inside the dynamic extent of a native\nthat re-enters the dispatch loop (with-exception-handler, guard,\ndynamic-wind, map, ...) unwound execution to the outermost loop: of the\neleven ContinuationInvoked catch sites in runUntil, only the plain .call\npath resumed in the innermost loop containing the restored frame, while\nthe tail_call / call_global / tail_call_global / tail_apply paths bailed\nunless target_frame_count == 0. Since (call/cc ...) in tail position of\na thunk compiles to tail_call, escaping from a guard or\nwith-exception-handler body abandoned the native's pending\nresult-register write and the surrounding expression evaluated to a\nstale register — typically the with-exception-handler builtin itself.\nEvery SRFI-64 assertion wraps its expression this way, which is what\nbroke \"deep non-tail escape\", \"inner escape, no arithmetic\", and \"outer\nescape from inner extent\" once the suite's silent breakage was fixed.\n\nResuming in the innermost loop whose scope still contains the restored\nframes keeps the Zig-side re-entrant callers between the restore point\nand that loop delivering results correctly. Frame depth alone cannot\nidentify that loop (a restore targeting older-but-deeper frames inside a\ndynamic-wind thunk would masquerade as the thunk's normal return and\nunderflow the wind stack), so each frame now carries a birth id\n(CallFrame.seq) preserved across tail-call reuse and capture/restore;\nresumesHere() resumes only where the loop's scope-root frame survived,\nand out-of-lineage restores propagate outward as before.\n\nThe u64 seq also gives SavedFrame 8-byte alignment on wasm32, replacing\nthe manual padding.\n\nRegression coverage: five unit tests in tests_continuations.zig and\ntests/scheme/continuations/callcc-reentrant-escape.scm (manual asserts\nso it stands alone while the SRFI-64 fix lands separately); all fail\nbefore this change.\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-03T06:18:14Z",
          "tree_id": "0771958fc695dae843eab0caadf47cbb662dcfeb",
          "url": "https://github.com/kaappi/kaappi/commit/04e79a2f521c5d202af010da72ef34c5a70dfae7"
        },
        "date": 1783060331489,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.467638,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.883679,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.870284,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.201945,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007046,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.033866,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.47062,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070581,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.21242,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.816184,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.217207,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.434095,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.428317,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.753937,
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
          "id": "59129796d033b7aa70568ec2684e13bc180c6423",
          "message": "Fix lost set! writes and builtin-name capture in macro templates (#935)\n\nTwo macro hygiene bugs, both of which silently corrupted test-harness\nmacros that keep pass/fail counters in globals:\n\n1. A template's (set! g ...) on a free global was silently lost. The\n   compiler injects a register alias local (preloaded via get_global)\n   for each template-free non-procedure global so references pierce\n   use-site shadowing, but compileSet resolved the target to that alias\n   and emitted a plain move into the register — the global was never\n   written back and no error was raised. Alias locals now carry an\n   is_global_alias flag and set! writes through with set_global, then\n   refreshes the alias register for later reads in the same expansion.\n   This is why counter-based harnesses printed PASS/FAIL lines but\n   reported \"0 pass, 0 fail\" and could never flip the exit code.\n\n2. A template binding named after a builtin procedure did not shadow\n   the builtin inside the template. renameForHygiene renamed the\n   binding occurrence but kept references unrenamed whenever the name\n   resolved to a procedure-valued global, so the body saw the builtin.\n   The procedure-preservation shortcut now consults the expansion's\n   scope table first, matching what the VOID-sentinel branch already\n   did. This was the cause of all 99 srfi-19-tests.scm failures\n   (\"expected #<builtin exp>\" from the harness binding (exp expected));\n   that file now reports 112 passed, 0 failed.\n\nNote: fix 2 also appears in open PR #929 (same reorder); its VM-level\nset_global fallback is complementary to fix 1, which handles alias\nlocals that never reach set_global at all. Reconcile whichever lands\nsecond.\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-03T06:20:21Z",
          "tree_id": "ecc4876fddc2da5b9a9825b1a606cc614305c832",
          "url": "https://github.com/kaappi/kaappi/commit/59129796d033b7aa70568ec2684e13bc180c6423"
        },
        "date": 1783060461105,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.553787,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.031784,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.864127,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.289261,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006972,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032895,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.471049,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070633,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.148715,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.804677,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.140622,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.440213,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.439434,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.740064,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045726,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "5dc8bc945d19d0dcde2035ebdb555a65beaa69fc",
          "message": "Fix case-lambda capturing user variables and dropping clauses past the 32nd (#936)\n\n* Stop case-lambda capturing user variables named n or args\n\nThe case-lambda desugaring bound its rest-parameter to the plain symbol\n`args` and the argument count to `n`, so clause bodies referencing outer\nvariables of those names silently resolved to the internal bindings:\n(define n 42) (define f (case-lambda ((x) (+ x n)))) returned 2 for\n(f 1) instead of 43. Rename the internals to %cl-args/%cl-n, following\nthe %-prefix convention parameterize already uses, which no user\nidentifier read from source can collide with.\n\nAlso rewrite the smoke test to assert via guard + (exit 1): the old\ndisplay-only version could never fail run-all.sh because uncaught\nscript errors currently exit 0 and SRFI-64 is broken, which is how\nthis regression stayed masked.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n* Compile all case-lambda clauses, not just the first 32\n\ncompileCaseLambda collected cond clauses into a fixed 32-entry buffer\nand silently ignored the rest, so a case-lambda with more than 32\nclauses raised \"wrong number of arguments\" for any call matching a\nlater clause. Collect clauses in a growable list instead; the clause\nvalues stay GC-reachable because no_collect is held until the\ndesugared form is fully built.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-03T06:34:39Z",
          "tree_id": "2e7f2c4527211efcc310f838688951c3f8caaa3b",
          "url": "https://github.com/kaappi/kaappi/commit/5dc8bc945d19d0dcde2035ebdb555a65beaa69fc"
        },
        "date": 1783061299386,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.471186,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.338683,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.847545,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.128009,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006955,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.033432,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.461257,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070167,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.198958,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.774061,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.182636,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.434584,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.395047,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.699389,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042439,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "d1e9616d0090cfee4c0cb96678e11680a0f85256",
          "message": "Remove dead .sbc cache-read path for .sld libraries (#937)\n\nWriting .sbc caches for .sld files has been disabled for a while (the\nserializer could hit a use-after-free when GC ran during library\nloading), but tryLoadLibraryFromFile still probed for and accepted\nexisting .sbc files. On such a hit it reconstructed the export table by\nre-parsing only the top level of the .sld, silently dropping exports\ndeclared via include-library-declarations or nested inside cond-expand\nbranches — the import then succeeded with no bindings and every use\nsite failed with \"undefined variable\". The path also looked up exports\nin vm.globals rather than the per-library environment, and any library\nexporting macros fell through to source compilation anyway.\n\nDelete the read path, extractExportsAndImports, and LibraryMeta\nentirely: .sld libraries now always compile from source and a stale or\nhand-built .sbc next to a .sld is ignored. If caching is ever\nreintroduced, the export table should be serialized into the .sbc\ninstead of re-derived from source. Main-program .sbc caching in\nmain.zig is unaffected.\n\nThe regression test hand-builds a hash-matching .sbc next to a .sld\nthat declares its exports through include-library-declarations and\ncond-expand, and verifies both exports survive the import.\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-03T06:45:18Z",
          "tree_id": "4e67eea0f3066e97da263ee327b15fde069b2ae6",
          "url": "https://github.com/kaappi/kaappi/commit/d1e9616d0090cfee4c0cb96678e11680a0f85256"
        },
        "date": 1783061968341,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.549643,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.130233,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.868504,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.30137,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006967,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.034333,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.472166,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070924,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.146019,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.816356,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.250585,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.437679,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.434968,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.749203,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042991,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "35b95cc2699fc03cf157f48edf98f49556df3fb7",
          "message": "Fail the Scheme suite when a test file times out (#938)\n\nrun-all.sh labeled per-file 60s timeouts as SKIP and the final exit\ncheck only counted FAILs, so a hanging test file left the suite green.\nThis let tests/scheme/srfi/srfi18.scm hang unnoticed for months.\n\nTimeouts now print a TIMEOUT label with the test's partial output,\ncount into the fail total, and make the suite exit 1. The R7RS awk\nparsing is unaffected — it only scrapes the chibi-test \"N pass, N fail\"\nlines, never the per-file labels.\n\nVerified: clean run passes (242 files, exit 0); an injected\ninfinite-loop test file produces TIMEOUT and exit 1.\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-03T06:50:58Z",
          "tree_id": "5451ebd3c04017fd8e0cf5ee879969f12ea3ef66",
          "url": "https://github.com/kaappi/kaappi/commit/35b95cc2699fc03cf157f48edf98f49556df3fb7"
        },
        "date": 1783062162789,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.515096,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.879477,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.853667,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.191275,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006981,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.034464,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.471075,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070591,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.156449,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.814415,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.244337,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.434849,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.432455,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.706288,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043164,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "81adb3c0da5b0e8f658783acd52fa78b60fe88b6",
          "message": "Mark hash-table entries occupied on insert via update!/default and alist->hash-table (#939)\n\nHashEntry.state defaults to .empty, and the insert paths in\nhash-table-update!/default and alist->hash-table omitted the state\nfield when writing new entries. The key and value were stored and the\ncount incremented, but findKey/findSlot treated the slot as empty, so\nthe key was invisible to lookup, duplicate detection in\nalist->hash-table never fired, and the phantom entry was silently\ndropped on the next rehash. hash-table-set! already set the state\nexplicitly, which is why only these two paths were affected.\n\nThe failures were masked until now because uncaught script errors\nexit 0, so the existing srfi69-ext and mutation-write-barrier tests\nreported PASS despite aborting mid-file.\n\nThe regression test uses manual counters with guard and an explicit\n(exit 1) rather than SRFI-64, because SRFI-64 asserts are currently\nbroken (undefined %test-on-test-begin) and would not gate the run.\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-03T07:19:17Z",
          "tree_id": "9d49880d443471970922b3f4d55cefb1f1d6d19f",
          "url": "https://github.com/kaappi/kaappi/commit/81adb3c0da5b0e8f658783acd52fa78b60fe88b6"
        },
        "date": 1783064139465,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.170938,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.981219,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.873797,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.23229,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007315,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.033205,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.472981,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070214,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.051218,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.804604,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.165355,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.48531,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.400323,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.860237,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045352,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "0b148c5e2f43d5c2086b14d429d5d8088f042704",
          "message": "Fix top-level thread-yield! scheduler interaction and pre-scheduler parameter loss (#940)\n\n* Fix top-level thread-yield! aborting defines and leaking fiber results\n\nCalling (thread-yield!) from the main fiber at the top level of a file\nmisbehaved in two ways. First, run() committed to the non-scheduler\npath once at entry, so when spawn created the scheduler lazily during\nthe form's execution, the subsequent yield escaped as a raw\nerror.Yielded and aborted the form (leaving a top-level define\nunbound). Second, runWithScheduler marked the main fiber .completed\nafter every top-level form and never reset it, so later forms could\nnot reschedule main after a yield; and when main's form completed\ninside a nested scheduler loop (a blocked fiber's native primitive\nresuming it via runUntil), the outer loop returned the spawned\nfiber's thunk result as the top-level form's value.\n\nrun() now re-checks vm.scheduler when catching Yielded and enters the\nscheduler loop; execute() resets the scheduler to fiber 0 per\ntop-level form; and runWithScheduler returns the main fiber's saved\nresult when the last runUntil unwinds out of a spawned fiber. The\nnested scheduler loops in primitives_srfi18.zig no longer abandon\nfiber 0's mutexes when it finishes a form — completing one top-level\nform is not thread death, and the mutexes stay valid for later forms.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n* Fix parameters set before scheduler creation being lost\n\ngetParameterValue consulted only the current fiber's override map once\na fiber existed. Parameter values set at the top level before the\nscheduler is lazily created live in the VM-level override map, so they\nvanished the moment spawn created the scheduler (the main fiber starts\nwith an empty override map) — e.g. a test runner installed with\n(test-runner-current r) before any fiber was spawned would read back\nas #f afterwards. Reads now fall through fiber overrides to the\nVM-level map before the parameter's default. Writes are unchanged, and\nonce a scheduler exists they all target fiber maps, so the VM-level\nlayer is effectively a frozen pre-scheduler base that spawned fibers\ncorrectly inherit through the same fallback.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-03T07:25:46Z",
          "tree_id": "ea29041846664779718c76271aada0a560ad93f8",
          "url": "https://github.com/kaappi/kaappi/commit/0b148c5e2f43d5c2086b14d429d5d8088f042704"
        },
        "date": 1783064469792,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.463701,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.636852,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.857695,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.222359,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007054,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.033077,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.468866,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.07053,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.073255,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.800474,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.140545,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.433109,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.430468,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.685288,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044435,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "5da1588bd339a8bde2430f3cd8ff0ce75073cdb5",
          "message": "Fix SRFI-64 suite silently asserting nothing; flip exit code on script errors (#929)\n\n* Fix SRFI-64 suite silently asserting nothing; flip exit code on script errors\n\nThe entire tests/scheme/ suite (except the R7RS suite) was a silent no-op:\nevery SRFI-64 assertion errored at runtime yet files exited 0, so\nrun-all.sh reported all 237 files as PASS. Three stacked bugs, present\nsince before v0.10.0:\n\n1. importBinding copied an exported macro's template free references from\n   the defining library's env only one level deep. test-assert expands\n   into the internal macro %test-comp1body, whose own references\n   (%test-on-test-begin etc.) were never copied, so use-site expansions\n   hit \"undefined variable\". Free references are now copied transitively\n   through macro-to-macro chains with cycle protection.\n\n2. renameForHygiene checked the global-procedure preservation heuristic\n   before the scope table, so a template binding named after a builtin\n   ((let ((exp expected)) ... exp)) renamed the binder but resolved body\n   references to the global builtin: every test compared against\n   #<builtin exp>. The scope table is now consulted first.\n\n3. set_global lacked the stripHygienicPrefix fallback that get_global and\n   call_global already had, so template (set! counter ...) writes to\n   definition-site globals failed as unbound __hyg_N_ names.\n\nSeparately, uncaught read/compile/runtime errors in scripts (file or\nstdin) now flip the process exit code so run-all.sh can never report PASS\non errored files again. Explicit (exit N) still wins; the REPL is\nunaffected. This immediately surfaced ~10 pre-existing product bugs that\nthe dead suite had been hiding (call/cc escapes, hash-table-update!/\ndefault, case-lambda arg binding, SRFI-35 condition macro, SRFI-133\nvector-partition, library declaration bugs, srfi18 hang) — tracked\nseparately; CI stays red until they land.\n\nTest changes: ellipsis-mismatch.scm's negative case moved to\nerror-format.sh (the mismatch is rejected at expansion/compile time,\nwhich guard cannot catch and which now fails the process); run-all.sh's\nretry with the removed --no-jit flag dropped.\n\nFixes #924\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n* Fix two Linux-only failures surfaced by exit-code enforcement\n\nBoth bugs were invisible on Linux CI because uncaught errors exited 0:\n\n- validateMode bounded modes by maxInt(mode_t), which is u16 on macOS but\n  u32 on Linux, so set-file-mode/set-umask! accepted out-of-range values\n  like 100000 on Linux. POSIX permission modes use only the low 12 bits;\n  bound by 0o7777 on all platforms.\n\n- ffi-open never tried a \".so\" suffix outside ~/.kaappi/lib: bare names\n  like \"libm\" only got as-is and \".dylib\" attempts, so opening a system\n  library by basename never worked on Linux. Try \".dylib\", \".so\", and\n  \".so.6\" (glibc's core libraries ship an unversioned .so that is a\n  linker script dlopen cannot load).\n\nCovered by the existing tests/scheme/ffi/ suite and\ntests/scheme/smoke/filesystem-intcast.scm, which now run with live\nassertions and exit codes on both platforms.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-03T07:48:29Z",
          "tree_id": "1cd7389d513066772b1f054c2ed07802fdbf4538",
          "url": "https://github.com/kaappi/kaappi/commit/5da1588bd339a8bde2430f3cd8ff0ce75073cdb5"
        },
        "date": 1783065822482,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.177806,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.480099,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.880288,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.197468,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007433,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.03291,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.475234,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068026,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.008486,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.779305,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.154403,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.474594,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.400894,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.893595,
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
          "id": "3864fd83387fb33dc96ed945eac494e3fcd2e84a",
          "message": "Retire replaced library envs instead of freeing them (#941)\n\nRe-registering a library (a second define-library with the same name)\nfreed the old library's lib_env, but closures compiled in the old\nlibrary's begin block still hold Function.env pointers to it and can\noutlive the library by escaping into vm.globals via import. Calling\nsuch a closure afterwards dereferenced the freed StringHashMap —\nuse-after-free that panics or silently corrupts memory.\n\nDetach the replaced env into a retired_envs list owned by the registry\nand free it only at registry teardown, and trace retired envs in\nmarkVMRoots so values reachable only through them (like non-exported\nlibrary internals) survive GC. The small leak is bounded by the number\nof re-registrations, which only happen when a program or REPL session\nredefines a library.\n\nFixes #820\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-03T14:05:40+05:30",
          "tree_id": "2d8bc78e631540947c2ca771b718148c275123e5",
          "url": "https://github.com/kaappi/kaappi/commit/3864fd83387fb33dc96ed945eac494e3fcd2e84a"
        },
        "date": 1783068618698,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.423291,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.445179,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.847584,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.382736,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006886,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.033201,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.464549,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069534,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.09876,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.809504,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.136457,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.438357,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.485852,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.702144,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042438,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "6fab131e061f36ff6dafe393cc28bf3f774c35f0",
          "message": "Fix SRFI-64 test-end template in tests/scheme/CLAUDE.md (#943)\n\nThe documented template called (test-runner-current) after the outermost\n(test-end ...), but test-end resets the current runner, so the follow-up\ncall no longer returns the runner and test-runner-fail-count raises a type\nerror. Capture the runner before test-end, matching the pattern already\nused by existing smoke tests.\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-03T14:12:09+05:30",
          "tree_id": "b5037c3d7a22d30796ab0e48a031827682c5d943",
          "url": "https://github.com/kaappi/kaappi/commit/6fab131e061f36ff6dafe393cc28bf3f774c35f0"
        },
        "date": 1783068855009,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.438536,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.167766,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.821226,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.36761,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006886,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.033152,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.462426,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069545,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.113099,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.811679,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.125258,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.430023,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.400974,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.503509,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042063,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "117af15862427e183ac23bbdc8b62b48fbb700f3",
          "message": "Root vector-partition yes/no accumulators (#810) (#944)\n\nThe #335 fix rooted intermediate results in vector-map, vector-unfold,\nand vector-cumulate but never touched vectorPartitionFn, even though\n#335 named its un-rooted yes/no accumulators as the same root cause.\n\nThe predicate runs arbitrary Scheme and can mutate the source vector.\nOnce an element is displaced from the vector, its only reference is the\nallocator-backed yes/no list, which the GC cannot see — the next\ncollection (a later predicate call, or the allocVector before the buffer\ncopy) frees it and hands back a recycled heap slot.\n\nApply the same extra_roots save/restore pattern vectorMapFn uses: root\neach element as it is classified so it survives later predicate calls.\n\nRegression test in vector-map-gc.scm: predicate mutates the source and\nchurns the heap; without the fix the first partition element returns as\na recycled object.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-03T09:00:32Z",
          "tree_id": "8bab79e36118a63ff65d55d3cdbaa418f537eddd",
          "url": "https://github.com/kaappi/kaappi/commit/117af15862427e183ac23bbdc8b62b48fbb700f3"
        },
        "date": 1783070057371,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.414215,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.216938,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.821319,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.450771,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007018,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032795,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.461114,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069569,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.05365,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.775975,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.137514,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.425617,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.378086,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.666127,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042229,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "95ff929fbd43ca5797c8bfd22aad05b7567e6dc8",
          "message": "thottam: copy visited-set keys to fix use-after-free on transitive deps (#947)\n\ndoInstall's cycle/dedup guard stored package-name keys by reference. For\na transitive dependency the name is a sub-slice of the caller's\nmanifest.depends buffer, which manifest.deinit frees when the caller's\ninstall frame unwinds — leaving dangling keys. Every later visited\nget/put bucket probe then read freed memory (use-after-free), and the\ndedup guard silently degraded (a diamond dependency printed \"rd already\ninstalled\" instead of a silent visited-hit early return, only avoiding\ndouble work because installed.txt caught it afterwards).\n\nExtract the guard into markVisited (inserts an owned dupe of the key)\nand freeVisited (frees the keys before deinit), so the map owns its keys\nfor its whole lifetime. Add a regression unit test that records a name,\nfrees the backing buffer, and re-probes — it faults on the dangling key\nwithout the fix.\n\nFixes #784\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-03T09:07:56Z",
          "tree_id": "539d9db0db9cc8bfc956bd8907d3891543c8c619",
          "url": "https://github.com/kaappi/kaappi/commit/95ff929fbd43ca5797c8bfd22aad05b7567e6dc8"
        },
        "date": 1783070426151,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.43612,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.556185,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.852221,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.367714,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007033,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032647,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.463596,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069487,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.029979,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.776812,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.153653,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.435214,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.390887,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.732848,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043146,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "ed919ae35032960a7f988e62345615bd8f03f6bb",
          "message": "Add /do-linux-test skill for x86-64 Linux testing via DigitalOcean (#946)\n\n* Add /do-linux-test skill for x86-64 Linux testing via DigitalOcean\n\nCreates a temporary DigitalOcean droplet (s-2vcpu-4gb, Ubuntu 24.04)\nto run the full Kaappi test suite on real x86-64 hardware. Complements\nthe existing /linux-test skill which uses podman with emulation.\n\nThe workflow: create droplet → install Zig 0.16 → clone repo at\ncurrent branch → build → unit tests → Scheme test suites → destroy.\nDroplet is always destroyed, even on failure/timeout.\n\nCloses #942\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Fix /do-linux-test skill based on real-world test run\n\nSplit the single SSH session into separate provision/build/unit-test/scheme-test\ncommands to avoid hitting the Bash tool's 14-minute timeout. Add apt lock wait\nfor fresh droplets, use ln -sf for idempotent Zig install, and add\nServerAliveInterval to keep connections open during long compile tests.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Add lessons learned from first test run to /do-linux-test skill\n\n- Redirect Scheme test output to file on remote so results survive\n  SSH disconnects; fetch separately\n- Document bash guard hook caveat (blocks rm -rf in SSH heredocs)\n- Document macOS timeout absence (use split commands instead)\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Add 55-minute self-destruct timer to /do-linux-test skill\n\nAfter SSH is up, install a background process on the droplet that calls\nthe DO API to delete itself after 55 minutes. Guarantees the droplet is\ndestroyed even if the Claude session dies mid-run.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-03T14:55:53+05:30",
          "tree_id": "24dd5031a2e504bb72987555f523de658e44a6de",
          "url": "https://github.com/kaappi/kaappi/commit/ed919ae35032960a7f988e62345615bd8f03f6bb"
        },
        "date": 1783071729043,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.180016,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.231051,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.861802,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.284465,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00727,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.033287,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.474279,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069002,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.017112,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.795466,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.16039,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.469496,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.40021,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.876678,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045563,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "c628cc2e84708d1f717f0b44bbdaf1638ef10f28",
          "message": "Lock symbol_mutex unconditionally in allocSymbol (#797) (#945)\n\nallocSymbol only took symbol_mutex when the calling GC was a child\n(shared_symbols != null). The parent thread — whose `symbols` field *is*\nthe shared table children alias — interned with no lock. While an SRFI-18\nchild thread was alive, a parent-side string->symbol raced the child's\nlocked get/put on the same StringHashMap; a put that rehashes reallocs and\nfrees the bucket array, corrupting the map and panicking (\"reached\nunreachable code\") in the parent's put.\n\nTake the lock unconditionally so parent and child serialize on the same\ntable. This is deadlock-free by the argument already documented in\ngc_collect.zig markRoots: allocSymbol never calls maybeCollect, so a thread\ncan never re-enter GC marking (which also takes symbol_mutex) while holding\nit here. The trackObject decision keeps using the child/parent distinction\n(now `is_child`), which is independent of locking.\n\nUpdate the now-stale markRoots comment that claimed the parent never holds\nsymbol_mutex in allocSymbol.\n\nRegression test tests/scheme/srfi/srfi18-symbol-race.scm interns 200k\ndistinct symbols on the parent while a child does the same; crashes 3/3 on\nthe unfixed build, passes with the fix.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-03T09:30:24Z",
          "tree_id": "e1f24b2ca5645036f332f9b2e09f49d19f15813d",
          "url": "https://github.com/kaappi/kaappi/commit/c628cc2e84708d1f717f0b44bbdaf1638ef10f28"
        },
        "date": 1783071890145,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.128809,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.508319,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.869847,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.248895,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007293,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032942,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.473279,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.06808,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.044634,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.810243,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.154525,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.476256,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.39722,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.874186,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045629,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "14e7093a7a17a420b5050ccdcef9656e89267415",
          "message": "Compare rationals exactly instead of falling back to f64 (#844) (#949)\n\nNumeric comparisons (=, <, >, <=, >=) lost precision whenever a rational\nwas involved. cmpPair's rational-vs-rational branch only handled operands\nwhose parts fit i48 fixnums with i64 cross-products that didn't overflow;\nanything else — bignum parts, overflow, or rational-vs-bignum — silently\nfell through to an f64 comparison. Rational-vs-flonum had no exact branch\nat all and always converted the exact side to a double.\n\nTwo user-visible consequences: distinct exact numbers within one double\nULP compared equal (e.g. (2^100+1)/2^101 = 1/2), and exact-vs-inexact\ncomparisons were non-transitive, e.g. (= 1/3 0.3333333333333333) => #t,\nviolating R7RS 6.2.6.\n\nRoute all exact-vs-exact comparisons through bignum cross-multiplication\n(na*db vs nb*da; denominators are positive) after the existing i64 fast\npath, covering rational-vs-rational, rational-vs-fixnum, and\nrational-vs-bignum without precision loss. Compare rational-vs-flonum\nagainst the flonum's exact value (a finite double is exactly\nmantissa*2^exp) so the predicates stay transitive across the\nexact/inexact boundary. Integer-vs-flonum fast paths are unchanged, so\ncommon comparisons keep their non-allocating path.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-03T09:56:59Z",
          "tree_id": "cb404a833e378eadfef8e97fa23bb7f3270b9b6c",
          "url": "https://github.com/kaappi/kaappi/commit/14e7093a7a17a420b5050ccdcef9656e89267415"
        },
        "date": 1783073488139,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.5608,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.007236,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.845607,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.227564,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006952,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.0329,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.462821,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069997,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.113531,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.792575,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.176729,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.427006,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.413764,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.663967,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043259,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "ddfe8d9c9780dde93554022c8e18832018e7b1e0",
          "message": "Track child-interned symbols on parent GC to fix leak (#950)\n\nA symbol first interned by an SRFI-18 child thread went into the parent's\nshared symbol table, but GC.allocSymbol skipped trackObject for child GCs,\nso the Symbol landed on no GC's object list: the child's sweep/deinit never\nfreed it and the parent never knew about it. Every distinct child-interned\nsymbol leaked its Symbol struct plus its name dupe.\n\nSymbols the child interns must outlive the child, since the parent's shared\ntable keeps referencing them, so ownership belongs to the parent. Pushing\nonto the parent's lock-free objects list from a child thread is unsafe, so\nadd a dedicated foreign_symbols list on the owner GC, appended under the\nsymbol_mutex allocSymbol already holds and freed at the parent's deinit.\nInterned symbols are permanent (marked as roots every GC, never swept), so\nthe list needs no sweep interaction.\n\nOrthogonal to #797, which only changed the locking, not the trackObject\ndecision. Regression covered by a unit test under std.testing.allocator\n(fails without the fix) plus a Scheme reproduction observable under the\nDebug leak-checking allocator.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-03T09:58:37Z",
          "tree_id": "e2b788b64c01be3ddec20b11cca578b69c099d77",
          "url": "https://github.com/kaappi/kaappi/commit/ddfe8d9c9780dde93554022c8e18832018e7b1e0"
        },
        "date": 1783073594035,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.076274,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.225409,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.841831,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.429093,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007244,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032645,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.463168,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.067598,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.983623,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.776199,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.150742,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.471991,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.364243,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.867814,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044378,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "75616fa48aa96aff5c2a5199a6ab406afd315d9e",
          "message": "Probe upvalues when checking if a keyword is shadowed (#814) (#951)\n\ncompileForm's shadowing guard consulted only resolveLocal, so a\nsyntactic keyword (if, and, begin, when, ...) shadowed by a variable\nbound in an enclosing function scope — resolving as an upvalue — was\nstill compiled as the special form instead of a procedure call. R7RS\nhas no reserved words: a lexical binding shadows the keyword throughout\nits scope, including inner lambdas. The same-scope case already worked,\nso this was an inconsistency in the implementation's own feature.\n\nMirror the dual local+upvalue check already used for apply (#760) and\nmacro keywords. The cheap effective_name == name comparison is checked\nfirst so hygienic renames short-circuit before touching resolveUpvalue,\nwhose upvalue-registration side effect is harmless for genuinely\nshadowed names (they compile to a call referencing that same upvalue).\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-03T10:09:52Z",
          "tree_id": "c03b70d18cd1ab6c92b391459ceff6dc697dfc81",
          "url": "https://github.com/kaappi/kaappi/commit/75616fa48aa96aff5c2a5199a6ab406afd315d9e"
        },
        "date": 1783074406056,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.398711,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.764434,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.821447,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.122075,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006903,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.03307,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.45569,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069766,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.174123,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.752474,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.161316,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.435763,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.368737,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.699147,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043061,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "f462e0ab32c159810455a401f311a6f3275f26d3",
          "message": "gc_deep_copy: iterate cdr spine to fix stack overflow on long lists (#801) (#952)\n\ndeepCopyValue recursed on both car and cdr of every pair, so the cdr\nrecursion went N frames deep for a proper list of N elements. Deep copy\nruns at every SRFI-18 thread boundary (thunk closure at thread-start!,\nresult at thread-join!), so passing a flat list of a few tens of\nthousands of elements to or from a thread overflowed the native stack\nand killed the whole process with a Bus error — lists >=~15k crashed.\n\nWalk the cdr spine in a loop, allocating and linking each successor\npair, and recurse only on car. Native recursion is now bounded by\nstructural nesting depth rather than list length. Each spine pair is\nregistered in `visited` before its car is copied, so shared and cyclic\nstructure resolves exactly as before. This mirrors the worklist fix\napplied to the GC marker for #864.\n\nAdd Zig unit tests copying 200k-element proper and improper lists (both\nwould previously crash), plus a Scheme smoke test exercising both thread\ndirections from the issue's reproduction.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-03T10:13:54Z",
          "tree_id": "20b16771f5aab0a70609c948ce591da3569c96cc",
          "url": "https://github.com/kaappi/kaappi/commit/f462e0ab32c159810455a401f311a6f3275f26d3"
        },
        "date": 1783074765180,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.419702,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.69433,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.812294,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.112722,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006903,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032933,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.45679,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070124,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.059321,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.763687,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.209117,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.428777,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.367485,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.709048,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042899,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "fbaf9fb6239701b13ce2a6f78555e93278c4bfd6",
          "message": "Fix panic on closures capturing 27+ variables (#809) (#953)\n\nTwo distinct u8-overflow panics on legal programs:\n\n- allocClosure computed its byte accounting in u8 arithmetic\n  (upvalue_count is u8), overflowing at 27 captures (27*8 + 40 > 255)\n  and aborting the process on every closure creation. Widen the\n  arithmetic to usize.\n\n- addUpvalue @intCast'd the upvalue count into a u8 upvalue_count field,\n  panicking past 255 captures. Widen upvalue_count to u16 (matching the\n  u16 locals_count and the u16 upvalue index already used in the\n  bytecode) so 256+ captures work, and cap the count gracefully at the\n  u16 limit with a CompileError instead of a panic.\n\nSerializing upvalue_count as u16 bumps the .sbc format to v5; stale v4\ncaches are rejected on version mismatch and recompiled.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-03T10:18:34Z",
          "tree_id": "6a7cb02e578ea6ac468f99cf52a7e56a9cfcfffc",
          "url": "https://github.com/kaappi/kaappi/commit/fbaf9fb6239701b13ce2a6f78555e93278c4bfd6"
        },
        "date": 1783074886547,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.414608,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.489819,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.80338,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.120654,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006838,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032412,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.457598,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069546,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.093353,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.749161,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.149048,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.426738,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.33876,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.661713,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042034,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "0f9d56cc13506b0562215cf8026fcd2688b8c357",
          "message": "Clear global cache on set_global/define_global rebind (#812) (#955)\n\nset_global and define_global bumped global_version but then re-stamped\nthe whole Function cache as current after refreshing only their own slot.\nAny entry cached before an unrelated rebinding (which had already bumped\nglobal_version) was re-blessed and served stale by the cache-hit fast\npaths in get_global/call_global/tail_call_global.\n\nMirror get_global's version-mismatch path: memset the cache to VOID\nbefore revalidating the written slot, so stale entries are re-checked\nagainst the environment on next access.\n\nAdd regression tests covering set_global (call + tail position),\nget_global (reference position), and define_global (via named let).\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-03T15:58:29+05:30",
          "tree_id": "67569d216dc817d74e398ee1adb9e2ff8e48b90e",
          "url": "https://github.com/kaappi/kaappi/commit/0f9d56cc13506b0562215cf8026fcd2688b8c357"
        },
        "date": 1783075386392,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.061259,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.36491,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.843904,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.107879,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007348,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032615,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.461279,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068261,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.06277,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.776939,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.159116,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.474929,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.355431,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.862776,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044719,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "9e00a482162eb61bf89834e1d5f68c6aae393f8d",
          "message": "Respect lexical shadowing of primitives in IR constant folding (#790) (#956)\n\nThe IR constant-folding and boolean-simplification passes guarded only\nagainst global redefinition of primitives via isRedefined(), which\nconsults the globals map. Lambda parameters that shadow +, -, *, <, =,\nzero?, not, etc. are lexical bindings the globals map never sees, so\nfolds fired using the built-in's semantics and produced silently wrong\nresults — e.g. ((lambda (+) (+ 1 2)) -) yielded 3 instead of -1.\n\nLambda bodies are lowered through the IR by compileLambdaWithIR, which\nregisters parameters as compiler locals but never told the IR about\nthem. Teach isRedefined about lexical scope:\n\n- Add Compiler.isLexicallyBound, a side-effect-free predicate that walks\n  the compiler's locals and parent chain (unlike resolveUpvalue, which\n  registers upvalues). Point IR.compiler at the enclosing compiler at\n  every IR.init site so isRedefined can consult it.\n- The LLVM native backend has no Compiler, so add IR.bound_names and\n  pass each lambda's own parameter names from llvm_emit_lambda.zig; it\n  exhibited the same bug.\n\nThe check only makes folding more conservative, so it can never\nintroduce an incorrect fold. Regression tests (Zig unit tests, a smoke\ntest, and a native-compile test) fail on the pre-fix build and pass\nafter. The smoke test uses the manual-check procedure-argument style\nbecause SRFI-64's test-eqv forces the already-correct legacy path.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-03T10:47:31Z",
          "tree_id": "3eef50bdc514f90e8132ad58925f7ef3d213aca9",
          "url": "https://github.com/kaappi/kaappi/commit/9e00a482162eb61bf89834e1d5f68c6aae393f8d"
        },
        "date": 1783076559432,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.283,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.560388,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.811222,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.07354,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006992,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.033351,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.45549,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069022,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.031157,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.765381,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.219944,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.42745,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.368875,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.645482,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.040841,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "4e71f21ba735004f1a5e512aed3c63970e2805f4",
          "message": "Fix thottam version-pinned install: use --end-of-options not -- (#780) (#960)\n\nArguments after `--` in `git checkout` are pathspecs, not refnames, so the\n#736 option-injection guard (`checkout --quiet -- <ref>`) made git try to\nrestore a file named after the tag/SHA and fail with \"pathspec did not match\nany file(s)\". This broke every version-pinned install: `pkg@v1.0.0`, semver\nconstraints, and `--locked`.\n\nUse `--end-of-options` (git 2.24+) instead: it stops flag parsing — keeping\nthe injection guard — while still resolving the argument as a revision. The\ncheckout is extracted into a documented `checkoutVersion` helper so the exact\nargument list is exercised by a regression test against a local tagged repo.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-03T11:02:49Z",
          "tree_id": "2a12886def82dfa758d9b5cc67a17ca20186ceb5",
          "url": "https://github.com/kaappi/kaappi/commit/4e71f21ba735004f1a5e512aed3c63970e2805f4"
        },
        "date": 1783077475618,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.029599,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.145173,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.845182,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.129368,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007476,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032724,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.464316,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068223,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.006586,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.784998,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.143977,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.472596,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.354798,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.815227,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044889,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "1388eeb4a6d6782e95b039143c811d180bc9ebb6",
          "message": "Expand (scheme r5rs) to the full R5RS identifier set (#813) (#965)\n\nThe built-in (scheme r5rs) library exported only 4 identifiers\n(null-environment, scheme-report-environment, eval,\ninteraction-environment). Per R7RS Appendix A it must provide the full\nR5RS set (~180 procedures plus syntax). A prefix import exposed the gap:\n`(r5:car '(1 2))` raised \"undefined variable 'r5:car'\".\n\nA complete-ish implementation existed at lib/scheme/r5rs.sld, but it was\npermanently shadowed — processImportSet consults the built-in registry\nbefore falling back to .sld loading, so the 4-name stub always won. That\n.sld was also itself incomplete (missing null-environment,\nscheme-report-environment, char-ready?, assoc/assq/assv, call/cc, etc.).\n\nRather than depend on an external file for a standard library (unlike\nevery other (scheme X), which are self-contained Zig registrations), the\nstub is expanded to the full Appendix A table, re-exporting from globals.\nexact->inexact / inexact->exact / interaction-environment are already\nregistered as globals under their R5RS names, so no renaming is needed.\nSyntactic keywords are recognized by the compiler, so the globals.get\nguard skips them — same as (scheme base).\n\nThe now-redundant, shadowed lib/scheme/r5rs.sld is removed, and the\nrelease bundle no longer references the emptied lib/scheme/ directory.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-03T11:31:31Z",
          "tree_id": "91a5c53d83227a1a35e01fc61d6958da78e3ec21",
          "url": "https://github.com/kaappi/kaappi/commit/1388eeb4a6d6782e95b039143c811d180bc9ebb6"
        },
        "date": 1783079233184,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.038879,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.639554,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.865608,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.136825,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007318,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032572,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.463583,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068424,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.985642,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.77584,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.15755,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.48186,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.389712,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.898213,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.04434,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "8764f2ee6a6948fa258f544aad92dbaebe8e7a1c",
          "message": "Scope library-body define-syntax macros to their library (#877) (#957)\n\ndefine-syntax inside a library begin block registered the macro directly\ninto the process-global vm.macros table while the library body was being\ncompiled. Two observable bugs followed: unexported library-body macros\nbecame usable by all code once the library loaded (even when the importer\nfiltered them out), and loading a library silently clobbered a same-named\nmacro the program had explicitly imported from another library.\n\nLibrary-body macros now live in the per-library lib_env (already GC-rooted\nand already home to imported transformers) instead of vm.macros:\n\n- compileDefineSyntax stores a library-top-level macro in lib_env.\n- compileLibExpr seeds the compiler's macro table from lib_env's transformer\n  entries, so a library body compiles hermetically without reading or\n  writing the global macro table.\n- Export resolution reads lib_env only; the vm.macros fallback (which only\n  worked because of the leak) is removed.\n- copyTransformerFreeRefs registers an exported macro's transitively\n  referenced private helper macros into the importer's macro namespace on\n  demand, so use-site expansion still resolves them (e.g. SRFI-64\n  test-assert -> %test-comp1body). importBinding remains the only path into\n  vm.macros.\n\nRegression test tests/scheme/smoke/library-macro-leak-877.scm with lib877/\nfixtures covers the leak, the clobber, cross-library macro import, and an\nexported macro that expands through a private helper.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-03T11:39:07Z",
          "tree_id": "9a620a1617bc3164e3f0f2bc65fbebbb9bc48de9",
          "url": "https://github.com/kaappi/kaappi/commit/8764f2ee6a6948fa258f544aad92dbaebe8e7a1c"
        },
        "date": 1783079857552,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.356066,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.032669,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.837357,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.107023,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006922,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032676,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.459661,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069938,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.071946,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.76575,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.169058,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.435768,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.363463,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.741131,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042563,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "f5524e14eea47f4ac11acd586f0d98ec5fe73bd8",
          "message": "Fix LLVM backend set!/define ignoring lexical scope (#819) (#966)\n\nIn the native backend, set! and internal define always emitted\nkaappi_define_global regardless of whether the target was a parameter,\na let-local, an upvalue, or a global. Mutations to lexical variables\nwere silently dropped, set! values referencing lexical variables were\nevaluated in the global environment (and crashed), top-level set! on an\nunbound variable silently defined it, and internal defines leaked to\nglobal scope.\n\nemitSet now evaluates the value with lexical scope respected and stores\nit into the slot the target denotes (local alloca, parameter %args slot,\nrest-param alloca, upvalue, or — for a real global — the new\nkaappi_set_global runtime export, which errors on unbound to match the\ninterpreter). emitDefine creates a fresh local binding for internal\ndefines inside a natively compiled let body instead of overwriting a\nglobal. At the top level, values are still evaluated via kaappi_eval so\nmacro calls in set!/define values keep expanding.\n\nThe free-variable analysis now inspects set_form/define, and\ntryCompileNativeClosure rejects any body containing set!/define, so a\nlambda that mutates or rebinds a captured variable (e.g. make-counter)\nfalls back to the interpreter instead of miscompiling — a native closure\ncopies its upvalues by value and cannot express shared mutation.\nemitLambdaFunction also nulls the locals map for the fresh function\nscope, fixing a latent case where an outer scope's allocas leaked in as\ninvalid IR.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-03T11:47:39Z",
          "tree_id": "0656a5583d6fb2e3234385b55cdd687269796014",
          "url": "https://github.com/kaappi/kaappi/commit/f5524e14eea47f4ac11acd586f0d98ec5fe73bd8"
        },
        "date": 1783080297886,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.36256,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.92611,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.823231,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.10171,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006977,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.03346,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.462202,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070329,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.14395,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.92687,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.206355,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.426509,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.368774,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.649211,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.041574,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "75f6c1351cb3e0d93eeb01b8b44ef9ed4b6a57da",
          "message": "Honor lexical shadowing of keywords in IR lowering (#788) (#967)\n\nIR lowering dispatched special forms (if, and, begin, quote, when, ...)\npurely by symbol name, ignoring lexical scope. A lambda parameter that\nshadowed a keyword was still compiled as the special form instead of a\ncall to the parameter — eliminateDeadBranches even folded (if 1 2 3) to a\nconstant. R7RS has no reserved words, so a lexical binding must shadow the\nsyntax; the legacy compileForm path already did this via its is_shadowed\nguard, but the IR path (used for lambda bodies) had no access to locals.\n\nThread the compiler's lexical scope into the IR: add an optional compiler\nreference to IR, guard the special-form/macro dispatch with a shadow check\n(mirroring compileForm), and extend isRedefined so a shadowed primitive\nisn't constant-folded as the builtin. The new isLexicallyBound probe is\nread-only (walks locals + parent chain, registers no upvalues), so it is\nsafe to call during lowering. Hygienic renames keep their special-form\nmeaning because the guard requires effective_name == name.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-03T11:54:17Z",
          "tree_id": "2375afda90c095f022acb1c1df7590cdf940f8d0",
          "url": "https://github.com/kaappi/kaappi/commit/75f6c1351cb3e0d93eeb01b8b44ef9ed4b6a57da"
        },
        "date": 1783080575771,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.343774,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.792711,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.836088,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.077039,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006889,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032656,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.456325,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068831,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.039744,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.77535,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.166617,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.435144,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.374747,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.657993,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.041167,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "aca967d30d6a7a00fcc3ec6d5317993971d8cd20",
          "message": "Exit non-zero on CLI usage and compile/standalone errors (#964)\n\nThe interpreter exited 0 for every kind of failure except an explicit\n(exit n), so shell scripts, Makefiles, and CI could not detect that\nkaappi was misinvoked or that a build/bundled step failed. Script\nread/compile/runtime errors already flip the exit code (#929); this\nextends the same guarantee to the remaining silent paths.\n\nCommand-line usage errors now exit 2 (getopt convention, distinct from\nthe 1 used for script failures): a missing argument to a value-taking\nflag (--lib-path, --timeout, --max-memory, -o, --coverage-xml,\n--profile-json, --completions), an unknown --completions shell, a\nbuild/inspect mode invoked with no file, and — new — an unknown flag,\nwhich was previously swallowed as a script filename and hid the typo.\n\nCompile-time and bundled-app failures now exit 1: --compile and\n--disassemble read/compile errors, and standalone-binary runtime,\npreamble, and corrupt-embedded-bytecode errors.\n\nExtends tests/scheme/errors/exit-code.sh with 19 new cases covering the\nusage and compile-mode paths.\n\nFixes #781\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-03T12:30:04Z",
          "tree_id": "49409ee6240e0c301736349f213976f85a98df25",
          "url": "https://github.com/kaappi/kaappi/commit/aca967d30d6a7a00fcc3ec6d5317993971d8cd20"
        },
        "date": 1783082622317,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.41391,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.020468,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.837705,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.217694,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006831,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032636,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.465618,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070615,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.172703,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.76798,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.159241,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.434992,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.379835,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.720767,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.048273,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "62b6b3320330b4996d07796bfed0592e2a09042f",
          "message": "Use trailing -- instead of --end-of-options in pinned checkout (#969) (#974)\n\ngit checkout only learned --end-of-options in git 2.43; older builds\n(such as the Apple git on the rolled-out macos-latest runner image)\ntreat it as a pathspec and fail with \"pathspec '--end-of-options' did\nnot match any file(s) known to git\", breaking every version-pinned\ninstall and the issue #780 regression test.\n\nSwitch to `git checkout <v> --`, which every git version parses as a\nrevision — even when a file with the same name as the tag exists. Since\n<v> now sits in option-parsing position, reject empty and leading-dash\nversions in checkoutVersion itself to keep the option-injection guard\nfrom #736; no valid tag, branch, or SHA starts with '-'.\n\nStrengthen the #780 test with a tracked file shadowing the tag name so\na pathspec mis-parse fails visibly, and add a #736 guard test.\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-03T13:46:18Z",
          "tree_id": "d056863cc5e78a9a5b2c62085d1dca457e0b0e4f",
          "url": "https://github.com/kaappi/kaappi/commit/62b6b3320330b4996d07796bfed0592e2a09042f"
        },
        "date": 1783087313044,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.77128,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.562592,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.797874,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.750307,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006948,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.031225,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.415787,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.06549,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.100997,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.617474,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.130413,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.404954,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.597503,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.963422,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.038464,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "55932339e7dde6a25360f51432599880e2950d60",
          "message": "Deep-copy native_fn/native_closure instead of aliasing across heaps (#975)\n\ndeepCopyValue returned the source-heap pointer for native_fn and\nnative_closure objects. For SRFI-18 OS threads the child->parent copy at\nthread-join! is followed immediately by freeing the child heap, so a\nthread result containing one of these left the parent holding a dangling\npointer into freed memory (follow-up to the issue #958 marking fixes --\nthis was the remaining aliasing hole in deepCopy itself).\n\nBoth types are safely copyable: the fn pointer and name are static (string\nliterals from primitives.reg, or code/rodata of a native binary), so a\nfresh object is allocated in the target GC and NativeClosure upvalues are\ndeep-copied. The new closure is registered in the visited map before its\nupvalues are copied so shared and cyclic references resolve, and upvalues\nstart as VOID placeholders so an aborted copy never leaves cross-heap\npointers in the target object.\n\nffi_library/ffi_function stay aliased deliberately: they wrap\nprocess-global dlopen handles that cannot be duplicated per-heap. The\nknown limitation (a child-created FFI handle returned through\nthread-join! still dangles) is now documented at the site.\n\nRegression tests: four unit tests in tests_deepcopy.zig -- without the\nfix three fail on aliasing assertions and the \"survive freeing the source\nheap\" test, which replays the join scenario by deiniting the source GC\nbefore reading the copy, dies with SIGABRT -- plus an end-to-end\nthread-join! test in tests_srfi18.zig that returns primitives from a\nthread and calls the copies.\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-03T13:53:50Z",
          "tree_id": "c38fc14bf7ab25aa8a193d007d46a2f43b72d288",
          "url": "https://github.com/kaappi/kaappi/commit/55932339e7dde6a25360f51432599880e2950d60"
        },
        "date": 1783087792702,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.422084,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.855447,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.849815,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.306754,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006564,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032732,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.47076,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070585,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.004428,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.826769,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.165426,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.436577,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.785916,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.73204,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043413,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "3fd0eaa77f4d70ed1d1c907ccc862c19366618a2",
          "message": "Show message and irritants for uncaught user-raised errors (#976)\n\nAn uncaught (error \"msg\" irritants...) printed only the raw Zig error\nname (\"runtime error: error.ExceptionRaised\") because execute()'s error\npath calls resetExecutionState(), which discards current_exception\nbefore the top-level printers in main.zig/repl.zig can read it — so\ngetErrorDetail() was empty and they fell back to the error name.\n\nPopulate the error detail from the pending exception in execute()'s\nerror path, before the reset. Error objects format as\n\"message irritant1 irritant2 ...\" (message displayed, irritants\nwritten); other raised values as \"uncaught exception: <value>\". Native\ndiagnostics are never overridden: the dispatch loop zeroes the detail\nbuffer before each native call, so a non-empty buffer at raise time is\nalways a specific native error. Exceptions caught by guard or\nwith-exception-handler are consumed inside run() and never reach this\npath, and SRFI-18 threads use callWithArgs, so thread-join! exception\npropagation is unaffected.\n\nSince every top-level form runs through execute() — script files, the\n.sbc cache path, bundled binaries, the interactive REPL, piped stdin,\nand library bodies executed during import — one hook fixes all modes.\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-03T13:55:31Z",
          "tree_id": "5ab5942aaa7fbb10d41a592c77d74db701f9f4c7",
          "url": "https://github.com/kaappi/kaappi/commit/3fd0eaa77f4d70ed1d1c907ccc862c19366618a2"
        },
        "date": 1783087890401,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.355309,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.204224,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.853905,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.249334,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006729,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.034282,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.472,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.071484,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.036805,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.826168,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.201482,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.433041,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.8026,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.700222,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.041938,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "1ba4e8df6dca95633649ed8e24d1b1632593646d",
          "message": "Print all values of a multiple-values result at the top level (#972) (#973)\n\nEvery top-level result-printing path truncated a multiple-values result\nto its first value, so (values 3 2) printed just 3. The interactive\nREPL's compiled path was worse: it didn't unwrap at all and echoed the\nraw object (#<values 3 2>). Chez, Guile, Racket, and Chibi all print\neach value on its own line — match that everywhere: interactive REPL,\npiped stdin, file execution (fresh and .sbc-cached), and bundled\nbinaries. (values) and void values print nothing.\n\nThe six copies of the unwrap block in main.zig collapse into one\nprintTopLevelResult helper. In repl.zig the fix must handle .store_last\nmode (the REPL main loop evaluates with it, not .normal); _ still binds\nthe first value and ,type still reports the first value's type.\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-03T14:00:48Z",
          "tree_id": "c382a3451dffa4760b89d014ea7dfa3f94b4a517",
          "url": "https://github.com/kaappi/kaappi/commit/1ba4e8df6dca95633649ed8e24d1b1632593646d"
        },
        "date": 1783088144202,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.382544,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.860103,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.849179,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.266793,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006396,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.033255,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.475041,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.071496,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.161099,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.824731,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.163842,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.441404,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.784368,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.720108,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045458,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "d0414d88001d2b558172da54d09add60cd13908f",
          "message": "Signal read-error? when read hits EOF mid-datum (R7RS 6.13.2) (#977)\n\n(read port) returned the EOF object whenever the reader ran out of\ninput, even when end of file interrupted an incomplete datum like\n\"(unclosed\" or an unterminated string. R7RS 6.13.2 requires an error\nsatisfying read-error? in that case; only EOF before any datum text\nbegins may return the EOF object. The file-loading path already\nreported such input as a read error — the deviation was specific to\nthe read procedure, on both string ports and file-descriptor ports.\n\nDistinguish the two cases with Reader.hasMore(): if only whitespace\nand comments remain, return the EOF object as before; otherwise a\ndatum has begun and any reader failure — now including UnexpectedEof —\nraises a read error. An OutOfMemory from the reader now propagates as\nan allocation failure instead of masquerading as end of input.\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-03T14:21:52Z",
          "tree_id": "14ac1a1b33e1e1bee8dc4a7187322cfd8e83cc33",
          "url": "https://github.com/kaappi/kaappi/commit/d0414d88001d2b558172da54d09add60cd13908f"
        },
        "date": 1783089417002,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.423152,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.099809,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.843341,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.235674,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006384,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032829,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.495102,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068828,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.104372,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.806804,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.151471,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.436479,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.781436,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.694006,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.041752,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "6c4e79d34cf9ba6ea7b0012d92f56624750493e2",
          "message": "Fix fiber scheduler returning void for multi-stage channel pipelines (#978)\n\nA blocked channel-receive drives other fibers from inside its own native\nframe, so a nested scheduler could never resume an outer blocked fiber\n(only LIFO unwinding worked). With two or more pipeline stages the inner\nstage exhausted schedule() and runSchedulerUntil silently returned VOID,\nso downstream stages computed on garbage and consumer loops spun forever.\nFibers permanently blocked at program end likewise never terminated.\n\nPark-and-retry: a fiber that cannot progress parks (.waiting on the\nchannel) and the dispatch loop rewinds ip to the call instruction before\nunwinding with Yielded, so channel-receive re-executes when the fiber is\nrescheduled. channel-send wakes all fibers parked on that channel. A\nblocked main program, or a receive/fiber-join that can never be satisfied,\nnow raises a catchable deadlock error instead of returning void. Parking\nis gated by dispatched_from_scheduler so a fiber blocked inside a native\ncallback (map/for-each/eval) errors rather than corrupting Zig frames.\napply and callWithArgs now propagate the park signal instead of mangling\nit into a type/bytecode error. Fibers still parked when the main program\nends are discarded (Go-style); documented in README and CHANGELOG.\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-03T14:29:47Z",
          "tree_id": "c018cfd0689404ee2d6dbb9be494790cd1e67ac7",
          "url": "https://github.com/kaappi/kaappi/commit/6c4e79d34cf9ba6ea7b0012d92f56624750493e2"
        },
        "date": 1783089930826,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.117935,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 10.344523,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.897675,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.44524,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007436,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.033987,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.49212,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.06927,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.993184,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.879716,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.193595,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.484571,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.729093,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.906995,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044843,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "f8278f87d7b615b6fa93643f30165ce5110746f2",
          "message": "Make current-input/output/error-port parameter objects (#811) (#979)\n\nR7RS 6.13.1 requires these to be parameter objects so parameterize\ncan redirect I/O. They were plain native procedures, causing an\narity error on (parameterize ((current-output-port sp)) ...).\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-03T15:07:09Z",
          "tree_id": "43ece44619c44a48df9ed79146937e645901006e",
          "url": "https://github.com/kaappi/kaappi/commit/f8278f87d7b615b6fa93643f30165ce5110746f2"
        },
        "date": 1783092135368,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.367426,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.306662,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.836833,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.655807,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006435,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032834,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.474559,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070498,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.032065,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.82363,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.183313,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.431704,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.805781,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.727365,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043759,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "ee8d0580532300c15f131502f9bd64e6c9e34062",
          "message": "Range-check FFI args against declared narrow int types (#795) (#980)\n\nnormalizeType() collapsed int8/uint8/int16/uint16/uint32/char into\ncarrier types (int/long) before validation, so toCheckedInt only\nenforced the carrier's range. A uint8 parameter silently accepted\nany value in c_int range, and uint32 accepted any c_long value,\ndelivering wrapped values to C.\n\nAdd checkNarrowIntRange() that validates arguments against the\ndeclared FfiType's exact range in validateArgs(), before dispatch.\n\nCloses #795\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-03T15:07:03Z",
          "tree_id": "40a5dcf53551f7d0633e61c4d1847a2136bd1233",
          "url": "https://github.com/kaappi/kaappi/commit/ee8d0580532300c15f131502f9bd64e6c9e34062"
        },
        "date": 1783092223585,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.508836,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.469554,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.707962,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.462116,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.005943,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.026361,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.39044,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.054332,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.391952,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.456798,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 0.914774,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.377163,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.328424,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.438486,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.035398,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "382365ae58f01d378c3314ebaf452a46e228d8a5",
          "message": "Invalidate stale native call sites after set!/define rebinding (#822) (#981)\n\nThe LLVM backend bound call sites to procedure definitions at compile\ntime and never invalidated those bindings when a name was reassigned.\nThree mechanisms were affected: native_fns direct calls kept invoking\nthe original function after set!/define, inline primitives like + kept\nusing the original op after (define + -), and IR constant folding\nevaluated (+ 10 3) → 13 before the emitter could see the rebinding.\n\nFix all three: track globally-rebound names in the emitter so later\ncall sites fall through to kaappi_global_lookup, and feed define/set!\ntargets across top-level forms to the IR's set_targets so constant\nfolding is suppressed for rebound primitives.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-03T15:09:13Z",
          "tree_id": "9c851920a080e3ebf2fbe33d5d99b84d3f8653ae",
          "url": "https://github.com/kaappi/kaappi/commit/382365ae58f01d378c3314ebaf452a46e228d8a5"
        },
        "date": 1783092338199,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.37514,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.001072,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.888529,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.669552,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00651,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.034038,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.492732,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.07147,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.083903,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.828333,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.220809,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.435882,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.814781,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.699998,
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
          "id": "57959cd2407c6ee7b61a33e86ddfa3cdaf1e7fa2",
          "message": "Handle cond-expand and nested include-library-declarations in ILD (#874) (#982)\n\nincludeLibraryDeclarations only handled export, import, begin, include,\nand include-ci — cond-expand and nested include-library-declarations were\nsilently dropped. Extract per-declaration processing into\nprocessLibDeclaration with all six R7RS library declaration types so\nspliced declarations are handled the same as directly-written ones.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-03T15:28:20Z",
          "tree_id": "838d712ae1f7bbf3e6e7bc044e8997eb5420257b",
          "url": "https://github.com/kaappi/kaappi/commit/57959cd2407c6ee7b61a33e86ddfa3cdaf1e7fa2"
        },
        "date": 1783093406798,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.152242,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.022722,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.676428,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.850081,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.005233,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.026332,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.377736,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.056153,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.380471,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.437086,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 0.933053,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.369985,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.310105,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.321913,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.035058,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "4b5f35ebf577bda7d42c739780bfcf56910ab774",
          "message": "Reject directories and propagate read errors in readFileContents (#983)\n\n* Reject directories and propagate read errors in readFileContents (#789)\n\nreadFileContents silently treated read() failures (EISDIR, EIO, etc.) as\nEOF, so passing a directory to kaappi ran an empty program with exit 0.\nNow fstat rejects directories with a clear message, and other read errors\nare reported and propagated instead of swallowed.\n\nFixes #789\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Use statx on Linux for directory check in readFileContents\n\nstd.c.fstat is void on Linux in Zig 0.16. Use linux.statx with\nAT_EMPTY_PATH to stat by fd, matching the pattern in\nprimitives_filesystem.zig.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-03T22:55:24+05:30",
          "tree_id": "a151ddc0c95bc3f7c353a122c73aaf680f911e3f",
          "url": "https://github.com/kaappi/kaappi/commit/4b5f35ebf577bda7d42c739780bfcf56910ab774"
        },
        "date": 1783100500145,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.066411,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.13973,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.874618,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.381573,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006844,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.036915,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.485445,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068605,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.968012,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.86215,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.193647,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.471103,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.707045,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.822461,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044843,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "47b8e74808341e77cf24572485ab2bbcbf1b3ca8",
          "message": "Parse fd-backed (read) incrementally instead of draining to EOF (#847) (#984)\n\nreadDatumFn accumulated all bytes until read() returned 0 before\nattempting to parse a datum. On interactive terminals read() never\nreturns 0, so (read) blocked forever. Parse after each chunk instead;\nincomplete datums (UnexpectedEof) loop back for more input.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-03T22:55:45+05:30",
          "tree_id": "759427182b00c6c7942581dccc152f906884c674",
          "url": "https://github.com/kaappi/kaappi/commit/47b8e74808341e77cf24572485ab2bbcbf1b3ca8"
        },
        "date": 1783100535916,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.387643,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.658667,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.846285,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.498826,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006435,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.033383,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.475821,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.071142,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.210739,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.822085,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.198947,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.427575,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.807127,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.709627,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044811,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "abe7cc4936957644944a0cf9bef86c8050269948",
          "message": "Reject filesystem paths with embedded NUL bytes (#805) (#985)\n\nEvery path-taking SRFI-170 primitive converted filenames to C strings\nvia dupeZ, which silently truncated at the first embedded NUL byte.\nThis caused operations to act on the wrong path with no error — a\ncorrectness and safety problem, especially for destructive operations\nlike delete-directory and rename-file.\n\nAdd validatePathNoNul() that raises a file error when a path contains\nan embedded NUL byte, and call it at all 24 extractPath sites plus the\ncreate-temp-file prefix argument. Mirrors the resolution of #630 for\nffi.zig::toCString.\n\nCloses #805\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-03T22:56:12+05:30",
          "tree_id": "24abdcb95257acca2eb7fac8eb00ce2bd3a4aca2",
          "url": "https://github.com/kaappi/kaappi/commit/abe7cc4936957644944a0cf9bef86c8050269948"
        },
        "date": 1783100542369,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.061652,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.149847,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.900094,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.384732,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00684,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.033557,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.484795,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069468,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.956497,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.848061,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.190933,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.470376,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.689668,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.838636,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044233,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "aa57b7e16396416567d0ee97afdeb5cc447b03f3",
          "message": "Fix LLVM backend eval fallback losing lexical environment (#827) (#987)\n\nWhen the native backend compiled a let or lambda body natively but a\nsub-form (cond, do, letrec, etc.) required interpreter eval fallback,\nthe sub-form was serialized and evaluated via kaappi_eval in the global\nenvironment — losing let-bound locals and clobbering same-named globals\nvia bindParamsAsGlobals.\n\nThe fix prevents splitting a lexical scope across the native/interpreted\nboundary:\n\n- emitLet: detect eval-fallback forms and capturing lambdas upfront;\n  fall back to evaluating the entire let form via the interpreter.\n- tryCompileDefineFunction / tryCompileNativeClosure /\n  tryCompilePureLambdaAsNativeClosure: reject native compilation when\n  the body contains forms needing eval fallback.\n- emitLambdaViaEval: return an error inside a let scope so the\n  enclosing let can fall back instead of creating a broken closure.\n- emitLetFallback: fix S-expression serialization that added an extra\n  layer of parentheses around the form args.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-03T22:56:32+05:30",
          "tree_id": "739d9c6403f6e49522d32fb0a27e217c6011c249",
          "url": "https://github.com/kaappi/kaappi/commit/aa57b7e16396416567d0ee97afdeb5cc447b03f3"
        },
        "date": 1783100806957,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.030117,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.720003,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.904786,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.374021,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00679,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.033655,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.489111,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068917,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.034128,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.869529,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.188755,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.477124,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.701949,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.899584,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044324,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "d02f6aad69ddb34f90db7fb84eee0aca637c4bfe",
          "message": "Guard vector-unfold/unfold-right against empty multiple values (#806) (#986)\n\n* Guard vector-unfold/unfold-right against empty multiple values (#806)\n\nWhen the step procedure returns (values) (zero values), both functions\nindexed into an empty array, aborting the interpreter. Return a catchable\ntype error instead. Also fixes vector-unfold-right leaving new_data[i]\nuninitialized (and subsequently pushed into gc.extra_roots) when the\nguard was false.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Pin wasmtime version in CI to fix broken upstream installer\n\nThe wasmtime.dev/install.sh script broke upstream — it resolves the\nlatest version as \"{\" instead of a real tag, causing the WASM CI job\nto fail. Download the tarball directly from GitHub releases instead.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-03T23:17:55+05:30",
          "tree_id": "7ff89c1784d7a6c866fb1802ff08ea208ee12f0e",
          "url": "https://github.com/kaappi/kaappi/commit/d02f6aad69ddb34f90db7fb84eee0aca637c4bfe"
        },
        "date": 1783101785923,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.364582,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.7749,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.846535,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.344609,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00643,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.033246,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.474127,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.071117,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.101388,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.819273,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.17145,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.435877,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.804982,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.745325,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.047092,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "ec52ce609de58764897322d61d09e0f8e926ad8e",
          "message": "Preserve string/bytevector eq? identity in thread deep copy (#807) (#988)\n\ndeepCopyValue was missing visited.put for .string and .bytevector,\nso shared references to the same mutable object became independent\ncopies across thread boundaries, breaking eq? identity and shared\nmutation semantics.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-03T18:57:47Z",
          "tree_id": "077cd3714f78461559fdb43d20ba437fb12a2616",
          "url": "https://github.com/kaappi/kaappi/commit/ec52ce609de58764897322d61d09e0f8e926ad8e"
        },
        "date": 1783105962298,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.377379,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.549459,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.844822,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.286881,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006374,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.033512,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.471267,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070966,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.062632,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.836409,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.207119,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.429883,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.786084,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.667394,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043313,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "6dabe8d65fd6d4ad7a88d1e638cd1647904e20af",
          "message": "Reject invalid --timeout and --max-memory values instead of silently ignoring them (#787) (#989)\n\n`catch 0` on parseInt silently dropped non-numeric, zero, and negative\nvalues — the resource limit the user asked for was never applied.\nReplace with explicit error reporting (exit 2) consistent with the\nmissing-argument handling added in #778.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-03T18:57:54Z",
          "tree_id": "8ee989b2556ac8d87fbb76e45657e079a79e1263",
          "url": "https://github.com/kaappi/kaappi/commit/6dabe8d65fd6d4ad7a88d1e638cd1647904e20af"
        },
        "date": 1783105980530,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.408348,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.377874,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.878778,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.303588,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006382,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.033368,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.472475,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.071249,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.080033,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.844023,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.188143,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.42788,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.799232,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.656909,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044718,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "270034a9d57377fb75fcbd2bee37d33646b8d172",
          "message": "Use fstatat instead of open in file-exists? (#808) (#990)\n\nfile-exists? was implemented with openat+close, which hangs on FIFOs\n(blocks until a writer connects) and returns #f for existing but\nunreadable files (e.g. mode 000). Switch to fstatat which checks\nexistence without opening, matching R7RS 6.14.1 semantics.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-03T19:12:30Z",
          "tree_id": "dc0bf5153a53cddca163efe7e43f5c9b9fa29dd4",
          "url": "https://github.com/kaappi/kaappi/commit/270034a9d57377fb75fcbd2bee37d33646b8d172"
        },
        "date": 1783106873094,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 2.291936,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.735142,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.459722,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.072978,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004189,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.018482,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.254753,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.036952,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 1.859807,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.921954,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 0.638715,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.315138,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 0.924682,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.203395,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.025103,
            "unit": "seconds"
          }
        ]
      }
    ]
  }
}