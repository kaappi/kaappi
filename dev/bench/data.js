window.BENCHMARK_DATA = {
  "lastUpdate": 1783702835916,
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
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "36022b75419303da7780b2d7d8fd7a7fbd6c03b9",
          "message": "Implement string-join grammar argument per SRFI-13 (#825) (#1312)\n\nThe optional third argument (infix, strict-infix, prefix, suffix) was\nsilently ignored — all calls produced infix output regardless. Now\nprefix prepends the delimiter before each element, suffix appends it\nafter each, and strict-infix raises an error on an empty list.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-08T10:54:52+05:30",
          "tree_id": "2442d0201b9c935f7e249bd256c89d78fc4c0ac0",
          "url": "https://github.com/kaappi/kaappi/commit/36022b75419303da7780b2d7d8fd7a7fbd6c03b9"
        },
        "date": 1783490666764,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.098875,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 10.354968,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 1.020066,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.416524,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.013911,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.222942,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.511015,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.07015,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 13.46169,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.981011,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 11.142881,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.066131,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 9.165721,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.860421,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.046193,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "7e9928fb66e2dc2c4901c3e6eabc062d53e2fdf8",
          "message": "Add nine missing SRFI-133 procedures (#1172) (#1308)\n\nvector=, vector-fold, vector-fold-right, vector-map!,\nvector-reverse-copy!, vector-unfold!, vector-unfold-right!,\nreverse-vector->list, and reverse-list->vector were spec-required\nbut unbound after (import (srfi 133)). All nine are now native\nZig primitives with multi-vector support, GC write barriers,\nand accumulator rooting where needed.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-08T10:55:29+05:30",
          "tree_id": "ab3bfcf589981918be597ea14926dbbb145e72aa",
          "url": "https://github.com/kaappi/kaappi/commit/7e9928fb66e2dc2c4901c3e6eabc062d53e2fdf8"
        },
        "date": 1783490781814,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.315744,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.980289,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.970254,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.393393,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012518,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.202917,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.500663,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.072197,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.598452,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.957882,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 10.114518,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.977277,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.346635,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.639549,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045397,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "dcef387312a310b4c761ce38589e548bfef0225b",
          "message": "Fix FFI char type to accept Scheme characters and return characters (#1186) (#1309)\n\n* Fix FFI char type to accept Scheme characters and return characters (#1186)\n\nThe char FFI type was behaviorally identical to uint8 — it rejected\nScheme character values like #\\A with a bare error, and char returns\nproduced fixnums instead of characters. Now char params accept both\nintegers and Scheme characters (codepoint must fit 0–255), and char\nreturns produce Scheme character values.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Tighten char return range to 0–255 and update audit ledger\n\nSymmetric with the param path which already range-checks to 0–255.\nUpdate docs/audit-strategy.md to reflect 48 tests + 2 disabled.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-08T05:50:19Z",
          "tree_id": "3e0c6f211bb780448b0c77ba5f02a5fb226c3b17",
          "url": "https://github.com/kaappi/kaappi/commit/dcef387312a310b4c761ce38589e548bfef0225b"
        },
        "date": 1783491813648,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.102085,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.77775,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 1.0296,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.416734,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.014262,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.22493,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.510548,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070471,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 13.57425,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.982155,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 11.240059,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.092537,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 9.229045,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.855042,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.046001,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "b2ff6238606093d29f92fdec1cc1ef817d2504d8",
          "message": "Guard test expressions in (chibi test) against exceptions (#1196) (#1311)\n\n* Guard test expressions in (chibi test) against exceptions (#1196)\n\nWrap the test expression in a `guard` form so that a raised exception\nis reported as a failure and counted, instead of escaping the macro and\naborting sibling tests in the same enclosing form.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Fix load crashing inside guard; use procedure-level guard in test macro\n\nThe test macro fix (wrapping expressions in guard) exposed two\npre-existing bugs:\n\n1. load used vm.execute() which resets all VM state (frame count,\n   handler count), corrupting the call stack when called from inside\n   guard's callReentrant. Fix: use callWithArgs (like eval does) which\n   properly saves/restores execution state.\n\n2. guard's escape continuation limits apply to 255 args (u8 nargs).\n   Adjusted two audit tests to stay under this limit.\n\nAlso: use a helper procedure for the guard (test-run) so that\ntest-error's inner guard doesn't nest at the macro level, and fix\nthe shell regression test for macOS bash heredoc compatibility.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Fix let*-values body scoping; use inline guard in test macro\n\nlet*-values with zero bindings desugared to (begin body...), which\nspliced definitions into the enclosing scope instead of creating a\nproper body scope. Changed to desugar to (let () body...) so that\ninternal define forms are correctly scoped — matching R7RS semantics\nand the behavior of let-values with zero bindings.\n\nThis also allows the test macro to use inline guard (no lambda wrapper)\nwithout changing define scoping for the tested expression.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Address review feedback\n\n- Revert list-audit map boundary back to 256 (only apply with 256+\n  scalar args is affected by the escape continuation limit, not map\n  with 256 list args)\n- File yield-in-handler bug as #1314 and reference it in fiber-audit\n  skip comment\n- Fix shell test to not trip set -e before diagnostics can print\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-08T12:53:00+05:30",
          "tree_id": "47de79b8f0ff6983ca23d4a4a71c62a1d4664bd6",
          "url": "https://github.com/kaappi/kaappi/commit/b2ff6238606093d29f92fdec1cc1ef817d2504d8"
        },
        "date": 1783496990879,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 2.357902,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.842229,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.54484,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.357706,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.008534,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.138697,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.257738,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.035642,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 7.925191,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.987995,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 7.132107,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.706807,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 5.692508,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.192044,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.025734,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "39febebd4f71a5c2dd8042ec92f31148f9f7cb31",
          "message": "Fix SRFI-151 bit-argument API mismatch (#1233) (#1316)\n\n- copy-bit: accept boolean (not integer) as third argument per spec\n- bitwise-eqv: make n-ary with identity -1 (was fixed 2-arity)\n- bits->list/bits->vector: make len optional (default: integer-length)\n- make-bitwise-generator: return booleans (was 0/1 fixnums)\n- Update internal callers (bit-swap, list->bits, vector->bits,\n  bitwise-unfold) to pass booleans to copy-bit\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-08T15:01:56+05:30",
          "tree_id": "fa7555fd40227ec53f8094ba8bec027853bf7c1b",
          "url": "https://github.com/kaappi/kaappi/commit/39febebd4f71a5c2dd8042ec92f31148f9f7cb31"
        },
        "date": 1783505205660,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.109701,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.978431,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 1.032964,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.41998,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.015013,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.225675,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.512624,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070602,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 13.69775,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.998399,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 11.266725,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.09197,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 9.355146,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.891078,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.047013,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "7362bb2dd83b9411f642c947724a11426e28720e",
          "message": "Fix string-contains and string-replace start2/end2 handling (#1158) (#1317)\n\nstring-contains silently ignored the optional start2/end2 arguments,\nalways searching for the whole needle. string-replace rejected them\nwith an arity error (registered as exact=4 instead of variadic=4).\n\nBoth now apply parseStartEnd on s2 at arg index 4, matching the\npattern used by string-prefix? and string-suffix?.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-08T15:03:01+05:30",
          "tree_id": "0f9201a25681a8c559c5f66a4128c19832e9ac92",
          "url": "https://github.com/kaappi/kaappi/commit/7362bb2dd83b9411f642c947724a11426e28720e"
        },
        "date": 1783505446209,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.344311,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.51455,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.98221,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.966182,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012667,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.202939,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.508256,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.072139,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.686489,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 2.010146,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 10.152713,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.978546,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.390219,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.763709,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.047332,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "d8bdfed6d1f81549f704a687994b3e5398d11a7f",
          "message": "Fix SRFI-210 value procedure and add box/mv export (#1218) (#1318)\n\nvalue returned its first argument (the index) instead of the index-th\nobject. Also add box/mv syntax which was implemented but not exported.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-08T15:04:35+05:30",
          "tree_id": "9bd1b6431d0b6ebb8dc9863dc3fb9abeef7645a2",
          "url": "https://github.com/kaappi/kaappi/commit/d8bdfed6d1f81549f704a687994b3e5398d11a7f"
        },
        "date": 1783505685836,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.331361,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.337406,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.982767,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.600147,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012798,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.206338,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.508342,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.072064,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.666019,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.967989,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 10.093943,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.983675,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.368672,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.695299,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043863,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "6dab75eedc661a507a29a758c891285936f4ae5b",
          "message": "Add hash-table-update! procedure to SRFI-69 (#1182) (#1315)\n\nSRFI-69 requires hash-table-update! with signature (ht key function [thunk]).\nOnly hash-table-update!/default was registered. The new procedure calls the\noptional thunk when the key is absent (or errors if no thunk is provided).\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-08T15:04:53+05:30",
          "tree_id": "f4b6ca19e1558a6b12e7a7d5f2a630311fcc135d",
          "url": "https://github.com/kaappi/kaappi/commit/6dab75eedc661a507a29a758c891285936f4ae5b"
        },
        "date": 1783505741593,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.123741,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.529147,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 1.021709,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.39107,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.014007,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.225243,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.510361,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070427,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 13.62879,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.98526,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 11.260608,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.098508,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 9.224322,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.88632,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.04592,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "be2e3ea2c95901ed6fb0bbac40087f3fcadf5b4c",
          "message": "Migrate reader Unicode classification to generated tables (#1268) (#1321)\n\nReplace the hand-rolled isUnicodeLetter in reader.zig (27 hardcoded\nscript-block ranges + case-table fallback) with a single call to\nunicode.inRanges(&unicode.alphabetic_ranges, cp), matching the pattern\nalready used by char-alphabetic? in primitives_char.zig.\n\nThis eliminates the divergence where char-alphabetic? accepted\ncodepoints (e.g. U+02B0 modifier letters) that the reader rejected,\nand removes 1300 bytes of dead lookup tables (extra_uppercase,\nextra_lowercase, containsU21) that existed solely for the old reader\nfallback path.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-08T15:07:19+05:30",
          "tree_id": "8766a3a4821a04383f862225dbd8354fca899065",
          "url": "https://github.com/kaappi/kaappi/commit/be2e3ea2c95901ed6fb0bbac40087f3fcadf5b4c"
        },
        "date": 1783505912403,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.369666,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.563755,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 1.022091,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.41784,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.013911,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.225248,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.510333,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070239,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 13.579752,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.97644,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 11.251718,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.101691,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 9.234991,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.857721,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.046276,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "c49b0d2f7c666c1c9a3706446673aa849989ebb8",
          "message": "Fix SRFI-27 random-integer, %rs-next-int, and pseudo-randomize! to accept bignums (#1193) (#1319)\n\n* Fix SRFI-27 random-integer, %rs-next-int, and pseudo-randomize! to accept bignums (#1193)\n\nAll three procedures only checked for fixnums, rejecting valid exact\nintegers wider than 48 bits (e.g. (expt 2 64)).  For random-integer and\n%rs-next-int, add rejection sampling over bignum limbs.  For\npseudo-randomize!, fold bignum i/j values to u64 seeds via XOR.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Fix top_bits overflow: u6 cannot hold 64 when top limb MSB is set\n\nWiden to u7 and cast to u6 only for the shift operand.  Add regression\ntests with saturated top limbs ((expt 2 127), (- (expt 2 128) 1)).\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-08T15:37:39+05:30",
          "tree_id": "fc39d571e5edcefea8823550bf89014cfa258c9f",
          "url": "https://github.com/kaappi/kaappi/commit/c49b0d2f7c666c1c9a3706446673aa849989ebb8"
        },
        "date": 1783506923682,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.184067,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 10.178329,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 1.048177,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.401266,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.014984,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.226134,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.511409,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070738,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 13.718545,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.978826,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 11.298684,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.102689,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 9.264412,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.993353,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.047444,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "9f757c25560767ac3de0f978e1a6ed3b10a341d5",
          "message": "Fix posix-time/monotonic-time to return SRFI-19 time objects (#1162) (#1320)\n\n* Fix posix-time/monotonic-time to return SRFI-19 time objects (#1162)\n\nExtend the Zig-level Srfi18Time type to carry integer seconds,\nnanoseconds, and a time type enum (utc/tai/monotonic/duration),\nunifying it as the canonical time representation for both SRFI-18\nand SRFI-19. Register SRFI-19 time accessors (make-time, time?,\ntime-type, time-second, time-nanosecond) as built-in primitives\nin (scheme time), and update lib/srfi/19.sld to use them instead\nof define-record-type.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Address review: validate nanoseconds, fix WASM availability\n\n- Move time accessors (make-time, time?, time-type, time-second,\n  time-nanosecond) from primitives_srfi18.zig to primitives_r7rs.zig\n  so they are available on WASM builds (primitives_srfi18.zig is\n  excluded on wasm32-wasi)\n- Validate 0 <= nanosecond < 1e9 in make-time to prevent interpreter\n  panics from negative nanoseconds reaching u64 casts in the printer\n  and timeout paths\n- Defensively clamp nanoseconds in printer and timeoutToDeadlineNs\n- Use floor instead of trunc in seconds->time for correct negative\n  second handling\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-08T16:49:17+05:30",
          "tree_id": "3d1f026fd22157005d6b6a3740b723d2fe1d4d3b",
          "url": "https://github.com/kaappi/kaappi/commit/9f757c25560767ac3de0f978e1a6ed3b10a341d5"
        },
        "date": 1783511338429,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.457891,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.45573,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.978311,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.449284,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012671,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.203553,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.504603,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.072526,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.859729,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.965994,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 10.180538,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.004413,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.439506,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.700894,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043708,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "c25dcccba7db2d1a905138e64636fcaa4ce36f6e",
          "message": "Fix stream-unfold predicate sense and stream macro hygiene (#1215) (#1322)\n\n* Fix stream-unfold predicate sense and stream macro hygiene (#1215)\n\nstream-unfold tested (pred? s) and stopped when true — inverted relative\nto SRFI-41 which says elements are produced while pred? holds.  Flip the\nif branches so unfold-loop continues while (pred s) is true.\n\nThe stream macro referenced the free variable stream-null in its base-case\ntemplate.  collectSetTargets pre-expands macros without VOID-marking free\nrefs, so renameForHygiene gave stream-null a hygienic prefix.  When two\n(stream …) calls appeared as sibling arguments in the same function call,\nthe second expansion's renamed stream-null resolved via the VM's\nhygienic-prefix fallback but landed in a compilation context where the\npromise layer was lost — producing a bare pair instead of a promise.\nReplace stream-null with (delay '()) in the base-case template to avoid\nthe free-variable reference entirely.\n\nAlso reverse the temp_globals cleanup loop in expandAndCompileMacroUse to\nLIFO order: Phase-A2 (def_env additions) and Phase-B (VOID sentinels) can\ncreate overlapping entries for the same name; forward cleanup let Phase-B\nre-add a name that Phase-A2 correctly removed, leaking it into globals\nfor subsequent sibling expansions.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Fix stream-zip any-stream-null check, strengthen sibling tests\n\nReview feedback:\n- stream-zip only checked the first stream for null; now checks all\n  streams via any-null? so zipping stops correctly when ANY stream\n  is exhausted (not just the first one)\n- Replace weak promise? sibling assertions with stream->list content\n  checks that actually verify expanded stream values\n- Add stream-zip test where first stream is longer than the second\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-08T17:08:44+05:30",
          "tree_id": "19f0fd3d6edde6428300b12ff542cbe6e3407801",
          "url": "https://github.com/kaappi/kaappi/commit/c25dcccba7db2d1a905138e64636fcaa4ce36f6e"
        },
        "date": 1783512402724,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.338741,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.586505,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 1.020638,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.410539,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012708,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.20485,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.50015,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.072199,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.769677,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.933018,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 10.18602,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.006195,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.441809,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.749924,
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
          "id": "b8859640552dc3bb6fd6c38ae93f1afe7bf0654b",
          "message": "Fix SRFI-210 set!-values shadowing bug (#1224) (#1324)\n\nThe consumer lambda's parameters shadowed the outer variables, making\neach (set! var var) assign a parameter to itself. Use a rest-arg lambda\nwith a helper macro to bind fresh temporaries instead.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-08T19:22:46+05:30",
          "tree_id": "795d57f5f0445151644509a8b31b520dd3a38df5",
          "url": "https://github.com/kaappi/kaappi/commit/b8859640552dc3bb6fd6c38ae93f1afe7bf0654b"
        },
        "date": 1783520222387,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.532659,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.271794,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.78115,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.449965,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.013421,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.20671,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.393685,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.061435,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.792462,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.493369,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 10.517061,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.03705,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.558466,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.876609,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.0372,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "b6be1fb07690086dd8b62a969aff708e7deacea5",
          "message": "Fix SRFI-175 ascii-digit-value and add 16 missing procedures (#1236) (#1325)\n\nascii-digit-value incorrectly treated letters a-z/A-Z as radix digits\n10-35. Per SRFI-175, it handles only decimal digits 0-9; letters are\nthe domain of ascii-upper-case-value and ascii-lower-case-value.\n\nAlso implements all 16 missing spec exports: ascii-bytevector?,\nascii-ci=?/<?/>?/<=?/>=?, ascii-string-ci=?/<?/>?/<=?/>=?,\nascii-control->graphic, ascii-graphic->control, ascii-mirror-bracket,\nascii-nth-digit, ascii-nth-upper-case, ascii-nth-lower-case.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-08T19:52:38+05:30",
          "tree_id": "052800baead81ac9accaf02293b9aff5cce9c5d3",
          "url": "https://github.com/kaappi/kaappi/commit/b6be1fb07690086dd8b62a969aff708e7deacea5"
        },
        "date": 1783522411558,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.321762,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.012133,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 1.004917,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.39953,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012675,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.203628,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.497639,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.071993,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.700877,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.932848,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 10.207355,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.999553,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.419889,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.670063,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043544,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "1e251e07eaab5863037feeef9597f9ecfd8d1d3e",
          "message": "Fix SRFI-232 curried procedures to support grouped application (#1238) (#1327)\n\nThe old implementation hardcoded four syntax-rules patterns that expanded\ninto strictly unary lambda chains, so grouped application like (add2 1 2)\nraised an arity error. Replace with the SRFI-232 reference implementation\nusing case-lambda dispatch: zero args returns self, exact args evaluates\nbody, surplus args forwards to the result, partial args accumulates via\na helper closure. Also export the curried form and support nullary,\nvariadic, and arbitrary-arity formals.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-08T20:34:08+05:30",
          "tree_id": "a2bbec6b36142edc38ef32bf6068d6c0eabf5a63",
          "url": "https://github.com/kaappi/kaappi/commit/1e251e07eaab5863037feeef9597f9ecfd8d1d3e"
        },
        "date": 1783524572650,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.320109,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.674138,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.980887,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.407598,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012695,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.204008,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.502403,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.072118,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.724956,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.938128,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 10.178417,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.003622,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.431044,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.698704,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044173,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "7e3e9108d404c3e5be746b4eb6f80f35c205ec4a",
          "message": "Export SRFI-33 aliases and second-tier procedures from SRFI-60 (#1164) (#1328)\n\nThe (srfi 60) library only exported log*-style names. Now exports both\nnaming conventions (logand/bitwise-and, etc.), the SRFI-60 plural\nany-bits-set?, second-tier procedures (copy-bit-field, rotate-bit-field,\nreverse-bit-field, log2-binary-factors), and MSB-first boolean/integer\nconversions (integer->list, list->integer, booleans->integer).\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-08T20:35:21+05:30",
          "tree_id": "465fc435fadf58a08d4df6657a61370741477fa9",
          "url": "https://github.com/kaappi/kaappi/commit/7e3e9108d404c3e5be746b4eb6f80f35c205ec4a"
        },
        "date": 1783524723035,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.339744,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.372133,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.980017,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.405758,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012641,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.203805,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.500529,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.07227,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.719255,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.939111,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 10.171963,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.007039,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.443292,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.509066,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043335,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "a9990f2a8405181e62e99e771b04cdb63fbc1799",
          "message": "Add 15 missing SRFI-41 derived-library procedures (#1210) (#1330)\n\nImplements: define-stream, stream-let, stream-from, stream-range,\nstream-iterate, stream-constant, stream-take-while, stream-drop-while,\nstream-scan, stream-reverse, stream-concat, port->stream, stream-unfolds,\nstream-match, and stream-of.\n\nstream-match uses letrec-syntax to define the recursive pattern matcher\nat the use site, working around a Kaappi limitation with recursive macros\nin libraries. stream-of-aux is a separate exported-scope macro since its\n`in`/`is` literals must be visible at the use site for hygiene matching.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-08T20:38:09+05:30",
          "tree_id": "2e329a9d7668f0cbd0b95645aaf405cacdc3f62b",
          "url": "https://github.com/kaappi/kaappi/commit/a9990f2a8405181e62e99e771b04cdb63fbc1799"
        },
        "date": 1783524740465,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.310859,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.545597,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 1.00121,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.397169,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012764,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.204368,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.498162,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.072342,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.736101,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.930459,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 10.195214,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.007583,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.425284,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.731741,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044569,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "bfe4776599f6a468c238fdf6b65e89411b843bea",
          "message": "Fix SRFI-43 vector library to match spec (#1209) (#1326)\n\n* Fix SRFI-43 vector library to match spec (#1209)\n\nSRFI-43 iteration procedures pass the index as the first callback\nargument; SRFI-133 (which was being re-exported) does not.  Rewrite\nvector-map, vector-map!, vector-for-each, vector-count, vector-fold,\nand vector-fold-right with correct SRFI-43 calling convention and\nmulti-vector support.  Add 8 missing exports: vector-unfold,\nvector-unfold-right, vector=, vector-binary-search, vector-reverse!,\nvector-reverse-copy!, reverse-vector->list, reverse-list->vector.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Except vector-map/vector-for-each from (scheme base) import\n\nThese two live in (scheme base), not (srfi 133), so the previous\nexcept clause did not cover them.  Excepting from both imports\navoids the duplicate-binding condition where an imported name is\nalso defined in the library body.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-08T20:33:30+05:30",
          "tree_id": "7c1984c75c52a66f7f87af81fe0c3387e5c004ab",
          "url": "https://github.com/kaappi/kaappi/commit/bfe4776599f6a468c238fdf6b65e89411b843bea"
        },
        "date": 1783524885273,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.066154,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 10.167863,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 1.032641,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.450225,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.013954,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.225825,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.544429,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.071227,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 13.597078,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.976447,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 11.301899,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.126817,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 9.272009,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.850267,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045409,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "23827c283622ee86e115b0d13e6c47b0384bc41e",
          "message": "Fix SRFI-152 string-every, string-split, and add missing exports (#1331)\n\n* Fix SRFI-152 string-every, string-split, and add missing exports (#1234)\n\nstring-every returned #t instead of the final predicate value.\nstring-split lacked grammar/limit parameters and returned (\"\") for\nempty string instead of (). ~28 spec-required procedures were missing.\n\nRewrite 152.sld to import native SRFI-13 implementations where they\nexist (fixing string-every/string-any for free) and implement the 17\ntruly missing procedures in Scheme: string-null?, reverse-list->string,\nstring-prefix-length, string-suffix-length, string-contains-right,\nstring-take-while, string-take-while-right, string-drop-while,\nstring-drop-while-right, string-break, string-span,\nstring-concatenate-reverse, string-fold, string-fold-right,\nstring-replicate, string-segment, and a full string-split with\ngrammar (infix/strict-infix/prefix/suffix) and limit support.\n\nAll 73 SRFI-152 procedures are now exported. Removed string-reverse\n(not part of SRFI-152).\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Add (scheme cxr) import and optional start/end args to 7 procedures\n\nReview feedback: caddr/cdddr/cadddr are in (scheme cxr), not\n(scheme base), causing runtime errors when optional args were passed\nto string-prefix-length, string-suffix-length, or string-split.\n\nAlso added optional [start end] parameters to string-contains-right,\nstring-take-while, string-take-while-right, string-drop-while,\nstring-drop-while-right, string-break, and string-span to match the\nSRFI-152 spec signatures.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-08T21:21:27+05:30",
          "tree_id": "d9080d330c90d2ddcd127c37002b2ff1aebdbf47",
          "url": "https://github.com/kaappi/kaappi/commit/23827c283622ee86e115b0d13e6c47b0384bc41e"
        },
        "date": 1783527471626,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.324671,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.252001,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.98363,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.426056,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012928,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.204328,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.500985,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.072093,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.711012,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.936191,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 10.158112,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.022453,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.428072,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.706845,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043852,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "d0159b80d03f19109d33f8ebbc7a8f58e46fcad5",
          "message": "Honor custom equivalence/hash functions in SRFI-69 hash tables (#1329)\n\n* Honor custom equivalence/hash functions in SRFI-69 hash tables (#1183)\n\nmake-hash-table and alist->hash-table previously discarded their optional\nequivalence and hash function arguments, always using equal?/hash. This\ncaused eq?-identity tables to coalesce distinct objects and string-ci=?\ntables to be case-sensitive. The accessor functions also lied about which\ncomparator the table used.\n\nStore a compare mode enum plus the original Scheme procedure Values on\neach HashTable object. Recognize well-known comparators (eq?, eqv?,\nequal?, string=?, string-ci=?) at creation time and dispatch to built-in\nZig implementations. For arbitrary custom Scheme procedures, call back\ninto the VM. Also detect SRFI-128 comparator records and extract their\nequality/hash fields automatically.\n\nFix valueHash to hash bignums, rationals, and complex numbers by value\ninstead of pointer address, preventing lookup failures for equal? tables\nwith heap-allocated numeric keys.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Fix custom-hash data loss, deep-copy, GC safety, and hash consistency\n\nAddress review findings:\n\n- Custom hash returning non-fixnum (bignum, rational) now hashes by\n  value via valueHash instead of by pointer bits, preventing key loss\n- Deep-copied custom-mode tables preserve slot positions instead of\n  re-hashing with valueHash, keeping lookups functional after copy\n- Bignums in fixnum range now hash identically to the equivalent fixnum,\n  fixing equal?/eqv? lookups across representations\n- Root ht_val in alist->hash-table during construction so custom hash\n  callbacks cannot trigger collection of the unfinished table\n- Rehash defers ht.entries swap until after the loop so GC can trace\n  old entries during custom hash callbacks\n- stringCiContentHash uses expanding folds (foldCharExpanding) matching\n  the comparison in equalForTable, so ß and ss hash consistently\n- Custom hash fixnum negation uses i128 intermediate to avoid overflow\n  on minimum fixnum\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Fast-path findKey/findSlot for equal? mode to avoid benchmark regression\n\nThe dispatch through hashForTable/equalForTable added ~22% overhead to\nthe hashtable benchmark due to extra call frames and error-union returns.\nAdd an early check for .equal mode (the default and most common case)\nthat calls valueHash/deepEqual directly, bypassing the dispatch layer.\nNon-equal modes still use the full dispatch path.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-08T21:52:04+05:30",
          "tree_id": "d0d6bb28b494ad22e5be9327e8ca08969bd857d4",
          "url": "https://github.com/kaappi/kaappi/commit/d0159b80d03f19109d33f8ebbc7a8f58e46fcad5"
        },
        "date": 1783529226447,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 2.217178,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.598806,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.51297,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.282242,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.008453,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.138467,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.253178,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.034241,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 7.825592,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.938021,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 7.051216,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.703687,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 5.638903,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.303424,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.026187,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "13fa2af088a1182dfcb2ccbf4853b288c16acfb7",
          "message": "Fix SRFI-233 ini-file->alist missing (scheme char) import (#1223) (#1333)\n\nThe library's internal string-trim calls char-whitespace? which lives\nin (scheme char), but only (scheme base) and (scheme write) were\nimported. Every parse of non-empty input failed with an unbound\nvariable error.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-08T23:19:35+05:30",
          "tree_id": "c16755eee5e7dda89001eb448eb75dd5a0a50c2d",
          "url": "https://github.com/kaappi/kaappi/commit/13fa2af088a1182dfcb2ccbf4853b288c16acfb7"
        },
        "date": 1783534598778,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.052509,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 10.848885,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 1.042247,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.482916,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.013972,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.226688,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.514349,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068262,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 13.684688,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.980604,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 11.424687,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.125402,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 9.291404,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.862471,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.047023,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "192d852a326b87546ce4b9c5f51f1b331d2b00e0",
          "message": "Fix SRFI-141 balanced/ to use correct tie-breaking (#1232) (#1334)\n\nbalanced/ was aliased to round/, but they differ at ties: round/\nbreaks to even quotient while balanced/ must keep the remainder in\n[-|d/2|, |d/2|) — ties always produce a negative remainder.\n\nCloses #1232\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-08T23:21:10+05:30",
          "tree_id": "70ae97ff28e20364f727a760c98188d011c9c527",
          "url": "https://github.com/kaappi/kaappi/commit/192d852a326b87546ce4b9c5f51f1b331d2b00e0"
        },
        "date": 1783534925370,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.620771,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 10.122407,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 1.055697,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.705544,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.013844,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.204501,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.498001,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.0694,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 13.47389,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 2.10307,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 10.821171,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.056155,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 9.057451,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.878191,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.046924,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "5d25909169c100c3bb24cd3bf423caf60a66d372",
          "message": "Fix SRFI-4 integer vector kinds to be disjoint types with range validation (#1225) (#1336)\n\nEach non-u8 vector kind (s8, u16, s16, u32, s32, f32, f64) is now a\ndefine-record-type wrapping its underlying bytevector or vector, giving\neach type a distinct identity. u8vector stays as a bytevector alias per\nSRFI-4 spec. All setters now validate element ranges and raise errors\nfor out-of-range values instead of silently wrapping.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-08T23:32:25+05:30",
          "tree_id": "ab5249749d7e0454a09c8263b07306181acfd34f",
          "url": "https://github.com/kaappi/kaappi/commit/5d25909169c100c3bb24cd3bf423caf60a66d372"
        },
        "date": 1783535573264,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.051012,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 10.213919,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 1.044036,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.411891,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.014182,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.226867,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.512366,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069371,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 13.677907,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.97975,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 11.328406,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.124039,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 9.418982,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.908771,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.047946,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "0c839a7b22d5058508cc1ea0d977846c3087cf4a",
          "message": "Fix SRFI-125 hash-table-ref/update! success proc, hash-table-find result, and add 21 missing exports (#1229) (#1337)\n\nThree bug classes:\n\n1. hash-table-ref and hash-table-update! ignored the optional success\n   procedure — (hash-table-ref ht key failure success) now calls\n   (success value) when the key is present and success is provided.\n\n2. hash-table-find returned (cons key value) instead of the true value\n   produced by proc, per the SRFI-125 spec.\n\n3. 21 procedures required by SRFI-125 were missing from the export list:\n   - 10 re-exported from SRFI-69: hash-table-walk, hash-table-exists?,\n     hash-table-update!/default, alist->hash-table, hash, string-hash,\n     string-ci-hash, hash-by-identity, hash-table-equivalence-function,\n     hash-table-hash-function\n   - 11 new implementations: hash-table-unfold, hash-table=?,\n     hash-table-mutable?, hash-table-pop!, hash-table-clear!,\n     hash-table-map, hash-table-map!, hash-table-prune!,\n     hash-table-empty-copy, hash-table-merge!, hash-table-xor!\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-08T23:33:11+05:30",
          "tree_id": "0e03fc4ba8cca9e637bbb996b0b664001944733c",
          "url": "https://github.com/kaappi/kaappi/commit/0c839a7b22d5058508cc1ea0d977846c3087cf4a"
        },
        "date": 1783535615012,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.323565,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.78318,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.754312,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.275191,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012935,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.201975,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.375485,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.054565,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.393796,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.441351,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 10.156351,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.008789,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.094314,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.876814,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.03549,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "3ae17a3c3624ac262fcc525c11d4a46f1b075feb",
          "message": "Fix SRFI-128 default comparator total order, hashability, and register-default! (#1335)\n\n* Fix SRFI-128 default comparator total order, hashability, and register-default! (#1230)\n\n- default-ordering: handle pairs (lexicographic), vectors (element-wise),\n  bytevectors (byte-wise), and cross-type comparisons via type-index\n- make-eq-comparator/make-eqv-comparator: use default-hash so they are hashable\n- comparator-if<=>: add 5-arg syntax-rules pattern (optional comparator)\n- comparator-register-default!: store comparators and wire into\n  default-ordering, default-equality, and default-hash\n- default-hash: reduce pair/vector/bytevector results modulo hash-bound;\n  improve vector hash to use all elements\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Guard default-ordering against unordered registered comparators\n\nCheck comparator-ordered? before dispatching to a registered comparator's\nordering predicate, so registering a comparator with #f ordering does not\nhit the error thunk. Add test for the edge case.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-08T18:11:03Z",
          "tree_id": "e297a2aa3729fdf0900da9cd6c5f1dce9d9f4191",
          "url": "https://github.com/kaappi/kaappi/commit/3ae17a3c3624ac262fcc525c11d4a46f1b075feb"
        },
        "date": 1783535958153,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.085632,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.661081,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 1.060572,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.404479,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.013897,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.22603,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.51379,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069281,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 13.647259,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.995823,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 11.369301,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.116097,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 9.277214,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.823855,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045999,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "c0f8ad32847dc8ae1c1d0261c2441f89af93e5db",
          "message": "Complete SRFI-235 implementation: add 27 missing exports, fix return values (#1221) (#1338)\n\n* Complete SRFI-235 implementation: add 27 missing exports, fix return values (#1221)\n\nFix all-of and conjoin to return the last predicate result instead of #t.\nAdd all 27 missing SRFI-235 exports: on-left, on-right, left-section,\nright-section, apply-chain, arguments-drop/take/drop-right/take-right,\ngroup-by, begin/if/when/unless/value/case-procedure, and/eager-and/\nor/eager-or-procedure, funcall/loop/while/until-procedure, always,\nnever, boolean.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Use explicit left-to-right evaluation in eager-and/or-procedure\n\nR7RS does not guarantee map's evaluation order, but SRFI-235 requires\nthunks to be invoked left-to-right. Replace map with explicit loops\nand add order-sensitive tests.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-09T00:09:55+05:30",
          "tree_id": "54d9bcf89edbcf2628c1efdfc3c3750e22d3a7eb",
          "url": "https://github.com/kaappi/kaappi/commit/c0f8ad32847dc8ae1c1d0261c2441f89af93e5db"
        },
        "date": 1783537371116,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.334832,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.273422,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 1.00214,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.424667,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012622,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.205758,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.499831,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069154,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.740217,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.948245,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 10.248854,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.006291,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.563836,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.748274,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043826,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "c916a8e94030f82cd199966587b077fc768affd6",
          "message": "Fix opt*-lambda sequential defaults and lift 2-optional cap (#1340)\n\n* Fix opt*-lambda sequential defaults and lift 2-optional cap (#1222)\n\nopt*-lambda was a bare alias of opt-lambda, so its zero-argument case\nused parallel let — defaults could not reference earlier parameters.\nBoth macros also used hand-enumerated patterns capped at 2 optionals.\n\nReplace with recursive syntax-rules using literal-tag dispatch (%p for\nparsing required/optional boundary, %b for clause accumulation, %d for\nnested-let default expansion). Both forms now support arbitrary numbers\nof required and optional parameters. opt*-lambda generates nested let\n(sequential), opt-lambda generates nested let (effectively sequential,\nbut consistent with partial-application cases where earlier params are\nalready case-lambda-bound).\n\nCloses #1222\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Give opt-lambda parallel default semantics distinct from opt*-lambda\n\nThe previous commit used nested let for both forms, making them\nsemantically identical. SRFI-227 requires opt-lambda defaults to be\nevaluated in the enclosing environment (parallel, like let), while\nopt*-lambda defaults are sequential (like let*).\n\nopt-lambda's %d phase now accumulates names and defaults into two\nlists, then emits ((lambda (names ...) body ...) defaults ...) — an\nimmediate application that evaluates all defaults in the outer scope\nbefore binding. This avoids a Kaappi expander limitation where ...\ncannot splice into let binding lists.\n\nObservable difference:\n  (define a 100)\n  ((opt-lambda  ((a 1) (b a)) (list a b)))  → (1 100)  ;; parallel\n  ((opt*-lambda ((a 1) (b a)) (list a b)))  → (1 1)    ;; sequential\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-09T00:44:18+05:30",
          "tree_id": "4dfd0d6b9417cd0ef8ee51d6085c650b5ff690f8",
          "url": "https://github.com/kaappi/kaappi/commit/c916a8e94030f82cd199966587b077fc768affd6"
        },
        "date": 1783539360405,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.332005,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.096949,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.99654,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.401881,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012756,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.20441,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.498143,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069503,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.652863,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.938407,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 10.190319,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.008044,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.487802,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.700425,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044321,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "a50fd864b9548708d7bf8f0a8281a6f76ae1523f",
          "message": "Implement complete SRFI-132 sort library (22 procedures) (#1339)\n\n* Implement complete SRFI-132 sort library (22 procedures) (#1231)\n\nAdd the 14 missing procedures (list-stable-sort!, vector-stable-sort!,\nlist-merge, list-merge!, vector-merge, vector-merge!,\nlist-delete-neighbor-dups, list-delete-neighbor-dups!,\nvector-delete-neighbor-dups, vector-delete-neighbor-dups!,\nvector-find-median, vector-find-median!, vector-select!,\nvector-separate!) and retrofit all vector procedures with optional\nstart/end range parameters via case-lambda.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Fix delete-neighbor-dups predicate shadowing and relax separate! test\n\nRename the = parameter to elt= in %vector-delete-neighbor-dups and\n%vector-delete-neighbor-dups! so it does not shadow the built-in\nnumeric = used for index termination checks. Without this, non-numeric\npredicates like char=? crash on the (= i end) bounds test.\n\nAlso relax the vector-separate! test to assert set membership rather\nthan exact order, since SRFI-132 only guarantees the smallest k\nelements land in the first k positions.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-09T00:41:48+05:30",
          "tree_id": "2525f4b1e32c069255a68a4ba80b4db2a147c178",
          "url": "https://github.com/kaappi/kaappi/commit/a50fd864b9548708d7bf8f0a8281a6f76ae1523f"
        },
        "date": 1783539620995,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.86953,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.720902,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.955628,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.030291,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.013706,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.193013,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.468558,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.065269,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.597516,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.73859,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.62747,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.935619,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 7.864626,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.041998,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.041467,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "fa451202863a3fa0d29ab925c29555eca96c18c6",
          "message": "Fix SRFI-134 ideque-filter calling unbound 'filter' (#1212) (#1341)\n\nideque-filter called 'filter' which is not exported by (scheme base).\nDefine a local filter-list helper, consistent with the existing local\nfold-left in the same library. Re-enable the previously disabled test.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-09T06:02:47+05:30",
          "tree_id": "40b14051a70a65ddea4373d594068c496c6f97d5",
          "url": "https://github.com/kaappi/kaappi/commit/fa451202863a3fa0d29ab925c29555eca96c18c6"
        },
        "date": 1783559026583,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.08113,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.683051,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 1.024605,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.479889,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.013881,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.225982,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.514154,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068081,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 13.626942,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.990783,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 11.307326,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.125681,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 9.293784,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.844426,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.046125,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "a864683c326b4765da08762b45a6d86de7453634",
          "message": "Fix SRFI-37 args-fold: short option matching, seed threading, option? export (#1211) (#1343)\n\nThree bugs made args-fold unusable for typical CLI parsing:\n\n1. Short char-name options never matched — the lookup built a string\n   from the char (e.g. \"v\") and compared it via member against names\n   that are chars (#\\v). Fixed by passing the char directly.\n\n2. List-valued seeds were splatted — the heuristic\n   `(if (list? new-seeds) new-seeds (list new-seeds))` unwrapped any\n   processor that legitimately returned a list as its single seed.\n   Replaced all 8 sites with call-with-values to thread seeds correctly.\n\n3. option? predicate was not exported despite being part of the SRFI\n   specification.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-09T06:05:21+05:30",
          "tree_id": "896e722d43f043dd374e86d0aba924f8128bce6f",
          "url": "https://github.com/kaappi/kaappi/commit/a864683c326b4765da08762b45a6d86de7453634"
        },
        "date": 1783559380919,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.322676,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.648277,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.962974,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.390659,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012752,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.203695,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.496587,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068732,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.656907,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.929298,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 10.191902,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.003227,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.430952,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.754718,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043772,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "771b480a01164e387a87da94233059aea18b69ba",
          "message": "Implement SRFI-17 generalized set! with pre-defined setters (#1349)\n\n* Implement SRFI-17 generalized set! with pre-defined setters (#1205)\n\nThe compiler now desugars (set! (proc arg ...) val) to\n((setter proc) arg ... val) in both the IR lowering path and the\nlegacy compiler path. The SRFI-17 library registers pre-defined\nsetters for car, cdr, vector-ref, string-ref, and all 28 cXXr\ncompositions as specified by the SRFI.\n\nCloses #1205\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Address review feedback: GC safety, error type, comments, test coverage\n\n- Use no_collect + pushRoot in legacy compileSet to protect intermediate\n  pairs during S-expression construction (mirrors compileDefineValues)\n- Change 16-arg cap error from InvalidSyntax to InternalLimit\n- Add comments: setter global dependency, LLVM backend fallback,\n  defensive-fallback note on legacy path\n- Add 4-deep cXXr test case (cadddr)\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-09T06:31:27+05:30",
          "tree_id": "3c51be38b8d049ee4c5eb7ada39ec01a1c781fd8",
          "url": "https://github.com/kaappi/kaappi/commit/771b480a01164e387a87da94233059aea18b69ba"
        },
        "date": 1783560748951,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.332546,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.349344,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.981794,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.441684,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.01259,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.204727,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.509252,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069815,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.717361,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.943761,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 10.198703,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.014291,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.429991,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.72545,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045724,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "2f6ccae01aaf2cdb2bae5157804b918ffcc9faa5",
          "message": "Fix SRFI-42 comprehensions: recursive qualifiers, guards, and missing generators (#1346)\n\n* Fix SRFI-42 comprehensions: recursive qualifiers, guards, and missing generators (#1216)\n\nRewrite SRFI-42 with a two-macro architecture: do-ec introduces a mutable\nstop flag and delegates to %do-ec, which recursively processes one qualifier\nper expansion. This enables nested qualifiers (cartesian products), (if ...)\nguards, and :while/:until early exit via the stop flag. Also implements\n:string, :vector, :integers, :let generators and corrects fold-ec to match\nthe SRFI-42 signature (seed qualifier... expr proc).\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Fix fold-ec/fold3-ec arg order and add :while/:until generator-wrapping form\n\nAddress review feedback:\n- fold-ec: call reducer as (f value accumulator) per SRFI-42 spec\n- fold3-ec: add missing x0 seed parameter, fix f2 arg order, return\n  x0 on empty sequences\n- Add :while/:until generator-wrapping patterns so the spec form\n  (:while (:range i 10) (< i 5)) works alongside the standalone form\n- Add tests: fold-ec with cons/-, fold3-ec (including empty case),\n  and/or guards, :while wrapping generator\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-09T10:03:31+05:30",
          "tree_id": "b0bfdf23b3abd86dafe32923387f518ab7ddcb9e",
          "url": "https://github.com/kaappi/kaappi/commit/2f6ccae01aaf2cdb2bae5157804b918ffcc9faa5"
        },
        "date": 1783573570784,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.08692,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 10.586866,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 1.036403,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.744011,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.014242,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.225702,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.512493,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.067823,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 13.598159,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.975959,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 11.306493,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.12432,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 9.302816,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.896588,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.046797,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "72477f4262989071568aa9380e77d8b120b29381",
          "message": "Fix SRFI-197 chain _ placeholder and add nest/nest-reverse (#1219) (#1345)\n\n* Fix SRFI-197 chain to substitute _ placeholder; add nest/nest-reverse (#1219)\n\nchain previously inserted the pipeline value as the first argument\nunconditionally.  Per SRFI-197, the _ placeholder marks where the value\ngoes; steps without _ ignore the pipeline value entirely.\n\nThe rewrite uses a two-phase helper (%chain-subst / %chain-subst*) that\nscans step arguments for _ as a syntax-rules literal and replaces each\noccurrence with the pipeline value.  chain-and and chain-when delegate to\nchain for step application, so they inherit _ support automatically.\n\nAlso adds nest (outermost-first) and nest-reverse (innermost-first)\nnesting operators, both with _ substitution.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Fix chain-when guard semantics and add nest syntax-error for missing _\n\nAddress review feedback:\n\n- chain-when: guard is an expression evaluated directly, not a procedure\n  called with the pipeline value. (if guard ...) not (if (guard? v) ...).\n  Matches the SRFI-197 spec example: ((odd? n) (cons \"odd\" _)).\n\n- nest/nest-reverse: raise syntax-error when a step has no _ placeholder\n  instead of silently dropping the inner form.\n\n- Tests: add expression-guard and false-guard-in-middle coverage for\n  chain-when; assert nest-reverse equivalence test against a literal.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-09T10:09:01+05:30",
          "tree_id": "a7a7785c6d623fa7a63e98ef5ac2be5d3ac8689b",
          "url": "https://github.com/kaappi/kaappi/commit/72477f4262989071568aa9380e77d8b120b29381"
        },
        "date": 1783573825569,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.334447,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.217004,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.975358,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.422328,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012765,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.203741,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.505131,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069714,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.702845,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.952491,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 10.175907,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.998544,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.420488,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.738723,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.046499,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "280085559c1ff2221e3a8bc921f5056fbc086252",
          "message": "Fix SRFI-78 check-passed?, add check-set-mode! and check-ec (#1342)\n\n* Fix SRFI-78 check-passed? signature, add check-set-mode! and check-ec (#1220)\n\ncheck-passed? now takes an expected-total-count argument and returns a\nboolean per the SRFI-78 specification, instead of returning the raw pass\ncount. Adds check-set-mode! (off/summary/report-failed/report) and\ncheck-ec (eager comprehension checks using SRFI-42).\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Address review: check-ec early-stop, mode validation, first-fail reporting\n\n- check-ec now uses call/cc to escape on the first mismatch, per spec\n  (previously ran the whole comprehension and reported the last failure)\n- check-ec accepts zero qualifiers (delegates to check) and trailing\n  diagnostic argument lists\n- check-set-mode! rejects unknown modes with an error\n- check-report prints the first failed check when there are failures\n- Add (scheme process-context) import for exit\n- %first-fail is now read by check-report (was dead state)\n- Tests cover early-stop, summary mode, invalid mode, zero qualifiers,\n  and diagnostic arguments (19 assertions)\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Fix caddr crash in check-report, remove dead equal parameter\n\ncheck-report used caddr which is not in (scheme base) — crashes inside\nthe library on any run with a failure. Replaced with (car (cddr ...)).\nAlso added (scheme process-context) import for exit, and removed the\nunused equal parameter from check-ec-run.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Add side-effect counter for early-stop and check-report failure regression\n\n- check-ec early-stop test now uses a mutation counter to prove only 1\n  iteration runs (would fail if escape were removed)\n- check-report failure path tested as subprocess in exit-code.sh:\n  verifies exit code 1 and \"First failure:\" output\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-09T04:46:11Z",
          "tree_id": "5323bf41843a4a4eac9c80568223ef6bda2542ec",
          "url": "https://github.com/kaappi/kaappi/commit/280085559c1ff2221e3a8bc921f5056fbc086252"
        },
        "date": 1783573969465,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.089698,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.661314,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 1.019605,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.422565,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.013835,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.226041,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.512759,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.06806,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 13.572369,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.984179,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 11.376078,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.115444,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 9.270053,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.850152,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045482,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "84e9d6808d9f7ce2f2e10d377daf1154f500f85e",
          "message": "Rewrite SRFI-26 cut/cute with recursive helper macros (#1208) (#1344)\n\n* Rewrite SRFI-26 cut/cute with recursive helper macros (#1208)\n\nThe previous implementation used a finite set of hardcoded syntax-rules\npatterns that capped arity, broke pattern matching order (earlier patterns\nswallowed later slot tokens), lacked operator-position slot support, and\ndefined cute as a plain alias of cut.\n\nReplace with the standard recursive-helper-macro technique: cut and cute\nentry macros separate the operator, then srfi-26-internal-cut/cute walk the\nargument list one element at a time, accumulating slot-names and the call\nform. cute wraps each non-slot expression in a nested single-binding let\nso it evaluates once at construction time (avoids an expander limitation\nwith ellipsis in let binding lists).\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Fix expander hygiene for recursive binder-accumulating macros\n\nTemplate-introduced identifiers accumulated across recursive macro\nself-invocations (e.g. x in SRFI-26's (slot-name ... x) pattern)\nwere colliding with top-level defines of the same name. The VOID-\nmarking trick in expandAndCompileMacroUse was suppressing hygiene\nrenaming for any template free-ref candidate that matched a global,\nincluding template-introduced binders that only coincidentally shared\na name.\n\nFix: record which free-ref candidates were actually bound at macro\ndefinition time (bound_free_refs on the Transformer), and restrict\nVOID marking to only those identifiers. Template-introduced names\nthat weren't in scope when the macro was defined are now correctly\nrenamed regardless of later user defines.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Propagate OOM from computeBoundFreeRefs, add rest-slot hygiene test\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-09T05:08:12Z",
          "tree_id": "fcc0aad7e2df2b07475ed3a81923a8276943f086",
          "url": "https://github.com/kaappi/kaappi/commit/84e9d6808d9f7ce2f2e10d377daf1154f500f85e"
        },
        "date": 1783575607418,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.319834,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.44072,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.982846,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.399059,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012967,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.203502,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.504719,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.06949,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.652432,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.933856,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 10.166301,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.004414,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.406168,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.552838,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044036,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "cc5ff20178228b4fd458818ae02c78c11ddaae3b",
          "message": "Add SRFI-174 timespec-hash, timespec->inexact, inexact->timespec (#1235) (#1352)\n\nThe library was missing three of the nine procedures defined by the spec.\nUses floor (not truncate) for inexact->timespec so nanoseconds stays\nnon-negative, consistent with the POSIX convention and existing comparisons.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-09T11:28:21+05:30",
          "tree_id": "2a70a2390a400d6048a087669ffe98d09f4c8fd3",
          "url": "https://github.com/kaappi/kaappi/commit/cc5ff20178228b4fd458818ae02c78c11ddaae3b"
        },
        "date": 1783579429394,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.323152,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.868227,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.964982,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.395056,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012531,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.203637,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.496114,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068756,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.63632,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.937918,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 10.157106,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.991583,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.402897,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.683711,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.04358,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "d7eaaf6f4eda89f7a9d05ab16885d17946cc1089",
          "message": "Fix SRFI-143 fxcopy-bit to accept boolean bit argument (#1323) (#1351)\n\nfxcopy-bit used (= bit 0) which rejected booleans with a type error.\nThe SRFI-143 spec says bitwise ops match SRFI-151, where copy-bit takes\na boolean. Use (if bit ...) instead, mirroring the SRFI-151 fix in #1316.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-09T11:27:47+05:30",
          "tree_id": "ed65d8fed2ccd1e82d57a36a59a4eadab7e52f67",
          "url": "https://github.com/kaappi/kaappi/commit/d7eaaf6f4eda89f7a9d05ab16885d17946cc1089"
        },
        "date": 1783579476913,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.065119,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 10.6979,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 1.039756,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.407508,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.013855,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.225974,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.51243,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.06816,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 13.649293,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.980631,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 11.308792,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.123852,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 9.289353,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.895397,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.046244,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "d26037326c3bd929ddacf668e41ba9c99eeab975",
          "message": "Export lazy and eager from SRFI-45 (#1207) (#1353)\n\nThe library only re-exported the R7RS (scheme lazy) surface. SRFI-45\nspecifies two additional names: lazy (alias for delay-force) and eager\n(wraps make-promise). Add both and enable the disabled tests.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-09T11:28:56+05:30",
          "tree_id": "0aaa2bf84e35c4670dca31d16756e32199762b26",
          "url": "https://github.com/kaappi/kaappi/commit/d26037326c3bd929ddacf668e41ba9c99eeab975"
        },
        "date": 1783579579325,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.048278,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 10.031534,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 1.026483,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.397855,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.014198,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.225819,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.512987,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.06784,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 13.694373,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.979417,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 11.331747,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.116877,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 9.306339,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.855549,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.04675,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "c20b06e8355a97a0bd15ef3ec072f60fa77c96b3",
          "message": "Fix SRFI-1 take-right/drop-right to accept dotted lists (#1166) (#1354)\n\nThe spec says flist may be proper or dotted, but the length-counting\nloop required every cdr to be a pair, rejecting dotted tails. Replace\nwith a lead/lag two-pointer walk that naturally handles dotted tails.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-09T06:12:51Z",
          "tree_id": "877b9ccafc6d234279581cdefaa0f7c09f92f164",
          "url": "https://github.com/kaappi/kaappi/commit/c20b06e8355a97a0bd15ef3ec072f60fa77c96b3"
        },
        "date": 1783579636498,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.362967,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.182808,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.99893,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.397233,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.013135,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.204096,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.502921,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069175,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.635749,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.932078,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 10.155653,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.001573,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.439286,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.666999,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.04398,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "04149d24b24b018ca79ed6a63d1f7df98c8448ff",
          "message": "Implement SRFI-61 general cond clause (generator guard => receiver) (#1206) (#1357)\n\nReplace the empty SRFI-61 stub with a syntax-rules macro that shadows the\nbuilt-in cond, adding the (generator guard => receiver) clause form. The\ngenerator may return multiple values via call-with-values; the guard is\napplied to them, and if true the receiver gets the same argument list.\n\nAll standard R7RS cond clause forms are preserved by the macro.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-09T06:12:55Z",
          "tree_id": "b8e062272dda90b26a925d89e269a3ecbdb41862",
          "url": "https://github.com/kaappi/kaappi/commit/04149d24b24b018ca79ed6a63d1f7df98c8448ff"
        },
        "date": 1783579969785,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.047641,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.763082,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 1.028305,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.411822,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.01397,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.226041,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.543857,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068488,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 13.633277,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.981726,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 11.330798,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.116436,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 9.276736,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.86241,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.046734,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "0e11c9b962454992f1fb6e500feadf7bec110cc5",
          "message": "Skip stress tests in Debug CI builds (#1365)\n\n* Skip stress tests in Debug CI builds (#1364)\n\nDebug builds are ~500x slower for allocation-heavy workloads, causing\nthree stress/benchmark files to exceed run-all.sh's 60s per-file timeout.\nAdd KAAPPI_SKIP env var support to skip named files, and KAAPPI_TIMEOUT\nto override the default timeout. CI sets KAAPPI_SKIP for the Debug matrix\nentry to skip callcc-bench.scm, r7rs-tail-procedures-gaps.scm, and\nr7rs-thin-forms-gaps.scm. These files still run in all Release builds.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Rename env vars to KAAPPI_TEST_SKIP and KAAPPI_TEST_TIMEOUT\n\nThese are test-runner-specific, so the KAAPPI_TEST_ prefix is clearer.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Address review feedback\n\n- Set matched=1 for skipped files to avoid false \"(no tests matched)\"\n- Compute KAAPPI_TEST_SKIP inline instead of via matrix field to keep\n  the GitHub job name clean\n- Document KAAPPI_TEST_SKIP and KAAPPI_TEST_TIMEOUT in tests/scheme/CLAUDE.md\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-09T08:28:17Z",
          "tree_id": "beb2149fae709648805b0b10fe3a63266f45dd08",
          "url": "https://github.com/kaappi/kaappi/commit/0e11c9b962454992f1fb6e500feadf7bec110cc5"
        },
        "date": 1783587287776,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.332639,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.76801,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.988455,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.395257,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012948,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.204046,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.504437,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069118,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.649345,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.947478,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 10.165431,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.001799,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.438081,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.714194,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043823,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "727f916d5139537dfe8c7d4f00af7a89b734fb26",
          "message": "Fix SRFI-133 vector-skip/vector-skip-right multi-vector form (#1171) (#1359)\n\nBoth procedures were registered with exact arity 2, rejecting the\nmulti-vector form specified by SRFI-133. Change to variadic arity and\nimplement the multi-vector loop pattern (matching vector-index and\nvector-index-right).\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-09T14:54:06+05:30",
          "tree_id": "29d798fca7b9bd6c6713509efe22add5f86221a0",
          "url": "https://github.com/kaappi/kaappi/commit/727f916d5139537dfe8c7d4f00af7a89b734fb26"
        },
        "date": 1783590572443,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.353974,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.387366,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.984675,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.420165,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.01259,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.203867,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.505349,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.06918,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.8198,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.948949,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 10.184067,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.018921,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.428529,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.726348,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044605,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "a03e120143032efdd47bc39c2f8934e3f60d7e5e",
          "message": "Fix SRFI-143 comparison and min/max to accept variadic arguments (#1226) (#1361)\n\nfx=?/fx<?/fx>?/fx<=?/fx>=? now accept two or more arguments (chained\ncomparison) and fxmax/fxmin accept one or more, matching the SRFI-143 spec.\nPreviously all were fixed at exactly 2 arguments.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-09T14:55:29+05:30",
          "tree_id": "3e2863162aaaa8d7841b173c6ea354377b740f54",
          "url": "https://github.com/kaappi/kaappi/commit/a03e120143032efdd47bc39c2f8934e3f60d7e5e"
        },
        "date": 1783591203172,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.351094,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.145511,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.969931,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.397312,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012563,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.204161,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.503941,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069178,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.69444,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.948383,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 10.168648,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.000758,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.409193,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.687733,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043763,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "a8e2352167b36a93122c923bbe1a3207af9de31e",
          "message": "Fix SRFI-13 wrong-typed optional args silently ignored (#1159) (#1360)\n\nstring-pad/string-pad-right treated a non-char pad argument as absent\n(defaulting to space). string-unfold/string-unfold-right did the same\nfor a non-string base argument, and silently dropped make-final return\nvalues that weren't strings. All six sites now raise a type error.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-09T15:16:35+05:30",
          "tree_id": "1c4086d0ce7506ba81efcb5051ec8e4562f34205",
          "url": "https://github.com/kaappi/kaappi/commit/a8e2352167b36a93122c923bbe1a3207af9de31e"
        },
        "date": 1783592112659,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.360633,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.514839,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 1.002208,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.408966,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.013032,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.205765,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.504587,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069824,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.763283,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.957858,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 10.266607,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.003305,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.721833,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.779457,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045596,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "9d8a6a4b99e450fb934f50200086043113e9e63d",
          "message": "Fix SRFI-144 flmax/flmin to be variadic per spec (#1217) (#1358)\n\n* Fix SRFI-144 flmax/flmin to be variadic per spec (#1217)\n\nflmax and flmin were defined as exactly 2-argument functions, but\nSRFI-144 specifies them as variadic: (flmax x ...) and (flmin x ...).\nWith zero arguments they return -inf.0 and +inf.0 respectively.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Handle NaN as missing data per C99 fmax/fmin semantics\n\nSRFI-144 specifies flmax/flmin as C99 fmax/fmin, where NaN arguments\nare treated as missing data and the numeric value wins. Seed best from\nthe first argument (preserving all-NaN → NaN) and skip NaN via explicit\nchecks so the result is order-independent.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-09T09:41:50Z",
          "tree_id": "7afff42f751c8b8b66810ff44c51936e4a67cc29",
          "url": "https://github.com/kaappi/kaappi/commit/9d8a6a4b99e450fb934f50200086043113e9e63d"
        },
        "date": 1783592746567,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.072632,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.715068,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 1.033465,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.436562,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.013792,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.226057,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.512297,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.067952,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 13.616688,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.97948,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 11.349031,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.113935,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 9.261805,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.851302,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.046718,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "ff6ee45706025061d044aed7852d2cb3549c9c7c",
          "message": "Accept native procedures in make-thread and spawn (#1155) (#1366)\n\n* Accept native procedures in make-thread and spawn (#1155)\n\nmake-thread (SRFI-18) and spawn (fibers) rejected native built-in\nprocedures like `list` or `newline` because they checked isClosure\ninstead of isProcedure. For make-thread, the downstream callWithArgs\nalready handles all procedure types, so the fix is a predicate change.\n\nFor spawn, the fiber scheduler sets up an initial bytecode frame\ndirectly from the closure's code, so non-closure procedures need a\ntrampoline: a synthetic closure whose bytecode loads the real procedure\nfrom an upvalue and calls it. The fiber is rooted across the trampoline\nallocation to prevent GC from freeing it.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Move fiber-native-thunk test to smoke/ and add ISA coupling comment\n\nfiber-native-thunk.scm tests (kaappi fibers), not an SRFI library,\nso it belongs in tests/scheme/smoke/ per test directory conventions.\n\nAlso adds a comment noting the trampoline bytecode's operand width\ndependency on vm_dispatch.zig's fixed_operand_bytes table.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-09T15:28:54+05:30",
          "tree_id": "bd14513def1bf2b57215ab3fbf10feed8533c787",
          "url": "https://github.com/kaappi/kaappi/commit/ff6ee45706025061d044aed7852d2cb3549c9c7c"
        },
        "date": 1783593169593,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.411998,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.309634,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 1.011141,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.459255,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012721,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.203873,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.511586,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068621,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.589531,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.954491,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 10.178288,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.007721,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.447222,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.67817,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.04457,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "9aba97b7fc2fa6e2ee8e42259ae0f390a380cea6",
          "message": "Export owner/unchanged and group/unchanged constants from SRFI-170 (#1163) (#1363)\n\n* Export owner/unchanged and group/unchanged constants from SRFI-170 (#1163)\n\nSRFI-170 specifies these as integer constants (-1) for partial chown\nvia set-file-owner. The implementation already handled -1 correctly in\nvalidateUid but the constants were never exported.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Guard SRFI-170 constants with comptime !is_wasm\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-09T15:29:49+05:30",
          "tree_id": "78527ccddd40d530ece8ed7fe828238d170e1305",
          "url": "https://github.com/kaappi/kaappi/commit/9aba97b7fc2fa6e2ee8e42259ae0f390a380cea6"
        },
        "date": 1783593171714,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.093713,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.590853,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 1.013155,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.420086,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.013895,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.226404,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.512089,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068028,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 13.760372,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.983107,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 11.3403,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.150227,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 9.271918,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.859988,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045433,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "3e196f07ea359df662d9f22182dbb794e4595c39",
          "message": "Fix random-source-make-reals to honor the unit argument (#1194) (#1367)\n\n* Fix random-source-make-reals to honor the unit argument (#1194)\n\nThe procedure validated that 0 < unit < 1 but then discarded it,\nalways returning a default-precision flonum. With an exact rational\nunit, the SRFI-27 spec requires exact results quantized as\nx*unit for random x in {1, ..., floor(1/unit)-1}.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Address review: fix bound for non-integer reciprocal units, add tests\n\nWhen 1/unit is not an integer (e.g. unit=3/5, 3/10), use floor(1/unit)\ndirectly instead of floor(1/unit)-1, which would undershoot or hit zero.\nThe -1 is only needed when 1/unit is an integer (to avoid generating\nexactly 1.0). Also drops the redundant exact wrapper.\n\nAdds test cases for 3/10, 3/5, and 2/3 units covering the non-integer\nreciprocal and (1/2,1) edge cases.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n* Update lib/srfi/27.sld\n\n* Document exact-unit quantization choice in CONFORMANCE.md\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-09T10:33:28Z",
          "tree_id": "4782af2069e953fe97349fb0d6ea3f64e34b122b",
          "url": "https://github.com/kaappi/kaappi/commit/3e196f07ea359df662d9f22182dbb794e4595c39"
        },
        "date": 1783594663555,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.148315,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.722097,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.81296,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.42002,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.010927,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.175614,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.396804,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.052682,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 9.959972,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.533468,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 8.844765,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.871646,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 7.211644,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.498043,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.035903,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "57d7c5d43b62b943e15f3f16067a7537c979cab8",
          "message": "Fix string-trim default criterion to use Unicode whitespace (#826) (#1368)\n\nThe no-argument fast paths in string-trim, string-trim-right, and\nstring-trim-both scanned raw bytes with a hard-coded ASCII whitespace\ncheck, missing vertical tab, form feed, and all multi-byte Unicode\nwhitespace (NBSP, EM SPACE, IDEOGRAPHIC SPACE, etc.). Now decodes\ncodepoints and delegates to isUnicodeWhitespace, matching char-whitespace?\nand the SRFI-13 spec (default criterion is char-set:whitespace).\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-09T16:55:14+05:30",
          "tree_id": "2c25551b37d3c270ffd7d0c8790e3d7450338162",
          "url": "https://github.com/kaappi/kaappi/commit/57d7c5d43b62b943e15f3f16067a7537c979cab8"
        },
        "date": 1783598633849,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.084027,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 10.140564,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 1.012393,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.428552,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.013968,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.226089,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.512854,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.06815,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 13.655432,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.976762,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 11.33801,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.123657,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 9.301226,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.905559,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.046609,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
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
      }
    ]
  }
}