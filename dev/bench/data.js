window.BENCHMARK_DATA = {
  "lastUpdate": 1783355328285,
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
          "id": "dfd461546a326e5255abadcc09db4bf253c0d9d2",
          "message": "Replace last inline VMError switches with shared mapVMError helper (#1019)\n\nThe string-for-each and string-map catch blocks were the last two sites\nusing inline 4-arm switch blocks instead of the shared mapVMError helper.\nThe else arm collapsed unexpected VM errors into TypeError, hiding the\nreal error variant.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-04T03:56:40Z",
          "tree_id": "2c206568899b7b5239621cc96a75e27b825c0acd",
          "url": "https://github.com/kaappi/kaappi/commit/dfd461546a326e5255abadcc09db4bf253c0d9d2"
        },
        "date": 1783138527582,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.521467,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.740465,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.931879,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.40639,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012464,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.210722,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.467642,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070825,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.388048,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.826125,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.916997,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.967263,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.266865,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.713545,
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
          "id": "946cc3bab1671c72ecf84d931e4c3f29c85900c9",
          "message": "Extract shared parseOptionalRange helper for optional start/end args (#1018)\n\n16 call sites across primitives_vector, primitives_bytevector,\nprimitives_string, and primitives_string_ext repeated the same\n10-line pattern for parsing optional start/end range arguments.\nPromote a single parseOptionalRange to primitives.zig and replace\nall inline copies.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-04T03:56:36Z",
          "tree_id": "958bbcdfd63374fe1729e9e9653b972554cf8709",
          "url": "https://github.com/kaappi/kaappi/commit/946cc3bab1671c72ecf84d931e4c3f29c85900c9"
        },
        "date": 1783138545098,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.318658,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.949219,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.901457,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.324677,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.013191,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.211021,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.466919,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070441,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.443533,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.820628,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.899087,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.979322,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.39483,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.74777,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045788,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "c047a9d73c10ea80561233f5706423549b0a9564",
          "message": "Add indexError detail helper for informative out-of-bounds messages (#1020)\n\nIndexOutOfBounds errors previously gave no diagnostic info. Add\nprimitives.indexError(proc, index, len) — mirroring the existing\ntypeError helper — and convert all 21 bare IndexOutOfBounds returns\nacross vectors, strings, bytevectors, and lists to use it. Errors\nnow read e.g. \"vector-ref: index 10 out of range for length 3\".\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-04T04:20:12Z",
          "tree_id": "76df355d51aa35fe3c65b233ebaef65a9b732735",
          "url": "https://github.com/kaappi/kaappi/commit/c047a9d73c10ea80561233f5706423549b0a9564"
        },
        "date": 1783139922030,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.292671,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.986417,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.906804,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.266229,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012476,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.211194,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.486856,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070519,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.460948,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.828124,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.920686,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.954199,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.254816,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.670363,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043425,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "fc642d3eb5911d9da14510734c3f9c8c72e956fb",
          "message": "Relocate gc_instance threadlocal from primitives.zig to memory.zig (#1021)\n\nThe GC instance pointer belongs next to the GC struct it references.\nHaving it in primitives.zig forced every primitives file to import\nprimitives.zig just to reach the GC, making the dependency graph\nmisleading. Now call sites import memory.zig directly.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-04T04:52:02Z",
          "tree_id": "47b194241fcb31fe79183ae9e188a9493e156120",
          "url": "https://github.com/kaappi/kaappi/commit/fc642d3eb5911d9da14510734c3f9c8c72e956fb"
        },
        "date": 1783141862187,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.279873,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.000728,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.934809,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.323917,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.01246,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.210759,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.486504,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070842,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.55309,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.843697,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.967895,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.976127,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.333095,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.738257,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043895,
            "unit": "seconds"
          }
        ]
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
          "id": "69a7e54676dbf7ea0b7789dcd89b671db07734b3",
          "message": "Release skill: sync docs WASM via workflow, not local copy\n\nStep 11 copied the locally built zig-out/bin/kaappi.wasm into the docs site,\nso the playground ran a binary that wasn't the one attested in the release\nSHA256SUMS. Point it at the new kaappi.github.io update-wasm workflow, which\ndownloads the released wasm, verifies it against SHA256SUMS, bumps\nkaappi_version, and deploys. Also drop the manual mkdocs.yml version bump from\nStep 4 (a separate repo, now handled by that workflow post-release).\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-04T11:01:54+05:30",
          "tree_id": "66d2700dc6d754eaa753720c67d9379219ccac57",
          "url": "https://github.com/kaappi/kaappi/commit/69a7e54676dbf7ea0b7789dcd89b671db07734b3"
        },
        "date": 1783144156733,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.247405,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.754845,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.908286,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.285608,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012434,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.210578,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.476831,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070887,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.448181,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.827789,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.914827,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.956891,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.267025,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.712513,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043184,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "bf6f479c57fbf17c5ff42dd0920d3243e5dde1a9",
          "message": "Split compiler IR handlers into compiler_ir.zig (#1023)\n\ncompiler.zig was 1763 lines, exceeding the 1500-line policy. Extract 12\nIR-to-bytecode compilation handlers (compileFromNode, compileIfFromIR,\ncompileCallFromIR, compileLambdaWithIR, etc.) into a new compiler_ir.zig\nfile (490 lines), bringing compiler.zig down to 1279 lines.\n\nFollows the same pattern as the existing compiler_*.zig split files:\nfree functions taking *Compiler, importing types/memory/ir_mod as needed.\nMade compileVariable, compileDefineSyntax, compileLetSyntax, and\ncompileLetrecSyntax pub so compiler_ir.zig can call them via the\nCompiler pointer.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-04T05:39:33Z",
          "tree_id": "adbdcdd8ac0cd36f5b88bb9458bcbd62571a3a43",
          "url": "https://github.com/kaappi/kaappi/commit/bf6f479c57fbf17c5ff42dd0920d3243e5dde1a9"
        },
        "date": 1783144719287,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.145031,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.753721,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.736585,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.1561,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.010809,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.181488,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.365626,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.052801,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 9.753561,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.420774,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 8.537322,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.834448,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 7.263651,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.472326,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.034941,
            "unit": "seconds"
          }
        ]
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
          "id": "c5c7836ea35eb8ea6c1dd763d7f8263a7d977828",
          "message": "Release skill: fix race in gh run watch, add error recovery\n\nAdd sleep before gh run list to avoid watching a stale run (gh workflow\nrun is async). Remove the deprecated manual cp note to avoid ambiguity.\nAdd error recovery guidance for Step 11 workflow failures.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-04T11:18:32+05:30",
          "tree_id": "06d2d9bf246cc20c9095103eddc1f07354e5d756",
          "url": "https://github.com/kaappi/kaappi/commit/c5c7836ea35eb8ea6c1dd763d7f8263a7d977828"
        },
        "date": 1783145289132,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.280022,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.110048,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.923711,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.274917,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012615,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.211177,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.474277,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.07165,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.521683,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.843839,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.943757,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.962907,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.242511,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.70888,
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
          "id": "2fda2fac2ab79f6a94def762e6b5a4f6cbc1ea65",
          "message": "Break compiler→VM circular dependency via globals.zig (#1022)\n\nThe compiler, IR, and expander files all imported vm.zig for globals\nlocking helpers (acquireGlobalsRead/Write) and the vm_instance\nthreadlocal, while vm.zig imported compiler.zig — creating a\nbidirectional dependency that prevented either subsystem from being\nunderstood or tested in isolation.\n\nExtract GlobalsRwLock, the four acquire/release helpers, and a\nGlobalsContext threadlocal into a new src/globals.zig module. The\ncompiler side now imports globals.zig instead of vm.zig. The VM\nsets/clears the GlobalsContext alongside vm_instance, and registers\na library-existence callback so cond-expand can check library\navailability without importing vm.zig.\n\nAfter this change:\n- compiler*.zig, ir.zig, expander.zig → globals.zig (no vm.zig)\n- vm*.zig → compiler.zig (natural direction, unchanged)\n- vm.zig re-exports GlobalsRwLock and lock helpers for compatibility\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-04T06:03:54Z",
          "tree_id": "76c63d45f43387d67a8015eb70924f97f2f5f34a",
          "url": "https://github.com/kaappi/kaappi/commit/2fda2fac2ab79f6a94def762e6b5a4f6cbc1ea65"
        },
        "date": 1783146105365,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.158319,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.541602,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.757748,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.264343,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.010895,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.181574,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.370717,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.053879,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 9.762277,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.419222,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 8.53749,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.833595,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 7.024446,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.385655,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.035023,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "c0d4f10f8ca0cffe4c79e4bfde5814b9e899b136",
          "message": "Deduplicate primitives reg() wrappers, consolidate numberTypeError, merge compileAnd/compileOr (#1024)\n\nThree mechanical refactors to reduce duplication:\n\n- Delete identical 3-line reg() wrapper from all 18 primitives_*.zig files,\n  replacing ~532 call sites with direct primitives.reg() calls\n- Replace custom numberTypeError in primitives_arithmetic.zig (which used\n  allocating printer.valueToString) with primitives.typeError(), matching\n  the canonical stack-buffer pattern used everywhere else\n- Merge near-identical compileAnd/compileOr in compiler_conditionals.zig\n  into a shared compileShortCircuit helper parameterized by empty-case\n  opcode and jump opcode\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-04T06:25:42Z",
          "tree_id": "8f74161e63b7ead1048d5859ef2d26764492908b",
          "url": "https://github.com/kaappi/kaappi/commit/c0d4f10f8ca0cffe4c79e4bfde5814b9e899b136"
        },
        "date": 1783147503621,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.4199,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.839131,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.910764,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.429424,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012481,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.211286,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.485375,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069761,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.414382,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.856054,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.908115,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.947174,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.312223,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.696394,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.04323,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "33ef8be83a4c8935b8de6cdc51448361fc32d1e4",
          "message": "Fix top-level macros invisible inside bare-lambda bodies (#1025) (#1077)\n\ncompileLambdaWithIR lowered body forms with the child compiler's\n(empty) macro table. IR macro lookup now uses the compiler's\nlookupMacro(), which walks the parent chain, so macros defined\nin enclosing scopes are visible in lambda bodies compiled via IR.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-04T07:24:14Z",
          "tree_id": "3ad8cf784f358fb081b62f32153ce816daa26079",
          "url": "https://github.com/kaappi/kaappi/commit/33ef8be83a4c8935b8de6cdc51448361fc32d1e4"
        },
        "date": 1783151006742,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.289394,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.245355,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.915499,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.225461,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.01252,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.210741,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.467138,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.071188,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.40743,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.840497,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.847403,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.954312,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.29369,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.690237,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042658,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "ef31aaffecbf33225c0675f005bc6ae933982e12",
          "message": "Add letrec* desugaring to bare-lambda IR path (#1026) (#1078)\n\nInternal defines in `(define f (lambda () ...))` bodies were compiled\nsequentially, so forward references to sibling defines failed at\nruntime (R7RS 5.3.2 requires letrec* semantics). The `compileLambdaWithIR`\npath now pre-scans leading defines, pre-declares all names as boxed\nlocals, then evaluates initializers with all names visible — matching\nwhat `compileBody` already does for the `(define (f) ...)` shorthand.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-04T07:43:22Z",
          "tree_id": "4ea7fc39b6055089e51015f27a5e5d749cef2abc",
          "url": "https://github.com/kaappi/kaappi/commit/ef31aaffecbf33225c0675f005bc6ae933982e12"
        },
        "date": 1783152190042,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.050418,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.567618,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.943143,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.368699,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.013813,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.234288,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.473546,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068377,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 13.438335,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.828723,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 11.033571,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.072201,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 9.172195,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.846219,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044224,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "f91ac87f6af941f5e021002fd9dad183e870af46",
          "message": "Panic on writeBarrier remembered-set OOM instead of silently dropping (#1036) (#1079)\n\nA dropped remembered-set entry lets minor GC sweep a live young object.\nFollows the precedent set for mark-stack OOM in gc_collect.zig.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-04T08:05:05Z",
          "tree_id": "84fd5fb95f682c49ae29071540758ba8d6901b2d",
          "url": "https://github.com/kaappi/kaappi/commit/f91ac87f6af941f5e021002fd9dad183e870af46"
        },
        "date": 1783153493291,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.439125,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.91138,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.932947,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.342142,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012655,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.210856,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.475432,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.071463,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.38779,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.858453,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.892058,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.956226,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.298193,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.53661,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042337,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "11449dab9cda4a3d11994d87b001667ebc709cbe",
          "message": "Unify typeName into types.zig, fix LSP hover for records/rationals/bignums (#1033) (#1080)\n\nMove the Value-to-type-name switch from repl.zig and kaappi_lsp.zig into\na single canonical types.typeName(). The switch is exhaustive over all 37\nObjectTag variants (no else arm), so adding a new heap type will cause a\ncompile error rather than silently returning \"object\". Also adds\nnative_closure coverage (was missing from both copies).\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-04T08:12:11Z",
          "tree_id": "1b138dc8fcc874bafa4d3899301a4110e9c8652c",
          "url": "https://github.com/kaappi/kaappi/commit/11449dab9cda4a3d11994d87b001667ebc709cbe"
        },
        "date": 1783153946369,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.291704,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.046846,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.906538,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.219155,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012443,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.210616,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.463826,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070441,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.49,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.829384,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.878645,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.957933,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.26481,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.700918,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042515,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "d0c0a239936b3152c1e304f7127f1fb385b0e9e7",
          "message": "Propagate InvalidSyntax from let*-values and guard instead of swallowing as OOM (#1032) (#1081)\n\nbuildLetValues and appendToList can return error.InvalidSyntax, but\ncompileLetStarValues and compileGuard caught all errors as OutOfMemory.\nSwitch to error-specific catch so malformed syntax gets the correct\ndiagnostic.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-04T08:14:40Z",
          "tree_id": "1a2bf3f08db7f9f9cddbed3dc2d28b554bc5e936",
          "url": "https://github.com/kaappi/kaappi/commit/d0c0a239936b3152c1e304f7127f1fb385b0e9e7"
        },
        "date": 1783154091176,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.335431,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.476078,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.935874,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.408959,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012457,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.211299,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.478556,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.071308,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.514975,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.82835,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.874737,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.958875,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.266414,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.662024,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042731,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "0d96bfea581bd14b8e61a0a60be66f7b55789a0e",
          "message": "Add shadow-stack GC rooting for native backend (#1034) (#1082)\n\nThe LLVM emitter stored intermediate Values in SSA temps invisible to\nthe GC. Nested allocating calls (e.g. (cons (f x) (g y))) could lose\nearlier results when a later call triggers collection.\n\nFix: emit pushRoot/popRoot calls around live intermediates in\nemitCallNode, tryEmitInlineBinary, emitDirectCall, emitSelfTailCall,\nand let/let* bindings. Two new C-ABI exports (kaappi_gc_push_root,\nkaappi_gc_pop_roots) wrap gc.pushRoot/popRoot for native code.\nKAAPPI_GC_THRESHOLD env var enables stress-testing native binaries.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-04T08:28:55Z",
          "tree_id": "545f9f5661e96a49ea4b33ca2b19fa45334db99e",
          "url": "https://github.com/kaappi/kaappi/commit/0d96bfea581bd14b8e61a0a60be66f7b55789a0e"
        },
        "date": 1783154837706,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.364731,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.739928,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.934928,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.270478,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012558,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.210446,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.501335,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070874,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.537795,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.850792,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.86434,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.957908,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.279341,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.558445,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043631,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "8a6238442a9db94e446f8a4c6ffd6a17717a6fca",
          "message": "Port self-tail-call optimization and line-table recording to IR path (#1035) (#1083)\n\nThe IR compilation path missed two features the legacy path had:\n\n1. (define f (lambda (n) (f ...))) compiled recursive tail calls as\n   generic tail_call instead of self_tail_call (a loop). Fixed by\n   injecting the define's name into the lambda IR node before body\n   compilation and adding self-tail-call detection to compileCallFromIR.\n\n2. compileFromNode never recorded line-table entries, so IR-compiled\n   code lost per-line error attribution. Fixed by adding source_line\n   to IR Annotations (populated during lowering from gc.source_lines)\n   and emitting line-table entries at the top of compileFromNode.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-04T08:34:23Z",
          "tree_id": "88f02beeef52366ff3a0f2091b677605bf06849d",
          "url": "https://github.com/kaappi/kaappi/commit/8a6238442a9db94e446f8a4c6ffd6a17717a6fca"
        },
        "date": 1783155188471,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.410799,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.851593,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.944078,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.358614,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.01247,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.211121,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.484068,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.071328,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.440335,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.886773,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.907565,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.952135,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.296928,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.680686,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042712,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "7d7c14d5a837e38ffb5a8b25c846325ed313d3b8",
          "message": "Honor KAAPPI_HOME in interpreter, ffi-open, and REPL (#1031) (#1084)\n\nthottam installs to $KAAPPI_HOME/lib when the env var is set, but the\ninterpreter's library auto-discovery, ffi-open's dlopen fallback, and\nthe REPL history path all hardcoded ~/.kaappi. Extract a shared\nkaappi_paths.getHome() that checks KAAPPI_HOME first.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-04T09:39:22Z",
          "tree_id": "442745a4706090a6605feec00b2fcfa5cbbad03c",
          "url": "https://github.com/kaappi/kaappi/commit/7d7c14d5a837e38ffb5a8b25c846325ed313d3b8"
        },
        "date": 1783159186579,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.053066,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.362021,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.946239,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.323542,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.013879,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.234156,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.478272,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068269,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 13.516813,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.846139,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 11.031326,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.068619,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 9.084409,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.86721,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.04374,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "e8c77bb41dddd94a030209534a5a9ff0d14c2a84",
          "message": "Resurrect 11 orphaned regression tests, harden run-all.sh (#1029) (#1086)\n\n6 shell scripts in smoke/, 3 in errors/, and 2 loose .scm files were\nnever executed by run-all.sh or CI. Add run_shell_suite() to discover\nand run *.sh per suite directory, move the loose .scm files into smoke/\nwith accurate \"native\" naming, replace hardcoded /tmp paths with mktemp,\nand fail (not skip) on non-executable .sh files.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-04T09:39:15Z",
          "tree_id": "b6c28250351a93e0f6e933542e8e63bf8080869a",
          "url": "https://github.com/kaappi/kaappi/commit/e8c77bb41dddd94a030209534a5a9ff0d14c2a84"
        },
        "date": 1783159264575,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.427874,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.62194,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.939334,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.254467,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012675,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.211215,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.476852,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.07121,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.504677,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.876691,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.922672,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.961252,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.318337,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.713381,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043517,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "aeabf23c44181196453db073e03171471232946e",
          "message": "Root SRFI-1 filter-map/append-map/unfold callback results via extra_roots (#1027) (#1085)\n\nfilterMapFn, appendMapFn, and unfoldFn accumulated callVM results in\nplain ArrayList locals invisible to GC markRoots. Any subsequent callback\ncould trigger collection of previously-stored values. Apply the\nestablished extra_roots save/restore idiom (matching vector-map) and\nroot unfold's seed across callbacks. Add GC stress tests with\nallocating lambdas for all three.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-04T09:39:51Z",
          "tree_id": "3f5c59af40bf3e8ba4596767cc9fc466127765da",
          "url": "https://github.com/kaappi/kaappi/commit/aeabf23c44181196453db073e03171471232946e"
        },
        "date": 1783159331760,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.067868,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.80695,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.976139,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.386526,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.013754,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.234325,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.478369,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068553,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 13.451827,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.851073,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 11.020472,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.067313,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 9.084111,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.883509,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044436,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "073823db0937e2124baf7ab60cdc001666e82148",
          "message": "Fix cross-thread fiber.status atomics and encapsulate child_resources (#1028) (#1087)\n\nThe child OS thread wrote fiber.status with plain stores while the parent\npolled it with @atomicLoad(.acquire) — the missing release on the write\nside breaks ordering on ARM and RISC-V. Error paths also published status\nbefore storing the result, creating a window where the parent could see\n.errored/.completed before the exception/result was visible.\n\n- All cross-thread fiber.status writes now use @atomicStore(.release)\n- All cross-thread reads now use @atomicLoad(.acquire)\n- Error paths reordered: data stored before status is published\n- Inline spinlock sites replaced with ChildRegistry struct using\n  memory.spinLock/spinUnlock (adds spinLoopHint)\n- Never-joined thread leak documented as by-design\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-04T15:36:06+05:30",
          "tree_id": "412175058d71215fffd559ec40ee302c88380302",
          "url": "https://github.com/kaappi/kaappi/commit/073823db0937e2124baf7ab60cdc001666e82148"
        },
        "date": 1783160739779,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.085676,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.826477,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.961493,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.461851,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.013699,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.234516,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.480218,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068997,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 13.776304,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.849969,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 11.027269,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.06669,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 9.086669,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.829651,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.04407,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "9f5634c6576b3808f703daedd49186c592b44671",
          "message": "Extract kaappiModule helper, fix cov_mod/thottam_mod inconsistencies (#1065) (#1088)\n\nbuild.zig created 10 near-identical modules with hand-repeated createModule +\naddImport(\"build_options\") + linenoise C-source + embedded_bytecode blocks,\nbreeding inconsistencies:\n\n- cov_mod lacked link_libc = true (its sibling cov_main_mod had it)\n- thottam_mod lacked build_options entirely (blocked #1060)\n- Stack-size comment said \"16 MB\" but the value is 64 MB\n\nExtract a kaappiModule(b, options_mod, .{...}) helper that consolidates the\npattern: createModule + build_options import + optional linenoise C source +\noptional embedded_bytecode anonymous import. All 10 modules (plus the\ncompiler_mod in the bundle-src path) now use it.\n\nFixes: cov_mod gets link_libc, thottam_mod gets build_options, comment\ncorrected. Net -42 lines.\n\nCloses #1065\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-04T16:24:44+05:30",
          "tree_id": "4a3c7d16adde1ba47f965b78904440100d3b3d8a",
          "url": "https://github.com/kaappi/kaappi/commit/9f5634c6576b3808f703daedd49186c592b44671"
        },
        "date": 1783163715070,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.300599,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.074202,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.959024,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.341702,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.013243,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.210818,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.475004,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070779,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.615461,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.80365,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.872868,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.962235,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.411335,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.758513,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045448,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "a2858320cf6109c3e0029fa8c985b016f0afbde7",
          "message": "Split thottam.zig along natural seams (#1063) (#1089)\n\nthottam.zig was the only file over the 1500-line policy. Extract three\nself-contained modules:\n\n- thottam_semver.zig: Semver, Constraint, constraint parsing (pure logic)\n- thottam_proc.zig: fork/exec plumbing (runCapture, runGit, checkoutVersion)\n- thottam_state.zig: PkgSpec/PkgManifest parsing, lockfile/installed ops\n\nTests move with their code. No logic changes — pure code motion.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-04T16:24:58+05:30",
          "tree_id": "2b8b276d2bcbc7e9ce584e0b0a598b7ca8951034",
          "url": "https://github.com/kaappi/kaappi/commit/a2858320cf6109c3e0029fa8c985b016f0afbde7"
        },
        "date": 1783163866569,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.352378,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.133867,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 1.056541,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.317855,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012816,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.210575,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.467204,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070357,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.520738,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.818593,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.841304,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.956828,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.270609,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.545472,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043135,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "959ee717fcadf54a15cfe44c60e1342d407eee6a",
          "message": "Add debug-checked Object.as(), typed accessors, and box helpers (#1051) (#1090)\n\nObject.as(T) is used ~468 times with no tag verification. Add a comptime\nexpected-tag map so debug builds assert the tag matches before casting\n(zero cost in ReleaseSafe/Fast). Add toPair/toClosure/toNativeFn/\ntoContinuation accessors that the four hottest types were missing. Add\nisBox/boxGet/boxSet helpers for the upvalue box convention (pair whose\ncdr is VOID) and replace the 6 open-coded patterns in vm_dispatch.zig.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-04T16:25:13+05:30",
          "tree_id": "cfdaba620dcb370bb2e71e8c1d37bc4521fb4076",
          "url": "https://github.com/kaappi/kaappi/commit/959ee717fcadf54a15cfe44c60e1342d407eee6a"
        },
        "date": 1783164106154,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.087832,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.949804,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.964974,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.322898,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.013985,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.234257,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.480527,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068598,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 13.450713,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.843726,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 11.019304,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.070929,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 9.152368,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.870561,
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
          "id": "f12961fe896ee47ead69fee6d6aa305bddfed16c",
          "message": "Replace hand-rolled JSON parsing with std.json in LSP server (#1066) (#1091)\n\nThe LSP's request-parsing layer used naive substring search to extract\nJSON fields, which could false-match keys appearing inside string values\nor nested objects. Replace all 6 parsing functions (jsonGetStringRaw,\njsonUnescape, jsonGetString, jsonGetInt, jsonGetRawId, jsonGetObject)\nwith Zig 0.16's std.json.parseFromSlice — parse once per message, pass\ntyped ObjectMap to handlers. This also fixes handleDidOpenOrChange to\nproperly navigate contentChanges[0].text through the JSON array instead\nof whole-message substring search, and drops the manual jsonUnescape\nsince std.json decodes escapes during parsing.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-04T16:34:05+05:30",
          "tree_id": "323217bcbeebc8e532de33d82db3a1d6ce21b2e6",
          "url": "https://github.com/kaappi/kaappi/commit/f12961fe896ee47ead69fee6d6aa305bddfed16c"
        },
        "date": 1783164284664,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.431981,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.31165,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.913993,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.277255,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012562,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.210685,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.469945,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.071506,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.433201,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.834925,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.851047,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.957637,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.275388,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.726562,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043702,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "3e646ef1b5b093ff29918fa7ef422cead8f643c7",
          "message": "Reduce gcd-gc-843 iterations to fix flaky macOS CI OOM (#1094) (#1095)\n\n500 iterations caused 234k bignum allocations that intermittently OOM\non macOS CI runners. 50 iterations still trigger 3 GC collections —\nenough to catch the original use-after-free bug from #843.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-04T17:30:57+05:30",
          "tree_id": "3303588383fc1d7c4e9d0f638072ef4035e2fde3",
          "url": "https://github.com/kaappi/kaappi/commit/3e646ef1b5b093ff29918fa7ef422cead8f643c7"
        },
        "date": 1783167717072,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.063845,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.685214,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.95642,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.495464,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.013805,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.234414,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.478951,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068491,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 13.371349,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.822396,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 11.023266,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.064441,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 9.092247,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.816621,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043218,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "5e4921e5865a1ca56f686f5ee6a1c659c421ae9f",
          "message": "Preserve line tables in .sbc bytecode cache (#1096) (#1097)\n\nSource snippets and line numbers silently disappeared from error messages\nwhen a .sbc cache existed because the serialization format omitted\nFunction.source_line and Function.line_table. The cached error path in\nmain.zig also lacked printSourceSnippet and stack trace output.\n\n- Serialize source_line and line_table in .sbc format (bump v6 → v7)\n- Set source_name on deserialized functions from the file path\n- Mirror fresh-compile error diagnostics in the cached path\n- Fix non-portable mktemp in test-source-snippet.sh (macOS compat)\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-04T13:41:32Z",
          "tree_id": "b97e5c201d1651394db6a159657c1610aae04c2b",
          "url": "https://github.com/kaappi/kaappi/commit/5e4921e5865a1ca56f686f5ee6a1c659c421ae9f"
        },
        "date": 1783173755312,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.390766,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.208065,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.944153,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.323942,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012582,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.211133,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.477933,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.071108,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.438294,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.858992,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.867719,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.960328,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.333574,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.736148,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.046777,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "5e875a091d01e1f42e3efb53ce5e6efadc7bd325",
          "message": "Root callWithArgs return values in map, fold, and unfold primitives (#1098)\n\ncallWithArgs pops its temporary VM frame before returning, so the\nreturn value has no GC root — it exists only in a Zig stack local.\nIf the next allocation triggers a collection, the unrooted value is\nswept and its memory reused, corrupting any structure that referenced\nit.\n\nThis manifested as SRFI-115 regexp \"unknown tag 0.0\" errors: map is\nused by %csre to build compiled regexp structures, and the unrooted\nmap callback results became dangling pointers after GC.\n\nRoot the return value in each affected primitive:\n- map: root result before allocPair\n- fold, fold-right, reduce, reduce-right: root acc across iterations\n- pair-fold, pair-fold-right: root acc across iterations\n- unfold-right: root seed and val before allocPair\n- map-in-order: root accumulated results via extra_roots\n- hash-table-fold: root acc across iterations\n- string-unfold, string-unfold-right: root seed across callVM calls\n\nFixes #1093.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-04T14:20:10Z",
          "tree_id": "2b2a58eb6d6b664d5afd3320cbed32e773635509",
          "url": "https://github.com/kaappi/kaappi/commit/5e875a091d01e1f42e3efb53ce5e6efadc7bd325"
        },
        "date": 1783176004459,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.359977,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.547635,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.924402,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.357934,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.014465,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.212329,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.478006,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.071075,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.442167,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.878017,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.926016,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.951975,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.284043,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.67623,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.04201,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "1aa429833924d68ea082139cb0a42ddb49758109",
          "message": "Remove duplicate primitive registrations and add reg() collision guard (#1030) (#1092)\n\nDelete 15 shadowed reg() calls and 8 dead function implementations across\nprimitives_string.zig and primitives_io.zig. The surviving implementations\nin primitives_bytevector.zig and primitives_list.zig are unchanged.\n\nAdd a runtime_safety assert in reg() that panics on duplicate registration,\npreventing this class of silent-overwrite bug from recurring.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-04T20:19:56+05:30",
          "tree_id": "6d0eeb6e7d71f30c4fb00bcb246b92e2b8fc85fc",
          "url": "https://github.com/kaappi/kaappi/commit/1aa429833924d68ea082139cb0a42ddb49758109"
        },
        "date": 1783177863520,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.342966,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.860279,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.898076,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.216855,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012541,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.210912,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.471857,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070396,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.423226,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.851192,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.901434,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.949204,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.282993,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.49552,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045422,
            "unit": "seconds"
          }
        ]
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
          "id": "e2ce74ca455e76771da164f519b2ef3733baeb2e",
          "message": "Improve parallel issue workflow: reuse worktrees and simplify issue format\n\nThe fix-issue script now reuses existing worktrees instead of failing,\nand falls back to checking out an existing branch if creation fails.\nThe parallel-issues skill drops # prefixes from issue numbers for\neasier parsing by downstream scripts.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-04T20:47:13+05:30",
          "tree_id": "b080c0a7c6d76d0cc08d35cdd5851e061088562e",
          "url": "https://github.com/kaappi/kaappi/commit/e2ce74ca455e76771da164f519b2ef3733baeb2e"
        },
        "date": 1783179304035,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.391133,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.538778,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.942058,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.233428,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.013231,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.212007,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.468192,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070948,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.713437,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.856363,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.918333,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.958896,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.332712,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.711304,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.04299,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "4243cde4e572001ee41820495820b3f2a6e4a5fa",
          "message": "Migrate last 3 hand-rolled range parsers to parseOptionalRange (#1056) (#1099)\n\nvector->string, vector-reverse!, and vector-reverse-copy were the last\nsites duplicating optional [start end] parsing instead of using the\nshared helper introduced in #1018. Unifies error message format across\nall range-validated vector procedures.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-04T21:33:12+05:30",
          "tree_id": "aef9e2b1c06781b6ff45611061daa58fb345ad8b",
          "url": "https://github.com/kaappi/kaappi/commit/4243cde4e572001ee41820495820b3f2a6e4a5fa"
        },
        "date": 1783183749381,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.260923,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.178902,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.916117,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.216796,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012438,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.211007,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.467862,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070733,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.484856,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.84039,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.913711,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.956847,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.265127,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.711146,
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
          "id": "a68d5f50213c94c5350f59318cf8acfcf0faeefe",
          "message": "Single-source the version string from build.zig.zon via build_options (#1060) (#1100)\n\nThe version was duplicated in three release-bumped files (main.zig,\nthottam.zig, build.zig.zon) plus a hardcoded literal in the LSP\ninitialize JSON. Pipe build.zig.zon's .version through build_options\nso main.zig and thottam.zig derive it at build time. Deduplicate the\nLSP version literal via comptime concatenation. Update the release\nskill to bump only build.zig.zon.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-04T21:33:33+05:30",
          "tree_id": "88a3fe8c8e46a868c9971d38a6aa559f9062bf6b",
          "url": "https://github.com/kaappi/kaappi/commit/a68d5f50213c94c5350f59318cf8acfcf0faeefe"
        },
        "date": 1783183975382,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.277181,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.208361,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.90984,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.218997,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012521,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.210664,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.468021,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070491,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.504416,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.815836,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.893287,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.956163,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.256294,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.694783,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043619,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
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
      }
    ]
  }
}