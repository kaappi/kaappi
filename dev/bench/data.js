window.BENCHMARK_DATA = {
  "lastUpdate": 1784455399752,
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
          "id": "e98846412302163dfcbc54a381281301b31d5eb2",
          "message": "Address PR #1485 review nits: stale comment, timed_out hoist, peer-death doc (#1486)\n\nThree non-blocking items carried over from the KEP-0002 P3 (#1468) review\nthat landed as PR #1485:\n\n- promoteChannel's migration-loop comment claimed registerRecvWaiter ran\n  \"above\" the loop; it actually runs once, after it. Corrected, and noted\n  the OOM-mid-loop corner this creates (stale-but-self-healing enrollments\n  vs. unreached fibers left with no wake path) rather than un-enrolling on\n  that error path.\n- channelReceiveShared reset me.timed_out after the SharedChannelPoll local-\n  sibling drive instead of before it. runSchedulerStep's generic loop bails\n  whenever timed_out is true regardless of Ctx, so a stale flag from an\n  unrelated earlier timed wait could silently skip the drive and let the\n  park decision run with the world still active. Hoisted the reset above\n  the drive.\n- Documented the KEP-0002 §5 accepted liveness gap on sharedWakeupPossible:\n  a receiver parked after this returned true hangs forever if the peer\n  exits without sending, since a stub release rings nothing and the parked\n  fiber's own registry entry keeps the deadlock detector disarmed. Go-style\n  hang, accepted by design; §6's planned per-call timeout is the escape\n  hatch.\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-13T13:15:41+05:30",
          "tree_id": "77b2cc46d1280c43a24d1a708748628b39f68a8c",
          "url": "https://github.com/kaappi/kaappi/commit/e98846412302163dfcbc54a381281301b31d5eb2"
        },
        "date": 1783930416490,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.37971,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.430871,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.672718,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.317269,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006411,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.043726,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.380355,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.05563,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.955922,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.474842,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.287663,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.414862,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.426963,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.101245,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.038916,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "d54c45c2b9d864ff6b033e34b19f87fdbffa168b",
          "message": "KEP-0004 Phase 0/1: unify cond-expand library checks, add subsystem features (#1488)\n\n* KEP-0004 Phase 0/1: unify cond-expand library checks, add subsystem features\n\nPhase 0 (cleanup): evalFeatureReq's hardcoded known_libs array in\ncompiler_conditionals.zig never listed any kaappi.* library or srfi.18,\nbut callers never noticed because it silently fell through to the\nglobals.libraryExists callback, which already checked the live registry\ncorrectly. Deleted the redundant array outright and extracted the\nduplicated \"does this library exist\" check (previously hand-written\nseparately in vm.zig's checkLibraryExists and vm_library.zig's\nevalLibFeatureReq) into one shared vm_library.libraryIsAvailable(),\ncalled from both entry points.\n\nPhase 1: added kaappi-fibers, kaappi-reactor (all targets, including\nwasm32-wasi per KEP-0001 Phase 4), and kaappi-threads (omitted on wasm,\nmatching Lib.wasmAvailable()'s existing srfi_18 => false gate) as bare\ncond-expand feature identifiers, so portable library code has a short\nway to detect these subsystems instead of spelling out (library ...)\nrequirements.\n\nVerified: 839/839 Zig unit tests, 1395/1395 R7RS suite, 440/440 Scheme\ntest files, plus manual end-to-end checks against a built binary for\nboth the new identifiers and the known_libs-removal regression risk.\n\nSee keps/keps/0004-discoverable-deviations.md.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* Address review: honor sandbox mode in libraryIsAvailable\n\nCodeRabbit flagged, and I independently confirmed against a built\nbinary, that libraryIsAvailable fell through to a disk probe\n(libraryFileExists) even under --sandbox, while tryLoadLibraryFromFile\nrejects every file-backed load there (vm_library.zig:428). Result:\n(cond-expand ((library (srfi 41)) ...)) reported the library available\nwhile the matching (import (srfi 41)) then failed — a behavioral\nmismatch, and a way for sandboxed code to probe host filesystem state\nthrough cond-expand.\n\nPre-existing in both call sites this PR unified (checkLibraryExists and\nevalLibFeatureReq had the identical get()-then-libraryFileExists()\nsequence on main already) — not a regression introduced here, but this\nPR's consolidation is the natural single place to close it.\n\nAlso extends features-consistency.scm (#1177) with the three KEP-0004\nPhase 1 identifiers for Scheme-level parity with the new Zig tests, per\nthe review's optional suggestion.\n\nLeft two other review comments as-is per triage: the new tests'\nGC/VM setup duplication matches the existing style in this file (no\nth.expectEval* helper covers symbol-result assertions), and the wasm\nbranch of platform_features isn't unit-testable from a native test\nbinary (already noted inline in types.zig).\n\nVerified: 840/840 Zig unit tests, 1395/1395 R7RS suite, 440/440 Scheme\ntest files. Manually reproduced the sandbox mismatch against a built\nbinary before the fix and confirmed it's closed after.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-13T08:02:16Z",
          "tree_id": "1270eadf2910b2a65b9a777a102d838144645190",
          "url": "https://github.com/kaappi/kaappi/commit/d54c45c2b9d864ff6b033e34b19f87fdbffa168b"
        },
        "date": 1783931403516,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.39606,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.845261,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.963455,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.545601,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006437,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.056393,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.520186,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070448,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.462565,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 2.009258,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.656881,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.434867,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.866668,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.748023,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043986,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "413c1b823ef993eac2c90c6d1080db8be4e83c3c",
          "message": "docs: refresh LLVM backend Lambda Strategy for the tiered emitter (#1501)\n\nThe \"Lambda Strategy\" section and the node-output table described lambdas as\nalways serialized to source and evaluated via kaappi_eval at runtime. That has\nbeen stale since the native closure tier landed: named/top-level and\nclosed/capturing lambdas now compile to real LLVM functions.\n\nRewrite the section to match src/llvm_emit_lambda.zig's three tiers (capturing\nclosure, closed/named native function, eval fallback), and document what is\ncompiled natively (fixed arity, variadic rest params, by-value closures,\nself-tail-call loops) and the precise eval-fallback triggers. Also de-stale the\nadjacent table rows for call/define/set!/let so let/let* are no longer lumped\nwith the genuinely eval-only forms.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-13T15:42:16+05:30",
          "tree_id": "76806f3d39d55b919ca714d5be9dd1c969a5f415",
          "url": "https://github.com/kaappi/kaappi/commit/413c1b823ef993eac2c90c6d1080db8be4e83c3c"
        },
        "date": 1783939012288,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.057551,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.8119,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.924796,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.451033,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007267,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.052844,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.513238,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069509,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.178395,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.987491,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.514285,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.47496,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.747629,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.882975,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045575,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "ce6656c7ecef5201dd009d04e454c4ef4b889732",
          "message": "KEP-0002 Phase 4: capacity, timeouts, close for cross-thread channels (#1502)\n\n* Capacity, timeouts, close: bounded channels, drain-then-EOF (KEP-0002 P4)\n\nImplements the amended §6 close semantics from KEP-0002 (kaappi/keps#12):\nEOF outwaits reservations and the failure path rings receivers on a\nclosed channel. Adds make-channel's optional capacity argument,\n[timeout [timeout-val]] on channel-send/channel-receive (SRFI-18\nshape), and channel-close!/channel-closed?, for both the local\n(unpromoted) and shared (cross-thread) channel representations.\n\nThe §4-6 protocol was already model-checked in Phase 1-3 (re-verified\nagainst the KEP's exact pseudocode with the TLA+ suite before writing\nany code); this phase wires it up end to end and adds the local-channel\nequivalent.\n\nFixes #1469\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* Fix shared-channel timeout swallowed by a spurious wake-all retry\n\nchannelSendShared/channelReceiveShared's main-fiber (and redispatched\ndispatched-fiber) loop can re-enter its local-sibling poll drive with\n`me.status == .running` while a previously-armed reactor timer is\nstill live: sweepSharedWaiters (the wake-all discipline §5 requires)\nflips a .waiting fiber to .suspended on *any* notify, with no per-\nwaiter targeting, and never cancels its timer. If that timer then\npops while the poll drive is running, wakeReadyFiber silently drops\nit (it only sets timed_out for a .waiting/.io_waiting fiber) --\npermanently losing the timeout for the rest of the wait.\n\nFix: detach the timer from the reactor's heap (not `me.deadline_ns`,\nwhich stays the single record of the original absolute deadline)\nbefore every poll-drive iteration, and re-arm from that preserved\nvalue at the next park step. Clearing the field too, as an earlier\nversion of this fix did, would make every re-arm fall through to a\nfreshly re-parsed relative timeout and silently extend it on each\nspurious wake instead.\n\nAlso tightens a Phase 4 regression test's leak-check discipline to\nmatch its neighbors (explicit baselines, non-deferred reactor\nteardown before the assertions).\n\nFound in PR #1502 review.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-13T21:02:55+05:30",
          "tree_id": "d57a1211c98c1abbdd10e233e41c4774e3b04dea",
          "url": "https://github.com/kaappi/kaappi/commit/ce6656c7ecef5201dd009d04e454c4ef4b889732"
        },
        "date": 1783958617139,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.354451,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.802242,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.90259,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.557304,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006474,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.053304,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.507013,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069939,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.388379,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.977181,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.567285,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.427448,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.842838,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.712226,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043644,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "c8f8549f5e5dee13fc37ba96eb5c5a858f814a27",
          "message": "docs: add Machine legibility section and correct GC description in vision.md (#1519)\n\n* docs: add Machine legibility section to vision.md\n\nRecords the machine-legibility strategic direction — making Kaappi the most\nlegible Scheme for humans and AI agents to understand, diagnose, and\nautomate — in the canonical vision doc, framed as the third core value\n(Transparency over magic) turned outward: from a runtime transparent to\ncontributors to a toolchain transparent to the programs that drive it.\n\nCaptures the falsifiable operational test (an agent goes from failing\nprogram to verified fix using only documented CLI output), the three pillars\n(Diagnose / Understand / Automate), and the non-goals that keep this as\nextension where R7RS-small is silent rather than deviation where it speaks —\nnotably the declined static type system. Cross-references KEP-0005 (the\ndiagnostic contract) and the tracking epic kaappi#1503.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n* docs: correct the GC description in vision.md to match the implementation\n\nThe \"Simplicity over abstraction\" value and the GC design-decision section\nstill described a pre-generational collector — \"no generational promotion, no\nwrite barriers,\" and a heading arguing against generational GC. The collector\nhas since become generational (young/old split, minor vs. full collections,\nold→young write barrier feeding a remembered set, promotion after surviving\nrepeated collections; see memory.zig, gc_collect.zig, and the Object header in\ntypes.zig).\n\nRewrite both passages to describe that accurately while keeping the doc's\nframing: the collector is still comprehensible, and the write barrier is\npresented as deliberate, earned machinery rather than something avoided. The\nstill-true points (no copying, no compaction, fragmentation not a problem in\npractice) are retained.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-13T22:06:04+05:30",
          "tree_id": "560ecf3603a8871bb0b258a5d461d3c89bc5700c",
          "url": "https://github.com/kaappi/kaappi/commit/c8f8549f5e5dee13fc37ba96eb5c5a858f814a27"
        },
        "date": 1783961919218,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.429727,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.011852,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.929102,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.508571,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006437,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.053769,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.506232,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070178,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.385618,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.980549,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.583547,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.432434,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.842238,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.714618,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044626,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "c008bac7b9a304f00e78997742700221d57b46f6",
          "message": "KEP-0002 Phase 5: (kaappi parallel) pools, parallel-map, processor-count (#1522)\n\nPure Scheme worker pools (make-pool/pool-submit/task-wait/pool-shutdown!)\nand parallel-map/parallel-for-each over (srfi 18) + (kaappi fibers),\ndegrading to fiber workers under --sandbox and on WASM where real threads\nare unavailable. processor-count is the one new native primitive.\n\nThe library is embedded into the binary (build.zig + vm_library.zig) so\nit stays importable under --sandbox, which otherwise blocks every\nfile-backed library load outright -- a plain portable .sld would be\nunimportable there at all, not just degraded.\n\nFound and filed two pre-existing runtime gaps while building this:\n- #1520: a closure that crosses thread-start! and then calls a\n  separately-defined library procedure hangs. Worked around throughout\n  by inlining (matches the KEP's own reference pseudocode).\n- Confirmed #1489 (lost cross-thread wakeup) is reachable through\n  ordinary parallel-map usage past a few hundred concurrent submissions,\n  not just synthetic repros. Documented; parallel-primes (kaappi-examples)\n  demonstrates the chunked-pool workaround.",
          "timestamp": "2026-07-14T01:10:06+05:30",
          "tree_id": "4089689a5344781b83f290e1fc917840ab5fe669",
          "url": "https://github.com/kaappi/kaappi/commit/c008bac7b9a304f00e78997742700221d57b46f6"
        },
        "date": 1783973346604,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.236898,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.989179,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.648194,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.219391,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00646,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.042433,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.357723,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.05387,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.862656,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.459348,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.285076,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.416622,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.39543,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.854535,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.038173,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "1da7cf32ba3b235d896a6abe9e997b4b4b73e834",
          "message": "Fix dirty-snapshot dispatch hazard in mutex-lock!/condition-variable-wait (#1521)\n\n* Fix dirty-snapshot dispatch hazard in mutex-lock!/condition-variable-wait (#1487)\n\nmutex-lock!, condition-variable-wait (mutex-unlock! with a condvar),\nthread-join!'s fiber path, and timed local channel-send/receive all set a\nfiber .waiting and then call runSchedulerStep recursively from the same\nnative frame -- the identical shape already fixed for shared channels in\nPR #1485. If something wakes that fiber (flips it .suspended) while its\nown nested drive is still live deeper on the Zig call stack, a different\nfiber's own nested schedule() call can dispatch it from a stale, mid-\nnative-call register snapshot, resuming bytecode past the in-flight\nprimitive call with the destination register never written. Confirmed via\na 3-fiber nested mutex-contention repro (git-stash A/B).\n\nRather than rewriting each call site to use PR #1485's yield_retry\ndiscipline, this lands the issue's alternative suggestion: a generic\n`driving` guard on Fiber, set for the whole extent of any\nrunSchedulerStep call and excluded from dispatch-selection regardless of\nstatus. A per-site rewrite would have silently broken cross-OS-thread\nmutex/condvar polling (which depends on the specific waiting loop's own\nperiodic recheck) and reintroduced the exact lost-wakeup race the condvar\ngeneration-snapshot-before-unlock ordering exists to prevent. The generic\nguard sidesteps both and, as a bonus, also closes the identical hazard in\nthread-join! and timed local channel-send/receive, which weren't named in\nthe issue but turn out to have the same bug.\n\nFirst attempt at the guard baked the exclusion into schedule() itself,\nwhich broke yieldFn/threadYieldFn's \"is yielding worthwhile\" advisory\ncheck -- a busy sibling's (yield) calls stopped seeing a driving ancestor\nwhose wait had just resolved, turning yield into a no-op and reproducing\nissue #1440's starvation symptom by a different path (caught by the\nexisting fiber-timed-mutex-lock-not-starved-by-busy-sibling.scm test).\nFixed by splitting schedule() (unchanged, used by advisory checks and\nvm_calls.zig's non-nested switchTo dispatch) from a new\nscheduleForDispatch() (excludes driving fibers, used only by\nrunSchedulerStep's own dispatch loop).\n\nVerified: zig build test and -Dgc-stress=true green; full Scheme/R7RS\nsuite 1839/0; zig build wasm and -Dtarget=x86_64-linux still build; zig\nfmt clean.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* Address PR #1521 review nits: stale schedule() comment, unreachable-guard note, test style\n\n- tests/scheme/smoke/mutex-nested-dispatch-dirty-snapshot-1487.scm: the\n  comment wrongly credited plain schedule() with excluding driving\n  fibers, contradicting the actual schedule()/scheduleForDispatch()\n  split (CodeRabbit + manual review, both flagged the same lines).\n- src/fiber.zig: note that runSchedulerStep's `next_idx == my_idx` guard\n  is now unreachable (driving subsumes it) but kept as defense-in-depth,\n  so it doesn't read as live logic.\n- src/tests_scheduler.zig: convert the three new driving-guard tests to\n  th.TestContext, matching the rest of the file (CodeRabbit).\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-13T20:04:34Z",
          "tree_id": "6260853a71648582dbeb6b49d3a3d07d283827df",
          "url": "https://github.com/kaappi/kaappi/commit/1da7cf32ba3b235d896a6abe9e997b4b4b73e834"
        },
        "date": 1783974829752,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 5.383515,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.230968,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.931462,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.536127,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.007151,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.054095,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.500986,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069549,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.505183,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.942854,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.588306,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.435335,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.841356,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.688206,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.04449,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "3e00924a667396a5d406c7998c3e6c64cbfe35d9",
          "message": "Resolve portable SRFI libraries via exe-relative lib/ fallback (#1524)\n\n* Resolve portable SRFI libraries via exe-relative lib/ fallback\n\nresolveLibraryPath only checked cwd-relative paths, --lib-path, the\nrunning script's own directory, and ~/.kaappi/lib — none of which point\nat a `zig build`-produced binary's own source tree. A binary built from\nsource and run from any other directory, with no prior thottam/installer\nsetup, couldn't resolve portable (non-built-in) SRFI .sld libraries.\n\nAdd a shared exe-relative lib-dir lookup (kaappi_paths.getExeRelativeLibDir),\nmirroring the <exe_dir>/../lib search already used to find libkaappi_rt.a\nfor the native backend. build.zig now installs lib/ into zig-out/lib/\nalongside the exe so the two line up, and main.zig adds that directory as\na last-resort fallback after ~/.kaappi/lib so an existing install is never\nshadowed. native_compiler.zig's near-duplicate local copy now delegates to\nthe shared helper instead of duplicating the platform-specific lookup.\n\nFixes #1523.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* Address PR #1524 review nits: macOS realpath, vacuous test, dup import\n\n- kaappi_paths.getExeRelativeLibDir: _NSGetExecutablePath can return a\n  symlinked or relative path (e.g. a Homebrew Cellar symlink), which would\n  derive ../lib from the wrong tree. Resolve it via std.c.realpath first,\n  falling back to the raw path if that fails. Verified against a synthetic\n  symlinked-bin/kaappi -> real/bin/kaappi layout.\n- Reject a Linux readlink(\"/proc/self/exe\") result that exactly fills the\n  buffer, symmetric with the macOS branch's overflow handling.\n- The getExeRelativeLibDir unit test silently passed if the function\n  returned null instead of exercising the /lib suffix check; assert\n  non-null explicitly.\n- main.zig: hoist the two function-local @import(\"kaappi_paths.zig\") in\n  mainImpl's library-path block into one.\n\nFlagged by CodeRabbit and by manual review on PR #1524.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-13T20:27:54Z",
          "tree_id": "e81673c69d8a275585de6441e4bf4eb60914badc",
          "url": "https://github.com/kaappi/kaappi/commit/3e00924a667396a5d406c7998c3e6c64cbfe35d9"
        },
        "date": 1783976212106,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.081547,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.440964,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.946833,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.441979,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006748,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.053019,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.510684,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068134,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.256529,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.991209,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.538011,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.477079,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.7702,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.81156,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.046403,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "7d2a7655aa78adc2a32c21e58769378595909145",
          "message": "Preserve a closure's lib_env when deep-copying across threads (#1479) (#1526)\n\nA procedure defined inside a `define-library` body that `thread-start!`s a\nthunk calling into another library's exported procedure hung (kaappi-http's\n`http-listen-threaded`) or raised \"undefined variable\" (unguarded) on every\nrequest.\n\nRoot cause: `GC.deepCopy`, which copies the thunk closure from the parent GC\nto the child OS thread's GC, set `new_func.env = null`. Runtime name\nresolution uses `func.env orelse self.globals` (vm_dispatch.zig), so nulling\nthe library's `lib_env` silently redirected every lookup in the child to the\nshared globals map — where library-scoped imports don't live. The child then\nfailed to resolve the cross-library name; http's `guard` swallowed the error\nand closed the socket, so the client just saw a hung connection. The same\ncode defined at top level worked because a top-level import lands in globals,\nwhere `env == null` already looks.\n\nFix: preserve `new_func.env = func.env`. `env` is a raw `*StringHashMap`\npointer into the shared library registry — `VM.initForThread` shares\n`vm.libraries` by pointer and the parent keeps every `lib_env` alive, so the\nchild resolving names through it (and running the parent-heap procedures it\nfinds) is exactly how it already runs any shared global. It is not a GC\nValue, so the collector never traverses it and no cross-heap mark-bit is\nwritten. `env_val` (the eval/immutability Environment *object*, a GC Value)\nstays NIL rather than sharing a parent-heap object into the child heap;\nruntime resolution uses `env`, not `env_val`, and a normally loaded library\nhas `env_val == NIL` here anyway.\n\nRegression test `library-thread-cross-call-1479.scm` (+ `lib1479/` fixtures)\ncovers both the plain and guard-wrapped (http-shaped) forms, including the\ncallee resolving its own library-scoped helper; it fails (exit 1) without the\nfix and passes with it. Full unit suite, gc-stress (srfi18 cross-thread copy),\nand Scheme suite (449 files) green.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-14T09:50:32+05:30",
          "tree_id": "383b21a553372260db40f648b5996cba20d73dc3",
          "url": "https://github.com/kaappi/kaappi/commit/7d2a7655aa78adc2a32c21e58769378595909145"
        },
        "date": 1784004511661,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.906324,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.438422,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.925709,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.514686,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006363,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.054591,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.50269,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069455,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.315357,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.957682,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.611079,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.426528,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.833504,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.622483,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043124,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "7177dbb17497500170b60b06afb6e4d49148028e",
          "message": "Make fiber scheduling O(1) with a ready ring and free-slot list (#1477) (#1525)\n\nFiberScheduler did an O(fiber count) linear scan on the dispatch hot path\nand again on every spawn:\n\n- schedule()/scheduleForDispatch() round-robin-scanned the whole `fibers`\n  array (mostly parked io_waiting fibers on a busy server) to find the next\n  runnable fiber, on every dispatch.\n- addFiber() scanned the array for a reusable slot on every spawn, so\n  spawning N live fibers was O(n^2).\n- Two more O(n) scans hid on the same tick: anyIoWaiting() scanned all\n  fibers to gate the reactor poll, and yield's advisory `schedule() == null`\n  check scanned them again.\n\nReplace all four with incremental O(1) bookkeeping:\n\n- A ready ring (FIFO of runnable slot indices) fed by markRunnable at every\n  transition to .created/.suspended, consumed round-robin by the dispatch\n  paths. Each Fiber carries its stable `sched_idx` (so wakes enqueue in O(1))\n  and a `queued` flag (so the ring can't accumulate duplicates).\n- A free-slot list fed by retireSlot at every .completed/.errored\n  transition, so addFiber reuses a vacated slot without scanning (and appends\n  straight away when none is free). Slot 0 (main) is never recycled.\n- anyIoWaiting() now reads the reactor's registration count in O(1).\n- yield's advisory check uses a new non-consuming anyRunnable() peek.\n\nThe ring and free list are pure accelerators: the dispatch paths keep the\noriginal O(n) round-robin scan as an authoritative fallback, so correctness\nnever depends on markRunnable coverage (any status set directly without it —\nmuch test code — still dispatches correctly, just via the scan). The\nadvisory peek is ring-only by design to stay O(1); a missed enqueue there\nonly costs a yield that no-ops when it could have rotated, never correctness.\n\nDriving fibers (#1487) are dropped from the ring rather than dispatched,\nconsistent with \"only the parked fiber's own loop ever consumes its wake\";\nthe fallback scan still finds them for plain schedule()/anyRunnable.\n\nMeasured with a two-worker ping-pong among N channel-blocked siblings\n(ns per real dispatch): baseline 416 / 4143 / 25996 at N=100 / 1000 / 5000;\nafter, a flat ~170 regardless of N — O(n) -> O(1), 154x at N=5000. Full unit\nsuite, R7RS (1395), and Scheme suite (449 files) green, including under\n-Dgc-stress=true for the fiber/scheduler/srfi18/port tests.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-14T09:50:08+05:30",
          "tree_id": "7588c0a63aa6ec8e5107fa7ecba65153d5d2f1ff",
          "url": "https://github.com/kaappi/kaappi/commit/7177dbb17497500170b60b06afb6e4d49148028e"
        },
        "date": 1784004578404,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 5.345646,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.176216,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.971121,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.533747,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006361,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.055437,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.504477,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069805,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.344469,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.967894,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.577242,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.439114,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.841525,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.7046,
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
          "id": "a3f3618367c489a8390860247d191f597bd2219e",
          "message": "Add fd->port to give a raw fd reactor-integrated I/O (#1478) (#1527)\n\nkaappi-net's TCP sockets never reach the fiber I/O reactor: tcp-recv/tcp-send\nare bare blocking send(2)/recv(2) FFI calls and poll-read/poll-write are a raw\nfcntl+poll(2) wrapper, none of which touch Reactor.register/waitForFd. So\nkaappi-http's http-listen-fiber layers a fixed 1ms poll-then-sleep loop on top\n-- a ~1ms tax on every request even fully uncontended (747 vs 3329 req/s at\nconcurrency=1 in the KEP-0001 Phase 7 benchmarks).\n\nThe blocker was crossing the FFI boundary: the reactor and waitForFd are\nVM-internal, and a standalone \"wait on this fd\" primitive can't work under the\npark/re-execution protocol -- it never drains the fd, so a re-executed park\nre-parks forever. The primitives that do work (readOneByte/portWriteBytes) do\ntry-syscall-then-wait-on-EAGAIN as one unit, and every port fd > 2 already\nflips to O_NONBLOCK lazily and suspends the fiber on the reactor.\n\nSo expose that machinery directly: (fd->port fd) wraps a raw descriptor as a\nbidirectional binary port. A kaappi-net socket fd (from tcp-accept/tcp-connect,\nalready plain integers) becomes a normal reactor-integrated port -- read-u8/\nread-bytevector!/write-bytevector suspend the fiber on EAGAIN instead of\nbusy-polling, no C changes needed. The port owns the fd (close-port closes it,\nwakes parked fibers, unregisters from the reactor); fd 0/1/2 are refused to\npreserve the standard streams' blocking semantics. Lives in (kaappi ffi), which\nFFI socket libraries already import.\n\nTests (tests_port_io.zig): a reader fiber on an fd->port pipe parks on the\nreactor and wakes exactly when the peer writes; fd 0/1/2 and non-fixnums are\nrejected. Green under -Dgc-stress=true and the full unit suite.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-14T04:32:56Z",
          "tree_id": "3ce5e014a2a252341b804fc538d39eabf004d13e",
          "url": "https://github.com/kaappi/kaappi/commit/a3f3618367c489a8390860247d191f597bd2219e"
        },
        "date": 1784005377878,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.086167,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 10.526862,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.931487,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.44145,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006825,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.0528,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.508781,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.067723,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.198317,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.978025,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.514907,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.480214,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.751677,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.819143,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045751,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "5e86f2319532a35b644d9ff9b4ccf1fea284118f",
          "message": "Clear stale gap registers before call/cc continuation capture (#1464) (#1528)\n\n* Clear stale gap registers before call/cc continuation capture\n\nA full call/cc continuation snapshots the contiguous register range\n[0, max_reg), where max_reg is the highest live frame end. That range\nspans \"gap\" registers between live frame windows — slots vacated by\nreturned frames that still hold that frame's last heap pointer.\n\nmarkVMRoots only marks per-frame windows, so it never keeps a gap\ntarget alive; under gc-stress the collector frees it, leaving the gap\nregister dangling. captureContinuation copied the gap verbatim into the\nsnapshot, and marking that continuation later dereferenced the freed\nobject — a GC use-after-free the fuzz workflow hit as a segfault in\nmarkValueInner reading obj.owner (issue #1464).\n\nScrub the dead gap slots to UNDEFINED before the snapshot so it covers\nexactly what the root marker protects. Restore copies the snapshot back\nverbatim and no frame ever reads a gap slot, so this is\nbehavior-preserving.\n\nThe same contiguous-vs-per-frame inconsistency exists in the fiber\nsave/mark path (saveCurrentFiber + markFiberState); that sibling is\ntracked separately.\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>\n\n* Make gap-register clearing allocation-free\n\nThe first cut allocated a per-capture bool bitmap and scanned the full\n[0, max_reg) range, regressing the call_cc benchmark ~1.9x (a tight\ncapture loop pays that cost on every call/cc).\n\nFrame bases are non-decreasing — every call places its callee's frame\npast the caller's base, and continuation restore preserves that order —\nso a single ordered sweep tracking the highest covered register finds\nthe gaps with no scratch buffer and touches only the gap slots. A debug\nassert guards the ordering invariant. The call_cc micro-benchmark is\nnow indistinguishable from baseline; the full suite stays green under\n-Dgc-stress=true.\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-14T13:35:24+05:30",
          "tree_id": "9b8e726da683419e8cfc953937d3c6784ee8c5a8",
          "url": "https://github.com/kaappi/kaappi/commit/5e86f2319532a35b644d9ff9b4ccf1fea284118f"
        },
        "date": 1784017887131,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.446558,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.00399,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.907314,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.55037,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006476,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.053896,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.518164,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069352,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.414555,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 2.011509,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.566264,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.429483,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.861097,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.635428,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042889,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "ef88d7e64596938ddeb87626b9a2b3e6c263e0bc",
          "message": "Bound fuzz eval by instruction count under gc-stress (#1531)\n\nThe grammar/native/portable generator-coverage gates and the differential-\noracle regression gate in tests_fuzz.zig were unconditionally skipped under\n-Dgc-stress=true. A full collection on every allocation slows evaluation by\norders of magnitude, so the fixed 100 ms per-program deadline degenerated\ninto \"did it time out\" rather than measuring whether the generator produces\nvalid programs — a gc-stress build lost these regression gates entirely.\n\nA gc-stress build executes the *same* number of bytecode instructions as a\nnormal build; only wall-clock time changes. So bound by instruction count\nthere instead: evalNormalized sets vm.instruction_limit (2M, ~50x the largest\ncorrect generator program measured over 300 seeds and well under the >10M\nloop-heavy tail the gates intentionally count as misses) and keeps only a\nloose wall-clock backstop. Normal builds are unchanged — the limit stays null\nand the 100 ms deadline applies as before. runUntil checks the limit inside\nthe existing per-1024-instruction block, so the hot path is untouched.\n\nUnder gc-stress the gates now measure generator correctness: grammar 56/60,\nnative 60/60, portable 60/60, and the oracle compares 57/60 fixed-seed pairs\n(3 giant-loop seeds hit the budget on both paths) instead of 0.\n\nCloses #1447, #1448, #1449, #1450\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-14T15:50:16+05:30",
          "tree_id": "b90bf5db44b51db2b29680784a1b70cecd3aefb0",
          "url": "https://github.com/kaappi/kaappi/commit/ef88d7e64596938ddeb87626b9a2b3e6c263e0bc"
        },
        "date": 1784026343314,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.421673,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.804535,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.691257,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.443048,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006437,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.04571,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.391807,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.05657,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.03715,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.503312,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.357821,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.430055,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.498674,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.077451,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.038728,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "9bc79a2a6a20e51807ac61bea798858518b98ae7",
          "message": "Compile the LLVM native backend at -O2 with an IR-verify safety net (#1532)\n\nThe linker was invoked with no -O flag, so LLVM compiled the emitter's\ndeliberately naive IR at -O0 — none of the optimization that is the reason to\nuse LLVM ran. Every immediate was `add i64 0, K`, let-bindings and shadow-stack\nroot slots and args arrays went through alloca/load/store, and if/and/or became\nlong br/phi chains, all left in place.\n\nPass -O2 in tryLink (kaappi compile), the `zig build native` step, the\ndocumented manual flow, and the e2e harness so mem2reg/instcombine/simplifycfg/\nconstant-folding collapse this. Root-slot allocas whose address escapes into\nkaappi_gc_push_root correctly stay in memory for GC scanning.\n\nAdd the paired safety net: hand-written IR that passes -O0 can hide\nwell-formedness bugs that break or miscompile under -O2's stricter verifier and\npasses. tests/e2e/run-e2e.sh now verifies every emitted .ll before linking,\nchoosing opt -passes=verify, llvm-as, or (typical on CI, where neither is on\nPATH) zig cc -c — the same bundled LLVM that links the binary, so the step never\nsilently no-ops. The verifier runs without -w so no malformed-IR diagnostic is\nhidden; -w stays on the user-facing compile, where it only silences cosmetic\nwarnings (a hard verifier error still fails regardless).\n\ne2e stays green (24/24, native output diffs identically against the\ninterpreter); a new tak.scm locks in the -O2 native path on multi-way recursion.\nfib(38) runs 1.11x faster (-O0 1.605s -> -O2 1.441s); the IR shrinks (fib 67 ->\n51 instruction lines, all `add i64 0,K` immediates folded). Larger gains need\nLTO to inline the runtime primitives, tracked separately as #1493.\n\nCloses #1492.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-14T15:50:37+05:30",
          "tree_id": "f3ec57e6f0647c836ad8afe5bc5373b476510bc7",
          "url": "https://github.com/kaappi/kaappi/commit/9bc79a2a6a20e51807ac61bea798858518b98ae7"
        },
        "date": 1784026472921,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.348989,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.339414,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.91493,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.430202,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006338,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.054042,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.501162,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069425,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.348304,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.941458,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.594865,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.438538,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.825884,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.691371,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044627,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "b464e02480147ccf565190f7190d845ac56423bb",
          "message": "Clear stale gap registers before fiber suspension snapshot (#1529) (#1533)\n\nmarkVMRoots marks a running fiber's registers per frame window and skips\nthe dead \"gap\" slots between windows, but saveCurrentFiber copies the\ncontiguous register span and markFiberState marks it contiguously. A gap\nslot's stale pointer — freed during the fiber's run because per-frame\nmarking never protected it — was copied into the fiber's saved snapshot\non suspension, and a later collection while the fiber was parked traced\nthat dangling pointer, a GC use-after-free (sibling of the call/cc bug\nfixed in #1464/#1528).\n\nMove clearGapRegisters (the allocation-free ordered sweep from #1528) to\na shared VM method and call it in saveCurrentFiber before the register\nmemcpy; captureContinuation now calls the same method. Scrubbing dead gap\nslots to UNDEFINED is behavior-preserving because no frame ever reads\nthem. Adds a gc-stress regression test that segfaults without the scrub.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-14T16:08:05+05:30",
          "tree_id": "0d133607e92613c69f7d08c20c1fb4eb90a42780",
          "url": "https://github.com/kaappi/kaappi/commit/b464e02480147ccf565190f7190d845ac56423bb"
        },
        "date": 1784027144602,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.361988,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.204196,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.903569,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.40409,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006334,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.053697,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.499444,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069393,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.41092,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.96064,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.598438,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.432013,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.857396,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.643883,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043938,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "b2043de60a22461ed894e0ec7f6397ac48f2ada0",
          "message": "Add A/B/C/D envelope-cost benchmark matrix (KEP-0002 Phase 7) (#1535)\n\nGrows src/bench_channel.zig from the Phase 1 single-lever harness into the\nfull P3 elision-lever matrix (research/open-problems.md P3) that the Phase 7\nA/B/C/D decision is pre-registered against: (A) per-message GC struct as\nshipped, (B) reusable per-channel arena, (C) immediates skip the envelope,\n(D) refcounted immutable side-heap for large payloads. A counting allocator\nreports true allocations/message and a printer evaluates the pre-registered\ncriteria mechanically.\n\nThe point of the matrix is the decision it records, not the raw numbers:\n\n- (C) ships -- the immediate fast path is 28-120x on fixnums and erases the\n  two fixed allocations (GC struct + ~8 KiB root buffer) that lever A pays\n  per message even for a zero-object fixnum payload.\n- (B) is a ship candidate whose verdict is build-mode sensitive: it clears\n  the >= 30%-on-all-small-messages bar under both safety-on builds\n  (ReleaseSafe 57-98%, Debug 65-99%) but dips the 1 KiB string to ~26% under\n  ReleaseFast. Since the shipped binary is ReleaseSafe (protocol §4.5) the\n  operative reading is \"replace A\", conditioned on the pre-registered second\n  clause -- a real arena in shared_channel.zig surviving gc-stress/leak with\n  no lifetime rule leaking outside that file -- which this micro-benchmark\n  does not settle.\n- (D) is measured only (2.6-2.8x on 64 KiB, 8->2 allocations, no copy-out);\n  its shipping decision belongs to the KEP-0003 gate (#1474).\n\nThis is the envelope-cost half of #1472, at the eyeball benchmark tier (like\nbench-fibers/bench-reactor), on one machine (macOS aarch64). The parallel-map\ngate campaign, the Linux run, the lever-B arena prototype, shipping C, and the\nKEP-0002 UQ 1 amendment remain. Full write-up and caveats in\ndocs/dev/kep-0002-phase7-envelope-benchmarks.md.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-14T16:40:17+05:30",
          "tree_id": "edd187e57f8d6088b2b77ab60a975188edce4c78",
          "url": "https://github.com/kaappi/kaappi/commit/b2043de60a22461ed894e0ec7f6397ac48f2ada0"
        },
        "date": 1784029261248,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.073962,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.77298,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.91355,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.407114,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006943,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.052828,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.507234,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068894,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.263933,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.991257,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.512644,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.470714,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.74841,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.765908,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045608,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "a27d2f82514e1cee900aa5292cdbd6ef40bd65ea",
          "message": "Add stable KP diagnostic codes to every error path (#1534)\n\nA diagnostic's message string was its only identity: a tool — an AI agent,\na CI gate, an editor — had to substring-match prose that is free to be\nreworded, and some paths leaked raw Zig error names straight to the user\n(`read error: error.UnexpectedChar`). This is the keystone of the machine\nlegibility campaign (#1503): give every user-facing diagnostic a stable\n`KP`-prefixed handle so the code is the contract and the message is free to\nimprove.\n\nIntroduce `src/diagnostics.zig`: a comptime registry binding each diagnostic\nto a code (the enum ordinal is the KP number), a message template, a prose\nexplanation for a later `kaappi explain`, and a severity. A comptime gate\nfails the build on any duplicate, missing, or empty-field entry — the KEP's\nregistry-integrity check, enforced at build time. Text output gains the code\n(`error[KP3001]: ...`), keeping the stage word for the human reader.\n\nErrors reach the reporting layer two ways. Native `VMError`s are coded from\nthe escaping error; errors raised as objects (division by zero, `error`,\n`raise`) carry their code on a new `ErrorObject.code` field, stamped at the\nraise site and lifted to the reporter by noteUncaughtException — the robust\nrepresentation the Phase-4 `error-object-code` accessor will reuse. High-\ntraffic diagnostics are coded first; the long tail shows the generic KP3000\nuncaught-exception until migrated, and no path ever regresses to leaking a\nZig name. `error_type` and the R7RS error accessors are untouched.\n\nDesign record: KEP-0005. Policy and contributor guide: docs/dev/diagnostics.md.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-14T11:56:54Z",
          "tree_id": "3e63454ead3f03bb40b6eaf22f5a6bf02fec50bb",
          "url": "https://github.com/kaappi/kaappi/commit/a27d2f82514e1cee900aa5292cdbd6ef40bd65ea"
        },
        "date": 1784031842808,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.055521,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.780565,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.923699,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.435788,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006729,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.052878,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.517498,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.067824,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.257953,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.987178,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.514474,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.479239,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.740906,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.845601,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.048505,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "328ca95ea31a2231a5fdd29bf22520448495e251",
          "message": "Add KEP-0003 acceptance-gate classification worksheet (#1474) (#1538)\n\nThe gate is a \"reading, not an argument\" of the #1472 §6 dataset, which\ndoes not exist yet (only the P3 eyeball benchmark landed in #1535). Build\nthe reading instrument now, from the frozen keps §5-§6 protocol, so that\nwhen the gate campaign produces the CSV the classification is pure\nfill-in-the-blanks with no room for post-hoc judgement: every gate and\nsupporting cell enumerated, each rule wired to its exact cells and CI\nbound, per-machine precedence and two-machine agreement as a mechanical\nprocedure. All data slots are empty placeholders; no numbers fabricated.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-14T18:45:31+05:30",
          "tree_id": "ef88ff92af504dac94bd1da5667615aa0d773147",
          "url": "https://github.com/kaappi/kaappi/commit/328ca95ea31a2231a5fdd29bf22520448495e251"
        },
        "date": 1784036291524,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.062417,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.766881,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.92,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.458791,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006902,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.053479,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.510707,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068104,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.262302,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.983827,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.529656,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.474136,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.754821,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.764479,
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
          "id": "2893437433dbcfc754488624b7a64ed727bc6778",
          "message": "Add regression test for nested-wait dirty-snapshot hazard (#1490) (#1536)\n\nIssue #1490 is the same dirty-snapshot dispatch corruption as #1487, already\nfixed by the generic `driving` guard in #1521 (which merged ~10h after #1490\nwas filed). It reaches the hazard through a distinct trigger, though:\nreactor-timer theft. A spawned fiber's blocking wait, nested inside another\nfiber's live `thread-sleep!` drive, parks in the reactor bounded by the\nnearest timer in the shared heap -- which is the *ancestor's* own sleep\ntimer. That timer pop flips the ancestor `.suspended`; without the `driving`\nguard the nested drive would then re-dispatch the ancestor from its stale,\nmid-native-call snapshot, surfacing as `panic: integer overflow` in\ninvokeEscape.\n\nThe existing regression test (mutex-nested-dispatch-dirty-snapshot-1487.scm)\nonly exercises the mutex-unlock wake trigger, and the local channel wait\npaths #1490 names had no coverage. This adds an end-to-end test over all four\nblocking primitives (channel-receive, full-bounded channel-send, mutex-lock!,\ncondition-variable wait), each nested under a thread-sleep! loop -- also\ncompleting the condvar/channel end-to-end repro deliberately deferred in\n#1521's review.\n\nVerified via A/B (scheduleForDispatch -> scheduleImpl(false)): every scenario\ncrashes without the guard and passes with it.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-14T13:30:55Z",
          "tree_id": "70bc0e816efeb6aad7bbddf90f2911922975ff1b",
          "url": "https://github.com/kaappi/kaappi/commit/2893437433dbcfc754488624b7a64ed727bc6778"
        },
        "date": 1784037340718,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.2898,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.89474,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.911326,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.428838,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006369,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.054086,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.503355,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069699,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.385955,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.955635,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.589243,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.434188,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.881448,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.467774,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045488,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "b52f873f85edaa19e87d0c59292038e32859dbb1",
          "message": "Add --diagnostics=json structured diagnostic output (#1505) (#1537)\n\nAgents driving kaappi have had to scrape human-oriented error text. This\nexposes every read, expand, compile, and runtime diagnostic as JSON Lines\non stderr under `--diagnostics=json`, so tools can match on structure\ninstead of prose. Text mode stays the default and is unchanged.\n\nRather than invent a schema, each line is an LSP `Diagnostic` — the exact\nshape the language server already publishes. The serializer now lives in\none place (src/lsp_diagnostic.zig) that both the CLI reporting funnel and\nkaappi_lsp.zig call, so the two cannot drift; the LSP gains KP codes as a\nresult. `code` comes from the diagnostics registry (#1504), and a \"did you\nmean\" fix maps to `data.suggestions` with kind/replacement, carried\nstructurally on the VM so the JSON message stays clean.\n\nPositions are the LSP-standard zero-based coordinates and are points until\nspan tracking lands (#1506). The text snippet and backtrace are suppressed\nin JSON mode so stderr stays one parseable object per line.\n\nPart of #1503.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-14T14:29:22Z",
          "tree_id": "cfcd9b02a23e9237c26261240ece1a4f90ab32aa",
          "url": "https://github.com/kaappi/kaappi/commit/b52f873f85edaa19e87d0c59292038e32859dbb1"
        },
        "date": 1784041041243,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.055518,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 10.132201,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.930885,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.42145,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00675,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.052808,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.509853,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068161,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.222816,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.980654,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.702139,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.475842,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.768253,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.816284,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045877,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "608b70f765e3c56da4f893fb4499d12efca153ac",
          "message": "Box mutable captured variables in the native backend (#1497) (#1539)\n\nThe LLVM native closure tiers copied captured variables by value into the\n%upvalues array at closure-creation time. This diverged from the interpreter's\nby-location closure semantics whenever a captured binding was mutated after\ncapture (#1422), and forced the tiers to reject any closure body containing a\nset! or internal define — a whole class of counter/accumulator closures fell\nback to the interpreter.\n\nApply classic assignment conversion: a binding that is both captured by a\nnested lambda and mutated (by set!) is represented as a heap box. Closures\ncapture the box pointer by value; reads/writes go through kaappi_box_ref /\nkaappi_box_set. Because the pointer is immutable but the contents are shared,\na set! through any closure over the binding is visible to all of them, matching\nthe VM exactly. Only captured-and-mutated bindings are boxed; everything else\nkeeps the by-value fast path. A box is a pair (value . '()), so the GC needs no\nnew heap type.\n\nTwo latent bugs surfaced and are fixed:\n\n- bindParamsAsGlobals republished captures by value, so a boxed variable\n  captured by a lambda that itself falls back to eval (e.g. a variadic inner\n  lambda) reintroduced the #1422 snapshot. It now aborts native compilation of\n  the enclosing frame so the interpreter handles the whole thing.\n- emitLambdaFunction registered native_fns before body emission (for self-tail\n  resolution) without rolling back on failure, which could leave a call site\n  emitting a direct call to a @lambda_N that was never defined.\n\nBoxed frames disable the self-tail-call loop and lower non-tail so box roots\npop at a single ret. Verified under -Dgc-stress and KAAPPI_GC_THRESHOLD=1.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-14T20:28:18+05:30",
          "tree_id": "0fb199943056f0110116db5c5331672319ff525b",
          "url": "https://github.com/kaappi/kaappi/commit/608b70f765e3c56da4f893fb4499d12efca153ac"
        },
        "date": 1784042984521,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.070574,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 10.510741,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.974172,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.421811,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006862,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.052983,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.513876,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068294,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.278317,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.985839,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.513335,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.485189,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.751981,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.800219,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045454,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "708a660b77b0d616de93be02f421b8a823d7219c",
          "message": "Batch fd reads in readOneByte (#1460) (#1542)\n\nreadOneByte issued one read(2) syscall per byte on fd-backed ports, so\nevery byte-at-a-time consumer (read-bytevector, read-string, read-char,\nread-line, read-u8) paid k syscalls to read k bytes from a file or\nsocket.\n\nThe fd path now reads up to read_chunk_size (4096) bytes in a single\nread(2), returns the first byte, and stashes the remainder in the port's\nexisting read_buf. The consumption drain at the top of readOneByte hands\nthose out on subsequent calls, so a run of byte reads costs one syscall\nper burst instead of one per byte.\n\nThe batched leftovers compose with the existing park/stash machinery\nbecause read_buf is always empty at the fd path: every park point sits\npast the peek/read_buf/string drains, so a caller that parks later does\nso on a subsequent call after this buffer drains, where stashPartialRead\nprepends onto an empty read_buf. The fresh slice is allocated exactly\nn-1 bytes so rb.len == read_buf_len and the \"last read_buf_len bytes\"\nconsumption cursor starts at 0. read(2) short-returns whatever is\navailable, so a 1-byte interactive read never blocks to fill a chunk,\nand an n==1 read allocates nothing (byte-identical to the old path).\nreadDatumFn's incremental-parse loop already batched; it now shares the\nread_chunk_size constant.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-14T22:30:46+05:30",
          "tree_id": "db54086b4a64f2b942ce3d966dabd5a9b7d8e66a",
          "url": "https://github.com/kaappi/kaappi/commit/708a660b77b0d616de93be02f421b8a823d7219c"
        },
        "date": 1784050013895,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.289928,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.438313,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.955238,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.478035,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006683,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.054589,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.516532,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070669,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.637284,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 2.110342,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.581259,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.438559,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.832305,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.672147,
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
          "id": "ae167d1449fa80ff29df4c678776ead96d13cb9d",
          "message": "Run the #809 300-capture stress test again (#1541)\n\nThe 300-variable-capture regression test for the u8→u16 upvalue_count\nwidening was skipped under -Dgc-stress=true because compiling that\nprogram once peaked ~7 GB RSS and OOM-killed the stress suite.\n\nThat blow-up was not inherent to the test: markValue reallocated its\nmark worklist on every call, and the testing allocator's metadata\nretention amplified the churn. #1436 made the worklist persistent, so\nthe peak is now a few tens of MB (verified: ~32 MB for this test in\nisolation under gc-stress). The skip outlived its cause — remove it so\nthe >255-upvalue boundary is covered under stress again.\n\nFixes #1451\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-14T22:30:26+05:30",
          "tree_id": "34a09af37dbb749bda9298c7f42b74932722699a",
          "url": "https://github.com/kaappi/kaappi/commit/ae167d1449fa80ff29df4c678776ead96d13cb9d"
        },
        "date": 1784050069325,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.319249,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.190716,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.935661,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.51737,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006452,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.054913,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.519199,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.071007,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.719209,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.989005,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.572917,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.427995,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.827404,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.639707,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045152,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "63079083ff2d5d36e7f3d7e6c394a85518338832",
          "message": "Unskip eval tail-call test under gc-stress via frame-depth proxy (#1540)\n\nThe #1253 regression test detected non-tail-called `eval` by forcing a\nframe-limit overflow, which is only decisive past MAX_FRAME_LIMIT (32768)\niterations. Every iteration recompiles the expression through `eval`, so\nunder -Dgc-stress=true that is millions of full collections — hours — and\nthe test was unconditionally skipped there (#1452), leaving no bound on\nwhen it might become practical again.\n\nOverflow-based detection is inherently unaffordable under stress: it needs\n>32768 compile-heavy iterations no matter how the count is tuned. Instead,\nobserve the guarded property (\"constant frame depth\") directly. A test-only\nobserver native records vm.frame_count at the base case of the recursion;\nrunning the loop at two very different iteration counts, a tail-called eval\nreuses its caller's frame so both depths match, while a non-tail-called eval\nwould push a frame per iteration and diverge. This is decisive with a few\nhundred iterations (910ms under gc-stress) and now runs on every build.\n\nVerified decisive by injecting the regression (eval in non-tail position):\ndepth grows 202 -> 2002 across the two counts and the test fails.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-14T22:30:08+05:30",
          "tree_id": "9a3cec2046f7a0eb1928590fffa928fe403c77dd",
          "url": "https://github.com/kaappi/kaappi/commit/63079083ff2d5d36e7f3d7e6c394a85518338832"
        },
        "date": 1784050117185,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.298789,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.477254,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.973109,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.490982,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006524,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.054323,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.518938,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.071087,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.69996,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.983621,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.598785,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.440946,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.836982,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.657527,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045203,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "efc976e3bcff31eb041f5636d16bee9f93b4b1b4",
          "message": "Inline fixnum fast paths for hot native primitives (#1493) (#1544)\n\nInlined primitives in the LLVM backend emit a cross-module call per\noperation (`kaappi_fixnum_add`, `kaappi_car`, …) into `libkaappi_rt.a`.\nPlain -O2 cannot inline across that archive boundary, so trivial\narithmetic in a hot loop pays a real call every iteration.\n\nThe issue proposed LTO as the primary fix, but it is unavailable on the\nprimary dev platform: Zig 0.16 cannot use LLD for Mach-O (\"using LLD to\nlink macho files is unsupported\") and -flto requires LLD, so both the\nruntime lib build and the native link fail with -flto on macOS. It works\nonly when targeting Linux. Rather than ship a per-platform-inconsistent\noptimization, take the issue's sanctioned alternative and emit the hottest\nprimitives as inline IR, which is portable across every target (it is just\ntext the emitter writes) and needs no cross-module inlining.\n\n`+ - * < = null?` now lower to inline fixnum fast paths with a runtime\nslow-path fallback (non-fixnum operands, or overflow out of the i48 range →\nbignum). The fast paths touch only the NaN-boxed Value bits, whose encoding\nis pulled from types.zig at emitter comptime (no hand-transcribed magic\nnumbers). car/cdr/cons stay as direct specialized calls: Pair/Object are\nauto-layout structs whose field offsets Zig does not guarantee, and cons\nallocates regardless.\n\nThe larger win is eliding the shadow-stack rooting the inline path emitted\naround every operation: the push_root/pop_roots pair only exists to keep\nthe first operand alive across the second's evaluation, which is pointless\nwhen the second operand cannot allocate. `nodeMayAllocate` conservatively\ndetects that (immediate constants and variable references never collect),\ndropping both calls for the common `(op var const)` / `(op var var)`\nshapes. fib(38) runs 3.30x faster than -O2-only (1.45s → 0.44s); alloc-\nbound loops are unchanged, as expected.\n\nVerified: e2e 27/27 (new native-inline-primitives.scm diffs overflow,\nnon-fixnum, and sign-extended-negative paths against the interpreter),\nunit suite 897/897, and native binaries stay correct under a forced-\ncollection KAAPPI_GC_THRESHOLD=1 run including the rooting-kept case.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-14T22:31:13+05:30",
          "tree_id": "f0f988b4cea64771d6ba1dacd172ac8bbdc959f4",
          "url": "https://github.com/kaappi/kaappi/commit/efc976e3bcff31eb041f5636d16bee9f93b4b1b4"
        },
        "date": 1784050921015,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.806974,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.30059,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.714514,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.434442,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.005238,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.041006,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.396068,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.052777,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.603374,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.540389,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.170268,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.371557,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.344787,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.423557,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.03757,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "91d63f359ee76220ebfd2e00208825ce69265878",
          "message": "Abandon cross-heap mutexes on fiber death (#1458) (#1545)\n\nabandonFiberMutexes found a dying fiber's held mutexes by scanning that\nfiber's own GC heap. A mutex shared across OS threads via a top-level\nglobal lives in whichever heap allocated it — typically the parent's, not\nthe dying child's — so the scan never found it: the mutex stayed\n'not-abandoned, m.owner dangled at the (soon-freed) dead child fiber, and\na cross-thread mutex-lock! hung or raised the generic deadlock error\ninstead of abandoned-mutex-exception.\n\nTrack held mutexes on the fiber itself (a per-fiber owned_mutexes list\nmaintained by mutex-lock!) so abandonment no longer depends on which heap\nowns the mutex object. The list is pruned-on-lock and deduped rather than\nmaintained at unlock, which bounds it without a cross-thread list-mutation\nrace; the defensive locked/owner guard still skips stale entries. It is\nonly ever mutated and walked on the fiber's own thread. thread-terminate!\nabandons a local fiber's mutexes in place and lets an OS-thread target\nself-abandon when it observes the terminate flag. markFiberState keeps\nheld mutexes alive (foreign ones are skipped by markValue's owner check);\nfreeObject frees the list.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-14T22:31:37+05:30",
          "tree_id": "94d7b13887993f361cfa57a81bb9c0149d0f1abe",
          "url": "https://github.com/kaappi/kaappi/commit/91d63f359ee76220ebfd2e00208825ce69265878"
        },
        "date": 1784050928394,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.422464,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.335765,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.89785,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.405041,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006391,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.053396,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.503517,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069878,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.430537,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.941585,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.587769,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.439019,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.832086,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.547017,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044269,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "df1a3524a429763708133b31d724ec3fa9309f90",
          "message": "Add `kaappi explain <code>` diagnostic documentation command (#1543)\n\nWith stable KP codes, each diagnostic can carry real documentation. Like\n`rustc --explain`, the binary becomes its own diagnostic reference —\noffline, version-matched, and identical for a human reading prose and an\nagent parsing JSON. Everything is read from the one registry in\ndiagnostics.zig, so the command, the --diagnostics=json stream, and the\ngenerated website page can never disagree about what a code means.\n\n`kaappi explain KP3001` prints the entry — meaning, a minimal triggering\nexample, and (woven into the prose) the fix. The code argument accepts the\nKP number in any case, a bare number, or the kebab name. `--json` emits one\nJSON object; `--all` the full text reference; `--all --json` a JSON array,\nthe drift-proof source a docs generator consumes.\n\nRegistry: add an `example` field to every entry (the \"minimal example that\ntriggers it\"), enforced non-empty by the same comptime gate and its runtime\nmirror. 22 of 26 examples are literal one-liners verified to emit their own\ncode; the four that cannot be inlined are representative and say so. The new\n`tests/scheme/errors/explain.sh` reruns every runnable example back through\n--diagnostics=json and asserts it still triggers its documented code, so a\ndrifting example fails CI rather than a user.\n\n`explain` is a pure query over the static registry, so main dispatches it\nbefore any VM/GC/library setup exists. The --json string escaper is shared\nwith --diagnostics=json (lsp_diagnostic.writeJsonString) so both machine\nsurfaces escape identically. tools/gen_diagnostics_reference.py renders the\nkaappi-lang.org page from `explain --all --json`; the page itself lands in\nthe docs repo as a follow-up.\n\nPart of #1503. Closes #1507.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-14T17:49:43Z",
          "tree_id": "76f8f486be0e78160b6ba16d0696617e677d6bc0",
          "url": "https://github.com/kaappi/kaappi/commit/df1a3524a429763708133b31d724ec3fa9309f90"
        },
        "date": 1784052860968,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.399569,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.535401,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.924517,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.433263,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00653,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.054989,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.499243,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068435,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.478838,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.95212,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.597947,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.444508,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.827212,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.69382,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.046381,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "d014dc9c75b6e2b6b45a03e6751817209477545c",
          "message": "Add dependency analysis to parallel-issues skill (#1547)\n\nIssues that depend on each other (via \"depends on #NNN\", \"blocked by\",\nGitHub linked-issues, etc.) shouldn't land in the same or an earlier\nbatch set than what they depend on.\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-14T23:52:08+05:30",
          "tree_id": "dd98f9f193ed6d8eb4b87a25c64880ff25bc350a",
          "url": "https://github.com/kaappi/kaappi/commit/d014dc9c75b6e2b6b45a03e6751817209477545c"
        },
        "date": 1784054840978,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 2.362312,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.957805,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.472646,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.475606,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004038,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.029277,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.268208,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.03426,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 1.91218,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.975685,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 0.846637,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.302072,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 0.914438,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.149521,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.025189,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "b5ce33d76e20e56f1251d84c74c9bf940976f537",
          "message": "KEP-0002 Phase 7 gate-campaign harness + lever D (#1472) (#1546)\n\n* Add KEP-0002 Phase 7 parallel-map gate-campaign harness (#1472)\n\nThe gate that decides KEP-0003 (kaappi#1474) reads the copy+reassembly\noverhead `share` of a parallel-map section, per the frozen protocol at\nkeps research/benchmarks/README.md. This lands the runnable harness for\nthat measurement (levers none/C; lever D follows in a later commit).\n\n- src/channel_instrument.zig: parent-side T_submit_copy / T_result_copy /\n  T_reassembly counters, the runtime elision-lever flag, and the peak-\n  envelope gauge, all behind -Dchannel-instrument (compiled out of the\n  shipped default per protocol §3; also keeps clock_gettime out of WASM).\n- shared_channel.zig: time the real send/receive copy path; lever C skips\n  the envelope heap for immediate payloads (Envelope.gc is now optional).\n- primitives_parallel.zig: %chan-instr-* / %elision-lever-set! harness\n  hooks, registered only in the instrument build so the shipped\n  (kaappi fibers) is unchanged, and tagged .kaappi_fibers (not .internal,\n  which is removed from globals after bootstrap) so they persist.\n- benchmarks/gate/: the six workloads + controls + serial baselines\n  (gate-harness.scm), the Kalibera-Jones driver emitting the §6 CSV\n  (run-gate.py), and README.md documenting the protocol mapping and the\n  pre-freeze findings (the #1489 hang, records not crossing channels,\n  matmul compute cost, an exception-crossing panic).\n\nVerified: unit suite green on normal and -Dchannel-instrument=true builds\n(new lever-C regression test + internal-spec drift guard); channel/fiber/\nparallel Scheme smoke tests green; local pilot on macOS aarch64 produced a\n§6 CSV with well-differentiated share values.\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>\n\n* Implement KEP-0002 Phase 7 lever D in the real channel path (#1472)\n\nLever D of the elision matrix (protocol §2): a refcounted immutable\nside-heap for large bytevectors, so a payload crossing a channel is\nsnapshotted once and shared by refcount instead of re-copied on every\nhop. The gate's C+D cells (kaappi#1474) require it.\n\n- src/shared_buffer.zig: SharedBuffer, the KEP-0002/0003 second\n  shared_object (after SharedChannel) -- a refcounted immutable byte\n  buffer outside every GC heap.\n- types.Bytevector.shared: opaque backing pointer; when set, data is\n  borrowed from a SharedBuffer and the bytevector holds one reference.\n- gc_deep_copy: under lever C+D the send side (envelope build) snapshots a\n  bytevector >= 4 KiB into a fresh SharedBuffer; the receive side (and any\n  re-copy of an already-backed bytevector) aliases by refcount -- zero\n  byte copy. Comptime-pruned in the shipped build.\n- memory.allocBytevectorShared / unshareBytevector: the backed allocator\n  and copy-on-write (a mutator privatizes borrowed bytes and drops the\n  reference before writing). COW wired into bytevector-u8-set!,\n  bytevector-copy!, read-bytevector!.\n- gc_collect: freeObject releases the SharedBuffer reference (freeing the\n  buffer at zero) instead of freeing borrowed bytes; objectSize counts\n  only the struct for a backed bytevector.\n- shared_channel.Envelope.create signals the send-side D mode around the\n  copy.\n\nScope (bytevectors only; no plain-source promotion for fan-out; strings\ndeferred) and rationale are in benchmarks/gate/README.md -- neither\naffects the gate classification (the one affected workload, FO-DIGEST\nfan-out, is compute-dominated).\n\nVerified: new lever-D unit test (backing / alias / copy-on-write /\nrefcount lifecycle) green on the instrument build and under\n-Dgc-stress=true; full unit suite green on normal and instrument builds;\nend-to-end pool test delivers correct bytes across a real thread and COW\nmutates safely; behaviorally, ip-band at C+D drops parent result-copy\ntime ~10x and peak envelope bytes ~40x vs lever none.\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-14T23:50:03+05:30",
          "tree_id": "da4adb009fcf71fc44b9434adebc9dbd43042620",
          "url": "https://github.com/kaappi/kaappi/commit/b5ce33d76e20e56f1251d84c74c9bf940976f537"
        },
        "date": 1784054869136,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 2.484516,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.040462,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.494705,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.545736,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004927,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.032103,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.282205,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.041367,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.194208,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.07395,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 0.934043,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.309345,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.04881,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.651952,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.027993,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "b6d349c0cc7207eca648f08588904a593a8712c2",
          "message": "Fix lost cross-thread wakeup in shared channel send/receive (#1489) (#1548)\n\nA fiber receiving on a promoted channel could park permanently even\nthough a live peer thread later sent. A local sibling's channel-send +\nchannel-receive, run during the receiver's SharedChannelPoll drive,\nconsumed the receiver's one-shot recv_waiters notifier registration, and\nthe fall-through check (peekReady) re-derived readiness WITHOUT\nre-registering. The later remote send found recv_waiters empty and rang\nnothing; the parked fiber's shared_waiters entry kept hasRunnableFibers()\ntrue, so the deadlock detector stayed suppressed and the process hung\nforever.\n\nRe-derive readiness after the drive THROUGH receive() itself, not a bare\npeekReady(): receive() re-registers the notifier under the channel lock\nwhen it returns .would_park, so the park is always armed (and returns the\nvalue/eof straight away if the drive produced one). channelSendShared had\nthe identical latent bug for bounded channels -- a sibling receive+send\nduring the drive consuming its send_waiters registration -- fixed the same\nway via send() (the full path enqueues nothing, so there is no\ndouble-send).\n\nRegression test tests/scheme/smoke/fiber-channel-lost-wakeup-1489.scm is\nthe issue's repro, bounded by a receive timeout so a regression FAILs\nrather than hangs (which run-all.sh would SKIP): it fails pre-fix (the\nreceiver is never woken and the timer fires) and passes post-fix.\n\nVerified: repro 20/20 no hangs; the gate-campaign cells that hung ~8% of\nruns are now 90/90 clean; full unit suite green on the normal build and\nunder -Dgc-stress for fiber/channel/scheduler; bounded-channel and\nparallel smoke tests green.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-15T00:55:26+05:30",
          "tree_id": "db77a1108a33c8d26b64bfdfc28f6cf57b1513d4",
          "url": "https://github.com/kaappi/kaappi/commit/b6d349c0cc7207eca648f08588904a593a8712c2"
        },
        "date": 1784058914642,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.460508,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.048332,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.891884,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.464168,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006422,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.054254,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.502708,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069551,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.402909,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.958267,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.616352,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.431513,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.83011,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.858635,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.051373,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "5d6b99e80c15f81a2bd861d0c5226bdddbdc1eb7",
          "message": "KEP-0002 Phase 7 gate: macOS dataset + filled worksheet (#1472, #1474) (#1549)\n\nThe macOS aarch64 reference machine of the KEP-0003 acceptance-gate\ncampaign, collected at commit b6d349c0 (K-J floor 20x10, w=8, both levers,\n920 launches, 0 failures -- the #1489 fix held at scale):\n\n- benchmarks/gate/results/gate-macos-aarch64.csv: the §6 dataset (+ metadata).\n- benchmarks/gate/classify.py: applies the §5 rules mechanically to the\n  CSV(s) -- the \"reading, not an argument\" -- emitting the share tables and\n  per/combined-machine outcomes.\n- benchmarks/gate/run-gate.py: --serial-invocations/--serial-iterations so the\n  non-gating speedup baselines run at reduced counts.\n- docs/dev/kep-0003-acceptance-gate-worksheet.md: filled with the macOS tables,\n  rule evaluations, and outcome.\n\nmacOS reads 4 Between (stays gated): Rule 1 (Racket) fails -- only IP-MAP\nclears the 25% CI-lower bound (at 64 MiB); IP-BAND and IP-MATMUL are\ncompute-bound -- and Rule 2/3 (Erlang/Absent) fail because IP-MAP, FO-TREE,\nFO-SLICE are far above 10%. Lever D barely moves the shares: the high-share\nworkloads are byte-opaque flonum vectors / trees a bytevector side-heap can't\nshare -- the pre-KEP-0003 walk tax.\n\nBecause macOS is Between, the combined two-machine outcome is Between\nregardless of Linux (agreement or disagreement both resolve to Between per\n§5). The Linux x86_64 half is still worth collecting for a published\ntwo-machine dataset (it was not driveable from the collecting session -- no\ndroplet shell); run the same run-gate.py command on an x86_64 >=8-core box at\nb6d349c0 and feed its CSV to classify.py alongside this one.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-15T05:43:58+05:30",
          "tree_id": "a3050a1c8bbd269afda1a0e6ca9ed4be60f07a91",
          "url": "https://github.com/kaappi/kaappi/commit/5d6b99e80c15f81a2bd861d0c5226bdddbdc1eb7"
        },
        "date": 1784075732060,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.451313,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.245255,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.914158,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.471152,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006425,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.054065,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.504156,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070031,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.386996,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 2.00325,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.596768,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.434625,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.886565,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.715828,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045503,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "5e93ee1258175a41c9feb3498540b3128891ff19",
          "message": "Ship envelope elision lever C (immediate fast path) as the default (#1472) (#1550)\n\nThe KEP-0002 Phase 7 P3 micro-benchmark decided lever C — immediate\nmessages skip the per-message envelope heap — ships: it clears the\npre-registered \"immediates >= 2x lever A on fixnums\" bar by an order of\nmagnitude (measured 28x ReleaseFast / 108x ReleaseSafe), and the KEP-0002\nUQ-1 amendment recorded C as ship. Until now the fast path only ran under\n-Dchannel-instrument as the gate lever `c`; production sends still built a\nfull private mini-heap for every fixnum/boolean/char/flonum/nil message.\n\nMake the immediate elision unconditional in the shipped build. It is\nprovably transparent: deepCopy of a non-pointer returns it unchanged\n(gc_deep_copy.zig, `if (!isPointer) return src`), so the full path only\never built an empty heap and stored the same value back — the fast path\ncarries that value inline and skips the GC struct + ~8 KiB root buffer.\nreceive() and deinit() already handle the null-heap envelope.\n\nKeep it lever-selectable under -Dchannel-instrument so the frozen gate\nprotocol's `none` baseline still forces the pre-C full-envelope path and\nstays reproducible; only the shipped (non-instrument) build changes.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-15T06:47:02+05:30",
          "tree_id": "b25ef5b763afeba13bcea3b35c4a03240225d63c",
          "url": "https://github.com/kaappi/kaappi/commit/5e93ee1258175a41c9feb3498540b3128891ff19"
        },
        "date": 1784080187745,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.37258,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.752535,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.936722,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.487064,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006776,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.054918,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.511675,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070385,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.517933,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.955933,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.629986,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.442505,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.979883,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.760123,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045277,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "e806e5568785615f7e6d0f5089f6fd4a6d1b13f1",
          "message": "Cache LLVM eval-fallback compilation per call site (#1494) (#1552)\n\nForms the native backend cannot lower (letrec, cond, case, do, guard,\nquasiquote, named let, and fallback lambdas) are serialized to a source\nstring and run via @kaappi_eval, which re-parses and re-compiles that\nstring on every execution. Inside a loop body or a frequently-called\nnative function — most commonly an inner variadic lambda, which no\nclosure tier accepts and which keeps its enclosing function native —\nthat is a severe, easily-overlooked cliff.\n\nAdd @kaappi_eval_cached: the emitter allocates one global slot per\nfallback call site; the first execution parses and compiles the form\nonce, permanently GC-roots the resulting Function, and stashes it in the\nslot, and every later execution runs the cached Function directly. The\ncompiled bytecode still resolves globals by name at run time, so a\nfallback that first republishes the enclosing frame as globals observes\nthe current values on each execution — behavior is identical to today.\n\nThe cached Function is rooted via extra_roots (which, unlike the LIFO\nshadow stack, holds a program-lifetime root) because the call-site slot\nis a module global the collector never scans. Only the main runtime\nthread touches a slot — the guard precedes both the read and the write —\nso a spawned SRFI-18 thread never caches a Function from a child heap or\nruns a main-heap Function under its own VM. Quoted heap constants stay on\nplain @kaappi_eval; building those once is the separate #1495 change.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-15T06:57:00+05:30",
          "tree_id": "afff88ac6abf20bf0d6bf7fbfd9bb93024ceaf4b",
          "url": "https://github.com/kaappi/kaappi/commit/e806e5568785615f7e6d0f5089f6fd4a6d1b13f1"
        },
        "date": 1784080530225,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.527297,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.171142,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.974894,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.734468,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006326,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.054168,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.509067,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070075,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.424427,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 2.011005,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.581451,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.435266,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.816263,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.716132,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.046214,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "09f083c3b4bed806b6432d577073c61452ef9f46",
          "message": "Index parked fibers by waited-on object for O(1) wakes (#1530) (#1553)\n\nAfter #1525 made fiber dispatch/spawn O(1), the five wake paths\n(wakeWaiters, wakeChannelWaiters, wakeMutexWaiters, wakeOneCondVarWaiter,\nwakeAllCondVarWaiters) still linearly scanned every slot in\n`sched.fibers.items` on each call. On a join-, channel-, or condvar-heavy\nworkload holding thousands of live fibers, each completion/send/close paid\nan O(fiber count) scan — the residual super-linearity #1477 flagged once\ndispatch was already O(1). `wakeWaiters` alone runs on every fiber\ncompletion and scanned all N fibers even with zero joiners, making\nspawn+join O(N^2).\n\nAdd a per-scheduler secondary index `waiter_index` mapping a waited-on\nValue (a fiber to join, a channel, a mutex, a condition variable) to the\nslot indices of the fibers parked on it, so a wake is O(waiters-on-that-\nobject). enrollWaiter feeds it at every local park site; wakeOn is the\nsingle choke point behind all five entry points, with doWake applying the\nper-fiber transition identically on both the index and fallback paths.\n\nDesign points:\n- Store slot indices, not *Fiber. A since-reused or terminated slot is\n  caught by the same validation the ready ring uses at pop (slot still owns\n  its index, still .waiting, still on the key), so a terminated waiter needs\n  no explicit de-index — unlike the pointer-holding shared_waiters registry.\n- The broadcast wakes require a complete index (a \"wake all\" cannot fall\n  back on an empty index the way #1525's lossy ready ring can). Enroll at\n  all nine local park sites; the four shared-channel parks (woken via\n  sweepSharedWaiters) and thread-sleep!'s VOID-keyed timed wait are\n  deliberately excluded, and the mutex/condvar retry spins re-enroll.\n- An enroll allocation failure sets a sticky waiter_index_degraded flag and\n  the wake paths fall back to the exact pre-#1530 scan, so OOM degrades to\n  old behavior instead of a lost-wakeup hang — no per-site park rollback.\n- A tail-check dedup (skip if the list tail is already this slot) bounds the\n  retry spins without a per-fiber flag, which would carry an address-reuse\n  ABA hazard.\n\nSame-machine bench-fibers A/B: spawn+join at 10,000 fibers 18,606 ns ->\n2,309 ns (~8x) and flat across 100/1k/10k instead of super-linear.\n\nAdds six tests_scheduler.zig unit tests (broadcast, hand-off, terminated-\nslot skip, tail-dedup + re-park, join-result hand-off, degraded scan) and\ntests/scheme/smoke/fiber-many-waiters-one-object-1530.scm (500 fibers block\non one channel; close wakes all). Full unit suite, targeted gc-stress on the\nconcurrency tests, and the full Scheme + R7RS suites all green.\n\nhasRunnableFibers and wakeIoWaitersOnFd are left as-is, matching the issue's\nscope: the former early-exits and is O(n) only in the genuine no-progress\ncase, and the latter keys on fd, not waiting_on.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-15T01:32:41Z",
          "tree_id": "62504b0b5aa54df7fcd52d49dedc7328bd79cb3e",
          "url": "https://github.com/kaappi/kaappi/commit/09f083c3b4bed806b6432d577073c61452ef9f46"
        },
        "date": 1784080944473,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.393397,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.805135,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.943831,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.592052,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00746,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.054286,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.513068,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068538,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.52447,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.95959,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.592466,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.433348,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.797703,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.724979,
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
          "id": "4c8e209b63da89b16fc32cba26b07a044144a747",
          "message": "Thread full source spans through to runtime diagnostics (#1506) (#1557)\n\nReader errors already carried line and column, but compile and runtime\nerrors reported file:line only, and nothing carried end positions.\nStructured diagnostics, precise editor squiggles, and automated fixes\nall need full spans.\n\nTrack (line, col, end_line, end_col) for every datum the reader can key\non heap identity (pairs, vectors) and thread it through the pipeline:\n\n- Reader records a full span per datum in gc.source_spans (was the\n  line-only source_lines), computed in a single scan.\n- IR nodes carry the span (Annotations.span); the compiler emits the\n  start column into the bytecode line table (LineEntry gains col).\n- Runtime errors map the failing instruction offset back to line:col via\n  Function.locForOffset and report file:line:col.\n- Compile errors report the innermost failing form's span through a\n  threadlocal channel, so a nested error points at the inner form (e.g.\n  the (if) in (define (f) (if))), with a full start/end range under\n  --diagnostics=json.\n\nThe .sbc bytecode cache format is bumped to v9 for the new column; a\nversion mismatch makes the loader ignore and recompile stale caches\ncleanly. Runtime debug info carries the start column only — end\npositions stay a reader/compile-time concern, per the acceptance\ncriteria.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-15T09:39:42+05:30",
          "tree_id": "2ef9485be509029b1f158afaf90ab4311115ef49",
          "url": "https://github.com/kaappi/kaappi/commit/4c8e209b63da89b16fc32cba26b07a044144a747"
        },
        "date": 1784090285454,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.339777,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.329826,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.920426,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.459968,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006409,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.054901,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.504753,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.0697,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.437021,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.968079,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.601023,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.43491,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.8664,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.712531,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042947,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "c2de085ae05b10e1a6b7adc004f8c96ab0d49bd7",
          "message": "Build quoted heap constants once via a per-site cache (#1495) (#1556)\n\nQuoted pairs/vectors were emitted as (quote …) strings run through\nkaappi_eval on every execution, re-parsing and re-consing the literal\neach time. This was both a hot-path cliff and a correctness divergence:\nthe interpreter compiles a quote to a single constant-pool entry, so\nevery evaluation of one literal returns the same object, whereas the\nnative backend rebuilt a fresh copy — (eq? (f) (f)) was #f natively but\n#t in the interpreter.\n\nkaappi_quote_cached builds each quoted heap constant once, permanently\nroots it, and memoizes it in a per-call-site global slot; later\nexecutions return the cached object. This is the data analogue of the\n#1494 eval cache (which caches a compiled Function). Per-site slots\nreproduce the interpreter's identity in both directions: one literal\nread twice is eq?, two textually distinct literals are not.\n\nChild SRFI-18 threads build the constant fresh each execution\n(cross-heap safety), the same carve-out as #1494.\n\nCloses #1495.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-15T09:39:20+05:30",
          "tree_id": "cbb7d14193f6cbbfd17ef17e4dcd0a83f820f823",
          "url": "https://github.com/kaappi/kaappi/commit/c2de085ae05b10e1a6b7adc004f8c96ab0d49bd7"
        },
        "date": 1784090469520,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.102104,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.994623,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.936493,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.438595,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00675,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.053029,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.511107,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068243,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.264237,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.994195,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.540385,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.48131,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.751443,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.85062,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.046932,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "8a369b4829afb664127d1d40510624c847236ebe",
          "message": "Lower cond/case/do natively in the LLVM backend (#1564)\n\ncond, case, and do desugar into machinery the emitter already lowers well —\nif-style block/phi chains and a self-branching loop — yet they were routed\nthrough kaappi_eval like any other unlowerable form. That made a plain\n`(define (f n) (cond ...))` serialize the whole function to the interpreter, a\nneedless per-call cliff.\n\nEmit them natively when every sub-form is emittable in the current lexical\nscope, gated by exprNativeEmittable. A form that reaches an unlowerable\nsub-form (a macro use, a passthrough special form, a nested eval-fallback\nform, a lambda, or a => clause) still falls back — at top level as a\nwhole-form eval (correct in the global environment), and inside a native\nlet/lambda body by signalling the enclosing form to abandon native\ncompilation as a unit, so a lexical scope is never split across the\nnative/interpreted boundary (the #827 discipline).\n\nBecause these forms are no longer eval-fallback forms, the closure tiers'\nfree-variable analysis must scope their clauses, or a capture hidden in one\ndegrades to a global lookup; walkSexpr/nodeHasFreeVars/collectNodeFreeVars now\ndescend into cond/case/do with correct binder scoping. The emitter also\nconsults the VM macro table so a macro use inside these forms reaches the\ninterpreter that can expand it.\n\nRejecting lambdas inside do sidesteps its fresh-binding-per-iteration\nsemantics: with no closure able to capture a loop variable, in-place mutable\nallocas are observably equivalent.\n\nVerified: full unit suite, e2e parity (incl. new cond/case/do programs), the\n1857-case Scheme suite, and 110 randomised interp-vs-native programs all pass;\ntail-recursive cond keeps its self-tail-call loop.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-15T12:59:02+05:30",
          "tree_id": "79bcb18ccef5b6009de8bce2c6377ea7a366a648",
          "url": "https://github.com/kaappi/kaappi/commit/8a369b4829afb664127d1d40510624c847236ebe"
        },
        "date": 1784102097796,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 2.48313,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 5.440743,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.49062,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.484527,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004896,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.03202,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.279334,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.041158,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.059399,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.067303,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 0.936405,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.304754,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.053978,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.765834,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.027789,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "5a2acef2006a24341e882901b0bc208347fb91bf",
          "message": "Grow native lambda analysis buffers + loop variadic self-tail-calls (#1498) (#1567)\n\n* Grow native lambda analysis buffers + loop variadic self-tail-calls (#1498)\n\nThe native lambda emitter (src/llvm_emit_lambda.zig) bailed to kaappi_eval\nwhenever a function exceeded a fixed-size stack buffer, and compiled\nself-tail-recursion as a loop only for non-variadic functions. Both were\narbitrary cliffs on otherwise-compilable code.\n\nPart 1 — remove the fixed analysis buffers. The per-function scratch arrays\n([16] params, [64] body nodes, [16] free vars, [17]/[18] name buffers, [32]\nformal names, FreeNameWalk's [64] bound / [16] output, BoxAnalysis's [16]/[17]\nflags) now grow on the emitter's existing arena. The only ceiling left is the\nruntime's real one: a native closure's arity and each upvalue index are u8, so\na function past 255 fixed params or captured upvalues still falls back.\n\nPart 2 — loop variadic self-tail-calls. A self-call in tail position now branches\nback to the body label for variadic functions too, rebuilding the rest list from\nthe args past the fixed arity (reusing the cons idiom) before the branch. The\nrest builder moves to the entry block so the loop does not re-run it.\n\nAlso fixes a pre-existing latent GC bug the loop would hit constantly: the\nvariadic rest list was built in a bare, un-rooted alloca, so a body allocation\nthat did not itself mention the rest list could collect the freshly-consed\nspine (native output diverged from the interpreter under GC pressure). The rest\nslot is now GC-rooted for the frame (frame_box_roots generalized to\nframe_entry_roots) and popped before every ret, including tail-call rets.\n\nTests: new tests_native.zig emit tests for the over-limit cases and the\nvariadic loop; new tests/e2e programs (native-many-params, native-many-captures,\nnative-variadic-tail). zig build test, gc-stress native tests, and\ntests/e2e/run-e2e.sh (35/35) all green.\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>\n\n* ci: raise macos-latest test job timeout to 30 min\n\nThe macOS runner is ~1.5x slower than the Linux ones: unit tests (~6 min) plus\nthe Scheme suites (~11 min) alone take ~17 min, so the job routinely drifts past\nthe default 20-min cap and is cancelled mid-run — a pre-existing flake seen on\nmain, not tied to any one PR. Bump macos-latest/ReleaseSafe to 30 min, matching\nthe timeout already used for the Debug and riscv64 jobs. Applied as an include\nentry that merges the timeout into the existing combination (no extra job).\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>\n\n* ci: set macos timeout via an os-aware expression, not a merged include\n\nThe previous commit added the macOS 30-min cap through a matrix `include` entry\nthat merges into the existing macos-latest/ReleaseSafe combination. Whether such\na merge exposes `timeout` as `matrix.timeout` (vs. being dropped) is a subtle\nmatrix-expansion detail the auto-generated job name did not confirm. Replace it\nwith an explicit `matrix.os == 'macos-latest'` check in the timeout expression,\nwhich is unambiguous and does not depend on include-merge semantics.\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-15T15:42:19+05:30",
          "tree_id": "4851bb46928d76c07f37225544d34bf9d66cebee",
          "url": "https://github.com/kaappi/kaappi/commit/5a2acef2006a24341e882901b0bc208347fb91bf"
        },
        "date": 1784112085116,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.374728,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.821511,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.899459,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.467845,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006345,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.053545,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.507518,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069311,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.463918,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.973989,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.573364,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.432518,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.838532,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.704451,
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
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "64d2e5d7c7b76a4fc81dbd1f64b3b2f4a136b060",
          "message": "Add `kaappi doctor` installation and environment self-check (#1513) (#1569)\n\n\"Why doesn't `(import (kaappi json))` work?\" has a fixed set of answers —\nlibrary-path resolution, thottam state, a missing native library, the wrong\nbinary on PATH — that were previously diagnosed by hand. Making the toolchain\ncheck itself lets both new users and agents go from a broken setup to a fix\nusing only documented CLI output, the operational test of the machine-\nlegibility epic (#1503).\n\n`doctor` is a meta-command like `explain` and `test`: it inspects the\nenvironment and runs no user code, so it dispatches before any VM/GC/library\nsetup exists. It reports PASS/WARN/FAIL per check across six groups (binary,\nlibrary search path, package manager, native backend, REPL, FFI), each failure\ncarrying an actionable suggestion, in a human table or one `--json` object.\n\nThe exit code is nonzero only on FAIL. WARN describes a degraded-but-usable\nenvironment (no libraries installed yet, no C compiler) and must not fail\nscripts or CI; the one FAIL is an explicit `KAAPPI_LIB_DIR` that does not\nresolve, an unambiguous misconfiguration. When a compiler and `libkaappi_rt.a`\nare both found, a smoke link against the archive proves the native toolchain\nend to end — run in a private 0700 temp dir, and skipped under the test binary\nso unit tests stay hermetic.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-15T17:17:41+05:30",
          "tree_id": "3fe0bd1dd1724c2173013e7284569ce186d5f1d0",
          "url": "https://github.com/kaappi/kaappi/commit/64d2e5d7c7b76a4fc81dbd1f64b3b2f4a136b060"
        },
        "date": 1784117780260,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.374633,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.941094,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.894415,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.424641,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006302,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.055397,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.495753,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069199,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.509009,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.937368,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.587685,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.433354,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.965359,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.682319,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042603,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "9bb1b63fefab216265286c17e4765d379d527f46",
          "message": "Add `kaappi features` capability-discovery subcommand (#1517) (#1570)\n\n`kaappi features [--json]` answers an agent's first question -- \"what am I\nworking with?\" -- at the CLI boundary, the way KEP-0004 already answers it\ninside Scheme via cond-expand. It reports version + git build id, target\ntriple, build mode, the compiled-in subsystems, built-in vs portable SRFIs,\ninitial VM/GC limits, and whether --sandbox is available. JSON is the primary\ninterface; a human-readable table is the secondary.\n\nThe point is that this output can never drift from the rest of the toolchain,\nbecause every field is derived, never re-typed:\n\n- features = types.platform_features, the exact table cond-expand and R7RS\n  (features) resolve against (a unit test asserts equality; features.sh proves\n  the CLI output equals the runtime (features) procedure).\n- built-in SRFIs come from the library registry -- the srfi_* tags of\n  primitives.Lib plus the new library.extra_std_libraries (which also de-dups\n  the srfi.9 / scheme.case-lambda registration shared by both registrars).\n- portable SRFIs are generated at build time by scanning lib/srfi/*.sld, so a\n  new .sld updates the output automatically.\n- build id is a best-effort git short hash (+ -dirty), \"unknown\" on failure.\n\nDispatched before VM setup (like explain/test), native-only. Wires the new\nsubcommand into --help, the bash/zsh/fish completions, README, and CLAUDE.md;\ndocuments it in docs/dev/features.md.\n\nPart of the machine-legibility epic #1503.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-15T12:24:22Z",
          "tree_id": "c5994c3a0a0a11d07cb95157f4571138bd51a637",
          "url": "https://github.com/kaappi/kaappi/commit/9bb1b63fefab216265286c17e4765d379d527f46"
        },
        "date": 1784120217819,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.314863,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.844526,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.893171,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.426566,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006425,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.053468,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.507451,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068782,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.456172,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.959031,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.580156,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.428406,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.810959,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.703531,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043951,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "e95f6b51812e94eae19f5a1b98de85b7a3b685f4",
          "message": "Guaranteed native mutual tail calls via tailcc + musttail (#1499) (#1572)\n\nSelf-tail-recursion in the LLVM backend was already constant-stack (an\narg-overwrite branch loop), but a tail call to *another* function was not:\nthe uniform entry reads its parameters from a caller-frame `%args` array,\nand a real tail call tears that frame down, so the callee would read freed\nstack. `even?`/`odd?`-style mutual recursion therefore grew the stack and\neventually overflowed. Guaranteed TCO needs arguments passed by value, not\nvia a pointer into the caller's frame — an ABI change.\n\nA fixed-arity, non-variadic, non-boxed named function (arity <= 8) now emits\ntwo LLVM functions: a `tailcc` register-argument fast entry holding the body\n(it copies the registers into a local `%args` array, so the existing body\nmachinery is reused unchanged), and an `internal` uniform-ABI trampoline for\nindirect dispatch. Direct tail calls between fast entries emit `musttail call\ntailcc` — LLVM-guaranteed constant stack (`tailcc` relaxes musttail's\nprototype-match rule, so different-arity mutual calls are legal). Self-\nrecursion keeps its loop; variadic/boxed/over-arity/closure functions keep the\nuniform entry unchanged.\n\nForward references (a callee defined later) resolve through a syntactic\npre-scan that reserves stable `@r{i}.fast` names for single-definition\ntop-level functions; a finalization stub covers any reserved name that falls\nback to the interpreter, so every musttail target links. A reference to a\nreserved name counts as a global in free-variable analysis, so the caller\nstill compiles natively.\n\n`musttail` is gated (`mustTailSafe`) on being in a fast entry, in tail\nposition, and outside any rooted `let`, so it never strands shadow-stack\nroots. The whole feature is gated per target on aarch64/x86_64, whose LLVM\nbackends support tailcc/musttail; other hosts keep the prior uniform ABI.\n\nVerified: 50M-deep mutual recursion runs native in flat ~3 MB RSS (would\notherwise overflow); GC-safe under forced collection; full unit suite and\n36/36 e2e programs green, incl. a new native-mutual-tail e2e whose\ninterpreter diff doubles as the constant-stack regression check.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-15T19:48:43+05:30",
          "tree_id": "b36f7ffa43c838d4c6fde4e11402061af20b8569",
          "url": "https://github.com/kaappi/kaappi/commit/e95f6b51812e94eae19f5a1b98de85b7a3b685f4"
        },
        "date": 1784127018206,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.671164,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.889918,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.881979,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.15441,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006686,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.051003,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.461468,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.065116,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.477426,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.775696,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.461,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.40386,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.913235,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.913307,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.041249,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "ebd9235a4588a8a473f776aa33de20991899a63d",
          "message": "Bound fuzz generator gates by instruction count on emulated targets (#1573) (#1574)\n\nThe riscv64-test CI job cross-compiles the unit-test binary to riscv64-linux\nand runs it under QEMU user-mode (~10-30x slower than native). The fuzz\ngenerator \"programs evaluate without error\" gates in tests_fuzz.zig bound each\ngenerated program by a 100 ms wall clock, so under emulation a correct-but-slow\nprogram blows the deadline, lands in the .scheme_error bucket, and pushes the\npass rate below the 90% gate -- a spurious failure that needs a manual rerun\nand, while it flakes, nearly doubles the job's wall time.\n\nThis is the same wall-clock-vs-slow-execution class already fixed for gc-stress\n(#1447/#1449), where the gates bound by instruction count instead -- a\nspeed-independent measure identical no matter how fast each instruction runs.\nThat treatment was never extended to the emulated riscv64 path.\n\nDetect a cross-compiled target in build.zig (resolved target arch/os != host)\nand expose it as build_options.emulated_target, then fold it into the existing\ngc-stress gate: speed_independent = gc_stress or emulated_target now drives both\nthe loose 120 s wall-clock backstop and the 2M-instruction bound. The 2M budget\nis reused unchanged (it clears the largest correct generator program by ~50x).\nemulated_target is consumed only by tests_fuzz.zig; the shipped binary is\nunaffected. Skipping was the alternative, but instruction-count bounding keeps\nthe generator-correctness coverage on the emulated path.\n\nAdds a regression test pinning the invariant: under gc-stress or emulation the\nbound is instruction-count (limit set, deadline loosened); on native builds the\ntight 100 ms deadline and no instruction cap are retained. Without the\nemulated-target half it fails on the riscv64 CI job instead of the gates\nflaking silently.\n\nVerified: native 1037/1037; gc-stress gates green; and a genuinely\ncross-compiled x86_64-macos build under Rosetta (emulated_target=true) runs all\nthree generator gates plus the differential oracle green (12/12) under the\ninstruction-count bound.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-15T20:59:56+05:30",
          "tree_id": "874e80307c4eb4c5bdae8f795219bf77b6e926d6",
          "url": "https://github.com/kaappi/kaappi/commit/ebd9235a4588a8a473f776aa33de20991899a63d"
        },
        "date": 1784131268874,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.314645,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.364966,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.938721,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.450346,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006465,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.054231,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.512432,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068736,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.454546,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.986484,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.566969,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.433295,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.80524,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.723125,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044285,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "807fd64ac9c6e38d4e9d492a0117a8958a8d3a90",
          "message": "Add `kaappi fmt` canonical comment-preserving formatter (#1518) (#1571)\n\nA canonical formatter makes diffs meaningful, ends style review, and gives\nagents format-on-save invariance — the job `zig fmt` does for the compiler's\nown Zig, which nothing did for Scheme. This is the final item of the\nmachine-legibility epic (#1503).\n\nComments are not datums, so the ordinary reader (which discards them) cannot\ndrive a formatter. `fmt` therefore has its own concrete-syntax reader\n(`src/fmt.zig`): a lexer that emits every lexeme — line/block/`#;` comments and\nthe blank-line structure between them — and a parser that builds a CST keeping\natom text verbatim, so number/character/string spellings are never rewritten.\n`src/fmt_print.zig` lays the CST out: 2-space R7RS indentation, single-space\nseparators, closing parens gathered, forms reflowed to 80 columns using the two\nstandard Scheme shapes (body style for define/lambda/let/when/case/…, call\nstyle for calls/cond/vectors/unknown heads).\n\nLayout only rearranges whitespace between lexemes, so the datums a program reads\nare invariant by construction — and that is also checked at runtime: before\nwriting any file, `verifyRoundTrip` re-reads the original and the formatted text\nwith the real reader and compares the datum sequences with `equal?`. On any\nmismatch it refuses to write, so a bug here can never corrupt a source file.\n\n`--check` writes nothing and exits nonzero listing paths that need formatting,\nfor CI; with no files, stdin is formatted to stdout.\n\nVerified over all 558 .scm/.sld files under tests/scheme and lib: zero semantic\ndrift, zero syntax errors, and 558/558 idempotent. Tests: src/tests_fmt.zig\n(exact cases, comment/blank-line preservation, idempotence + round-trip over\ngrammar-fuzzer programs) and tests/scheme/fmt/fmt.sh (CLI behaviour plus the two\ncorpus-wide properties), wired into run-all.sh. Documented in docs/dev/fmt.md.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-15T15:59:54Z",
          "tree_id": "3ec96ad2dae3fb6fb3d1326543572ec1fb4b383a",
          "url": "https://github.com/kaappi/kaappi/commit/807fd64ac9c6e38d4e9d492a0117a8958a8d3a90"
        },
        "date": 1784133184648,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.401971,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.036704,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.920499,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.46445,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006526,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.054155,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.50658,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069704,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.395191,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.989996,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.570437,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.434811,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.849904,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.682599,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043074,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "020289ab9c636ae761ad98d274b6656f09854cbb",
          "message": "Add crash-reporting panic handler with context breadcrumb (#1575)\n\nWhen a bug is in kaappi itself, ReleaseSafe dies with a raw Zig panic and\ntrace. Better than a silent segfault, but the user gets no guidance and no\nversion context, and we get reports that arrive unreproducible or not at all.\n\nAdd a custom panic handler for the user-facing binaries (kaappi, thottam):\neach root file sets `pub const panic = crash.PanicHandler(\"<name>\")`, a\nFullPanic that prints a banner then delegates to defaultPanic so the message\nand full stack trace are preserved. The banner names whose bug it is, the\nexact build (version, arch-os, build mode), the pipeline stage and file in\nflight, and where to report it.\n\nThe `while:` line is driven by a near-zero-cost breadcrumb (a plain enum + a\nslice, read only from the panic handler) updated at reading/expanding/\ncompiling/executing boundaries in runFile, runStdin, the embedded path, the\nREPL, the pipeline dumps, and the native compiler. It is omitted when idle,\nso thottam (no Scheme pipeline) shows only the build + report lines.\n\n`--panic-test[=<stage>]` is an internal, undocumented hook that deliberately\npanics so CI can verify the banner. It is intentionally not Debug-gated: the\nerror suite runs against the shipped ReleaseSafe build, which is the path a\nreal user hits and the mode the banner names.\n\nCloses #1514.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-15T23:26:39+05:30",
          "tree_id": "84f006da0d0a6da8a508cb085e71f31d764fdd0e",
          "url": "https://github.com/kaappi/kaappi/commit/020289ab9c636ae761ad98d274b6656f09854cbb"
        },
        "date": 1784140150277,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.363256,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.415797,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.940195,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.490336,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006469,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.054269,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.50616,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.07021,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.459541,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.994219,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.596976,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.442638,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.867736,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.775098,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044849,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "1154d5c9e96c07f234baa6f9153af9163f9fdccb",
          "message": "Cache transparency: `kaappi cache status|clear` + build-id cache keys (#1516) (#1576)\n\n* Add cache transparency: `kaappi cache status|clear` + build-id keys (#1516)\n\nThe `.sbc` bytecode cache was keyed on source hash + version *string*. During\ndevelopment the version string doesn't change between rebuilds, so a freshly\nrebuilt kaappi silently executed bytecode compiled by the previous binary —\nmanufacturing phantom bugs and masking real fixes. The standing workaround\n(\"delete the cache before testing compiler changes\") was tribal knowledge. For\nan agent, an invisible cache is a correctness hazard, not a convenience.\n\nHonest keys: `compilerHash` now folds in the git build id (short HEAD hash +\n`-dirty`) via a pure `compilerHashFor`, so any recompiled binary misses a cache\nthe old binary wrote. Two clean builds of the same commit still share a key.\n\nCentral store: the run-cache moves from co-located `file.sbc` to a single\n`$KAAPPI_HOME/cache` (default `~/.kaappi/cache`), keyed by absolute source path.\nThe `.sbc` header (VERSION 9→10) records the producing build id and source path\nfor reporting. `--compile` outputs are unchanged — explicit artifacts, not the\ncache — so the `--no-ir-opt --compile` poisoning guard is no longer needed and\nis removed.\n\nNew subcommands (`src/cache.zig`, dispatched before VM setup like doctor):\n  kaappi cache status   location, entry count, total size, and per entry the\n                        size, producing build id (current/stale), source path\n  kaappi cache clear    remove every entry — the one supported way to wipe it\n\nTests: unit tests prove the build-id key changes on same-version/different-build\nand that a foreign-build entry misses on load; `renderStatus`/`clearDir` are\ncovered over a temp dir; a new `cache-transparency-1516.sh` covers status/clear\n+ HIT-after-MISS end-to-end. `run-all.sh` isolates `KAAPPI_HOME` so the suite\nnever touches the developer's real cache. Fuzz `.sbc` fixture regenerated for\nthe v10 header.\n\nDocs: `docs/dev/cache.md` documents the key, location, invalidation, and bypass;\nCLAUDE.md and the project-notes footgun entries updated to \"fixed by build-id\nkeys\". HIT/MISS under `--timings` remains tracked in #1515.\n\nPart of #1503.\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>\n\n* cache: get entry size portably in cache clear (fix Linux build)\n\n`std.c.fstatat`/`std.c.Stat` are macOS-only in this Zig std — on Linux the\nglibc `__xstat` indirection leaves `std.c.fstatat` typed `void`, so the cache\nbuild failed to compile on every Linux target. Read the file length through\n`file_utils.readWholeFile` (the same portable path `renderStatus` already\nuses) instead of stat'ing, avoiding per-OS stat code for a cosmetic byte total.\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-15T23:56:47+05:30",
          "tree_id": "85dafc013bc586a500141db38b31db1f057d72e8",
          "url": "https://github.com/kaappi/kaappi/commit/1154d5c9e96c07f234baa6f9153af9163f9fdccb"
        },
        "date": 1784142068506,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.380795,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.748018,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.963922,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.564705,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006372,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.054475,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.527443,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070459,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.507386,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 2.035782,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.600623,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.445347,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.874458,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.771672,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044364,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "9e797a76817dab6c47237ac5ba5aceca0ce5f87a",
          "message": "LLVM backend: bind fixed-arity define values as native closures (#1500) (#1577)\n\nA natively-compiled define's global value was still eval'd even though @f\nwas already emitted for its direct call sites. Materialize a fixed-arity\nfunction's value as a native closure over that compiled entry instead\n(emitNativeFnClosureValue), so value uses (map/apply/eq?/returning) run\nnative code and startup skips the per-program parse+compile. Native closures\nnow print as #<procedure name> to match the interpreter's closures.\n\nThe value path runs native @f bodies from new contexts, exposing two issues:\n\n- vm.execute is not re-entrant (it resets to frame 0). A native value whose\n  body reaches an eval/quote fallback, invoked from inside an outer execute,\n  clobbered the suspended outer form. runTopLevelFunction runs the nested\n  thunk through the re-entrant callWithArgs path when the VM is already\n  executing, leaving the outer form intact.\n\n- An eval fallback republishes captured params as globals\n  (bindParamsAsGlobals), which aliases across activations -- a pre-existing\n  native-backend limitation that a native value would widen to the common\n  (define a (f 1)) (define b (f 2)) pattern. Gate the materialization on\n  NativeLambda.has_eval_fallback: a function whose body has a code eval\n  fallback keeps its correctly-capturing interpreter-closure value. A quoted\n  constant is not a code fallback (it can't alias, and the re-entrancy fix\n  covers building it), so quote-body functions stay eligible.\n\nCloses the last child of #1491. The 36 tests/e2e/programs drop from 59 to 27\nemitted eval-fallback sites (20 now at zero). Unit suite, e2e (37/37), and\nthe scheme suites are green.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-15T19:13:28Z",
          "tree_id": "ba3f0a1e2cddcf4a8fbe0cee3590f95ef37d1d56",
          "url": "https://github.com/kaappi/kaappi/commit/9e797a76817dab6c47237ac5ba5aceca0ce5f87a"
        },
        "date": 1784144805135,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.03654,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.876272,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.92127,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.456583,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006716,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.053109,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.504195,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068114,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.214932,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.96491,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.516778,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.477943,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.731698,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.903735,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045401,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "dc9233ddadd086537e3b2520ad041f5b20cf0903",
          "message": "Add `--timings`: per-stage pipeline timings + cache HIT/MISS visibility (#1515) (#1578)\n\n`--profile` profiles the user's program; nothing reported how long kaappi's\nown pipeline stages take, or whether a run was served from the invisible `.sbc`\ncache — the same cache whose staleness (#1516) has cost real debugging hours.\n\n`--timings` / `--timings=json` give `zig build`-style transparency on stderr:\nper-stage wall time (read / expand / lower / optimize / emit / execute, plus\nnative `llvm-emit` / `link`) and, as the headline, an always-present cache line\nstating HIT or MISS and the path. JSON is for CI regression tracking alongside\nthe benchmark workflows. Wired into the run, `--compile`, and native `compile`\npaths.\n\nThe pipeline is not flat — macro expansion is interleaved with emission (a macro\nuse lowers to a passthrough node expanded and re-compiled during\n`compileFromNode`), so a naive accumulator would double-count nested regions.\n`src/timings.zig` uses a self-time profiler stack that credits wall time to the\ninnermost active stage, so the buckets are disjoint regardless of nesting or\nwhich driver is on top. Instrumentation lives at the shared chokepoints\n(`ir.lowerAndOptimize`, `expander.expandMacro`, `compiler.compile`,\n`native_compiler`, the run/compile drivers), so every caller is covered at once.\n\n`enabled` is threadlocal (like `ir.optimize_enabled`) so child SRFI-18 threads\nneither race on nor pollute the buckets, and each begin/end is a single\npredicted branch when the flag is absent — no measurable overhead on a normal\nrun.\n\nTests: `src/timings.zig` unit tests drive the stack on a deterministic clock\n(gated on `builtin.is_test`) and check text/JSON rendering; the end-to-end\n`tests/scheme/timings/timings-1515.sh` validates the JSON shape (parsed with\npython3 when available), HIT/MISS transitions, cache-off reasons, the compile\nshape, and that timings never leak onto stdout. Full suite 1866 pass / 0 fail;\nLinux and WASM cross-builds green. Part of #1503; see docs/dev/timings.md.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-15T20:43:43Z",
          "tree_id": "385ff3f291d7c92322d3493e5ca266296593df5b",
          "url": "https://github.com/kaappi/kaappi/commit/dc9233ddadd086537e3b2520ad041f5b20cf0903"
        },
        "date": 1784150296144,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.397693,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.63466,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.921916,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.495434,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006683,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.054256,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.507712,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070132,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.400486,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.979366,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.584042,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.44148,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.851259,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.748725,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044948,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "cd35f75ddaaa28a7ae1891a9861bdb772dfb01df",
          "message": "Add P1 access-semantics codegen experiment (#1473) (#1579)\n\nStep 2 of research problem P1 (KEP-0003 Unresolved Question 2): does shared\nflat-buffer element access have to compile to `unordered` atomics to be\nsound, and what does that cost the numeric loops KEP-0003 exists to serve?\n\nMeasures six kernels (f64 fill/map/sum, i64 checksum, u8 fill/copy) under\nthree encodings (plain / unordered / monotonic) through Kaappi's exact\n`zig cc -O2` native pipeline, with the pre-registered Kalibera-Jones\nstatistics discipline (invocations x iterations, bootstrap CIs, order and\nenvironment-size randomization, no best-of-N).\n\nThe reason for the LLVM-IR-level harness: KEP-0003's shared buffers do not\nexist yet (building them is #1475, gated on this experiment), so the kernels\nare emitted as IR matching KEP-0003's stated element-access lowering and\ncompiled by the same `zig cc -O2` the backend shells out to.\n\nResult, by the pre-registered criteria: the hybrid. `unordered` element\naccess costs +55% to +2747% (bootstrap-CI lower bounds) versus plain on every\nceiling-validated kernel on aarch64-macos (auto-vectorization loss; the\nmemset/memcpy libcall idioms gap widest); the same codegen gap is confirmed\non x86_64-linux by cross-compile. f64_sum drops out as the control. The\ninterpreter tier is free (same machine instruction; ~107 ns/call dispatch\ndwarfs the access). x86_64 timing magnitudes are a documented follow-up.\n\nAdds benchmarks/access-semantics/ (generator, driver, evidence + K-J runner,\ninterpreter-tier control, results) and the report\ndocs/dev/kep-0003-access-semantics-experiment.md. No source changes.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-15T20:54:24Z",
          "tree_id": "f069ad39dbde5f4fdb7fa5ec349d30db49c45815",
          "url": "https://github.com/kaappi/kaappi/commit/cd35f75ddaaa28a7ae1891a9861bdb772dfb01df"
        },
        "date": 1784150643732,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.383447,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.397083,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.912371,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.518196,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006455,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.054121,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.509841,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070252,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.371202,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.978431,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.570691,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.44026,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.842646,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.765933,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.04445,
            "unit": "seconds"
          }
        ]
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
          "id": "8b45ff1f4bd555e704979cb5bf1f0c908396ffe5",
          "message": "Release v0.15.0",
          "timestamp": "2026-07-16T03:20:06+05:30",
          "tree_id": "bc208878edf2954b61571cf189bd0773917787da",
          "url": "https://github.com/kaappi/kaappi/commit/8b45ff1f4bd555e704979cb5bf1f0c908396ffe5"
        },
        "date": 1784153937636,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.396818,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.349196,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.92353,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.482152,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006452,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.053766,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.507792,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070086,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.371453,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.977191,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.584177,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.439926,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.842061,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.722572,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044077,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "109a2f5f4b576cc82885690855ceba1c269b1f15",
          "message": "KEP-0002 Phase 7 gate: Linux x86_64 dataset + completed worksheet (#1472, #1474) (#1580)\n\nCollects the second (Linux x86_64) reference machine for the frozen\nKEP-0002 Phase 7 gate benchmark, completing the two-machine dataset the\nKEP-0003 acceptance gate (#1474) reads. Run on a dedicated 8-physical-core\nx86_64 droplet (confirmed via lscpu, no SMT) at commit 807fd64a, K-J floor\n20x10, w=8, both levers -- zero timeouts or failures.\n\nLinux independently classifies as \"4 Between\", the same outcome macOS\nalready read, so the combined classification now holds by genuine\ncross-machine agreement rather than only via the cross-machine rule's\n\"one machine reading Between forces Between regardless\" fallback.\n\nOne amendment, mirroring the existing IP-MATMUL precedent: FO-DIGEST's\n64 MiB cell was excluded on this machine (both levers) after a timing\nprobe showed ~74-82s/iteration there, which alone would have added\nroughly 10 hours to the run. This doesn't affect the classification --\nFO-DIGEST is compute-dominated and reads well under 2% share at every\nsize collected on both machines.\n\nKEP-0003 stays Draft (gated); #1474 stays open with its revisit trigger\n(real kaappi-examples traces showing an IP-*-shaped hot loop).\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-16T09:14:03+05:30",
          "tree_id": "e80cf5e06904867970dccfec59b5549ed2a5b9cb",
          "url": "https://github.com/kaappi/kaappi/commit/109a2f5f4b576cc82885690855ceba1c269b1f15"
        },
        "date": 1784175537434,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.04169,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.195218,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.91361,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.410182,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006717,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.053042,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.510594,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068232,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.210593,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.984448,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.511368,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.467689,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.732591,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.831377,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044442,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "62f781aacb2643578889c6d7278b95d470a6a920",
          "message": "Update gate/P3 benchmark docs to reflect completed Linux run + #1474 closure (#1581)\n\ndocs/dev/kep-0002-phase7-envelope-benchmarks.md, benchmarks/gate/README.md,\nand the kep-0003 worksheet still described the gate campaign's Linux x86_64\nrun as open/deferred and lever B's shipped-default decision as pending --\nboth landed since (PR #1560, PR #1580). Also corrects a stale conflation:\nthe P3 micro-benchmark's own Linux re-run (bench_channel.zig, still open)\nis a different, unrelated task from the gate campaign's Linux run (done),\nwhich a \"the only open piece is the Linux x86_64 run (item 1)\" sentence\nhad blurred together.\n\nUpdates the worksheet's \"#1474 stays open\" language to note the actual\ndisposition: closed by explicit maintainer decision on 2026-07-16, which\nwas a deliberate deviation from the frozen protocol's own default action\nfor a \"Between\" outcome -- documented so a future reader doesn't mistake\nit for a protocol violation. The revisit trigger is unaffected either way.\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-16T09:25:16+05:30",
          "tree_id": "3c1a1a4c9041c4b79179593cbea7714dd92e48a1",
          "url": "https://github.com/kaappi/kaappi/commit/62f781aacb2643578889c6d7278b95d470a6a920"
        },
        "date": 1784176041431,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.390809,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.2556,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.910288,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.48286,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006445,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.05395,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.508684,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069865,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.389118,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.976361,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.574402,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.435528,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.836413,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.584741,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044021,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "ff49cc654681966ec7cc9b6ddbc706bc34b554f0",
          "message": "Add /do-gate-benchmark skill for KEP dual-machine benchmark campaigns (#1582)\n\nCodifies the operational procedure for running the KEP-0002 Phase 7\ngate-campaign benchmark (benchmarks/gate/) on a Linux x86_64 reference\nmachine via DigitalOcean droplet -- generalized from collecting kaappi#1474's\nLinux dataset (PR #1580) so a future KEP acceptance gate, or a KEP-0003\nrevisit-trigger rerun, doesn't have to rediscover the same lessons:\n\n- This account's dedicated CPU-Optimized droplet line is tier-restricted\n  above 4 vCPUs even though larger sizes show as available; go straight\n  for the Premium \"Basic\" tier instead of wasting a create/delete cycle.\n- Verify actual core topology with lscpu rather than trusting vCPU count.\n- Three bash-guard string-match footguns hit repeatedly during provisioning\n  (sudo, pkill -f self-matching, rm -rf on non-root paths) and their\n  workarounds.\n- Always run a direct single-iteration timing probe of the heaviest\n  workload before committing to a multi-hour statistical run -- a driver-\n  level pilot alone hides the real bottleneck, and the same benchmark can\n  run 5-6x slower per-thread on a cloud x86 vCPU than the Apple Silicon\n  reference for some interpreted kernels.\n- How to split a run around a per-machine workload cap (mirroring the\n  protocol's existing IP-MATMUL precedent) and merge the resulting CSVs.\n\nAlso adds the skill to CLAUDE.md's skills table and a matching section in\ndocs/dev/claude-code-harness.md, per that file's own \"when changing the\nharness, update both\" instruction.\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-16T09:33:39+05:30",
          "tree_id": "84ae4afe633f4564ad84595b4efc235f6a70aa6d",
          "url": "https://github.com/kaappi/kaappi/commit/ff49cc654681966ec7cc9b6ddbc706bc34b554f0"
        },
        "date": 1784176827761,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.430377,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.879369,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.894087,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.496636,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006441,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.053833,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.507405,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070071,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.400467,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.972533,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.565384,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.427432,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.830795,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.574775,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043639,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "2da66933fcb823194f88b908e8c2117bf17e58e6",
          "message": "LLVM backend: split llvm_emit.zig into inline + let sub-modules (#1583)\n\nllvm_emit.zig had grown to 1841 lines, past the 1500-line file-size\npolicy. Extract two self-contained subsystems along natural seams,\nfollowing the existing llvm_emit_<theme>.zig convention (forms, lambda,\ntailcall):\n\n- llvm_emit_inline.zig — inline fixnum fast-path emission (#1493) for\n  + - * < = null?, plus its private nanbox/ArithOp/CompareKind helpers\n  and nodeMayAllocate. These helper types were used only by this cluster.\n- llvm_emit_let.zig — native let / let* emission (emitLet and its\n  fallback/abandon paths) plus the nameInList helper.\n\nBoth use the direct-call dispatch pattern (like llvm_emit_forms.zig), so\nllvm_emit.zig only gains two imports and four call-site rewrites — no\ndelegation wrappers. Every moved function's remaining dependencies are\nstable LLVMEmitter methods or already-pub lambda.* helpers, so this is a\npure code move: no behavior change. llvm_emit.zig is now 1378 lines.\n\nVerified: zig build + full unit suite (tests_native/tests_ir) green,\nzig fmt clean, and a native-compiled program exercising every moved path\nproduces output identical to the interpreter.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-16T11:21:18+05:30",
          "tree_id": "a72e4bc972af70cafdfa2883e1c8825dd60b298c",
          "url": "https://github.com/kaappi/kaappi/commit/2da66933fcb823194f88b908e8c2117bf17e58e6"
        },
        "date": 1784182930042,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.041254,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.506978,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.927081,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.442391,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006782,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.052834,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.510296,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068208,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.220989,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.982038,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.514444,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.473119,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.731683,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.851319,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044577,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "e2986a76a6806532a86959992bea95c44d93db1f",
          "message": "Allow dlopen of user FFI libraries in signed macOS releases (#1588)\n\nThe Developer ID signature applies the hardened runtime, whose library\nvalidation refuses any dylib not signed by the same team or by Apple —\nso every locally-built C FFI library (kaappi-net, kaappi-pg,\nkaappi-sqlite, kaappi-crypto) failed ffi-open with a dlopen error on\nrelease binaries, while unsigned source builds loaded the same file\nfine. disable-library-validation is the entitlement Apple provides for\nexactly this plugin-loading case, alongside the allow-jit grant the\nfile already carries.\n\nVerified on macOS arm64 by re-signing a source build ad hoc with the\nhardened runtime: with the shipped entitlements the test dylib is\nrefused; with this change it loads (#1587).\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-16T12:05:12+05:30",
          "tree_id": "4044abeee169fccb636fc6db1409cd8d5f760a34",
          "url": "https://github.com/kaappi/kaappi/commit/e2986a76a6806532a86959992bea95c44d93db1f"
        },
        "date": 1784185372572,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.386215,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.987767,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.918868,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.483742,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006582,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.05395,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.507035,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070033,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.390283,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.979294,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.574074,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.43716,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.845996,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.743857,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043705,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "3c03ac9b80feb34541cc089a9bf36ad8759a5ce6",
          "message": "LLVM backend: fix native let root leak (#1585) + duplicated fallback effects (#1586) (#1589)\n\nTwo pre-existing bugs in the native let/let* emitter. Native codegen is not\ncovered by -Dgc-stress, so the unit suite never caught them.\n\n#1585: an unboxed let lowers its last body expr in tail position, but the\ntail-call emitters popped only frame_entry_roots before `ret` — never the let's\nbinding roots. The trailing kaappi_gc_pop_roots landed in the dead orphan block\nafter the `ret`, leaking one shadow-stack slot per binding on every execution\nuntil GC.pushRoot overflowed at MAX_ROOT_CAPACITY. The self-tail-call\nbranch-back to the loop header leaked the same way, re-pushing the binding roots\neach iteration.\n\nThread the binding roots through a new body_scope_roots emitter counter (a\nsibling to frame_entry_roots): the three tail-call emitters pop\nframe_entry_roots + body_scope_roots before every `ret`, and emitSelfTailCall\npops only body_scope_roots before the loop back-edge (frame_entry_roots live\nbefore the header and persist across iterations). This keeps proper tail calls,\nunlike disabling tail position for any let with bindings.\n\n#1586: emitLet writes binding initializers into the output buffer incrementally\nbut can abandon to the whole-form interpreter fallback partway through, running\nan already-emitted side-effecting init once natively and again from the\nfallback. Make emitLet transactional: snapshot the buffer position and current\nblock before writing any IR, and truncate back to it on abandon (discarding the\npartial inits, their effects, and their root pushes) before emitting the\nfallback. Restoring current_block re-opens the block an init's control flow may\nhave split.\n\nAdd compile-and-run regression tests for both bugs; they fail on the prior code\n(GC root stack overflow / doubled side effects) and pass with the fix.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-16T07:11:39Z",
          "tree_id": "8fa3a4e1799f069cd6511fa96841ad6c056cecd6",
          "url": "https://github.com/kaappi/kaappi/commit/3c03ac9b80feb34541cc089a9bf36ad8759a5ce6"
        },
        "date": 1784187636376,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.35135,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.677523,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.90223,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.444145,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006428,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.053804,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.497036,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069732,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.340918,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.941371,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.579887,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.432955,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.822984,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.724432,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043956,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "7b27e7c785f50c2297a7fa9708ea98fd3c2b05c6",
          "message": "Split bytecode_file.zig along the serialize/deserialize seam (#1593)\n\nbytecode_file.zig had grown to 1594 lines, past the 1500-line policy.\nA serialization module has a natural architectural seam — the write half\nand the read half share only a format contract — so split there rather\nthan by function count.\n\n- bytecode_file.zig (684): hub owning the shared format contract (magic,\n  version, constant tags, size limits), BytecodeError, and the cache-key\n  hashing both halves agree on; re-exports the read/write API so external\n  callers still see a single `bytecode_file` module. Round-trip tests\n  stay here since they exercise both halves.\n- bytecode_file_write.zig (389): serializer (Writer, writeConstant,\n  function collection, writeFileWithTopLevel/writeFileWithBundle).\n- bytecode_file_read.zig (594): deserializer (Reader, readConstant,\n  bytecode validation, deserializeFromBuffer, readHeaderInfo,\n  DeserializeResult/HeaderInfo).\n\nPublic API is unchanged: every externally-used symbol is re-exported\nfrom the hub, so main.zig, cache.zig, kaappi_lsp.zig, and the tests_*\nfiles keep resolving through bytecode_file.X with no edits. The read and\nwrite halves import the shared contract via `const bf = @import(...)`,\nthe same mutual-import pattern the VM and compiler splits use.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-16T09:47:48Z",
          "tree_id": "72d990cd603eeb6dbee79caa7d0a8b2f05c2ccdf",
          "url": "https://github.com/kaappi/kaappi/commit/7b27e7c785f50c2297a7fa9708ea98fd3c2b05c6"
        },
        "date": 1784197170287,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.332687,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 10.510782,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 1.012222,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.602714,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006473,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.056071,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.514655,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069432,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.463425,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.986161,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.592271,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.443611,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.810779,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.83329,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045084,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "fb4723a3d37c1a93324672883164e848e61f4ed1",
          "message": "Split free-variable/capture analysis out of llvm_emit_lambda.zig (#1591) (#1592)\n\nllvm_emit_lambda.zig was ~1590 lines, over the 1500-line file-size policy.\nMove the free-variable walking + capture-analysis section into a new focused\nmodule, llvm_emit_freevars.zig, keeping the closure/lambda emission tiers in\nplace. Pure code motion, no behavior change — same discipline as the #1583\nsplit.\n\nThe seam is clean: the analysis functions never call back into emission code;\nthey only walk ir/types data and use three public emitter predicates\n(allocator, isNameShadowed, isKnownOrReservedGlobal). Four functions become\npub (sexprContainsDefine, analyzeBoxedParams, hasFreeVars, collectFreeVars) so\nthe lambda and let emitters can call them across the module boundary; the\nother analysis entry points were already pub. The two emission helpers that\nsat inside the analysis region (freeVarsAnyBoxed, emitBoxedParamSlots) stay in\nllvm_emit_lambda.zig.\n\nllvm_emit_lambda.zig: 1589 -> 835 lines; new llvm_emit_freevars.zig: 781.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-16T09:51:38Z",
          "tree_id": "0dc28dc20b4c2008583e097abf8374ff2848f1b9",
          "url": "https://github.com/kaappi/kaappi/commit/fb4723a3d37c1a93324672883164e848e61f4ed1"
        },
        "date": 1784197429046,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.519759,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.709202,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.83929,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.96156,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006624,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.050377,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.455556,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.065537,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.418855,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.707279,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.454554,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.397595,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.929573,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.906138,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.041973,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "3f02051d4b7c6cc8048663f5c099c1ea96b9cfb4",
          "message": "Fix --profile dropping functions promoted to the old generation (#1599)\n\nprintProfileReport, writeProfileJson, and resetProfileCounters walked\nonly gc.objects, but sweepYoung promotes functions surviving two minor\ncollections onto gc.old_objects. Long-running programs therefore printed\nno profile at all (count == 0 hit the silent return), mid-length runs\nprinted a report silently missing the oldest — hottest — functions, and\nREPL profile resets left stale counters on promoted functions. Coverage\nreporting is unaffected (it reads counters via library export refs, not\na heap walk).\n\nAll three walkers now share an allObjects iterator over both generation\nlists. Regression tests force promotion with explicit minor collections\nand assert reset and JSON output both reach old-generation functions;\nboth fail on the young-list-only walk.\n\nFound while capturing --profile traces of kaappi-examples for the\nKEP-0003 revisit-trigger check (#1596).\n\nCloses #1598\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-16T17:02:36+05:30",
          "tree_id": "97e096c83a8a495363153452bdaf9e19b386d579",
          "url": "https://github.com/kaappi/kaappi/commit/3f02051d4b7c6cc8048663f5c099c1ea96b9cfb4"
        },
        "date": 1784203586160,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.375372,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.555533,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.897716,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.48501,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006477,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.054793,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.508008,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070129,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.320437,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 2.046789,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.580299,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.430599,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.86786,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.692816,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044698,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "40da1661e81e8136778c6b2f150221961d7971e9",
          "message": "Rendezvous semantics for (make-channel 0) on both representations (#1602, #1603) (#1604)\n\n* Rendezvous semantics for (make-channel 0) on both representations\n\nCapacity 0 shipped in v0.15.0 as the documented degenerate \"permanently\nfull\" channel: construction succeeded but send waited for a slot that\ncannot exist and receive for a value that can never be enqueued — every\nuntimed pairing deadlocked (#1600). Per the KEP-0002 §4/§6 amendment\n(kaappi/keps#28, model-checked first), capacity 0 is now a Go-style\nrendezvous channel: a send completes only against a committed receiver,\nwhichever side arrives first waits.\n\nRendezvous is the dynamic-capacity generalization of the existing\nreservation/wake-all-retry protocol — the admission bound becomes\nrv_demand, the count of committed receivers, and the value still\ntransfers through the queue. Receivers hold demand tokens\n(Fiber.rv_demand_on: acquired idempotently at the park decision since\nyield_retry re-executes the whole primitive; released on every terminal\nexit and on fiber death via retireSlot/thread-terminate!, the\nabandonFiberMutexes precedent; traced like waiting_on, but surviving\nwakes). New demand rings parked senders exactly like a freed slot\n(model finding 4). promoteChannel seeds SharedChannel.rv_demand from\nthe local counter, so pre-promotion local-park tokens stay counted\nacross migration.\n\nTwo rules keep timeouts honest (§6): delivery-wins — both operations'\ntimeout redispatch decides through one actual send()/receive(), never\ndiscarding a handoff that materialized with the timer pop — and\nreservation-drain — a timed-out receiver outwaits reserved > 0 so a\nsend past its point of no return is never silently stranded (the abort\npath now rings recv_waiters on rendezvous channels even while open).\n\nOne rule testing found, now regression-tested: dispatched fibers must\nflat-park (yield_retry) on rendezvous waits, never in-call park.\nRendezvous is the only capacity where a parked sender and receiver can\nexist simultaneously, and an in-call park makes the fiber a frozen\nancestor when its drive transitively dispatches the counterparty\n(#1487) — a main-fiber receiver stacked on top raised a spurious\nKP3000 with viable timed senders frozen beneath it. Timers survive\nre-parks via the preserved-deadline discriminator.\n\nCloses #1602. Closes #1603. Tracking: #1600.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n* Address #1604 review: close two demand-accounting races + hardening\n\nCodeRabbit's review found two genuine concurrency races in the\nrendezvous demand accounting, both instances of one flaw — counter\ntransitions in separate critical sections from the queue/reservation\nstate that justifies them. Both are specified and model-checked first\nin kaappi/keps#29 (findings 5 and 6, with rejected-variant witnesses).\n\nFinding 5 (withdraw-at-pop): receive() gains holds_token and withdraws\nthe caller's demand inside the pop's mutex section — previously the\ntoken stayed counted through the unlocked copy-out, and the freed-slot\nring could admit a second send against an already-satisfied receiver,\nstranding its value when no receiver remained. On the copy-failure\nraise the token stays withdrawn (terminal exit; the re-queued envelope\nfalls under §6's abnormal-exit rule), so callers clear the fiber field\nwithout decrementing again.\n\nFinding 6 (atomic timeout-withdraw): tryTimeoutWithdraw replaces\nreservedCount — the queue check (delivery-wins), the reservation check\n(drain), and the demand decrement are one lock section, so a sender's\nadmission and a timed-out receiver's withdrawal serialize; previously a\nsender could reserve against the still-held token between the zero\ncheck and the withdraw and push into demand that no longer existed.\n\nAlso from the review:\n- threadEntryFn releases a terminated child's demand token beside its\n  mutex abandonment — the parent-side path deliberately never touches\n  an OS thread's fiber, and thread-terminate! is a normal API, so this\n  leak was reachable without OOM.\n- Post-park send timeouts decide through one real send()/admission\n  check (delivery-wins symmetry with the entry redispatch), both\n  representations.\n- Every fallible park path (addTimer/enrollSharedWaiter/\n  runSchedulerStep) rolls back the token and detaches the timer on\n  error, matching the status/waiting_on cleanup those handlers already\n  did; the main fiber has no retireSlot backstop, so these were real\n  (if OOM-only) phantom-demand leaks.\n- Two-sender tests now pin one-demand/one-send admission: exactly one\n  delivery, one timeout, and an emptiness probe (Zig + Scheme).\n- New deterministic cross-thread close-wake test polls sc.rv_demand —\n  the child's commitment is exactly the observable the counter provides\n  — instead of the Scheme twin's thread-sleep! guess.\n- tests_shared_channel.zig was over the 1500-line policy (1682):\n  rendezvous coverage moves to tests_shared_channel_rendezvous.zig\n  (the tests_native.zig split, #1595, is the precedent), with finding\n  5/6 protocol-level regressions added there.\n\nVerification: full unit suite; gc-stress (tests_fibers +\ntests_shared_channel*); full Scheme suite 1871 pass / 0 fail; TLA suite\n16/16 at expected outcomes with Cap>0 pass-configs bit-identical.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-16T14:59:05Z",
          "tree_id": "4857472ff1450c7e1a81c682fb29fe5b955a2141",
          "url": "https://github.com/kaappi/kaappi/commit/40da1661e81e8136778c6b2f150221961d7971e9"
        },
        "date": 1784215820359,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.053005,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 10.007058,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.938363,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.453209,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006991,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.052768,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.509994,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070282,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.272646,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.976006,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.523492,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.477303,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.745844,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.937965,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044654,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "a4d1fe2ec510f1455a0bf69ede282a13ff11bac5",
          "message": "referencesYoung: trace owned_mutexes in the fiber arm (#1605)\n\nInvestigation of a suspected generational-GC gap (flagged during #1602):\nthe fiber arm of referencesYoung omitted owned_mutexes while\nmarkFiberState traces it, so remembered-set pruning looked able to drop\nan old fiber whose only reference to a young mutex is its owned list —\na use-after-free at the next minor sweep, or at abandonFiberMutexes.\n\nVerified false alarm for correctness: every scheduler-resident fiber is\nmarked as an unconditional root each collection (markVMRoots ->\nFiberScheduler.markRoots), minor collections included, so\nmarkFiberState re-traces owned_mutexes every cycle regardless of the\nremembered set — for fibers the pruning path is belt-and-braces, not\nload-bearing. The same argument covers the write-barrier-less\nowned_mutexes.append in mutex-lock!.\n\nAdd the loop anyway, with a comment recording that argument: it\nrestores the markFiberState/referencesYoung pairing convention\n(waiting_on, rv_demand_on) and keeps pruning safe even if the\nroot-marking invariant ever changes.\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-16T16:01:38Z",
          "tree_id": "4a9a561e47e4f15979a6bf524672717fd94102b8",
          "url": "https://github.com/kaappi/kaappi/commit/a4d1fe2ec510f1455a0bf69ede282a13ff11bac5"
        },
        "date": 1784219628595,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.046126,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.305025,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.919325,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.430356,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006751,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.052976,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.511059,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.067797,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.244251,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.98872,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.513769,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.471766,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.736071,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.846947,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044671,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "329d40665069e0a1c1f2571590261d79be275e34",
          "message": "Allow ~/.ssh reads in the project permissions (#1614)\n\nThe Windows port's testing workflow drives a remote win11 VM over ssh\n(docs/dev/windows.md), but the harness deny rule Read(~/.ssh/**) also\nblocks Bash commands that touch those paths, so even checking which\nhost aliases exist was refused mid-debug. Move the rule from deny to\nallow and update the harness docs to match.\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-17T01:11:06+05:30",
          "tree_id": "0a2707189871ae0ea273eb6a7977f824dc0d49af",
          "url": "https://github.com/kaappi/kaappi/commit/329d40665069e0a1c1f2571590261d79be275e34"
        },
        "date": 1784232880334,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.055352,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 10.235633,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.93566,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.456218,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006808,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.053025,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.512016,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068737,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.31681,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.98608,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.514476,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.481411,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.747366,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.91726,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045715,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "4585791606e76c1e1ed30d96c08ad1e24a191f53",
          "message": "Document the root cause of the ARM64 Windows toolchain crashes (#1613, #1607) (#1615)\n\nBoth the Zig 0.16.0 native-compilation crash (#1613) and the stripped\nkaappi.exe startup crash (#1607) trace to one upstream bug: under strip,\nZig demotes threadlocals to private linkage, and LLVM's AArch64 COFF\nS_HI12 fixup emits a +64 KB TLS offset for them (Codeberg ziglang#31865,\nfixed via llvm/llvm-project#199581). Verified on the reference VM: Zig\nmaster 0.17.0-dev.1413 compiles natively on the box, and a 7-line\nthreadlocal probe reproduces the strip crash under 0.16.0 and runs clean\nwhen built by master. Update windows.md and the release.yml strip\ncomment so nobody starts the now-obsolete #1607 bisection; both issues\nunblock at the 0.17.0 toolchain bump.\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-16T20:58:04Z",
          "tree_id": "c4151adf3f9bb6104e9619afe1aed05c54838733",
          "url": "https://github.com/kaappi/kaappi/commit/4585791606e76c1e1ed30d96c08ad1e24a191f53"
        },
        "date": 1784237396660,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.810649,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.036382,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.865889,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.090056,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006501,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.051699,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.460137,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.063953,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.458431,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.721067,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.47179,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.405382,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.670115,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.973771,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.040612,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "4036bb127823d2590ef5e1a45d719f7838cb689e",
          "message": "Run the FFI Scheme suite on Windows (#1611) (#1616)\n\nThe suite could not run there: (ffi-open #f) probed only the exe's\nempty export table, tests opened C libraries by POSIX name, and the\nuint64-range fixture only built as .dylib/.so.\n\n- platform.zig: give the dlOpen(null) process handle POSIX\n  dlopen(NULL) semantics — dlSym now probes every loaded module via\n  K32EnumProcessModules, so CRT symbols resolve from ucrtbase.dll.\n- tests: cond-expand ucrtbase for libm (no libm.dll), llabs/int64 for\n  labs/long (LLP64), and the CRT's _byteswap_ulong for ws2_32's htonl;\n  declare qsort with its true size_t signature everywhere; teach\n  uint64-range.scm the repo-relative fixture path.\n- CI: windows-cross cross-compiles libu64test.dll into the artifact;\n  windows-arm-test stages it and runs the ffi suite; run-all.sh builds\n  the host fixture when zig is on PATH, so uint64-range.scm stops\n  silently skipping on every platform.\n\nVerified on a Windows 11 ARM64 VM: all 14 ffi files pass (the fixture\nDLL loads, callbacks round-trip through qsort) and the unit suite is\n1050/0 including the new dlSym regression test. POSIX: full local\nsuite 1871/0.\n\nCloses #1611.\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-17T05:59:00+05:30",
          "tree_id": "6ac7d67e253752660762a9908631049683a1b273",
          "url": "https://github.com/kaappi/kaappi/commit/4036bb127823d2590ef5e1a45d719f7838cb689e"
        },
        "date": 1784249871044,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.040444,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.642348,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.925987,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.43101,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006768,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.053062,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.512187,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.0686,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.2454,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.986695,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.521478,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.471555,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.743944,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.836093,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044636,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "ae970816acc54bc74110b53d60c84b288a256510",
          "message": "Windows: port thottam package installation (#1609) (#1617)\n\n* Windows: port thottam package installation (#1609)\n\nthottam's install/remove/update were gated on Windows because the\ninstall pipeline shelled out to POSIX userland. Replace those shell-outs\nwith shim-based helpers so the pipeline runs identically everywhere and\nlift the gate:\n\n- new src/thottam_fs.zig: makeDirRecursive (mkdir -p), touchFile,\n  copyFile, copyTree (cp -R src/. dst/ merge semantics), removeTree\n  (rm -rf; retries through makeWritable for git's read-only object\n  files, which block _wunlink on Windows), and collectFilesWithSuffix\n  (the find call sites). Symlinks are never traversed.\n- platform.zig: lstatPath (no-follow stat; FindFirstFileW reports\n  reparse points on Windows), makeWritable/makeReadOnly (_wchmod /\n  chmod), is_symlink on StatInfo.\n- thottam.zig: dylib_ext is .dll on Windows; a manifest `build:` line\n  is refused on Windows with a clear error (every ecosystem build: is a\n  POSIX Makefile; pure-Scheme packages install fine); HOME falls back\n  to USERPROFILE (also in kaappi_paths.getHome, so installed libraries\n  are importable from plain pwsh/cmd shells).\n- thottam.zig now aggregates its sibling modules' tests; the existing\n  thottam_proc/state/semver tests were silently absent from the test\n  binary (Zig only collects tests from files referenced by a test\n  block). The proc test's std.c.getpid usage did not compile for\n  Windows; it now uses the platform shim.\n- CI: windows-arm-test runs thottam-tests.exe plus an install/remove\n  integration test of kaappi-json — removal deletes a real git clone,\n  the read-only hazard above.\n\nCloses #1609\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n* Address review: fail installs on copy errors, tighten symlink handling\n\n- copyTree skips symlinks entirely (old cp -R duplicated links, never\n  read through them; a package-controlled link must not copy content\n  from outside the tree), and copyFile unlinks a destination symlink\n  before writing so a write can't land outside the lib dir.\n- Library/dylib copy failures now fail the install (exit 1) instead of\n  warning: a partial copy was previously recorded as installed+locked.\n  A missing/unreadable pkg dir still means \"no native libraries\".\n- Windows CI integration step also exercises `thottam update`.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n* Guard copy destinations against pre-existing symlinks\n\nremoveIfLink now backs every destination the copy pipeline writes or\nrecurses into: a planted link at a destination child (file or dir/\njunction) is removed — with failure propagated, never ignored — before\nany content is created through it. The merge root itself stays\nuntouched: a user may legitimately symlink ~/.kaappi/lib, and cp\nfollows a symlinked destination directory the same way.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n* removeIfLink: retry read-only file symlinks; test dst file-link replace\n\nDeleteFile honors READONLY on the link object itself, so the file\nbranch goes through unlinkRetry like every other unlink (RemoveDirectory\nignores READONLY on directory objects, so the junction branch stays\ndirect). The copyTree symlink test now also covers a pre-planted\ndestination *file* link: replaced by a real file, old target untouched.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-17T08:10:13+05:30",
          "tree_id": "8c28dbcd323d3ec3f0131a49e39d8a6cecab78cb",
          "url": "https://github.com/kaappi/kaappi/commit/ae970816acc54bc74110b53d60c84b288a256510"
        },
        "date": 1784257699031,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.056795,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 10.255279,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.948359,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.461813,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006798,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.052863,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.512316,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068773,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.267328,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.985634,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.51356,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.479241,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.741576,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.918805,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.046294,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "4f4ec49dd8dced29f312d755fa930bfb96c56d58",
          "message": "Windows socket readiness: WSAEventSelect reactor backend (#1608 stage 1) (#1619)\n\n* Windows socket readiness: WSAEventSelect reactor backend (#1608 stage 1)\n\nLift the blocking-port degradation for socket-backed ports on Windows,\nper the issue's suggested staging. A socket enters the port layer as a\nCRT fd wrapping a SOCKET (_open_osfhandle — the bridge contract for\nkaappi-net-style FFI code and fd->port):\n\n- maybeSetNonblocking probes isSocketFd on first touch and routes socket\n  ports through platform.sockRecv/sockSend unconditionally — CRT\n  _read/_write cannot operate on (overlapped) SOCKET handles at all —\n  and additionally flips FIONBIO once a scheduler exists, so would-block\n  surfaces as the EAGAIN the shared park-and-retry protocol expects.\n- WindowsEventBackend (reactor.zig) grows real fd readiness: every armed\n  socket posts to one shared manual-reset event via WSAEventSelect (no\n  64-handle cap), wait() blocks on [notify, sock_event] bounded by the\n  nearest timer deadline, and a WSAEnumNetworkEvents sweep maps records\n  onto ReadyEvents. A 0-timeout select() probe right after each arm\n  closes the documented WSAEventSelect races (FD_WRITE/FD_CLOSE are\n  edge-recorded and re-issuing WSAEventSelect clears pending records).\n- platform.close tries closesocket before _close on every fd: a socket\n  closed by bare CloseHandle leaks ws2_32's per-handle state, which then\n  falsely claims whatever file recycles that handle value is a socket\n  (observed as silently dropped writes); isSocketFd cross-checks\n  GetFileType for the same reason.\n\nPipes and files keep blocking reads (no would-block mode at the CRT\nlayer); the completion-based rework stays open as #1608 stage 2.\n\nThe fd-readiness suites (tests_reactor, tests_scheduler, tests_port_io)\nnow run on Windows — testing_helpers grows cross-platform fd pairs\n(pipes/socketpairs on POSIX, loopback TCP pairs on Windows) — resolving\nthe suite-exclusion cleanup from the issue thread, and two new portable\ntests pin the pre-arm race behavior on every backend.\n\nShipping this surfaced a repo-wide latent bug: Zig's auto struct layout\nmoved Port.header off byte offset 0 when two bools were added, silently\ncorrupting every port Value (most makePointer call sites pass the struct\npointer while Object.as() addresses the header field). A comptime layout\nguard in types.zig now turns any such drift into a compile error, and\nthe new Port state is a single packed u8 (sock_state) that keeps the\noffset at 0; normalizing the call sites is #1618.\n\nVerified: full unit + Scheme + R7RS suites on macOS; full unit suite\n(1111 pass, 0 fail) and R7RS on a Windows 11 ARM64 machine.\n\nCloses nothing; part of #1608.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n* Address review findings: single-owner socket close, verified probe, module split\n\n- platform.close is plain _close again, even for sockets: the paired\n  closesocket closed the same handle value twice, a TOCTOU where another\n  thread's allocation could receive the value between the calls and get\n  its handle closed from under it. Kernel teardown via CloseHandle is\n  equivalent (peers still observe FD_CLOSE/EOF); the stale ws2_32\n  bookkeeping it leaves is instead neutralized where it bites:\n- isSocketFd gains a third, kernel-verified gate — ioctlsocket(FIONREAD)\n  round-trips to AFD, so only a handle that is a socket right now\n  passes; a stale ws2_32 entry pointing at a recycled pipe/file handle\n  errors out. (GetFileType and getsockopt(SO_TYPE) remain as the cheap\n  first gates.)\n- ensureWinsock publishes ready only when WSAStartup succeeds; a failure\n  is retried on the next call instead of being cached as ready.\n- WindowsEventBackend.deinit disarms every still-registered socket\n  (WSAEventSelect(sock, null, 0)) before closing the shared event.\n- The Windows socket substrate moves to platform_win_sock.zig\n  (platform.zig had crossed the 1500-line policy; the seam was already\n  self-contained), re-exported so callers keep the platform.* names.\n- CHANGELOG: the earlier Windows-target entry no longer claims all ports\n  block — superseded by the socket-readiness entry.\n\nVerified: full unit suite on macOS and on Windows 11 ARM64\n(1112 pass / 0 fail), cross-compile gate green.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-17T06:15:10Z",
          "tree_id": "1016be29b2f102b1b796fae6349848a31c081cef",
          "url": "https://github.com/kaappi/kaappi/commit/4f4ec49dd8dced29f312d755fa930bfb96c56d58"
        },
        "date": 1784270743031,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.366904,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.097669,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.920756,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.441201,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006378,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.054009,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.506305,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070319,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.46945,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.966729,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.584881,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.438186,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.847136,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.773492,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044934,
            "unit": "seconds"
          }
        ]
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
          "id": "347432b586c99823b0c34ef3b0252e15cc90ee9b",
          "message": "Add skip-issues argument to /parallel-issues skill\n\nAccepts an optional second comma-separated argument of issue numbers\nto exclude from analysis, e.g. `/parallel-issues label1 7898,7845`.\n\nCo-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>",
          "timestamp": "2026-07-17T11:46:23+05:30",
          "tree_id": "3ce363fe2923fc0645fa8845d71df32ff7e62421",
          "url": "https://github.com/kaappi/kaappi/commit/347432b586c99823b0c34ef3b0252e15cc90ee9b"
        },
        "date": 1784270751364,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.293725,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.371626,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.879266,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.39343,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006203,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.052552,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.500625,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069233,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.357352,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.93222,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.542779,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.424188,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.826308,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.662019,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044265,
            "unit": "seconds"
          }
        ]
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
          "id": "684fe63bde7f114dbc12753f7cf7acc38db5ccf3",
          "message": "Skip blocked-upstream issues in /parallel-issues skill\n\nCo-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>",
          "timestamp": "2026-07-17T11:54:12+05:30",
          "tree_id": "6ac3c0a18054ca4bee9849a8cdd568825de136dd",
          "url": "https://github.com/kaappi/kaappi/commit/684fe63bde7f114dbc12753f7cf7acc38db5ccf3"
        },
        "date": 1784271251074,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.429856,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.521899,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.934445,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.562878,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006509,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.055642,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.506841,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.07081,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.550999,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 2.01751,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.651867,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.452449,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.920487,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.716949,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045081,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "b2cebe06c293b6d8dfab3ebdc9b37e62426e2611",
          "message": "Fuzz #1620: fix two generator leaks + report-job misclassification (#1621)\n\n* Fix two portable-generator leaks producing erroneous programs (#1620)\n\nThe nightly oracle-diff batch flagged seed 10294: Kaappi raised where\nChibi returned. The program was erroneous, i.e. a generator leak, not an\nimplementation bug: genLetMut generated the mutation statement's\nindex/value sub-expressions before registering the fresh binding, so the\npicker could reference an outer same-named int that the new binding\nshadows — the emitted reference resolved to the fresh object instead:\n\n  (let ((c (make-bytevector 1 92))) (bytevector-u8-set! c (modulo c 1) ...) ...)\n\nRegister the binding as .reserved before the mutation statement (hiding\nthe outer name, per the letrec precedent) and upgrade it to its real kind\nfor the body result.\n\nA 4000-seed totality scan after that fix surfaced a second, older leak:\nthe \"x y!\" pool literal recorded len 5 (actually 4), so every derived\nindex could land out of range. This one was invisible to the oracle —\nboth sides raise identically on out-of-range indices. Pool lengths are\nnow computed from the text at comptime (strLit), removing the bug class.\n\nVerified: the failed CI batch (seeds 10000..10999) now runs 0 divergent\nagainst the same Chibi 0.12.0 oracle, and seeds 0..2999 all evaluate\ncleanly. Pinned regression seeds cover both leak shapes.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n* Make fuzz report marker detection artifact-layout-agnostic (#1620)\n\nThe seed-10294 oracle divergence was filed as \"Fuzz CI: infrastructure\nor build failure\" even though the oracle-diff job uploaded its finding\nartifact. Root cause: download-artifact v8 extracts each artifact into\nartifacts/<name>/ EXCEPT when the run produced exactly one artifact\n(the action's `artifacts.length === 1` special case) — then contents\nland in artifacts/ itself. One failed job is the common case, so marker\ndetection anchored on artifacts/<name>/ missed real findings whenever\nexactly one job failed.\n\nThis is also what misfiled seed 2788 (#1584): both artifact containers\nheld loose files, so the wrapper-zip theory behind the \"Unwrap archived\nartifacts\" step was a misdiagnosis. The unwrap step stays as a cheap\nsafety net, reframed.\n\nMarker detection now searches all of artifacts/ for filenames only the\nowning job can produce (seed-*.kaappi.* vs seed-*.{vm,nat}.*, and the\n.zig-cache/f/crash path), and derives each excerpt directory from the\nmatched file, so both layouts — and a job dying before upload while\nanother uploads — classify and excerpt correctly.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n* Correct the wrapper-zip comment in windows-arm-test (#1620)\n\nNamed artifact downloads extract contents into the path directly; the\nunwrap loop is a defensive no-op, not a required step. Keep it, but stop\nciting the misdiagnosed wrapper-zip behavior as fact.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-17T07:07:47Z",
          "tree_id": "78246eea83b869a155ed471ac7da4a929138e97b",
          "url": "https://github.com/kaappi/kaappi/commit/b2cebe06c293b6d8dfab3ebdc9b37e62426e2611"
        },
        "date": 1784274116667,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 2.41522,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.810396,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.492418,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.545995,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004256,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.029234,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.260309,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.036751,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 1.989664,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.978473,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 0.868942,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.314688,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 0.953896,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.270697,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.026754,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "8c0251b94d9ac86dd86d0bf1e50d3c8b9453d0a6",
          "message": "Normalize heap-Value creation to makePointer(&x.header) (#1622)\n\nA heap Value's payload was the *struct* address at ~100 call sites but\nthe *header field* address in newer code (fiber, reactor, srfi18,\nshared_channel) — two conventions that only agree while Zig's auto\nlayout happens to keep `header` at byte offset 0, which it promises for\nno field: adding two bools to Port once moved its header to offset 48,\nsilently corrupting every port Value (#1608 review).\n\nMake the header-address convention universal and compiler-enforced:\nmakePointer now takes *Object instead of *anyopaque, so the only natural\nspelling is makePointer(&x.header) and passing a struct pointer is a\ncompile error rather than latent corruption. All 122 call sites are\nmigrated (99 struct-pointer sites converted, 23 already-correct sites\nlose their now-redundant @ptrCast), which lets heap structs gain and\nreorder fields freely — as Fiber, whose header already sits at a nonzero\noffset, always could.\n\nThe stopgap comptime layout guard from #1608 (assert header offset 0 for\nall 36 types.zig heap types) is deleted along with Port.sock_state's\npacking constraint, replaced by a round-trip test on a deliberately\nreorder-prone struct and updated heap-type docs.\n\nCloses #1618\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-17T07:25:39Z",
          "tree_id": "864f2797dd46e0715ac9a0f9a0ed57f87e4a9be5",
          "url": "https://github.com/kaappi/kaappi/commit/8c0251b94d9ac86dd86d0bf1e50d3c8b9453d0a6"
        },
        "date": 1784274986860,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.867284,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.093807,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.868841,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.121927,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006363,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.052492,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.469411,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.064347,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.452722,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.769259,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.454408,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.404092,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.683355,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.963864,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.041057,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "ac4145ba344a678b014ca09aeb4a955ebe256fe5",
          "message": "Add porting guide for new OSes and CPU architectures (#1624)\n\nThe Windows (#1606/#1608/#1609), WASI (KEP-0001 P4), and riscv64 ports\neach rediscovered where portability lives in this codebase: the\nplatform.zig shim, the reactor Backend switch (the one hard compile\ngate), the runtime capability probes, and the NaN-box 48-bit pointer\nconstraint. docs/dev/porting.md captures that as a support matrix, a\nporting-surface map, the fiber-I/O degradation ladder, and staged\nchecklists for OS and CPU ports, so the next port starts from a plan\ninstead of an archaeology dig. Index it in docs/dev/README.md and\npoint to it from CLAUDE.md's platform section.\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-17T13:07:01+05:30",
          "tree_id": "f75dd997959d87bd521c463af13d42fbddab1cfa",
          "url": "https://github.com/kaappi/kaappi/commit/ac4145ba344a678b014ca09aeb4a955ebe256fe5"
        },
        "date": 1784275841831,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.376365,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.477914,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.935537,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.457856,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006377,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.054372,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.50842,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069938,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.47887,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.99689,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.581556,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.437309,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.839795,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.74896,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045411,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "dd3a8360bd5db137a02578913d665c8b91091008",
          "message": "Windows pipe readiness: polled backend lifts the blocking-pipe degradation (#1608 stage 2) (#1623)\n\n* Windows pipe readiness: polled backend lifts the blocking-pipe degradation (#1608 stage 2)\n\nResolves the #1608 stage-2 question — do pipes/files justify a\ncompletion-based (IOCP/overlapped) rework of the park-and-retry\nprotocol? — with a no, and ships the design that fits instead:\n\n- IOCP cannot serve the pipe fds the port layer actually sees: CRT\n  _pipe/inherited/CreatePipe handles lack FILE_FLAG_OVERLAPPED, so the\n  only general completion design is a blocking worker pool whose\n  issued-read semantics can lose data on cancellation — something the\n  never-read-until-ready model structurally cannot.\n- Regular files gain nothing on any OS: POSIX has no regular-file\n  readiness either (O_NONBLOCK is a no-op, epoll rejects them), so\n  blocking file reads are the cross-platform baseline, not a Windows\n  gap.\n- Pipes need only readiness, and Windows can express it by polling:\n  PeekNamedPipe answers read-readiness, and\n  NtQueryInformationFile(FilePipeLocalInformation).WriteQuotaAvailable\n  answers write-readiness (libuv's own non-overlapped-pipe query).\n\nA pipe port under a scheduler now enters emulated non-blocking mode\n(port.nonblocking set with no OS-level flip): pipeRead/pipeWrite\npre-check peek/quota and synthesize the EAGAIN the shared protocol\nexpects — writes clamp to the known-free space so the blocking CRT\nwrite underneath can never block — and the WindowsEventBackend bounds\nits wait at a 10 ms quantum while pipe interest is armed, re-running\nthe same checks in its sweep (level-triggered, so none of\nWSAEventSelect's edge-record races apply; the quantum is paid only\nwhile a pipe waiter exists). Sequential programs keep plain blocking\npipe I/O and their exact syscall profile.\n\nThe Port fd-kind byte becomes fd_state (probe_done/is_socket/is_pipe),\nclassified once per port by the new platform.fdKind. New OS-pipe-pair\ntests (testing_helpers.makePipeFdPair) run the park/wake, write-full,\nsequential-blocking, and close-wake patterns over real pipes on every\nplatform — on Windows they are the new backend's coverage and would\nhave deadlocked before this change.\n\nVerified: macOS full unit suite + R7RS + the new suites under\n-Dgc-stress=true; Windows 11 ARM64 VM unit suite 1115 passed / 0\nfailed (15 skips) and R7RS 0 fail; wasm32-wasi and x86_64-linux\ncross-builds.\n\nCloses #1608\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n* Address #1623 review round: finalizer quota gate, file-size policy, test hardening\n\n- gc_collect freeObject flush: route emulated-non-blocking pipe ports\n  through pipeWrite. The flush's contract is \"a would-block drops the\n  remainder\", but plain _write on a full Windows pipe blocks — and a GC\n  sweep can never park — so an abandoned port with pending output and a\n  full pipe would hang the whole OS thread. Regression test constructs\n  exactly that port and collects it.\n- platform.zig back under the 1500-line policy (1419): the kernel32/ntdll\n  pipe externs move into platform_win_pipe.zig (their only consumer —\n  unlike the ws2_32 slice, which stays in platform.win because reactor\n  and testing_helpers share it), and the inline tests move to a new\n  tests_platform.zig (appendQuotedArg/buildCommandLineW now pub for it).\n- Park/wake tests prove the reader reached .io_waiting before the peer\n  fiber is spawned, so a lucky schedule can't pass them without the\n  parked-pipe path; raw setup writes are asserted so a setup failure\n  fails loudly instead of hanging the blocking read.\n- platform_win_pipe.zig documents MSDN's multithreaded-PeekNamedPipe\n  caveat and why it sits outside the runtime's ports-never-cross-threads\n  model.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-17T09:03:40Z",
          "tree_id": "1bd76a5ce26249541aab4401cb1e109434ce06ff",
          "url": "https://github.com/kaappi/kaappi/commit/dd3a8360bd5db137a02578913d665c8b91091008"
        },
        "date": 1784280768362,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.376888,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.868321,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.920529,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.439789,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006378,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.054204,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.50379,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070348,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.484386,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.965277,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.576172,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.435615,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.85032,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.692865,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043744,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "283d5f1356852e6e91bad342894b5697e49a119d",
          "message": "Windows native backend: kaappi compile verified end-to-end (#1610) (#1626)\n\nkaappi compile had never produced a running native binary on a Windows\nmachine; doing so surfaced four defects, three of which the issue\npredicted:\n\n- The runtime-archive probes (native_compiler.checkLibDir, doctor's\n  hasArchive) looked for libkaappi_rt.a, but Zig names COFF archives\n  kaappi_rt.lib, so discovery always failed on Windows. A new\n  platform.rt_lib_name carries the platform spelling; the probes, the\n  compile error message, doctor's messages, and --help all use it.\n- kaappi compile foo.scm derived \"foo\" as the output; PowerShell/cmd\n  PATH lookup and double-click need the extension, so the derived name\n  now appends platform.exe_suffix (foo.exe on Windows, unchanged\n  elsewhere). Explicit -o stays as given.\n- The emitted LLVM module triple fell to aarch64-unknown-unknown on\n  Windows; it is now aarch64/x86_64-pc-windows-gnu, matching the gnu\n  ABI the runtime lib is built with (clang's driver-triple override\n  hid this, but only behind the -w the link line passes).\n- New find: linking failed with undefined Winsock symbols. The\n  fd-readiness backends (#1608) call ws2_32 via extern \"ws2_32\"\n  declarations, which Zig links automatically only when it drives the\n  final link itself - a foreign zig cc link of the static archive\n  needs -lws2_32 explicitly. tryLink and doctor's smokeLink add it in\n  place of -lpthread on Windows; the previously-failing doctor\n  smoke-link now passes.\n\nVerified on the Windows 11 ARM64 box (build 26100) with a Zig master\ntoolchain as linker (0.16.0's zig cc access-violates natively, #1613):\ntests/e2e/run-e2e.ps1 - a new PowerShell port of run-e2e.sh's parity\nphase, kept for the post-0.17.0-bump retest - passes 38/38 (all 37\nprograms match the interpreter, incl. closures, self/mutual tail\ncalls, call/cc, macros; plus the derived-.exe check). KAAPPI_LIB_DIR\nand exe-relative lib discovery and the missing-lib error were\nexercised individually. macOS e2e suite stays 37/37; unit suite green\nnatively and as the aarch64-windows compile gate.\n\nCloses #1610\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-17T16:04:13+05:30",
          "tree_id": "e1515b82ffd914c06970e34c5400472922482b33",
          "url": "https://github.com/kaappi/kaappi/commit/283d5f1356852e6e91bad342894b5697e49a119d"
        },
        "date": 1784286413461,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.038667,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.252273,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.914616,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.359723,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006816,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.053408,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.50541,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068173,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.231081,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.95928,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.525965,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.468803,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.748907,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.835667,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044754,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "19ff254a1b1bf476ee533106f710d36fda27f1ff",
          "message": "Unwind an idle in-place I/O drive pinned over a resolved wait (#1625) (#1628)\n\n* Unwind an idle in-place I/O drive pinned over a resolved wait\n\nA guard-wrapped blocking read in a spawned fiber cannot park-and-retry:\nthe guard's call/ec + with-exception-handler natives are re-entrant Zig\nframes, so waitForFd takes drive mode and runs the scheduler in place.\nWhen that drive went idle, parkOnReactor polled unbounded on the fiber's\nown fd — hasRunnableFibers counts the fiber's .io_waiting and the fd\nkeeps the reactor non-empty, so the generic deadlock escape never fires.\nAn enclosing drive whose wait had already resolved (a fiber-join whose\ntarget completed, an expired thread-sleep!) stayed pinned beneath those\nnative frames forever: the whole OS thread wedged in kevent (#1625).\n\nThe reported \"parked fiber redispatched by a later join\" was a misread\nof the same stack: the hang is the pre-parking join itself — a\nguard-wrapped reader never survives in a parked state past the eval\nthat dispatches it, because it drives instead of parking.\n\nFix: every runSchedulerStep drive publishes its wait in a type-erased\nper-scheduler stack (driving_waits), so a nested drive can evaluate\nwhether an ancestor's condition is satisfied or timed out — resolutions\nnothing else announces, since a driving fiber is never .waiting and no\nwake path targets it. At the idle point (runnable siblings always get\ndispatched first), a wait that opted in (IoWait only) breaks off, and\nwaitForFd surfaces that as a catchable \"port I/O abandoned\" error: the\nre-entrant frames that made parking impossible are exception plumbing,\nso an ordinary raise is exactly the unwind they handle. Join, channel,\nmutex, and condvar drives are unaffected — with no fd of their own they\nalready fall out through parkOnReactor's deadlock check — and pure\nsleeps still run their full duration.\n\nCloses #1625\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n* Propagate OOM from the driving_waits push instead of degrading\n\nReview follow-up (PR #1628): unlike the ready ring or waiter_index,\nwhose OOM degradation is backed by correctness-preserving fallback\nscans, driving_waits is a correctness registry with no fallback — an\nentry silently dropped on OOM would re-open the #1625 wedge for the\ndrive's descendants as a silent hang. runSchedulerStep already\npropagates OutOfMemory mid-drive (saveCurrentFiber's growth,\nparkOnReactor's poll), so failing the wait loudly is the established,\nalready-handled path, and it simplifies the enrollment to a plain\nappend + defer pop.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-17T11:06:41Z",
          "tree_id": "9d2655f12e977e592f32362c8798c9482ae2a277",
          "url": "https://github.com/kaappi/kaappi/commit/19ff254a1b1bf476ee533106f710d36fda27f1ff"
        },
        "date": 1784288098335,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.134708,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.092447,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.714191,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.41331,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.005285,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.041086,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.394881,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.053104,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.564591,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.528671,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.171751,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.371494,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.345181,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.513331,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.036891,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "04fdfdc635071089886b7c209c6e2d9accced98c",
          "message": "Run the shell-based test suites on Windows (#1612) (#1630)\n\n* Run the shell-based test suites on Windows (#1612)\n\nThe bash-driven suites (errors, compile, test-runner, pipeline, doctor,\nfmt, cache, timings, the smoke .sh scripts, sandbox, robustness) had\nnever executed on Windows — exactly the surface most likely to differ:\nexit codes, error formats, path handling, subcommand output. Verified on\nthe reference Windows 11 ARM64 VM under Git Bash (34 pass, 0 fail,\n15 skip) and wired into the windows-arm-test CI job.\n\nThe first sweep caught two real runtime bugs, both fixed here:\n\n* The CRT's preopened fds 0/1/2 stayed in text mode, so every \\n reached\n  pipes as \\r\\n — piped output differed byte-for-byte from POSIX (files\n  already open O_BINARY for exactly this reason). platform.initConsole\n  (console UTF-8 + VT mode) also turned out to be dead code, never\n  called since the port landed. The new platform.initStandardStreams,\n  called first in all three binaries' mains, flips stdout/stderr to\n  binary unconditionally, flips stdin only when it is not the\n  interactive console (the plain REPL's line reader relies on console\n  text mode), and performs the console setup for real. In kaappi-lsp\n  this also protects Content-Length framing.\n* kaappi test --changed/--list-affected discovery used std.fs.path.join\n  (the runtime's one platform-separator join), so discovered paths\n  carried '\\' and never matched the '/'-spelled import-graph and\n  git-diff paths.\n\nTheir regression tests are the suites themselves, now in CI on Windows:\nrepl-multiple-values.sh and test-runner/changed.sh each fail without the\ncorresponding fix.\n\ntests/scheme/shell-common.sh is the shell analogue of the .scm tests'\ncond-expand (windows ...) gate: skip_on_windows exits 77 (reported as\nSKIP by run-all.sh and CI), plus native_path (the C:/... spelling kaappi\nitself prints) and rt_lib_name (kaappi_rt.lib vs libkaappi_rt.a). The\ncompile/ suite self-skips — each script rebuilds with a native zig,\nwhich #1613 breaks until the 0.17.0 bump — as does\nprofile-json-escaping.sh, whose planted \"/\\ filename characters Windows\nforbids. The remaining drivers needed only spelling-level fixes\n(/dev/stdin arguments → real stdin, abort() exit 3 vs died-by-signal,\nplatform archive names, autocrlf-hermetic git fixture), all\nbehavior-identical on POSIX: the full POSIX suite stays green\n(1871 pass, 0 fail).\n\nCloses #1612.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n* Guard the CI shell-suite loop against the runner's implicit bash -e\n\nGitHub's `shell: bash` runs steps with -e, so the plain `out=$(...)`\nassignment aborted the whole step at the first skipping script's\nexit 77 (the VM harness ran without -e, masking this). Capture the\nstatus with `|| status=$?` instead.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-17T12:28:39Z",
          "tree_id": "05986e572abb483271fa418c7a8acf3218cfecf3",
          "url": "https://github.com/kaappi/kaappi/commit/04fdfdc635071089886b7c209c6e2d9accced98c"
        },
        "date": 1784293041379,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.379536,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.300813,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.928544,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.417168,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006462,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.054003,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.504934,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068543,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.399567,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.935896,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.58259,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.434284,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.825291,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.72015,
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
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "distinct": true,
          "id": "fee98e0af031c5bbeb42c9c23bd750629b2ab72c",
          "message": "Release v0.16.0",
          "timestamp": "2026-07-17T18:23:20+05:30",
          "tree_id": "331f61b07355fe5d2eead3f6c8bcf450879409f3",
          "url": "https://github.com/kaappi/kaappi/commit/fee98e0af031c5bbeb42c9c23bd750629b2ab72c"
        },
        "date": 1784294892101,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.372166,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.702784,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.934027,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.403512,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006618,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.054114,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.509293,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069413,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.409859,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 2.046359,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.613332,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.44369,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.845576,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.711131,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043075,
            "unit": "seconds"
          }
        ]
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
          "id": "b9bfd6acdb14c81d202732d36643a5a0f47ee56a",
          "message": "Improve /github-release skill with five fixes from v0.16.0 release\n\n- Fix Step 5 grep pattern to match actual .name spec structs\n- Add workspace ../CLAUDE.md version bump to Step 4\n- Remove stale src/main.zig src/thottam.zig from Step 7 git add\n- Add concrete ssh win11 smoke test commands to Step 10\n- Replace sleep+lookup dance with direct gh run watch in Step 11\n\nCo-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>",
          "timestamp": "2026-07-17T18:34:11+05:30",
          "tree_id": "bce4f68ea0ee7fc08fd3c937d523e2137449884e",
          "url": "https://github.com/kaappi/kaappi/commit/b9bfd6acdb14c81d202732d36643a5a0f47ee56a"
        },
        "date": 1784295032150,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.378259,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.542469,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.895145,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.403477,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006458,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.053644,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.503809,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068385,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.304652,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.945909,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.584182,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.430903,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.820693,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.708728,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042833,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "ccda40a1210dca6f201cb4761de8de6849cd30bb",
          "message": "Port Kaappi to FreeBSD (x86_64, aarch64) (#1631)\n\n* Port Kaappi to FreeBSD (x86_64, aarch64)\n\nFreeBSD is the fourth completed OS port and the smallest: a full-POSIX\nplatform whose readiness API is kqueue, so the existing macOS backend\ncarries it unchanged. The port adds the .freebsd tag to reactor.zig's\nfour per-OS switches (plus a guarded EV_EOF constant this Zig's freebsd\nstd.c binding omits), a sysctl kern.proc.pathname self-exe lookup, and\nthe FreeBSD LLVM triples. Everything else — platform shim, thottam,\nREPL, SRFI-170, FFI — already worked through the POSIX paths.\n\nVerified on a real FreeBSD 15.1 aarch64 machine: 1141/1141 unit tests,\nthottam suite, R7RS 1395/0, and the full run-all.sh battery (1869 pass,\n0 fail), including the native backend linking with the base system cc —\nno Zig toolchain on the box.\n\nThe port surfaced one genuine runtime bug: the graceful out-of-memory\nerror relied on malloc refusing absurd requests, but FreeBSD's default\novercommit reserves a 100 TB make-bytevector and the zero-fill then\ncommits pages until the kernel's OOM killer ends the process. The GC\nnow caps single payload allocations at 1 TiB (GC.max_payload_bytes)\nand raises the same catchable error before asking the OS, on every\nkernel.\n\nThe shell suites' zig dependency becomes a capability gate rather than\nan OS gate: skip_without_zig skips the -Dbundle scripts, and\nensure_runtime_lib lets the kaappi-compile scripts run against a\nprebuilt libkaappi_rt.a on toolchain-less machines.\n\nCI gains a freebsd-test job (cross-compile gate on ubuntu-latest, then\nexecution in a KVM FreeBSD 14.3 VM via SHA-pinned vmactions);\nrelease.yml ships both FreeBSD arches. New docs/dev/freebsd.md; all\nsupport matrices updated.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n* Build libkaappi_rt.a for the FreeBSD CI VM\n\nThe freebsd-test VM run exposed a gap: six compile-suite scripts use\nkaappi compile without invoking zig themselves (so the new\nskip_without_zig/ensure_runtime_lib gates correctly leave them\nrunning), but the job never cross-compiled the runtime archive they\nlink against. On the aarch64 reference box they passed because the\narchive was shipped alongside the binaries. Add `zig build lib` to the\nhost cross-compile step so zig-out/lib/libkaappi_rt.a syncs into the\nVM, matching the reference-machine recipe in docs/dev/freebsd.md.\n\nEverything else in the VM's first flight was green: the 14.3 image\nbooted, unit suite, thottam suite, R7RS 1395/0, and all other .scm\nsuites passed; the six -Dbundle/zig-rebuilding scripts skipped as\ndesigned.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n* Bundle compiler-rt into libkaappi_rt.a\n\nThe FreeBSD CI VM (x86_64) exposed the next layer after the archive\nwent missing: every `kaappi compile` link failed under the VM's base\nclang because the Zig-built archive references __zig_probe_stack — an\nx86-only, Zig-internal stack-probe symbol no system toolchain provides.\nThe aarch64 reference box never hit it (no stack probing on that arch),\nwhich is why \"base cc suffices\" held there.\n\nSetting bundle_compiler_rt on the static library embeds Zig's\ncompiler-rt (weak symbols, so no duplicate-symbol conflicts with a\nhost runtime), making the archive linkable by whatever C compiler\n`kaappi compile` finds on any platform — the property the FreeBSD\nport's native-backend story depends on. Verified: x86_64-freebsd\narchive now weak-defines __zig_probe_stack; the aarch64 box links and\npasses the compile suite with the bundled archive; the macOS zig-cc\npath is unaffected.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-17T21:18:33+05:30",
          "tree_id": "2e5497461e7a520553a1e09eded6612318be4ad8",
          "url": "https://github.com/kaappi/kaappi/commit/ccda40a1210dca6f201cb4761de8de6849cd30bb"
        },
        "date": 1784305475646,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.044974,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.665438,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.921324,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.407167,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006816,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.052916,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.509563,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.06839,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.257779,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.984134,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.519148,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.474532,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.749032,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.786497,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044622,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "6090935f92ca9d07083907200b9f9cd96bbc9ef3",
          "message": "Make FreeBSD installable: install.sh + release skill (#1632)\n\nThe FreeBSD port (#1631) shipped release.yml artifacts but left the\nuser-facing install path macOS/Linux-only. Two gaps:\n\n- install.sh rejected `uname -s = FreeBSD` and never mapped FreeBSD's\n  `amd64` (what x86_64 reports via uname -m) to the `x86_64` artifact\n  name, so `curl | bash` failed on FreeBSD. Add the FreeBSD OS case and\n  the amd64→x86_64 arch mapping; verified `detect_platform` emits\n  `aarch64-freebsd` on the reference box.\n- The /github-release skill's platform list and per-platform smoke-test\n  step didn't mention FreeBSD. Add both FreeBSD targets to the build\n  list and a smoke-test leg on the `ssh freebsd` box (no hosted FreeBSD\n  runner, so it's checksum-covered but not CI-acceptance-tested — same\n  posture as Windows).\n\nThe end-user download page (kaappi.github.io) is a separate repo and\ngets its FreeBSD rows in a companion PR.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-18T00:50:13+05:30",
          "tree_id": "25081a775fd65f4110d0049e9e774479c8fd3c7f",
          "url": "https://github.com/kaappi/kaappi/commit/6090935f92ca9d07083907200b9f9cd96bbc9ef3"
        },
        "date": 1784317987036,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.4636,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.735933,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.985786,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.503714,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00641,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.055297,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.534854,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.071104,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.309814,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.967132,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.573909,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.429731,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.853153,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.76006,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044021,
            "unit": "seconds"
          }
        ]
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
          "id": "38fe09e15f2eb250ceae60c7a9d1d16f99661564",
          "message": "Release v0.17.0",
          "timestamp": "2026-07-18T01:02:14+05:30",
          "tree_id": "199781ad3996e66f5891c6bba669de908d181aea",
          "url": "https://github.com/kaappi/kaappi/commit/38fe09e15f2eb250ceae60c7a9d1d16f99661564"
        },
        "date": 1784318562815,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.428066,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.98952,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.933456,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.528655,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006446,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.054337,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.543686,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.071014,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.349275,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.981115,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.577916,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.426943,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.849591,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.713908,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043561,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "9a9b3f6dac898cfbffa3eee41363b21d40120b62",
          "message": "Port Kaappi to OpenBSD (x86_64, aarch64) (#1634)\n\n* Port Kaappi to OpenBSD (x86_64, aarch64)\n\nOpenBSD is the fifth completed OS port: a full-POSIX platform whose\nreadiness API is kqueue, so the existing macOS/FreeBSD reactor backend\ncarries it unchanged. Unlike FreeBSD, OpenBSD's security hardening forces\ntwo accommodations nothing else in the tree needs.\n\nBTCFI. OpenBSD on arm64 enforces Branch Target CFI: an indirect branch\nmust land on a `bti` instruction or the kernel raises SIGILL/ILL_BTCFI.\nZig 0.16 emits no landing pads (no -mbranch-protection, no bti CPU\nfeature), so a Zig-linked binary trapped on its first function-pointer\ncall, before main ran. OpenBSD's own opt-out is `-z nobtcfi`, which emits\na PT_OPENBSD_NOBTCFI program header. `kaappi compile` adds the flag to the\nbase-cc link directly (native_compiler.zig). Zig's CLI rejects the flag,\nso the Zig-linked binaries get the marker post-link: tools/openbsd_nobtcfi.zig\nrepurposes the PT_GNU_STACK header in place (OpenBSD ignores GNU_STACK, and\nthe phdr table has no room to grow before .interp), and build.zig's\ninstallExe runs that host tool on each installed executable for OpenBSD\ntargets — so `zig build -Dtarget=<arch>-openbsd` yields working binaries\ndirectly, with no separate patch step.\n\nResource limits. OpenBSD's default login class caps the main-thread stack\nat 4 MiB (it ignores the ELF stack hint and sizes the stack from\nRLIMIT_STACK) and the data segment at 1.5 GiB. The kaappi binary already\nruns on a 64 MiB worker thread, but kaappi-lsp compiles on the main thread,\nso both mains now call platform.raiseStackLimitBestEffort() (setrlimit\nsoft->hard, OpenBSD-only). The data limit only affects the unit-test\nbinary — std.testing's DebugAllocator never reuses freed address space —\nso CI and the reference recipe raise ulimit -d before running it; the\nshipped C-allocator binaries never accumulate.\n\nOther surfaces: self-exe lookup via sysctl KERN_PROC_ARGS/KERN_PROC_ARGV\nargv[0] resolution (OpenBSD has no KERN_PROC_PATHNAME); the reactor gains\n.openbsd on its four kqueue switches (OpenBSD's std.c bindings are\ncomplete, so no constant fallback); the OpenBSD LLVM triples; and three\nunit tests switch from Io.Dir.realPathFile (fd->path, OperationUnsupported\non OpenBSD) to a path-string realpath helper.\n\nThree shared FFI tests (narrow-range, int-range, type-validation) resolved\n`abs` through a libm handle. abs is a libc function; OpenBSD's dlsym does\nnot chain a dlopen'd libm handle into libc the way Linux/macOS/FreeBSD do,\nso the call returned #f. They now resolve abs from the process/libc handle\n(the null default handle on POSIX, ucrtbase on Windows), keeping genuine\nlibm functions like sqrt in libm.\n\nVerified on a real OpenBSD 7.9 aarch64 machine: 1141/1141 unit tests,\nthottam suite, R7RS 1395/0, the full run-all.sh battery (1869 pass, 0 fail,\n2 skip), all 14 FFI suites, and the native backend (kaappi compile) linking\nwith the base system cc — no Zig toolchain on the box. CI gains an\nopenbsd-test job (cross-compile gate on ubuntu, then execution in a KVM\nOpenBSD 7.9 VM via SHA-pinned vmactions); release.yml ships both arches.\nNew docs/dev/openbsd.md; all support matrices updated.\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>\n\n* Link libc for the openbsd_nobtcfi host tool\n\nThe tool uses std.c.pread/pwrite/close, which are libc externs. macOS\nlinks libc implicitly, so `zig build -Dtarget=<arch>-openbsd` built the\nhost patcher fine locally — but the Linux CI host does not, and the\nopenbsd-test job failed at the cross-compile step with \"dependency on\nlibc must be explicitly specified in the build command\". Set\nlink_libc = true on the tool's module so it builds on every build host.\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>\n\n* Pass -lc to the openbsd_nobtcfi zig-run sites\n\nCompanion to the build.zig link_libc fix: the CI job and the docs recipe\nalso invoke the tool via `zig run`, which compiles it standalone without\nbuild.zig's settings. `zig run` links libc implicitly on macOS but not on\nthe Linux CI host, so the \"Compile and mark unit tests\" step failed the\nsame way the build step did. Add -lc to both `zig run` invocations.\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>\n\n* Address PR review: native marker, install.sh on OpenBSD, PATH lookup\n\nFive CodeRabbit findings on the OpenBSD port:\n\n- build.zig: the `zig build native` step links via `zig cc` (which rejects\n  `-z nobtcfi`) and installed the binary unmarked, so an OpenBSD native\n  artifact could SIGILL under BTCFI. Run the nobtcfi host patcher on the\n  native output before install, mirroring installExe.\n- install.sh: detect_platform accepted OpenBSD but the installer hard-coded\n  curl and sha256sum/shasum, none in the OpenBSD/FreeBSD base. Add a\n  download() fallback (curl → wget → fetch → ftp) and OpenBSD/FreeBSD base\n  `sha256` checksum verification.\n- src/kaappi_paths.zig: the OpenBSD argv[0] PATH search accepted any entry\n  passing access(X_OK), which is also true for searchable directories —\n  require a regular file so a $PATH dir named like the program isn't picked.\n- CHANGELOG.md: blank line after the new heading (markdownlint MD022).\n- docs/dev/porting.md: fix the grammar in the OpenBSD exemplar sentence.\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-18T02:27:04Z",
          "tree_id": "0bc64641f8d6efceedca91385c5d221e301837ef",
          "url": "https://github.com/kaappi/kaappi/commit/9a9b3f6dac898cfbffa3eee41363b21d40120b62"
        },
        "date": 1784343627100,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.053095,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 10.0851,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.94043,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.405322,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006753,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.053037,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.50952,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068399,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.281965,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.986023,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.513781,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.470158,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.740558,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.834359,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044473,
            "unit": "seconds"
          }
        ]
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
          "id": "1f73a11d977d3cdb0942a0e3407553c944a61cbb",
          "message": "Release v0.18.0",
          "timestamp": "2026-07-18T08:02:50+05:30",
          "tree_id": "7ed215ec18bc88c7eb4c0f6f86f7135a5d5a2453",
          "url": "https://github.com/kaappi/kaappi/commit/1f73a11d977d3cdb0942a0e3407553c944a61cbb"
        },
        "date": 1784344164092,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.044157,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.578969,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.912988,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.403837,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006718,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.052851,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.509341,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068508,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.265153,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.984063,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.508215,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.471041,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.727958,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.84518,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044203,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "8151f8c4c3ca89730e57ec00b3e39b8fe1f7a833",
          "message": "Port Kaappi to NetBSD (x86_64, aarch64) (#1635)\n\n* Port Kaappi to NetBSD (x86_64, aarch64)\n\nNetBSD is the sixth completed OS port: a full-POSIX platform whose\nreadiness API is kqueue, so the existing macOS/FreeBSD/OpenBSD reactor\nbackend carries it unchanged. Unlike the other BSDs, NetBSD's defining\nproblems are binary-compatibility engineering and a non-IEEE floating\npoint default — both producing silent wrong data rather than crashes.\n\nVersioned libc symbols. NetBSD keeps every old-ABI function under its\nplain name for old binaries and renames the modern one; Zig's std.c\ndeclares a handful by plain name and therefore links the compat version,\nwhich misparses modern structs. Five symbols bit: readdir/opendir\n(dirent grew at 3.0 — directory listings came back name-shifted, so\n`kaappi cache status` saw an empty cache and thottam tree walks copied\nnothing), getpwnam/getpwuid (passwd grew at 6.0 — SRFI-170 user-info\nreturned shuffled home dir/shell), lstat (struct stat time fields — the\ncompat syscall leaves the modern layout's timestamp padding\nuninitialized), kevent (timeout timespec — benign on LP64 but bound\nexplicitly), and unsetenv (void→int return, cosmetic). All five now\nbind the versioned name (__readdir30, __getpwnam50, __lstat50,\n__kevent50, __unsetenv13) via comptime-selected externs. Detection was\nnm --dynamic against libc (weak plain symbol beside a strong __nameNN\none) plus one on-box link, where NetBSD ld's .gnu.warning sections\nnamed the last two — the audit method is documented in\ndocs/dev/netbsd.md.\n\nFloating point. NetBSD/aarch64 starts every process with FPCR.FZ|DN set\n(0x3000000): denormals flush to zero, so (> fl-least 0.0) was #f and\nSRFI-144 failed. platform.normalizeFpEnvBestEffort() resets FPCR to the\nIEEE default at startup (kaappi, kaappi-lsp, kaappi_runtime_init for\nnative binaries); threads inherit the corrected state — verified\nempirically with a pthread probe. Regression tests at both levels.\n\nOther surfaces: self-exe lookup via sysctl {KERN, PROC_ARGS, -1,\nPROC_PATHNAME} (kernel-canonical, like FreeBSD under a different mib);\nraiseStackLimitBestEffort extended to NetBSD (8 MiB default soft\nstack); the NetBSD LLVM triples; C-compiler discovery probes clang\nbefore cc on NetBSD (base cc is GCC, which cannot consume LLVM IR — the\nnative backend needs pkgsrc clang, and the shared cc_search_order now\nkeeps doctor's finding honest, warning when only GCC is present);\ninstall.sh detects NetBSD via uname -p (uname -m reports the kernel\nport, evbarm, not the CPU) with base ftp download and sha256 checksums.\n\nVerified on a real NetBSD 10.1 aarch64 machine: 1142/1142 unit tests,\nthottam suite, R7RS 1395/0, the full run-all.sh battery (1869 pass, 0\nfail, 2 skip), kaappi test runner, the interactive linenoise REPL, and\nthe native backend (kaappi compile) linking with pkgsrc clang — no Zig\ntoolchain on the box. The unit-test binary's DebugAllocator commits\n~4 GiB cumulative, which OOM-kills swapless 4 GiB boxes (UVM: out of\nswap) — the reference box got a swapfile and the CI VM 6 GiB of RAM.\nCI gains a netbsd-test job (cross-compile gate on ubuntu, then\nexecution in a KVM NetBSD 10.1 VM via SHA-pinned vmactions);\nrelease.yml ships both arches; the release skill gains the NetBSD\nsmoke-test leg. New docs/dev/netbsd.md; all support matrices updated.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n* Address PR #1635 review findings\n\nAll five CodeRabbit findings, verified against the code:\n\n- doctor's smoke-link now resolves its driver through the shared\n  native_compiler.cc_search_order instead of a private zig→cc→clang→gcc\n  probe, so the c-compiler finding and the smoke link always describe\n  the same compiler `kaappi compile` will use (on NetBSD: pkgsrc clang,\n  never silently base GCC), and both findings now name the driver.\n- cc_search_order gains a regression test asserting zig first, gcc\n  last, and clang probed before cc on NetBSD — it runs on the NetBSD\n  unit-test leg, where a reordering would fail.\n- platform.zig (1507 lines) split along the arch-specific seam the\n  file-size policy names: the self-contained Windows extern namespace\n  moves to platform_win.zig (re-exported as `platform.win`, call sites\n  unchanged), leaving platform.zig at ~1280 lines.\n- README: NetBSD row in the supported-platforms table, and the install\n  script section now names the BSDs and their base-system download/\n  checksum fallbacks.\n- porting.md: reflowed the exemplar sentence so an issue reference no\n  longer starts a Markdown line (MD018).\n\nVerified: host suite green, aarch64-windows and aarch64-netbsd still\ncross-compile, and on the NetBSD 10.1 box the unit suite passes\n1143/1143 with doctor reporting clang for both c-compiler and\nsmoke-link.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-18T07:51:57Z",
          "tree_id": "5c6b924959c9c11d29679c0adebd44d03bee7c66",
          "url": "https://github.com/kaappi/kaappi/commit/8151f8c4c3ca89730e57ec00b3e39b8fe1f7a833"
        },
        "date": 1784363087910,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.390008,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.319285,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.91229,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.548809,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006345,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.053469,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.501992,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070586,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.462295,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.930162,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.575667,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.433217,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.825178,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.750151,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045017,
            "unit": "seconds"
          }
        ]
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
          "id": "d8c9ee8f872f7783be680bb4e4ff747a3ea3018c",
          "message": "Release v0.19.0",
          "timestamp": "2026-07-18T14:28:45+05:30",
          "tree_id": "cd0c907acc7afea0a4f5237d1c3cf7b03bbc03ff",
          "url": "https://github.com/kaappi/kaappi/commit/d8c9ee8f872f7783be680bb4e4ff747a3ea3018c"
        },
        "date": 1784367234748,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.433061,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.643342,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.914219,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.546618,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006349,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.053684,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.505684,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069884,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.460191,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.929084,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.596989,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.426346,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.845477,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.723538,
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
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "e19c06ccaa1a47a99a50ee2aec8657b89b645b20",
          "message": "Add SRFI 263 (Prototype Object System) (#1640)\n\n* Add SRFI 263 (Prototype Object System)\n\nImplements the Self-inspired prototype object system as two portable\nlibraries — (srfi 263) for the core message-passing/reflection protocol\nand (srfi 263 syntax) for the define-object/derive-object/copy-object/\nset-method! sugar — loaded on demand like the other portable SRFIs.\nCloses #1638.\n\nPorted from Daniel Ziltener's reference implementation. The reference\ntargets CHICKEN and leans on a few things R7RS leaves unspecified, so\nthe port makes them portable and, where the reference is simply broken,\nmatches the SRFI's documented behavior instead (each site is marked\n\"Kaappi:\"):\n\n  * The private symbol ##srfi-263#obj-data is bar-quoted so a strict\n    R7RS reader accepts it, and the dead first copy of recursive-lookup\n    is dropped.\n  * The root 'derive method returns a single value rather than relying\n    on CHICKEN truncating (values obj data) in a single-value context —\n    without this even basic derivation fails.\n  * copy/copy-object never worked in the reference (it sends the mirror\n    'get-* messages no mirror understands, and its methods captured the\n    original's data). It now uses the real 'immediate-* messages and\n    re-installs 'mirror so a copy is an independent duplicate.\n  * An unhandled message now re-dispatches message-not-understood /\n    ambiguous-message-send to the receiver, so a custom handler slot can\n    intercept it as the SRFI requires; the reference applied the bare\n    symbol and could not be overridden.\n\nThe portable-SRFI count is generated by scanning lib/srfi/*.sld, so\nkaappi features and the docs move to 73 SRFIs (65 portable). A\nconformance suite in tests/scheme/srfi/srfi263.scm ports the reference\ntests and adds coverage for reflection, working copy, custom handlers,\nand the syntax macros (51 checks).\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>\n\n* Address SRFI 263 review: reflection, copy, define-method\n\nFixes found in code review — all latent bugs in reference-implementation\npaths the reference's own test suite never exercised, plus spec-compliance\ngaps. Each site is marked \"Kaappi:\".\n\nCore (lib/srfi/263.sld):\n  * full-slot-list crashed: it unioned slot *records* with (car slot).\n    Dedup by slot-getter, and include the receiver's own slots by folding\n    (list self) into recursive-ancestor-collector (which previously kept\n    self only in the no-parents base case).\n  * Mirror reflection ran the recursive collectors against the mirror\n    receiver, so full-ancestor-list / full-slot-list returned mirror\n    objects instead of the real ancestors/slots. Thread the mirrored\n    object through populate-mirror and drive the collectors from it.\n  * Add the has-ancestor mirror message the SRFI lists but the reference\n    omits.\n  * The root's set-method-slot! slot recorded the procedure instead of the\n    'set-method-slot! message name; quote it so reflection and deletion by\n    name work.\n  * copy of the parentless root object aliased the global root (mirror\n    reinstall was skipped when there were no parents); always reinstall,\n    falling back to the root object as the mirror base.\n\nSyntax (lib/srfi/263/syntax.sld):\n  * Export define-method — the name the SRFI specifies — as the primary\n    method macro; keep set-method! (the reference's name) as an alias.\n\nDocumented as a known limitation (a gap in the finalized SRFI itself):\n  * (resend #f ...) from a method inherited from a non-immediate ancestor\n    loops; a correct fix needs a distinct-origin lookup the SRFI never\n    specified. Noted in the source header and CONFORMANCE.md.\n\nTests (tests/scheme/srfi/srfi263.scm): rewritten to SRFI-64 per\ntests/scheme/CLAUDE.md, and extended to cover full-slot-list, has-ancestor,\nreal-object ancestry, resend to super, private (non-symbol) selectors,\nroot-copy independence, define-method vs the set-method! alias, and\nnamed-parent expansion of derive-object / copy-object. 64 checks.\n\nAlso lists (srfi 263 syntax) in CONFORMANCE.md's sub-library inventory.\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-18T15:40:50+05:30",
          "tree_id": "4ef56f3eef34875ff9368c49b4bf163a6a107655",
          "url": "https://github.com/kaappi/kaappi/commit/e19c06ccaa1a47a99a50ee2aec8657b89b645b20"
        },
        "date": 1784371395422,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.378553,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.753562,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.905248,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.459721,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006336,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.053678,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.504515,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070038,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.436179,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.93099,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.573947,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.43215,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.824229,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.58501,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.047105,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "ec09cc40c6d50fa3f607b7c54398dfd50032bae6",
          "message": "Implement SRFI 267: Raw String Syntax (#1642)\n\n* Implement SRFI 267: Raw String Syntax\n\nRaw strings (#\"X\"...\"X\") are string literals that interpret no escape\nsequences, with a per-literal delimiter X (any run of bytes without \").\nThey spare the escaping of content full of \\ and \" — regexes, Windows\npaths, embedded source.\n\nThe lexical syntax is built into the reader: readHash gains a `\"` arm that\nscans the delimiter and copies content verbatim up to the leftmost `\"X\"`\nterminator. #\" was previously a read error, so nothing conflicts, and\nraw-string literals work anywhere a string can appear. The (srfi 267)\nlibrary adds the port procedures — read-raw-string,\nread-raw-string-after-prefix, can-delimit?, generate-delimiter,\nwrite-raw-string, and the two error predicates — in pure (scheme base);\ngenerate-delimiter is linear-time to avoid the blow-up the SRFI warns of.\n\nCloses #1639.\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>\n\n* SRFI 267: linear generate-delimiter, reject surplus port args\n\nAddress CodeRabbit review on #1642:\n\n- generate-delimiter walked the string with indexed string-ref, which in\n  Kaappi rescans UTF-8 from the front on every access (O(n^2)), contradicting\n  the linear-time claim. Rewrite it as a single pass over (string->list ...),\n  computing empty-delimiter validity and the longest `=` run together; drop the\n  now-unused longest-run helper.\n\n- read-raw-string, read-raw-string-after-prefix, and write-raw-string accepted\n  any number of trailing arguments and silently used only the first port. Add\n  opt-port, which rejects two-or-more arguments with an arity error, matching\n  the SRFI's fixed [port] signatures.\n\nTests extended: generate-delimiter edge cases (adjacent quotes, UTF-8 content)\nand surplus-port rejection for all three procedures.\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-18T16:19:23+05:30",
          "tree_id": "8899a21331e3e3893933e16aa013602c50d9763f",
          "url": "https://github.com/kaappi/kaappi/commit/ec09cc40c6d50fa3f607b7c54398dfd50032bae6"
        },
        "date": 1784373571257,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.36979,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.221184,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.918922,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.491422,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006384,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.0537,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.506796,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069855,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.440061,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.937023,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.589431,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.439115,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.823892,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.595093,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044484,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "c9e3fba2752896b0bf8b2b92f9f5de8897120239",
          "message": "Implement SRFI 254 (Ephemerons and Guardians) (#1643)\n\n* Implement SRFI 254 (Ephemerons and Guardians)\n\nSRFI 254 exposes three garbage-collector-dependent primitives that cannot be\nwritten portably in standard Scheme: ephemerons (a key/value pair whose value\nis retained only while the key is reachable other than through the value),\nguardians (post-mortem resurrection, the substrate for finalization), and\ntransport cell guardians plus current-hash (a stable identity hash).\n\nEphemerons and object guardians need real GC integration. A new\ngc_collect.processWeakRefs pass runs after strong marking and before sweeping,\nreaching a fixpoint that retains an ephemeron's value once its key is proven\nreachable, breaks the ephemerons whose keys never are (so a value that\nreferences its key still breaks — the case a plain weak-key pair gets wrong),\nand resurrects unreachable guarded objects onto each guardian's ready queue.\nEphemerons are processed before guardians each round so the two structures\ninteract correctly. Only ephemerons and guardians reached during marking are\nprocessed, so unreachable ones are swept normally.\n\nBecause Kaappi's collector is non-moving, current-hash is the stable boxed\nvalue word and transport cell guardians are the degenerate case: a key is\nnever transported, so cells are held strongly and a zero-argument\ntransport-cell-guardian call always returns #f.\n\nA guardian is itself a procedure; invocation is handled by\nvm_calls.invokeGuardian and wired into every call-dispatch site (callValue,\ncallWithArgs, and the inline tail_call/tail_apply paths), mirroring how\nparameter objects are invoked.\n\nBuilt in as (srfi 254) plus the component libraries (srfi 254 ephemerons),\n(srfi 254 guardians), (srfi 254 transport-cell-guardians), and the\n(srfi 254 ephemerons-and-guardians) alias. Adds deterministic GC unit tests\n(tests_srfi254.zig, green under -Dgc-stress) and an end-to-end Scheme\nconformance suite. Closes #1637.\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>\n\n* Fix Debug-build test timeout; address review feedback\n\nThe srfi-254.scm conformance test forced collections by allocating ~200k\npairs several times, which blew the 60s per-file timeout under the Debug\nbuild (every allocation is traced). Collapse it to a single ~20k-pair churn\nthat still crosses the 8192-object GC threshold, so every unreachable-key\nephemeron breaks and every unreachable guarded object resurrects in one\ncycle. Runs in ~6s in Debug (was >60s).\n\nAlso from PR review:\n- Correct the stale \"72 SRFIs / 8 built-in\" summary at the top of\n  CONFORMANCE.md to 73 / 9.\n- Add a cross-generational guardian test proving an old guardian's young\n  registered object is resurrected without a write barrier — a minor\n  collection re-traces every reachable guardian, so the old->young edge is\n  seen with an empty remembered set. This documents why guardian\n  registration needs no write barrier.\n- Document, at the guardian keep-case, that a representative is retained\n  strongly on purpose (memory safety on a non-refcounted collector); the\n  bounded cost is an unspecified-order resurrection delay.\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-18T16:59:08+05:30",
          "tree_id": "67cd9044b18e05b03c13464cc443fe59891ae901",
          "url": "https://github.com/kaappi/kaappi/commit/c9e3fba2752896b0bf8b2b92f9f5de8897120239"
        },
        "date": 1784376129803,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.37581,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.190751,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.988613,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.982443,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006375,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.05532,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.519086,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069858,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.347848,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 2.103967,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.586142,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.434262,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.802991,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.702368,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043726,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "1b7995b59347819ee290b576af1f02f0c46630aa",
          "message": "Implement SRFI 271 (Random Port Libraries) (#1641)\n\n* Implement SRFI 271 (random port libraries)\n\nSRFI 271 (finalized 2026-07-18) provides binary input ports that yield\nrandom bytes through the standard R7RS port interface, split into\ncryptographic-quality \"randomized\" ports and reproducible \"determinized\"\nports.\n\nA random stream is unbounded, so a random port cannot be a fixed\nbytevector port. Instead it is backed by a new types.RandomGen owned by\nthe Port and driven from readOneByte, so read-u8 / read-bytevector /\nu8-ready? work on it unchanged. Randomized ports refill each block from OS\nentropy (new platform.osRandomBytes: getrandom / arc4random_buf /\nRtlGenRandom, with a best-effort fallback); determinized ports run a\nxoshiro256** PRNG whose full observable state — the four words plus the\ncurrent 8-byte output block and how much of it was consumed — is snapshot\nas a self-describing bytevector. Because the snapshot is a bytevector it\nround-trips through write/read verbatim as a #u8(...) literal, which is\nexactly the external-representation invariance the SRFI requires of\nstates, and equal snapshots imply identical byte streams.\n\nFive %-prefixed core primitives (primitives_random_port.zig) do the\ngeneration and state marshaling; the user-facing API — the three\nmake-random-port cases, the state predicates, random-port-state=?, and the\nrandom-port-initialization-error? condition — lives in the portable\nlib/srfi/271*.sld libraries. (srfi 271) aliases the randomized library.\nThe build-time lib/srfi scan registers 271 automatically, so features and\ncond-expand see it.\n\nTests: tests/scheme/srfi/srfi271.scm (SRFI-64, 35 checks) and\nsrc/tests_random_port.zig unit tests for the generator core; green under\nzig build test, -Dgc-stress=true, and the full run-all.sh suite.\n\nCloses #1636.\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>\n\n* Harden SRFI-271 randomized ports against weak entropy fallback\n\nReview follow-up: osRandomBytes silently drained randomSeed64/monotonicNs\nwhen OS entropy was unavailable — most reachably on WASI, where the old code\nalways took the clock path — handing a \"cryptographic-quality\" randomized\nport predictable, timing-derived bytes.\n\n- osRandomBytes now uses a real CSPRNG on every platform (WASI random_get,\n  which the browser playground shim backs with crypto.getRandomValues) and\n  returns bool instead of void; on genuine OS-source failure it returns\n  false rather than substituting clock/PRNG bytes.\n- RandomGen.nextByte returns ?u8 (null only when a randomized refill cannot\n  obtain entropy; determinized ports never fail), and readOneByte raises a\n  catchable \"OS entropy source unavailable\" error instead of a silent EOF.\n\nDeterminized ports are unaffected. Green under zig build test, zig build\nwasm, and tests/scheme/srfi/srfi271.scm.\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>\n\n* Fix Linux getrandom errno decode (std.os.linux.E.init removed in Zig 0.16)\n\nosRandomBytes' Linux branch used std.os.linux.E.init(rc), which doesn't\nexist in Zig 0.16 — the branch is comptime-gated to Linux so it compiled\nfine on macOS but broke every Linux CI job (ubuntu x86_64/arm, riscv64,\nbenchmark-pr) with \"enum 'os.linux.E' has no member named 'init'\".\n\ngetrandom is a raw syscall that returns the byte count or a negative\n-errno directly (it does not set libc errno), so decode the signed return\nin place — advance on a positive count, retry on -EINTR, fail otherwise —\nrather than routing through std.posix.errno (which under libc reads C errno\nand expects the -1 convention). Verified with zig build -Dtarget=x86_64-linux\nand -Dtarget=riscv64-linux.\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-18T12:06:21Z",
          "tree_id": "69783719124547d985fd97417bdc70751bcd9333",
          "url": "https://github.com/kaappi/kaappi/commit/1b7995b59347819ee290b576af1f02f0c46630aa"
        },
        "date": 1784378231980,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.372824,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.819064,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.698755,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.476802,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006415,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.044349,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.39049,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.058796,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.115262,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.512262,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.312795,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.444502,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.460135,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.088442,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.038114,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "c11b06801bf465310f02b9b64abde91b8ad6dc63",
          "message": "Implement SRFI 250 (Insertion-ordered Hash Tables) (#1647)\n\nAdd the portable (srfi 250) library: hash tables that preserve\nfirst-insertion order across iteration, folding, and conversion, with the\nfull API — constructors, the bidirectional cursor interface, ordered\nfold-left/fold-right, and destructive set operations.\n\nDesign: a doubly-linked list of nodes gives O(1) ordered insert, delete,\nand pop, while a built-in (SRFI 69) hash table keyed through the SRFI 128\ncomparator maps each key to its node for O(1) lookup. The comparator flows\nstraight into the built-in table, which already extracts a comparator's\nequality and hash, so key comparison honours it.\n\nNodes are 4-slot vectors and the table record stores the head/tail *keys*\nrather than node references. This keeps `write` finite: Kaappi's record\nprinter recurses into fields without cycle detection, so a node reference in\na record field would loop on the prev/next cycle. Holding leaf keys instead\nkeeps the cyclic nodes solely inside the index, which prints opaquely.\n\nIncludes a SRFI-64 conformance suite covering the ordering guarantees,\ncursors, mutability rules, and set operations, and bumps the SRFI count\n(76 -> 77) in README, CONFORMANCE, and CLAUDE.\n\nCloses #1646.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-18T21:01:48+05:30",
          "tree_id": "80a8310dca5330bb6950a82dcff53ac7dd13563e",
          "url": "https://github.com/kaappi/kaappi/commit/c11b06801bf465310f02b9b64abde91b8ad6dc63"
        },
        "date": 1784390675844,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.093648,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.460874,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.919287,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.414812,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00672,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.052432,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.51034,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068351,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.259569,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.978911,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.51645,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.469862,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.740256,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.817428,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045184,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "84dd19d26ea8bd72cdfb6be26c47989049527b0d",
          "message": "Fix two macro-hygiene bugs in let-syntax and named-let expansion (#1648)\n\nBoth surfaced while investigating SRFI 257's matcher (#1644), whose\nheavily macrological reference implementation exercises corners of\nsyntax-rules that most programs never reach. They are general expander\nbugs, independent of that SRFI.\n\n1. let-syntax sibling passed as an argument went undefined. R7RS 4.3.1\n   resolves a transformer's *template* free references at its definition\n   site, where sibling keywords aren't visible, so compileLetSyntax\n   suppressed every sibling during the expansion's compilation. But a\n   sibling handed to a helper macro as an *argument* is a use-site\n   identifier, not a template free reference, and must stay resolvable.\n   Now only siblings a transformer actually free-references in its\n   template are suppressed (collectTransformerFreeRefs).\n\n2. A named let's loop gensym was re-renamed by hygiene. Named let\n   desugars to a __nlet_N_loop gensym during compilation, interleaved\n   with macro expansion; when the recursive (loop ...) call rides\n   through another macro whose template re-emits it, renameForHygiene\n   renamed the already-gensym'd name (__hyg_M___nlet_N_loop), splitting\n   the call from its letrec binding. It now leaves __nlet_ names alone,\n   as it already does for __hyg_ ones (issue #919).\n\nEach fix has a regression test in tests_macros.zig that fails without it.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-18T22:15:33+05:30",
          "tree_id": "6d557f7b7e74a4a448ac4872098c7c7972899ba3",
          "url": "https://github.com/kaappi/kaappi/commit/84dd19d26ea8bd72cdfb6be26c47989049527b0d"
        },
        "date": 1784395001577,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.275911,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.650008,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.651755,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.160477,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.005669,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.041228,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.369334,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.053374,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.805071,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.419348,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.266935,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.393306,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.453527,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.916538,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.038436,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "38163b7705f7c5b68c5d3a7787bd9eac8a994307",
          "message": "Implement SRFI 261 (Portable SRFI Library Reference) (#1650)\n\n(srfi srfi-<n>) and (srfi <mnemonic>-<n>) now resolve to (srfi <n>) as\nan import-resolver fallback — no library file, per the spec's nature as\na pure naming convention. The trailing digits are authoritative\n(mnemonics collide by design: vectors-43 vs vectors-133), literal names\nwin when they exist, and sub-library tails pass through. The SRFI 97\ncolon form is deliberately unsupported: its decorative trailing\nidentifiers collide with real R7RS sub-libraries like (srfi 146 hash).\n\nThe rewrite lives at every reference-side resolution surface: import\n(processImportSet, covering library bodies, environment, eval, check,\nLSP), both cond-expand (library ...) entry points, and — path-level —\ntest_selection's import graph, where a 261-form import would otherwise\nlook built-in and silently drop its dep edge from kaappi test --changed.\ndefine-library names stay literal.\n\nA miss on a rewritten name reports the spelling the user wrote plus the\nresolved number; found-but-broken literal files keep their load-error\ndetail (#1010).\n\nCloses #1645\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-18T16:49:22Z",
          "tree_id": "a41bca9b1580ce663dd36ade9c134e3cf6e24bc3",
          "url": "https://github.com/kaappi/kaappi/commit/38163b7705f7c5b68c5d3a7787bd9eac8a994307"
        },
        "date": 1784395258246,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.350415,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.882726,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.91643,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.413215,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006335,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.053711,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.50836,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070862,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.480518,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.940968,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.620845,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.432515,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.837134,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.727794,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044929,
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
          "id": "aae508f8588c6b730fc370525bc514bc16df9d5f",
          "message": "Bump softprops/action-gh-release in the github-actions group (#1633)\n\nBumps the github-actions group with 1 update: [softprops/action-gh-release](https://github.com/softprops/action-gh-release).\n\n\nUpdates `softprops/action-gh-release` from 3.0.1 to 3.0.2\n- [Release notes](https://github.com/softprops/action-gh-release/releases)\n- [Changelog](https://github.com/softprops/action-gh-release/blob/master/CHANGELOG.md)\n- [Commits](https://github.com/softprops/action-gh-release/compare/718ea10b132b3b2eba29c1007bb80653f286566b...3d0d9888cb7fd7b750713d6e236d1fcb99157228)\n\n---\nupdated-dependencies:\n- dependency-name: softprops/action-gh-release\n  dependency-version: 3.0.2\n  dependency-type: direct:production\n  update-type: version-update:semver-patch\n  dependency-group: github-actions\n...\n\nSigned-off-by: dependabot[bot] <support@github.com>\nCo-authored-by: dependabot[bot] <49699333+dependabot[bot]@users.noreply.github.com>",
          "timestamp": "2026-07-18T22:27:37+05:30",
          "tree_id": "e98b5ed284eb1ffdda4e1c140aa6d7928ec957d7",
          "url": "https://github.com/kaappi/kaappi/commit/aae508f8588c6b730fc370525bc514bc16df9d5f"
        },
        "date": 1784396030514,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.065739,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.500577,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.934779,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.408284,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006673,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.05257,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.509716,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.067994,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.227055,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.996,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.509265,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.477189,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.746759,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.884294,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045216,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "5564ae08c473c6929dddd2695dacd719968e48c8",
          "message": "Add Windows x86_64 (x64) support (#1651)\n\n* Add Windows x86_64 (x64) support\n\nThe platform layer was already OS-gated, so both Windows architectures\nshare the same code; this wires x86_64-windows through CI, releases,\nand docs, verified end-to-end on the Windows 11 reference VM via the\nbuilt-in x64 emulation layer: unit suite 1166/0 (15 skips), thottam\nsuite, R7RS, all 436 .scm suite files, shell suites (34 pass / 15 skip,\nsame profile as aarch64), acceptance.sh 34/34, and the native-backend\ne2e 38/38 with the stock zig-x86_64-windows-0.16.0 as linker. The\naarch64-only toolchain bugs do not apply on x64: #1613 (native builds\naccess-violate) — kaappi builds natively from clean source on the box\n(verified, target x86_64-windows-gnu) — and #1607 (stripped kaappi.exe\ncrashes), so the release row ships stripped like every other platform.\n\nCI: windows-cross becomes an aarch64/x86_64 matrix (now also staging\nkaappi_rt.lib in the artifacts), and a windows-x64-test job executes\nthe same suites as windows-arm-test on windows-latest, then installs\nthe natively-working x64 Zig and runs tests/e2e/run-e2e.ps1 — the\nkaappi compile leg the arm job cannot have until the 0.17.0 bump.\nReleases gain the x86_64-windows row; post-release gains a real\nacceptance leg for it (acceptance.sh under Git Bash on windows-latest).\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n* Gate post-release summary on the new Windows x64 acceptance leg\n\nsummary's needs list and results string enumerate the jobs explicitly;\nwithout test-windows-x64 in both, a failing Windows leg would not fail\nthe workflow.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n* Fix silent truncation of CLI arguments past the 64th (#1652)\n\nOptions collected script args into a fixed [64][]const u8 and dropped\neverything past it with no diagnostic, so `kaappi fmt` over the\n573-file corpus only ever formatted/checked the first 64 files, a\nscript's (command-line) truncated at 64, and `kaappi test` ignored\nsuite paths past the cap. The fmt.sh corpus phases have therefore\nnever validated files 65+ — POSIX xargs fits all 573 paths in one\ninvocation. windows-arm-test on PR #1651 exposed it: GitHub's large\njob environment makes MSYS xargs split the list in two, `fmt` vs\n`fmt --check` argv lengths split at different boundaries, and the\nfiles in the gap were formatted by neither pass but flagged by the\nrecheck.\n\nScript args now grow in a c_allocator-backed slice — the same\nimmortal-argv convention platform.argsIterate uses — with a loud\nusage error on OOM. Regression tests: a 129-argument parse test in\ncli.zig, and a 70-file --check invocation in fmt.sh whose 70th file\nis the only unformatted one.\n\nRunning the corpus in full for the first time surfaced a second\nlatent bug: the fmt CST lexer did not know SRFI 267 raw strings, so\nthe round-trip guard refused srfi267.scm (\"formatting would change\nthe program\"). scanRawString now carves `#\"X\" content \"X\"` exactly\nlike reader_tokens.readRawString, as one verbatim atom; multiline\nraw strings never inline (computeMeasure already breaks on embedded\nnewlines). Covered by new tests_fmt.zig cases including an\nunterminated-raw-string diagnostic.\n\nThe --lib-path cap of 16 has the same silent-drop shape and is\ntracked separately (#1653).\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n* Address review: stale readiness docs, platform facade wording, strict summary gate\n\nThree CodeRabbit findings on PR #1651, all valid:\n\n- src/platform.zig's module header still described fd readiness as\n  socket-only with pipes degrading to blocking reads — stale since the\n  polled pipe backend landed (#1608 stage 2); it now describes the\n  socket/pipe/file split and names the platform_win*.zig helpers.\n- windows.md and CLAUDE.md claimed every syscall-level difference lives\n  in one file; platform.zig is the facade, with the Windows ABI and\n  socket/pipe helpers in platform_win{,_sock,_pipe}.zig.\n- post-release.yml's summary only rejected `failure`, so a cancelled or\n  skipped acceptance leg still reported success; every needed result\n  must now be exactly `success`.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-19T01:25:38+05:30",
          "tree_id": "9284fe94a53f47b4381393c144ea99a642071492",
          "url": "https://github.com/kaappi/kaappi/commit/5564ae08c473c6929dddd2695dacd719968e48c8"
        },
        "date": 1784406511620,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.062563,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.651638,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.920618,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.415552,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00684,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.052849,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.508402,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.067894,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.246658,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.983873,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.515634,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.479972,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.75469,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.909935,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.046132,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "3da3bfa0b606ff1ad6ffbfc494cff88460767ead",
          "message": "Fix --lib-path entries past the 16th being silently dropped (#1653) (#1655)\n\nTwo fixed [16] buffers capped the library search path with no diagnostic,\nthe same silent-data-loss shape as the CLI-argument cap fixed in #1652:\n\n- cli.zig's Options.lib_path_buf ([16][]const u8, guarded by\n  `if (count < 16)`) stored the explicit --lib-path entries.\n- main.zig's search-path assembly copied those plus the auto-discovered\n  dirs (script directory, ~/.kaappi/lib, exe-relative lib) into a second\n  fixed [16] local with the same guards.\n\nSo a 17th --lib-path — or the auto-discovered dirs once 16 explicit ones\nexisted — vanished silently (exit 0, no error).\n\nBoth now grow: cli.zig accumulates into a c_allocator-backed ArrayList and\ntoOwnedSlice (the same immortal argv-lifetime convention as script_args),\nand main.zig sizes its assembly buffer to opts.libPaths().len + 3 (the\nthree possible auto-discovered dirs) and drops the four `< 16` guards. The\nassembly buffer is deliberately never freed: vm.lib_paths points into it\nand is read as late as the deferred coverage report, and it aliases the\nalready-immortal klp/elp path strings — so it must live for the whole run.\n\nRegression tests fail without the fix and pass with it: a cli.parse unit\ntest (20 --lib-path entries all survive) and an end-to-end shell test\n(tests/scheme/smoke/lib-path-many-1653.sh) covering both failure shapes —\na library in the 20th explicit path, and the auto-discovered script dir\nsurviving 16 explicit paths — with a no-library negative control.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-19T02:41:37+05:30",
          "tree_id": "ad6104916e04975afccb37e2c9b3ddb578821c86",
          "url": "https://github.com/kaappi/kaappi/commit/3da3bfa0b606ff1ad6ffbfc494cff88460767ead"
        },
        "date": 1784411101582,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.026158,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.676407,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.843269,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.971282,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006456,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.050574,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.449372,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.064598,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.416316,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.661431,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.471442,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.403689,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.661294,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.932909,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.039981,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "dad1401200fbbdd59430fd372221dca2a67dbd74",
          "message": "Document the native-backend architecture-scope decision (#1658)\n\nThe #1654 port campaign proved interpreter-tier CPU ports are free, and\nits riscv64 experiment proved the native backend is not: kaappi compile\non an unsupported arch links via the -w-hidden driver override of the\nunknown-unknown-unknown triple and produces a binary that segfaults\n(#1656). Record why the backend stays aarch64/x86_64 — triage ergonomics\n(no ppc64le unwinder), the runtime tether (21 C-ABI exports + eval\nfallback), per-arch LLVM variance, and the e2e-on-target verification\nbill plus permanent matrix tax — and what a real port would take, with\nriscv64 as the designated pathfinder.\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-19T03:04:23+05:30",
          "tree_id": "f9cb7e65a8f7819bf9b2e95b9e44ddfe48f1eef0",
          "url": "https://github.com/kaappi/kaappi/commit/dad1401200fbbdd59430fd372221dca2a67dbd74"
        },
        "date": 1784412674188,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.032694,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.414326,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.924354,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.562605,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00672,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.052758,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.514228,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068486,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.216695,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.9992,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.507379,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.47339,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.744144,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.839382,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.047858,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "12f4bbe0ebd4396d8adfaa4e61deb4bb7cbcd918",
          "message": "Add Linux s390x and ppc64le support (interpreter tier) (#1657)\n\n* Add Linux s390x and ppc64le support (interpreter tier)\n\nBoth architectures cross-compile with zero runtime code changes and pass\nthe full battery — unit suite, thottam suite, R7RS (1395/1395), and the\ntests/scheme/ suites — under QEMU user-mode and on real-kernel Alpine\nVMs. s390x is the first big-endian target: the endian-explicit .sbc\ncodec round-trips unchanged, so the new s390x-test CI job now guards\nbyte-order correctness permanently. Real-kernel VA layouts confirm the\n48-bit NaN-box pointer precondition empirically (s390x stays below\n2^42; ppc64le below its 2^47 default map window).\n\nThe native LLVM backend stays aarch64/x86_64-only, like riscv64.\ncrash-handler.sh now asserts trace addresses only when Zig's unwinder\nproduced a trace at all — ppc64le prints \"(empty stack trace)\" (no\nframe-walk in Zig 0.16's std there), and the banner cannot retain what\nstd never emits.\n\nCloses #1654\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n* Align README riscv64 row with porting.md: interpreter only\n\nREADME claimed an LLVM backend for Linux riscv64, but porting.md states\nriscv64 ships interpreter-only and llvm_emit.zig's emitPreamble emits a\nreal target triple only for aarch64/x86_64 — every other arch gets\n\"unknown-unknown-unknown\", which only the -w on the zig cc link lets\nthe driver override with the host triple. Nothing CI-tests native\ncompilation on riscv64, and untested support is not support.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-18T21:47:20Z",
          "tree_id": "10f4aab94283e533decf55f83a7abc1afac6144c",
          "url": "https://github.com/kaappi/kaappi/commit/12f4bbe0ebd4396d8adfaa4e61deb4bb7cbcd918"
        },
        "date": 1784413843389,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.212226,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.248772,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.769658,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.620751,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.005248,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.041644,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.414291,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.054004,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.608861,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.613481,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.183585,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.375352,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.346461,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.472234,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.037755,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "935a98691ad13b62132e07dc1bde113d281c63b9",
          "message": "Refuse native compilation on unsupported arches (#1659)\n\nCloses #1656.\n\n`kaappi compile`/`--emit-llvm` on a host the LLVM backend can't target (anything but aarch64/x86_64 × the six supported OSes) emitted a non-concrete `*-unknown-unknown` triple that the `-w` link silently overrode with the host default — the link succeeded and produced a segfaulting binary, worse than an honest failure. A single-source-of-truth `targetTriple` now returns null for such hosts; `emitLlvmFile` refuses before any codegen (exit nonzero, names the arch, points at the interpreter), and `kaappi doctor` reports one honest `arch` WARN instead of the misleading c-compiler/archive/smoke-link PASS trio. Verified end-to-end on riscv64 under QEMU; aarch64/x86_64 native compile unaffected.",
          "timestamp": "2026-07-19T07:09:36+05:30",
          "tree_id": "284d2b997fbf5ad64a787b387239ad35b8872ba6",
          "url": "https://github.com/kaappi/kaappi/commit/935a98691ad13b62132e07dc1bde113d281c63b9"
        },
        "date": 1784427031754,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.580832,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.8407,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.727039,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.593444,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006629,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.048014,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.407323,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.058538,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.272089,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.566059,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.4172,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.446864,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.553308,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.912157,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.038189,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "a3b4157756061c240c382780cbcef5e824220649",
          "message": "Add srfi-<n> cond-expand feature identifiers (#1660)\n\nCloses #1649.\n\nR7RS implementations conventionally advertise each supported SRFI as a\ncond-expand feature identifier (srfi-1, srfi-64, ...) so a program can\nprobe support without attempting an import. Kaappi exposed none, so\n(cond-expand (srfi-1 ...) (else ...)) always took the else branch despite\nthe interpreter shipping SRFI 0 itself.\n\nResolve srfi-<n> by routing through the same availability check as\n(library (srfi <n>)) (libraryIsAvailable), so built-in, portable,\n--sandbox and WASM answers all match what (import (srfi <n>)) would do --\nnothing hardcoded (the #1517 derive-don't-list principle). SRFI 261 is the\none supported SRFI with no library file, so srfi-261 answers true directly.\n\nA single implementation (vm_library.srfiFeatureAvailable) serves both\nfeature-req evaluators: evalLibFeatureReq (define-library) calls it\ndirectly; the compiler's evalFeatureReq reaches it via a new\nglobals.srfiFeatureAvailable callback the VM registers, mirroring the\nlibrary_exists_checker used by the (library ...) form.\n\nLike a (library ...) requirement, a srfi-<n> identifier is a derived probe\ncond-expand resolves on demand, not a bare feature, so (features) stays the\nplatform/subsystem table it must equal at the kaappi features CLI boundary\n(#1517); kaappi features notes the ids in its SRFIs section.\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-19T08:41:08+05:30",
          "tree_id": "0c6a2542cb7130a26df678c50aff5ad197934842",
          "url": "https://github.com/kaappi/kaappi/commit/a3b4157756061c240c382780cbcef5e824220649"
        },
        "date": 1784432644520,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.069008,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.54678,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.924093,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.428649,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006789,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.05242,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.511286,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.06802,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.274651,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 2.001286,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.502079,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.480886,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.726371,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.889916,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045917,
            "unit": "seconds"
          }
        ]
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
          "id": "3e7986d6165d127ad85e99a44b33ad0b7e7e5af3",
          "message": "Release v0.20.0",
          "timestamp": "2026-07-19T11:00:54+05:30",
          "tree_id": "65d7f1b38d839def0a9bbc258d7804f1b897ea85",
          "url": "https://github.com/kaappi/kaappi/commit/3e7986d6165d127ad85e99a44b33ad0b7e7e5af3"
        },
        "date": 1784441256924,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.007265,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.822118,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.636733,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.042173,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.005579,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.038896,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.344728,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.05047,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.696289,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.311803,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.134202,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.372243,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.245831,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.79404,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.033164,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "d8cdaf53cac57d2d94d2421e0a61a1bf83c7fcca",
          "message": "Report the real dlopen failure from ffi-open (#1662)\n\nffi-open probes several candidates (name as-is, platform suffixes,\n<home>/lib/ with suffixes) but reported dlerror() only after the last\nprobe — and dlerror only remembers the most recent failure. A library\nthat existed but refused to load (macOS code-signing rejection, wrong\narchitecture, corrupt file) was therefore reported as \"no such file\"\nfor a fallback path the user never asked for.\n\nTwo changes:\n\n- Snapshot per-candidate failures and report, in order of preference:\n  the first candidate that exists on disk but failed to load, else the\n  as-is attempt's error (prefixed with the requested name when the\n  platform's dlerror text doesn't contain it, e.g. Windows' bare\n  \"Win32 error N\") plus a note listing the other probes. The dlerror\n  text is clamped so the note survives the 256-byte detail buffer.\n\n- Skip the <home>/lib/ fallback for names containing a path separator,\n  matching dlopen(3) semantics where a slash means pathname, not search\n  key. Previously an absolute path produced nonsense probes like\n  \"<home>/lib//abs/path/libfoo.dylib.so\" — whose \"no such file\" then\n  masked the real error. All ecosystem packages pass bare names, so\n  nothing relied on the old behavior.\n\nMotivating repro: with libkaappi_math.dylib present in ~/.kaappi/lib\nbut rejected by library validation, (import (kaappi math)) reported\nonly \"no such file\" for ~/.kaappi/lib/libkaappi_math.so and never the\nvalidation error for the .dylib that exists. Since the library passes\na bare name, the interesting error came from a mid-order candidate —\nwhich is why existence, not probe order, selects the reported error.\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-19T07:41:12Z",
          "tree_id": "f4ee62349d8f4cb8840c65801b2941e1f1d91741",
          "url": "https://github.com/kaappi/kaappi/commit/d8cdaf53cac57d2d94d2421e0a61a1bf83c7fcca"
        },
        "date": 1784448966947,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.443335,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.954518,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.912342,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.442541,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006375,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.053645,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.497193,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069244,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.572538,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.953883,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.618425,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.441765,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.837112,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.713689,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044657,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "e3591242436f6eafc23d0d7032e7206c6a48c02b",
          "message": "Splice top-level cond-expand into top-level forms (#1661) (#1663)\n\n* Splice top-level cond-expand into top-level forms (#1661)\n\nA `cond-expand` at the top level was compiled as an ordinary expression, so\nan `import` (or any top-level-only declaration) nested in the matched clause\nwas mis-compiled: `(srfi 1)` read as a call to an undefined `srfi`, printing\n`KP3001 undefined variable 'srfi'` and exiting 1 — even though the import's\nside effect still ran. This defeated the idiomatic #1649 probe\n`(cond-expand (srfi-1 (import (srfi 1))) (else ...))`.\n\nR7RS 4.2.1 says a top-level cond-expand expands to the selected clause's forms\nin a top-level context. Make `handleTopLevelForm` recognize `cond-expand`:\nselect the first satisfied clause (or `else`) with the existing\n`evalLibFeatureReq` — the same live-registry evaluator `define-library` uses,\nso `else`, `(library (srfi N))`, and the `srfi-N` feature ids all resolve\nidentically — then splice its body through `handleTopLevelBegin`, exactly as\ntop-level `begin` already does. `isSpecialTopLevelForm` learns `cond-expand`\ntoo so the native eval-cache declines it. Expression-position `cond-expand`\n(inside `define`, as an argument, ...) is untouched: it never reaches\n`handleTopLevelForm` and still goes through the compiler.\n\n`kaappi check` had the same splitting bug surfacing as spurious `KP4001`\nwarnings — the clause compiled as an expression flagged `srfi`, and a `define`\nnested in a matched clause was never gathered as a top-level name so a forward\nreference warned. Mirror the splice in `check.zig`: `checkForm` recurses into\nthe selected clause (like `begin`), and `collectFromForm` gathers names from\nevery clause body (no VM there to pick one — the same conservative\nover-approximation `test_selection.zig` already uses).\n\nRegression coverage: runtime splice/import + expression-value unit tests\n(tests_libraries.zig), check unit tests (tests_check.zig), and a top-level\nimport-in-cond-expand exit-code case (errors/exit-code.sh).\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>\n\n* Address review: re-entrancy-safe splice + malformed-tail parity (#1661)\n\nTwo fixes from CodeRabbit review of #1663:\n\n- handleTopLevelBegin ran the selected top-level body with vm.execute(), which\n  resetExecutionState and corrupts frame 0 when eval is re-entered from a native\n  callback (frame_count != 0) — the case runTopLevelFunction was added to\n  handle. Route through runTopLevelFunction instead; it is identical to\n  vm.execute at true top level and re-entrant otherwise. This is a latent bug in\n  top-level begin that the new cond-expand splice now also reaches.\n\n- handleTopLevelCondExpand silently yielded void for an improper clause-list\n  tail reached without a match (e.g. `(cond-expand (x 1) . junk)`), where the\n  expression-position compiler reports a syntax error. Reject it to match. (A\n  matched clause still returns immediately without inspecting later clauses,\n  exactly as the compiler does — so trailing clauses after a match are not\n  validated in either position; verified, and covered by a new parity test.)\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>\n\n* Reject improper cond-expand clause bodies at top level (#1661)\n\nSecond-pass review follow-up: `(cond-expand (else 1 . junk))` at top level\nspliced the proper prefix and silently dropped the improper tail (via\nhandleTopLevelBegin), while the expression-position compiler rejects the same\nform. Validate the selected body is a proper list in handleTopLevelCondExpand\nbefore splicing, so cond-expand's own structure is fully validated to match the\ncompiler. handleTopLevelBegin (shared with top-level begin) is left untouched —\nbegin's tail leniency is a separate, pre-existing concern.\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-19T09:24:38Z",
          "tree_id": "a47695090ead83066fc9c042bcdc8c2c6e878ce1",
          "url": "https://github.com/kaappi/kaappi/commit/e3591242436f6eafc23d0d7032e7206c6a48c02b"
        },
        "date": 1784455398187,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.299699,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.074594,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.912265,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.421946,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006762,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.052786,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.502182,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068851,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.419407,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.952086,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.575918,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.439517,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.847171,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.727213,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043674,
            "unit": "seconds"
          }
        ]
      }
    ]
  }
}