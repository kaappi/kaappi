window.BENCHMARK_DATA = {
  "lastUpdate": 1783184114999,
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
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "a96df06b28bff7c41beab9ff2d98f6086f57084a",
          "message": "Fix >255 vector args overflowing fixed arg buffers (#802) (#991)\n\nNine vector primitives used fixed [256]Value or [257]Value stack buffers\nthat overflowed when called with >255 vector arguments via apply,\ncausing a ReleaseSafe bounds-check panic (or silent stack corruption in\nReleaseFast). Replace each with a stack-fast/heap-fallback pattern:\nuse the stack buffer for the common case (<=256 args), heap-allocate\nvia gc.allocator when the count exceeds it.\n\nAffected: vector-map, vector-for-each, vector-count, vector-any,\nvector-every, vector-index, vector-index-right, vector-unfold,\nvector-unfold-right.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-04T00:56:40+05:30",
          "tree_id": "c41ebc1df7fe154888682ae12f2d4ea2e3d11841",
          "url": "https://github.com/kaappi/kaappi/commit/a96df06b28bff7c41beab9ff2d98f6086f57084a"
        },
        "date": 1783107711522,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.362081,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.179497,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.836222,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.311199,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006383,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.033232,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.48717,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.071002,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.057323,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.818846,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.191159,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.431398,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.793752,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.672232,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042121,
            "unit": "seconds"
          }
        ]
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
          "id": "d9afdf919c2ab5824a917c110ad746a091af6392",
          "message": "Add parallel issue triage skill and fix-issue launcher script\n\nThe skill groups open GitHub issues into conflict-free parallel sets\nfor concurrent Claude Code sessions. The script creates a worktree\nper issue and launches Claude to fix it.\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-04T00:59:37+05:30",
          "tree_id": "99a88d60719b4721535fca8b27d9b4932494e1fe",
          "url": "https://github.com/kaappi/kaappi/commit/d9afdf919c2ab5824a917c110ad746a091af6392"
        },
        "date": 1783107910749,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.374998,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.637648,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.875355,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.380367,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006436,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.034181,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.491615,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.071496,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.068769,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.886812,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.177629,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.436043,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.798451,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.718413,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043174,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "19b31e0e5af0d8660fb54f627881d81eb4e52eb9",
          "message": "Include compiler version in .sbc cache validity check (#925) (#993)\n\nThe bytecode cache was keyed on source hash only, so a .sbc produced by\na buggy compiler kept replaying the bug even after rebuilding with a fix.\nAdd a compiler hash (derived from the version string) to the .sbc header\nand reject caches written by a different compiler version. Bump the\non-disk format VERSION from 5 to 6 so all pre-existing caches are also\ninvalidated.\n\nCloses #925\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-03T20:00:29Z",
          "tree_id": "06a0a93aa7594092e3d19844862bc5c2a01e3c81",
          "url": "https://github.com/kaappi/kaappi/commit/19b31e0e5af0d8660fb54f627881d81eb4e52eb9"
        },
        "date": 1783109859481,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.34568,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.609126,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.971873,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.432484,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00643,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.037883,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.508305,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.074893,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.136005,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 2.026441,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.226796,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.431326,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.815923,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.697888,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.04285,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "34952ddb5c2c2a0edeb4ea4f2fc4017ddc9fd3a2",
          "message": "Call sched_yield in thread-yield! when no cooperative scheduler exists (#948) (#994)\n\nthread-yield! was a silent no-op in schedulerless VMs (child OS threads),\ncausing busy-spin at 100% CPU. Now calls std.Thread.yield() (sched_yield)\nto hand the CPU to the OS scheduler per SRFI-18 semantics.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-03T20:03:28Z",
          "tree_id": "66b4509618b1996f8501cc2ac1f7840967663102",
          "url": "https://github.com/kaappi/kaappi/commit/34952ddb5c2c2a0edeb4ea4f2fc4017ddc9fd3a2"
        },
        "date": 1783110156293,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.033722,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.591154,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.863297,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 6.242664,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006809,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.033708,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.487477,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068808,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.976129,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.855388,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.188983,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.475699,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.690942,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.791406,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044527,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "7f426c63e8a56c7765d5fdec77d60bfcdc2af99c",
          "message": "Skip .sbc bytecode cache in sandbox mode (#785) (#995)\n\n--sandbox promises no filesystem side effects, but runFile\nunconditionally wrote (and read) .sbc cache files. Gate the cache\npath on vm.sandbox_mode so sandboxed runs neither load nor create\nbytecode cache files on disk.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-03T20:08:39Z",
          "tree_id": "d50a9a69d2ce43949c84e404f42e3cd23029df1a",
          "url": "https://github.com/kaappi/kaappi/commit/7f426c63e8a56c7765d5fdec77d60bfcdc2af99c"
        },
        "date": 1783110250113,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.424794,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.252022,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.885283,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.340292,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006598,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.033991,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.495121,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.07198,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.128189,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.904936,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.187441,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.441043,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.799112,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.770158,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044513,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "1cd5d84bb55442e63b447342fa737ce2cfc690dc",
          "message": "Accept full unsigned 64-bit range for uint64/size_t FFI arguments (#794) (#992)\n\nThe argument-direction marshaling forced uint64 and size_t parameters\nthrough the signed i64 path (toCheckedInt → toIntArgOpt), rejecting\nany value ≥ 2^63.  The return direction already handled the full\nunsigned range via marshalLongOrUlong; this adds the symmetric path\nfor arguments via toLongArg/toUnsignedArgOpt and fixes checkNarrowIntRange\nto validate unsigned types through the unsigned conversion.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-03T20:09:51Z",
          "tree_id": "e78eaac850d926a250e163796662b52d81136ed6",
          "url": "https://github.com/kaappi/kaappi/commit/1cd5d84bb55442e63b447342fa737ce2cfc690dc"
        },
        "date": 1783110693636,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.128215,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.93514,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.689633,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.255103,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.005319,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.026384,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.37974,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.054329,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.403329,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.460348,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 0.917382,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.370792,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.316103,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.284763,
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
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "27e6d1551fef63ed5cb5262ef86e592762c84af0",
          "message": "Parse #e decimal strings exactly without f64 round-trip (#856) (#996)\n\nstring->number with the #e prefix was converting the decimal string to\nf64 first, then trying to recover an exact rational. This failed for\nsmall-scale decimals (e.g. #e1e-20 → 0) and values beyond f64 range\n(e.g. #e1e400 → #f).\n\nNew parseExactDecimal function parses the string directly into mantissa\ndigits and exponent, then constructs the exact result using bignum\narithmetic — no f64 intermediate. Also simplifies the applyExactness\nfallback to delegate to exactFn's IEEE 754 bit decomposition.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-03T20:28:09Z",
          "tree_id": "c1208ae97ee614fd571d1516a101c544f49e4899",
          "url": "https://github.com/kaappi/kaappi/commit/27e6d1551fef63ed5cb5262ef86e592762c84af0"
        },
        "date": 1783111719620,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.904267,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.81326,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.929771,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.567834,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006853,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.033775,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.54721,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069308,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.001332,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.891353,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.191621,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.469471,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.694997,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.822634,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043866,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "f0458df788c702d6aa9b5c92680a478b6690c805",
          "message": "Fix read after peek-char reordering stream bytes (#804) (#997)\n\nreadDatumFn assembled its parse buffer as read_buf ++ peek_byte, but\npeek_byte holds a byte taken from the front of read_buf — so it must\ncome first. Reorder to peek_byte → peek_extra → read_buf → fd,\nmatching readOneByte's drain order.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-03T20:33:46Z",
          "tree_id": "2c8fd2f4cfa1c45f68e1abbbdcdd8a7cdb325b9c",
          "url": "https://github.com/kaappi/kaappi/commit/f0458df788c702d6aa9b5c92680a478b6690c805"
        },
        "date": 1783111885572,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.120718,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.016412,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.682846,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.203885,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.005225,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.026377,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.378509,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.053358,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.42506,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.468756,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 0.931204,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.366332,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.314747,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.424364,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.035226,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "3ff20e1e46addb009663788cb96319a32be1a8ee",
          "message": "Handle bignums in types.toF64 so FFI double/float args marshal correctly (#792) (#998)\n\ntypes.toF64 had no bignum case — any bignum fell through to `return 0.0`,\ncausing bignum-backed rationals passed as FFI double/float arguments to\nsilently marshal as 0.0 (bignum numerator) or +inf.0 (bignum denominator).\n\nAdd bignumToF64 helper (mirrors the existing bignum.toF64 logic) to avoid\na circular import between types.zig and bignum.zig.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-03T20:31:26Z",
          "tree_id": "7416c97ff68e520ef7f623f405777b37307934a3",
          "url": "https://github.com/kaappi/kaappi/commit/3ff20e1e46addb009663788cb96319a32be1a8ee"
        },
        "date": 1783111897496,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.387002,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.514506,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.912794,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.410128,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006405,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.03419,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.512475,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.072877,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.141629,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.939791,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.315864,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.428534,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.806646,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.690291,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043071,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "f7cac2503851faf7e2d5dc32b0864739c26801d2",
          "message": "Handle bignums in types.toF64 to fix FFI double/float marshaling (#793) (#999)\n\ntypes.toF64 had no case for bignums — any bignum fell through to\nreturn 0.0, causing bignum-backed rationals to marshal as 0.0 or\n+inf.0 when passed to C functions expecting double/float arguments.\n\nAdd a bignum check that delegates to bignum.toF64, matching the\npattern already used by primitives.toF64.\n\nCloses #793\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-03T20:50:54Z",
          "tree_id": "f0b5cb969b6fea6e0d7a004afddcdf78d1709e46",
          "url": "https://github.com/kaappi/kaappi/commit/f7cac2503851faf7e2d5dc32b0864739c26801d2"
        },
        "date": 1783112857000,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.390096,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.979266,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.970473,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.448717,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006672,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.033766,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.480233,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.072198,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.09368,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.868217,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.21368,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.444214,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.843022,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.700044,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043034,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "c0dae669c57025d101a12ac946d8a3c4668e11c9",
          "message": "Honour timeout/timeout-val in thread-join! for OS threads (#878) (#1000)\n\nthread-join! ignored timeout and timeout-val arguments for OS-backed\nthreads (blocked unconditionally via std.Thread.join) and returned void\nimmediately for never-started threads. Parse timeout args before the\nOS/fiber branch, poll fiber.status with atomic loads in a 1ms sleep\nloop for the OS-thread and never-started paths, and extract reapOsThread\nto share cleanup between both cases.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-03T21:00:09Z",
          "tree_id": "eca742daff20d7dcf1fd46d88f115268d8cfe743",
          "url": "https://github.com/kaappi/kaappi/commit/c0dae669c57025d101a12ac946d8a3c4668e11c9"
        },
        "date": 1783113428300,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.05658,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.72429,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.925347,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.603052,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006851,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.034564,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.496548,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.06951,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.969804,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.850141,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.180468,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.475972,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.712364,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.839422,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045613,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "6b27b2d7dde014b4899ce081bdd17c8cab625ec6",
          "message": "Fix string-titlecase word boundaries and Unicode case mapping (#824) (#1002)\n\nWord boundaries now trigger on any non-cased character (not just ASCII\nwhitespace), matching SRFI-13 semantics. Case mapping uses the full\nUnicode tables instead of byte-level ASCII ±32.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-03T21:29:19Z",
          "tree_id": "6fcb1ff39c6b3e04b35a4218011935f5a8093217",
          "url": "https://github.com/kaappi/kaappi/commit/6b27b2d7dde014b4899ce081bdd17c8cab625ec6"
        },
        "date": 1783115301624,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.865635,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.518167,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.813215,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.962323,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006733,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032269,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.434908,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.066895,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.131933,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.632835,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.162007,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.403443,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.657597,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.964341,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.040046,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "2cca1cc81439727cf5d2d579b5ffda8de320eecc",
          "message": "Fix peek-char returning raw lead byte for multi-byte UTF-8 on fd ports (#798) (#1001)\n\nWhen peek_byte held a multi-byte UTF-8 lead byte (e.g. after read-line\npushed back the byte following \\r), peekCharFn fell through to returning\nthe raw lead byte as a Latin-1 character instead of decoding the full\nUTF-8 sequence. Add an else branch that temporarily clears peek_byte,\nreads continuation bytes from the fd via readOneByte, restores peek_byte,\nand stashes the continuation bytes in peek_extra for subsequent read-char.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-03T21:29:32Z",
          "tree_id": "9695834586976ed668728dd34bd9b9d5c20912d7",
          "url": "https://github.com/kaappi/kaappi/commit/2cca1cc81439727cf5d2d579b5ffda8de320eecc"
        },
        "date": 1783115355583,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.949674,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.572518,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.815625,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.96942,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006542,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.03228,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.430245,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.06692,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.159785,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.627032,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.140897,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.406365,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.682373,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.028364,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.041096,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "3e65aebfee372f5f7a97b148bf39495c6d4a84cc",
          "message": "Fix Unicode reader gaps and fold-case for non-ASCII identifiers (#920) (#1004)\n\nThe reader's isUnicodeLetter was missing several bicameral scripts\n(Cherokee, Georgian Mtavruli, Coptic, Glagolitic, Deseret, Osage,\nWarang Citi, Adlam), preventing them from being used as bare\nidentifiers. Add these ranges and a fallback to the Unicode case\ntables so any cased letter is recognized.\n\nThe #!fold-case directive used std.ascii.toLower byte-by-byte, so\nnon-ASCII identifiers were never folded. Replace with UTF-8-aware\ndecoding that applies charFoldcase per codepoint.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-03T21:39:18Z",
          "tree_id": "691d219e89913c7c3bc40d7cf05c175d7bf34b67",
          "url": "https://github.com/kaappi/kaappi/commit/3e65aebfee372f5f7a97b148bf39495c6d4a84cc"
        },
        "date": 1783115809464,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 5.959407,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.714738,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.842484,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.299795,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006397,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.033123,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.477538,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070285,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.131335,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.835647,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.216942,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.429313,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.782278,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.6949,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044955,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "31bf5ab2964ad9081eb1462d5225bb537f3ee496",
          "message": "Replace fixed 256-node buffers with growable lists in IR lowering (#791) (#1003)\n\nlowerBegin, lowerList, and lowerCondBody used [256]*Node stack buffers\nthat rejected begin/and/or/when/unless forms with more than 256\nsub-expressions. R7RS places no such limit, and macro-generated code\ncan realistically exceed it. Switch to std.ArrayList with the IR\nallocator (the make* constructors already copy the slice).\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-03T21:33:18Z",
          "tree_id": "c52ebf916668b99453203b155637ba3e82287270",
          "url": "https://github.com/kaappi/kaappi/commit/31bf5ab2964ad9081eb1462d5225bb537f3ee496"
        },
        "date": 1783116103420,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.573637,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.965948,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 1.013047,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.643287,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006919,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.038824,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.534937,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.075989,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.5105,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 2.296179,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.222155,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.42454,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.10293,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.691702,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042884,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "934cf9817728f9a2de88c99772d618de253ffd40",
          "message": "Add width-aware pretty-printing for REPL output (#921) (#1005)\n\nDetect terminal width via ioctl/TIOCGWINSZ and use it for all REPL\noutput paths.  Improve the pretty-printer with exact flat-length\nmeasurement, multi-line vector/bytevector support, and special-form-\naware indentation (body forms like define/lambda/let keep the first\narg on line 1; clause forms like cond/case indent each clause).\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-03T21:51:00Z",
          "tree_id": "49fea02c485418334be3f5a9667fcf50c39614b5",
          "url": "https://github.com/kaappi/kaappi/commit/934cf9817728f9a2de88c99772d618de253ffd40"
        },
        "date": 1783116409759,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.131681,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.26508,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.704326,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.319072,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.0053,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.026622,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.382693,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.054247,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.380989,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.454353,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 0.923924,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.367823,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.316106,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.364706,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.035452,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "72bfacfe3dd05e522af5ad0b792df63745049b08",
          "message": "Check peek_byte before returning EOF in string-port read (#799) (#1006)\n\nThe string-port branch of readDatumFn returned EOF when string_pos\nreached the end of string_data, without checking whether a pushed-back\nbyte was still pending in peek_byte. This caused (read) to miss the\nlast datum after read-line consumed a \\r or after peek-u8/peek-char.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-04T03:39:42+05:30",
          "tree_id": "bf139ca15cd123f380c188886dd02b031d4985da",
          "url": "https://github.com/kaappi/kaappi/commit/72bfacfe3dd05e522af5ad0b792df63745049b08"
        },
        "date": 1783117510606,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.392454,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.310006,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.835488,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.301209,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006355,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.035224,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.470844,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070573,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.141828,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.819161,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.179973,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.429005,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.792622,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.517216,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042836,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "53f8841269e8e8e88afaa7b1cf74a612f5bae3a0",
          "message": "Stop --sandbox pre-scan at filename boundary (#783) (#1007)\n\nThe pre-scan that decides sandboxing before primitive registration was\nscanning all of argv, including script arguments after the filename.\nA script invoked as `kaappi script.scm --sandbox` would silently enter\nsandbox mode, breaking the script.\n\nMake the pre-scan respect the same positional contract as the main flag\nloop: skip argv[0], recognize all interpreter flags (consuming values\nfor flags that take one), and stop at the first unrecognized argument\n(the filename).\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-04T03:39:58+05:30",
          "tree_id": "7a636eaf467646453e91096a3883f47b827a9540",
          "url": "https://github.com/kaappi/kaappi/commit/53f8841269e8e8e88afaa7b1cf74a612f5bae3a0"
        },
        "date": 1783117527258,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.461033,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.559308,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.83719,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.928924,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006478,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.033561,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.4759,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070046,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.142734,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.825221,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.198581,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.438663,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.806302,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.817726,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043847,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "fadb0742d14d4062a4dfa1317cd66e76f1d364b0",
          "message": "Fix SRFI-158 gtake crash, SRFI-189 nothing procedure, SRFI-115 unknown char class (#1008)\n\n* SRFI-158: drive generators with Scheme recursion, not native map\n\ngenerator-fold, generator-for-each, generator-map->list, gmap, and\ngcombine called their generators via (map (lambda (g) (g)) gs). map is\na native primitive, and a coroutine generator captures a continuation\ninside the callback; that continuation cannot resume once the native\nmap frame has returned, so the second invocation crashed with \"type\nerror in 'cdr': expected pair, got #<procedure>\" or silently corrupted\nstate. This broke gtake and (generator->list gen n), which are built\non make-coroutine-generator and generator-fold.\n\nReplace the native-map driving with a %call-generators helper that\nwalks the generator list in plain Scheme, keeping every frame the\ncaptured continuation needs inside the bytecode dispatch session.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n* SRFI-189: make nothing a procedure per spec\n\nnothing was defined as the Nothing record instance itself, so the\nspec-mandated call form (nothing) raised \"not a procedure\". Keep the\nunique instance in a private %the-nothing and export nothing as a\nzero-argument procedure returning it, as SRFI-189 requires.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n* SRFI-115: raise on unknown named char class instead of matching nothing\n\nA bare symbol in an SRE compiled to a class node without validation,\nand the match interpreter's fallback returned #f for names it did not\nrecognize. A typo like digit (for numeric) therefore made every search\nsilently return #f. Validate class names against the set the matcher\nunderstands at compile time, so (regexp-search '(+ digit) \"age: 25\")\nraises \"regexp: unknown character class\" and valid-sre? returns #f.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-04T03:42:35+05:30",
          "tree_id": "de3a3b831920b3863065ce30b172980065f754b3",
          "url": "https://github.com/kaappi/kaappi/commit/fadb0742d14d4062a4dfa1317cd66e76f1d364b0"
        },
        "date": 1783117683428,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.433649,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.719612,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.847611,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.542912,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00676,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.033579,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.475832,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069929,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.143613,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.828803,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.149814,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.434933,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.793539,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.744005,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043457,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "69cb2d25e68ec532432e6e0329e88f36b699e161",
          "message": "Raise on continuation resume across a returned native call (#1009)\n\nA continuation captured inside the closure that a native driver (map,\nfor-each, sort, apply, ...) runs via callWithArgs snapshots the frame\nthat callWithArgs pushed. That frame's result is delivered by its own\nrunUntil session's return value, so its dst register is a placeholder.\n\nWhen such a continuation is resumed after the native call has already\nreturned (e.g. a coroutine generator driven a second time by map), the\nrestored frame eventually returns while frame_count is still above the\ncurrent dispatch loop's target. The old code wrote the result into the\ncaller's dst register — but that register belongs to the now-dead native\nframe, and the native's iteration state is gone. The result landed in the\nwrong place and produced silent garbage (e.g. `#<builtin map>`).\n\nMark callWithArgs-pushed frames with returns_to_native (preserved across\ntail calls and continuation capture/restore, like seq). At every result-\ndelivery site in the dispatch loop, if a returns_to_native frame returns\ninto an outer loop, raise a clear, catchable error instead of corrupting\nregisters.\n\nRegression tests: a Zig unit test in tests_continuations.zig asserts the\nerror is raised; error-format.sh asserts the diagnostic message text.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-03T22:39:43Z",
          "tree_id": "feaa4c22625c7060e34418b628c82b9b67b5e8d8",
          "url": "https://github.com/kaappi/kaappi/commit/69cb2d25e68ec532432e6e0329e88f36b699e161"
        },
        "date": 1783119403491,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.439886,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.365373,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.834429,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.348382,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006371,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.033647,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.471236,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.071062,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.163956,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.820339,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.377714,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.425168,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.790594,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.661198,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.041873,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "b5fe57a8a25014229e4d749cdae25850200d930b",
          "message": "Fix alist->hash-table arity, root top-level forms, add book-bug regression tests (#1011)\n\n* Accept SRFI-69 optional equality/hash args in alist->hash-table\n\nSRFI-69 specifies (alist->hash-table alist [equal-proc [hash-proc\nargs...]]), but the primitive was registered with exact arity 1, so the\nspec-conforming call (alist->hash-table lst equal?) failed with an arity\nerror. Kaappi hash tables always compare with equal? internally and\nmake-hash-table already accepts-and-ignores the optional comparator\narguments; alist->hash-table now does the same.\n\nFound verifying the kaappi-book chapter 16 listings against the\ninterpreter.\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>\n\n* Root top-level forms during evaluation; add book-bug regression tests\n\nRooting: the file runner, stdin runner, bundle preamble, REPL input\nloop, and eval() all evaluated freshly read datums without a GC root.\nEvaluating a form can allocate heavily (an import that loads a whole\n.sld library), and a collection landing mid-walk could reclaim the\nform's own AST. Recent GC work on main fixed the reported mid-session\nimport failures, but these call sites still relied on collection\ntiming; root the datum for the duration of each form's evaluation,\nmatching the pattern the script runner and loadLibrarySource already\nuse.\n\nRegression tests for interpreter bugs found by verifying every REPL\nlisting in the kaappi-book (fixes already on main, previously\nuntested):\n\n- errors/error-format.sh: uncaught exceptions must print their message\n  and irritants (\"error: something went wrong 42\"), not the bare\n  \"runtime error: error.ExceptionRaised\" fallback; covers error\n  objects, non-error raises, and script mode.\n- continuations/coroutine-repl-echo.scm: continuations captured with\n  call/cc must survive the top-level value echo. On v0.11.0 the echo\n  path invalidated the saved continuation, so the second re-entry\n  failed with \"not a procedure\"; the forms are deliberately left bare\n  (not display-wrapped) because consuming the value hid the bug.\n  Covers top-level-global and closure-factory coroutine shapes.\n- smoke/fiber-pipeline.scm: add the book's generic variadic pipeline\n  builder, where every stage's fiber closes over one recursive loop's\n  locals; with two or more stages this used to make channel-receive\n  return garbage (#978 fixed the scheduler; the existing tests only\n  covered the add-stage helper shape).\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-03T23:10:46Z",
          "tree_id": "c32c5b84b9fc0227db83883fcd5a8ad8a9d413c0",
          "url": "https://github.com/kaappi/kaappi/commit/b5fe57a8a25014229e4d749cdae25850200d930b"
        },
        "date": 1783121288786,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.396271,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.471583,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.875118,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.436974,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006882,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.034787,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.481032,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.071849,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.204279,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.871778,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.273052,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.437858,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.838755,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.571176,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042481,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "63a93faa63aa147b43e931d3f3409b1cb2a5a931",
          "message": "Fix GC corruption during library include-load (#1010) (#1012)\n\nImporting (srfi 158) after (srfi 115) failed with a CompileError masked\nas \"library not found\": a collection landing mid-compile corrupted the\ndesugared form of gdelete-neighbor-dups. Two holes conspired:\n\n- compileNamedLet built its formals list and renamed body from fresh\n  unrooted pairs across makeUniqueLoopName/renameInBody (which allocate\n  enough to collect on large bodies), and never rooted the desugared\n  lambda args across the nested compileLambda.\n- handleTopLevelForm never rooted the (import ...) datum itself, so a\n  collection during the library load could sweep the form while\n  handleImportInto was still walking it.\n\nHarden the same fresh-unrooted-desugar pattern elsewhere in the\ncompiler: compileBody/compileLetBody def_inits stack arrays (mirrored\ninto extra_roots), compileDefineValues, compileLetValues, and the\nquasiquote vector branch. Fix no_collect increments leaking on error\npaths in compileCaseLambda, compileGuard, compileParameterize, and\ncompileQQSplicing, which would have disabled collection for the rest of\nthe process after a malformed form.\n\nAlso stop masking load failures: when an .sld file is found and read\nbut fails to load, report the failing definition and file instead of\n\"library not found\".\n\nThis also fixes the nondeterministic CompileError when importing\n(srfi 64) and (srfi 158) together.\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-04T06:20:39+05:30",
          "tree_id": "e0cf60026aa645dfb4af4855a9a23994500be977",
          "url": "https://github.com/kaappi/kaappi/commit/63a93faa63aa147b43e931d3f3409b1cb2a5a931"
        },
        "date": 1783127151613,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.846035,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.667793,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.778081,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.800633,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006682,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032193,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.422852,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.066136,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.278378,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.58624,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.181216,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.405607,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.632572,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.052684,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.039096,
            "unit": "seconds"
          }
        ]
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
          "id": "3c8411eb6070fbc57fb03f2c20953a47c863d877",
          "message": "Release v0.12.0",
          "timestamp": "2026-07-04T06:33:44+05:30",
          "tree_id": "cf9e93a738f93e142c255805726c4231c1fd1523",
          "url": "https://github.com/kaappi/kaappi/commit/3c8411eb6070fbc57fb03f2c20953a47c863d877"
        },
        "date": 1783128022813,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.851396,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.607408,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.780101,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.812655,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006524,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032342,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.42298,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.066072,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.218939,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.590562,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.18061,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.402892,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.629632,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.031845,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.03969,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "6ac5687106a98518c1733f402566aa5c0ce4cab3",
          "message": "Panic instead of silently dropping reachable objects on GC mark OOM (#1014)\n\nThe mark-phase worklist (added in #864 to avoid native stack overflow)\nused `catch {}` on all 41 append calls. If any append OOMed, reachable\nobjects would silently not be marked and then incorrectly freed — a\nlatent use-after-free.\n\nPre-allocate 1024 worklist slots before the mark loop to cover the\ncommon case without allocation in the hot path. Convert all `catch {}`\nto `catch @panic(...)` so that if the worklist ever does need to grow\nbeyond pre-allocated capacity and that allocation fails, we get a hard\ncrash instead of silent heap corruption.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-04T01:52:51Z",
          "tree_id": "db872dca745843f490d06561d67bbdd6c46cde1c",
          "url": "https://github.com/kaappi/kaappi/commit/6ac5687106a98518c1733f402566aa5c0ce4cab3"
        },
        "date": 1783131195987,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.43494,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.149859,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.935543,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.443036,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012702,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.211227,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.479664,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069985,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.529815,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.853543,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.999124,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.964053,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.372293,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.703049,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042478,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "d8a5659cafa51f64ce5142e0a292cc1e7ed5d9a7",
          "message": "Fix current-input-port corruption under extreme GC pressure (#1013) (#1015)\n\nRoot each standard port in extra_roots immediately after allocation\ninstead of batching all three roots after all three allocations. With\ngc-threshold=1, allocPort for stdout triggered collection before stdin\nwas rooted, freeing it and corrupting the current-input-port parameter.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-04T02:22:46Z",
          "tree_id": "f7e1e7c5a99359429c72d5234a544738f66ebff6",
          "url": "https://github.com/kaappi/kaappi/commit/d8a5659cafa51f64ce5142e0a292cc1e7ed5d9a7"
        },
        "date": 1783132918118,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.293413,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.67037,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.908306,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.249288,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012457,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.210856,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.472778,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.07078,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 12.43276,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.810106,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.958726,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.958975,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 8.242573,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.69519,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042686,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "9465456181f99829b242509148a257d33ffbee31",
          "message": "Propagate OutOfMemory from compiler hash map and list insertions (#1017)\n\ncatch {} on macros.put, globals.put, locals.append, and similar calls\nsilently swallowed OutOfMemory, causing macros or globals to fail to\nregister. This led to confusing \"undefined variable\" errors downstream\ninstead of a clear OOM signal.\n\nChange 13 catch {} to try across compiler.zig, compiler_bindings.zig,\nand compiler_lambda.zig. Change 3 void helpers (endBodyMacroScope,\ninjectHygCapturedWalk, CaptureScan.walk) to return errors so their\ncallers can propagate. The 3 remaining catch {} are in defer/errdefer\nblocks where error propagation is impossible.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-04T02:41:45Z",
          "tree_id": "da217c175d039bc6035baa73b53d3d03b135a44b",
          "url": "https://github.com/kaappi/kaappi/commit/9465456181f99829b242509148a257d33ffbee31"
        },
        "date": 1783133997050,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.846374,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.836603,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.90554,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.033028,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.012222,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.198489,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.452584,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.067663,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 11.919421,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.734685,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 9.272154,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.892065,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 7.658737,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.943264,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.038891,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "e19779a861c52b0f7f968db2aef351d83e619c33",
          "message": "Fix VMError-to-PrimitiveError catch-all that collapsed errors into TypeError (#1016)\n\nThe `else => PrimitiveError.TypeError` catch-all in 36 sites across 10\nprimitives files was destroying diagnostic information — a StackOverflow\nor InvalidBytecode from user callbacks would be reported as a type error.\n\nAdd 7 missing PrimitiveError variants (StackOverflow, UndefinedVariable,\nNotAProcedure, InvalidBytecode, CompileError, ExecutionTimeout, Terminated)\nto make PrimitiveError a superset of VMError. Add an exhaustive mapVMError\nhelper for the VMError→PrimitiveError direction, and update the reverse\nPrimitiveError→VMError switches in vm_dispatch.zig and vm_calls.zig.\n\nCo-authored-by: Claude Opus 4.6 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-07-04T02:41:26Z",
          "tree_id": "4e05b855cc7d75e8ad36472369539bbfc44dc5a7",
          "url": "https://github.com/kaappi/kaappi/commit/e19779a861c52b0f7f968db2aef351d83e619c33"
        },
        "date": 1783134037033,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.046063,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 10.183237,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.959347,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.346205,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.013738,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.233872,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.476738,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.067977,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 13.411586,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.832912,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 11.02944,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 1.068445,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 9.099362,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.86233,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044621,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
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
      }
    ]
  }
}