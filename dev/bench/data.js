window.BENCHMARK_DATA = {
  "lastUpdate": 1785680169464,
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
          "id": "9f1c323f402bd5265086faa059bd861df592c4c4",
          "message": "Say what R6RS rejected, instead of raising a bare type error (#1880)\n\n`define-record-type`'s R6RS clause syntax had two conditions that reported\n`error[KP3002]: type error` and nothing else -- no procedure, no expected\ntype, no value, the three things KP3002's own registry entry promises. Both\nreproduce in five lines: a sealed parent rtd, and a `nongenerative` uid\nalready bound to a non-equivalent type.\n\nNeither is a type error. Both arguments are of a perfectly good type and the\nprocedure rejects them anyway, which is what KP3007 (invalid-argument) is\nfor -- and R6RS's own wording for the first is \"an exception is raised if\nparent is sealed\", nothing about types.\n\nThe procedural half of the same two rules (`%make-record-type-descriptor`)\nhas been getting this right since #1868, so the fix is to stop stating the\nrule twice: `RtdShape`, `sealedParentError` and `reuseNongenerativeRtd` in\nprimitives_srfi237.zig now hold both the equivalence test and its wording,\nand the syntactic and procedural routes share them. Only the procedure name\ndiffers -- a caller who wrote `define-record-type` should not be told about\nthe internal primitive it desugars to. A uid collision now names the one axis\nthat actually differs rather than listing every axis it might have been.\n\nReading those two functions turned up a third condition of the same shape\nthat #1880's census could not see, because it is spelled as a `return switch`\narm rather than a bare return: more than 255 fields once a parent's are\ncounted. Its procedural half was the worse of the two -- a bare TypeError out\nof a primitive is not anonymous, `mapNativeError` fills the detail in from\n`args[0]`, so it confidently blamed the type's *name* for a limit the field\nlist broke.\n\nAlso folds `callFfi`'s four call sites into one `vm_calls.mapFfiError`. Two\nof them supplied a fallback message when callFfi returned without setting a\ndetail and two did not, and the two that did not are the hot ones. That is\nlatent today -- callFfi guarantees a detail on every path it can currently\nfail through -- but one shared mapper is cheaper than separate copies of the\nsame guard staying in sync. Worth knowing for anyone testing this: the four\nsites are *not* reached by direct call / apply / map, which all land in\nvm_calls.zig; the two vm_dispatch.zig sites are the tail-call and tail-apply\nopcodes, so the regression test uses tail-position forms.\n\nThe two remaining bare returns outside ffi.zig already call `setErrorDetail`\non the line above and are now annotated as such, leaving every non-FFI site\nin src/ either fixed or carrying a stated reason.\n\nNot done: ffi.zig's 27 sites (the issue's Group D), which are internal\npass/fail signalling behind `validateArgsDetailed` -- retagging them would\nchange nothing a user sees and would break the caller's switch. The\n`format` job's grep is unchanged; widening it is now a single question about\nthose 27 rather than a mixed bag.\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-31T08:52:21+05:30",
          "tree_id": "7ea2e112ab6fae5ee525bfdd6b07ff6533a21058",
          "url": "https://github.com/kaappi/kaappi/commit/9f1c323f402bd5265086faa059bd861df592c4c4"
        },
        "date": 1785470289832,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.300079,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.89231,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.580175,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.981307,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004642,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046457,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.311103,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057056,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.616138,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.232008,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.578073,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.280976,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.797544,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.486603,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.046708,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "3fbfc0a575efff60ad66152ef7b62e5b3e799268",
          "message": "Let a record's constructor be named `fields` or `parent` (#1882)\n\nSRFI 237's R6RS clause grammar is ambient — `(scheme base)`'s\n`define-record-type` accepts it with no `(import (srfi 237))` — so the two\nsyntaxes are told apart structurally. The detector inspected only the head\nof the form's 2nd element, which in R7RS syntax is the *constructor's*\nname, so `(define-record-type point (fields x y) point? (x point-x) (y\npoint-y))` was parsed as R6RS and rejected. Nothing in such a program\nsignals that the R6RS grammar is in play, and the diagnostic was a bare\nKP2001 whose follow-on `undefined variable 'fields'` pointed away from the\ncause.\n\nThe 3rd element separates the grammars unambiguously: R7RS always has one\nand it is always the bare-symbol `<predicate>`, while an R6RS `<record\nclause>` is always a list — or absent, when there is at most one clause.\nAdding that as a second condition is a pure narrowing, so every R6RS form\nkeeps its path and every malformed form keeps its diagnostic; only valid\nR7RS forms move.\n\nTwo paths beyond the top-level handler shared the misdetection. In a body\nit aborted the internal-define scan, so sibling `define`s written after\nthe record lost their mutual visibility. In a library body, where the R6RS\ngrammar is rejected outright as a documented top-level-only feature, the\nwhole library failed to load.\n\nTests: a compliance suite with a library fixture (18 assertions, 8 of them\nfailing before the fix) plus three unit tests — the R7RS one demonstrates\nthe fix, the R6RS-detection and malformed-form ones bound it.",
          "timestamp": "2026-07-31T11:20:10+05:30",
          "tree_id": "998eea705c31025c9b6744147610e7f0e8726ec9",
          "url": "https://github.com/kaappi/kaappi/commit/3fbfc0a575efff60ad66152ef7b62e5b3e799268"
        },
        "date": 1785479085311,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.055786,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.203136,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.43785,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.215485,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.003795,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.034516,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.231392,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.042579,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 1.774703,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.917524,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.175114,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.237565,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.312865,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.381513,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.035481,
            "unit": "seconds"
          }
        ]
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
          "id": "40f04a6db595e198ccd8008a513184ab9ddd798a",
          "message": "Release v0.22.1\n\nBug fixes and diagnostics. Three native-backend correctness fixes: an\ninternal define in a `let` body was never GC-rooted (#1854), the procedure\nshorthand `(define (f ...) ...)` compiled to a global define (#1861), and a\nnested `let` falling back to the interpreter lost the enclosing scope\n(#1862). Plus the `(srfi 120)` Windows wedge (#1870) and a library body that\ncould not reference an unimported global from its own top level (#1860).\n\nThe user-visible surface change is #1856: `(scheme base)` no longer exports\n22 `%`-prefixed internal primitives, so a user library defining its own\n`%name` loads again under v0.22.0's R7RS 5.2 enforcement. The ones portable\n`.sld` files need move to a new `(kaappi primitives)`.\n\nDiagnostics: every type error now names the expected type and the right\nargument (#1868), an uninitialized runtime reports KP9001 instead of a\ncaller type error (#1874/#1876/#1878), and two R6RS record conditions\nreport KP3007 rather than a bare KP3002 (#1880).\n\nBuilt-in procedures 690 -> 689 (`%length` deleted). The count command in\nthe release skill was undercounting by 2 -- it greps only for literal\n`.name = \"...\"`, and two entries converted to named constants this cycle --\nso it now resolves those too.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-31T11:50:24+05:30",
          "tree_id": "dc5bbbf2a11807643f675b30b34648ed25440706",
          "url": "https://github.com/kaappi/kaappi/commit/40f04a6db595e198ccd8008a513184ab9ddd798a"
        },
        "date": 1785482014724,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.3059,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.582863,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.571659,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.978246,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004648,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046357,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.310691,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057033,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.602668,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.231199,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.572815,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.278719,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.800123,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.620418,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043836,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "261fde5fad3c3d65cda83fdd507ce5d14cee729a",
          "message": "Gate publishing on CI, and ask for a changelog entry while it is cheap (#1885)\n\nv0.22.1 went public at 06:35:24 with ci.yml still running on the same\ncommit, and would have published identically had CI failed. The tag push\nand the branch push start release.yml and ci.yml as two independent runs\nwith nothing between them, so they race and publishing wins. The only\nthing that actually gated that release was a local test run.\n\nA new `ci-gate` job polls for the ci.yml run on the tagged SHA and only\nthe `release` job depends on it, so the 14 platform builds still run in\nparallel with CI -- gating costs no wall clock unless CI is the long pole.\nAbsence of a run is retried rather than treated as failure, since a tag\npushed alongside its branch can beat its own CI run into existence; a\nconcluded-but-not-successful run (including `cancelled`) refuses to\npublish. The workflow gains `actions: read`, without which the poll would\n403 -- declaring any `permissions:` block zeroes every scope not listed.\n\nThe changelog half addresses a different recurring miss: `[Unreleased]` is\nreconstructed from `git log` at release time rather than written as the\nwork lands, and had 14 of 100 commits at v0.22.0 and 5 of 16 at v0.22.1.\nA PR touching src/ or lib/srfi/ without touching CHANGELOG.md now fails,\nwith a `no-changelog` label for changes that are genuinely not\nuser-visible. Labels are read live via the API rather than from\ngithub.event, because re-running a job replays the original event payload\n-- a label added in response to the failure would otherwise be invisible\nto the re-run, making the documented escape hatch a dead end.\n\nAlso corrects two things the v0.22.1 run surfaced in the release skill:\nthe build-target list said 12 where the matrix ships 14 (s390x and\nppc64le were missing, both present in the released assets), and the\nNetBSD denormal probe imported (srfi 144), which needs ~/.kaappi/lib and\nso fails on a fresh VM as `undefined variable 'fl-least'` -- reading as a\ndenormal regression on the one platform whose FPCR fix it guards. The\nlibrary-free `5e-324` spelling tests the same thing with no import.\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-31T13:08:23+05:30",
          "tree_id": "b2a7bbed1d42d32efd3baa3a2e7685fb4d8c6579",
          "url": "https://github.com/kaappi/kaappi/commit/261fde5fad3c3d65cda83fdd507ce5d14cee729a"
        },
        "date": 1785485901359,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.318459,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.998063,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.582215,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.982443,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004751,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046463,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.311828,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057339,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.604341,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.231106,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.580214,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.278186,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.797204,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.626622,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044503,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "12588782c29762552483fa03b64786a3232e731b",
          "message": "Rewrite the audit strategy for a codebase that now has fuzzers (#1889)\n\nThe v1 campaign (#1137) closed on 2026-07-05 and its document still\ndescribes what it audited: ~39k lines, 578 procedures, 21 primitives\nfiles, 72 SRFIs. Since its base commit that is 417 commits and +67k\nlines ago. 132 of 162 .sld files and 166 of 200 SRFI tests postdate it,\nso for most of the tree a second campaign is a first audit, not a\nre-audit — and ten primitives files have no audit test at all.\n\nTwo things change the shape of the work rather than just its size.\n\nThe project now runs nightly differential fuzzing with three oracles\n(opt-vs-no-opt, VM-vs-native, Kaappi-vs-Chibi). v1 predates all of it,\nso v2 is scoped explicitly as the complement: fuzzers own crashes and\ntier divergence inside a generated subset, the audit owns breadth and\nanything whose oracle is a document rather than the implementation's\nother half. Without that split the obvious next campaign would spend\nits budget rebuilding harnesses that already run every night.\n\nAnd a large fraction of the remaining work is documentation truth, not\ntesting. Five of the six expander limitations CLAUDE.md lists as open\nare fixed; the eval_fallback_form_names hazard it warns about has\nmigrated to a different, still hand-maintained list; the SRFI 58/163\nexclusions rest on two statements that are now false. An auditor\ntrusting the docs today loses sessions to bugs fixed months ago, which\nis why the truth pass is Phase 0 and not an afterthought.\n\nA seven-agent reconnaissance pass fed the rewrite and is recorded in\nit: 13 reproduced findings against a fully green suite (624/624 Scheme\nfiles, 1395/1395 R7RS assertions). That gap is the campaign's\njustification — the suite is green because it does not ask these\nquestions, not because the answers are right.\n\nThe audit-primitives skill is updated in the same commit because every\nPhase 2 session loads it and it had drifted onto the old\n`try reg(vm, ...)` registration and a 18-of-31 file list.\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-31T15:02:02+05:30",
          "tree_id": "6cb49d8cb3805204fa855918b2bda28f91a115f7",
          "url": "https://github.com/kaappi/kaappi/commit/12588782c29762552483fa03b64786a3232e731b"
        },
        "date": 1785493530297,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.935647,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.864529,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.562005,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.832828,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004842,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.044575,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.293627,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.054868,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.284727,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.158065,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.511626,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.301755,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.68899,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.783272,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.046638,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "c6040f1802c2e54b7068a0d632a36bb99cfedbb4",
          "message": "Tick Phase 0A and point the tracker at the filed issues (#1904)\n\nThe document calls its progress tracker the single source of truth for\nwhat is done, so leaving 0A unticked after running it contradicts the\nrule the campaign is meant to enforce — the first session to read it\nwould have re-run the baseline and re-filed thirteen issues.\n\nRecords the green baseline, the tracking issue, and the twelve issue\nnumbers. Also notes that reproducing F12 before filing corrected it: a\nflat cdr-cycle prints its label correctly, and only a car-nested cycle\npast the depth limit loses one. The reconnaissance table keeps the\nrepro recipes, since those are what a fixer needs and the issues\nduplicate rather than replace them.\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-31T15:42:35+05:30",
          "tree_id": "4d609c6de114ec2e3a4175b0615a4302f7baae5e",
          "url": "https://github.com/kaappi/kaappi/commit/c6040f1802c2e54b7068a0d632a36bb99cfedbb4"
        },
        "date": 1785500102341,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.942564,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.072483,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.560011,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.844202,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.0049,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.044633,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.293514,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.054836,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.29169,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.157576,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.519576,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.299184,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.685114,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.732877,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044263,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "6d621fc7f3afe0e9bf713c9810475bf35758014c",
          "message": "Correct six documentation claims that no longer describe the code (#1905)\n\nPhase 0B of the v2 audit campaign (#1901). Every claim was re-verified\nagainst v0.22.1 before being edited, which matters more than usual here:\nthe point of the pass is to stop propagating unverified statements, so\ntaking the reconnaissance report on faith would have reproduced the\nfailure mode it was meant to fix. Two findings changed under that check.\n\nThe native-backend warning was aimed at the wrong list.\neval_fallback_form_names is comptime-derived and self-maintaining; the\nhand-maintained array that can actually cause a silent miscompilation is\nisRejectedFormHead, which is already missing define-property (#1896).\nAnyone adding a form was being pointed at the safe list.\n\nSRFI 148 was recorded as 134 passing with 8 test-expect-fail. It is 142\npassing with none. The reconnaissance also called the test file's header\ncitations dead comments; reading it showed the opposite — the header\ndocuments both fixes accurately and is worth keeping, so the note now\nsays to read it rather than distrust it. Repo-wide there are 6\ntest-expect-fail calls, 4 of them in srfi150.scm, which matches that\nfile's reported count exactly and disproves the claim that two never\nexecute.\n\nThree limitations documented as open are fixed: the let-syntax chain\nproducing define-syntax, library-body shadowing of define-record-type,\nand (already noted elsewhere) the ellipsis leniency. The shadowing note\nnow records the trap that made it look broken — bind a name from the\nmacro's pattern, not one introduced by its template, or hygiene renames\nit and the test fails for an unrelated reason.\n\nThe SRFI 120 corruption claim does not reproduce. Both documented entry\npaths now fail cleanly and deterministically across 10 runs, because a\n<timer> holds a Fiber that gc_deep_copy rejects outright, so the\nsingle-thread constraint is engine-enforced rather than a hazard to\ndesign around. The re-check's limits (macOS, ReleaseSafe, no gc-stress)\nare recorded alongside it — stale claim, not proof the bug never existed.\n\nThe SRFI 58 and 163 exclusions rested on \"SRFI 160 has no implementation\nat all\" and \"SRFI 4 is a purely portable wrapper\". Both are false now, so\neach entry drops to a single reader-ambiguity blocker and both SRFIs\nbecome re-considerable.\n\nFinally, tests/scheme/CLAUDE.md's directory table was missing six suites\nthat exist and run, and said nothing about run-all.sh's globs being\nnon-recursive — the reason tests/scheme/srfi/slow/ has never run (#1900).\nThat stale table is what sent a reconnaissance agent chasing a\n\"tests exist but never run\" headline that turned out to be false.\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-31T15:45:08+05:30",
          "tree_id": "59aac2a19d1c488ca2527790782f66af787d2428",
          "url": "https://github.com/kaappi/kaappi/commit/6d621fc7f3afe0e9bf713c9810475bf35758014c"
        },
        "date": 1785504205910,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.388724,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.202274,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.597258,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.048954,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004692,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.047007,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.318063,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.059108,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.624791,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.251477,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.612267,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.29035,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.821671,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.624745,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.047755,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "61f6e8c48003b4674677737513f975a7eed71233",
          "message": "Phase 2.1: internal-primitive audit — 239 assertions over a 51-procedure surface with no prior tests (#1918)\n\n* Audit the %-prefixed internal-primitive surface (audit v2, Phase 2.1)\n\nEvery registered primitive spec lands in vm.globals regardless of its\n`libs` tag -- only *export* is gated -- so all 60 `%`-prefixed specs in a\ndefault build are callable from a plain top-level script with no import\nat all. 51 of them are reachable that way today; the other 9 are the\npurged `internal_helpers` (8) plus the instrument-only build hooks.\nBetween them they had close to zero mention anywhere in tests/.\n\n239 assertions across the record substrate (R7RS and R6RS/SRFI 237),\nSRFI 160 numeric vectors, SRFI 271 random ports, SRFI 181 transcoded\nports, SRFI 248 unwind handlers, the parameter internals, the SRFI 27\nsubstrate, and the sysinfo probes. Each procedure is probed for arity at\nboth bounds, wrong types in *each* argument position independently, and\nboundary values (negative and just-past-the-limit indices, empty inputs,\nper-kind numeric range ends).\n\nDiscovery only -- no source is changed. 14 assertions are commented out\nbehind `;; FAIL: TBD` markers covering seven distinct defects, each\npaired with an enabled discriminating control that proves the failure is\nspecific rather than a whole-codebase convention. The three cross-tier\nassertions marked \"(fails on wasm32)\" pass natively and fail under\nwasmtime, pinning an index-truncation divergence.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Point Phase 2.1 FAIL markers at the filed issues\n\nCommitted with placeholders before the issues existed; each now names the\nissue whose fix re-enables it.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-31T16:08:10+05:30",
          "tree_id": "9d84885761abdb3c4ab8d665babb6ddece93b148",
          "url": "https://github.com/kaappi/kaappi/commit/61f6e8c48003b4674677737513f975a7eed71233"
        },
        "date": 1785505306939,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.944945,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.379032,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.564248,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.844358,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004882,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.0445,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.293462,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.054817,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.309844,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.158526,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.513685,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.30613,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.697198,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.803746,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.046008,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "1c3dec04c7ed3571f4a526d2c0fdca6d104abd96",
          "message": "Run the test suites in parallel, and stop sleeping through them (#1887)\n\n* Run the test suites in parallel, and stop sleeping through them\n\n`bash tests/scheme/run-all.sh` took 17.8 min on a 4-core box to do about\n90s of actual work. Two independent causes, fixed here.\n\n**The poll interval.** `wait_with_timeout` polled a spawned child with\n`sleep 1`, so every one of the ~620 spawned units cost a full second of\nwall clock no matter how fast it really was — and 381 of the 566 .scm\nfiles finish in under 50ms. That single sleep was ~93% of the script's\nruntime. The tick is now 0.05s, counted in 20ths of a second so the\ntimeout keeps its exact meaning, with an integer fallback if a platform's\n`sleep` rejects fractions.\n\n**No parallelism.** Each .scm file is already a fresh interpreter with no\nshared state, so `run_suite` now dispatches KAAPPI_TEST_JOBS at a time\n(default: one per CPU; 1 restores strictly-sequential). Workers write\ntheir verdict to a slot and the parent tallies and prints afterwards in\nglob-sorted order, so output ordering and the counters are unchanged. An\naudit of the corpus found no cross-file collisions on fixed paths or\nports before turning this on.\n\nShell suites stay sequential: several call `ensure_runtime_lib`, which\nruns `zig build lib` into the shared zig-out/lib, so concurrent scripts\nwould race over one output archive. They are now the larger half of the\nremaining wall time.\n\n`kaappi test` gets the same treatment via `-j`/`--jobs`, which its own\ndocs already anticipated. Worker threads claim files from an atomic\ncounter while the main thread reports the completed prefix in file order,\nso verdicts and output ordering are identical at any job count. The emit\npath now travels in the child's own envp: setenv on the parent before\neach fork is a single mutable global shared by every in-flight worker,\nand two concurrent spawns would have sent both children to the same path\nand lost a result. Windows stays at one job, where that env is still\ninherited from the parent.\n\nMeasured on 4 cores, all three producing identical results\n(2019 pass, 0 fail):\n\n    run-all.sh, before                1070s\n    run-all.sh, KAAPPI_TEST_JOBS=1     425s   2.5x\n    run-all.sh, default (4 jobs)       279s   3.8x\n    kaappi test tests/scheme/srfi     18.5s -> 4.6s   4.0x\n\ntests/scheme/test-runner/jobs.sh pins the parity down by diffing whole\ntranscripts between --jobs 1 and --jobs 4, including a deliberately\nslow-first fixture so a reporter that emitted in completion order would\nfail even though its totals stayed correct.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\nClaude-Session: https://claude.ai/code/session_01Qk6ip9ctt9dJANetqdwDMm\n\n* Address review: validate KAAPPI_TEST_JOBS, cover resolveJobs, sharpen docs\n\nThree findings from CodeRabbit on #1887, all valid.\n\n`KAAPPI_TEST_JOBS` was never validated — only `detect_jobs`'s own output\nwas. `[[ $running -ge $JOBS ]]` evaluates its operands arithmetically, so\na non-numeric value is silently 0: `KAAPPI_TEST_JOBS=abc` did not fail,\nit quietly serialised the run with a spurious `wait` per file, and still\nreported success. A typo in a CI env var should not cost a 4x-slower\nsuite that looks fine. Bad values now exit 2 with the offending value\nnamed. `0` is rejected in `detect_jobs` too, where it would have been\npassed through as a valid count.\n\n`resolveJobs` is pure and encodes the platform policy the rest of the\nfeature rests on, so it gets direct unit coverage: zero and one file,\na request above the file count, an explicit `--jobs 1`, and auto —\nwith the Windows and single-threaded expectations gated on the same\ncomptime conditions the function itself uses.\n\nThe `--jobs` doc claimed output is identical at any job count without\nnoting that durations obviously are not; it now says the test normalises\nthe `…ms` fields and then requires a byte-for-byte match, which is what\njobs.sh actually does.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\nClaude-Session: https://claude.ai/code/session_01Qk6ip9ctt9dJANetqdwDMm\n\n* Add the CHANGELOG entry the `changelog` CI job requires\n\nThe PR touches src/, and `kaappi test --jobs` is a new user-facing flag,\nso this is a real entry rather than the `no-changelog` escape hatch.\n\nRecords the flag itself and, under Fixed, the emit-path race it required\nclosing — worth stating separately because it was a latent correctness\nbug in shipped code, even though nothing could reach it while spawns\nwere serialised.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\nClaude-Session: https://claude.ai/code/session_01Qk6ip9ctt9dJANetqdwDMm\n\n---------\n\nCo-authored-by: Claude <noreply@anthropic.com>",
          "timestamp": "2026-07-31T16:19:37+05:30",
          "tree_id": "9a209b851b025a51669a094eae25d72bc844b930",
          "url": "https://github.com/kaappi/kaappi/commit/1c3dec04c7ed3571f4a526d2c0fdca6d104abd96"
        },
        "date": 1785506313723,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.346949,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.970683,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.590433,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.982932,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004741,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.047208,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.318695,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.05739,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.661153,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.231094,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.616613,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.284512,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.79793,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.611677,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044051,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "2903f3532d14576629b5dcd949643a81aea2371d",
          "message": "Phase 1A: reader exactness audit — 128 assertions, 5 new bugs including a process-abort panic (#1917)\n\n* Add Phase 1A reader-exactness audit tests\n\nAudit v2 Phase 1A: `#e`/`#i` over the i64 boundary and reader vs\n`string->number` parity, against R7RS 6.2.5, 6.2.7 and 7.1.1.\n\n128 assertions pass; 39 are commented out with `;; FAIL:` markers — 7 for\nthe known #1891 and 32 for six findings this pass reproduced. Every\ndisabled group keeps an enabled discriminating control beside it, so the\nfile still proves the neighbouring path works.\n\nThe findings share one cause: `applyExactness` exists twice, in\n`reader_tokens.zig` and `primitives_numeric.zig`, with different\nstrategies. `string->number` rebuilds the value exactly from the decimal\ndigits; the reader parses to f64 first and then tries to un-round it with\na tolerance-based continued fraction, so it loses at both ends of the\nrange. Past fixes (#79, #419, #604, #751) each landed in one copy only.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Point Phase 1A FAIL markers at the filed issues\n\nThe disabled assertions were committed with placeholder markers before the\nissues existed. Each now names the issue whose fix re-enables it.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Address review: declare (scheme inexact), unpin a non-conforming control\n\nTwo review findings on #1917, both valid, though the first for a different\nreason than stated.\n\nfinite?/infinite?/nan? are registered to (scheme inexact), so the import\nbelongs there. The claim that omitting it made the file fail was wrong --\nit ran 128 assertions green, because a top-level script reaches vm.globals\ndirectly whether or not the import is declared. That ambient reachability\nis exactly what kaappi#1831 documents, and relying on it in a test would\nhave made the file pass here while the same code failed inside a library\nbody. Declared explicitly.\n\nThe second finding was right outright, and investigating it found a bug the\ncontrol was hiding. Asserting (not (string->number ...)) pinned #f as the\ncorrect answer for a valid R7RS numeric string, so fixing string->number\nwould have looked like a regression. Rewritten to assert only the non-crash\nproperty. Probing why it returned #f showed the UNPREFIXED spelling of 2^63\nfails too, with the reader parsing it correctly -- the opposite parity from\nevery other divergence in this file. Filed as #1921 with four enabled\ncontrols and one disabled assertion.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-31T18:38:54+05:30",
          "tree_id": "86756ff19d7512557562d4326426a804332b910b",
          "url": "https://github.com/kaappi/kaappi/commit/2903f3532d14576629b5dcd949643a81aea2371d"
        },
        "date": 1785506432457,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.352054,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.889947,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.582048,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.028709,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004766,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.047001,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.31841,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057403,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.647567,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.23114,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.614311,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.281133,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.812327,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.63892,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044207,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "3dbd0b5bcdcca2f412e0a75e7d67556e74f082b3",
          "message": "Make (srfi 14) a character set, not a multiset that stops at z (#1895) (#1928)\n\nThe library was three defects at once, and the third made the first two\nworse: `(char-set #\\a #\\a #\\b)` kept the duplicate, `char-set:full` was\ncode points 0-127 so `#\\λ` was not in it, and 23 of the SRFI's 64 names\nwere exported -- while `(cond-expand (srfi-14 ...))` answered yes, so\nportable code was told the library was there and then handed a multiset.\n\nA char set is now an inversion list: a sorted, disjoint, non-adjacent list\nof `(lo . hi)` code-point pairs. That is what makes it a set structurally\nrather than by filtering -- duplicates cannot be represented -- and what\nmakes `char-set:full` and `char-set-complement` two pairs instead of 1.1\nmillion list cells. `equal?` on two canonical range lists decides\n`char-set=` outright, which `char-set-hash` then rides on. All 64 spec\nnames are implemented; none is omitted.\n\nThe standard `char-set:*` constants come from generated Unicode general-\ncategory tables rather than from a scan over `(scheme char)`'s predicates.\nScanning was the obvious approach and two things ruled it out. It costs\n~0.14s per predicate, which is too much at every import; and making it\nlazy and memoised is unsafe in this engine, not merely inelegant. Globals\nare shared between SRFI-18 threads by pointer while heaps are per-thread,\nso a child thread forcing a memo writes a child-heap value into a\nparent-heap record, and the parent reads freed memory after the join.\nThat reproduces with no char sets involved -- a record box, `set!` from a\nchild, read from the main thread -- and a field holding a fixnum survives\nwhere one holding a fresh pair does not. So nothing here is ever mutated\nafter construction, and the tests pin that a constant read first from a\nchild thread is still sound in the parent.\n\nDeriving from categories is also what the SRFI asks for, but it means two\nvisible disagreements with `(scheme char)`, both intentional and both\ntested: `char-set:letter` is L* while `char-alphabetic?` answers for the\nbroader Alphabetic property, and `char-set:digit` is all 680 of Nd while\n`char-numeric?`'s hand-written 36-entry table covers only the 370 in the\nBMP. Each predicate is right for its own spec except the last, which is a\nseparate bug in `isUnicodeNumeric`.\n\nThe suite is written against the spec rather than the implementation: on\nthe pre-#1895 library it reports 17 passes and 144 failures. Beyond the\nspec's own worked examples it property-checks every range operation\nagainst a brute-force list-of-code-points model over a 121-character\nalphabet, which is what catches the overlap and adjacency cases hand-\nwritten tests reach only by luck -- four of five seeded mutations in the\nrange algebra are caught, the fifth being an equivalent mutant.\n\n`tools/gen_srfi115_charsets.py` becomes `tools/gen_srfi_charsets.py` with\na `--target {115,14}` selector, since it now feeds both libraries.\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-31T18:38:58+05:30",
          "tree_id": "c194d0a1470722fc624ecafce71616e0468a0922",
          "url": "https://github.com/kaappi/kaappi/commit/3dbd0b5bcdcca2f412e0a75e7d67556e74f082b3"
        },
        "date": 1785507139505,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.962166,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.328717,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.559231,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.835603,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00494,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.044587,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.29722,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.055244,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.298687,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.158115,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.510861,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.298699,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.690756,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.763706,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044462,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "8cb776be89da98a9c82728d0f93c01d5e8eeffe5",
          "message": "Phase 1C: port refill sweep — 1714 configurations, a silent-split class, and a correction to #1893 (#1946)\n\n* Pin the reader's port-refill boundary with a token x offset sweep\n\n`(read port)` on an fd-backed port reads 4096-byte chunks and re-parses\nthe accumulated buffer after each one, treating only\n`ReadError.UnexpectedEof` as \"incomplete, read more\". A token straddling\na chunk boundary therefore survives only if its scanner happens to\nreport truncation with that exact error.\n\nSweeping 26 token kinds against every interior split point at both the\n4096 and 8192 boundaries -- against a string-port oracle over the same\nbytes, which cannot refill -- shows 12 kinds that do not, in two modes:\na hard `KP3000: read error` (strings, raw strings, `#u8\"...\"`, `#u8(`,\n`|sym\\x41;|`, and a multi-byte UTF-8 codepoint split anywhere, even\ninside a list) and a silent truncation with no error at all (bare\nsymbols, numbers, `#\\space`, `#\\x41`, `#true`, and line comments, whose\nremaining body is then read as program data).\n\nThe passing kinds are enabled and swept; the failing ones are commented\nout with a `;; FAIL:` marker. Fixtures are generated at run time and\ndeleted, so no 4 KB blobs are committed.\n\nWorth recording: #1893's own stated discriminating control -- \"the same\nfile with a bare symbol payload reads all 1024 datums\" -- does not hold.\nThe symbol only survived because it was wrapped in a list, which does\nrefill, and because the check counted datums instead of comparing them.\nAt top level the same symbol splits in two, silently.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Point port-refill FAIL markers at the filed issues\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-31T18:42:38+05:30",
          "tree_id": "14d1054f4c209b7d0452ed420c561133b5d348ef",
          "url": "https://github.com/kaappi/kaappi/commit/8cb776be89da98a9c82728d0f93c01d5e8eeffe5"
        },
        "date": 1785508159081,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.354779,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.93978,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.583787,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.979059,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004746,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.047034,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.318927,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057266,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.62904,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.234423,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.605772,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.28174,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.803356,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.649718,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043638,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "5dcf4e3776e00eae9b64a70f3cc550d528aa5646",
          "message": "Phase 4B: differential harness for the opt-off and cache tiers — 557 files, one real divergence (#1923)\n\n* Turn the execution-tier differential into a repeatable gate\n\nThe reconnaissance pass ran tiers (b) `--no-ir-opt` and (d) cold-vs-warm\n`.sbc` cache once, across 333 files, and found nothing. A one-off green\nrun is not a gate, and — for tier (b) — it was not even much of a\nnegative: only 3 of the 550 pre-existing corpus files make the IR\noptimiser do anything at all, because every `define`/`lambda` body lowers\nto an opaque `passthrough` node and the five passes only ever reach\ntop-level expression position. The other 547 compile identically with the\noptimiser off, so the comparison was vacuous for 99.5% of the corpus.\n\nSo the harness does three things the one-off sweep did not.\n\nIt measures its own vacuity. The summary reports how many files change IR\nunder `--no-ir-opt` and how many populated the bytecode cache (40 of 330\nby default; a program that imports is never cached), so a regression that\nsilently disables either shows up as a count collapsing rather than as a\nstill-green run.\n\nIt ships probes that the passes actually reach. `probes/` puts foldable,\ndead-branch, `not`-rewrite, identity and nested-`begin` shapes at top\nlevel, where the passes live, and leans on the cases where the rewrite is\nonly conditionally sound: `(if 0 ...)` is true in Scheme, `(* 1.5 0)` is\nnot `1.5`, and a shadowed `+`/`*`/`not` must suppress the rewrite\nentirely. Six of the seven are verified non-vacuous, tripling the number\nof corpus files that exercise the optimiser.\n\nIt decides nondeterminism by measurement instead of by a guessed skip\nlist. A tier mismatch has to survive three controls before it is\nreported: the file must actually be cached (otherwise cold and warm are\nthe same configuration, so a tier-(d) mismatch cannot be a cache effect),\ntwo cold baselines must agree, and the divergence must reproduce. The\nfirst control is what distinguishes a real finding from\n`nested-wait-under-sleep-dirty-snapshot-1490.scm`, which hung once under\nload and read as a cache divergence until the check was added. The static\nskip list is consequently empty.\n\nOne real divergence, found by the probes and suppressed via KNOWN_DIFFS\nso the suite stays green: on a cache HIT a runtime error loses its source\nline and snippet whenever the location comes from `Function.source_line`\nrather than the line table, because `vmErrorLocation`'s `fallback_line`\nis a hardcoded 0 on the cache-HIT path where the fresh-compile path\npasses the top-level datum's line. Exit code and stdout agree; only the\ndiagnostic degrades. `probes/cache-error-location.scm` carries the repro\nand its control side by side — `vector-ref` out of range, located by the\nline table, prints identically in both runs.\n\nUnlike the `;; FAIL: #1234` convention, that suppression cannot rot\nquietly: when a listed entry stops diverging the summary says so and asks\nfor it to be deleted. It is a note rather than a failure, because a gate\nthat goes red the moment someone fixes a bug teaches people to distrust\nit.\n\nWired into run-all.sh over the smoke+compliance+audit corpus plus the\nprobes: 330 files, 116s, inside the 300s shell-suite budget.\n`KAAPPI_DIFF_FULL=1` adds continuations/, hygiene/ and srfi/ — 557 files,\n210s — and is opt-in rather than the default because the extra 227 files\nbuy no additional tier coverage: zero of them change the IR, and they add\nseven cached files.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Point the known cache divergence at kaappi#1922\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Reduce the differential corpus to probes/ on a Debug build\n\nCI's Debug leg killed the suite at run-all.sh's 300s SHELL_TIMEOUT. Debug\nruns the whole pipeline unoptimised and is ~500x slower on allocation-heavy\nwork, and the harness is ~1000 interpreter invocations, so the same sweep\nthat takes 110s on ReleaseSafe does not finish.\n\nReducing to probes/ rather than skipping the suite or raising the budget,\nbecause the census the harness itself reports says probes/ is where the\nsignal is: 9 of 331 corpus files make the optimiser do anything and 6 of\nthose 9 are the probes. Debug now runs 7 files in 15s and still covers 6 of\nthe 9 discriminating ones, so what it drops is the part that was vacuous by\nconstruction.\n\nDetected from {\"version\":\"0.22.0\",\"build_id\":\"ca18ae6\",\"target\":\"aarch64-macos-none\",\"build_mode\":\"ReleaseSafe\",\"gc_stress\":false,\"sandbox_available\":true,\"features\":[\"r7rs\",\"kaappi\",\"ieee-float\",\"exact-closed\",\"exact-complex\",\"kaappi-fibers\",\"kaappi-reactor\",\"kaappi-diagnostics\",\"posix\",\"kaappi-threads\"],\"srfis\":{\"builtin\":[1,9,13,18,39,69,133,170,192,254,258,260],\"portable\":[0,2,4,5,6,7,8,11,14,16,17,19,23,25,26,27,28,29,30,31,34,35,36,37,38,41,42,43,44,45,46,48,51,54,57,59,60,61,62,63,64,66,67,70,71,74,78,86,87,90,94,95,98,101,111,112,113,115,116,117,118,120,123,125,126,127,128,129,130,131,132,134,135,136,137,139,140,141,143,144,145,146,147,148,149,150,151,152,153,156,158,161,162,164,165,166,167,168,169,171,173,174,175,178,180,181,185,188,189,190,193,194,195,196,197,201,202,203,207,209,210,213,214,215,216,217,219,221,222,223,224,225,227,228,229,231,232,233,234,235,236,237,238,239,240,241,242,244,247,248,250,251,252,253,255,257,259,263,264,267,270,271]},\"limits\":{\"initial_frame_capacity\":480,\"initial_register_capacity\":2048,\"gc_initial_threshold\":8192}} rather than an env var, so it is\nright whether the build came from CI, a local -Doptimize=Debug, or a stale\nzig-out. KAAPPI_DIFF_FULL=1 still forces the whole corpus.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-31T19:39:36+05:30",
          "tree_id": "8976b3f277bc70b7a9d4ba341d32f72610c96978",
          "url": "https://github.com/kaappi/kaappi/commit/5dcf4e3776e00eae9b64a70f3cc550d528aa5646"
        },
        "date": 1785509657923,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.973515,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.444874,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.566195,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.842375,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004866,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.044536,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.297518,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.055164,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.305599,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.158962,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.507275,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.302923,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.833881,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.777322,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044957,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "cbbf0f94087cbaa7a6d1055f2cbb12fec58bff12",
          "message": "Phase 1B: delimiter sweep — 494 cells, 382 splits, and a guard that has never executed (#1931)\n\n* Sweep trailing-delimiter checking across every numeric prefix\n\nR7RS 7.1.1 requires a number to end at a <delimiter> or end of input.\n`Reader.readNumber` (src/reader.zig:366) enforces that, but only for\nun-prefixed decimals: `readNumberPrefixed` (src/reader_tokens.zig:481)\ncalls the unguarded `reader_tokens.*` functions directly, so any `#`\nprefix at all disables the check and one token silently reads as two\ndatums.\n\nThe systematic 19x26 sweep (19 prefix spellings x 26 trailing characters)\nsplits 382 of 494 cells; all 26 un-prefixed cells are correct, which is\nthe control axis. `string->number` rejects every failing cell, so each\ndisabled assertion is paired with an enabled oracle assertion. Chibi 0.12\nand Guile 3 raise on all of them too.\n\n148 assertions pass; 58 are disabled (55 under #1892, 3 under TBD for two\nnon-delimiter reader/string->number divergences the same sweep surfaced).\nThe enabled groups also pin the syntax a fix must not regress: SRFI 270\nhex floats, SRFI 169 digit separators, rationals, complex tails, and hex\n`e`/`d` as digits rather than exponent markers.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Point delimiter FAIL markers at #1929\n\n#1892 reported the radix-prefix case; the sweep showed one bypassed call\nsite produces all 382 failing cells across every prefix spelling, so the\nmarkers name the wider issue that a fix will actually close.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-31T19:40:15+05:30",
          "tree_id": "f355651720339ada74bc4939f6ba72a5663ff21d",
          "url": "https://github.com/kaappi/kaappi/commit/cbbf0f94087cbaa7a6d1055f2cbb12fec58bff12"
        },
        "date": 1785509664474,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.358727,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.57382,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.5796,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.009405,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004694,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.047051,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.319169,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057043,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.636414,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.230923,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.61636,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.276379,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.804693,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.58907,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042981,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "c5ddfe48acfbf8af321b798530fc53b24821b4bb",
          "message": "Phase 5C: cross-thread boundary audit — 49 assertions, six new findings including a read-direction UAF (#1938)\n\n* Map the cross-thread heap boundary, and pin the half of it that works\n\nPhase 5C of the v2 audit campaign. #1924 established that a child thread\nmutating a heap object reachable from a top-level binding leaves the parent\nreading freed memory. This maps how far that reaches, and — as importantly —\nwhere the boundary is actually sound, so those parts need not be re-audited.\n\n49 enabled assertions pin the working boundary: immediates (fixnum, char,\nboolean, flonum) survive every container; raw-byte content does too\n(string-set! including the widening rebuild, string-copy!, bytevector and\nf64vector elements); interned symbols survive because a child stamps them\nwith the parent's GC id; a child may store a parent-heap value into a\nparent-heap object and keep eq?; a child may grow a parent hash table across\na rehash; parameters are per-thread; a mutex left locked by a dead child\nreads as abandoned; join deep-copies results, nested objects included; and\nall seven reachable uncopyable tags are refused in both directions.\n\n24 assertions are commented out behind `;; FAIL:` markers rather than\ntest-expect-fail, because reading freed memory can take down the runner.\nSeventeen are #1924's shape across every mutable heap type — including the\nshared globals map itself and promise memoisation, which its own matrix\ndoes not cover. Seven are new and are marked TBD:\n\n  * the read direction, which #1924 does not cover: the parent's collector\n    reclaims an object a LIVE child still references, since markVMRoots\n    returns early unless vm.gc == gc. Under -Dgc-stress=true this escalates\n    to the engine's own UAF panic, 3/3, with the no-drop control clean 3/3.\n  * a plain R7RS record returned through thread-join! arrives as a\n    DIFFERENT record type: pt? answers #f and every accessor raises. The\n    supported worker-thread path, no globals and no mutation involved. A\n    SRFI 237 nongenerative type is the control and is enabled — its uid\n    registry is the one identity-preserving path in gc_deep_copy.\n  * gc_deep_copy's .channel arm skips the ownership check for an\n    already-promoted channel, so a grandchild that only ever reached a\n    channel through a shared global gets a working stub. The unpromoted\n    control is enabled and refuses.\n  * symbol interning is one level deep: at thread depth >= 2 a grandchild's\n    string->symbol no longer dedupes against the process table.\n  * a continuation invoked cross-thread returns a value satisfying no type\n    predicate at all.\n\nCLAUDE.md's claim that top-level bindings are shared by pointer while\nlexical captures are deep-copied-and-re-owned is confirmed, and both halves\nare now asserted directly.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Point cross-thread FAIL markers at the filed issues\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-31T19:40:55+05:30",
          "tree_id": "4aa2be03e1a6302c71fd7fd1dfa0dfcaea17a740",
          "url": "https://github.com/kaappi/kaappi/commit/c5ddfe48acfbf8af321b798530fc53b24821b4bb"
        },
        "date": 1785510205407,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.335597,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.604451,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.450512,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.416965,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004082,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.034737,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.230712,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.042794,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 1.831192,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.896954,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.172455,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.237944,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.305979,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.440092,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.035719,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "912b1e6246e05b822fe3968f982e614c1b8fe19a",
          "message": "Phase 2.2: primitives_io audit — 49 → 197 assertions, all 45 specs covered, one process-abort panic (#1947)\n\n* Phase 2.2: cover the 1100 lines primitives_io.zig grew after its audit\n\nThe audit test for src/primitives_io.zig was written against a version of\nthat file that predates custom ports, transcoded ports, the write-buffering\nlayer, and SRFI 192 — 112 lines of assertions against 1941 lines of code.\nThis takes it to 197 passing assertions covering all 45 spec entries, and\nleaves 8 disabled assertions marking defects the coverage found.\n\nFour defects, each paired with an enabled discriminating control so the\nmarker says *because of what*, not just *that it fails*:\n\n- A custom-port read! that re-enters a read on its own port trips\n  std.debug.assert(port.read_buf == null) and ABORTS the process — the\n  single-slot read buffer assumes no re-entrancy. Reachable at two sites\n  (readOneByteFromCustomPort, readOneByteFromTranscodedPort). Control: the\n  same shape returning one byte per call never populates read_buf and\n  completes cleanly. Its non-aborting sibling silently reorders the byte\n  stream.\n- SRFI 192's string-port branch ignores the port's own peek-byte read-ahead,\n  which the fd branch corrects for: port-position over-reports by one after\n  a pushed-back byte, and set-port-position! does not discard the stale byte,\n  so a seek is followed by a read of data from the old position. Controls:\n  the identical cases on a file port are both right.\n- port-has-set-port-position!? is registered to the same function as\n  port-has-port-position?, so it answers about get-position instead of\n  set-position! — wrong in both directions for a custom port with only one\n  of the two. Controls: ports with both, and with neither, answer correctly.\n- flush-output-port on a transcoded port is a silent no-op; it has custom-\n  backend and buffered-fd branches but no transcode branch, and a transcoded\n  port carries the fd -1 sentinel. Controls: flushing the wrapped port works,\n  and close-port does cascade.\n\nConfirmed correct along the way: the 8 KiB high-water drain and its\nflush/close/read triggers, fd-port positions corrected for read-ahead and\nwrite-behind, the freshly-re-read UTF-8 byte-offset conversion after a\nwidth-changing string-set! inside read!, CRLF decode and encode, both\ndecoding error modes, close-port's flush-and-cascade discipline, the\nblocking-callback rejection, and gc_deep_copy's refusal to carry a port\nacross a thread boundary.\n\nFound by: systematic audit v2, Phase 2.2 (docs/audit-strategy.md).\nDiscovery only — no source changes.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Point primitives_io FAIL markers at the filed issues\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-31T19:41:33+05:30",
          "tree_id": "dcf0c4b87487858c011e4a12cc7ad5a6041cbef6",
          "url": "https://github.com/kaappi/kaappi/commit/912b1e6246e05b822fe3968f982e614c1b8fe19a"
        },
        "date": 1785511043172,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.945213,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.399424,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.56213,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.853622,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.005031,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.044442,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.297564,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.055146,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.299306,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.157885,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.510634,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.305477,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.695136,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.760242,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044976,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "6114398ba48db971cd17792170b82d92e3f439fd",
          "message": "Tick the eight units landed in the first two batches (#1948)\n\nThe tracker read 2 of 53 while eight units were merged, because each\nunit's PR added its test file without touching the tracker. The document\ncalls that tracker the single source of truth, so a stale one is the same\nfailure Phase 0B existed to fix: the next session to open it would have\nre-run work already done and re-filed issues already filed.\n\nEach entry records its PR and the issues it produced, so the tracker\nanswers what a unit found without needing eight PRs opened alongside it.\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-31T20:49:37+05:30",
          "tree_id": "3994183ec5106eb2bdac9eda445056deddab5073",
          "url": "https://github.com/kaappi/kaappi/commit/6114398ba48db971cd17792170b82d92e3f439fd"
        },
        "date": 1785512696769,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.352258,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.083364,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.59766,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.981369,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004997,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.047616,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.319096,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057249,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.645299,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.231968,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.619376,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.284556,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.815246,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.648532,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043738,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "93fa575717d4339d84e008953104d530adc3b622",
          "message": "Stop a VM limit from arriving as a catchable condition (#1919)\n\nA recursive procedure that wraps its own recursive call in `guard` is\nordinary code, and past 64 levels it was silently incorrect: it returned\na plausible wrong value and exited 0.\n\nThe exception-handler and dynamic-wind stacks were fixed 64-entry inline\narrays. `with-exception-handler` relabelled the overflow as OutOfMemory\nand then converted it into an ordinary Scheme error object, so the\n*enclosing* guard caught it and its `(#t ...)` clause returned. A case\nthat must return 0 at every depth returned `(0 1 37)` for 63/64/100.\n`with-exception-handler` had it worse -- the overflow was invisible, the\nhandler simply receiving a bare `#<error \"error\">`.\n\nBoth stacks now grow on demand like the frame and register stacks\n(`-Dmax-handlers`/`-Dmax-winds`, hard cap 32768), and `errors.isUncatchable`\nkeeps VM limits and control-flow signals out of a user's `guard`: a limit\nof the implementation is not something the program raised, so it unwinds\nto the top level under its own code. `thread-terminate!` likewise no\nlonger runs the terminated thread's guard clauses on its way out.\n\nTwo error tags turned out to be overloaded, and only the suites said so.\n`OutOfMemory` is real exhaustion but equally the payload-size cap for\n`(make-vector 100000000000000)`, so it stays catchable. `StackOverflow`\ncovered `apply`'s 255-argument ceiling -- which is the bound that ends\nthe walk of a *circular* argument list, and has to stay recoverable --\nso those three sites become KP3007 with a message that names the real\nlimit, instead of sending readers to hunt for runaway recursion.\n\nFixes #1886\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-31T15:30:28Z",
          "tree_id": "6ad812fa1bd824b3379e7100f27d2705bd03360c",
          "url": "https://github.com/kaappi/kaappi/commit/93fa575717d4339d84e008953104d530adc3b622"
        },
        "date": 1785513593298,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.423656,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.619933,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.462667,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.548192,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.005039,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.04156,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.254491,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.048371,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.472071,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.039077,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.365679,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.271626,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.499003,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.83458,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.038942,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "3de5281fede1fbbdb530005faa9bcc902479cc30",
          "message": "Phase 1D: printer audit — 79 assertions, five hangs, and a legal-but-wrong datum at depth 1023 (#1956)\n\n* Audit v2 Phase 1D: sweep the printer's structural round-trip\n\n`src/printer.zig` had no Scheme-level test of its own beyond a handful of\nZig unit tests.  Sweep it against the round-trip oracle -- (equal? x (read\n(open-input-string <written x>))) -- across every printable type and every\nstructural shape, with the four `write`-family contracts checked against\ntheir own R7RS 6.13.3 text rather than against each other.\n\n79 enabled assertions, 16 disabled.  Each disabled assertion is paired with\nan enabled control -- a near-identical input that behaves differently -- so\nthe file keeps proving the neighbouring path still works.\n\nBeyond the three symptoms already filed as #1902, the sweep separates that\nissue's single \"1024\" into three independent mechanisms with three distinct\ncliffs (markShared's cdr-spine depth; the seen[] cap, which makes detection\ndepend on an object's *position*; and the shared[] cap), and turns up five\nfindings it does not cover:\n\n- `write-simple` is registered as `.func = &write`, so it emits datum labels\n  on circular structure, which R7RS says it never may.\n- All four output procedures loop forever on a cycle reachable only through\n  a container the cycle pre-pass does not walk (error objects, mutex and\n  condition-variable names).  #1713 fixed this shape for record instances\n  and left the other arms behind.\n- An exact rational at nesting depth 1023 prints as \".../...\" and reads back\n  as a *symbol*: the printer's depth counter outruns the reader's nesting\n  count for that one arm, and the plain printer's truncation sentinel \"...\"\n  is itself a legal identifier.\n- `write-shared` becomes exponential once seen[] is full, so the same two\n  objects in a two-element vector print instantly one way round and never\n  terminate the other.\n- Closed issue #859 (REPL prettyPrint hang) still reproduces; the fix that\n  closed it removed the unbounded memory growth but not the hang, which now\n  lives in `exactFlatLen`.\n\nFindings only -- no printer changes.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Point printer FAIL markers at the filed issues\n\nAlso drops the claim that #859 still reproduces. A properly constructed\npty test -- one that checks whether the REPL still services later input,\nrather than whether the process is merely alive -- shows it responding at\nboth COLUMNS=200 and COLUMNS=12, so that closed issue stays closed.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-31T22:46:53+05:30",
          "tree_id": "1ec2247abc3ba02ae0a922b3488a7df7d6aea9c4",
          "url": "https://github.com/kaappi/kaappi/commit/3de5281fede1fbbdb530005faa9bcc902479cc30"
        },
        "date": 1785519951230,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.302085,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.678265,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.57334,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.981789,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004664,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046303,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.310848,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.055927,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.61012,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.230189,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.55831,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.280802,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.772434,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.5987,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045189,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "1c6b02f3115b2b4f910a0bcdf8ee1a59142b5fb3",
          "message": "Stop three diagnostics from misdescribing what they are about (#1958)\n\nEach of these sent a reader looking at the wrong thing.\n\nAn integral flonum rendered without its `.0`, so a type error on 1.0 read\n\"expected exact integer, got 1\" -- and 1 is an exact integer, so the message\nargued against itself. `safeValueDescription` formatted flonums with a bare\n`{d}` instead of the printer, so this affected every type error in the\ncodebase, not just the numeric-vector ones it was found in. It now goes\nthrough `printer.formatFlonum`, which is safe in this deliberately-defensive\nhelper: a flonum is inline under NaN-boxing, so nothing heap-shaped is read.\n\nA multi-limb bignum handed to a (srfi 160) constructor was reported as\n\"expected exact integer, got #<bignum>\". It is an exact integer; its only\nfault is not fitting s8..u64. `magnitudeAndSign` returned a plain `?MagSign`,\nwhich gave \"too wide\" and \"not an integer at all\" the same answer. Splitting\nthem into `ExactMag.too_wide` / `.not_exact` lets an out-of-range bignum say\n\"in-range\", matching what an out-of-range fixnum has always said -- and say\n\"non-negative\" instead when it is negative, since then the sign is the real\ncomplaint.\n\n`%record?` and `%transcoded-port` reported their errors as `record?` and\n`transcoded-port`. Those are not cosmetic truncations: both are real,\ndifferent procedures, exported by (srfi 237) and (srfi 181), with different\nargument lists -- `(record? 5 5)` is an arity error, not a type error. Both\nnow use the shared-constant convention primitives_srfi237.zig's MAKE_RTD\nalready documented for exactly this reason, so the name cannot drift again.\n\nThe audit that found these (#1890, Phase 2.1) had already written the\nassertions and commented them out as known failures; they are enabled here,\nalongside their original controls and three cases the audit did not cover\n(a negative multi-limb bignum, a signed-kind overflow, and a genuine\nnon-integer, which is what keeps \"in-range everywhere\" from passing). One\nof the four could not be enabled as written: `(not (has-substring? msg\n\"got 1\"))` cannot pass whatever the code does, since \"got 1\" is a prefix of\nthe correct \"got 1.0\" -- it is stated positively instead, which is fully\ndiscriminating because the buggy message was exactly \"got 1\".\n\nMutation-tested: reverting each of the three fixes in turn fails exactly the\nassertions belonging to it and no others.\n\nFixes #1916\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-31T22:47:11+05:30",
          "tree_id": "4e4667e4a449d0e129efd701cdcc4272bc647d0f",
          "url": "https://github.com/kaappi/kaappi/commit/1c6b02f3115b2b4f910a0bcdf8ee1a59142b5fb3"
        },
        "date": 1785520126466,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.115725,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.261311,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.443981,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.183069,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004164,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.035738,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.225216,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.041166,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.147257,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.96069,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.211298,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.23357,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.281543,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.81746,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.04029,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "589aba141046e3b8544cf84787b4cb1b8a1579ad",
          "message": "Phase 2.4: SRFI 160 audit — 1066 assertions across 12 element kinds, one hang (#1952)\n\n* Phase 2.4: audit primitives_srfi160 across all 12 element kinds\n\nsrc/primitives_srfi160.zig is 280 lines and six %-prefixed generic\nprimitives, but those six are the entire native surface under 12 element\nkinds and ~732 exported names across 13 .sld files. It had no audit test,\nand the existing tests/scheme/srfi/srfi160.scm is 75% s8.\n\nAdds tests/scheme/audit/primitives_srfi160-audit.scm: 1066 assertions,\nevery 12-kind sweep generated from one kind table rather than written out\nper kind.\n\nConfirmed correct, systematically rather than by spot check: the 8\ninteger kinds at min/min+1/min-1/max/max-1/max+1 and against nine\ntype/exactness rejection classes; the two independent range checks\n(%uvec-elt-valid? in Scheme, expectSignedInRange/expectReal in Zig) agree\non a 12x23 corpus; f32 really truncates to single precision; -0.0, +-inf.0\nand NaN survive; c64/c128 pack two components independently and at the\nright width; a rejected set! never leaves a half-written element; the\nu8-as-bytevector seam holds in both directions; every per-type wrapper\nfixes its own kind symbol (12x12 predicate matrix plus every\nkind-constructing entry point); and callback errors propagate out of all\n18 higher-order generics, with an out-of-range callback result rejected\nrather than truncated.\n\nThree findings, disabled with a marker and an enabled control each:\n\n- Uvector-segment with n = 0 never terminates. %uvec-segment advances by\n  (min len (+ start n)), so start never moves while a fresh zero-length\n  copy is consed each iteration. All 12 kinds, both dispatch branches.\n  SRFI 160 makes n = 0 \"an error\", so a raise would conform; a hang does\n  not. Controls: n = -1 raises, n = 1 and n = 3 work, empty vector with\n  n = 0 returns ().\n\n- c64/c128 comparator hash raises on every value. %uvec-hash folds with\n  number-hash, which is (abs x)-based and rejects a complex. c64/c128\n  elements always decode to a Complex, so this fires even when every\n  imaginary part is zero. SRFI 160 requires the comparator to provide\n  hashing. Controls: the s8, f64 and u8 comparator hashes all work.\n\n- A zero-imaginary c64/c128 element writes as a form that reads back as a\n  different type: real? is #f, yet write emits \"1.5\", which reads as a\n  flonum. Affects the default fill, so every fresh c64/c128 vector has\n  such elements. Only decodeElement can produce them -- make-rectangular\n  normalises a zero imaginary part away. The vector printer prints\n  \"1.5+0.0i\" for the same bytes, so the two printer paths disagree.\n\nByte order is host-native by design and, on this evidence, not observable\nfrom Scheme: there is no NumericVector-to-bytes view, and NumericVector\nis not .sbc-serialisable. The printer and the primitives are two separate\nhand-written native-endian decoders, so the section 8 assertions use\nvalues whose byte-reverse is a different in-range number -- they assert\nencoder/decoder agreement rather than a little-endian layout, so they\npass on any host and would fail on s390x only if the two drifted apart.\n\nFound by: systematic audit v2, Phase 2.4\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Point SRFI 160 FAIL markers at the filed issues\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-31T23:11:25+05:30",
          "tree_id": "c2c96809d17d13065b03b09200c18c067ea72f26",
          "url": "https://github.com/kaappi/kaappi/commit/589aba141046e3b8544cf84787b4cb1b8a1579ad"
        },
        "date": 1785521556195,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.140581,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.408456,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.447896,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.214184,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004263,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.036742,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.228824,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.041613,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.243518,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.981944,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.252776,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.241359,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.35194,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.763942,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.034544,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "e24e594ed8a650edb6b09d9216b16594a78610ad",
          "message": "Parallelise run-all.sh's shell suites, and stop rebuilding twice (#1957)\n\nThe shell suites were the larger half of run-all.sh's wall time and ran\nstrictly sequentially, because several scripts build into the one shared\nzig-out/ and would race each other's install. Two separate things had to\nchange: the race (which blocked concurrency) and the cost (which was\nsomewhere else entirely).\n\nThe cost was two full interpreter rebuilds. `zig build -Dbundle=…`\nrecompiles everything, since the embedded bytecode is part of the compiled\nmodule graph, and the two scripts that need a standalone binary each paid\nfor one — 85% of the shell suites' entire wall time for two tests. They\nneeded different embedded bytecode only because each carried its own\nfixture, so they now share one, in\ntests/scheme/compile/fixtures/bundle-replay/. Identical bytes make the\nsecond build a ~0.2s hit in Zig's own content-addressed cache. The .sbc is\nregenerated on every call rather than cached: unchanged sources give\nidentical bytes and the hit, while an edit under src/ changes them and\nforces exactly the rebuild it must — a cached .sbc of our own would go\nstale against the new binary's build id instead.\n\nThe race is closed at both ends. run-all.sh builds the runtime archive once\nup front and exports KAAPPI_RT_LIB_READY, which ensure_runtime_lib treats as\n\"already fresh\"; the marker is advisory, so a script run standalone (the\nWindows CI legs invoke each one directly) still builds its own. What builds\nremain take a mkdir-based lock — atomic on POSIX and Git Bash alike, where\nflock is Linux-only and macOS has none — and a lock whose holder was killed\nis stolen by the next waiter via the recorded pid. Six scripts had their own\ninline copy of the archive build, checking only for the file's existence;\nthey go through ensure_runtime_lib now, so one guard covers all 18.\n\nDispatch inside a suite is longest-first, found by grep rather than a list\nof names. Reporting still walks glob order, so a transcript diff between two\nruns stays meaningful at any job count.\n\nFull suite on a 12-core box: 475s -> 245s, same 2026 pass / 0 fail. The\nparallel and KAAPPI_TEST_JOBS=1 transcripts differ only in the line that\nreports the job count.\n\nCloses #1926",
          "timestamp": "2026-07-31T23:27:09+05:30",
          "tree_id": "a44f3a0ad9e71998d6a8746749f3433472bc0dba",
          "url": "https://github.com/kaappi/kaappi/commit/e24e594ed8a650edb6b09d9216b16594a78610ad"
        },
        "date": 1785523328128,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.327595,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.23971,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.603549,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.968196,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004676,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.047056,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.314084,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057826,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.69526,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.222003,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.648019,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.28591,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.802526,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.679759,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043003,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "db8e3d074fe64ead9d14b6b389d913e1a9dff132",
          "message": "Test what is inside each per-tag GC arm, not just that one exists (#1963)\n\nZig's exhaustiveness check guarantees markObjectContents, markValueInner,\nreferencesYoung, objectSize and freeObject each have an arm for all 41\nObjectTag members. Nothing guarantees the arm traces the tag's Value\nfields: one that forgets a field compiles cleanly and silently frees a\nlive object. Port's satellites are hand-written at five sites, and\nmarkValueInner deliberately duplicates markPortValues rather than calling\nit, so a third Value-bearing Port field would be invisible in up to five\nplaces at once.\n\nTwo runtime shapes, because the three mark-graph switches are reached by\ntwo different paths. Rooting a container makes markValueInner the only\nthing that can keep a referent alive. Promoting a container to the old\ngeneration, repointing a field through writeBarrier, then dropping the\nroot before a minor collection makes the remembered-set walk\n(markObjectContents, its only caller) the only route, and exposes\npruneRememberedSet's referencesYoung decision directly. Every rooted case\nends by dropping the root and asserting the referents die: an assertion\nthat cannot fail is not a test.\n\nLiveness is decided by walking the GC's own object lists for the\nreferent's address, never by dereferencing it -- reading back a swept\nreferent would be the use-after-free this file exists to detect.\n\nThe comptime inventory pins the exact field list of every heap struct\nthese switches dispatch on, plus the satellites they reach through\n(CustomBacking, TranscodeState, HashEntry, GuardEntry, WindRecord,\nExceptionHandler, SavedFrame, CallFrame). Value is u64, so no comptime\ntype test can tell a real Value from profile_calls -- pinning the whole\nlist is what makes the guard sound. Adding a field is now a build error\nnaming all five switches until someone has looked at them.\n\nMutation-tested: eight deliberate single-field deletions across\nmarkValueInner, markPortValues, referencesYoung and markFiberState each\nfailed exactly the intended case and nothing else, and a seventh Value\nfield on CustomBacking fails the build with the inventory error.\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-01T00:04:40+05:30",
          "tree_id": "0b6e9a3003744e22473bbbb692aae9841479b758",
          "url": "https://github.com/kaappi/kaappi/commit/db8e3d074fe64ead9d14b6b389d913e1a9dff132"
        },
        "date": 1785526087883,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.058264,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.199712,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.432448,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.27726,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.003749,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.03479,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.229581,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.042564,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 1.803694,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.898721,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.181508,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.239669,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.307003,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.380815,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.037203,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "e58801829acda296b6fcddb1f86d945d9af05ff1",
          "message": "Stop piping into grep -q under pipefail (#1966)\n\n`grep -q` exits the moment it matches. When the match is on an early line\nof the output, the writer on the left of the pipe can still be mid-write\nand dies of SIGPIPE — and `set -o pipefail`, which every one of these\nscripts sets, then reports the whole pipeline as failed even though the\nmatch succeeded. The assertion fails while printing the very text it was\nlooking for.\n\nIt is a race, so it passes locally and on 16 of 17 CI legs, then fails on\nthe slowest one. #1957 made run-all.sh dispatch the shell suites\nconcurrently, which raised the load enough to fire it: three assertions in\ntests/scheme/errors/ failed on freebsd-test, each matching the first or\nsecond line of a multi-line output, each with the expected text visible in\nthe failure it printed. In every case the assertion beside it matching the\n*last* line passed, because grep then reads to EOF and the writer never\nsees a closed pipe.\n\nReproduced directly: with an early match and a large output, `echo \"$x\" |\ngrep -q PATTERN` under pipefail reports no-match 20 times out of 20, and\nthe here-string form 0 times out of 20. At the real ~3-line size it is\nabout 1 in 16,000 on an idle machine — rare enough to have gone unnoticed,\ncommon enough to bite three times in one run on an emulated 4-core VM.\n\nA here-string has no pipeline for pipefail to judge: same grep, same\npattern, same exit status, no second process whose death can be mistaken\nfor a failed match. Converted all 29 sites rather than the three that\nfailed, since they are one latent bug and the rest would surface next.\n\nTwo piped `grep -q` uses remain, in errors/reader-*-errors.sh: those have a\ncommand on the left rather than a variable, and neither script sets\npipefail, so neither can hit this.",
          "timestamp": "2026-08-01T01:18:44+05:30",
          "tree_id": "41a345cc698f8dd2d6924bd845d24699e9a8d1ad",
          "url": "https://github.com/kaappi/kaappi/commit/e58801829acda296b6fcddb1f86d945d9af05ff1"
        },
        "date": 1785529566020,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.959296,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.117832,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.595535,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.829967,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004863,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.044767,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.296501,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.05944,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.504309,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.16581,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.524644,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.308806,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.687212,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.817554,
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
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "db0533161a6b1294321bf611b13206ca6504472b",
          "message": "Tick the third batch, and mark 5B as landed-but-blocked (#1968)\n\n1D, 2.4 and 7B are merged. 5B is ticked as complete work with its PR\nstill open, because it is blocked by a CI regression on main (#1967)\nrather than by anything in the unit -- leaving it unticked would imply\nthe work is outstanding when what is outstanding is someone else's\nFreeBSD failure.\n\nEach entry records what the unit found AND what it confirmed correct.\nThe two units that found no bugs in their target are the ones most at\nrisk of being read as wasted, so their entries say what they closed:\nnine untested false rows in the unwind asymmetry, and a 41-tag mark\ngraph whose arm contents nothing could check.\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-01T02:00:15+05:30",
          "tree_id": "10d24394df48e68650b6ebf4b7772864a79c6d27",
          "url": "https://github.com/kaappi/kaappi/commit/db0533161a6b1294321bf611b13206ca6504472b"
        },
        "date": 1785533974500,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.961673,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.607652,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.557629,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.834074,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004867,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.044936,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.295251,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.059248,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.510185,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.15452,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.613622,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.302184,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.764885,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.783166,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045887,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "2b2027b1d8c95e9e7932da541ad37edc2af9da14",
          "message": "Phase 5B: waitForFd park-vs-drive — 26 tests for a protocol that had zero direct coverage (#1960)\n\n* Assert which branch waitForFd took, not just that the read worked\n\n`waitForFd`, `driving_waits` and `anyAncestorWaitResolved` had zero direct\nreferences in any src/tests_*.zig. The park-vs-drive branch was reached only\nincidentally, through Scheme programs that happened to block, and incidental\ncoverage cannot say which branch ran: a change that made every caller drive in\nplace — or every caller park — would have left the whole suite green.\n\nsrc/tests_waitforfd.zig (26 tests) asserts the branch. The selector,\n`my_idx != 0 and vm.dispatched_from_scheduler`, is plain VM state, so all four\ncells are set up directly rather than raced into; the two that must DRIVE are\ndiscriminating controls for the two terms of the conjunction. The park cells\nuse an fd that is already readable, which separates \"parks because it was told\nto\" from \"parks because the fd was not ready\".\n\nThree gaps this closes beyond the branch itself:\n\n- The #1625 unwind asymmetry. `IoWait` is the only wait kind setting\n  `unwind_on_resolved_ancestor`, and runSchedulerStep gates on `@hasDecl`, so\n  opting a join/channel/mutex/condvar wait in — or IoWait out — compiles\n  cleanly and silently changes blocking semantics. A comptime table over all\n  ten production Ctx types pins it; the nine `false` rows had no coverage at\n  all. `anyAncestorWaitResolved` gets direct tests for its identity filter,\n  its timed_out disjunct, and its whole-stack scan.\n\n- The yield-retry contract. A parked primitive re-executes from scratch, so\n  progress in a Zig local is lost. Five tests reach a *confirmed* park with the\n  stream torn mid-item (mid-UTF-8, mid-line, mid-CRLF, mid-datum) and assert\n  both that the prefix landed in port.read_buf and that the resumed primitive\n  produces the whole item, plus a control at an item boundary where nothing\n  may be stashed. The write side takes the other route — drain before append,\n  progress in write_buf_start — and is checked for loss and duplication.\n\n- Which frames actually force the drive branch. `guard` does; `map` and\n  `dynamic-wind` do not, because both are bootstrapped in Scheme\n  (vm_bootstrap.zig) and their thunk call stays in the same runUntil. All\n  four fibers in that test run the identical `(read-char rp)`. README section\n  Fibers already says this; two Zig doc comments still name dynamic-wind and\n  map/for-each as re-entrant native frames, including the user-visible\n  \"port I/O abandoned\" message text.\n\nDeterminism, rather than sleeping, comes from FIFO dispatch: a trivial\n`(fiber-join (spawn ...))` dispatches every already-spawned fiber to its first\nblocking point first. 6/6 identical runs; unchanged under -Dgc-stress=true.\n\nThe production diff is visibility only — nine wait-context types go `pub` so\nthe asymmetry table can name them — plus the vm_tests.zig registration.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Gate the write-side parking assertions to POSIX\n\nWindows CI reached .completed where the test expected .io_waiting: the\n20 KB write is accepted outright, so the flush never EAGAINs and there is\nnothing to park on. Shrinking SO_SNDBUF is what forces the park on\nkqueue/epoll hosts and it does not have that effect there.\n\nWhy the mechanism is not stated in the comment: I could not establish\nwhether the reduced SO_SNDBUF is ignored or the socket layer simply\nbuffers past it, and this cannot be checked from the dev machine. The\ncomment records the observed outcome and says so, rather than asserting a\ncause that was never verified.\n\nThe gate covers only the three parking assertions. The lossless-resume\nassertions -- 20000 bytes arriving exactly once, nothing lost to a park\nand nothing duplicated by a re-execution -- are the property the test\nexists for, and they still run on every platform whether or not a park\noccurred.\n\nVerified: 30/30 on macOS with the gate in place (so it does not silently\ndisable the test here), and `zig build test -Dtarget=x86_64-windows`\ncompiles clean -- the same command CI's windows-cross job runs.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-01T02:13:39+05:30",
          "tree_id": "d08a5fccaf4ff34f7ba9e8882d7536c6c8f468dd",
          "url": "https://github.com/kaappi/kaappi/commit/2b2027b1d8c95e9e7932da541ad37edc2af9da14"
        },
        "date": 1785536810385,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.24768,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.674911,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.45735,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.24858,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004612,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.037616,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.24723,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.045303,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.279681,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.015743,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.262393,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.254601,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.35284,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.833433,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.03751,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "9a82cd4d90d32a2c8e7d0d5f5b4b0680a39238e3",
          "message": "Say which kind of failure a port error is (#1944) (#1969)\n\nprimitives_io.zig had 44 typeError sites and zero indexError/argError\nsites, so every non-type failure in the file arrived mislabelled.\n\nSeeking a string port past its end raised a detail-less \"invalid\nargument in 'set-port-position!'\" — no index, no length — while the\nsibling non-seekable path three branches down did set detail. It reports\nindex and length now (KP3006).\n\nwrite-string's range check blamed args[0]: `(write-string \"abc\" p 5)`\nsaid \"expected valid range, got #<string>\", naming the one argument that\nwas valid. The offending index is named now, following substring, the\nhouse precedent for a start/end pair. An inverted-but-in-range pair is\nneither a type nor a range fault, so `(write-string \"abc\" p 2 1)` is\nargError: \"start 2 is greater than end 1\".\n\nA closed port was \"type error: expected open input port, got #<port>\".\nA closed port is a port, and the direction check has already run, so\nnothing about its type is wrong — that is argError (KP3007). A genuine\nnon-port, and an input port where an output port is wanted, are still\ntype errors; both are pinned as controls.\n\nThree internal guards carried the tag .claude/rules/gc-safety.md\nforbids: waitPortFd and raisePortClosedDuringIo reported a missing VM or\nGC as KP3007, blaming the program for a broken interpreter. #1874\nblessed these as Rule 1 keepers on the grounds that they \"already\ncarried a tag of their own\" — but InvalidArgument is not a tag either\nfunction returns for any other reason, and raisePortClosedDuringIo is a\nbyte-for-byte twin of raiseWrappedPortClosed 950 lines down the same\nfile, which Rule 2 had already moved. Both are settled the same way now,\nand the doc's seam paragraph says why the Rule 1 side is narrower than\nit read.\n\nThe audit file's existing assertions only ever asked whether a bad call\nraises, which is how all of this drifted; 13 new assertions pin the\nmessage text, 9 of which fail without this change. The guard tags are\nunreachable from Scheme, so they get a Zig test where the private\nhelpers live.\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-01T02:25:15+05:30",
          "tree_id": "3d6c4b566c2864f447d18282ec13a6ece5c07ca8",
          "url": "https://github.com/kaappi/kaappi/commit/9a82cd4d90d32a2c8e7d0d5f5b4b0680a39238e3"
        },
        "date": 1785536944840,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.287284,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.785897,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.570462,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.952305,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004713,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.04671,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.31136,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.056612,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.686396,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.24324,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.582693,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.286477,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.771485,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.50433,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042888,
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
          "id": "fab1e9e9864d8b9b0caf98df3609801924cefe37",
          "message": "Bump vmactions/netbsd-vm from 1.4.3 to 1.4.4 in the github-actions group (#1970)\n\nBumps the github-actions group with 1 update: [vmactions/netbsd-vm](https://github.com/vmactions/netbsd-vm).\n\n\nUpdates `vmactions/netbsd-vm` from 1.4.3 to 1.4.4\n- [Release notes](https://github.com/vmactions/netbsd-vm/releases)\n- [Commits](https://github.com/vmactions/netbsd-vm/compare/fac0a63f3e5244c600cb9ca532d27ee774ecdb4b...bf34bcd909bb50856f934a67d09a8fbe2b966a1b)\n\n---\nupdated-dependencies:\n- dependency-name: vmactions/netbsd-vm\n  dependency-version: 1.4.4\n  dependency-type: direct:production\n  update-type: version-update:semver-patch\n  dependency-group: github-actions\n...\n\nSigned-off-by: dependabot[bot] <support@github.com>\nCo-authored-by: dependabot[bot] <49699333+dependabot[bot]@users.noreply.github.com>",
          "timestamp": "2026-08-01T02:31:30+05:30",
          "tree_id": "0e04d110683f4745caedbdc00e29ef9edc2bcc65",
          "url": "https://github.com/kaappi/kaappi/commit/fab1e9e9864d8b9b0caf98df3609801924cefe37"
        },
        "date": 1785537513088,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.927184,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.157308,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.560264,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.816146,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004844,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.045731,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.295585,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.054657,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.31871,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.157812,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.577712,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.296566,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.675182,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.765222,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044383,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "775890947add3c041dcaa46606f654797330ec9f",
          "message": "Document what may actually cross a thread boundary (#1964)\n\nThe uncopyable-tag list in gc_deep_copy.zig reads as the authoritative\nanswer to \"what can cross a thread boundary\". It is not: it governs the\n*copy* route only — the thread-start! thunk closure, the thread-join!\nresult, a channel message. A value reached through the shared globals map\n(VM.initForThread shares the parent's map by pointer) is never copied and\nnever reaches that switch.\n\nThirteen of the fourteen tags are freely usable through a top-level\ndefine, and for mutexes and condition variables a global is the *only*\nsupported way to share one — exactly inverted from a channel, which must\nbe captured lexically. Nothing anywhere noted that the two differ, and\nthey appear side by side in every concurrency example.\n\nThe globals route is defended per-type inside individual primitives, and\ntwo types do so: channels and thread handles. Extending that to the rest\nuniformly is not possible — it would remove the sole way to synchronise\nthreads — so the honest model is documented instead, with the two\nknown-unsound rows left to their own issues (#1924, #1936).\n\nCLAUDE.md's \"threads cannot share mutable heap state\" was the false\nguarantee in its most compact form; it now describes both routes.\n\ndocs/dev/thread-value-sharing.md holds the per-type matrix.\nsrfi18-sharing-model.scm pins both routes for the nine types covering\nevery distinct enforcement shape, as a characterisation test, so a change\nto any row fails visibly instead of widening the gap silently.\n\nCloses #1937\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-31T21:10:49Z",
          "tree_id": "d2444d938a890c0924bc2a6909420c9b4f7d7cae",
          "url": "https://github.com/kaappi/kaappi/commit/775890947add3c041dcaa46606f654797330ec9f"
        },
        "date": 1785539453227,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.272862,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.045469,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.580243,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.954901,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004639,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.047974,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.312345,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.056273,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.677575,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.230175,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.571281,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.282839,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.767409,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.611099,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044674,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "ea2e2e4988014e8fdcd40e9a0e1d957a96366918",
          "message": "Stop the \"port I/O abandoned\" error naming dynamic-wind as unparkable (#1965)\n\nThe message named \"guard, dynamic-wind, callbacks\" as frames a fiber cannot\nsuspend under. dynamic-wind is bootstrapped Scheme: its body runs in the\nbytecode dispatch loop and a fiber parks inside it like a bare read, so the\nerror sent users to move blocking I/O out of a dynamic-wind for no reason and\nleave it inside the guard that actually caused the drive.\n\nIt now names what genuinely opens a nested native frame: guard, and the native\nhigher-order drivers (SRFI-1 fold/filter/find, hash-table-walk, assoc/member\nwith a custom predicate, string-index, eval).\n\nSix comment copies of the same misclassification are corrected alongside,\nincluding raiseDeadNativeReturn's \"(map, for-each, sort, apply, ...)\", which\nnames sort — portable Scheme in lib/srfi/95.sld. README's list dropped sort\nfor the same reason.\n\nRegression test: readers blocking inside dynamic-wind, a map callback, and a\nsort comparator must all reach .io_waiting when dispatched before any writer\nexists, contrasted with the adjacent #1625 test where guard drives.\n\nCloses #1959",
          "timestamp": "2026-08-01T03:18:44+05:30",
          "tree_id": "bfe137901e3db835719f43581031bc920923d102",
          "url": "https://github.com/kaappi/kaappi/commit/ea2e2e4988014e8fdcd40e9a0e1d957a96366918"
        },
        "date": 1785539635941,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.254348,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.736404,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.596318,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.947722,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004738,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.04658,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.31624,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057427,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.69308,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.160761,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.587188,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.284167,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.775336,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.640932,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044048,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "ab961376f282c00a307028ea6aa09994bee2f311",
          "message": "Drop the resolved blocker from the 5B entry (#1971)\n\n#1960 merged, so \"open, blocked by #1967\" is no longer true in either the\nstatus line or the unit entry. #1967 was the pipefail/grep -q race in the\nshell suites, fixed by #1966; 5B's FreeBSD leg then passed with nothing\nchanged but its base.\n\nLeft alone deliberately: the entry still records that 5B found no bugs in\nwaitForFd and says what it closed instead. That is the part most likely to\nbe misread as a wasted unit, and it is the reason the entry is worth\nhaving.\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-01T03:29:54+05:30",
          "tree_id": "833a0f07a416b0052c538d54bc36536d5875124f",
          "url": "https://github.com/kaappi/kaappi/commit/ab961376f282c00a307028ea6aa09994bee2f311"
        },
        "date": 1785539745203,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.261632,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.641274,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.60754,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.949783,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.005107,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.04676,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.316313,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057629,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.723387,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.205618,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.606921,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.290104,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.793277,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.685328,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044872,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "5fdc06de60ce50a6e0b7efb163cfa185cf0e5445",
          "message": "Phase 2.5: SRFI 237 audit — 186 assertions, and a 27-field record aborts the process (#1975)\n\n* Audit primitives_srfi237.zig: 186 assertions, one uncatchable panic\n\nPhase 2.5 of the v2 audit campaign (docs/audit-strategy.md, #1890). The\nfile had no audit test and postdates the v1 campaign entirely.\n\nCovers all 18 specs, the R6RS `define-record-type` desugarer that shares\ntheir enforcement helpers, and the portable layer in lib/srfi/237.sld\nthat is their only other caller. The oracle is R6RS Library chapter 6:\nSRFI 237 defines every one of these as \"equivalent to the procedure with\nthe same name in R6RS\", so R6RS's own sentences are quoted beside the\nassertions they justify.\n\nConfirmed correct, with the assertions to keep it that way:\n\n  * Protocol composition over a 4-level chain, all 16 present/absent\n    combinations, plus the rule that a protocol runs once per\n    record-constructor call and never per instance.\n  * Field shadowing — a child redeclaring an ancestor's field name gets\n    its own slot, its own mutability, and leaves the ancestor's readable.\n  * sealed, enforced identically from both layers via one shared helper.\n  * nongenerative uid reuse, and all four R6RS equivalence axes rejected\n    with the differing axis named. The type NAME is correctly not an axis.\n  * A nongenerative record survives thread-join! with its identity, by\n    uid re-resolution in gc_deep_copy.\n  * All 18 arities match their bodies; all 18 reject bad input catchably.\n\nDisabled, each paired with an enabled control (26 markers):\n\n  * A record type with 27 or more fields PANICS on instantiation —\n    allocRecordInstance sizes itself in u8 arithmetic. Uncatchable, and\n    reachable from plain R7RS define-record-type, not just SRFI 237.\n    Control: 26 fields works.\n  * record-type-field-names returns a list; R6RS requires a vector.\n  * record-accessor/record-mutator take k as an absolute index across\n    inherited fields; R6RS requires an own-field index. Control: the\n    by-name path resolves per level correctly, and record-field-mutable?\n    already uses own-field indexing on the same rtd.\n  * The opaque flag is stored but never enforced: record? answers #t,\n    record-rtd returns the rtd, and opacity is not inherited.\n  * record-mutator does not reject an immutable field.\n  * Three specified names are absent and undocumented: the 7-argument\n    make-record-descriptor, make-record-constructor-descriptor, and\n    record-constructor-descriptor?.\n\nAlso pins the current behaviour of #1914 (own-field 255-limit overflow\nreports a bare TypeError blaming args[0] while the inherited path reports\nit precisely), #1915 (constructor arity unchecked, so an extra argument\nsilently shifts the field layout) and #1932, so their fixes flip a test.\n\nDiscovery only — no source changes.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Point SRFI 237 FAIL markers at the filed issues\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-01T03:36:47+05:30",
          "tree_id": "820e20c4c901e51210b7a60b1232818cdf755dc3",
          "url": "https://github.com/kaappi/kaappi/commit/5fdc06de60ce50a6e0b7efb163cfa185cf0e5445"
        },
        "date": 1785540559899,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.270532,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.122883,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.606205,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.950425,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004715,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.04682,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.315995,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057198,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.719247,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.205352,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.611071,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.2911,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.784604,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.698868,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044987,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "c3e05be76342221dc8c933c78d5c00ddd2504a6e",
          "message": "Phase 6D: LSP end-to-end — 152 assertions for a 942-line server with no prior integration test (#1987)\n\n* Audit 6D: drive the language server end-to-end, 152 assertions\n\nkaappi_lsp.zig was 942 lines with 6 inline unit tests and no integration\ntest of any kind — the largest wholly-untested subsystem in the tree. It\nneeds no editor to test: it is JSON-RPC over stdio with Content-Length\nframing, so a shell driver can write framed requests to the real binary's\nstdin and assert on the framed replies.\n\ntests/scheme/lsp/lsp.sh pins the advertised capability set, exact framing\n(a lone shutdown is exactly 60 bytes on the wire), id correlation, a full\ninitialize -> initialized -> didOpen -> hover/definition/references/\ndocumentSymbol/completion -> shutdown -> exit session, and cross-checks\nevery published diagnostic against `kaappi check --diagnostics=json`,\nwhich shares the serializer in src/lsp_diagnostic.zig.\n\nCross-checking is where the value is. On read and compile errors the two\nsurfaces agree exactly on code, severity and start line. They diverge in\nfour ways, all reproduced with a discriminating control and left as\ndisabled assertions:\n\n  * a `define-syntax` in one open document leaks through the shared\n    vm.macros table into every other document's diagnostics, so\n    byte-identical text is diagnosed clean and then KP2001 purely\n    because an unrelated file was opened; closing it does not retract\n    the macros, and a plain `define` of the same name does not leak.\n  * `hasMore() catch false` discards every reader error raised while\n    skipping intertoken space, so an unterminated `#|` comment hides\n    the whole file — no diagnostic and an empty documentSymbol list —\n    while check reports KP1001.\n  * runDiagnostics breaks at the first bad form, so a two-error file\n    publishes one diagnostic where check reports two; and no KP4xxx\n    lint runs at all, so check's arity error exits 1 on a file the\n    editor shows as clean.\n  * the range is always a whole-line 0..999 sentinel, never the real\n    span check pinpoints.\n\nProtocol edges account for the rest: a malformed *body* is skipped and\nthe session continues, but a malformed *header* silently ends it and\ndrops every later message; a request whose params are missing gets no\nreply at all, so a client blocks on that id forever; shutdown is answered\nbefore initialize and requests are still served after it; exit without a\nprior shutdown returns 0 where LSP requires 1; and a column past\nend-of-line resolves a symbol on a later line.\n\nNo hangs found. Deeply nested input, recursive macros, prose, and\nunopened URIs all degrade cleanly. Runtime 3.4s, deterministic over 5\nruns. Discovery only — no server code changed.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Point LSP FAIL markers at the filed issues\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-01T04:12:23+05:30",
          "tree_id": "303ce149ce4fb5fe469b145f4bb3d4ce26d7b6a5",
          "url": "https://github.com/kaappi/kaappi/commit/c3e05be76342221dc8c933c78d5c00ddd2504a6e"
        },
        "date": 1785540837603,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 2.184053,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 5.125663,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.275183,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 1.513863,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.002861,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.02383,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.145922,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.02752,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 1.243178,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.586527,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 0.810014,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.19347,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 0.883137,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.189009,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.025018,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "e7c723ddf073ad0865ba358f129607c3c0916c77",
          "message": "Tick 2.5 and 6D; close 3.2/3.3 as subsumed by 2.4 (#1990)\n\n* Close SRFI 160 sweeps 3.2 and 3.3 as subsumed by 2.4\n\n2.4 audited primitives_srfi160.zig AND the portable surface it carries,\nwhich is what 3.2 and 3.3 were scoped to cover separately. Its 1066\nassertions already sweep all 12 element kinds at every boundary, both\nseams, and the per-type wrappers.\n\nLeft open, they would tell the next session that SRFI 160 coverage is\nmissing when it is not -- the same class of drift Phase 0B existed to\nremove, just pointing the other way: a tracker that overstates remaining\nwork wastes a session as surely as one that understates finished work.\n\nStruck through rather than deleted, with what 2.4 actually covered\nrecorded inline, so the decision is auditable instead of looking like\nunits that quietly vanished.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Tick 2.5 and 6D, and record why 2.12 and 5D are not ticked\n\nOnly two of the fourth batch merged. 2.12 and 5D are complete and green\non macOS but held by real BSD failures -- 2 assertions on FreeBSD and\nOpenBSD, 1 on NetBSD, out of 421 and 273 respectively.\n\nThose stay unticked rather than ticked-with-a-caveat, because the work is\nnot landed and the tests are not running anywhere. The status line names\ntheir PRs so the next reader knows the units exist and where they stopped,\ninstead of finding two silently missing entries.\n\nUnlike the earlier #1967 case, this is not harness flake: the failures are\nin the units' own audit files, on the platforms whose filesystem and\nthread semantics those units probe, and the same files pass everywhere\nelse. Chasing them needs a real BSD box.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-01T04:50:56+05:30",
          "tree_id": "126dd8c90836116d52c13be556bf97b05954044d",
          "url": "https://github.com/kaappi/kaappi/commit/e7c723ddf073ad0865ba358f129607c3c0916c77"
        },
        "date": 1785541364331,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.254822,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.863211,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.588007,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.951469,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00471,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046534,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.315574,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057158,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.645479,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.228194,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.581629,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.28531,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.780013,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.648735,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043476,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "c1fb2025bcd90d0cd64991376ba714e91ca822ff",
          "message": "Phase 5D: SRFI-18 re-audit — 77 → 274 assertions, and thread-terminate! cannot interrupt a native wait (#1986)\n\n* Phase 5D: re-audit SRFI-18 — 274 assertions, six bugs, one of them a hang\n\nThe v1 campaign audited src/primitives_srfi18.zig at 994 lines. It is now\n1435 lines across 34 specs (+793/-352 over 27 commits since the v1 base),\nwhile tests/scheme/audit/primitives_srfi18-audit.scm had not changed since\n2026-07-10. This grows it from 77 assertions to 274 (+197), covering every\nspec — thread-yield! had never been called at all — plus the full mutex\nstate matrix, the condition-variable protocol, the terminate matrix, and\ntime/timeout parsing in both spellings.\n\nSix root causes found, all with a discriminating control, 20 assertions\ndisabled behind `;; FAIL:` markers:\n\n* mutex-unlock! never clears the abandoned flag, so an abandoned mutex a\n  program explicitly resets by unlocking still raises a spurious\n  abandoned-mutex-exception. SRFI 18: \"Unlocks the mutex by making it\n  unlocked/not-abandoned.\"\n* thread-terminate! on an already-terminated thread destroys its\n  end-result (and, for a thread that raised, its end-exception): the\n  `terminated` store sits above its own completed/errored guard, and\n  threadJoinResult tests `terminated` first.\n* thread-terminate! is not observed by a thread parked inside a native\n  SRFI-18 wait. #880 was closed by a 1024-instruction dispatch-loop\n  safepoint, which a thread blocked in threadSleepFn / mutexLockFn /\n  mutexUnlockFn's condvar branch never reaches. thread-join! then blocks\n  for the rest of the wait — or forever, when the wait is untimed.\n* Unguarded float-to-int conversions abort the process (exit 134,\n  uncatchable) in seconds->time, thread-sleep!, and timeoutToDeadlineNs —\n  the last of which also serves mutex-lock!, thread-join!, mutex-unlock!\n  and (kaappi fibers) channel timeouts. Two distinct panics, one cliff.\n* mutex-lock! with a terminated thread as the owner argument records it as\n  the owner instead of making the mutex unlocked/abandoned.\n* A thread that terminates itself joins as an uncaught-exception with a\n  void reason rather than a terminated-thread-exception.\n\nThe suite is deterministic and bounded: no wall-clock assertions, every\nwait either timeout-bounded or resolved by a thread the file joins, and\nevery aborting or hanging shape commented out rather than\ntest-expect-fail'd. Helper threads spin in Scheme rather than sleeping —\nterminating a sleep-polling child costs 3.8s against run-all.sh's 60s\nper-file timeout, because terminate latency tracks wall-clock time per\n1024 bytecode instructions.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Point SRFI-18 FAIL markers at the filed issues\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Stop pinning the value of an undefined float conversion\n\nCI's NetBSD failed \"seconds->time +nan.0 collapses to 0\". That assertion\npinned the result of @intFromFloat on a NaN, which is undefined -- macOS\nand the NetBSD reference VM both happen to yield 0.0, so it passed\neverywhere I could reach and failed where I could not.\n\nSix sequential runs and twelve four-way-concurrent runs on the NetBSD VM\nwere all clean, which is exactly why the CI log had to be read for the\nassertion NAME rather than the failure re-created: an idle box cannot\ndistinguish \"fixed\" from \"did not fire\", and this was never a race to\nbegin with.\n\nThe finding the assertion exists for is that NaN does NOT abort, unlike\n+inf.0 and |x| >= 2^63 which do (#1983). That contrast survives without\nnaming a value, so it now asserts only that a time object comes back.\n\nVerified on the NetBSD VM: 274 pass, 0 fail.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-01T06:24:25+05:30",
          "tree_id": "9ba57b12ca70152f2d2bf1e0aa27fc7312f4baac",
          "url": "https://github.com/kaappi/kaappi/commit/c1fb2025bcd90d0cd64991376ba714e91ca822ff"
        },
        "date": 1785548739422,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.269905,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.015683,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.607222,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.987249,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004703,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.04667,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.315783,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057145,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.696756,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.204723,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.589758,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.287722,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.785645,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.610294,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043337,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "321da93a6fd8ab5ef64c637ac0338894e4cae1c1",
          "message": "Evaluate guard clauses in the guard's own dynamic environment (#1991)\n\nFixes #1988.\n\nR7RS 4.2.7 evaluates a guard's implicit `cond` \"with the continuation and\ndynamic environment of the guard expression\". A handler, though, runs at the\nraise point, with every `parameterize`/`dynamic-wind` extent entered since the\nguard still live — and the desugaring handed the escape continuation the cond's\n*value*, so the clauses ran there. A plain `raise` hid it, because this VM\nunwinds before calling any handler; the `raise-continuable` a declining `guard`\nissues for its implicit re-raise does not, so an extent between a declining\ninner guard and an outer one leaked into the outer guard's clauses.\n\nThe clauses now run after a new internal `%unwind-to-escape` has left those\nextents. Escaping to the continuation first would do the same job in one step —\nthe issue's own suggestion, and what R7RS's sample implementation does — but the\nescape has to come after the clauses, not before: a clause may reinstate a\ncontinuation captured inside the guard body, and this VM cannot resume one whose\nnative frame has returned. `(srfi 255)`'s restarters are exactly that shape, and\nescaping first breaks them. Splitting the unwind from the escape keeps those\nframes standing; the escape then finds the wind stack already at its target.\n\nOne deviation remains, documented under \"Known limitations → Exceptions\" in\nREADME.md: with no matching clause the re-raise happens in the guard's dynamic\nenvironment rather than the original raise's, which is what a plain `raise`\nalready does here.\n\nAlso fixes a pre-existing leak on the same path: `raiseContinuable` re-pushed\nthe handler it had popped even when the handler left via a continuation that had\nalready reset the handler stack. `guard`'s handler always leaves that way, so\nevery declining guard stranded one slot — 32768 hit the KP3008 cap.\n\n🤖 Generated with [Claude Code](https://claude.com/claude-code)",
          "timestamp": "2026-08-01T06:43:36+05:30",
          "tree_id": "7786e4f016b4ca6ddd2638d2871bc5688c2c3a16",
          "url": "https://github.com/kaappi/kaappi/commit/321da93a6fd8ab5ef64c637ac0338894e4cae1c1"
        },
        "date": 1785549153528,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.446467,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.655736,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.587069,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.013796,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.005032,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.048615,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.319843,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.058708,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.766632,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.255872,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.643694,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.301625,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.822337,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.724247,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.048961,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "793abc6a9999beb324f424307b8e7e83606e5c67",
          "message": "Make SRFI 237's record procedures obey R6RS 6.3 (#1989)\n\n* Make SRFI 237's record procedures obey R6RS 6.3\n\nSRFI 237 defines most of its procedural and inspection layers as\n\"equivalent to the procedure with the same name in R6RS\", and four of\nthem were not. Each had a control in the same library showing the data\nneeded was already present, so these were reporting bugs rather than\nmissing capability:\n\n  - record-type-field-names returned a list where R6RS requires a\n    vector, while make-record-type-descriptor already demanded a vector\n    for the same field list.\n  - An integer k for record-accessor/record-mutator indexed the whole\n    instance rather than the rtd's own fields (\"k cannot be used to\n    specify a field of any type rtd extends\"), so it silently returned\n    an ancestor's field -- and disagreed with record-field-mutable?,\n    whose own k was already own-relative. The integer path also skipped\n    rtd validation and never range-checked k.\n  - The opaque flag was stored and read back but never enforced, and\n    was not inherited from an opaque parent.\n  - record-mutator returned a working mutator for an immutable field.\n\nKeeping %record-type-field-names list-valued and converting at the\npublic boundary leaves the primitive's contract, its audit test, and\nthe internal index walks in SRFI 57/131/136/150 untouched. Opacity is\nmade effective at construction by a helper both creation paths share,\nfor the same reason the sealed-parent and nongenerative rejections\nalready share theirs: the procedural and syntactic paths must not drift\ninto disagreeing about what R6RS requires.\n\nSRFI 137 relied on the absolute-index reading -- its subtypes declare\nzero own fields, so no k names the payload -- and now asks by name.\n\nAlso add the three specified names that were missing, which made a test\nwritten against the R6RS spelling fail on the binding rather than on the\nbehaviour under test: make-record-constructor-descriptor,\nrecord-constructor-descriptor?, and the 7-argument\nmake-record-descriptor.\n\nThe 7-argument form is specified as passing its `parent` to both\nmake-record-type-descriptor and the parent-descriptor slot, which only\ntype-checks once a record descriptor is accepted wherever an rtd is\nexpected -- the SRFI's \"the type of record descriptors is a subtype of\nthe type of record-type descriptors\". That widening exposed the\nremaining gap: a syntactic define-record-type's <record name> evaluates\nto a simple rtd, and a protocol lives on the descriptor, so deriving a\nprotocol-less descriptor from one would quietly bypass the protocol and\nstore the raw constructor arguments. Rather than give RecordType a\nGC-traced protocol field, %record-type-constructor recovers the\nfinished, protocol-applied constructor the desugarer already bound,\nafter confirming the sibling type alias still names that same rtd (both\naliases are keyed by type name, so a generative redefinition rebinds\nthem). When it cannot be recovered and the new has_protocol bool says\nthere is one, it raises rather than building a wrong record. Together\nthese make the SRFI's own worked Examples section run -- a procedural\ntype inheriting from a syntactic one whose construction a protocol\ngoverns.\n\nFixes #1974\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Note the SRFI 237 conformance fixes in the changelog\n\nrecord-type-field-names changing from a list to a vector is a breaking\nchange for any caller, so it needs the migration note rather than just\na bug-fix line.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Re-pin the SRFI 237 audit to the corrected R6RS semantics\n\n#1975 landed its audit while this fix was in review, so the two disagree\nby construction: 20 of its assertions pinned the defects #1974 reports as\na \"before\" for exactly this PR, and 10 more sat commented out waiting for\nthe fix. Flip both sets.\n\nThree of the re-pinned ones needed a real rewrite rather than an edited\nexpectation, because they read an inherited field by index -- which is\nprecisely what R6RS says k cannot do. The 4-level protocol matrix and the\narity cases now reach each level's single field as k=0 on that level's\nown rtd, walking the parent chain, so they exercise the same instance\nslots without relying on the flat layout.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-01T06:45:42+05:30",
          "tree_id": "0ddf8334f627640311beb339dc3338386bb14fa3",
          "url": "https://github.com/kaappi/kaappi/commit/793abc6a9999beb324f424307b8e7e83606e5c67"
        },
        "date": 1785549796008,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.90522,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.830477,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.5563,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.933475,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004794,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.044731,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.291311,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.054475,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.338485,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.146848,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.509085,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.309517,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.665579,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.775094,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045192,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "e6081c3ba6db8aa8b00526fd71c5fb8d00354216",
          "message": "Tick 5D, and record the portability lesson it cost (#1992)\n\n5D merged with all three BSD legs green. 2.12 remains blocked: the rdev\nfix was real and verified on the FreeBSD VM, but CI then surfaced a\nsecond, distinct divergence that the VM cannot reproduce -- CI runs\nFreeBSD 14.3 and the reference VM runs 15.1, and their assertion totals\ndiffer (423 vs 412), so the two are not comparable runs.\n\nThe 5D entry records the lesson rather than just the issue numbers,\nbecause it generalises: an assertion that pins the VALUE of an undefined\nfloat conversion passes everywhere the conversion happens to agree and\nfails where it does not. Assert the property that is actually specified --\nhere, that NaN does not abort, which is the real contrast with #1983's\naborting cases.\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-01T07:43:03+05:30",
          "tree_id": "5c4782daabbc524c1ada38770730747e6c944467",
          "url": "https://github.com/kaappi/kaappi/commit/e6081c3ba6db8aa8b00526fd71c5fb8d00354216"
        },
        "date": 1785551790540,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.916267,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.703441,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.554643,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.808193,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004849,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.044966,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.291276,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.054778,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.329555,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.147941,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.515761,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.307842,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.674297,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.76172,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044506,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "d0ea592b34aa98c74a1e827c36b0635820dfdc70",
          "message": "Phase 2.12: filesystem audit — 69 → 428 assertions, and file-info aborts on any /dev path (#1985)\n\n* Audit primitives_filesystem.zig: 69 -> 428 assertions, all 68 specs\n\nv2 audit campaign Phase 2.12 (docs/audit-strategy.md).  The file had 68\nregistered procedures and ~102 syscall sites against a 177-line test that\nnever mentioned 10 of them, and exercised almost no error path.\n\nAdds the syscall-boundary matrix the happy-path tests never reach —\nnonexistent path, wrong kind of object in both directions, permission\ndenied, broken symlink, symlink loop (including a self-loop), path too\nlong, empty path, embedded NUL across all 24 path-taking procedures,\nrelative-vs-absolute, and a path that vanishes between two calls — plus\nfile-info across every reachable file type, the full directory-object\nlifecycle (read past end, double close, use after close, mutation during\ntraversal, 2000-entry buffer refill, GC finalisation of an unclosed\nstream), the error taxonomy, and the SRFI-18 deep-copy boundary.\n\nEvery disabled assertion carries a \";; FAIL: TBD\" note and an enabled\ncontrol proving the same validation fires for a neighbouring input, so\nthe gap is located rather than merely observed.\n\nDiscovery only — no source changes.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Point filesystem FAIL markers at the filed issues\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Stop asserting one platform's spelling of \"no device number\"\n\nFreeBSD reports st_rdev = -1 (NODEV) for a non-device file where macOS\nand Linux report 0, so three assertions that hardcoded 0 failed there --\n2 in CI, 3 when run directly on the FreeBSD reference VM.\n\nWhat the SRFI actually promises is that a plain file has no device\nnumber, not what the absent-value sentinel looks like, so accept either\nspelling and say why in a comment.\n\nFirst attempt used (test-equal #t (memv ...)), which still failed:\nmemv returns the matched tail, not #t. Converted to test-assert.\n\nVerified on the FreeBSD VM: 409 pass / 3 fail before, 412 pass / 0 fail\nafter.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Name every assertion in the filesystem audit\n\nCI's freebsd-test fails two assertions in this file and the log prints\nbare `#f` / `FAIL` with nothing to identify them. The reference VM runs\nFreeBSD 15.1 against CI's 14.3 and executes 11 fewer assertions, so the\nfailure cannot be reproduced locally -- leaving no way to tell WHICH\nassertions fail.\n\nBy contrast the NetBSD failure in 5D was diagnosed in a single step,\nbecause that assertion happened to have a name: the CI log printed\n\"FAIL TODAY: seconds->time +nan.0 collapses to 0\" and pointed straight\nat it.\n\nNames are derived from the expression under test rather than invented,\nso they stay meaningful and need no upkeep: (test-equal 0 (file-info:rdev\nfi)) becomes (test-equal \"(file-info:rdev fi)\" 0 (file-info:rdev fi)).\n\nSRFI-64 already supports source-file/source-line, but nothing populates\nthem -- portable syntax-rules cannot capture source location -- so naming\nis the only route available in Scheme.\n\nSemantics-preserving, verified: 426 assertions before and after, 428\npasses before and after, and test-name now appears in the log. An earlier\ncut of the generator truncated labels BEFORE escaping them, which sliced\n`#\\z` to `#\\` and produced an invalid escape; it now truncates first and\nescapes after, so a trailing lone backslash is legal.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Fix three platform assumptions the BSD legs caught\n\nNaming the assertions (previous commit) paid off immediately: freebsd-test\nprinted `FAIL (memv (file-info:rdev fi) '(0 -1))` instead of a bare `#f`,\nwhich named the defect outright.\n\nrdev: POSIX defines st_rdev only for character- and block-special files.\nFor everything else it is unspecified, and two successive guesses were both\nwrong on CI — first 0 (macOS, Linux), then {0, -1} adding FreeBSD's NODEV.\nFreeBSD 14.3 still failed for a regular file while *passing* for a fifo in\nthe same run, which is precisely what \"unspecified\" licenses. Dropped both\nvalue assertions; the exact-integer? check is the whole portable contract.\n\nfd exhaustion (#1993): the suite opened 3000 directory streams without\nclosing them, asserting the GC reclaimed them. It does — but only when its\nallocation-count threshold happens to trip, never on descriptor pressure.\nAt `ulimit -n 256` exactly 253 unclosed opens succeed, i.e. no collection\nruns at all; at 1024, 1745 do. Ports behave identically (253 / 1747), so\nthis is a property of every fd-holding object, not of open-directory. The\nassertion passed on macOS and Linux only because their limit is 1048576,\nand on openbsd-test and netbsd-test it exhausted the table and took down\nthe *next* block, which could no longer create its own scratch files:\n\n    error[KP3000]: cannot open output file \"/tmp/kaappi-a212-68521-14/f0\"\n\nDisabled behind a FAIL marker, and replaced with the half the program\nactually controls: 3000 open/close cycles must not accumulate descriptors.\n\nLog noise: three stray `#f` lines came from this suite's own top-level\ncleanup calls, because kaappi echoes non-void top-level values when running\na script. That is deliberate and long-standing, but documented only in\ndocs/dev/fuzzing.md — filed as #1994. Here the fix is local: an empty\ncond-expand else branch and void-returning cleanup helpers.\n\nVerified at ulimit -n 256, 512, 1024 and the default: 427 passes, 0\nfailures, and two lines of output.\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-01T08:25:34+05:30",
          "tree_id": "380a94de94a16a7b89614c7704875c9653d9213d",
          "url": "https://github.com/kaappi/kaappi/commit/d0ea592b34aa98c74a1e827c36b0635820dfdc70"
        },
        "date": 1785557594009,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.395255,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.50684,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.603686,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.993736,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00475,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046961,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.313045,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057365,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.620513,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.226148,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.587602,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.286927,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.786872,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.475363,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044115,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "1aedd4014ee6a3ddc5b3fc88a20b81db5f0e2228",
          "message": "Phase 2.3: SRFI 181 audit — 196 assertions, and (read port) has never worked on a custom or transcoded port (#2015)\n\n* Phase 2.3: audit SRFI 181 custom and transcoded ports\n\nprimitives_srfi181.zig had no audit test at all. This adds one — 196\nassertions plus 17 disabled — covering all 10 native specs, the whole\nportable layer in lib/srfi/181.sld, and the SRFI's own obligations on the\nimplementation that nothing else asks about: the read!/write! argument\ncontract, the six callback sites' blocking rejection, positioning under\nlookahead, cross-heap deep copy, and the eol-style x error-mode matrix in\nboth directions.\n\nFive issues filed, none fixed here (the campaign separates discovery from\nfixing):\n\n  #1995  (read port) returns #<eof> on every custom and transcoded port —\n         readDatumFn is the one input primitive that goes around\n         readOneByte, so it never invokes read! at all. read-char,\n         read-line, read-string and read-bytevector on the same port all\n         work; a string port and a file port read the same datum fine.\n  #1996  port-position on a custom port returns get-position verbatim,\n         ignoring the port's own read-ahead. The fd path subtracts it one\n         branch below. Also breaks the spec's explicit \"must return its\n         cached position rather than calling get-position\" after a peek.\n  #1997  Transcoded output ignores #\\return as a line ending, so a crlf\n         transcoder writes CR CR LF for one CRLF and a round trip turns\n         one line break into two. The decode direction gets it right,\n         which is what makes this an internal inconsistency.\n  #1998  close-input-port closes the output side of a bidirectional\n         custom port too, and runs its close callback.\n  #2012  Not SRFI 181's: the first (environment '(srfi N)) on a\n         file-backed .sld silently abandons the rest of the enclosing\n         top-level form. Found because a probe in this suite looked like\n         it passed and had in fact never run.\n\nClean results worth recording: the blocking-callback guard is correct at\nall six callback sites and every rejection stays catchable; the eol-style\ndecode matrix is right in all nine cells, including the lf-on-input case\nnothing tested before; gc_deep_copy refuses custom and transcoded ports\ncleanly at both SRFI-18 boundaries; and every neighbouring re-entrant\ncallback shape completes, which localises #1939 to the single-slot\nread_buf rather than re-entrancy as such.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Point 2.3's tracker entry at the PR that actually exists\n\nThe entry cited #1999, written before the PR was opened. The PR is #2015;\n#1999 is not a pull request at all.\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-01T09:57:11+05:30",
          "tree_id": "9355b4384f90d4864a87085c321de02745688913",
          "url": "https://github.com/kaappi/kaappi/commit/1aedd4014ee6a3ddc5b3fc88a20b81db5f0e2228"
        },
        "date": 1785560865965,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.383034,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.277644,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.57284,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.989605,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004672,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046303,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.312584,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.05709,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.568376,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.234059,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.576814,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.27986,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.794835,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.598625,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.04322,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "b94afc2bd917c568a69b9737e818eb6f6996d437",
          "message": "Phase 2.6: fibers audit — 32 → 111 assertions, and a channel receive inside a custom-port callback aborts the process (#2004)\n\n* Phase 2.6: audit (kaappi fibers) — 32 → 111 assertions\n\nprimitives_fiber.zig grew +1241/-110 since the v1 campaign against a\n135-line audit test — the largest churn-to-coverage ratio in the\nprimitives table. All 11 specs are covered now, along with KEP-0002 §6\n(capacity, rendezvous, close!, timeouts), the KEP-0001 park-vs-drive\nprotocol, and both halves of the cross-thread sharing model.\n\nFour findings, nine assertions disabled behind their issue numbers:\n\n- #1999 spawn never binds the thunk's parameters, so a non-thunk runs\n  anyway with the fiber's own closure and #<undefined> as arguments\n- #2000 channel/fiber blocking inside a SRFI-181 custom-port callback\n  bypasses in_custom_port_callback and aborts the process (SIGBUS)\n- #2001 fiber-join has no Object.owner check, so a child thread joins a\n  parent-heap fiber and gets the parent's object uncopied\n- #2002 argument diagnostics misidentify the problem\n\nEvery assertion carries a name string, and nothing asserts wall-clock\ntiming — only relative ordering and bounded termination — since this\nsuite runs under emulation on several CI targets.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Tick 2.6 in the audit tracker\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-01T09:57:48+05:30",
          "tree_id": "5c841c3136d66ed2cc824666068b359703ada988",
          "url": "https://github.com/kaappi/kaappi/commit/b94afc2bd917c568a69b9737e818eb6f6996d437"
        },
        "date": 1785561313471,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.386274,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.305795,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.585689,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.99437,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004971,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.04665,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.312631,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057241,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.590334,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.227978,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.603996,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.284607,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.789558,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.689255,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044194,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "940368ca69d1b97be0e12a274e7409351819c359",
          "message": "Phase 2.11: six unaudited primitives files — 247 assertions, and a use-site (let ((car ...))) hijacks car inside any macro (#2014)\n\n* Phase 2.11: audit the six unaudited small primitives files\n\nparallel, sysinfo, random_port, srfi258, srfi260 and srfi211 — ~570\nlines and 27 specs, all postdating the v1 campaign, none with an audit\ntest. 230 SRFI-64 assertions plus a 17-assertion --sandbox suite for\ndimension D7.\n\nThe six files are clean. All 27 specs behave correctly, every %-name is\nreachable with no import (D1) and none panics, the --sandbox gate matches\nits documented per-name split exactly, and SRFI 258's uninterned-ness\nsurvives both deep-copy directions with object sharing preserved.\n\nEvery finding is in the surrounding engine, reached through these files'\nown documented claims:\n\n  #2003  a use-site local binding captures a macro template's free\n         reference to a global procedure, so (let ((car ...)) ...)\n         hijacks car inside any macro. The local-scope half of closed\n         #1812; syntax-rules and ER alike, wrong against Chibi and Guile.\n  #2005  load of a file containing import fails, blaming the loader's\n         own line 1.\n  #2007  kaappi check calls two valid SRFI 211 transformer-specs\n         invalid syntax.\n  #2009  doc-truth: SRFI 260's rationale still says Kaappi has no\n         uninterned symbols, 51 minutes after SRFI 258 gave it some.\n\nExtended #1913: the all-zero-seed port's own state fails\nrandom-port-state?, so it cannot be rebuilt from itself.\n\nSeven assertions are staged disabled behind #2003 and #1913. The\nhygiene section keeps its parity assertions enabled, so a fix that\nlands on only one of the two macro paths fails here.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Point the 2.11 tracker entry at the real PR number\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-01T09:57:52+05:30",
          "tree_id": "054c2f0d6a87030b8b47945ccfde25d0931fbff4",
          "url": "https://github.com/kaappi/kaappi/commit/940368ca69d1b97be0e12a274e7409351819c359"
        },
        "date": 1785561811859,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.079073,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.245033,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.456125,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.200223,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004234,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.035077,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.230393,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.042727,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 1.860285,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.90167,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.187181,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.24118,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.353094,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.442884,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.036042,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "abb036b44e4cd61b5447944b5a8852deb69030ae",
          "message": "Phase 2.10: SRFI 254 audit — 178 assertions, and a guardian shared through a global kills the process with no message at all (#2013)\n\n* Audit SRFI 254: 178 assertions for a GC-integrated file with no test\n\nPhase 2.10 of the v2 audit campaign (#1890). primitives_srfi254.zig is the\nonly primitives file with real garbage-collector integration and had no audit\ntest at all, so the surface covered here spans four files: the 16 specs, the\nweak-reference fixpoint in gc_collect.processWeakRefs, guardian invocation in\nvm_calls.invokeGuardian, and the deep-copy refusal arms in gc_deep_copy.zig.\n\nThe ephemeron half is correct, including the parts a weak pair gets wrong: a\ntwo-link chain resolves consistently in both directions, and an ephemeron\nwhose value references its key -- or whose key *is* its value -- still breaks.\nAll 16 error paths carry the right KP code, every call-dispatch site accepts a\nguardian, and all three weak types fail cleanly across both SRFI-18\nboundaries.\n\nThree defects, all filed rather than fixed, per the campaign protocol:\n\n  #2008  invokeGuardian has no owner check, so a guardian shared through a\n         global -- which the thread sharing model shares by pointer -- is\n         mutated across heaps. Concurrent registration aborts the process\n         with empty stdout and stderr, 5 of 5. Channels and thread handles\n         both defend themselves this way; guardians do not.\n  #2006  Transport cell keys are held strongly, against the spec's \"stored in\n         a weakly holding location\". Cells never break and no registration is\n         ever releasable -- observable because it also stops an unrelated\n         object guardian from resurrecting the same object.\n  #2011  A second guardian watching one object never resurrects it: the first\n         guardian's ready queue is marked strongly, so every other guardian's\n         reachability probe sees a live object. Thirty collections do not\n         help; draining the winner unblocks it immediately.\n\nNothing asserts when a collection happens, only what is observable after one\nis forced. The suite is green in ReleaseSafe (0.09s) and under\n-Dgc-stress=true (16s).\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Hold both operands live in two hash/eq? assertions\n\nAn object freed between the two current-hash calls can be replaced at the\nsame address, which would make equal hashes correct rather than a collision;\nand an ephemeron whose key is dropped immediately breaks, so the eq?-identity\nmiss would pass for the wrong reason. Both now bind their keys.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Correct the disabled-assertion count in the tracker (5, not 4)\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-01T10:55:22+05:30",
          "tree_id": "1919aeed2d1ceeb71f353f882442fe8e1dac04a0",
          "url": "https://github.com/kaappi/kaappi/commit/abb036b44e4cd61b5447944b5a8852deb69030ae"
        },
        "date": 1785563852038,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.391479,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.562978,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.588991,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.001321,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00479,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046536,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.313201,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057432,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.605899,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.225157,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.592895,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.284812,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.793924,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.673317,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044553,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "d0d03deb89134671c0b279efb70e254cddd30978",
          "message": "Stop reporting a platform and a range rule as type errors (#2016)\n\nFive typeError sites in primitives_io.zig put a non-type in the \"expected\ntype\" slot: four `comptime is_wasm` gates said \"expected non-WASM platform,\ngot #<string>\", and fd->port rejected 0 with \"expected socket/pipe file\ndescriptor (> 2)\" — but 0 is a fixnum, exactly the type it wants.\n\nFor the three (scheme file) procedures this was not only cosmetic. R7RS 6.13\nsays they signal a condition satisfying file-error?, which is what they do on\nevery native target and what portable code guards on, so the type error fell\nstraight through such a guard on the WASM tier — the playground. They now\nraise through raiseFileError, the same helper their own native failure path\ntwo lines down already used, with the platform named in the message and the\npath still the irritant. fd->port has no spec and no file, so its gate and\nboth range rules are argError (KP3007).\n\nA comptime gate cannot be tested from a native build, so\ntests/wasm/platform-gates.scm covers those four under wasmtime in the `wasm`\nCI job; fd->port's native range rules join #1944's text assertions in the io\naudit. Both sets were mutation-tested against the reverted source.\n\nCloses #1972\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-01T11:13:51+05:30",
          "tree_id": "6fdbf071b1541a34b825ceafa21d0c4d26c072c6",
          "url": "https://github.com/kaappi/kaappi/commit/d0d03deb89134671c0b279efb70e254cddd30978"
        },
        "date": 1785564714098,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.929649,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.282882,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.532599,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.72361,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004821,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.043845,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.274473,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.053547,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.78424,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.087951,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.427751,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.261189,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.628944,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.891383,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.041955,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "50fa0f2da37df7e58297fa03cbe34b809af87b1e",
          "message": "Tick 2.12, reconcile the batch count, and record three footguns (#2017)\n\nFive units landed together (#1985, #2004, #2013, #2014, #2015), taking the\ncampaign to 22 of 53. Each unit ticked its own box; this reconciles the\nstatus line, which four of them raced on, and ticks 2.12, whose PR carried\nonly the test file.\n\nThe three footguns are what 2.12 paid for. It needed three CI rounds and\nnot one of them was a defect in the code under test:\n\n- Name every assertion. SRFI-64 prints a failed assertion's value, not its\n  source, so an unnamed failure on a remote BSD leg is `#f` / `FAIL` with\n  nothing to identify it among 400. The round after names went in, the log\n  read `FAIL (memv (file-info:rdev fi) '(0 -1))` and named the defect.\n- Never assert a value the spec leaves unspecified. POSIX defines st_rdev\n  only for character- and block-special files; two guesses were both wrong,\n  and FreeBSD 14.3 failed for a regular file while passing for a fifo in\n  the same run.\n- A test's side effects must not be platform-scaled either, and\n  `( ulimit -n 256; ... )` is the cheapest BSD-leg simulator available.\n\nThat last one also corrects a finding. 2.12 reported \"3000 unclosed\ndirectory streams do not exhaust the fd table\" as confirmed-correct; it is\na false clean, true only at macOS and Linux CI's ulimit of 1048576. At 256,\n`--gc-stats` reports Collections: 0 and exactly 253 opens succeed. That is\nnow #1993, alongside #1994, and the entry says so rather than repeating the\nclaim.",
          "timestamp": "2026-08-01T11:25:08+05:30",
          "tree_id": "c92205b39fd178636c86390bd008e75d53f8d827",
          "url": "https://github.com/kaappi/kaappi/commit/50fa0f2da37df7e58297fa03cbe34b809af87b1e"
        },
        "date": 1785565417114,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.34943,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.783095,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.57195,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.990335,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004603,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.047032,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.314862,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057081,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.697569,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.214074,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.573769,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.276672,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.790047,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.607832,
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
          "id": "a66a85cc689ed2c29e050bd29be9cc5b7af6cc29",
          "message": "Document the issue-tracker label taxonomy and priority rubric (#2032)\n\nThe four priority labels carry one-line GitHub descriptions that are too\ncoarse to settle real triage, so the working rubric existed only as\nprecedent spread across ~1000 issues. Labeling a new issue meant reading\nits neighbours and inferring the rule, which is fine for a maintainer who\nfiled those neighbours and useless to everyone else.\n\nRecords the rule adopted today — `critical` is reserved for process-level\nunsafety, and a correctness bug tops out at `high` however broad or silent\nit is. This is not invented: 11 of the 12 issues ever labeled critical are\nmemory unsafety or a process abort, and the twelfth (#1250) is called out\nas a pre-rule exception so nobody calibrates against it.\n\nAlso captures the two distinctions the precedent encodes but never states:\nreachability separates critical from high (#1939 aborts from five lines and\nis critical; #2000 is the same abort class but needs ~2500 fibers and is\nhigh), and an audit header's severity is an input to the priority decision\nrather than the answer, since `wrong-result` spans high to medium purely on\nblast radius.\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-01T11:54:29+05:30",
          "tree_id": "54919109d67526e4135bcb2734600c417ae43580",
          "url": "https://github.com/kaappi/kaappi/commit/a66a85cc689ed2c29e050bd29be9cc5b7af6cc29"
        },
        "date": 1785569450453,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.44251,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.332419,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.489069,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.408022,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004834,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.041235,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.256969,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.047529,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.390818,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.038192,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.368223,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.276819,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.486866,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.913231,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.039169,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "08828884cdbbc3529a373c39f3b5b3405f6bc46a",
          "message": "Phase 2.13: error taxonomy and diagnostic fidelity — 98 assertions, and the bare-return path CI forbids produces a better message than the one it enforces (#2029)\n\n* Phase 2.13: audit the error taxonomy and diagnostic fidelity\n\nCross-cutting sweep over all 31 primitives_*.zig files plus src/ffi.zig,\nagainst the codebase's own written contract: docs/dev/adding-features.md's\ntypeError/indexError/argError table and the explanation text that\n`kaappi explain` prints for KP3002/KP3006/KP3007.\n\n98 assertions on the code and the message content, never on `raises?` alone\n-- that is the documented lesson from #1944 and the central hazard of this\nunit. 64 further assertions are disabled behind `;; FAIL:` markers; each was\nverified to fail when enabled and to pass nowhere else.\n\nFour issues filed:\n\n  #2020  33 bounds failures report KP3002 instead of KP3006. The largest\n         contributor is parseOptionalRange, shared by 20 procedures.\n         `substring` and `string-copy` are the same operation by R7RS\n         definition and return different codes.\n  #2021  72 sites reject a correctly-typed value as KP3002 rather than\n         KP3007, because the type branch and the range branch of one check\n         share a single message string.\n  #2022  31 procedures misreport which procedure failed: shared helpers\n         hardcode 'string' (a real, working procedure), 'arithmetic', and\n         'string operation'.\n  #2026  CI's bare-TypeError gate misses src/ffi.zig on both axes at once --\n         wrong path glob and wrong spelling -- so 27 bare returns there have\n         never been reported.\n\n#1899 (F10) was extended rather than re-filed. Its stated rationale for the\nopacity does not hold: mapNativeError runs the full allocating printer on the\nsame error path, so `(sqrt 'the-key)` names the symbol while\n`(magnitude 'the-key)` reports `#<symbol>`. The suite pins that pair.\n\n13 of 31 primitives files are clean on both taxonomy axes and are asserted as\nsuch, along with the codes that are already granular -- KP3001/3003/3004/3005\neach stay distinct from KP3002.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Tick 2.13, and record what the taxonomy sweep found\n\nCites PR #2029 and the four issues it filed. Deliberately does not touch the\nStatus count line -- the orchestrator reconciles that.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-01T13:07:42+05:30",
          "tree_id": "b684d75f680ac976f646d387f1e7fdeffe92a84a",
          "url": "https://github.com/kaappi/kaappi/commit/08828884cdbbc3529a373c39f3b5b3405f6bc46a"
        },
        "date": 1785576573261,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 2.961075,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.346625,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.424688,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.103577,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004223,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.03522,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.226383,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.040699,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.079597,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.916972,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.189519,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.225746,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.287636,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.734572,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.034903,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "400aef3c3f3279786347d4c438d4d7f6e2a8ea20",
          "message": "Correct #1250's label and drop the critical-corpus exception (#2041)\n\n#2032 merged five minutes before this content reached the remote, so it\nshipped the first commit only. Everything below was written against that\nbranch and is landing now; main currently says #1250 is the critical\ncorpus's standing exception while the tracker has it labeled high, which is\nthe kind of contradiction this document exists to prevent.\n\n#1250 was the one issue labeled `priority: critical` that the rule did not\ndescribe: a macro-introduced `set!` escaping assignment conversion, which is\na pure correctness bug with no memory unsafety. Both of its reproductions\nhang, and a hang is `high` here — #1954, where four output procedures hang\nforever on a cycle, is the direct precedent. Relabeled, so all 13 issues\never marked critical are now memory unsafety or a process abort and the rule\nis fully descriptive. The doc keeps the correction rather than quietly\ndropping the issue: a lone counter-example in the corpus is exactly what a\nfuture maintainer would calibrate against.\n\nThree other fixes the same pass turned up. The critical table was already\nstale — #2027 and #2024 were labeled after it was written — so it now lists\nall 13. The claim that doc-truth is \"reliably low, because by construction\nthe behaviour is correct\" has a live counter-example in #2038, where the\nundocumented caveat hides a loop running 2^n-1 times that past n≈20 prints\nnothing and exits 0; the premise is now something the reader is told to\ncheck rather than assume. And the invariant gains its one real exemption:\nauto-filed `fuzz-finding` CI reports are triage-and-close, and all six ever\nfiled were handled with no priority label, so the triage query skips them\nrather than reporting a gap that nobody intends to close.\n\nAlso replaces the total-issue count with a claim that does not rot, since\nthe audit campaign files in bursts and the number moved twice while the\noriginal branch was open.\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-01T13:12:12+05:30",
          "tree_id": "af1ea9de7f4b5fcd5f4fd58d53a07d2205d89747",
          "url": "https://github.com/kaappi/kaappi/commit/400aef3c3f3279786347d4c438d4d7f6e2a8ea20"
        },
        "date": 1785581006832,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.384146,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.819936,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.570632,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.992623,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004642,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046578,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.315147,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.056952,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.702792,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.213817,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.612615,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.277039,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.786578,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.605108,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044318,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "1718a2e148b9fc9c9f1eafdf4d0e1ad7392d88fc",
          "message": "Put the reason a fuzz job died into the issue it files (#2042)\n\nThe \"infrastructure or build failure\" issue could say no more than \"see the\nrun log\", so every instance costs a manual `gh api .../logs` to explain. That\nis worst for the failures it is most often filed for: a GitHub-hosted runner\nreclaimed mid-job *cancels* the job, which skips even the `if: failure()`\nupload step, so no artifact reaches the report job and the run log is the only\nsurviving evidence.\n\nThe report job already holds `actions: read`. Have it fetch each failed job's\nlog over the API and lead the issue with a per-job verdict — duration plus the\nlast few `##[error]` lines — recognizing the runner-shutdown line specifically.\nThat is the distinction the old text could not draw: a shutdown (exit 143) is\ninfrastructure and wants a re-run, whereas a job cancelled at its own\n`timeout-minutes` is worth chasing as a hang, since every generated program is\nindividually time-bounded.\n\n#2040 was the first kind wearing the second's clothes — an arm64 leg killed 46\nmin into a 55-min budget, on a commit whose x86_64 leg was entirely normal.\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-01T08:06:10Z",
          "tree_id": "f8189011b69be162fedf37b3df55db8c9fa5825a",
          "url": "https://github.com/kaappi/kaappi/commit/1718a2e148b9fc9c9f1eafdf4d0e1ad7392d88fc"
        },
        "date": 1785589571359,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.033689,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.357974,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.569017,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.947608,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004975,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.045086,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.295084,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.05506,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.306315,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.178694,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.533594,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.308367,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.685778,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.864144,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.04535,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "fad68505ef5ff7553608a2c119340300f3542d93",
          "message": "Phase 2.9: control-flow audit — 171 assertions, and a wrong-arity exception handler runs anyway with a leftover register as its third argument (#2039)\n\n* Phase 2.9: control-flow audit — 35 → 171 assertions\n\nprimitives_control.zig had 35 unnamed assertions from the v1 campaign and\nnothing at all for the mechanism that postdates it: SRFI 248's sticky\nexception handlers. This restates the old assertions with names and adds\nthe dimensions v1 did not have — the sticky-handler interactions with\ndynamic-wind, nested guard and resume; D1 (internal-primitive\nreachability); D2 (KP codes); D5 (which native callback sites can park a\nfiber).\n\nThe oracles are documents, as the campaign prefers: R7RS §4.2.7's two\nguard examples, §6.11's two worked examples, and all three of §6.10's\ndynamic-wind ordering rules are now pinned verbatim, with the two\nre-entry rules cross-checked against chibi-scheme.\n\nSix issues filed, none fixed here:\n\n  #2034  callHandler/callThunk skip the arity check, so a wrong-arity\n         exception handler, with-exception-handler thunk, call-with-values\n         producer or call/cc/call/ec receiver runs anyway, with surplus\n         parameters bound to leftover register contents\n  #2033  a top-level redefinition of call/cc, apply, eval or\n         call-with-values is ignored in tail position only\n  #2035  819 nested dynamic-wind extents abort with KP9001 \"internal\n         error\", and the failure is catchable\n  #2036  three diverging diagnostic paths in the control primitives\n  #2037  %unwind-to-escape is missing from internal_helpers\n  #2038  doc-truth: README and CONFORMANCE claim SRFI 248 has exactly\n         two caveats\n\n15 assertions are disabled with ;; FAIL: markers naming those issues, each\nsitting next to the enabled control that discriminates it — the\ndynamic-wind arity checks beside #2034, non-tail call/cc beside #2036,\nlocal shadowing beside #2033.\n\nGreen in ReleaseSafe, Debug, and -Dgc-stress=true.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Tick 2.9 in the audit tracker\n\nCites PR #2039 and the six issues it filed. The Status count line is\nleft to the orchestrator.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-01T14:18:33+05:30",
          "tree_id": "ecd40955e73b780518d2175ea8855fc0bd670e5f",
          "url": "https://github.com/kaappi/kaappi/commit/fad68505ef5ff7553608a2c119340300f3542d93"
        },
        "date": 1785591666234,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.355716,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.594232,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.606951,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.997794,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004737,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.04833,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.315134,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057245,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.702092,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.216488,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.582252,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.287607,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.815795,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.544461,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045507,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "dfd8dff73d8749689a4918d4ab29549a20afbfeb",
          "message": "Phase 3.8: ten smoke-only SRFIs — 261 assertions, and two closed issues whose regression tests pinned the valid case (#2078)\n\n* Phase 3.8: ten smoke-only SRFIs — 67 → 261 assertions\n\nAudit v2 unit 3.8. Ten SRFIs whose test files existed but held ≤12\nassertions each: 23, 46, 98, 112, 139, 149, 188, 190, 236, 244. A smoke\ntest proves the library loads; it does not test the library.\n\nFour of the ten are genuinely thin by nature — 23 is one procedure whose\nspec explicitly declines to prescribe behaviour, 46/149 are bare\n(export syntax-rules) conformance statements, 244 re-exports a core\nspecial form — so the work went into the mechanism each one *claims*\nrather than the wrapper.\n\nTwo closed issues reproduce verbatim and were reopened:\n\n  #682  A pattern variable used at a LOWER ellipsis depth than it was\n        matched silently expands to (). The fix (PR #730) added a\n        `b.depth != 1` check to instantiateEllipsis; #931 removed it —\n        correctly, since it blocked legitimate nested reduction — and\n        nothing replaced it. The regression test the issue shipped only\n        ever exercised the VALID case, so it printed PASS throughout.\n        The depth-0 half, which #730 never touched, still carries the\n        comment admitting it.\n\n  #550  Top-level define-values ignores an arity mismatch. The fix\n        (153cefd8) added its checks inside the MultipleValues arm only;\n        the single-value arm has none, so three of the issue's four\n        reproductions still exit 0 with a prefix of the formals bound.\n\nOne new issue:\n\n  #2075 A begin-wrapped internal define in a let body escapes to the\n        global environment when no enclosing procedure exists. R7RS\n        4.2.3 requires the begin to be transparent; the unwrapped form\n        is correct everywhere, and the same text inside any lambda is\n        correct — so `(define g 'global)` followed by\n        `(let ((g 'outer)) (begin (define g 'inner)) g)` answers `outer`\n        and leaves the global reading `inner`. Found while checking the\n        claim lib/srfi/188.sld's header rests on, which turns out to be\n        true only at top level.\n\nSRFI 190 inherits #2060 exactly (make-coroutine-generator is call/cc\nbased, so a resume cannot cross a returned SRFI 1 native frame); cited\nrather than re-filed, with the (scheme base) map/for-each controls\npinned enabled beside it.\n\n11 assertions are disabled behind ;; FAIL: markers and every one was\nmutation-tested — each fails today, so a fix flips it. The\nbegin-splicing probes in srfi188.scm are evaluated at true top level and\nstashed in variables, because SRFI-64's own test-equal wrapper supplies\nthe enclosing procedure scope whose absence is the defect and answers\n`inner` from inside the assertion.\n\nClean on the rest: SRFI 139's adjustment reaches a macro defined before\nthe parameterize and is restored across a macro boundary; SRFI 149's\nsemantics rule 4 over a compound template element matches Guile (chibi\n0.12 does not); SRFI 46's custom ellipsis, tail patterns and their\ncombination are correct in all 24 probed shapes; SRFI 98's alist is\nfreshly allocated per call so a caller cannot corrupt the environment;\nSRFI 112 answers string-or-#f for all six with correct arity; SRFI 236\nevaluates every expression exactly once with no template capture.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Note in srfi244.scm that fixing #550 aborts the file at load\n\nThe three top-level probes pinning #550's silent cases are definitions,\nnot assertions, so a fix makes them raise while the file is loading. Say\nso where the fixer will read it.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Pin the two-ellipses-in-one-pattern split (#2082)\n\nR7RS 4.3.2's pattern grammar admits at most one ellipsis per list or\nvector pattern; SRFI 46's tail patterns widen what may follow it, not\nhow many there may be. This expander accepts two and gives the trailing\npattern the last two elements regardless of input length, while a short\ncall fails outright. chibi 0.12 and Guile 3.0 both reject the\ndefine-syntax.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-01T14:34:24+05:30",
          "tree_id": "d4d8c6c053f982707aff31235b7b05102f78b63c",
          "url": "https://github.com/kaappi/kaappi/commit/dfd8dff73d8749689a4918d4ab29549a20afbfeb"
        },
        "date": 1785593450497,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.349359,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.000877,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.608617,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.987852,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004748,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046844,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.315527,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057966,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.740627,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.215363,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.612104,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.291752,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.80216,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.736928,
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
          "id": "ae45e7871208e8399ebdf40600c290e7bec19a06",
          "message": "Require a priority label on every issue (#2090)\n\n* Require a priority label on every issue\n\nThe rubric landed in docs/dev/github-issues.md (#2032, #2041), but nothing\ntold a filer to apply it. The evidence that a document alone is not enough:\n41 issues were filed unlabeled while those two PRs were open, in bursts of\n6-27 as each audit phase completed. Triage after the fact means re-reading\nevery issue body to recover a judgement the filer had already made.\n\nPuts the decision table where it is needed at filing time, plus the four\nrules that settle the hard cases — critical is process-level unsafety only,\nreachability separates critical from high, an audit header's Severity is an\ninput rather than the answer, and silence moves an issue up within its level\nrather than between levels. The full rubric, worked boundary cases, and the\nlabel taxonomy stay in docs/dev/github-issues.md; this is the filing-time\nsubset.\n\nAdvisory only, like the neighbouring test and file-size rules: a CI gate\nwould have to run against the tracker rather than the diff, and the failure\nmode here is a missing label rather than broken code.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Make the priority-label audit catch double labels too\n\nReview of #2090: the prose requires exactly one `priority:` label, but the\ncommand only reported issues with zero. An issue carrying two was invisible\nto the very check meant to enforce the rule. Counts the labels and reports\nanything that is not 1, keeping the fuzz-finding exemption.\n\nFixed in docs/dev/github-issues.md as well as CLAUDE.md — the snippet was\ncopied from there, so the same blind spot shipped in #2032.\n\nNo issue in the tracker has ever carried two, so this finds nothing today;\nthat is the point. A check that cannot observe half of what it asserts would\nhave gone on reporting a clean tracker either way.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-01T15:03:55+05:30",
          "tree_id": "7e3074d63cf4ab1467be4765740eec1cddabb01f",
          "url": "https://github.com/kaappi/kaappi/commit/ae45e7871208e8399ebdf40600c290e7bec19a06"
        },
        "date": 1785594471481,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 2.548942,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.903786,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.362164,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 1.935329,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.003779,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.030209,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.192009,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.03609,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 1.768757,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.772884,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.016314,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.219299,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.132917,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.897927,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.030387,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "80553427120c666d034fcfa11af4268ae09f7552",
          "message": "Phase 3.4: SRFI 146 audit — 668 assertions over all 161 exports, and (srfi 146 hash) never uses the comparator it is given (#2070)\n\n* Phase 3.4: SRFI 146 audit — 668 assertions over all 161 exports\n\nSRFI 146's two libraries exported 161 names and its one manual-counter test\nfile touched 53 of them. Two new SRFI-64 files close that gap completely.\n\ntests/scheme/srfi/srfi146-reference.scm ports the SRFI's own reference suite\n(srfi/146/test.sld and srfi/146/hash/test.sld, MIT, Marc Nieper-Wisskirchen)\nverbatim apart from the library wrapper — 167 assertions, 7 disabled.\n\ntests/scheme/srfi/srfi146-differential.scm runs one parameterised body over\nboth libraries through an operation table, so the 66 names they share are\nchecked for agreement rather than against a hand-written expectation — 501\nassertions, 26 disabled. Nothing asserts hashmap iteration order.\n\nThe differential is what found most of it. (srfi 146 hash) discards its\ncomparator argument outright and keys every hashmap by equal?, so a\ncomparator whose equality is `=` merges 1 and 1.0 in the ordered library and\nsplits them in the hash one. Both constructors also give the LAST duplicate\nkey precedence where the spec says the first — the one distinction the spec\ngoes out of its way to contrast with mapping-set, and mapping-adjoin and\nalist->mapping are both correct, which is what makes it a defect rather than\na convention.\n\nFiled #2044 (comparator discarded), #2045 (duplicate-key precedence), #2046\n(mapping-key-predecessor/-successor invoke failure unconditionally), #2047\n(=? omits the key-comparator identity check), #2048 (make-mapping-comparator\nsupplies no ordering and make-hashmap-comparator no hash), #2049\n(hashmap-ref/default calls a procedural default), #2050 (any?/every? return\nthe predicate's value), #2052 (the single-mapping comparison form), #2053\n(mapping-map and mapping-find run their fold twice). Commented on #2023 with\nthe wider blast radius through this SRFI's own API.\n\nClean and now pinned rather than assumed: all four mapping-search\ncontinuations on both libraries, escaping continuations out of every\nhigher-order entry point, the purity of all eight pure/linear pairs, the\nwhole ordered surface (min/max, predecessor/successor, the five ranges,\nsplit, catenate, map/monotone, fold/reverse), set algebra on disjoint,\nidentical and overlapping inputs, mixed-type default-comparator keys, and\n1000 inserts plus 1500 interleaved insert/delete rounds against a red-black\ndelete that never rebalances.\n\nFound by: Systematic audit v2, Phase 3.4 (tracking #1890)\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Pin the #2023 cliff, not a miss count — the Debug leg found the keys\n\n`(> (hash-misses 12 40) 0)` asserted that the bug is still present. It\npassed on macOS ReleaseSafe and failed on CI's `ubuntu-latest, Debug` leg,\nreproduced locally in a Debug build.\n\nPast the depth limit the hash degenerates to the key's pointer, so whether\ntwo structurally-equal keys collide is an accident of allocation. Measured\non one ReleaseSafe binary: 31 and 32 misses of 40 at `deep 8` across two\nruns, then 3 vs 40 of 40 at `deep 9`. Debug finds far more. No miss count\nis assertable past the limit, in either direction.\n\nWhat is stable in every run and both builds is the cliff itself, so that is\nwhat this pins now: 0/40 misses at every depth from 1 to 7.\n\nNote `deep` builds a FLAT list of length depth+1, not a nested structure,\nand the hash walks the spine — so the limit is reached at `deep 8`\n(length 9), and `deep 7` (length 8) is the last fully findable case. The\nfirst attempt at this fix used `deep 8` and failed for that reason.\n\nVerified: Debug 501/501, and 0 misses at depths 1-7 across runs in both\nbuild modes.\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-01T15:09:16+05:30",
          "tree_id": "a9dbc360b8ceac0347872608c15025ebb4e5a8c8",
          "url": "https://github.com/kaappi/kaappi/commit/80553427120c666d034fcfa11af4268ae09f7552"
        },
        "date": 1785595426327,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.910995,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.799274,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.568073,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.804383,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004907,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.044907,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.291523,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.05549,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.295892,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.15296,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.512446,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.306443,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.677539,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.802883,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045463,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "c83f07a6bb79eeb1be27380bb87f460674f10af9",
          "message": "Phase 3.6: SRFI 158 audit — 349 assertions over all 55 exports (#2068)\n\n43 of SRFI 158's 55 exported names appeared in no test. The reconnaissance\npass had spot-probed 18 of them and found nothing, so this unit was scoped as\nclosing a measurement gap rather than a bug hunt, with effort ranked toward\nthe three places a generator library actually breaks. Two of those three came\nback clean and are now pinned rather than assumed:\n\n  * Laziness — every combinator's construction is instrumented with a\n    call-counting source and asserted to consume zero. gmerge is the one\n    exception (it primes both inputs at construction); that is the reference\n    implementation's design, chibi agrees, and the spec constrains only merge\n    order, so it is pinned as documented behaviour.\n  * Exhaustion — all 12 constructors and all 18 combinators are drained and\n    then called three more times. Every one keeps returning eof.\n  * Infinite sources — 37 compositions of an endless generator with a bounded\n    consumer, all under run_timeout during development. No hangs.\n\nThe bugs were elsewhere, and each has its own root cause:\n\n  #2055  make-range-generator does not begin the sequence with an inexact\n         start. The (- (+ start step) step) round trip that carries exactness\n         contagion also perturbs a start that is already inexact — and when\n         step is much larger, annihilates it: (make-range-generator 1e-20 1.0\n         1.0) begins at 0.0. make-iota-generator, with identical \"begins with\n         start\" wording, is correct at every one of those inputs, and so is\n         make-range-generator's own one-argument form.\n\n  #2057  gflatten raises on an empty list from its source. Its refill runs\n         once instead of looping, so (car '()) escapes. A filtering gmap that\n         yields '() for rejected elements is the natural way to hit it.\n\n  #2060  SRFI 158's own generator-unfold example does not run. SRFI 1's\n         higher-order procedures, hash-table-walk, and assoc/member with a\n         predicate are still native drivers, and four SRFI 158 constructors —\n         including gtake — are coroutine-backed, so a resume crosses a\n         returned native frame. make-for-each-generator's stated job of\n         converting \"any collection\" fails for a hash table, and fails on the\n         *second* call, not the first. #1347 closed this for the map family;\n         SRFI 1 was never in its scope. CONFORMANCE.md cites a README section\n         for the restriction that does not state it.\n\n13 assertions are disabled against those three; the mutation test enables them\nand exactly those 13 fail. Nine controls are enabled beside them, so a fix\nflips both sets.\n\nTwo portability traps worth carrying: never write (list (g) (g)) — chibi\nevaluates arguments right to left, so the same generator yields the reverse\nsequence and the file only looks correct on one implementation — and an\naccumulator's return value for a non-eof argument is explicitly unspecified,\nso only its eof value is asserted anywhere here.\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-01T15:12:04+05:30",
          "tree_id": "071726d345164485a54197d7e6b0d6be92b274f9",
          "url": "https://github.com/kaappi/kaappi/commit/c83f07a6bb79eeb1be27380bb87f460674f10af9"
        },
        "date": 1785598662413,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.924445,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.522821,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.556833,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.80722,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004842,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.04511,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.291488,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.054834,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.294553,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.151848,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.535459,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.303796,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.677471,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.770293,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044913,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "22a8930f764e725c9df4e156a3ea15abaa55efa1",
          "message": "Stop pinning an exact atime in the filesystem audit (#2077) (#2091)\n\nThree assertions in tests/scheme/audit/primitives_filesystem-audit.scm\npinned an exact access time. Nothing can hold st_atime still: any read by\nany process — an indexer, a backup agent, an AV scanner, the periodic /tmp\ncleaner — moves it to \"now\". It flaked in ~2 of 9 parallel corpus runs,\nreporting the current epoch second where the set value belonged.\n\nReproduced deterministically rather than by re-running until it broke:\n\n    set-file-times p 1000000 2000000\n    before reader: atime=1000000     mtime=2000000\n    (call-with-input-file p read-char)      ; one read, what a scanner does\n    after  reader: atime=1785575578  mtime=2000000\n\n    OLD  (= atime 1000000)  => #f     ← the flake\n    NEW  (>= atime 1000000) => #t\n    mtime still exact       => #t\n\nmtime now carries the discrimination. No reader changes it, and it alone\nseparates all three cases (set / both sentinels / atime sentinel with a\nreal mtime). atime is asserted as \"not earlier than what we set\" — the\nstrongest true statement available, since an intervening reader can move it\nforward but never backward.\n\nEach case also takes one file-info and reads both fields from it, instead\nof stat'ing twice for the two halves of one assertion.\n\nThis is the same class as #1993 from the same unit: an assertion that held\nonly because the machine happened to be quiet. 427 -> 430 assertions (three\ncombined assertions became six).",
          "timestamp": "2026-08-01T17:12:51+05:30",
          "tree_id": "f4264a049bcf568fd20a98c74f06c34f6ab4217f",
          "url": "https://github.com/kaappi/kaappi/commit/22a8930f764e725c9df4e156a3ea15abaa55efa1"
        },
        "date": 1785599671803,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.921249,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.784503,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.559102,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.807649,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004861,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.044745,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.292137,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.055107,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.288358,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.155191,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.508512,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.306209,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.668407,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.800001,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044915,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "fc66b3c47104e4272ff2209622f0765d38533304",
          "message": "Phase 3.5: SRFI 166 audit — 244 assertions across all 89 exports, and pretty never breaks a line at any width (#2069)\n\n* Phase 3.5: SRFI 166 audit — 245 assertions across all 89 exports\n\nThe unit was scoped as closing a measurement gap: 52 of 89 exported names\nnever appeared in a test file. The gap turned out to be hiding a library\nthat is largely a skeleton, so the suite is written against the SRFI's own\nspec page rather than against the implementation, and every expected value\nis either quoted verbatim from one of the spec's \"=>\" examples or derived\nfrom a sentence of its prose cited in a comment.\n\n188 assertions pass; 57 are committed disabled with a `;; FAIL: #NNNN`\nmarker naming the issue. Uncommenting the disabled set makes exactly those\n57 fail and leaves all 188 passing, in both ReleaseSafe and\n-Dgc-stress=true.\n\nEleven issues, one per root cause:\n\n  #2054  fn and with are procedures where the spec defines macros, so every\n         documented use of the state-variable API raises \"not a procedure\";\n         fn additionally binds nothing, computing its bindings and\n         discarding them, and the `output` state variable has no slot\n  #2056  with restores the whole 13-slot state vector, so col and row are\n         rolled back and output written inside a with is invisible to the\n         space-to / tab-to / fl that follow it\n  #2058  tab-to emits a full tab width when already on a tab stop, which\n         the spec calls out explicitly; tab-width 0 divides by zero\n  #2059  escaped wraps its output in quote delimiters the spec does not add\n         and ignores esc-ch/renamer; maybe-escaped never quotes on an\n         embedded quote character\n  #2061  the numeric family reads only num/radix/precision: sign-rule,\n         comma-rule, comma-sep and decimal-sep are ignored, radix is\n         dropped as soon as precision is given, numeric/comma inserts no\n         commas at all, and numeric/si ignores its base and separator\n  #2062  padded/trimmed/fitted measure with string-length, so the ellipsis\n         and string-width state variables are never read\n  #2063  displayed renders a formatter argument as #<procedure>\n  #2064  pretty is write — it never breaks a line at any width — and\n         written-shared/pretty-shared do not label shared structure\n  #2065  columnar and tabular do not align, wrapped hardcodes width 78,\n         wrapped/char and justified are aliases of wrapped, line-numbers\n         is not a stream; the SRFI's own nl(1) example produces garbage\n  #2066  (srfi 166 unicode) is a stub: substring-terminal-width returns an\n         integer where the spec returns a substring, string-terminal-width\n         is string-length, terminal-aware is a no-op\n  #2067  15 documented names are not exported and (srfi 166 base) does not\n         exist, while (cond-expand (srfi-166 ...)) answers yes\n\nCorrect and asserted as such: all 23 (srfi 166 color) exports, including\nthe exact SGR codes for the 16 foreground/background colours, the three\nstyles, and both the 8-bit cube and 24-bit true-colour forms; the whole\njoined family; every non-ellipsis trimming case including the odd/even\nasymmetry; fitted in all three directions; forked, call-with-output,\nfrom-file, upcased and downcased (with the spec's Greek word-final sigma);\ncycle detection in written and pretty; and pretty's read-back round trip.\n\nTwo portability notes the file documents inline. Non-ASCII text is written\nwith \\x...; escapes so the assertions are byte-stable on every CI leg, and\nno assertion consults the ambient terminal width. Also worth knowing:\n#\\x1b; is not a hex character escape — R7RS spells the in-string form\n\"\\x1b;\" with a terminating semicolon and the character literal #\\x1b\nwithout one, so #\\x1b; reads as ESC followed by a comment that swallows\nthe rest of the line. The suite uses (integer->char 27).\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Drop the one disabled assertion that would not flip on its own fix\n\n\"fn: a binding is visible to the body under the procedural form\" asserted\na value this implementation's calling convention never defined — there is\nno way to *name* an fn binding under the procedural form, so the assertion\nfailed only incidentally, and #2054's fix (making fn a macro) would have\nrequired deleting it rather than re-enabling it. A `;; FAIL:` marker\npromises the opposite.\n\nThe three remaining #2054 assertions cover the same defect in the spec's\nown terms, where the fix does flip them. 244 assertions: 188 enabled,\n56 disabled; the mutation test is still exact.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-01T17:18:11+05:30",
          "tree_id": "427e7d1dcb2fd66e6809fdc0409f646f651e5dac",
          "url": "https://github.com/kaappi/kaappi/commit/fc66b3c47104e4272ff2209622f0765d38533304"
        },
        "date": 1785601100379,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.917303,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.035669,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.573342,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.816125,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00484,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.044874,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.292346,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.05462,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.295172,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.151661,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.613907,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.307154,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.676451,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.762969,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044827,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "6b5c4e21be3a1f4aba2816a19ef925b2db2b02f6",
          "message": "Phase 2.8: hash-table audit — 201 assertions, and equal? tables lose any key deeper than 8 (#2031)\n\nThe 268-line audit test asked its hash/equality-consistency questions only\nat depth <= 2, so a green suite never noticed that `valueHashDepth` stops\nrecursing at MAX_HASH_DEPTH = 8 and returns the *pointer* of whatever sits\nat the cutoff. A nine-cons-cell key is enough: 200 of 200 freshly-built\ntwelve-element keys are unfindable, while the eight-element control misses\nnone. Closed #1180 named this exact residue in its own suggested fix and\nshipped only the bignum/rational half.\n\nTwo more, both new: a custom hash procedure that inserts into its own table\nmakes `rehash` keep iterating an entry array the nested rehash already\nfreed, aborting the process with empty stdout *and* stderr; and all four\nhash procedures mask to 62 bits and then hand the result to a 48-bit\n`makeFixnum`, so about half of them come back negative.\n\nEvery assertion now carries a name string, and the file states two standing\nportability rules for itself: never assert a hash value derived from a\npointer or from `usize`, and never assert iteration order.\n\nAll 8 callback sites were probed under mutation, raise, re-entry and\nblocking. Only the custom-hash site is unsafe. walk and fold are correct on\nevery route tried, and the path needs no blocking guard — a channel call\n6000 native frames deep inside a walk callback works, where the custom-port\npath aborts at 3000.\n\nIssues: #2023, #2024, #2025. D2 taxonomy for this file is already #2021.\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-01T18:05:41+05:30",
          "tree_id": "aae5667abea94253644f4bc9d78b6cbffeee55c0",
          "url": "https://github.com/kaappi/kaappi/commit/6b5c4e21be3a1f4aba2816a19ef925b2db2b02f6"
        },
        "date": 1785601121553,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.038887,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 5.67648,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.441208,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.175095,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004384,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.03764,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.227322,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.043156,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.132385,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.931104,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.210737,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.231549,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.319837,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.733514,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.035748,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "5ca8f28d00d7d1f84d0d5bfa0f7ee8323a126821",
          "message": "Phase 3.9: eight large-and-thin SRFIs — 1579 assertions, and bitvector-logical-shift shifts the wrong way (#2095)\n\nEight SRFIs with substantial export surfaces and thin tests: 113, 225, 178,\n152, 240, 189, 35, 27. Coverage of exported names goes from 288/456 to\n441/456; assertions from 495 to 2074.\n\nThe unit was scoped as a measurement gap, and the strategy doc is explicit\nthat a high untested-export count is not itself evidence of bugs. It found\nsix anyway, because two of these SRFIs had a real oracle available:\n\n  * SRFI 178's own reference implementation loads into this build as an\n    alternate library. Diffing all 107 exports against it over a\n    523,361-check corpus left exactly three divergences — one real bug\n    (#2083), one shrinking-`pad` case the spec leaves ambiguous (not filed,\n    documented in the suite header), and nothing else. That is a much\n    stronger statement than any hand-written suite could make.\n  * SRFI 113 has both a reference implementation and chibi-scheme. Where the\n    three disagree the suite says which is right and why: three chibi\n    defects are asserted in Kaappi's favour, and two Kaappi defects are\n    disabled with the reference's own code quoted.\n\nFindings, all reproduced on a fresh ReleaseSafe build with a discriminating\ncontrol:\n\n  #2083  bitvector-logical-shift moves bits toward higher indices for\n         count>=0 and lower for count<0 — inverted on both branches, and it\n         fails the two assertions in SRFI 178's own test/quasi-ints.scm.\n         count=0 is correct, which is the control.\n  #2084  bitvector-segment conses outside its recursive call, so a legal\n         200,000-bit vector with n=1 dies of an *uncatchable* KP3008, and\n         n=0 recurses without bound instead of raising. 1,000 segments is\n         the control. The reference validates n and delegates to a map.\n  #2085  bag-increment! ignores the spec's \"but not less than zero\", and the\n         resulting negative multiplicity makes bag->list, bag-fold and\n         bag-for-each loop forever on `(= i count)`. bag-product with a\n         negative n is a second route. Zero and positive counts terminate.\n  #2086  set->bag! leaves an element already in the bag at its old count;\n         the reference and chibi both increment.\n  #2087  SRFI 189 exports 24 names of the spec's 82, four of the present\n         ones have narrower signatures than the spec, `either` is exported\n         but never defined — and cond-expand answers yes to both srfi-189\n         and (library (srfi 189)). The three monad laws and both functor\n         laws are asserted as properties over five payloads and all hold.\n  #2088  An R7RS define-record-type produces an rtd whose own_field_names is\n         empty, so record-type-field-names returns #() for a record that has\n         fields and record-accessor/mutator/field-mutable? are unusable —\n         the exact interoperability SRFI 240 exists to provide. The R6RS\n         clause syntax and make-record-type-descriptor are the controls.\n\nClean results worth recording, since they are what the measurement was for:\n\n  * SRFI 225's generic layer agrees across all three DTOs on 49 of 51\n    operation groups; the two that differ do so correctly (dict-ref with no\n    failure raises everywhere, dict-pure? is what tells the two apart). All\n    35 proc-id tags are exercised through dto-ref for the first time.\n  * SRFI 152 cannot diverge from SRFI 13 at all: the .sld imports those 22\n    names straight from (srfi 13), so they are the same binding. Asserted by\n    identity, which doubles as a gate if anyone reimplements one. Gone\n    deliberately shallow otherwise — #1234 already audited 152 in v1 and its\n    20 remaining untested exports are (scheme base) re-exports.\n  * SRFI 27 is correct on every axis a random source can be pinned on:\n    range and exclusivity of both bounds, exactness, bignum bounds,\n    pseudo-randomize reproducibility and independence, and state\n    capture/restore including mid-sequence and across sources. Stable over\n    three consecutive runs.\n  * SRFI 35's condition world and R7RS's error-object world are disjoint and\n    self-consistent in both directions. Not a defect, but nothing pinned it.\n\nAll 32 disabled assertions were mutation-tested by enabling each one alone in\nits own copy of the file: 30 fail, one errors, one hangs. None pins nothing.\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-01T18:19:40+05:30",
          "tree_id": "5438004f1124f0c6e8d88aa97e30e358117ab012",
          "url": "https://github.com/kaappi/kaappi/commit/5ca8f28d00d7d1f84d0d5bfa0f7ee8323a126821"
        },
        "date": 1785601219515,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.348726,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.669102,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.612807,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.029662,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004787,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046996,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.315838,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057256,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.706146,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.216685,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.590027,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.28993,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.807711,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.636382,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.04595,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "70675ffae061552ebbb9a2373e45dae431353560",
          "message": "Phase 6B: reconcile kaappi test with run-all.sh — a suppressed (exit 0) still meant exit 0 (#2081)\n\n* Phase 6B: reconcile kaappi test with run-all.sh — a suppressed (exit) still has semantics\n\nThe two runners disagreed on tests/scheme/srfi/srfi150.scm: green under\nrun-all.sh, `1 errored` and exit 1 under `kaappi test`, with a summary that\nread as self-contradictory (`0 failed` tests above `1 failed` files). Every\nunit of the audit campaign has been reporting it as noise, and it is what\nblocks `kaappi test` from replacing the legacy runner.\n\nThe cause is not `test-expect-fail`, where the finding pointed — those\nannotations only decide whether the orphaned assertions land in `xfail`\nrather than `fail`. It is the file's own exit status. srfi150.scm provokes an\nuncaught top-level error and then calls `(exit 0)` on the SRFI-64-clean path,\ndeliberately. A plain run honours that, so run-all.sh reads 0 and says PASS.\nThe `kaappi test` worker sets `suppress_exit` so the file's `(exit)` cannot\nrob it of the chance to emit a result — but it then reported `script_had_error`\ndirectly, never consulting what the suppressed call had asked for.\n\nrun-all.sh was right. tests/scheme/errors/exit-code.sh already pins the rule a\nplain run follows, with its own regression test: an explicit `(exit N)` wins\nover an already-reported top-level error. And this was a gap rather than a\npolicy — `emitResult`'s own doc comment claimed `errored` covered \"a nonzero\n`(exit)`\", which the code never did. Suppressing the termination was never\nmeant to also discard the status.\n\nSo the semantics are reapplied where the verdict is formed, in one function\nwith all three facts in hand. An `(exit 0)` waives the file's own top-level\nerror; it can never bury a failing assertion, because the counters stay\nauthoritative. A nonzero exit the counters already explain stays redundant, as\nbefore — calling it an error would trade per-assertion detail for a bare ERROR\nline. A nonzero exit they do not explain is now an error, which closes the\nopposite-direction divergence nobody had noticed: such a file was FAIL under\nrun-all.sh and silently PASS here.\n\nNothing goes quiet. A waived error becomes a note — carried in error_message\nwith error:false, printed under the file's verdict line with the worker's own\ndiagnostic, and tallied as `noted` in both summaries. The first summary line is\nrelabelled `Tests:`, since it counts tests and the line under it counts files.\n\nVerified by running both runners' verdict rules over all 352 SRFI-64 files:\n1 disagreement before, 0 after. srfi150.scm is the only file repo-wide in this\nstate, and it is untouched by this change.\n\nrunner-agreement.sh is the gate that keeps it that way: seven fixtures, each run\nthrough both rules, which must agree and land on the expected verdict. Its first\nfixture rebuilds srfi150's shape from scratch, so the guarantee outlives #2051\nfixing SRFI 150. Reverting resolveVerdict kills 3 of its 10 assertions, in both\ndirections.\n\nCloses #1903.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Record the runner-agreement fix in the changelog\n\nThe changelog gate is right to fire here: this changes what `kaappi test`\nreports for a real class of file, which is user-visible behaviour, not a\nrefactor.\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-01T18:29:58+05:30",
          "tree_id": "a20f5d30d65ea1222a32cdc4d69cc923a5e1e4d9",
          "url": "https://github.com/kaappi/kaappi/commit/70675ffae061552ebbb9a2373e45dae431353560"
        },
        "date": 1785601242778,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.268112,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.567725,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.569836,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.977499,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00466,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046511,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.314248,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.0571,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.695347,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.224677,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.57476,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.282775,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.768204,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.464813,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044264,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "e699b451536d8200d76cfe0d5ed71e2f98f905f8",
          "message": "Phase 3.10: un-quarantine the SRFI 257 reference suites; re-triage SRFI 150 (#2071)\n\ntests/scheme/srfi/slow/ held the two full SRFI 257 reference suites and no\nrunner reached it: run-all.sh's globs are non-recursive (kaappi#1900). The\nquarantine's premise was wall-clock — the headers claimed 4.5 and 1.5 minutes\nof macro expansion against a 60s per-file budget. Both now run in ~0.4s.\n#1802/#1804 (ReleaseSafe was memsetting the expander's 1MB buffers on every\nexpansion) obsoleted the quarantine eight days after it went in, and nothing\nre-measured, because nothing ever reported the files as missing.\n\nMove both up into tests/scheme/srfi/ rather than teaching run-all.sh one more\nglob: that keeps the invariant \"subdirectories hold fixtures, suite files sit\nat the top level\" intact, and needs no change to the 18 CI legs that run this\nscript. They rank 6th and 7th slowest of 202 srfi files; five already-enabled\nfiles are slower, so the budget argument is settled by a wide margin.\n\nThey do not supersede the lean srfi257.scm / srfi257-rx.scm: 18 of 34 and 8 of\n25 of those assertions have no counterpart in the full ports, so both are\nkept. That made their SRFI-64 suite names collide — the only two duplicate\ntest-begin names in the tree, and SRFI-64 derives its log filename from the\nsuite name — so the full ports are renamed to srfi-257-full / srfi-257-rx-full.\nNet: +131 assertions for ~0.8s.\n\nrun-all.sh gains a reachability check so this cannot recur silently. It fails\nthe run if any .scm under a suite subdirectory contains test-begin. Fixtures\nare exempt by construction (a fixture never opens a SRFI-64 suite), verified\nagainst the whole tree: 11 fixture files under suite subdirectories, zero\nfalse positives, and the check is mutation-tested in both directions.\n\nSRFI 150's four expected failures are re-triaged. They cited closed #1832;\nthat attribution is wrong on both halves. #1832 is fixed — its own regression\ntest passes and its exact shape works under plain (scheme base)\ndefine-record-type — and a pre-existing top-level binding, #1832's defining\ncondition, is not required here at all: removing it leaves every case failing\nidentically. They are also not #2003, which needs the captured global to hold\na procedure. All four are one new defect, kaappi#2051: lib/srfi/150.sld\ncarries field names to run time inside quote, and quoting strips the hygiene\nrename, so two hygienically-distinct fields collapse into one. The expansion\nitself is correct. The library header's claim that the rename survives that\nboundary is corrected in place.\n\nThe annotations' structure is deliberately left alone so #1903 keeps its\nreproducer; that issue's own text contemplates restructuring this file as one\npossible resolution, which is 6B's call to make, not this PR's.\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-01T19:09:13+05:30",
          "tree_id": "a69c0245756d44d237d4df5d27d334d9a764413f",
          "url": "https://github.com/kaappi/kaappi/commit/e699b451536d8200d76cfe0d5ed71e2f98f905f8"
        },
        "date": 1785604353533,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.285411,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.136965,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.581225,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.010866,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004694,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.048087,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.318348,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.05728,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.677152,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.228172,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.580147,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.292904,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.782904,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.676398,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.04602,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "7c564fe00696c8aaf929c42b371c5b67e810495d",
          "message": "Phase 3.7: eleven untested SRFIs — 271 assertions, and a use-site local named after a keyword captures it in every macro template (#2076)\n\n* Phase 3.7: eleven untested SRFIs — 271 assertions, and a use-site local named after a keyword captures it in every macro template\n\nEleven SRFIs had no test file at all: 2, 8, 11, 16, 28, 31, 34, 111, 145,\n222, 229. All eleven now have one, and all eleven answer their `srfi-N`\ncond-expand identifier — which is what made the gaps below invisible.\n\nThree files rather than eleven. SRFI 2 and SRFI 222 each carry a filed\ndefect, so each gets a self-contained file a fix PR can re-enable whole.\nThe other nine are 1-4 exports apiece with nothing filed against them;\nthey share one hygiene harness and one set of cross-SRFI composition\nassertions, so batching them beats nine near-empty files.\n\nEight of the eleven are correct against their own spec and against\nchibi-scheme 0.12.0 on every probe: 8, 11, 16, 28, 31, 34, 111, 229 —\nincluding all of SRFI 229's three worked examples, all of SRFI 34's six,\nall three of SRFI 11's, and SRFI 16's `plus`. SRFI 145 is correct too;\nits failure path errors where chibi returns #f, which is the reference\nimplementation's own debug-mode behaviour.\n\nThree issues filed:\n\n- #2072 (srfi 222) implements 5 of the spec's 10 procedures —\n  compound-map, compound-map->list, compound-filter, compound-predicate\n  and compound-access are simply absent, and the last two are what the\n  SRFI's own rationale is built around. Of the five that exist,\n  make-compound does not flatten nested compounds and compound-subobjects\n  raises on a non-compound instead of returning a one-element list, though\n  its two siblings compound-length and compound-ref both have the\n  non-compound arm and both behave correctly.\n\n- #2073 SRFI 2's `(and-let* ((x 1)))` returns #t, not 1. The spec's own\n  denotational semantics is explicit — eval[(AND-LET* (CLAW))] =\n  eval_claw[CLAW] — and chibi returns the claw value for all three claw\n  shapes. lib/srfi/2.sld folds the no-claw and last-claw base cases into\n  one rule that always yields #t.\n\n- #2074 A use-site local binding named after a syntactic keyword captures\n  that keyword inside any macro template. 15 of 17 keywords probed —\n  including begin, lambda, quote, letrec, cond, case, and, or, do, set! —\n  so `(let ((begin 5)) (m 7))` compiles m's `(begin e)` template as the\n  procedure call `(5 7)`. Chibi gets 16 of 17 right. The guard at\n  src/ir.zig:620 states the intended exemption in its own comment but\n  cannot deliver it: a template-introduced keyword never acquires a\n  `__hyg_N_` prefix, so isLexicallyBound decides the case. This is the\n  mirror image of closed #788, whose fix added that guard. It reaches two\n  shipped libraries here — SRFI 31's `rec` (via letrec) and SRFI 8's\n  `receive` (via lambda).\n\n39 assertions are disabled behind those three plus #2003 (which SRFI 8's\nreceive and SRFI 145's assume both reproduce, via call-with-values and\nerror respectively) and #1932 (a box built on a worker thread comes back\nwith box? => #f — the same defect Phase 5C found for a user-defined\nrecord, now reaching a spec-mandated type). Every disabled block was\nmutation-tested: uncommented, exactly those assertions fail, and two\n#f-expecting SRFI 222 assertions were rewritten as `(list … 'ran)` after\nthe mutation test showed they passed vacuously on an undefined-variable\nraise.\n\nTwo behaviours pinned as observed rather than filed, because chibi\nproduces byte-identical output: SRFI 28's `format` emits a trailing tilde\nand an unknown directive literally where the SRFI's reference\nimplementation raises (the Specification prose mandates an error only for\ntoo-few values), and `~A` is not `~a` — it passes through *without*\nconsuming its object, so a later `~a` silently takes the wrong argument.\nKaappi's `~a` on a nested list is the one place it beats chibi: R7RS\n6.13.3 requires nested strings and chars to be unescaped, and only Kaappi\ndoes that.\n\nRefs #1890.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Shrink the 200k format assertion — it was 35.7s of a 36s file (#2100)\n\nThe assertion is about recursion depth, and 10,000 frames exercises that.\nBut `format` walks its argument with `string-ref`, which is O(k) here\nbecause Kaappi indexes strings by codepoint over UTF-8 bytes — so the call\nis O(n^2):\n\n    input     format    bare string-ref loop   read-char from a string port\n     10,000     88 ms                 88 ms                           1 ms\n     50,000  2,181 ms              2,173 ms                           4 ms\n    100,000  8,691 ms              8,738 ms                           7 ms\n    200,000 35,756 ms\n\nstring-ref is essentially 100% of the cost, and the doubling steps confirm\nthe exponent (2x input -> 3.98x and 4.11x time). Filed as #2100, together\nwith the 20 other portable .sld files that use the same index-loop idiom.\n\nAt 200,000 this blew the 60s per-file budget on four CI legs — ubuntu\nReleaseSafe and Debug, freebsd-test, netbsd-test — while passing on a\ndeveloper Mac in 36s. The whole file now runs in 0.165s, same 196\nassertions.\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-01T19:28:25+05:30",
          "tree_id": "95795263e749b8a6b00fd67de805fb5d71c75848",
          "url": "https://github.com/kaappi/kaappi/commit/7c564fe00696c8aaf929c42b371c5b67e810495d"
        },
        "date": 1785606223661,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.274088,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.09732,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.571379,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.975592,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004625,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046744,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.313726,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057059,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.657892,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.224925,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.58126,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.281032,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.782276,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.596332,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045371,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "f04aa5a75fa7bfe12381d1732ebaeb88787f7b7e",
          "message": "Phase 4A: derive isRejectedFormHead — the one missing name was define-property, and it was live on cond/case/do (#2092)\n\n* Phase 4A: derive isRejectedFormHead from the eval-fallback set\n\nThe native backend had two gates against splitting a lexical scope across\nthe native/interpreted boundary, and only one of them was derived.\n`ir.eval_fallback_form_names` is comptime-built from `llvm_node_table`,\nevery `FormKind` field, and `other_special_forms`; `isRejectedFormHead` —\nwhich gates cond/case/do through `exprNativeEmittable` — was a literal\n32-name array standing parallel to it. Parallel lists drift, and this one\nhad: `define-property` was in the derived set and absent from the array.\n\nThat was not latent. `define-property` is a compile-time form —\n`compileDefineProperty` evaluates its expression and stores the property\nwhile the enclosing form is compiled — and the interpreter compiles a\ntop-level `cond` whole, so the effect lands ahead of the clause body. With\nthe name missing, the backend emitted the cond natively and left only the\nregistration behind as a run-time `kaappi_eval`, moving that effect after\nthe rest of the body: `PBC` interpreted, `BPC` compiled. `case` diverged\nthe same way, and `do` did not compile at all (KP9001), because `emitDo`\ninstalls loop-variable locals before reaching the deferred form and\n`emitFormEval` refuses to eval inside a lexical scope.\n\n`rejected_form_heads` is now\n`(eval_fallback_form_names \\ derived_exclusions) ∪ extra_rejected_heads`.\n`derived_exclusions` is empty. `extra_rejected_heads` holds the six names\nthis gate rejects for its own reasons — `lambda` and `define`, lowered\nnatively elsewhere but not in sub-expression position here, and the four\nsyntax-position markers `unquote`/`unquote-splicing`/`else`/`=>`, which\nmust stay out of the derived set or `sexprNeedsEvalFallback`'s blind\nrecursion would reject every natively-lowered cond with an else clause.\nBoth lists now carry their reasons in code.\n\nA comptime block rejects a stale exclusion, an extra that duplicates a\nderived name, and any derived name that escapes the gate. The runtime test\nis deliberately stricter than the comptime invariant: it permits no\nexclusions at all, so weakening the gate takes two deliberate edits rather\nthan one quiet line. A second runtime test asserts the emitter behaviour,\nsince a correct list nothing reads would pass every list-level check.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Record the isRejectedFormHead fix in the changelog\n\nThis changes what the native backend emits for a real form, which is\nuser-visible behaviour rather than a refactor, so the gate is right to\nrequire an entry.\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-01T19:52:25+05:30",
          "tree_id": "9ad05ae621efe0d3e61d5136c28e57b32aaf7a7e",
          "url": "https://github.com/kaappi/kaappi/commit/f04aa5a75fa7bfe12381d1732ebaeb88787f7b7e"
        },
        "date": 1785606301182,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.961793,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.753976,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.575551,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.823901,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004882,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.044619,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.297449,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.054999,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.305794,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.156004,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.618274,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.312044,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.682164,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.827887,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045445,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "5681053f9c173173264bb359f8cbf024f94f85f3",
          "message": "Make a fuzz overrun reportable, and stop it destroying its own evidence (#2094)\n\n* Report a fuzz job killed by its own timeout\n\nA job killed by `timeout-minutes` is CANCELLED, not failed, and it cancels the\nwhole run with it — so the report job's bare `if: failure()` was false and the\njob was skipped. The single outcome this workflow most wants to hear about, a\nfuzz leg overrunning its budget, filed nothing at all. Verified live: #2040's\nre-run burned its full 55 minutes and produced no issue.\n\nGate the job on `failure() || cancelled()`, and inside the step decide by the\ncheck-run annotation: a leg carrying `exceeded the maximum execution time`\nreaches the infra issue (including when a sibling leg's crash artifact would\notherwise have been the only thing filed), while a plain manual or concurrency\ncancellation still files nothing.\n\nThe annotation is also the only durable evidence a timeout leaves — a cancelled\njob's log blob is frequently never archived, and #2040's re-run answered\nBlobNotFound while its annotation was intact — so the verdict now reads logs\nand annotations together. The runner-shutdown line lives only in the former,\nthe timeout message only in the latter.\n\nThat same re-run disproved the shutdown verdict this file shipped hours ago:\nit claimed a reclaimed runner meant \"not a hang… re-run the job\", when in fact\nthe shutdown had masked an overrun already in progress on that very leg. It now\nsays a shutdown does not certify the job was healthy, and to check the leg's\nelapsed time against its history.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Keep a fuzz overrun's evidence instead of destroying it\n\nAn overrunning fuzz job erased everything needed to diagnose it. Reaching\n`timeout-minutes` cancels the job; a cancelled job skips its `if: failure()`\nupload, so nothing is captured — and the corpus it started from is never\nwritten back (save-on-success) and is eventually LRU-evicted. By the time\n#2040's arm64 overrun was investigated, no copy of the input set that\nprovoked it existed anywhere, and it is still unexplained.\n\nBound the fuzz command itself with `timeout`, derived as the job budget minus\n8 minutes so the two cannot drift. The step now fails on its own terms while\nthe job is still alive, so the upload runs — and it carries the whole corpus\nand coverage map plus `fuzz-state.txt`, an mtime-ordered corpus listing whose\nnewest entries are what the fuzzer was working on when it stalled.\n\nAdd a one-minute heartbeat: `zig build` writes nothing until it finishes on a\nrunner, so a stalled job and a healthy one were indistinguishable for the\nwhole budget — #2040 burned 55 minutes of silence twice.\n\nThe report job gets a matching verdict, ordered ahead of the job-level\ntimeout, so an issue says which of the two happened and where to look.\n\nAlso record what the investigation ruled out, so a recurrence does not repeat\nit: no code regression (a local aarch64 A/B of the two commits is flat, the\nfailing one marginally faster, with the harness byte-identical), not corpus\nsize (x86_64 restored a larger one and ran fastest), not unit-suite growth,\nnot slow arm64 hardware (the gc-stress leg on the same run was normal), not a\nprinter cycle hang. And correct the matrix comment's headroom figure: one\nall-targets `--fuzz=200` pass measures ~13 min, not the \"~2 minute pass\" the\n2K limit was justified with.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Correct the corpus claims: it is evicted nightly and never restored\n\nInvestigating #2040 mis-attributed a \"Cache Size: ~49 MB / restored\" line to\nthe fuzz corpus. It belongs to the setup-zig cache, which the corpus step's\noutput happens to follow. The corpus step's own line, on every arm64 default\nrun checked — six consecutive nightlies, including both the failing run and\nthe last green one — reads \"Cache not found for input keys:\nfuzz-corpus-arm64-default-\".\n\nSo the corpus has never once been restored. Saving works (an entry appears\nafter a green run), but ~365 KB touched once a day loses the repo's 10 GB LRU\nrace against the 100-400 MB setup-zig caches CI churns continuously. The\ncoverage-guided fuzzer has been running undirected, from an empty corpus,\nevery night — the workflow comment and the runbook both claimed the opposite.\n\nFor #2040 this settles one thing and unsettles another: the accumulated\ncorpus cannot explain the arm64 overrun, because both runs had none, which\nremoves the last standing hypothesis. A dispatched run on later main then\nfinished the same leg in 1826s, inside the historical band, so it does not\ncurrently reproduce. What is left is transient runner environment — recorded\nas such, not as a conclusion.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-01T20:03:21+05:30",
          "tree_id": "72bf0c75156055504cfc889a397a3ab441d51858",
          "url": "https://github.com/kaappi/kaappi/commit/5681053f9c173173264bb359f8cbf024f94f85f3"
        },
        "date": 1785606319631,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.262877,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.001142,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.5898,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.979079,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004676,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046998,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.313906,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057224,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.676322,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.23042,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.592305,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.2795,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.774578,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.637088,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044365,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "bf71d4b101cf79f57dc82066cfb48fecae3e6556",
          "message": "Drop the per-PR CHANGELOG gate; derive release notes from git log (#2103)\n\nThe gate required every PR touching src/ or lib/srfi/ to edit CHANGELOG.md.\nWith concurrent branches that is a guaranteed conflict: every PR appends to\nthe same few lines under [Unreleased], so each one that merges leaves the\nrest needing a rebase for a reason unrelated to their content.\n\nNothing depends on the job. release.yml still reads CHANGELOG.md when it\nbuilds the release body, and the release skill still writes that section at\nrelease time (Step 3) — only the per-PR requirement is gone.\n\nThe release skill's Step 2 is flipped to match: git log since the previous\ntag is now the primary source, with [Unreleased] folded in if it happens to\ncarry anything. It already consulted commits; it just called CHANGELOG.md\nprimary, which will now usually be empty. Added the actual command and a\nnote to read commit bodies rather than subjects, since this project's\nconvention puts the \"why\" there — which is what a release note needs.\n\nNote for the record: CLAUDE.md never carried this rule. Its only changelog\nmention is the /github-release skill description, which stays accurate.",
          "timestamp": "2026-08-01T20:08:40+05:30",
          "tree_id": "38cdd47d89df25052c5ecaf0948d0812a96acb8b",
          "url": "https://github.com/kaappi/kaappi/commit/bf71d4b101cf79f57dc82066cfb48fecae3e6556"
        },
        "date": 1785606340962,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.270543,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.486676,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.600473,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.987644,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004704,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.047095,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.314682,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057345,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.835198,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.227023,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.596416,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.288053,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.801133,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.537757,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044891,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "7d81c3abeef6a3ded75c404012c5065f24c33424",
          "message": "Phase 2.7: SRFI-18 deep-copy matrix — 122 assertions, and FFI handles are aliased across heaps into a type-confused (0.0 . 0.0) (#2030)\n\n* Phase 2.7: enumerate the cross-heap deep-copy matrix\n\nThe SRFI-18 audit files test the procedures; nothing enumerated the type\nmatrix underneath them. gc_deep_copy.zig switches on all 41 ObjectTag\nmembers, and a tag that is neither on the refusal list nor round-trip\ntested is where a silent corruption lives.\n\nThis adds the enumeration: every reachable tag against all three copy\nboundaries (thread-start! capture, thread-join! result, and the uncaught\nexception path), for type AND content fidelity rather than mere arrival.\n\nThe 22 copied arms are correct. Comparison mode, parameter converters,\npromise forced-state, error irritants, exactness and internal sharing all\nsurvive both directions. The 13 reachable refusals are clean, and their\nshape is asymmetric in a way nothing pinned before: an IN refusal arrives\nwrapped in uncaught-exception?, an OUT refusal arrives direct.\n\nTwo cells were not covered by either class. ffi_library and ffi_function\nare *aliased* — the receiving heap gets a pointer into the sending one,\nwith no promotion, refcount or owner check. A child-created handle is\nreclaimed by the child's own collector while the receiver holds it and\narrives type-confused as (0.0 . 0.0), at all three boundaries including\nchannel-send with the child still running (#2027). The parent-owned\ncontrols are correct, which isolates the cliff to which heap allocates.\n\nNames are string literals throughout: SRFI 64 logs the test-name\nexpression as written, so a computed name records the string-append form\nand a remote-leg failure identifies no type at all.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Tick 2.7, and record what the deep-copy matrix found\n\nThe unit's value was the enumeration itself: 22 copied arms verified for\ncontent fidelity, 13 refusals verified clean, and two tags in neither\nclass — the aliased FFI handles of #2027.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Correct the class counts in the matrix header\n\nThe copied class is 24 arms, not 22: srfi18_time and random_source are\ncopied too. 22 is the reachable subset — flonum and native_closure are\nnot constructible from interpreted Scheme, which section G now states as\nthe reason rather than filing them under a fourth class that double-counts\nthem.\n\n24 + 3 + 14 = 41, matching ObjectTag exactly.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Say 22 of 24 in the tracker, matching the corrected header\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Add the guardian refusal rows the matrix was missing\n\nSection D covered 12 of the 13 reachable refused tags; guardian had only\nits IN direction tested, in Phase 5C's file. Both directions now asserted\nhere, so the refusal class is genuinely complete.\n\n122 assertions, green in ReleaseSafe and -Dgc-stress=true.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* 122, not 120, after the guardian rows\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Correct a false claim about SRFI 64 test names\n\nThe header said SRFI 64 records the test-name *expression* as written, so a\ncomputed `string-append` name would log the form rather than the string.\nThat is not true. Checked directly:\n\n    (test-equal (string-append \"computed \" ty) 1 2)\n\nlogs `test-name: \"computed vector\"` — the evaluated string — in both the\nconsole output and the .log file.\n\nLeft as a correction rather than a deletion because the claim contradicts\nthe strategy doc's \"name every assertion\" footgun, which tells later units\nto derive names mechanically from the expression under test. If computed\nnames were broken that guidance would be wrong, and someone would have had\nto rediscover this.\n\nThe literal-per-row style stays; its actual justification is only that one\nrow per tag is greppable and cannot drift from the tag it names.\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-01T20:11:23+05:30",
          "tree_id": "0a59238c2a79bb111c71466812b2aef3203cb782",
          "url": "https://github.com/kaappi/kaappi/commit/7d81c3abeef6a3ded75c404012c5065f24c33424"
        },
        "date": 1785606556281,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.289563,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.629262,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.597681,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.018686,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.005071,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.048451,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.315783,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057983,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.739126,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.242187,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.615899,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.291674,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.819703,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.682686,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044749,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "32cb609c2b87abb5f025a65f626f6f3f1fc42db7",
          "message": "Phase 6C: derive shell completions from the flag table (#2099)\n\nThe three `kaappi --completions` scripts were hand-written string literals\nparallel to the argument parsers, with nothing keeping them in step — the\nsame structural hazard as `isRejectedFormHead` and the `%`-prefix incident.\nThey had drifted in both directions.\n\nMissing from the completions but accepted by the CLI: `--no-ir-opt` (all\nthree scripts), and `kaappi test`'s five selection flags `-j`/`--jobs`,\n`--changed`, `--list-affected`, `--since`, `--seed` (none offered anywhere\nexcept `--seed` in bash). zsh additionally lacked `--json`, `--all`, the\nbare `--timings`, and `cache`'s `status`/`clear`; fish the same minus the\nlast two.\n\nOffered but rejected, the worse direction: `explain`, `features`, `test`,\n`doctor` and `cache` intercept argv in their own module before `cli.parse`\nruns and reject anything outside their own table with exit 2. zsh and fish\noffered the entire global flag set inside all five — 15 of 16 probed flags\nare rejected in each.\n\nThe fix is structural rather than a resync, which would have gone stale\nwithin a release. `src/cli_spec.zig` is now the one authoritative table:\nevery parse loop dispatches on an exhaustive `switch` over its `Id` enum,\n`printUsage`'s `Options:` block is generated from it (it was a fourth\nparallel list), and `completions.zig` generates all six shell scripts from\nit at comptime.\n\nClosing the last escape hatch mattered as much as the generation.\n`--diagnostics=` and `--timings[=fmt]` were matched by `startsWith` outside\nthe old table because it could not express GNU `=` syntax, and that is\nexactly how they — and later `--no-ir-opt` — drifted out. A `ValueSyntax`\nenum covers all four spellings, so nothing reaches a parser without a table\nrow. It also fixes the zsh specs: attached-only values now use `--opt=-`\nand `::` for optional, so zsh no longer completes the `--diagnostics json`\nform the parser rejects.\n\nThe gate was verified by mutation: adding an `Id` variant with no row, a\nrow the parser does not handle, deleting `--seed` from `test_flags`, and\ndropping `--no-ir-opt` from the top-level offer each fail the build or the\ntests.\n\n`completions.zig` had no tests. It now has 11, plus a 41-assertion shell\nsuite that drives the generated bash function and feeds every offered flag\nback to the real binary per context, with its own discriminating control so\na broken matcher cannot pass vacuously.\n\nFound while measuring, filed separately as #2096: `kaappi --check foo.scm`\nruns the program, because `--check` is `fmt`'s flag accepted by the global\nloop one hyphen-pair from the `check` subcommand that executes nothing.\n\nRefs #1890\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-01T21:17:26+05:30",
          "tree_id": "2833ced270e6effbb1868d8df15b7c916b1bda12",
          "url": "https://github.com/kaappi/kaappi/commit/32cb609c2b87abb5f025a65f626f6f3f1fc42db7"
        },
        "date": 1785607964543,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 2.473972,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 5.028285,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.342138,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 1.900298,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004006,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.033092,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.182528,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.034387,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 1.682669,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.757121,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 0.957461,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.191347,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.067707,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.60286,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.029162,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "f0b105a64e9689640a5905ffc21cd9ef839eccd2",
          "message": "Normalize kaappi fmt line endings to LF, and say so (#2093)\n\nCloses #1897. `fmt` already stripped every CR between lexemes — `\\r` is\nwhitespace to its lexer and the printer only ever emits `\\n` — but nothing\ndeclared that as policy, `docs/dev/fmt.md` never mentioned line endings at\nall, and the formatter leaked CRs of its own back into the files it wrote.\n\nThe policy is LF, matching `zig fmt` on this compiler's own Zig (verified:\n`zig fmt` normalizes both CRLF and lone CR). The rejected alternative is\nrustfmt's `newline_style = \"Auto\"`, which preserves a file's dominant ending\nso a Windows checkout is never rewritten wholesale. That cost is real and is\nbeing accepted rather than dismissed, for three reasons. `fmt.md` already\npromised that layout \"depends only on the program's content and its comments,\nnot on the input's own line breaks, so two files that differ only in\nwhitespace format identically\" — preserve makes that sentence false. `fmt`\nalready canonicalizes every other whitespace dimension unconditionally (tabs,\nruns of spaces, all indentation, a missing trailing newline), so preserving\nexactly one of them is the arbitrary position. And preserve has no defined\nanswer for a genuinely mixed file or for a file with no line break at all,\nwhere normalize has no undefined case.\n\nTwo real defects fixed underneath the declaration, both places `fmt` emitted\na CR itself:\n\n  * A line comment's trailing `\\r` survived. The comment scan runs to `\\n`,\n    so that CR is the terminating CRLF's — but `trimEnd` stripped only\n    \" \\t\", leaving every commented line in a CRLF file ending in a stray CR\n    while every other line got LF. The output was a fixed point, so this was\n    stable and wrong rather than noisy.\n  * Block-comment interiors kept their CRs, so a CRLF file with a block\n    comment formatted to a mixed-ending file. A block comment ends at `|#`\n    and its bytes reach no datum, so normalizing them cannot change the\n    program. Doing it at parse time rather than in the printer also keeps\n    `measure` honest: a CR-only block comment holds no `\\n` and would\n    otherwise be judged inline-able, putting a raw CR mid-line.\n\n`skipSpace` now counts a lone CR as a line ending (R7RS 7.1.1 says it is\none), so blank-line grouping and trailing-vs-leading comment placement no\nlonger collapse on a CR-only file.\n\nA `;` comment's *interior* CR is deliberately left alone: this reader ends a\ncomment only at `\\n` (#2079), so rewriting it would split the comment and\npromote its tail to real code. That deviation is pinned by a test and\ndocumented, both citing the issue.\n\nBytes inside a datum are never touched — string, SRFI 267 raw string,\n`|piped symbol|`, `#\\<CR>` — because there a CR is program data. That half\nwas already correct and is now asserted rather than assumed.\n\nWhy this needed its own tests: the `equal?` round-trip guard is structurally\nblind to it. `\\r` is whitespace to the reader, so a whole-file CRLF->LF\nrewrite is invariant under `equal?` — the guard proves the program did not\nchange and cannot prove the bytes did not.\n\nVerified a strict no-op on the existing tree: formatting all 942 tracked\n`.scm`/`.sld` files with the pre-change and post-change binaries produces\nbyte-identical output, and `fmt --check` flags the same 833 files before and\nafter (pre-existing; the repo has no `kaappi fmt` gate and no tracked source\nfile contains a CR).\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-01T21:07:05+05:30",
          "tree_id": "8ea5fd42eee728c665d281028a0f91f710c21e54",
          "url": "https://github.com/kaappi/kaappi/commit/f0b105a64e9689640a5905ffc21cd9ef839eccd2"
        },
        "date": 1785608021050,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.298622,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.2537,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.580213,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.090491,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004638,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046855,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.312277,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057108,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.78667,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.235053,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.588319,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.283676,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.798717,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.516495,
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
          "id": "23bbc49339cc66deadbee9e29e70c96486cdd2ab",
          "message": "Phase 7A: unify port-satellite tracing behind one enumeration (#2098)\n\nFive sites hand-traced Port's Value-bearing satellites, and nothing checked\nthat they agreed. The premise was worth measuring before refactoring on it,\nso three mutations went in first and came back out:\n\n  Port.probe_proc: Value          -> missed by 3 of 5, use-after-free\n  CustomBacking.probe_cb: Value   -> missed by 3 of 5, use-after-free\n  Port.probe_state: ?*ProbeState  -> missed by 5 of 5, UAF + leak\n\nEvery one compiled clean under `zig build`, and every one made a rooted\nport's referent fail expectAlive -- a real reclaim, not a projected one.\n\nTwo corrections to the premise fell out. `zig build test` was never silent:\n7B's expectFields pin catches all three, so the gap is the product build,\nnot the test build. And the common case is 3 of 5, not 5 of 5 -- objectSize\nuses @sizeOf and freeObject uses destroy(), so both stay right when a field\nlands inside an existing satellite. Only a brand-new satellite misses all\nfive, which is why the fix gates that case specifically.\n\ntypes_port.forEachValue is now the single enumeration, with satelliteBytes\nand destroySatellites deriving the two sweep arms. It lives in types_port.zig\nfor the reason the old comment already gave: types.zig cannot import\nmemory.zig without a cycle. Expressing the enumeration there and letting each\ncaller pass its own action is what makes sharing possible -- and it preserves\nmarkValueInner's worklist append, which is precisely why that arm duplicated\nmarkPortValues instead of calling it. No arm changed what it does; they\nstopped disagreeing about which fields to do it to.\n\nTwo comptime gates move the satellite case into `zig build`: an unclassified\n?*T field on Port is an error, and a satellite declared value-free must be\nvalue-free. A Value added to Port or to an existing satellite now needs no\nGC edit at all.\n\nSeven cases extend src/tests_gc_tracing.zig. The mutation test proper counts\nits expectation from @typeInfo rather than from the walk it checks, over a\nport carrying both satellites at once -- a shape nothing previously covered.\n10 mutations, all killed, 7 by tests rather than incidental compile errors.\n\nPort is the only heap type owning a non-Object satellite struct that holds\nValues; the one analogue, Transformer.def_env, is already #1962. No new\nissues -- the arms were all correct, and the risk measured here is closed.\n\nAudit v2 Phase 7A (#1890).\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-01T21:18:48+05:30",
          "tree_id": "922b5dfaaf6b161fb42e33e135d6ab56991ae2fd",
          "url": "https://github.com/kaappi/kaappi/commit/23bbc49339cc66deadbee9e29e70c96486cdd2ab"
        },
        "date": 1785609290760,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 2.995059,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 5.434807,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.404384,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.10607,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004209,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.035899,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.220897,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.040749,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.092585,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.899501,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.182149,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.224822,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.304599,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.723058,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.034744,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "3c1a56beb44ed9e46d514b0e207b7de098cec218",
          "message": "Stop pinning #2027's presence — whether a freed alias still works is luck (#2105)\n\n`(not (procedure? r))` asserted that the bug is still THERE: that a\nchild-created FFI handle, aliased across heaps and freed under the receiver,\narrives unusable. Whether a freed pointer still behaves like a live one is\nan accident of the allocator, not a property of the code. It held on macOS\nand failed on freebsd-test, where the handle arrives callable.\n\nThis is the third bug-presence pin in this campaign to fail on a platform\nother than the author's:\n\n  #2023  held on ReleaseSafe, failed on the Debug leg (94/200 deep keys\n         found under Debug vs 6/200 under ReleaseSafe)\n  #2027  this one — macOS vs freebsd\n  and both were written because a real bug was found and pinning it seemed\n  like the responsible thing to do.\n\nThe assertion directly above it is the stable half, and is the one the\nmatrix actually needs: ffi_function is in the ALIASED class, not the\nREFUSED class, and \"the join does not refuse it\" IS that classification.\nWhen #2027 is fixed that assertion flips, because a correct implementation\nmust refuse or copy rather than alias — so the row keeps a tripwire without\ndepending on how a freed pointer happens to behave.\n\n122 -> 121 assertions.\n\nNote on how this reached main: #2030 merged at 14:41 on checks that were\ngreen for an earlier push; the rebase-triggered run finished at 15:03-15:45\nand failed on five platform legs. Worth knowing that a rebase-and-merge in\nquick succession can merge on stale green.",
          "timestamp": "2026-08-01T22:09:09+05:30",
          "tree_id": "a04b10f334f375738c5ddf6573855f77de14848c",
          "url": "https://github.com/kaappi/kaappi/commit/3c1a56beb44ed9e46d514b0e207b7de098cec218"
        },
        "date": 1785609580580,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.271602,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.018506,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.608864,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.988776,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004984,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046133,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.312628,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057541,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.799071,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.231056,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.593496,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.294442,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.812014,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.665437,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044684,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "f429bdf22e32ce032d3c51142e1c286745b8e57f",
          "message": "Tick the twelve merged units; record two footguns and retire a stale reason (#2106)\n\nPhases 0, 1, 2 and 3 are complete — 38 of 53. The twelve units ticked here\n(3.4-3.10, 4A, 6A, 6B, 6C, 7A) were all told not to edit the tracker, since\nevery batch before them lost time to conflicts on this one file, so their\nentries are written here from their reports plus my own re-verification.\n\nWhere the two disagree, the entry says so. Three cases worth naming:\n\n- 3.6's #2055 and #2057 are reference-implementation defects chibi\n  reproduces identically, not Kaappi porting errors. That changes whether\n  fixing them is even desirable, so the entry records it.\n- 3.7's \"15 of 17 keywords\" is load-bearing: a spot-check using `if` and\n  `let` reproduces nothing and matches chibi, because those are among the\n  two unaffected.\n- 3.10 was handed two premises and both were false — the slow/ files run in\n  0.4s, and SRFI 150's failures are neither #1832 nor stale annotations.\n\nTwo new footguns, both paid for today:\n\n- Never assert that a bug is still PRESENT. Three such pins were written\n  after real bugs were found, and all three failed on a platform other than\n  their author's, because the symptom depends on the allocator. #2027's\n  reached main and left it red on five legs.\n- A rebase followed quickly by a merge can land on stale green: the checks\n  you read may belong to the previous push.\n\nAnd step 7's rationale is corrected rather than deleted. Preferring\n`;; FAIL:` markers over `test-expect-fail` is still right — an expected-fail\ncase that never returns wedges the suite — but it cited the F13 divergence,\nwhich 6B showed was never about `test-expect-fail` at all.",
          "timestamp": "2026-08-01T22:55:26+05:30",
          "tree_id": "bab2ee004b276761c8ea03659b27306c0a2ea0a1",
          "url": "https://github.com/kaappi/kaappi/commit/f429bdf22e32ce032d3c51142e1c286745b8e57f"
        },
        "date": 1785609705880,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.421561,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.399748,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.472121,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.432565,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004785,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.040303,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.254047,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.047138,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.388259,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.023744,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.348202,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.27333,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.484838,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.864355,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.037487,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "58a05751c562c5dfe7b3e5542f5a36b2c935c762",
          "message": "Re-derive the bytecode and IR docs from source, and gate the counts at comptime (#2104)\n\n* Re-derive the bytecode and IR docs from source, and gate the counts at comptime\n\nBoth documents described an earlier design confidently enough that a careful\nreader would not think to check, and both document exactly the kind of detail\ntaken on faith: counts, operand widths, struct fields.\n\nbytecode.md said 29 opcodes (31), and called register operands u8 when the\ndispatch loop reads u16 for every one of them — so every byte count in its\ntable was wrong, and a reader computing instruction widths from it produced a\nstream validateCode rejects. Closure capture descriptors are 3 bytes\n(is_local:u8 + index:u16), not 2. The table is now re-derived from the OpCode\nenum and the fixed_operand_bytes switch, and the disassembly example is real\noutput rather than a hand-computed one (its offsets had the old widths baked\nin, it showed a \"; Bytecode (N bytes):\" header the disassembler never emits,\nand offsets are decimal, not hex).\n\nir.md said 33 node tags. NodeTag has 18: the doc predates the collapse of\ncond/case/guard/... into the single sexpr_form tag with its 18 FormKinds,\nwhich is the one thing a reader most needs from it — how lowered the IR\nalready is. Three documented Annotations fields, and the two analysis passes\nthat set them, do not exist; identifyPrimitives and markConstants were removed\nin v0.13.0 and markTailPositions is the only pass left. The standalone Emitter\nand its bytecode-parity tests went with them.\n\nThree findings the issue did not list, all the same defect:\n\n- architecture.md carried a second, undeclared copy of the opcode table\n  describing three opcodes that do not exist (get_local, set_local,\n  close_upvalue) while omitting three that do (self_tail_call, tail_call_cc,\n  tail_eval) — a wrong table whose row count happened to stay right at 31, so\n  counting it would not have caught it. Removed rather than corrected:\n  bytecode.md is the declared single source of truth, and duplicating it is\n  how this drifted.\n- adding-features.md instructed the reader to add a NodeTag variant, a Data\n  union variant, and switch arms in identifyPrimitives and markConstants —\n  the pre-sexpr_form procedure, contradicting .claude/rules/compiler-forms.md.\n  A reader following it would not have compiled.\n- The OpCode enum's own inline comments claimed u8 operands too, so the\n  source read as wrong as the doc.\n\nThe counts are now pinned at comptime, in the diagnostics.zig style: changing\nOpCode, NodeTag or FormKind fails the build with a message naming the files to\nupdate. Each gate was mutation-tested. This would have caught all of it —\nexcept architecture.md's table, which is why that one is gone instead.\n\nAlso swept README.md, CLAUDE.md, docs/dev/README.md, understanding-map.md,\nclaude-code-harness.md and the /bytecode-isa skill, which stated the same\ncounts a third and fourth way (the skill said 32 — doc 29, skill 32, enum 31).\nCHANGELOG entries are left alone as historical record.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Close the review's two stale sites, and four more the gate lists missed\n\nReview of #2104 found docs/dev/README.md:74 still saying 32 opcodes and\n.coderabbit.yaml:76 still saying 33 node types / 3 analysis passes. Both\nconfirmed against source. An exhaustive sweep across every file type — not\njust *.md and *.zig, which is what missed .coderabbit.yaml in the first place —\nshows these were the only two left.\n\nThe diagnosis was the useful part: docs/dev/README.md is named in the NodeTag\ngate's file list and absent from OpCode's, and correspondingly its node-type\nrow got fixed while its opcode row did not. The gap in the list and the miss\nare the same gap.\n\nChecking the rest of the lists against the sweep, they had four more gaps the\nreview did not reach: OpCode omitted docs/dev/claude-code-harness.md as well,\nand FormKind named only docs/dev/ir.md while CLAUDE.md and\ndocs/dev/architecture.md both state \"18 FormKinds\". Six gaps in three\nhand-written lists is the point: a list of filenames inside an error message\nis its own drift surface, which is the bug class the gate exists for. So each\nmessage now carries a search as well as the list, and says the list is the\nknown set rather than a guarantee.\n\nThe search greps the *noun*, not the number. Grepping the number does not\nwork in either direction: \"31-opcode\" and \"31 opcodes\" need different\npatterns — that separator variance is what hid README.md:74 from the original\nsweep — and a bare \"18\" collides with every SRFI number, 43 hits for \"31\"\nalone. Each search was verified to be a superset of its known sites.\n\n.coderabbit.yaml is the worst of the two stale copies, as the review argued:\nit is configuration for the automated reviewer, so it would carry the\ncorrected-away model into future PRs. Its instruction also contradicted its\nown sibling block for src/compiler*.zig, which already described the FormKind\npath correctly. Fixed less bluntly than suggested, though — the NodeTag /\nData union / freeNode list it carries is still correct for a genuinely\nstructured node, so it is kept and labelled as that path rather than deleted,\nwith the FormKind path named as the normal one.\n\nEvery count claim in the repo now matches the source. Gates re-mutation-tested.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-01T23:08:18+05:30",
          "tree_id": "d401a9e2c8f3a5687694a264dedd4b98d208fd33",
          "url": "https://github.com/kaappi/kaappi/commit/58a05751c562c5dfe7b3e5542f5a36b2c935c762"
        },
        "date": 1785611547693,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.937205,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.752373,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.561085,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.946049,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004852,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.044717,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.300907,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.054764,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.295967,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.156094,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.514663,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.299873,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.686475,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.636992,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.04503,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "e43f0f5b9b6186c8068d348df67f7c599540dbfd",
          "message": "Record the wasm32 print-depth abort as the 14th critical (#2124)\n\nTriaging the 16 unlabelled open issues put kaappi#2107 at `priority:\ncritical` — an 848-deep print exhausts the wasm32 stack and traps the\nmodule, uncatchably, from a three-line program.\n\nThe rubric doc keeps a table of every critical specifically so future\ntriage has something to calibrate against, so an entry that is missing\nfrom it is worse than no table at all. Two things would have drifted:\nthe corpus count, which is stated in the doc and again in CLAUDE.md's\nsummary of it, and the table itself.\n\nThe new entry is worth more than a row. It is the first critical whose\nabort is confined to one tier, and the first that is stack exhaustion\nrather than a heap defect — so it forms a sharper reachability pair with\nkaappi#2084 than the existing #1939/#2000 one does: both are uncatchable\nstack exhaustion, leaving reachability as the only variable between them.\nThe line that decides it is that 848 sits below printer.zig's own\nMAX_PRINT_DEPTH of 1024, i.e. inside the envelope the implementation\nintends to support, while #2084 needs a 200,000-bit bitvector.\n\nState explicitly that tier does not discount an entry. Without it the\nnext reader sees twelve core-tier heap defects plus one WASM row and\ninfers a discount the rule does not contain.\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-01T23:40:59+05:30",
          "tree_id": "b130044f3c39ccda23409fe7c86bb9732b77c766",
          "url": "https://github.com/kaappi/kaappi/commit/e43f0f5b9b6186c8068d348df67f7c599540dbfd"
        },
        "date": 1785612133181,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.28931,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.306088,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.583991,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.748606,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004756,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046029,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.31142,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057332,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.764952,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.227745,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.572355,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.28573,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.8096,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.676541,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.04429,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "04452d1ffdacacfe13b47aecead439048e86ba64",
          "message": "Phase 4D: diff the corpus under wasmtime against the interpreter (#2122)\n\nThe WASM tier shipped in every release and backs the playground, and it\nwas checked by four hand-written programs asserting their own results\nplus an exit code. A build that ran but answered differently would pass.\n\nThis adds run-wasm-differential.sh, the sibling of the Phase 4B harness:\nthe interpreter is the oracle, and every corpus file must produce\nbyte-identical stdout, an identical exit status, and identical\nnormalised stderr under `wasmtime run --dir=.`. It exits 77 where there\nis no runtime or no module, so run-all.sh picks it up everywhere and\nonly actually runs it where it can.\n\n591 files swept. 184 agree byte-for-byte, 3 are documented degradations\nmatched on the engine's own message text, and 4 diverge:\n\n  #2107  write/display of an 848-deep car nest aborts the module with an\n         out-of-bounds memory access. MAX_PRINT_DEPTH's 1024 guard is\n         unreachable on wasm32 -- build.zig gives every native executable\n         a 64 MB stack and wasm_exe is the one with no stack_size at all.\n         Uncatchable: a `guard` with a #t clause never runs. The\n         regression test for closed #49 is itself one of the files that\n         aborts.\n  #2108  no file-backed .sld is importable even when the host mounts it,\n         because platform.openRead has no WASI branch and so\n         resolveLibraryPath's existence probe fails for every candidate.\n         This is why 401 of the 591 files cannot run on this tier at all.\n  #2109  (command-line) is '() and vm.lib_paths is empty -- main.zig's\n         WASM entry returns before both are set, leaving a now-dead\n         `if (!is_wasm)` inside the block it skips.\n  #1912  (pre-existing) index arguments truncate to u32 inside the bounds\n         check, so 2^32+1 aliases element 1 -- a silent wrong read and a\n         silent wrong write.\n\nThe 401 unrunnable files are reported as their own line rather than\nquietly excluded, so a green run cannot be mistaken for broad coverage:\nit covers 184 files, not 591. When #2108 is fixed that count collapses\nand the compared count jumps.\n\nTwo probes join the shared corpus. large-index-bounds-1912.scm pins\n#1912 with the control that attributes it to truncation rather than to a\nmissing bounds check. deep-nesting-print-tier-margin.scm is the positive\ncontrol for #2107 -- depth 500, a 40% margin under the measured 847\ncliff, so it stays green on both tiers and the harness watches the\nheadroom instead of only the known failure.\n\nKNOWN_DIFFS suppresses the four while they are open, and note_stale\nreports an entry that stops diverging -- from the agreeing, library and\nplatform buckets alike, since an entry that merely shifts bucket is\nequally stale and would otherwise keep suppressing a bucket nobody\nreviewed.\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-02T00:32:20+05:30",
          "tree_id": "35afde66877167fdef393b70547afa19f5c5a5be",
          "url": "https://github.com/kaappi/kaappi/commit/04452d1ffdacacfe13b47aecead439048e86ba64"
        },
        "date": 1785614873202,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.806739,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.064286,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.524465,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.640263,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004815,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.044186,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.27265,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.052811,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.761354,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.079753,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.425781,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.255476,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.657415,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.873965,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.041663,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "23c16dc5c1f26562628d51999f369156239f3a16",
          "message": "Phase 4C: give the compile suite an interpreter oracle (#2123)\n\nThe native backend's regression tests mostly asserted that a compiled\nprogram printed a hardcoded string. That checks the native tier against a\nhuman's belief about the program, not against the reference implementation,\nand it rots: when the golden value is wrong, the test pins the wrong answer\nforever. #2092 is the worked example — `define-property` inside a top-level\ncond/case/do evaluated at the wrong *time* natively, so the binary printed\n`BPC` where the interpreter printed `PBC`. A tier comparison catches that by\nconstruction; a golden string only if someone thought to write `PBC` down.\n\nThe survey found 23 scripts, not the tracker's 22 (#1896's landed with Phase\n4A today), and 8 already compared tiers rather than 2 — the \"2 of 22\" figure\npredates five scripts written since. 11 more now do, plus one upgraded from\na partial comparison, leaving 4 genuine exceptions.\n\n`shell-common.sh` grows `interp_stdout`/`assert_tiers_agree` and the block\nexplaining the three tier differences that are by design and must not be\ncompared (docs/dev/fuzzing.md): the VM echoes a bare top-level expression's\nvalue and a native binary does not, the VM continues past a top-level error\nwhile a native binary exits at the first, and a procedure prints as\n`#<procedure name>` vs `#<procedure>`. Every converted script keeps its\ngolden string as a second assertion — now against the *interpreter*, where\nit documents intent and still catches a bug both tiers share.\n\nset-define-lexical-scope-819.sh's own comment already claimed it matched the\ninterpreter's stdout and exit status. It never ran the interpreter. It does\nnow.\n\nThe exceptions, and why: assertions that compilation *fails* have no\ninterpreter counterpart because the interpreter runs the same program fine\n(native-external-library-import-1743.sh); assertions about emitted LLVM IR\nare about which tier ran, not what it answered; a native diagnostic's text\ncannot equal the VM's, which frames one with file:line and an excerpt; and\nnothing can execute a named .sbc — `kaappi out.sbc` reads it as source — so\ncompile-preamble-699.sh has no runnable second tier short of a ~180s\n-Dbundle rebuild. It now at least asserts --compile wrote a non-empty file.\n\nFour live divergences the golden strings had been silent about, filed not\nfixed: #2115 (a guard does not catch an error raised in a natively compiled\ncallee — 4 smoke files die where the interpreter recovers, and\nllvm-backend.md lists guard under \"stress-tested\"), #2117 (constant folding\nignores both a set! rebinding and an upvalue-shadowed primitive — #600 and\n#790 are live again in the LLVM emitter), #2118 (a parameter shadowing a\nsyntactic keyword is ignored — #788 likewise), and #2119 (re-invoking a\ntop-level continuation from a native callback silently keeps the stale\nvalue, against continuation-strategy.md's stated equivalence commitment).\nAll four were found by a throwaway tier-(c) sweep of smoke/compliance/audit;\n178 of 338 files compile, 25 differ, those four are real.\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-02T00:45:46+05:30",
          "tree_id": "39ca9f97edc7c3a2d63e52c2d031e0a2cfad876f",
          "url": "https://github.com/kaappi/kaappi/commit/23c16dc5c1f26562628d51999f369156239f3a16"
        },
        "date": 1785615950573,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.306712,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.644855,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.605009,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.9893,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004744,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046507,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.312114,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057435,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.740554,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.232621,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.579074,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.293727,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.81173,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.676859,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044467,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "a6c2e8a2c1c714397140c0755a6d33244fe53380",
          "message": "Phase 5E: de-flake the timing tests — five racing blocks in srfi120.scm, and a regression test that could not fail (#2120)\n\n* Phase 5E: de-flake the timing tests — five racing blocks in srfi120.scm, and a regression test that could not fail\n\nThe audit's timing unit. Every fix here removes a place where a test raced a\ndeadline it had chosen itself, or could not report a failure at all.\n\nsrfi120.scm is the flakiest file in the tree: red on windows-x64-test, then\ntwice in one day on netbsd-test (#2076, #2093) with different assertions each\ntime, on two structurally unrelated PRs. Five blocks were racing, not the two\nCI happened to catch. Reproduced deterministically by injecting a delay where\nan emulated leg is slow, rather than by hoping an idle laptop goes red:\n\n  timer-task-remove!  300 ms margin — exists?/remove! must beat the deadline\n  timer-reschedule!  1000 ms margin — already adequate, left alone, now pinned\n  period-0 reschedule  40 ms period — queued ticks answer the next receive\n  timer-cancel!        30 ms period — likewise; this is #2093's failure\n  no error-handler     30 ms margin — this is #2076's KP3000 at :156\n\nThe last two are fixed structurally rather than by widening a number. The\ncancel block now uses two one-shots, so there is nothing to queue. The\nno-handler block schedules the erroring task LAST, so nothing calls into the\ntimer after it may stop — the ordering removes the deadline instead of\noutrunning it. The other three get margins of several thousand times the work\nthat must fit inside them, and every negative wait now outlasts the deadline it\ndisproves, so widening did not weaken detection. Three rules are written into\nthe file header so the next edit does not reintroduce them.\n\nsrfi120-slow-setup.scm is new and is the evidence: it mirrors each block with\nthe delay injected. Against the old shapes 6 of its 10 assertions fail —\nincluding \"no further firings after a delayed cancellation\" and \"scheduling the\nerroring task last never raises\", i.e. both netbsd failures by name. Against the\nnew shapes, 12/12 pass.\n\nthread-sleep-876.scm had no exit path: it displayed the answer and exited 0.\nSubstituting (thread-sleep! 0) — the exact #876 regression — printed #f and\nstill passed. Now SRFI-64 with the exit-on-fail epilogue, and mutation-tested:\nthe substitution fails both assertions and exits 1. It is one of 54 such files;\nthe rest are #2116.\n\nfiber-sleep-does-not-stall-sibling.scm asserted the fast fiber finishes within\n150 ms of the start — an upper bound on how slow the machine may be. It now\ncompares two measured timestamps (fast-done-at < sleeper-woke-at), which is the\nproperty under test and carries no wall-clock bound. Mutation-tested: a sleeper\nthat busy-waits instead of parking fails it.\n\nsrfi18-cross-heap-abandoned-mutex.scm slept 100 ms to \"let it acquire mt\". It\nnow polls the mutex's own state, so it synchronises on the event; if the child\nnever gets there the retry budget reports it instead of testing the wrong thing.\n\nRefs #1870, #2116.\n\n* Address review: require a real owner in the mutex poll, and import (scheme process-context) explicitly\n\nCodeRabbit raised three points on #2120.\n\nDeclined one: converting srfi18-cross-heap-abandoned-mutex.scm to SRFI-64 is a\nrepo-wide style migration of a pre-existing manual-counter file, and that file\ndoes have a working exit path.\n\nDeclined the substance of a second while taking its intent. The suggestion was\nto have wait-until-held! return #t only when (mutex-state m) is eq? to the child\nthread. That would never be true: mutex-state answers with the child's own\nFIBER, not the thread make-thread returned, so the poll would spin to its retry\nbudget and the test would fail. Filed as #2125 with the probe. The underlying\nconcern — that \"not 'not-abandoned\" also accepts 'abandoned, i.e. a child that\ndied on the way — is real, so the predicate now requires an owner object and\nexcludes both unowned symbols.\n\nTook the third: (exit …) is R7RS's (scheme process-context), and although\nkaappi happens to provide it from (scheme base) alone, the documented template\nin tests/scheme/CLAUDE.md imports it. Added to both new/rewritten SRFI-64 files.\n\nRefs #2125.",
          "timestamp": "2026-08-02T00:48:26+05:30",
          "tree_id": "aa452e4d817b6da85e141f14c30bc6c3d1a9a2f6",
          "url": "https://github.com/kaappi/kaappi/commit/a6c2e8a2c1c714397140c0755a6d33244fe53380"
        },
        "date": 1785616402868,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.280897,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.273057,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.576622,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.767128,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004756,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046171,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.311138,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057417,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.751656,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.229463,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.563158,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.277047,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.808897,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.621009,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045756,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "fbd92a14e3821a534eb02c20f1bd97c21ca3c193",
          "message": "Document ir.isRedefined() shadowing guard, link KEP-0008 (#2126)\n\nfoldConstants, eliminateIdentity, and simplifyBooleans all guard against\nfolding a user-shadowed primitive via ir.isRedefined(), but docs/dev/ir.md\nnever mentioned it. Also links to KEP-0008, the new cross-repo IR contract\nshared with paal and chaaya.",
          "timestamp": "2026-08-02T00:51:22+05:30",
          "tree_id": "854d991c4b763128ca94c54eeb420102fb4dc4e8",
          "url": "https://github.com/kaappi/kaappi/commit/fbd92a14e3821a534eb02c20f1bd97c21ca3c193"
        },
        "date": 1785618575921,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.329578,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.969168,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.570863,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.968826,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004733,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046348,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.311713,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.05739,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.834583,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.233841,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.569442,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.280226,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.802077,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.641921,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044001,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "94ebd5a0221d36bd35e2e545051b08efa9803420",
          "message": "Phase 4E: .sbc cache coverage — eight probes, and three things a HIT changes (#2121)\n\nPhase 4B shipped the cold-vs-warm cache differential and found zero\ndivergence across 333 corpus files.  That was a coverage result, not a\ncorrectness one: only 40 of them populate the cache at all, and the six\ntoy forms in `sbc equiv:` are the entire round-trip surface the codec\nhas ever been asked about.\n\nEstablish the population rule first, since everything else depends on\nit.  A run writes an entry iff caching is on, at least one form compiled,\nand `has_imports` stayed false — and that flag is set by ANY of the eight\nhead symbols `vm_eval.handleTopLevelForm` claims, not just `import`.\nMeasured, one isolated KAAPPI_HOME per file: 40 of 345 cached; of the 305\nuncached, 303 have a top-level `import`, one is disabled by a top-level\n`begin` and one by a top-level `define-values`; zero cached files contain\nany of the eight.  `docs/dev/cache.md` documents only the `import` case\nand `--timings` blames `imports` for all eight (#2114).\n\nThen round-trip every constant tag through a real cold/warm run rather\nthan a unit fixture.  Fixnum at both ends of the 48-bit payload, flonum\nincluding -0.0 / +-inf.0 / NaN / 1e308 / 5e-324, bignum in both signs,\nrational with bignum parts, complex with its exactness bits, non-ASCII\nstrings, #\\x10FFFF, |weird sym|, bytevectors, nested and improper\nstructure, closures and upvalues, case-lambda, named let, call/cc,\ndynamic-wind, guard, parameterize: all clean.  That is the headline\nresult and it is a real one.\n\nThree things are not.  A HIT rebuilds constants through the ordinary\nallocators, so it drops `Object.flags.immutable` and `set-car!` on a\nliteral raises cold and succeeds warm, exit 1 becoming exit 0 (#2110).\n`writeConstant` has no visited-set, so datum-label sharing is emitted\nonce per reference and `eq?` flips #t to #f — with a shared DAG going\nexponential (241 source bytes, 4.7 MB of .sbc) and a cyclic literal\nnever loading at all (#2111).  And `define-syntax` registers its\ntransformer as a compile-time side effect that a HIT never replays, so a\ntop-level macro is invisible to a run-time `eval` (#2112).\n\nThe fourth is what hid the third symptom: the writer enforces almost none\nof the reader's limits, so a constant past MAX_CONSTANT_DEPTH or a vector\npast MAX_VECTOR_LEN writes an entry that can never be loaded.  The file\nrecompiles and rewrites the same .sbc forever, `cache status` calls the\nentry \"current\", and counting entries reads it as covered (#2113).  The\nharness now runs `--timings` once per cache-populating file and fails on\nan unexpected permanent miss; across all 599 files in the full corpus\nthere are none.\n\nProbes are written to stay cacheable — sbc-population.scm carries the\nrule and the control that the four non-library heads only disable it in\ntop-level head position.\n\nDefault corpus 345 -> 353 files, cache-exercising 40 -> 48, 118s.\nFull suite green: 663 Scheme files, 1395 R7RS assertions, 0 fail.\n\nRefs #1890\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-02T01:05:22+05:30",
          "tree_id": "171cf8e97cbb787c07d86a6aae46cf9abb65eaee",
          "url": "https://github.com/kaappi/kaappi/commit/94ebd5a0221d36bd35e2e545051b08efa9803420"
        },
        "date": 1785622240595,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.287617,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.092973,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.573069,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.987546,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004713,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046061,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.311168,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057369,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.785479,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.230107,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.569087,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.281043,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.80023,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.622473,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044055,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "891933bd6d06cb53cb0617f48b687732c1b9132c",
          "message": "Tick 4C, 4D, 4E and 5E — Phase 4 complete, 42 of 53 (#2128)\n\nEvery one of these four corrected the tracker's own description of the\nwork before doing it, which is worth more than the tick:\n\n- 4C: 23 scripts, not 22, and 8 already compared tiers, not 2 — the \"2\"\n  predates five tier-comparing scripts written since #1799.\n- 4D: \"import-free corpus\" was the wrong cut. Built-in registry libraries\n  import fine on WASM; file-backed .sld files never load at all, and that\n  is a bug (#2108), not a platform limit.\n- 4E: the cache is disabled by eight top-level heads, not just import.\n- 5E: \"76 wall-clock lines\" is not reproducible under any definition, at\n  HEAD or at the campaign baseline. The real count is 216.\n\nTwo results are worth reading past the issue numbers. 4E found the codec\nis correct for every value it can represent — every constant tag round-\ntrips clean — which makes its four divergences sharper, because all four\nare metadata a HIT drops rather than values it corrupts. And 4D's harness\nprints its 401 unrunnable files explicitly, so a green run reads as\ncovering 184 files rather than 591.\n\n5E closed a loop from yesterday: srfi120.scm blocked two unrelated PRs,\n#1870 was reopened, and 5E then reproduced all five racing blocks\ndeterministically by injecting delays — two fixed structurally rather\nthan by widening margins, because the periodic task's ticks were queuing\nin an unbounded channel and a wider margin would have made it worse. The\nnext PR to hit that leg (#2121) was cured by rebasing onto the fix.",
          "timestamp": "2026-08-02T01:49:37+05:30",
          "tree_id": "9a006cd5e78c074d07b7026984fbecaffc3f47e1",
          "url": "https://github.com/kaappi/kaappi/commit/891933bd6d06cb53cb0617f48b687732c1b9132c"
        },
        "date": 1785622561530,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.288162,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.110941,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.572588,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.091271,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004847,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046275,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.31155,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057279,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.781121,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.231974,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.595936,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.278857,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.798347,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.64236,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043854,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "46e637039e30eba5c1a12562ff2131b7207b237c",
          "message": "Retire the SRFI 120 corruption claim, and pin why it cannot come back (#2140)\n\nThe most alarming statement in the tree was that a second thread calling\ninto a timer produced nondeterministic memory corruption, \"not\nroot-caused\". It does not reproduce -- not on ReleaseSafe and not under\n-Dgc-stress=true, which stamps freed headers and quarantines freed slots\nso a dangling value panics deterministically rather than corrupting by\nluck. A claim retired without a test is a claim that comes back, so the\nrewrite ships with 18 assertions pinning every way a <timer> can reach\nanother thread and which guard refuses it.\n\nThe earlier re-check reached the right verdict for a partly wrong reason,\nand that mattered: it credited gc_deep_copy's .fiber rejection with\nclosing both entry paths. A value reached through a top-level binding is\nnever deep-copied, so that list has no bearing on it at all -- what\nrefuses there is the control channel's Object.owner check. Two\nindependent guards, and a change to either one alone would have left a\nhole nobody was watching.\n\nThree further entry paths that neither earlier check enumerated turn out\nto be refused too, and are pinned as well: a timer sent as a channel\nmessage payload, a task thunk closing over a second timer (timer-schedule!\nships the thunk over the control channel, so that is a copy boundary with\nno thread-start! in sight), and a timer reached through a top-level\ncontainer rather than a binding of its own.\n\nTwo other header claims were measured and were wrong. A thunk calling back\ninto its own timer was documented as deadlocking; it cannot -- it has no\nway to name the timer at all, and both spellings fail immediately with a\ncatchable error. And the reason given for not fixing that gap cited the\ncorruption claim being retired here, so it no longer applies.\n\nWhat did turn up is a real crash, filed as #2129 and not fixed here:\nthread-join! frees the joined thread's GC/VM while a thread it spawned is\nstill in its startup prologue. make-timer inside a SRFI-18 thread returns\nat exactly that moment, so it dies 24/30 runs. That is an engine bug --\nreproducible with no timers involved -- and the header now says so\ninstead of gesturing at unlocated corruption.\n\nRefs #1890, #2129.",
          "timestamp": "2026-08-02T02:18:05+05:30",
          "tree_id": "44fda5edabc10dcec3e3b9ff7adf22963b647557",
          "url": "https://github.com/kaappi/kaappi/commit/46e637039e30eba5c1a12562ff2131b7207b237c"
        },
        "date": 1785623232979,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.291694,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.451056,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.590639,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.97412,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004765,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046436,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.311242,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057596,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.741387,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.231008,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.567025,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.286835,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.799114,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.647719,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043816,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "e6b428d75810412e192dc7b9771cb8322276d8c8",
          "message": "Tick 5F, and correct a 30x-stale time estimate it exposed (#2147)\n\n5F is clean on both halves, run on a c5-4vcpu-8gb droplet at 94ebd5a0 and\ndestroyed after ~37 minutes for ~USD 0.09:\n\n  unit suite,  -Dgc-stress=true    1570 pass, 0 fail\n  Scheme suite against that binary 2061 pass, 0 fail, 0 timeout\n\nThe Scheme suite has never run against a gc-stress build on x86-64 Linux\nbefore. With a collection attempted on every allocation, that is the\nstrongest evidence available that yesterday's twelve merged units\nintroduced no rooting bugs.\n\nThe finding, though, is the timing. The run reported EXIT:0 with a 7-byte\nresults file after 8 minutes, against a documented 1.5-3 hour budget — the\nsignature of a build flag that silently failed to apply, and this campaign\nhas already found three tests that passed without exercising anything. The\ncontrol settled it:\n\n  plain       1567 pass, 3 skip     50s\n  gc-stress   1570 pass             5m07s\n\nSix times slower with a different skip count, so the flag is active and the\nestimate was ~30x stale — on a droplet vCPU slower than the M-series Mac it\nwas compared against. Almost certainly since #1802/#1804 and #1809 stopped\nReleaseSafe 0xAA-filling `= undefined` buffers.\n\nThe skill now carries the measured numbers, keeps the detached-poll pattern\n(it costs nothing when the run is short), and warns that `zig build test`\nprints nothing on success — so a fast finish must be checked against the\ncontrol, not the clock.",
          "timestamp": "2026-08-02T03:00:18+05:30",
          "tree_id": "29b12ecbb1a54a42141b8f0e36acc78b52a7044e",
          "url": "https://github.com/kaappi/kaappi/commit/e6b428d75810412e192dc7b9771cb8322276d8c8"
        },
        "date": 1785623807295,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.081096,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.460524,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.43863,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.209412,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.003784,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.034676,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.231501,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.042846,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 1.841963,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.905424,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.172623,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.232813,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.314396,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.315967,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.035092,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "910f7c75e0c204bb6fd64407361f9165cd29628b",
          "message": "Phase 7C: the big-endian canary — it ran the unit suite and r7rs-tests.scm, and SRFI 74's one endian assertion compared a function to its own definition (#2145)\n\n* Phase 7C: make the big-endian canary able to fail\n\ns390x exists to catch byte-order bugs (#1654), but `ci.yml`'s `s390x-test`\njob ran three steps -- the cross-compile, the unit suite, and\n`r7rs-tests.scm` -- and `r7rs-tests.scm` imports no SRFI with a\nbyte-order-sensitive surface. So SRFI 74 (blobs), SRFI 160 (host-native\nnumeric-vector storage) and SRFI 135 (UTF-16) had never executed on a\nbig-endian machine, and `ppc64le-test` is not a second canary: POWER is\nlittle-endian in this configuration.\n\nThe one assertion that claimed to cover this could not fail. Under the\nheading \"native accessors agree with explicit-endianness accessors\",\nsrfi74.scm compared `blob-u32-native-set!` against\n`(blob-u32-set! (endianness native) ...)` -- which is how lib/srfi/74.sld\n*defines* it. Measured: hardcoding the `endianness` macro's native arm to\n'big leaves srfi74.scm at 30/30 pass, while the replacement suite reports 7\nfailures.\n\nNo Scheme test can close the gap by itself. `(endianness native)` is\n`(if (%host-big-endian?) 'big 'little)` and that primitive is the only\nScheme-visible witness of host byte order -- SRFI 160 exposes no byte view\nof a NumericVector -- so a Scheme assertion can only re-derive its\nexpectation from the same primitive. The chain is therefore split:\n\n- src/tests_endian.zig (11 tests) pins what Scheme cannot: `%host-big-endian?`\n  against an actual memory probe, and the `.sbc` codec's canonical\n  little-endian scalars. Every `.sbc` test until now wrote and read on the\n  same host, so a paired byte-swap cancelled out; these check the writer\n  against literal expected bytes and the reader against a hand-assembled\n  literal-little-endian header, one direction at a time. #438 (writeF64\n  omitted the conversion) was exactly this class of bug, found by\n  inspection rather than by a test. The unit suite already runs on s390x,\n  so these need no CI change.\n- tests/scheme/audit/endianness-audit.scm (99 assertions) pins the\n  explicit big/little byte layouts at every width, native's *selection*\n  between them relative to `%host-big-endian?` (never a hardcoded order),\n  SRFI 160's encoder-vs-ref-vs-printer agreement, SRFI 135's UTF-16BE/LE\n  including surrogate pairs and BOM dispatch -- srfi135.scm had zero utf16\n  coverage -- and, as controls, the byte-oriented surfaces that must not\n  vary at all.\n- tools/run-endian-suite.sh runs that file plus the nine pre-existing\n  suites carrying endian assertions: one command, ~1s natively, now a step\n  on all three QEMU legs (riscv64 and ppc64le as little-endian controls).\n\nsrfi74.scm's tautology is replaced and all 31 of its assertions are named:\nSRFI-64 prints a failed assertion's value, not its source, so an unnamed\nfailure on an emulated leg is a bare `#f`.\n\nTwo things `docs/dev/porting.md` now states rather than implies: what the\ncanary actually runs, and that a local `zig build test -Dtarget=s390x-linux`\nproves nothing about behaviour -- `skip_foreign_checks` makes it exit 0\nhaving skipped the run, and it only executes in CI because\nsetup-qemu-action registers binfmt_misc.\n\nCloses #2139.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Make the endian suite independent of /proc/self/exe and of the caller's cwd\n\nThe exe-relative library default (<exe_dir>/../lib) reads /proc/self/exe on\nLinux, and the three legs this script exists for run the binary through\nbinfmt_misc, where that path is the emulator's to define. Naming --lib-path\nlib explicitly costs nothing and removes the failure mode. The script now\nalso resolves its argument against the caller's cwd before cd-ing to the\nrepo root, so a relative path means what the caller meant.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Drop an unused import from tests_endian.zig\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Add SRFI 271 to the endian suite\n\nA byte-punning sweep of src/ turned up one surface the first pass missed:\ndeterminized random ports move u64s in and out of a bytevector with an\nexplicit .little (primitives_random_port.zig, types_port.zig), so a seeded\nstream is meant to be byte-identical on every host. srfi271.scm's own\nassertions compare two ports on the SAME host -- the same cancelling pairing\nthe .sbc tests have -- so running it big-endian is what catches a write and\nread side disagreeing. A cross-host golden byte sequence is still missing,\nthe same shape of gap Phase 7D owns for .sbc.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-02T03:53:15+05:30",
          "tree_id": "7e37477d9dd5b5985a19b178fecc7848e8e35e26",
          "url": "https://github.com/kaappi/kaappi/commit/910f7c75e0c204bb6fd64407361f9165cd29628b"
        },
        "date": 1785624558615,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.994159,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.073724,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.596413,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.557119,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004719,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.047538,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.374961,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.058475,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.739161,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.44034,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.602785,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.279247,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.80389,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.570769,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043278,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "c16b1a331404b5f220f344c6d5132182442df825",
          "message": "Make the priority rubric generic — the tracker is the precedent source (#2151)\n\ngithub-issues.md is a top-level docs/dev/ guide, which docs/dev/CLAUDE.md\nclasses as evergreen. It had accumulated a hand-maintained second copy of\ntracker state: a 14-row table of every issue ever labelled critical, four\nworked reachability/silence comparisons, and a sample command naming a real\nissue. All of it goes stale on the next triage pass, and a label that moves\nsilently falsifies the doc.\n\nEvery citation is converted into the rule it encoded rather than dropped.\nThe generalised forms are the more portable rules anyway — \"compare the\ntrigger against the limit that path documents; inside the envelope is\ncritical, far past the cap is high\" applies to a subsystem that has never\nhad an issue filed against it, which four worked examples did not.\n\nWith the examples gone, \"Calibrate before labeling\" is the only remaining\nroute to precedent, so it now says so and gains two cautions: the rubric\ntext is the authority and neighbours are only a contradiction check, and\nmatch on failure shape rather than subsystem.\n\nThe four-bullet condensation in the core CLAUDE.md is kept in step; it\ncarried the same count and issue reference, and described the doc as\nholding \"worked boundary cases\".\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-02T04:58:57+05:30",
          "tree_id": "0d74dd9cc06d56304b18dddba405c06db6a18386",
          "url": "https://github.com/kaappi/kaappi/commit/c16b1a331404b5f220f344c6d5132182442df825"
        },
        "date": 1785629989592,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.24778,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.097699,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.572798,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.035514,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004689,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.045965,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.311144,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057288,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.797897,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.23864,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.568936,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.283573,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.790441,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.574804,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043565,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "c241e8e7938bd514461d7bac6e830b8b6b20f527",
          "message": "Phase 6F: fmt adversarial comments and mutation fuzzing — 51,000 inputs, three root causes, and a formatter that reports a syntax error in a file that has none (#2148)\n\n* Phase 6F: fmt adversarial comments and mutation fuzzing\n\nFuzz `kaappi fmt` where its round-trip guard cannot see: comments are not\ndatums, so a comment that moves or vanishes passes `equal?` unnoticed, and\nidempotence is a separate property the guard says nothing about.\n\nAdds `tests/scheme/fmt/fmt-adversarial.sh` (61 fast assertions: 53 comment\nplacements where the layout engine must decide, the blank-line controls, and\nthe parser-depth property) and `tools/fmt_fuzz.py`, the on-demand fuzzer the\nfindings came from — four modes over the repo's own corpus, none of which can\nwrite to a corpus file.\n\nFound kaappi#2141 (stack overflow on a long reader-prefix chain; max_nesting\nguards lists only), kaappi#2142 (non-idempotent when a head-line block comment\ndisplaces a blank-preceded item past hasBodyBlank's index), and kaappi#2143\n(a `#`-led lexeme glued to an identifier splits differently in fmt's lexer\nthan in the reader). Their repros are committed disabled with FAIL markers.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Phase 6F: pin fit-to-width, and file the byte-vs-column gap\n\n`fmt.md` promises \"a form that fits within max_width (80) columns is put on\none line\"; `computeMeasure` returns `node.text.len`, so every non-ASCII lexeme\ncounts double or triple. A 75-column form of twelve five-character Unicode\nidentifiers breaks into 12 lines; the same shape in ASCII stays on one.\n\nCosmetic — measure and the inline emitter are both byte-based, so the fit\npredicate stays consistent and the result is idempotent. Filed as kaappi#2149.\nThe ASCII control is enabled; the Unicode case is committed disabled.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* head -c is not POSIX — OpenBSD generated an empty file and passed it\n\n`repeat() { head -c \"$2\" /dev/zero | tr '\\0' \"$1\"; }` builds the deep-nesting\ninputs. `head -c` is a GNU/FreeBSD extension; OpenBSD answers\n\n    head: unknown option -- c\n    usage: head [-count | -n count] [file ...]\n\nand prints nothing. The 300,000-paren file came out empty, `fmt` accepted it,\nand `expected exit 1, got 0` failed on openbsd-test alone.\n\nSame shape as the no-GNU-regex rule already in tests/scheme/CLAUDE.md: it\npasses on macOS, Linux and FreeBSD, and only the strict leg disagrees. The\nreason it presented as a *depth-limit* disagreement rather than a missing\nutility is that an empty file is valid input, so the failure looked like a\nplatform-dependent nesting cap.\n\n`printf '%*s'` is POSIX, needs no external file, and is faster. 62 passed,\n0 failed locally.\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-02T05:03:47+05:30",
          "tree_id": "ef9fc9c05c7d49995c616e0418b752ba6d659d42",
          "url": "https://github.com/kaappi/kaappi/commit/c241e8e7938bd514461d7bac6e830b8b6b20f527"
        },
        "date": 1785630773842,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.074527,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.663753,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.441839,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.231727,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.003814,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.03495,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.233357,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.04269,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 1.826905,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.932382,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.166055,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.235279,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.307668,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.360511,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.037114,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "337027c2ecc57ed5fb1bcfcf9306b2660573b82c",
          "message": "Phase 6E: thottam audit — 301 assertions, and a nightly tag installs as a release (#2146)\n\n* Phase 6E: thottam audit — 301 assertions, and a nightly tag installs as a release\n\nthottam had 3 tests over 932 lines of package manager that ships on every\nplatform. This adds 233 Zig assertions over the surface that needs no\nnetwork (src/tests_thottam.zig) and 68 end-to-end assertions over the full\ninstall/list/verify/remove/update lifecycle run against a directory of local\nbare git repositories via KAAPPI_ORG (tests/scheme/thottam/, wired into\nrun-all.sh). Both are hermetic: KAAPPI_HOME and KAAPPI_ORG point at\nthrowaway directories, which matters here because `thottam remove` deletes\ntrees.\n\nThe oracle for the constraint operators is SemVer 2.0.0 for what a version\nis and node-semver's range grammar for what ^ and ~ mean, since neither\noperator is in the SemVer spec.\n\nTen issues filed; the assertions that document them are commented out with\nFAIL markers for the fix PRs to re-enable.\n\n  #2130  Semver.parse reads three dot-separated components and discards the\n         rest, and delegates each to std.fmt.parseInt — so Zig's integer\n         literal grammar becomes the version grammar. A tag\n         v2.0.0.nightly-UNRELEASED parses as 2.0.0 and >=1.0.0 installs it;\n         v1_0.0.0 parses as 10.0.0 and outranks v2.0.0. The control is that\n         v2.0.0-rc1 is correctly rejected.\n  #2131  An omitted version component is filled with 0 and then treated as\n         written, so ~1 means 1.0.x rather than node-semver's 1.x.\n  #2132  Six distinct constraint parse failures all surface as \"no version\n         matching X\" — including `>= 1.0.0`, whose space is legal in\n         node-semver, while `>=1.0.0, <2.0.0` parses fine.\n  #2133  A CRLF lockfile makes verify print\n         \"MISMATCH (locked: 75f253e118c0, actual: 75f253e118c0)\" — the \\r\n         is outside the 12-character display prefix.\n  #2134  install pkg@ver on an installed package is a silent no-op, exit 0;\n         update can never move a package off a pin (git pull on a detached\n         HEAD), and one pinned package fails the whole-tree update.\n  #2135  verify iterates the lockfile, not installed.txt: an empty lockfile\n         reports \"All packages verified.\" and exits 0.\n  #2136  remove unlinks .sld files by name with no ownership record, so\n         removing one package deletes a file another still-installed\n         package needs — and verify still reports it OK.\n  #2137  --locked enforces the SHA but not the source URL, then overwrites\n         the lockfile's recorded provenance with the URL it was handed.\n  #2138  kaappi.pkg `source:` and `name:` are parsed and never read.\n  #2144  isValidPkgName guards install and remove only; list, verify and\n         update build paths from names read back out of state files.\n\nNegative results worth not re-testing: a package name cannot escape\n$KAAPPI_HOME via install or remove (the byte-range property test pins the\naccepted set exhaustively), the transitive depends: path is guarded too,\ngit refuses the ext:: transport, and the #614 option-injection guard on\nsource URLs holds.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Address review: fix a vacuous lockfile assertion, and pin --locked's provenance erasure\n\nCodeRabbit's four findings on #2146, all valid:\n\n- The stale-entry check in the updateLockfile round trip searched for\n  \"sha-a\\n\", but an entry that carries a source URL never ends with its\n  SHA, so the assertion could not fail. Now matches the whole superseded\n  line and pins the line count, so an append-instead-of-replace regression\n  is caught.\n- \"isConstraintSpec routes exactly the four operator-led forms\" asserts\n  six (>=, >, <=, <, ^, ~); four is the number of leading *characters* it\n  branches on. Renamed.\n- saved_lock was computed and never used in the --locked section. Using it\n  found a sharper symptom of #2137: a --locked restore does not overwrite\n  the recorded source URL, it ERASES it — doInstall rewrites the entry from\n  parsed.source, which is null when no ::url was given, so a committed\n  lockfile degrades to the org default after one restore. Pinned as a\n  disabled assertion with an enabled control showing the SHA does survive;\n  reported on #2137.\n- The manifest-traversal probe read a fixed /tmp path that a previous run or\n  a concurrent leg could have created. Cleared on both sides.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Probe the local-bare-clone capability instead of assuming it (#2150)\n\nThe lifecycle suite's whole method is pointing KAAPPI_ORG at local bare git\nrepositories, so the install/verify/lockfile path can be exercised with no\nnetwork. That works on macOS and Linux and fails on all three BSD legs:\n\n    Installing kaappi-alpha...\n    Cloning /tmp/tmp.r4La2k2vHN/kaappi-alpha.git...\n    Failed to clone repository\n\ngit is present there (the OpenBSD leg installs it explicitly), the command is\nan unremarkable `git clone --quiet -- <url> <dir>`, and the fixture's own\ninit/commit/clone --bare steps did not fail. I could not identify the cause\nand did not want a red CI or a silent deletion, so the suite now probes the\ncapability directly — create a bare repo, clone it — and exits 77 when that\nfails.\n\nProbing beats hardcoding a platform list: if this is a git-version boundary\nrather than an OS one, or if it gets fixed, the suite resumes on its own with\nno allowlist to maintain. The skip message names #2150 so the coverage loss\nis visible rather than assumed to be intentional.\n\nDistinct from #2149 (head -c is not POSIX), which hit a different suite on\nOpenBSD alone.\n\nLocally unaffected: 69 passed, 0 failed.\n\n* Skip on the real precondition: thottam hardcodes /usr/bin/git (#2152)\n\nThe previous commit guessed that git could not clone a local bare repository\non the BSD legs, and probed for that. The probe PASSED on OpenBSD and the\nsuite still failed — which is what located the actual bug.\n\nthottam_proc.zig:148 invokes git as the absolute path /usr/bin/git on every\nnon-Windows platform. That exists on macOS and CI's Linux images and on none\nof the three BSDs (FreeBSD/OpenBSD put git in /usr/local/bin, NetBSD in\n/usr/pkg/bin), so every git-backed thottam operation fails there. My probe\nused a PATH lookup; thottam does not. That difference was the whole thing.\n\nFiled as #2152, along with the compounding defect that made it hard to see:\nrunGit discards git's stderr, so a missing binary and a real clone failure\nboth print \"Failed to clone repository\" and three runs of CI logs contain no\ngit diagnostic at all.\n\nThe gate now tests the exact path thottam will execute, so it skips precisely\nwhere thottam is broken and nowhere else, and the comment says to replace it\nwith `command -v git` once #2152 makes thottam search PATH.\n\n69 passed, 0 failed locally; `bash -n` clean.\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-02T05:37:48+05:30",
          "tree_id": "a273e63b9c5f586244e56c8b6e2e6bab7a86ee45",
          "url": "https://github.com/kaappi/kaappi/commit/337027c2ecc57ed5fb1bcfcf9306b2660573b82c"
        },
        "date": 1785632054505,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.946468,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.03803,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.571726,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.834079,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.005008,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.045753,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.302166,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.054853,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.303016,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.154802,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.527682,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.304614,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.684751,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.843818,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045392,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "b8003c2401ed3aeddc6c7d68cee48c7e57573bd5",
          "message": "Phase 5G: reactor backend parity — kqueue and epoll agree on all 1593 unit tests, and WASI is executed by nothing (#2153, #2154) (#2158)\n\nThe reactor has four backends behind one API and they must be\nbehaviourally interchangeable. The tracker assumed nothing asserted\nthat; the measurement corrects it. `tests_reactor.zig`'s 23 tests and\n5B's `tests_waitforfd.zig` already run on whichever backend the target\nhas, and CI executes them on three of the four — so parity *is*\nasserted for what they cover. What was missing is a set of contracts\nthat `reactor.zig`'s own doc comments state and nothing checked.\n\n`tests_reactor_parity.zig` adds 15, written against the\nbackend-independent `Reactor` surface and naming no backend, so a\nproperty that holds on one leg and fails on another is a parity defect\nby construction: deadline-ordered timer firing, an already-due deadline\nflooring `effectiveTimeout` at 0, `popExpiredTimers` standalone (the\nscheduler's per-tick path), `isEmpty` with only a timer pending,\n`removeTimer`'s sibling isolation, `poll`'s documented duplicate wake,\na hangup waking *both* directions rather than only the read one, both\ndirections of one ready fd in a single poll, `removeWaiter` actually\nsilencing the removed fiber, a zero timeout probing rather than\nblocking, and a cross-thread notify interrupting a wait without\nconsuming the timer or the fd arming underneath it.\n\n`msFromNs` becomes `pub`: epoll's nanoseconds-to-milliseconds ceil is\nthe one backend-specific rule that is a pure function, so a kqueue host\ncan verify epoll's arithmetic directly — never rounds down, both\nsentinels, and saturation instead of an overflow into a negative\n\"block forever\".\n\nEvery assertion was mutation-tested individually; all 15 mutations were\nkilled. Both backends were executed, not inferred: macOS aarch64\n(kqueue) and aarch64 Linux (epoll) via a cross-compiled test binary in\na container, full suite green on both — 1594/1597 macOS, 1593/1597\nLinux, zero failures. Two findings, neither a live divergence:\n\n- #2153: `zig build test -Dtarget=wasm32-wasi` does not compile (20\n  errors, the 32-bit-usize class of #1912), so `WasiPollBackend` is not\n  even a compile gate, and the one CI step named \"reactor poll_oneoff\n  backend\" covers only the CLOCK path — `arm`, `disarmAll`, `subFd`,\n  the fd branch of `wait` and the whole userspace ONESHOT emulation in\n  `clearInterest` are executed by nothing anywhere. `porting.md`\n  Stage 3 makes \"the fd-readiness unit suites pass\" the acceptance\n  criterion for a backend, so it lists one this backend cannot meet.\n- #2154: the ceil-to-milliseconds rule is written twice by hand, and\n  the Windows copy cites `msFromNs` by name while restating its\n  arithmetic. They agree on every reachable input — the only\n  disagreement is a clamp at 24.9 vs 49.7 days, where an early return\n  is always safe — but only the epoll copy is reachable from a test.\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-02T06:06:14+05:30",
          "tree_id": "06ec0e19ac4713b2638917c9b5ff0e25c4692a00",
          "url": "https://github.com/kaappi/kaappi/commit/b8003c2401ed3aeddc6c7d68cee48c7e57573bd5"
        },
        "date": 1785632733066,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.164388,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.637416,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.435841,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.206107,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00382,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.034726,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.231543,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.042687,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 1.812556,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.905984,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.167241,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.233661,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.314637,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.399086,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.035064,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "98195459f6a0b658295d97c0a3a3543b0008fddc",
          "message": "Phase 7D: golden .sbc bytes, because a paired byte-swap cancels (#2159)\n\nAudit v2, Phase 7D. Refs #1890.\n\n7C broke the writer/reader pairing for the `.sbc` *header* — writer against\nliteral bytes, reader against a hand-assembled little-endian header — and\nhanded 7D the rest: the per-function record and every constant encoding are\nreached only by the round-trip tests in `bytecode_file.zig`, which write and\nread on the same host. A swap present on *both* sides cancels and leaves them\ngreen on every machine, s390x included.\n\n## Field-by-field: nothing is unconverted\n\nEvery scalar in the format goes through a helper, and every `@bitCast` in\neither half is paired with a `nativeToLittle`/`littleToNative`. The two\napparent exceptions are not fields: `readI16FromCode` bitcasts a u16 already\nassembled byte-at-a-time from the code stream (bytecode operands are emitted\n`v >> 8`, `v & 0xFF` and read back the same way, so they are endian-neutral by\nconstruction), and bignum limbs are `[]u64` in little-endian *limb* order with\neach limb serialized whole through `writeU64`. No field is written with a raw\n`asBytes` or an unconverted `@bitCast`. **There is no byte-order bug here** —\nwhat was missing is the instrument that would show one.\n\n## The instrument\n\n`GOLDEN_BODY` in `src/tests_endian.zig`: a committed literal covering\n`func_count`/`top_level_count`, both function records\n(arity/locals/upvalues/variadic/name/code/line table) and all 18 constant\nencodings — fixnum, flonum, symbol, string, boolean, nil, void, eof,\nundefined, char, function reference, pair, vector, bytevector, bignum,\nrational, complex — plus the bundled-files and preamble trailers. Written as a\n`++` chain of one-field-per-line literals so `zig fmt` cannot reflow a value\nacross a line boundary; each line's comment names the value it spells LSB-first,\nand a `comptime` guard rejects a byte-palindrome for the four scalars carrying\nthe argument.\n\nIt is used twice with no contact between the uses: the serializer must\nreproduce it, and the deserializer must decode it. The hand-assembled header\nuses shifts only, never a `@bitCast`, so it cannot inherit the host's byte\norder from the code under test. Neither expected value is a function of the\nhost.\n\n## Mutation evidence\n\n| mutation | `bytecode_file.zig` round-trips | writer golden | reader golden |\n|---|---|---|---|\n| paired: `writeU32` **and** `readU32` flipped | 10/10 **pass** | **fail** | **fail** |\n| writer only (`writeU64`) | fail | **fail** | pass |\n| reader only (`readU32`) | pass | pass | **fail** |\n| byte-reverse one fixture field (the bignum limb) | pass | **fail** | **fail** |\n\nRow 1 is the point: the bug class that is invisible to every existing test now\nfails on every host. Rows 2–3 confirm the two directions are independent —\nneither test can mask the other's mutation. Row 4 confirms the literal is what\nis being asserted.\n\n## SRFI 271 has the identical shape\n\n`tests/scheme/srfi/srfi271.scm` compares two ports on the same host, so it is\nblind to byte order outright: flipping the seed-word read to `.big` leaves it\nat **35/35**. Eight golden assertions in\n`tests/scheme/audit/endianness-audit.scm` (which the s390x leg runs, via 7C's\n`tools/run-endian-suite.sh` step) pin both directions — a literal 32-byte seed\nto a literal 16-byte output prefix and a literal 46-byte state, and separately a\nhand-written literal state to its own literal output. Expected values were\nderived from the published xoshiro256** algorithm, not captured from the\nimplementation, and matched it exactly on the first run. Three mutations\n(`.little`→`.big` in the seed read, in the paired state read+write, and in the\noutput block write) each leave `srfi271.scm` at 35/35 and fail 3–4 of the new\nassertions. The unread-port state is called out explicitly as *the* cancelling\ncase — the words go in and straight back out, so those bytes equal the seed\nunder any consistent order — which is why the assertion after it reads the\nstate one byte in.\n\nAlso pins `sourceHash`/`compilerHashFor` as host-independent: Wyhash reads\nthrough `readInt(..., .little)`, so the cache key is a function of bytes, not of\nhost byte order. Nothing stated that, and a native-load hash would make the key\nhost-dependent with every other test still green.\n\n## The cache-key question: it should include the target\n\nFiled as #2155 rather than fixed. `compilerHashFor` takes the version string\nand the git build id and nothing else — not the target triple — and\n`gitBuildId` has no `-Dtarget` input, so all 17 platform binaries in a release\nshare one key. The load gate checks only magic, VERSION, source hash and\ncompiler hash; the header carries no target field. Meanwhile `cond-expand` is\nresolved at compile time and only the taken branch survives into the `.sbc`\n(measured: the cache entry for a `cond-expand` inside a procedure contains\n`POSIX-BRANCH` and not `WINDOWS-BRANCH`). Honest exposure, since it changes the\npriority: the realistic shared-`$KAAPPI_HOME` pairs all have identical feature\nsets today, so the reachable path is `zig build -Dbundle=out.sbc` with a cross\n`-Dtarget` — a documented workflow where the compiler-hash check silently\npasses.\n\nAlso filed #2156: `kaappi --compile` executes top-level `cond-expand`, `begin`\nand `define-values` bodies for real — a compile-only command that deletes a\nfile — while a bare top-level form, `define-record-type` and code inside a\nlambda are not executed.\n\n## Verification\n\nVerified, little-endian macOS aarch64 ReleaseSafe at `910f7c75`: `zig build\ntest` green; the endian tests green under `-Dgc-stress=true`; `kaappi test\ntests/scheme/audit` 5306/0 and `tests/scheme/srfi` 33937/0; the endian suite\n11/11; `zig fmt --check` and markdownlint clean; every mutation result above\nrun and reverted.\n\nNot verified, by construction: how any of this *behaves* big-endian. No s390x\nexecution was performed here, and a local `zig build test -Dtarget=s390x-linux`\nproves compilation only (`skip_foreign_checks`). The `s390x-test` leg on this PR\nis the first big-endian run of the new assertions — read that check before\nmerging, and treat a failure there as a finding.\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-02T06:10:15+05:30",
          "tree_id": "e61897380d74dbc2a1806e5488aa53459b5c691e",
          "url": "https://github.com/kaappi/kaappi/commit/98195459f6a0b658295d97c0a3a3543b0008fddc"
        },
        "date": 1785633032591,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.29726,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.169655,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.579861,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.99875,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004797,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.047313,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.320439,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057551,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.776925,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.22787,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.57278,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.287638,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.802809,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.659911,
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
          "id": "03ccf6c53c705004b2b9c9190839c9616d282f7e",
          "message": "Phase 7E: gate PRs on gc-stress — 7 min for the unit suite, 12 for the Scheme corpus (#2165)\n\n`-Dgc-stress=true` appeared 0 times in ci.yml (#1898, reconnaissance finding\nF9). It was not absent from CI — fuzz.yml's two gc-stress legs run the same\nunit suite as their pre-fuzz phase — but daily at 02:47 UTC against whatever\nlanded that day, not against the diff that introduced it.\n\nThe premise that kept it out is stale. Measured here, macOS aarch64 under\nload average 4-6 from two concurrent audit units:\n\n  plain       1579 pass, 3 skip     4m\n  gc-stress   1582 pass, 0 skip     7m\n\n1.75x, not the 30x the estimates assumed. The differing skip count is the\ncontrol that the flag applied; `zig build test` prints nothing on success, so\n`--summary all` is now on every unit-test step, including the five existing\nones, where the counts are the only thing distinguishing a passing run from a\nrun that executed nothing.\n\nTwo jobs, both hanging off `format` and running concurrently with everything\nelse: `gc-stress` (unit suite) and `gc-stress-scheme` (the 605-file .scm\ncorpus plus the R7RS suite, through a new tools/run-gc-stress-suite.sh in the\nshape of #2145's run-endian-suite.sh). Two rather than one because the\ncritical path is the 19-minute Debug leg; serialised they would exceed it, in\nparallel each sits inside its shadow.\n\nThree things make it a gate rather than a decoration: `kaappi features --json`\nmust report gc_stress:true before anything runs, the corpus glob has a floor\nso matching nothing cannot read as finding nothing, and the R7RS suite's\ncounts are parsed rather than its exit status -- which is a bug in five other\nlegs (#2157).\n\nMutation-tested: dropping the pushRoot around reader_datum.zig's datum-label\nplaceholder gives `1579 pass, 3 crash` / `test transitive failure` under\ngc-stress and `1579 pass, 3 skip` / `test success` plain, same tree, one flag\napart. An earlier attempt at the textbook #1414 shape was caught by neither --\ngc-stress detects a lost root when the freed object is later marked, not\nmerely read.\n\nThe gate found two real bugs on its first run, both excluded by name until\nfixed: #2160 (primitives_srfi1 buildList reads freed values from its unrooted\nitems slice -- three files abort, including one written to exercise SRFI-1\nunder GC pressure) and #2161 (record_uid_registry keys are borrowed slices\ninto GC-owned strings, so a nongenerative uid stops resolving -- 19\nassertions). Also filed #2162, #2163, #2164.\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-02T06:50:11+05:30",
          "tree_id": "5efa950ea939a53f247413aec8c35d25c92d9d20",
          "url": "https://github.com/kaappi/kaappi/commit/03ccf6c53c705004b2b9c9190839c9616d282f7e"
        },
        "date": 1785636397676,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.263199,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.319449,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.579696,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.981557,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00473,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046123,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.311191,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057383,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.755735,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.23095,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.569749,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.284689,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.799555,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.64892,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044017,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "0bba2a1f114c22816cdce31114c8c5b46d7a7f12",
          "message": "Correct 5F: its Scheme half never ran under gc-stress (#2168)\n\nI reported that 5F ran the Scheme suite against a gc-stress binary on\nx86-64 Linux for the first time, 2061 pass / 0 fail. That is wrong.\n\n`zig build test -Dgc-stress=true` builds *test* binaries. It does not\nrebuild `zig-out/bin/kaappi`, which is what `run-all.sh` executes. On the\ndroplet I had run a plain `zig build` for the sanity check, so the Scheme\nhalf ran against that plain binary and demonstrated nothing about gc-stress.\n\nVerified directly: after `zig build test -Dgc-stress=true`, the installed\nbinary still reports `gc_stress = False`.\n\nPhase 7E found this (#2163) the right way — not by re-reading my claim but\nby noticing the reported timings were arithmetically inconsistent with a\nstressed binary, since three corpus files exceed run-all.sh's 60s budget by\n100x under stress.\n\n5F's unit-suite result stands: 1570/1570 under a genuinely stressed build,\nconfirmed by the 6x slowdown and the differing skip count. Only the Scheme\nhalf was unsupported.\n\n7E's new `gc-stress-scheme` job is what actually closes that gap, and it\nfound two real bugs on its first run (#2160, #2161) — which is the clearest\nevidence that the coverage I claimed did not previously exist.",
          "timestamp": "2026-08-02T07:05:08+05:30",
          "tree_id": "788232f70e4d76757254eb1e3b986040b8857639",
          "url": "https://github.com/kaappi/kaappi/commit/0bba2a1f114c22816cdce31114c8c5b46d7a7f12"
        },
        "date": 1785638096054,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.064231,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.274582,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.461624,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.207746,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004072,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.034804,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.231721,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.043024,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 1.828458,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.904849,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.172182,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.243874,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.308319,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.450899,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.036176,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "dc9215a61bb9287d99925956e2add22bc238043c",
          "message": "Tick the last seven units — every audit unit is complete, 50 of 53 (#2169)\n\nOnly Phase 8 (synthesis) remains. These seven entries are written from each\nunit's report plus my own re-verification of its headline, and where those\ndisagreed the entry says so.\n\nThree findings in this batch came from a unit's own hypothesis being wrong:\n\n- 6E guessed the BSD legs could not clone a local bare repo, built a probe\n  for exactly that, and the probe PASSED while the suite still failed. That\n  falsification located #2152 — thottam hardcodes /usr/bin/git, so the\n  package manager is non-functional on three platforms it ships for.\n- 5A found the reconnaissance had credited the wrong guard for a claim that\n  is genuinely retired, and then found a live crash (#2129) on a fourth\n  entry path nobody had written down.\n- 7E's own first mutation was caught by neither build, which is what taught\n  it that gc-stress detects a lost root when the object is later marked,\n  not merely read.\n\n7C is the only unit in the whole campaign that confirmed both of its\ntracker claims rather than correcting one.\n\nAnd 7E's #2163 caught my own false claim about 5F's Scheme half, corrected\nin #2168 — that entry now carries the correction inline rather than the\noverclaim.",
          "timestamp": "2026-08-02T07:09:51+05:30",
          "tree_id": "28776d8ef31a71650481c399b8ad4e224cb40744",
          "url": "https://github.com/kaappi/kaappi/commit/dc9215a61bb9287d99925956e2add22bc238043c"
        },
        "date": 1785639571409,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.405634,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.654756,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.595402,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.114359,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004814,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046261,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.311183,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057505,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.779518,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.232598,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.578423,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.291188,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.790371,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.667007,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044353,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "d2b4e01aa6de212a988405dd56341f3ea0af93aa",
          "message": "Make eqv? respect complex exactness flags and keep negation exact (#2170)\n\nR7RS 6.1 requires (eqv? a b) => #f when one number is exact and the\nother inexact, but all four eqv?-semantics comparators (eqv?, equal?,\nmemv/assv, SRFI-69 eqv tables; case rides on eqv?) bit-compared a\ncomplex's f64 components and ignored exact_real/exact_imag, so\n(eqv? (make-rectangular -3/2 -1) -1.5-1.0i) was #t. They now share\none types.complexEqv so the copies cannot drift apart again; the\nbitwise component rule (NaN, signed zero) is unchanged.\n\nNegation lost exactness the same way: (- z) went through the\nflag-less f64 rebuild and returned inexact where R7RS — and the\nadvertised exact-closed/exact-complex features — require exact.\nUnary (- z) and (- 0 z) are the two rounding-free cases, so they now\npreserve the flags, normalizing an exact zero component to +0.0. The\nrest of complex arithmetic still collapses to inexact: that is the\nf64-backed representation problem #2166 tracks, and preserving flags\nthere would relabel rounded results as exact.\n\nTwo audit-suite expectations ((+ 1+2i 2+2i) => 3+4i and\n(* 1+2i 3+4i) => -5+10i) had passed only because the broken equal?\nequated their inexact actuals with the exact expected values; they\nare now named and test-expect-fail pending #2166.\n\nFixes #2167. Interim slice of #2166.\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-02T02:28:07Z",
          "tree_id": "9c34105444d15ddc1d7c7eb3ab5f9fc0c3927876",
          "url": "https://github.com/kaappi/kaappi/commit/d2b4e01aa6de212a988405dd56341f3ea0af93aa"
        },
        "date": 1785640483449,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.273095,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.10558,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.567934,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.941909,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004759,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046272,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.312712,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.056177,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.656389,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.262808,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.571103,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.276048,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.767748,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.625116,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043076,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "ad53bc2a886065a0b1ad021b40125466cbaed8d2",
          "message": "Phase 8: synthesis — 170 issues are 35 root causes, and the most repeated one is a check that tests nothing (#2171)\n\n* Phase 8: synthesis — 170 issues are 35 root causes, and the most repeated one is a check that tests nothing\n\nThe campaign filed 188 issues across 53 units. A pile that size is raw\nmaterial, not a result, so this adds a `## Findings` section recording what\nit concluded: every open issue assigned to one of 35 root-cause groups, a\nprioritisation with its reasoning visible, the deduplication recommendations,\nand the `;; FAIL:` marker inventory.\n\nThree hypotheses carried into the unit were disproved, which is the more\nuseful half. SRFI 166's 11 issues do not share a root cause: routing the\nthree the tracker names as derived through the working procedural mechanism\nstill gives the wrong answer, so the failures are consumer-side and there are\n11 separate procedures to write. The arity issues are four unrelated\nmechanisms, though a real structural finding survives them — three sites\nhand-roll frame setup instead of routing through callClosure, and each\ninherits none of its validation.\n\nThe open count is 170, not 168: two issues had fallen out of both tracking\nqueries and were recoverable only through the disabled-test markers.\n\nTwo findings are new here. The segment-at-n=0 class has four members, not\ntwo — string-segment and range-segment hang identically and are unfiled,\nwith SRFI 171's tsegment as the control proving it is a missing precondition\nrather than an inherent shape. And isSpecialTopLevelForm is a fourth\nhand-maintained parallel list, which disappears if the top-level dispatcher\nis split into classify and run.\n\nTracking issue: #1890\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Correct two counts in the Findings section\n\nReview caught both. The marker inventory said 435 lines in 35 files; the\ndefensible count over .scm files, matching the documented `;;+ FAIL: #NNNN`\nconvention, is 434 in 36 — the earlier figure came from a looser grep, and\nthe file count had dropped the one file whose three markers use `;;;`. Both\nspellings are now counted and stated.\n\nAnd \"two issues were reachable only through the disabled-test markers\" was\nwrong about which: 2129 is found by the `audit` label query, and only 1920\nneeds the markers. 1870 is the third case — footer, no label — so the honest\nstatement is that no single query finds every campaign issue.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-02T08:38:42+05:30",
          "tree_id": "91afe839c3094c612c21e47203f9b98a50794f10",
          "url": "https://github.com/kaappi/kaappi/commit/ad53bc2a886065a0b1ad021b40125466cbaed8d2"
        },
        "date": 1785642465143,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.261677,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.175552,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.576768,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.93471,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004799,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046593,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.311144,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.056336,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.605735,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.233148,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.578445,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.281905,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.791596,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.537989,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044209,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "72c8e472a068d417700dede1daa9bc7b8a36f1c8",
          "message": "Close the campaign at 53 of 53, and correct the claim Phase 8 disproved (#2173)\n\n* Close the campaign at 53 of 53, and correct the claim Phase 8 disproved\n\nEvery unit is done. 186 issues filed, grouped into 35 root causes.\n\nPhase 8 was asked to refute the leads it was handed rather than confirm\nthem, and it refuted three — including one that was mine and had landed in\na merged tracker entry. I claimed SRFI 166's 11 issues shared close to one\nroot cause. Phase 8 disproved that by experiment, not argument: routing the\nsupposedly-derived issues through the working procedural mechanism still\ngives wrong answers, so the failures are consumer-side. Eleven distinct\ncauses. The 3.5 entry now carries the correction above the original reading\nrather than quietly replacing it.\n\nThe synthesis's priority argument is worth repeating because it is the\ncampaign's central finding stated as an action: fix the\ngreen-but-tests-nothing class FIRST, because until failure is detectable\nevery other fix's regression test is of unknown value. Five structurally\ndifferent mechanisms, including 1,395 R7RS assertions gating nothing on\nfive CI legs.\n\nIt also found two structural items nobody had filed: isSpecialTopLevelForm\nis a fourth hand-maintained parallel list, and the segment-at-n=0 class has\nfour members, not two (#2172, verified — string-segment and range-segment\nhang while SRFI 171's tsegment raises correctly, which is what proves a\nmissing precondition rather than an inherent shape).\n\nThe marker convention held: 101 distinct numbers and none cites a closed\nissue. Two blind spots worth knowing — one marker cites a merged PR rather\nthan an issue, which a mechanical audit reads as done, and three use ;;;\nso a grep for the documented convention misses them.\n\n* Reconcile the counts CodeRabbit flagged — both were real\n\nTwo inconsistencies, both genuine, and checking them turned up the actual\nreason rather than just making the numbers agree.\n\n186 vs 188. The campaign filed 188 issues; 186 carry the footer. The three\nthat do not — #2129, #1870, #1920 — are exactly the ones Phase 8 flagged as\nrecoverable only by label or by the ;; FAIL: markers, so the discrepancy was\ncarrying real information. The status line now states both and names them.\nLast updated moved to 2026-08-02 to match.\n\nR25's \"8 issues\" vs 3.5's \"11 distinct causes\". Both correct, different\npopulations, and the doc said neither. Verified against the synthesis\ncomment's own group lists: Phase 3.5 filed 11 SRFI 166 issues; R25 holds 8,\nbecause #2062 and #2066 regroup into R21 (byte vs codepoint vs column) and\n#2067 into R11. That is the regrouping doing its job — three issues filed\nunder one library turned out to belong to cross-cutting themes — so the two\ncounts are now stated with what each measures.\n\nmarkdownlint clean.",
          "timestamp": "2026-08-02T08:46:50+05:30",
          "tree_id": "410dd999a710ca0204709b96229521aa9f1b9745",
          "url": "https://github.com/kaappi/kaappi/commit/72c8e472a068d417700dede1daa9bc7b8a36f1c8"
        },
        "date": 1785642764992,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.2513,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.492285,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.597672,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.934456,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004696,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.047018,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.309653,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.056302,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.657127,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.215179,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.599123,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.283662,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.78777,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.685903,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.04422,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "39ae79684bb8bb00915186894111d950dc7a96e7",
          "message": "Make (read port) safe across the 4096-byte chunk boundary (#2174)\n\n* Make (read port) safe across the 4096-byte chunk boundary\n\nThe incremental read loop refills on exactly UnexpectedEof and treats\nevery other parse outcome as final. Tokens straddling a chunk boundary\nbroke that contract both ways: scanners that reported truncation as a\ndifferent error made valid files unreadable (strings #1893, dotted\npairs #1920, split UTF-8 codepoints #1945, raw/byte strings and #-\nprefixes #1940), and scanners that treated end-of-buffer as a token\nterminator silently split symbols, numbers, characters and booleans --\nand fed a line comment's tail back in as program data (#1940).\n\nInstead of per-site patches, Reader gains one mode: incomplete_input,\nset only by readDatumFn's chunk loop, under which any scan that stops\nat end-of-slice (rather than at a delimiter or closing character)\nreports UnexpectedEof -- never finalize a token more bytes could\nextend, never reject one more bytes could complete. Deferral loses\nnothing: the whole-input parse at fd EOF keeps today's precise errors,\nand every other Reader user leaves the flag off.\n\nAlso, per #1920's analysis: exhausted input where ')' belongs is now\nUnexpectedEof in every mode; the read procedure's error object names\nwhat failed (\"read error: unterminated string literal\") instead of a\nbare \"read error\"; a trailing #!directive yields the EOF object rather\nthan a spurious read error (new Reader.readDatumOrEof); and a buffer\nholding a directive is never discarded by the loop, so fold-case\nsurvives the boundary.\n\nOne deliberate semantic change: a bare atom on a still-open pipe with\nno delimiter now waits for one instead of returning immediately --\nthat early return was the split bug. Newline-terminated interactive\ninput is unaffected (#847 behavior preserved, regression-tested).\n\nCloses #1893. Closes #1920. Closes #1940. Closes #1945.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n* Exclude the boundary sweep from the gc-stress Scheme gate as too-slow\n\nreader-port-refill-gaps.scm runs ~800 chunk-boundary fixtures, each an\nincremental read re-parsing a 4 KiB buffer per refill -- ~1 s plain,\nexit 124 at the 900 s stress timeout. Category (a) of the job's own\nskip taxonomy; the incomplete-input mode it guards keeps stress\ncoverage via tests_reader_incremental.zig in the gc-stress unit job,\nand the file itself still runs unstressed on every other leg.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-02T05:08:45Z",
          "tree_id": "0faa2f5a95414540aaca7e846062abe7bd2704ca",
          "url": "https://github.com/kaappi/kaappi/commit/39ae79684bb8bb00915186894111d950dc7a96e7"
        },
        "date": 1785649164388,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.337419,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.260278,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.571827,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.036931,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004675,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046665,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.312995,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.056308,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.682985,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.216165,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.574831,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.285287,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.794862,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.623852,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042993,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "18c9b05b23a30d63e2aa51e6d436c653c932f92d",
          "message": "Make SRFI 41 stream-map and stream-for-each variadic (#2178)\n\nSRFI 41 specifies both as (proc strm strm ...), and the document's\ncenterpiece example — the self-referential Fibonacci stream — depends\non the two-stream form:\n\n  (define fibs\n    (stream-cons 0 (stream-cons 1 (stream-map + fibs (stream-cdr fibs)))))\n\nBoth were defined with a single fixed strm parameter, so that example\n(and any multi-stream call) raised KP3003. The fix walks all streams in\nstep using the same any-null?/map-over-cars pattern stream-zip already\nuses, terminating at the shortest input per the spec. Requiring the\nfirst stream positionally keeps the spec's \"at least one stream\"\nprecondition as a natural arity error.\n\nRegression tests pin the fibs example plus two- and three-stream map,\nshortest-stream termination for both procedures, unary calls, and\nlaziness over infinite inputs.\n\nFixes #2176\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-02T11:36:11+05:30",
          "tree_id": "c55965cc18bdbabb1b882066e1ec8e4a547bb741",
          "url": "https://github.com/kaappi/kaappi/commit/18c9b05b23a30d63e2aa51e6d436c653c932f92d"
        },
        "date": 1785652779836,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.344001,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.032625,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.568976,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.000906,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004626,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046978,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.314453,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.056306,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.540724,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.220833,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.571931,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.279931,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.815307,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.604702,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042619,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "fed39ec857d9b4a3d50be3a34b1cc12c271ad02e",
          "message": "Complete SRFI 42: generic ':' dispatch, :real-range, :char-range, :dispatched (#2180)\n\n* Complete SRFI 42: generic ':' dispatch, :real-range, :char-range, :dispatched (#2177)\n\n(list-ec (: i 5) i) — the first form in every SRFI 42 tutorial — was\nKP2001 invalid syntax: the port implemented eleven typed qualifiers but\nnot the generic ':', nor :real-range, :char-range, or :dispatched.\nInvestigating also showed three qualifiers the library already\nexported — :port, :do, and :parallel — had no %do-ec rules at all and\nfailed identically inside a comprehension; all three work now.\n\nThe port is direct-style (nested loops around the body with a stop\nflag), not the reference's CPS design, so ':' cannot dispatch by :do\nfusion. It instead uses the SRFI's own runtime protocol: a dispatcher\nmaps the evaluated argument list to a generator procedure g, stepped as\n(g empty) until it returns the eq?-unique sentinel. The initial\ndispatcher covers the spec's cases (lists, strings, vectors,\nexact-integer ranges, real ranges, char ranges, ports), and the\nextension surface is complete — :-dispatch-ref, :-dispatch-set!,\nmake-initial-:-dispatch, dispatch-union, :generator-proc — so user\ndispatchers compose per spec. :generator-proc compiles the standard\ntyped generators straight to closure constructors; any other form falls\nback to a call/cc coroutine over do-ec. Typed generators now also\naccept multiple arguments ((:list x '(1 2) '(3)) concatenates),\nmatching both the spec and the runtime dispatch path.\n\nDocumented deviations (library header): no (index i) form, and\n:parallel accepts only single-variable sub-generator forms — raw :do\nand :while/:until-wrapped generators are rejected at expansion time\nrather than merged. The reference implementation's\nmake-initial-:-dispatch tests (string? a1) twice where a2/a3 were\nmeant; corrected here.\n\nFixes #2177. The pre-existing eager termination gap in\nfirst-ec/any?-ec/every?-ec found during this work is tracked\nseparately as #2179.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n* Reject a zero step loudly in :range and :real-range (PR #2180 review)\n\nThe review's :range finding is real: %gen-range (new in this PR,\nreachable via (: i 5 3 0) and (:generator-proc (:range 5 3 0))) never\nadvances with a zero step, so from > to yielded the same value forever.\nThe macro arm predates the PR but behaves identically, and the reference\nimplementation rejects a zero step in :range explicitly — this port had\nsilently diverged. Both paths now raise the reference's exact message,\n\"step size must not be zero in :range\".\n\nThe :real-range findings were half right: an exact zero step already\nraised a loud, catchable division-by-zero at setup — byte-for-byte the\nreference's behavior, whose :real-range has no zero-step check — but the\nreview's own inexact example (: x 0.0 1.0 0.0) would not have \"failed at\nsetup\" at all: (/ 1.0 0.0) is +inf.0, so istop = +inf.0 and the loop\nnever terminates, in the reference too. That silent case is the one\nworth closing: %gen-real-range and the macro arm now reject a zero step\nexplicitly, documented in the library header as a deliberate deviation\nbeyond the reference.\n\nSeven regression tests pin the macro, generic-dispatch, and\n:generator-proc routes for both generators.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n* Scope :while/:until to the wrapped generator; add nested/begin (PR #2180 review)\n\nCodeRabbit's major finding is real and spec-verified: (:while (gen ...)\ntest) rewrote to (gen ...) (:while test), and the bare form sets the one\ncomprehension-wide stop flag — so a failing test ended every enclosing\nloop, where the spec scopes it to the wrapped generator only.\n(list-ec (:range j 2) (:while (:list x '(1 2 3)) (< x 2)) (cons j x))\nreturned ((0 . 1)) instead of ((0 . 1) (1 . 1)). The wrap rules now give\nthe wrapped generator a private stop flag, with translator qualifiers\n(%while-xlate/%until-xlate) that re-thread the enclosing flag for the\nrest of the chain and mirror an ambient stop into the private flag, so a\nbare :while/:until deeper in still ends the wrapped loop. The bare forms\n— this port's extension, absent from the spec's grammar — keep their\nstop-everything meaning, now documented in the header and pinned by\ntests.\n\nIts minor finding asked to document \":nested\"; the spec spells the\nqualifier (nested ...) — no colon — and has a sibling (begin ...)\ncommand qualifier the review missed. Both are one rule each in this\ndirect-style design, so they are implemented rather than documented\naway.\n\nThose four rules pushed %do-ec to 35 rules, over the engine's 32-rule\nsyntax-rules cap, which rejects the whole definition as a bare\nInvalidSyntax (filed as #2184). The qualifier processor is now split:\n%do-ec keeps the generators and forwards anything else to %do-ec-more\n(grouping, command, control, and guard qualifiers).\n\nTest-side findings, all accepted: upto-dispatcher now honours the\nzero-argument identification convention and a test observes it through\nthe failure path's error irritants; the stale \"keep last\" comment is\ntrue again (the dispatcher-mutating block moved to the end of the file,\nso every earlier ':' test hits the unmutated dispatcher);\ndispatch-union's conflict branch has a regression test; and the\n3-argument string/vector dispatch branches — the reference-typo\ncorrection — are pinned, including the mixed-type case that actually\ndiscriminates the fix (three well-typed strings pass under the typo\ntoo). Also adds the :generator-proc zero-step case for :real-range.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-02T07:55:53Z",
          "tree_id": "e7e831e59f8295f888dfd98b1efb33d7046f9ef8",
          "url": "https://github.com/kaappi/kaappi/commit/fed39ec857d9b4a3d50be3a34b1cc12c271ad02e"
        },
        "date": 1785658967105,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 2.248598,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 5.555884,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.282112,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 1.530214,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.002868,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.023785,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.144537,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.027852,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 1.259041,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.580577,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 0.804343,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.192101,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 0.909091,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.210062,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.024902,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "e77bbf7b264609de34831718c2dc56868263870d",
          "message": "Route reader #e/#i through string->number's digit-exact parser (#2181)\n\nThe reader and string->number each had their own applyExactness with\nstructurally different strategies: string->number rebuilt exact values\nfrom the decimal digits (mantissa x 10^scale via bignum) while the\nreader parsed to f64 first and un-rounded it with an i64 continued\nfraction under an absolute 1e-15 tolerance. R7RS 6.2.7 requires the two\nto agree, and every past fix (#79, #419, #604, #751, #1891) had landed\nin one copy at a time.\n\nstringToNumber's body is now the pub parseNumberText, and an\nexactness-prefixed number body in the reader becomes a prefixed_real\ntoken whose span datum construction re-parses through it — the\ntokenizer still runs first, so token boundaries and incremental-input\nsemantics are untouched, and the two parsers cannot diverge on #e/#i\nagain by construction. The reader's f64-unrounding conversion is\ndeleted. Complex tokens are the one exception (readNumber's complex\ngrammar is wider than parseNumberText's): exactness there is exactly\nthe two flags, with #e refusing non-finite parts.\n\nFixes, one per issue: #1891 (#e dropped past i64), #1907 (panic at the\n2^63 guard's off-by-one, aborting check/fmt/ast), #1908 (#i radix\nbignums read as decimal), #1909 (sub-1e-15 collapse to exact 0), #1910\n(Complex arms on both applyExactness sides plus exact-component\nprinting at any magnitude, so #e1e19+1i round-trips instead of writing\n0/0), #1921 (string->number rejecting the unprefixed 2^63 decimal),\nand the #e+inf.0 parity gap (now a read error, matching #419's #f).\n\nThe tiny exact-complex round-trip gap surfaced in review is pinned in\nboth directions and sequenced as #2183 then #2182 — the reader grammar\nextension must wait for the scaled rational->f64 conversion or the\nprinted form would read back as a silent 0.0.\n\nCloses #1891, closes #1907, closes #1908, closes #1909, closes #1910,\ncloses #1911, closes #1921.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-02T14:01:18+05:30",
          "tree_id": "761dfde96f16b91a8f28a8acc419740fcaf16ed0",
          "url": "https://github.com/kaappi/kaappi/commit/e77bbf7b264609de34831718c2dc56868263870d"
        },
        "date": 1785661129212,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.300078,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.94211,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.56797,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.009793,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00468,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046769,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.314975,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.056449,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.627618,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.222602,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.582356,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.276255,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.783741,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.610414,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043114,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "67fc69d0950091602a0c3ba778cdc9bef362aa68",
          "message": "Fix the uncatchable-abort family: record sizing, devfs stat, SRFI-18 timeouts, 255-arg calls (#2186)\n\n* Fix the uncatchable-abort family: record sizing, devfs stat, SRFI-18 timeouts, 255-arg calls\n\nAll four are one root cause — unguarded narrow arithmetic or conversion\nat a representation boundary — each an exit-134 process abort reachable\nfrom an ordinary program, invisible to guard.\n\n#1973: allocRecordInstance sized its allocation as\n`num_fields * @sizeOf(Value)` in u8 arithmetic (num_fields is a u8), so\nthe first instantiation of any record with >= 27 fields aborted; under\nReleaseFast it would instead corrupt GC accounting silently. Widened to\nusize. parseRecordSpec also admitted 256-field specs whose later u8\n@intCast aborted at definition time; capped at 255 to match the R6RS\nparser. The three audit assertions disabled against this are re-enabled,\nplus new ceiling pins: 254 fields is the construction ceiling everywhere\n(the rtd+fields call hits the 255-arg ISA limit), loudly.\n\n#1976: doStat @intCast a signed dev_t (i32 on macOS/OpenBSD) into u64,\nso file-info aborted on every devfs path — macOS /dev/null stats as\nst_dev = -1296473318. New devToU64 reinterprets the bits as unsigned\nbefore widening (a device id is an opaque identity, not a quantity),\napplied to dev and rdev on both stat branches. The audit's disabled\ndevfs assertions are re-enabled.\n\n#1983: seconds->time, thread-sleep!, and timeoutToDeadlineNs converted\nuser-supplied numbers with unchecked @intFromFloat / u64 multiplies.\nTwo deliberate behaviors now:\n- seconds->time raises a catchable KP3007 outside [-2^63, 2^63)\n  (including inf/nan) — it constructs an observable value, so clamping\n  would silently build a wrong time. The bound is written 0x1p63\n  exactly; @floatFromInt(maxInt(i64)) rounds up and would re-admit the\n  first aborting value (the same off-by-one-ULP shape as #1907).\n- Timeouts saturate (*|, +|, std.math.lossyCast): +inf.0 and any\n  beyond-range duration or far-future time object mean \"never times\n  out\", the SRFI-18 convention (Gambit), continuous with #f. NaN stays\n  0 as before. timeoutToDeadlineNs is pub and shared with\n  (kaappi fibers), so this also fixes channel-send/receive timeouts.\nThe audit file's disabled abort cases are re-enabled under the new\ncontract, and its stale \"TODAY\" NaN pin updated.\n\n#2185 (found by sweeping for sibling sites while fixing #1973):\ncallClosure computed `nargs + 1` in u8, aborting every 255-argument\ncall — the ISA's own maximum; three tail-dispatch paths computed a\nvariadic callee's `arity + 1` rest-slot count the same way; and both\ncompileLambda copies (compiler_lambda.zig and the live IR path in\ncompiler_ir.zig) overflowed their u8 arity counter on a 256-parameter\nlambda, aborting at compile time — including from `kaappi check`. Calls\nwidened to usize; a 256th fixed parameter is now a clean KP2001\n(InvalidSyntax, not TooManyLocals, which surfaces as a KP9001\n\"internal error — report this bug\" and would blame kaappi for user\nsyntax).\n\n#1907 (reader #e panic at 2^63) needed no code here: verified fixed by\n#2181 on this branch — read, check, ast, and fmt all handle the\nformerly-aborting literal, and both boundary values are pinned by\n#2181's tests.\n\nRegression tests: tests_records.zig (27/254/255/256-field ladder),\ntests_filesystem.zig (devfs), tests_srfi18.zig (seconds->time bounds,\ntimeout saturation), tests_fibers.zig (channel timeout, unbounded sleep\nparks with progress pinned), tests_core_eval.zig (255-arg direct/tail/\napply x exact/variadic, 256-param rejection), plus scheme suites\nsrfi170-devfs-1976.scm, srfi18-timeout-saturation-1983.scm,\ncall-255-args-2185.scm and the re-enabled audit assertions.\n\nCloses #1973. Closes #1976. Closes #1983. Closes #2185.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n* Address PR #2186 review: single saturating-conversion helper, tolerant /dev/fd pin\n\nExtract saturatedNsFromSeconds, shared by timeoutToDeadlineNs's number\nbranch and threadSleepFn. #1983 existed as three diverged copies of this\nexact conversion, so a future policy change (say, to NaN handling) must\nhave a single edit point; the helper's doc records why the two sites'\nhistoric @max spellings were equivalent, making the unification visibly\nbehavior-preserving.\n\nThe audit's re-enabled /dev/fd assertion no longer requires the path to\nresolve: on Linux it is a symlink into /proc, which a minimal environment\nmay not have mounted. It still pins 'directory wherever /dev/fd does\nresolve — dropping that entirely would lose the assertion's dev-vs-rdev\ndiscriminating role — and accepts only a catchable failure otherwise,\nnever the abort #1976 fixed.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-02T10:35:23Z",
          "tree_id": "df04952741bac1c99f7918293d27dff0442cc151",
          "url": "https://github.com/kaappi/kaappi/commit/67fc69d0950091602a0c3ba778cdc9bef362aa68"
        },
        "date": 1785668634448,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.291526,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.11757,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.580341,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.989124,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004637,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046691,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.311422,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.056474,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.737304,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.219034,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.585378,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.281098,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.787294,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.614896,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043378,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "53a989b4f612cbcff2b5ed403551ef468aca3508",
          "message": "Make the .sbc cache transparent: format v11, honest write gating, target-keyed compiler hash (#2188)\n\n* Make the .sbc cache transparent: format v11 + honest write gating\n\nSix cache defects, one root theme: a HIT behaved differently from a MISS.\n\nFormat v11 (bytecode_file*, #2110 #2111 #2113):\n- Pair/string/vector/bytevector constants carry their immutability byte,\n  so a set-car! on a literal raises KP3002 warm exactly as cold (#2110).\n- A shareable constant reached twice is emitted once and referenced via\n  TAG_BACKREF, so datum-label sharing keeps eq?, shared DAGs stay linear\n  on disk (a 20-level DAG drops 4.7 MB -> 474 B), and cyclic literals\n  terminate and load (#2111).\n- List spines are walked iteratively on both halves — depth counts\n  nesting only — so a quoted list past 257 elements is cacheable; and\n  the writer now refuses (never truncates) anything the reader would\n  reject, so an entry that recompiles forever cannot be written (#2113).\n\nCache gating and reporting (main.zig, cache.zig):\n- A file whose compilation registered a macro or syntax property is not\n  cached (--timings: \"define-syntax\") — a HIT compiles nothing, so a\n  top-level define-syntax/define-property was invisible to run-time\n  eval (#2112). Detection is semantic (table-count snapshots around each\n  form), so a macro expanding into define-syntax is covered too.\n- A file with a top-level compile error is not cached (\"compile error\")\n  — the warm run used to execute the partial program with exit 0 and no\n  diagnostic (found during this work; probe cache-compile-error.scm).\n- The HIT path feeds runtime errors the same per-form fallback line\n  (Function.source_line) the fresh path uses, so errors with no\n  line-table entry keep their file:line and snippet (#1922).\n- cache status dry-runs each current-build entry's body and reports one\n  the reader rejects as \"unloadable\" instead of \"current\" (#2113).\n\nCache key (#2155): compilerHashFor gains a target component — the triple\nplus types.platform_features — so the 17 release binaries built from one\nclean checkout no longer share a key, and a cond-expand-bearing .sbc\ncompiled on POSIX is a loud miss for a Windows binary instead of silently\nrunning the wrong branch.\n\nThe differential harness's KNOWN_DIFFS and KNOWN_NEVER_HIT lists are both\nempty now; the five probes stay in the corpus as regression probes, so\nany of these divergences coming back fails the run. Docs: cache.md gains\nthe target key component, the full refusal list, the unloadable state,\nand a transparency-guarantees section.\n\nCloses #1922, closes #2110, closes #2111, closes #2112, closes #2113,\ncloses #2155.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n* Extend writer/reader limit parity to the bundle sections (review)\n\nCodeRabbit review of #2188, all three findings taken:\n\n- writeFileWithBundle now refuses (LimitExceeded) a bundled-file count,\n  bundled path/content length, preamble count, or preamble form length\n  the reader would reject, completing the parity the v11 header comment\n  claims — the gap was --compile artifacts, not the auto-run cache\n  (which writes both sections empty), so the failure mode was a bundle\n  that only fails at run time as \"invalid embedded bytecode\", not an\n  invisible permanent miss. The path cap also makes the u16 length cast\n  unreachable (it could panic in ReleaseSafe on a >65535-byte path).\n  The reader's magic 4096s become shared MAX_BUNDLED_FILES /\n  MAX_PREAMBLE_FORMS constants, and a unit test pins refusal, no\n  file-on-disk, the in-bounds round-trip, and double-free safety.\n\n- freeDeserializeResult resets funcs alongside bundled_files/preamble,\n  so all three fields are uniformly safe against a second call.\n\n- timings-1515.sh asserts the \"compile error\" refusal reason, matching\n  the coverage the other two new reasons already had (kaappi#2187).\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-02T11:51:08Z",
          "tree_id": "64b3821fc021cad21dc9f6b86242ac296541cddc",
          "url": "https://github.com/kaappi/kaappi/commit/53a989b4f612cbcff2b5ed403551ef468aca3508"
        },
        "date": 1785673432818,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.319065,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.928382,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.571273,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.028937,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004657,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046632,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.313994,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.058127,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.65308,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.229475,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.586626,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.279474,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.800902,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.569061,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043171,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "aa4f8887e9bb8a32ae73ace6a22bf39972622202",
          "message": "Split vm_dispatch.zig and fiber.zig under the 1500-line policy (#2189)\n\nBoth had crossed the 1500-line file-size limit (1531 and 1530), the\nfirst non-exempt files to do so since the 2026-07-30 sweep. Each is cut\nalong the seam its own structure suggests, as pure code motion:\n\n- vm_dispatch.zig keeps runUntil (the hot dispatch loop) and its\n  loop-control helpers; the support layer the opcode arms call —\n  operand/bytecode readers, register-window validation, the shared\n  global-resolution helper (kaappi#1831/#1860), the noinline error\n  raisers, buildRestList — moves to vm_dispatch_helpers.zig.\n- fiber.zig keeps the Fiber/FiberScheduler structs and scheduling\n  core; the blocking-wait machinery — waitForFd, wakeIoWaitersOnFd,\n  IoWait, parkOnReactor, and the shared in-place scheduler drive\n  runSchedulerStep — moves to fiber_wait.zig.\n\nSame-name re-exports keep every unqualified call site and external\nvm_dispatch.X / fiber.X reference resolving; visibility widens only\nwhere the file boundary requires it. The one non-motion change: the\ntwo debug-pause wrappers are dropped in favor of calling vm_debug\ndirectly at their single call site. tests_gc_tracing.zig (1720) is\ndeliberately not split — a flat list of independent per-type test\nblocks is the breadth the policy exempts.\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-02T12:06:29Z",
          "tree_id": "dd3e53691bb0018203b94d3468fdbf40c5f56bf0",
          "url": "https://github.com/kaappi/kaappi/commit/aa4f8887e9bb8a32ae73ace6a22bf39972622202"
        },
        "date": 1785674217981,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.949649,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.218807,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.57374,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.882515,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004892,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.044709,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.292572,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.05533,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.394153,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.153756,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.534883,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.30769,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.727792,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.786498,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045682,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "bfd73a166e5020873ab96aaab58050e040264f68",
          "message": "Make the printer exact, iterative, and cycle-safe; unalias write-simple (#2190)\n\n* Make the printer exact, iterative, and cycle-safe; unalias write-simple\n\nThe printer silently truncated at fixed 1024-entry limits, recursed on\nthe native stack, and its cycle pre-pass walked fewer containers than\nits print arms did. Audit v2 Phase 1D/4D turned that into four\nuser-visible failures: an exact rational at nesting depth 1023 printed\nas `.../...` and read back as a symbol (#1953); a cycle reached only\nthrough an error-object irritant or a mutex/condition-variable name\nhung write, display, write-shared and write-simple alike (#1954);\nwrite-simple was registered as `&write`, so it emitted datum labels the\nspec forbids (#1955); and on wasm32 the recursion exhausted the 16 MiB\ndefault shadow stack at depth 848 -- an uncatchable module abort --\nwhile the depth guard sat at 1024, calibrated to the native 64 MB stack\nthat build.zig never gave the wasm module (#2107). #1902 (closed,\ndecomposed into the first three) catalogued the truncation cliffs.\n\nOne fix serves all of them because they were one design problem: the\nprinter now runs a single iterative, label-aware engine over a\nheap-allocated task stack, with hashmap-based detection (cycle targets\nfor write/display, all repeated containers for write-shared) that\nenumerates children through the same `childAt` the engine uses -- so\ndetection and printing can no longer disagree about which edges exist,\nno capacity or depth constant remains on the exact path, and no native\nstack is consumed regardless of nesting. Rationals render atomically\n(their parts are always exact integers), so no depth seam can split\nthem. write-simple gets its own implementation: label-free by\ndefinition, and a catchable error on cyclic input where the spec\nanticipates non-termination -- loud beats a wedged process. The wasm\nmodule also gets the same 64 MB stack as every native executable, so\nthe remaining native-stack recursions (reader nesting, REPL layout)\nkeep the headroom their guards assume.\n\nThe bounded `printValue` survives as the diagnostic printer (compiler\nmessages, REPL layout probes) -- now iterative and spine-ticking, which\nalso ends the REPL wedge on cyclic values at narrow widths (#859's\nsurviving tail). The pretty-printer moves to printer_pretty.zig under\nthe 1500-line policy.\n\nAll 16 formerly-disabled assertions in printer-gaps.scm are re-enabled\n(reworded where the old expectation pinned the bug), the per-tag\nself-cycle lock and depth/label exactness live in src/tests_printer.zig,\nand a new cross-tier probe pins native/wasm agreement at the old cliff\ndepths. write-shared on 32k shared nodes got ~4x faster (hashmaps\nreplace the linear array scans); write/display are unchanged within\nnoise, and non-cyclic output is byte-identical to before.\n\nFixes #1953\nFixes #1954\nFixes #1955\nFixes #2107\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n* Address PR #2190 review: widen prettyPrint fits-check, thread bignum allocator, complete the per-tag lock\n\nReview of #2190 surfaced one real pre-existing crash: `exactFlatLen`\nsaturates at maxInt(u16) and `ppValue`'s fits-check added it to `indent`\nin u16 arithmetic, so echoing any nested subtree whose flat form reaches\n64 KiB — ((<70000-char string>)) — panicked the ReleaseSafe REPL with\ninteger overflow. Verified reachable on the pre-rework binary too;\nwidened to u32 with a regression test.\n\nAlso from review: the new cyclic prettyPrint test was missing the write\nbarrier its tests_printer.zig sibling already had; `writeBignum` now\nthreads the engine allocator instead of paying page_allocator's\nmmap/munmap per element; the \"every traversable container\" mutation\nlock gains the two tags (.pair, .record_instance) it delegated\nelsewhere, so it alone owns the checklist CLAUDE.md points at; and two\ncomments are refreshed — the #1713 block no longer describes the\nremoved depth-cap machinery, and printer_pretty's header now spells out\nwhy the multi-line fallback's emissions are bounded on purpose (fit\ndecisions and emitted text must come from the same renderer).\n\nDeclined with evidence on the PR: routing ppValue's flat emissions\nthrough the exact printer (an exact emission behind a bounded\nmeasurement can be arbitrarily wider than the width the layout just\nbudgeted), and rooting allocSymbol results in the moved tests (interned\nsymbols are permanent GC roots — memory.zig:166 — which is why those\npre-existing tests have always been gc-stress green).\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-02T13:51:23Z",
          "tree_id": "5581bfc26462cb4219fe4e27b3343da96b2ef2d7",
          "url": "https://github.com/kaappi/kaappi/commit/bfd73a166e5020873ab96aaab58050e040264f68"
        },
        "date": 1785680168464,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.953832,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.317363,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.579275,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.872056,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.005018,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.044824,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.293147,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.054903,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.313039,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.154005,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.530694,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.309988,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.725154,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.801173,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044693,
            "unit": "seconds"
          }
        ]
      }
    ]
  }
}