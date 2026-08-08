window.BENCHMARK_DATA = {
  "lastUpdate": 1786172577325,
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
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "990eae71da27761ad31ec11beb96cee6b8704c5c",
          "message": "Reject non-positive segment sizes across SRFIs 152/160/178/196 (#2191)\n\n* Reject non-positive segment sizes across SRFIs 152/160/178/196\n\nFour segment procedures shared one missing precondition: none rejected\na non-positive size, and each loop advances by that size per iteration,\nso n = 0 never advanced — an unbounded-allocation hang (%uvec-segment on\nall 12 kinds, string-segment, range-segment) or unbounded recursion into\nan uncatchable KP3008 (bitvector-segment). SRFI 171's tsegment already\nrejected n = 0 at entry; the other four now do the same, raising a\ncatchable error for any size that is not an exact positive integer —\nwhich SRFI 160 and 178 spell out verbatim, and which is the only sane\nreading for 152/196, where no finite list of length-0 pieces can cover\na non-empty input.\n\nbitvector-segment also recursed once per segment with the cons outside\nthe recursive call, so a legal call on a 200,000-bit vector died with an\nuncatchable stack overflow. It now accumulates in tail position and\nreverses, the shape the other three already had.\n\nOne observable change beyond the hangs: (s8vector-segment (s8vector) 0)\nreturned () — the empty vector was the sole input where n = 0\nterminated. The guard runs before the loop, so it raises now too, per\nthe spec's unconditional \"it is an error\".\n\nRe-enables the assertions disabled with FAIL: #1949 / FAIL: #2084 and\nadds n = 0, n = -1, and inexact-n regressions across both dispatch\nbranches and all five test files.\n\nFixes #1949\nFixes #2084\nFixes #2172\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n* Move the deep bitvector-segment case to its own stress-skipped file\n\nThe 200,000-segment regression for #2084 timed out the gc-stress-scheme\njob (exit 124): stress collection runs on every allocation, so building\n200k bitvectors against a growing live heap is quadratic — measured\n4.2 s at 5k, 42 s at 20k, ~3 min at 40k on a fast machine, extrapolating\nfar past the job's 900 s per-file budget at 200k. Shrinking the count is\nno escape: any count that still exceeds the 32,768 frame cap (the point\nof the test) is already minutes under stress.\n\nSo the deep case moves to srfi178-segment-stack-2084.scm, listed in\nKAAPPI_GC_STRESS_SKIP under reason (a) like reader-port-refill-gaps.scm\nbefore it — run-all.sh still runs it plain on every PR (~0.1 s), and\nsrfi178-audit.scm keeps its other 369 assertions stressed (5.3 s under\nthe stress binary), including the n = 0 guard half of #2084.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n* Address review: uniform guard coverage, accurate skip-list prose\n\nReview follow-ups on #2191, from CodeRabbit and inline notes:\n\n- primitives_srfi160-audit.scm sweeps n = 0 through all 12 public\n  segment wrappers via the existing all-kinds table. The guard is one\n  shared definition in %uvec-segment and s8/u8 already proved both\n  dispatch branches, so this pins wrapper reach, not 12 copies of the\n  guard — a future per-kind split cannot drop it for one kind unnoticed.\n- Every segment site now covers the full predicate matrix uniformly:\n  n = 0, n = -1, an inexact 2.0, and n = 0 on the empty input — the\n  last one pinning guard-before-length-check order, the one subtle\n  placement decision in the fix (empty inputs used to return ()).\n- srfi178-audit.scm's \"discriminating control\" comment predated the\n  tail rewrite; the 1,000-bit case is now labeled the smoke check it is,\n  with the depth job pointed at srfi178-segment-stack-2084.scm.\n- ci.yml no longer claims skipped files \"still run stressed in the\n  nightly fuzz.yml legs\": fuzz.yml's gc-stress legs run fuzz targets\n  and the Zig unit suite, never the Scheme corpus. The rewritten\n  paragraph says what is actually true — listing a file removes its\n  stressed Scheme run entirely, plain coverage stays on every other\n  leg, and named counterparts keep the stressed half.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-02T14:49:11Z",
          "tree_id": "a261b2aa30ed45097d399178188a139a61a1f2e6",
          "url": "https://github.com/kaappi/kaappi/commit/990eae71da27761ad31ec11beb96cee6b8704c5c"
        },
        "date": 1785683900303,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.263764,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.207414,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.568913,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.965574,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004699,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046445,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.309608,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.056598,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.684413,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.235654,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.568085,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.281014,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.784887,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.60288,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042921,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "92e3133cd159233b601f804d64b5b84e39715bcf",
          "message": "Fix six port-layer defects across SRFI 181, SRFI 192 and R7RS 6.13.1 (#2192)\n\nEvery one of these is a branch that was never written for a port kind that\ndoes not have an fd. A custom port and a transcoded port both carry the\n`fd = -1` sentinel, so a path missing their branch fell through to a real\nsyscall on -1, failed with EBADF, and reported the failure as ordinary end\nof input or as nothing at all.\n\n#1995 — `read` returned #<eof> on every custom and transcoded port.\n`readDatumFn` is the one input primitive that does not go through\n`readOneByte`; its refill called `portFdRead(-1, ...)` directly, so the\nread! callback was never invoked even once. It now refills through\n`readOneByte` for these two port kinds, restoring the invariant CLAUDE.md\nalready states. That also removes the spurious KP3000 the partially-drained\ncase produced, and the chunk-size dependence that made a whole-datum burst\nwork by accident.\n\n#1997 — the encode half of a transcoder converted only #\\newline, while\nthe decode half already treated bare CR, bare LF, and CRLF alike. So a\n`crlf` transcoder turned one CRLF into CR CR LF and a round trip doubled\nevery line break. Encode now recognizes the same three line endings the\ndecode side does. A CRLF split across two writes stays one line ending via\na new `TranscodeState.pending_cr`, committed only after the wrapped write\nsucceeds so a parked write's retry recomputes the identical translation.\n\n#1943 — `flush-output-port` on a transcoded port was a silent no-op: the\nfunction had a custom_backend branch and an isBufferedFdPort branch and no\ntranscode branch. The body is now `flushPortObj`, which cascades to the\nwrapped port — itself possibly a custom or buffered fd port, hence a\nrecursive call rather than a drain.\n\n#1942 — `port-has-set-port-position!?` was registered to\n`portHasPortPositionP`, which inspects `get_position_proc`, so it answered\na question about the getter. Wrong in both directions for a custom port\ncarrying one of the two procedures without the other; invisible on every\nother port kind, which supports both or neither. It gets its own function.\n\n#1941 — the string-port branch of `port-position`/`set-port-position!`\nneither subtracted software read-ahead nor discarded it on seek, though\nthe fd branch has always done both and `read-line`'s CR handling pushes a\nbyte back on string ports too. Position over-reported by one and a seek\nserved the stale byte first.\n\n#1998 — `close-input-port` and `close-output-port` both closed the whole\nport, and ran the custom port's close callback on the first side closed.\nR7RS 6.13.1 gives them independent semantics on a port that is\nsimultaneously input and output, which `make-custom-binary-input/output-port`\nconstructs. `Port` gains `input_closed`/`output_closed`; the shared backing\nis released only when the second side goes, so the callback still runs\nexactly once. Single-direction ports are unaffected. Both flags are set\nafter the (possibly suspending) flush completes, mirroring closePortObj's\nown drain-then-mark order.\n\nVerified against the pre-fix v0.22.1 binary: all six symptoms reproduce\nthere and none here. 17 previously disabled audit assertions are\nre-enabled and the two \"current (wrong) behaviour\" pins are flipped.\n\nCloses #1941, #1942, #1943, #1995, #1997, #1998\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-02T21:37:26+05:30",
          "tree_id": "5a24fcedf97363b14aaff6e63b1e2b7291104e00",
          "url": "https://github.com/kaappi/kaappi/commit/92e3133cd159233b601f804d64b5b84e39715bcf"
        },
        "date": 1785688468537,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.082884,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.259096,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.451214,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.194074,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.003802,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.034944,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.228877,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.043055,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 1.808707,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.899476,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.184787,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.238339,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.312717,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.411236,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.035582,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "f7a960e7bbea70028f9c4fa412b67c9aa176d56d",
          "message": "Stop two custom-port callback shapes from aborting the process (#2193)\n\n* Stop two custom-port callback shapes from aborting the process\n\nA SRFI 181 callback runs re-entrantly, under vm.callWithArgs with\ndispatched_from_scheduler forced false. Two things the port layer assumed\ncould not happen from there both could, and both killed the process\nuncatchably from ordinary Scheme.\n\nport.read_buf is a single slot, and the three fills that stash into it --\nthe fd burst, a custom read!'s result, a transcoded port's re-encoded\ncharacter -- each asserted it was empty first. A read! that reads from its\nown port runs a whole earlier read! to completion, so that slot already\nholds the earlier burst's leftovers when the outer invocation returns. At\n>= 2 bytes the assert fired: exit 134, and `guard` cannot catch it. At\nexactly 1 byte the assert did not fire and the later burst's byte was\nserved ahead of the earlier one's leftovers, so the stream was silently\nreordered instead. All three now go through takeFirstBufferingRest, which\nconcatenates in chronological order and hands out the front byte -- no\nabort, and bytes come out in the order read! produced them. Re-entrancy\nstays supported, as it already was for write!, flush and close, and the\nfd path keeps its allocation-free single-byte fast path.\n\nvm.in_custom_port_callback was read at exactly two sites, waitForFd and\nthread-sleep!. Every other blocking primitive -- channel-receive,\nchannel-send, fiber-join, thread-join!, mutex-lock!,\ncondition-variable-wait -- drove the scheduler recursively on the native\nstack instead, running whole sibling fibers to completion inside the\ncallback. Nesting grows one drive per level, so n fibers reading one such\nport died with SIGBUS at n = 2500 while n = 2400 was clean: far short of\ncallReentrant's max_native_depth = 3000, which is calibrated for a plain\nre-entrant call rather than a nested runUntil *plus* a drive. The check\nnow also sits in fiber.runSchedulerStep, the single shared body behind\nevery in-place drive, so a blocking primitive added later is covered\nwithout anyone having to list it. The two early checks stay, each having\nstate (a registered fd, an armed timer) it is cheaper never to arm.\n\nThe four assertions the two audit suites had disabled against these issues\nare re-enabled and corrected, and the deep-nesting case they deliberately\nleft out -- it took the runner down with it -- is now its own file, which\nstill aborts pre-fix and passes post-fix.\n\nCloses #1939\nCloses #2000\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Serve re-entrant leftovers before EOF, and test the two named D5 blockers\n\nReview follow-up on #1939/#2000.\n\nThe first commit routed every *non-empty* fill through\ntakeFirstBufferingRest but left all three EOF exits returning null\ndirectly, so it fixed two of the three sizes of the same bug and shipped\nthe third. When a nested read! leaves bytes in read_buf and the outer\ninvocation then returns 0, the custom-port path answered eof-object over\nthem and the *next* read produced the data: a spurious EOF mid-stream.\nConfirmed at f92df40 -- `(a #<eof>) (b 66)` where both should be 66.\n\nEvery EOF exit of all three fills now routes through the helper, which\nserves a pending byte before reporting EOF. The fd burst's and the\ntranscoded character's need re-entrancy on their own port to reach a\nnon-empty read_buf and no program was found that does; they are routed\nanyway, because three fills that look identical while one silently isn't\nis what produced this bug in the first place. The helper also handles the\npending-is-exactly-one, burst-is-empty case explicitly: alloc(u8, 0) would\notherwise leave read_buf non-null at read_buf_len 0, a state the drain\nfalls through into a spurious extra read! call.\n\nThe D5 doc comment named thread-join! and condition-variable-wait as\ncovered by the runSchedulerStep guard while testing neither. Both are\nreachable, so they are tested rather than the claim softened. Only\nthread-join!'s *fiber* path drives -- the OS-thread path joins the pthread\ndirectly, which is why primitives_srfi181-audit.scm's \"a read! that joins a\nshort-lived thread is NOT rejected\" control still passes; both directions\nare now pinned. The target must already have started: thread-join! on a\nspawn'd fiber still in .created spins in its own sleepNs poll without ever\ndriving the scheduler and hangs, which is unrelated to this guard and left\nalone.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-03T00:59:20Z",
          "tree_id": "13a0a29381aa82b7522e2a76c0baa6f8548e7223",
          "url": "https://github.com/kaappi/kaappi/commit/f7a960e7bbea70028f9c4fa412b67c9aa176d56d"
        },
        "date": 1785720495011,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.002101,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.846085,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.406451,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.105442,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004204,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.034203,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.217198,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.041212,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.05918,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.883177,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.120113,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.228902,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.259441,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.876078,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.033317,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "c742af6856fed94f266bc3d100bc5e16a0106f62",
          "message": "Fix four SRFI-69 hashing defects: deep keys, a self-mutating hash procedure, and negative hashes (#2195)\n\n* Fix four SRFI-69 hashing defects: deep keys, self-mutating hash, negative hashes\n\nAll four live in valueHashDepth/rehash and break the same SRFI 69 rule from\ndifferent directions: a hash must agree with the table's equality, and must\nland in [0, bound).\n\nCloses #2023.\n\n  The depth cutoff at MAX_HASH_DEPTH returned the *pointer* of whatever sat\n  there, while findKey/findSlot compare with deepEqual. Two equal? keys whose\n  structure reached depth 8 hashed to unrelated buckets, so the stored entry\n  became unreachable -- 200 of 200 twelve-element keys unfindable, and the\n  same through (srfi 125), (srfi 126) and (srfi 146 hash). The cutoff now\n  folds in a fixed sentinel, and a list spine is walked iteratively so length\n  no longer spends the nesting budget that only nesting should.\n\n  Found while fixing it: SRFI 160 numeric vectors are compared structurally by\n  deepEqual (kind + raw bytes) but had no arm at all in valueHashDepth, so\n  they fell through to the same pointer hash at depth 0. Same invariant, same\n  symptom, no depth needed -- fixed here too rather than filed separately.\n\nCloses #2024.\n\n  rehash captured the old entry array and then called the table's own hash\n  procedure from inside the loop iterating it. A hash procedure that inserted\n  into its own table reached a nested rehash, which swapped in its own array\n  and freed the one the outer loop was still walking, then freed it a second\n  time -- a silent abort, exit 133/134 with empty stdout and stderr.\n\n  HashEntry now caches the hash computed at insertion, so rehash re-buckets\n  from it and runs no Scheme code at all. hash-table-merge!, the second site,\n  walked ht2's live array across findSlot on ht1 and left ht1 with 1 of 10\n  entries; it now iterates a rooted snapshot, the shape walk/fold got in\n  #1181. findKey/findSlot derive the mask only after the hash procedure has\n  returned, and copy entries out by value.\n\nCloses #2025.\n\n  hash, string-hash, string-ci-hash and hash-by-identity masked to 62 bits and\n  handed the result to makeFixnum, which keeps 48 and sign-extends from i48 --\n  so any hash with bit 47 set came back negative, about half of all inputs.\n  Masking to 47 bits is the widest value that survives the round trip. The\n  bounded arm was always correct and is untouched.\n\nThe audit file's disabled assertions are re-enabled (all four FAIL markers\ncleared) and joined by the numeric-vector cells, a discriminating merge\nrepro, and coverage for the caching itself: growth, copy, and re-bucketing a\nmerged entry under the target table's hash function rather than the source's.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Wire types.zig to types_hashtable.zig instead of duplicating it\n\nThe #1731 domain split added `types_hashtable.zig` but never wired it up:\nnothing imported it, so the byte-identical copy in `types.zig` was the one the\nbuild compiled and the domain file was never even type-checked.\n\nAdding `HashEntry.hash` in the previous commit meant editing both by hand,\nwith no compile error if they drifted -- which is exactly the trap a split\ninto domain files is supposed to remove. `types.zig` now re-exports the four\nnames the way it does for every other `types_*.zig`, matching what CLAUDE.md\nalready documents.\n\nNo behaviour change: the struct definitions are identical.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Address review: stale slot indices, cutoff coverage, and a benchmark regression\n\nThree things review turned up on the first two commits.\n\n**A silent entry-loss path the abort fix did not close.** CodeRabbit and my own\nreading independently landed on the same gap: `findSlot`/`findKey` derive a\nmask and choose a slot, but a `.custom` equality procedure is arbitrary Scheme\nand one that inserts into the table being probed makes `rehash` install a new,\nlarger `entries`. There is no use-after-free -- `ht.entries` is re-read -- but\nthe chosen index names an arbitrary bucket in the new layout, so the caller's\nwrite lands on a live entry for a different key while `count` is still\nincremented. One pre-existing key destroyed, `count` no longer matching the\nlive set. A (prefill x inject x span) sweep reproduced it in **128 of 210**\ncombinations; all 210 are clean now. The probe restarts when it observes the\nlayout move, bounded at 16 restarts so a procedure that mutates on every call\nraises instead of spinning.\n\n**The new #2023 assertions did not reach either cutoff.** `mk` builds a flat\nlist, and after the fix a flat list no longer spends the nesting budget -- so\nnothing exercised `DEEP_CUTOFF_HASH` or the `MAX_HASH_SPINE` truncation. Added\na `nest` helper for keys deeper than `MAX_HASH_DEPTH`, and a case whose only\ndistinguishing element sits past the spine cutoff so every key hashes alike and\n`deepEqual` has to separate them. The duplicate 200-deep-keys cell became the\nnesting one rather than a second copy of a test three lines away.\n\n**A 1.32x regression on `benchmarks/hashtable.scm`.** Routing the default\n`.equal` mode through `hashForTable`/`equalForTable` -- whose `.custom` arms\npull in the whole VM-call path -- stopped `valueHash` and `deepEqual` from\ninlining: 18% on insert, 10% on lookup. The `.equal` specialization the\noriginal code had is restored, and the other callback-free modes get a probe\nloop without the restart bookkeeping. `HashEntry.hash` is also `u32` rather\nthan `usize`: only `hash & (capacity - 1)` is ever read, and it keeps the\nstruct at its original 24 bytes. Now 0.0302s against 0.0306s on main.\n\nAlso: strengthened the #2024 abort assertion, which accepted entry loss\n(`(>= size 5)` passes while a key is missing); corrected an inaccurate test\nname (an f64vector and a bytevector with the same elements are not the same\nbyte length); and made the deep-copy test assert the copied entry's cached hash\nagrees with the *destination* table -- not with the source, since the\nnon-custom arm deliberately re-hashes as it re-buckets.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Note why MAX_PROBE_RESTARTS is a backstop, not the first defence\n\nAn unconditionally-mutating custom procedure re-enters the table from inside\nits own callback, so `KP3008: native re-entrancy too deep` fires long before\nthe restart count runs out -- verified directly: the process raises and stays\nalive rather than spinning. Records that, and why the exhaustion path raises an\nordinary catchable error instead of another VM limit: KP3008 is uncatchable by\ndesign (#1886), so if anything ever does reach this bound, a `guard` should be\nable to see it.\n\nComment only.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-03T12:05:58+05:30",
          "tree_id": "5c94ad0105eae57cdef3c873276c201dc972f64e",
          "url": "https://github.com/kaappi/kaappi/commit/c742af6856fed94f266bc3d100bc5e16a0106f62"
        },
        "date": 1785740731206,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.273146,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.063715,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.583473,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.961217,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004665,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046886,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.314323,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.058016,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.745254,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.211907,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.641061,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.284403,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.791189,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.654606,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043161,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "07cceb257ed76cf6fd4d7d890a4a8b367544c496",
          "message": "Refuse three cross-heap uses that the owner checks were missing (#2198)\n\nAll three issues are the same shape: an object used by a thread that does\nnot own it, on a route where nothing checked. The globals map is shared by\npointer, so a thunk that merely *names* a top-level binding hands the child\nthe parent's own object -- and only channels and thread handles compared\nObject.owner against the running GC.id.\n\nfiber-join (#2001) is the worst of the three, because the API itself\nperforms the hand-off: it returned the parent's heap object to the child as\nits documented result value, so a set-car! in the child was observed by the\nparent. A still-running foreign fiber was reported as a deadlock, sending\nthe reader to look for a cycle that does not exist -- the fiber simply\nbelongs to another thread's scheduler. gc_deep_copy refuses the .fiber tag\noutright, so there is no idiom to protect: nothing legal is now refused.\n\ninvokeGuardian (#2008) mutated Guardian.registered -- a raw std.ArrayList,\nthe only Zig container Scheme can grow across a heap boundary -- with the\n*calling* thread's allocator and no lock. Two threads registering into one\nshared guardian aborted the process 5 of 5 times with empty stdout and\nstderr. A child registering a child-heap object left the parent holding a\npointer into the freed child arena, which weakReachable then read for an\nowner id: silently #f in ReleaseSafe, an unrelated live parent-heap pair\nunder -Dgc-stress. One check ahead of both the register and the retrieve\nbranch closes both.\n\ngc_deep_copy's channel arm (#1934) checked ownership only on the\nunpromoted branch, so promotion state alone decided whether KEP-0002\ninvariant 4 applied. A thread could read a promoted channel out of a\nshared global -- which every channel primitive refuses it directly -- and\nhand it to a child, which then held a perfectly working stub. The check\nnow runs before `shared` is read at all (so a foreign heap's field is\nnever read on this path) and keys off direction rather than promotion\nstate: a copy *out of* the running heap into an Envelope must be a channel\nthe running thread owns, while a copy *in*, draining an envelope some\nentitled thread already built, is not re-checked -- its objects belong to\nthat private heap, not to the importer, so re-checking would reject every\nlegal message. All three import sites set gc_instance to the destination\nfirst.\n\nTwo existing unit tests modelled a thread boundary without moving the\nthreadlocal with it, and now set it the way the production path does.\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-03T07:35:59Z",
          "tree_id": "d2990824a84b8b8b87b199b6c5e2e6eca4e477c2",
          "url": "https://github.com/kaappi/kaappi/commit/07cceb257ed76cf6fd4d7d890a4a8b367544c496"
        },
        "date": 1785744426098,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.082126,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.628332,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.564224,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.884687,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004887,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.045022,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.296736,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.054011,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.309598,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.168119,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.52496,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.305176,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.701278,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.781277,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044534,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "e292e8e27a87e83d6341ff656a64524159c9356f",
          "message": "Stop compile-only commands running program code, and name the real cache reason (#2199)\n\n* Stop compile-only commands running program code, and name the real cache reason\n\n`vm_eval.handleTopLevelForm` claims eight top-level heads — import,\ndefine-library, define-record-type, define-values, include, include-ci,\nbegin and cond-expand. Three consumers each carried their own hand-kept\ncopy of that list, and both defects here came from the copies disagreeing\nwith what the dispatcher actually does.\n\n`--compile` and `--disassemble` routed every claimed head through the\n*evaluator*. Three of the eight carry ordinary program code, so a\n`delete-file` inside a top-level begin, cond-expand or define-values ran\nfor real while the artifact was being produced — and the form was also\nrecorded in the preamble, so across compile + run the effect happened\ntwice. A bare top-level `(delete-file ...)` was never executed, which is\nwhat makes this the dispatcher's fault rather than \"compiling runs the\nprogram\".\n\nSplice begin and cond-expand into the driver's form stream instead\n(`toplevel_driver.TopLevelForms`), so their bodies are compiled: only a\ncond-expand's branch *selection* is a compile-time question. Evaluate\nonly `TopLevelHead.isEnvSetup()` — the five declarations later forms are\ncompiled against — and record define-values without running its producer.\nThis also repaired an ordering divergence, since the preamble replays\nentirely before the compiled forms: `one / (begin two) / three` used to\nprint `two one three` from the standalone binary.\n\nThe cache half is reporting, not behaviour. All eight heads legitimately\ndisable the `.sbc` cache — handleTopLevelForm appends no Function, so a\nHIT would skip the form's work entirely — but `--timings` blamed\n`imports` for all of them, telling files containing no import that an\nimport was the cause. It now names the head that fired, and the docs give\nthe shared reason rather than the library-loading one that only covers\nthree of the eight.\n\nThe four parallel lists are now one `vm_eval.TopLevelHead` enum. The\ndispatch is an exhaustive switch, so a ninth head cannot reach the VM\nwithout a handler; `isSpecialTopLevelForm` (whose own comment asked the\nreader to keep it in sync) and check.zig's env-setup allowlist derive\nfrom it.\n\nCloses #2156.\nCloses #2114.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Address review: compile shadowed define-record-type, propagate compile OOM\n\nFive review findings, all verified against the code before acting.\n\n`check` classified top-level heads by *name*, so a `define-record-type`\nshadowed by a macro (SRFI 57/131/136/150 each bind that name) entered the\nenv-setup branch, `handleTopLevelForm` declined it — it does consult the\nmacro table — and the form was dropped uncompiled. `vm.topLevelHead` gives\nthe VM-aware answer, so it now falls through to ordinary compilation.\n\nThe review described the false-negative half: a malformed shadowed use\nreported nothing and `check` exited 0. The false-*positive* half is worse\nand was not mentioned — dropping the form also dropped whatever it bound,\nso later forms drew phantom diagnostics. Sweeping `check` over 880 files\n(tests plus every shipped .sld), old vs new, found exactly two that differ,\nboth known-good: srfi136.scm lost 3 phantom KP2001 \"invalid syntax\" errors\nplus a phantom KP4001, and srfi150.scm a phantom KP2002. Both are hard\nerrors, so `check` was failing valid files.\n\n`compileFile` had three silent failure paths — a failed valueToString or\npreamble/compiled_funcs append dropped a form, then printed\n\"Compiled ... -> ...\" and exited 0 with an artifact missing an import or a\ntop-level form. They now propagate OutOfMemory, as runFile's equivalent\nsite already did.\n\n`define-values` still replays from the preamble, which runs in full before\nany compiled form, so its producer can observe an earlier form's binding as\nunbound: the artifact for `(define x 1)` + `(define-values (a b) (values x\n2))` fails with KP3001 where the interpreter prints `(1 2)`. Reproduced\nidentically at 07cceb25, so this PR neither caused nor fixed it — splicing\nis what restores order and there is nothing to splice a define-values into.\nFiled as #2200 and documented in cache.md rather than folded in here; the\nfix needs an order-preserving preamble or a compilable define-values.\n\nTests: four assertions in errors/check.sh for the shadowing fix (all four\nfail pre-fix), using the real SRFI files as the guard for the\nfalse-positive direction — a synthetic probe cannot show it, since `check`\ngathers top-level define names structurally and never sees a binding any\nmacro introduces. The #2156 suite now uses interp_stdout /\nassert_tiers_agree, which also compares exit status; the golden string\nstays as a second assertion against the interpreter. Deduplicated the\ninclude/include-ci assertion.\n\nRefs #2199 review.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-03T12:19:10Z",
          "tree_id": "7a778f392438e9f8b459ff6cbdfa61c30e9f5801",
          "url": "https://github.com/kaappi/kaappi/commit/e292e8e27a87e83d6341ff656a64524159c9356f"
        },
        "date": 1785761404583,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.412813,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.128928,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.571461,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.079665,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004691,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046955,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.315135,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.058301,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.678782,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.220512,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.600071,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.286545,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.822148,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.585962,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042547,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "72d941a10b95ae9380b4036dbb996ed361acae8e",
          "message": "Point CONTRIBUTING.md at kaappi/community for get-involved content (#2201)\n\nThe \"How to get involved\" section duplicated kaappi/community's\nCONTRIBUTING.md (and kaappi.github.io/docs/community.md) almost\nverbatim. Link to the canonical version instead so there's one place\nto update the Discussions/org-access/contributor-path guidance.",
          "timestamp": "2026-08-03T18:13:09+05:30",
          "tree_id": "a677d00527b500fa34087a319d8685821be39146",
          "url": "https://github.com/kaappi/kaappi/commit/72d941a10b95ae9380b4036dbb996ed361acae8e"
        },
        "date": 1785763451383,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.332802,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.928676,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.571967,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.987321,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004735,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046746,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.31145,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057765,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.656797,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.220524,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.615336,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.276956,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.809151,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.591435,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042694,
            "unit": "seconds"
          }
        ]
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
          "id": "b813fd0cfa9579f51f83adf5b447b366847f4b27",
          "message": "Add DCO2 app config\n\nEnables individual remediation commits so a contributor can retroactively sign off a commit without a force-push. See https://github.com/cncf/dco2.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>",
          "timestamp": "2026-08-03T19:16:41+05:30",
          "tree_id": "097dd7d53d7dad5ceac119e4884ea06cdf1e14a1",
          "url": "https://github.com/kaappi/kaappi/commit/b813fd0cfa9579f51f83adf5b447b366847f4b27"
        },
        "date": 1785766848126,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.068876,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.611482,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.552554,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.875302,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.005019,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.045382,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.301313,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.053425,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.840242,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.113366,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.508815,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.260662,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.745902,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.92578,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.041796,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "cc351d020a8251ecb1ab02ee8085d1c58641314b",
          "message": "Validate arity in the two call paths that build their frames by hand (#2203)\n\ncallClosure checks arity for the `call` opcode. Three other places construct\na frame themselves and inherited none of that: callHandler, callThunk, and the\nfiber scheduler's spawnFiber. Two of them skipped the check entirely, so a\nwrong-arity procedure ran anyway with its surplus parameters reading whatever\nthe register file happened to hold — a live value from a neighbouring frame,\nnot merely an undefined slot, because the hand-built frames also never cleared\npast the argument they staged. A 3-argument exception handler received the\ncaller's `list` procedure as its third argument, deterministically.\n\nRather than add the same check in each caller — which is how it went missing —\nevery re-entrant frame now binds its arguments through one helper on the\ncallReentrant path, bindReentrantArgs, which validates arity and folds surplus\narguments into a variadic callee's rest list. callHandler, callThunk and\ncallWithArgs each collapse to a single call and cannot skip it. That covers\nthe with-exception-handler handler, the call-with-values producer, and the\ncall/cc and call/ec receivers in non-tail position (the tail-position\nsuperinstruction always had its own check).\n\nwith-exception-handler and %call-with-unwind-handler additionally check their\nthunk before installing the handler. Left to callThunk, the thunk's arity\nerror is raised inside the extent of the handler being installed, so the\nhandler catches the report of its own caller's malformed call and the form\nquietly returns the handler's value. Their handler's arity is deliberately\nstill checked at the call, since a handler that is never invoked has nothing\nto report about.\n\nspawnFiber had the same gap plus a second defect: with base = 0, r0 is the\nthunk's first parameter, not a callee slot, so writing the closure there bound\na fiber's own thunk to its first parameter and `#<undefined>` to the rest —\nmaking a rest parameter satisfy neither `list?` nor `null?`, against R7RS\n4.1.4. r0 is now left to the variadic rest list, and the closure stays reachable\nthrough frames[0].closure and fiber.thunk, which the GC already traces. Both\nchecks moved ahead of allocFiber, which used to run first, so a refused thunk\nno longer leaves a fiber and a consumed id behind. spawn also stops relabelling\nevery spawnFiber failure OutOfMemory, which reported a memory problem for what\nis an argument problem and discarded the diagnostic.\n\nA pure-variadic thunk — the natural way to write \"ignore my arguments\" — now\nworks in both places instead of failing outright.\n\nCloses #2034\nCloses #1999\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-03T14:25:15Z",
          "tree_id": "c5ad4c4ca8b31e6a24e28f4ba614fc8b7719c757",
          "url": "https://github.com/kaappi/kaappi/commit/cc351d020a8251ecb1ab02ee8085d1c58641314b"
        },
        "date": 1785768959479,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.496169,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.188382,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.57032,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.103017,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004675,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.047227,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.317864,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.055864,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.686241,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.264175,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.574683,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.283692,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.844568,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.58825,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043139,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "e62b90ebd41368fc03b2e462c39806b6e709becb",
          "message": "Check arity on the native branches of the re-entrancy helpers too (#2206)\n\ncallHandler and callThunk reach a native procedure through their own branches,\nwhich had no arity check at all — a gap the closure-side fix left behind, found\nby CodeRabbit in review of it.\n\nA NativeFn body indexes args[0], args[1], … without bounds checks of its own,\nbecause the VM is expected to have validated arity before the call. Both helpers\nhand one a fixed-size argument array, so a wrong-arity native read past its end.\nUnder the default ReleaseSafe build that is a panic — a process abort out of\nfive lines of ordinary Scheme, not the catchable arity error the closure path\nnow produces:\n\n    (call-with-values cons list)                                    ; callThunk, 0 args to arity 2\n    (with-exception-handler cons (lambda () (raise-continuable 'x))) ; callHandler, 1 arg to arity 2\n    (dynamic-wind (lambda () 1) (lambda () (raise 'x)) -)            ; unwind, 0 args to variadic min 1\n\nAll three printed \"kaappi internal error — this is a bug in kaappi\" and died.\n\nThe check itself already existed twice, verbatim, in callNative and in\ncallWithArgs' native branch. Rather than add a third and fourth copy — the\nduplication this PR is otherwise removing — it moves to checkNativeArity and\nall four sites share it. Messages are unchanged.\n\nThe dynamic-wind case reports as before: the unwind loop discards a failing\nafter-thunk, so the original raise survives, which is what should happen. What\nchanges is that the process reaches that point at all.\n\nThis is pre-existing, not a regression from the previous commit — the native\nbranches are untouched by it — and inside #2034's stated scope, whose table\nlists the with-exception-handler handler reached via callHandler as unchecked.\nIt only tested closures.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-03T20:40:24+05:30",
          "tree_id": "c5103917c94fce3c03d369887fe5f65682173f2f",
          "url": "https://github.com/kaappi/kaappi/commit/e62b90ebd41368fc03b2e462c39806b6e709becb"
        },
        "date": 1785771669056,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.329055,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.025367,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.576594,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.992864,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004671,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046979,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.312776,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057884,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.648063,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.219668,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.623063,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.282094,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.808687,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.477415,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044188,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "798cb60794fe488e111f5c9a3d92cb94205b5b42",
          "message": "Make a failing test able to fail (#2207)\n\n* Make a failing test able to fail\n\nFour issues, one root cause: a check that reports success having asserted\nnothing. Until this lands, every regression test in the corpus is of unknown\nvalue, which is why the audit strategy ranks R10 first.\n\n56 .scm files had no way to signal failure. They computed the right thing and\nthrew the verdict away: `(display (= x 43))` prints #f and exits 0, and so does\n`(display \"FAIL: ...\")`. Both runners reported every one of them as passing\nwhatever they computed -- smoke/thread-sleep-876.scm was demonstrably green\nunder the very regression it was written to catch. run-all.sh's stdout net\ncould not help: it matched a failure COUNT, which neither shape has.\n\nAll 56 are now SRFI-64 suites with the exit-on-fail epilogue (55 from #2116's\nown enumeration, plus deep-nesting-print-tier-margin.scm, which that\nenumeration's predicate missed because the word \"assert\" appears in one of its\ncomments). Three stay import-free with a hand-rolled `(exit 1)` and say why in\ntheir own headers: `(import (srfi 64))` fails at library load on WASM (#2108),\nwhich run-wasm-differential.sh classifies as LIBDIFF -- destroying what the two\n#2107/#1912 probes exist to measure -- and coroutine-repl-echo.scm's top-level\nforms must stay bare because consuming their values is what hid its bug.\n\nA verdict-channel check in run-all.sh now fails the run if a globbed suite file\ncarries none of test-begin, `(exit`, `(error` or `(assert`, so the count cannot\ngrow back from zero. It is a heuristic and says so; the standard is the\nepilogue.\n\nWidening the net to a bare FAIL token found the predicted second finding on its\nfirst run: smoke/fiber-error-handling.scm had been asserting the #551 behaviour\nthat #1155 deliberately REVERSED, printing \"FAIL - should have raised\" and\nexiting 0 ever since. Fixed to assert what #1155 specifies.\n\nThe R7RS suite's own verdict comes from its printed counts -- the (chibi test)\nshim exits 0 with failed assertions in the log -- and five ci.yml steps\n(riscv64, s390x, ppc64le, both Windows legs) took the exit status instead, so\n1,395 assertions caught a crash and never a wrong answer. That matters most on\ns390x, the big-endian canary, where a byte-order bug presents as exactly a\nwrong answer. tools/run-r7rs-suite.sh is now the single implementation behind\nall six callers. runner-agreement.sh's copy of the net regex gained a drift\ncheck against run-all.sh, so the copy cannot silently fall behind.\n\nrun-all.sh no longer builds a default binary when one is missing: the natural\ntwo-command gc-stress sequence silently substituted a plain build for the\nconfiguration being measured, with nothing in the output naming it. It now\nrefuses, and prints the binary's version, build id, target, build mode and\ngc_stress in its header.\n\nprimitives_filesystem-audit.scm asserted that an environment variable named\nKAAPPI is unset -- the name every harness here uses for \"the binary under\ntest\". Moved to a name the test owns.\n\nMeasured cost, so a green WASM differential is not misread: giving 52 files an\n`(import (srfi 64))` moves them into the #2108 LIBDIFF bucket, taking that\nharness's `agree` count from 176 to 124. It reverses entirely when #2108 lands;\nnoted in the harness header.\n\nVerified: run-all.sh 2075 pass / 0 fail; zig build test 1672 pass, 3 skip;\nrunner-agreement 10/10; the R7RS block green under a -Dgc-stress=true build;\nand mutation controls for each new gate (a fresh verdictless file, a drifted\nregex, a missing binary, a broken R7RS assertion, and each hand-rolled exit).\n\nCloses #2116\nCloses #2157\nCloses #2162\nCloses #2163\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Respond to review: fix 8 findings, decline 2 with evidence\n\nEight of CodeRabbit's ten findings were valid; the two it marked Critical were\nboth wrong, and disproving them was the useful part of the pass.\n\nAccepted:\n\n- The one inventory. The counts genuinely drifted: 56 files had no verdict\n  channel, 52 became SRFI-64 suites and 4 kept a hand-rolled `(exit 1)`, plus\n  fiber-error-handling.scm for 53 conversions. Two docs said \"Three files are\n  exempt\" and omitted deep-nesting-print.scm, which I converted and then\n  reverted late without updating them. tests/scheme/CLAUDE.md now carries the\n  single inventory table and the others point at it.\n- Seven callers of tools/run-r7rs-suite.sh, not six: run-all.sh,\n  run-gc-stress-suite.sh, and five ci.yml steps.\n- `-x` not `-e` for the binary pre-flight: a path that exists but is not\n  executable is a harness failure (exit 2), and `-e` let the exec fail with 126\n  and be reported as exit 1, i.e. \"the suite reported failing assertions\".\n- `(import (scheme process-context))` in the two exempt files that are not\n  KNOWN_DIFFS probes, so their verdict does not rest on Kaappi's ambient\n  script-mode `exit`. Verified WASM-safe: process-context is a BUILT-IN\n  library, not a file-backed .sld, and tier-margin's output and exit status are\n  byte-identical under wasmtime with and without it. The two KNOWN_DIFFS probes\n  are left alone — their divergence is the measurement.\n- Three assertions strengthened, each with a mutation control:\n  `(eq? '->string '->string)` was vacuous (both literals truncate identically\n  under #647 and eq? is still #t) — now asserts the symbol's text;\n  prettyprint-cycle-859 accepted any `#` — now matches `#0=` and `#0#`;\n  syntax-rules-many-vars summed 17 variables, and addition is commutative, so a\n  permuted expansion still totalled 153. Proved directly: with the template\n  permuted the sum-based assertion exits 0 and the list-based one exits 1.\n\nDeclined:\n\n- \"run-all.sh does not fail when the R7RS suite reports failing assertions\"\n  (Critical). It does. `R7RS_FAIL` is sourced from the counts file and tested\n  in the summary condition, which the finding did not check. Proved end to end:\n  one broken assertion injected into r7rs-tests.scm gives `1395 pass, 1 fail`\n  and run-all.sh exit 1. The suggestion is still worth taking on robustness\n  grounds, so the block now gates on `R7RS_RUNNER_STATUS -ne 0` — one condition\n  covering every runner exit rather than three that happen to cover today's\n  two.\n- \"(srfi 133) is not imported, so all five assertions pass vacuously\"\n  (Critical). vector-reverse!, vector-reverse-copy and vector-unfold resolve\n  with only (scheme base) imported — SRFI 133 is built-in. Discriminating\n  control: the VALID calls do not raise (they would if the names were unbound)\n  while a genuinely unbound name does, so `raises?` is sound and the\n  assertions are not vacuous.\n\nVerified: run-all.sh 2075 pass / 0 fail; runner-agreement 10/10 with its regex\ncopy and drift check intact; tier-margin identical native and under wasmtime.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n---------\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-03T19:30:40Z",
          "tree_id": "befda9667dced64aa2ed54b8c88c9eba518eeb56",
          "url": "https://github.com/kaappi/kaappi/commit/798cb60794fe488e111f5c9a3d92cb94205b5b42"
        },
        "date": 1785787358935,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.360611,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.530314,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.60543,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.965039,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004689,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.047147,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.313102,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057912,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.67077,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.220809,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.640459,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.290283,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.825695,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.66389,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044557,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "fbd9f4643a8fe15a94a2951559efdca49a26c5a4",
          "message": "Give the native backend's re-lowered bodies their lexical scope (#2210)\n\n* Give the native backend's re-lowered bodies their lexical scope\n\nThe LLVM backend does not emit from the IR tree it is handed: every\nlambda, closure and let body is still a raw S-expression there and is\nre-lowered during emission through a scratch IR that has no Compiler.\nTwo IR fields stand in for that Compiler, and both were under-supplied.\n\n`bound_names` held only the immediate frame's parameter names, so a\nbinding one level out was invisible — and it feeds two different\ndecisions, not one: `isRedefined`'s fold gate (#2117) and\n`lowerFormWithMacros`'s special-form-vs-call dispatch (#2118). It is now\n`LLVMEmitter.lexicalNames`, derived from the same locals/boxes/rest/\nparams/upvalues maps `emitGlobalRef` resolves against rather than kept\nas a parallel list, since a parallel list is what drifted.\n\n`set_targets` was never supplied at all, so a `set!` in the enclosing\nbody did not suppress a later fold in that same body (#2117 route 1).\nnative_compiler now runs the interpreter's own `set!` pre-scan — minus\nmacro expansion, which needs a Compiler, and which the backend already\ndeclines a body for (#1807) — and hands the map to the emitter.\n\n`lowerScoped` is now the one way to re-lower a sub-form; the scope-less\n`ir.lowerSingleExpr`/`lowerSingleExprTail` it replaces are deleted so\nthe omission cannot recur. That also closes the let-body and cond/case/do\ncases, which had no shadowing information whatsoever: `(let ((+ -)) (+ 1 2))`\nprinted 3 natively and -1 under the interpreter.\n\nThe three .scm suites that already owned these bugs —\nlambda-param-shadows-keyword-788, lambda-param-shadow-fold-790,\nset-redefine-fold — passed the whole time because no suite ran them\nthrough `kaappi compile`. The new compile script does, alongside 16\nper-route tier comparisons including the issues' own discriminating\ncontrols; against the unfixed backend the three suites fail 9, 1 and 6\nassertions respectively.\n\nCloses #2117\nCloses #2118\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Cover #2211's four scope-less lowering sites in the compile test\n\nThe compile script pinned four of the eleven divergences #2211 reports.\nAdd the other seven — let*, a let-bound `quote`, case, do, an apply\noperand, and a let shadowing seen from a nested let in both nesting\ndirections — plus that issue's own control, a lambda capturing an\nunboxed let-local, which declines native compilation outright and so was\ncorrect on both tiers all along.\n\n18 of the 24 comparisons now diverge against the pre-fix backend; the\nother 6 are the controls.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Address review: pin the tier, compare Part A, cover initializers\n\nThree of CodeRabbit's findings on #2210 were right.\n\nThe tests_native assertions were shaped \"this fold did not happen\",\nwhich a frame that never compiled natively satisfies vacuously. All nine\nprograms do compile natively today (checked: zero eval fallbacks), so\nnothing was passing falsely — but the shape is the bug, not the current\nanswer. expectNativeTier now pins the tier first.\n\nPart A checked only the compiled suites' sentinel and exit status, not\ntier agreement, on the grounds that the VM echoes their bare `#t`\nresults. Stripping exactly those lines makes the comparison work, and it\nis strictly more informative: against the pre-fix backend the three\nsuites now report a stdout mismatch and an exit-status mismatch rather\nthan just a missing sentinel.\n\nThe let/let* binding INITIALIZERS (llvm_emit_let.zig:212 and :264) had\nno coverage — every case exercised the body at :361. Three added; all\nthree diverge pre-fix, including a let* initializer shadowed by an\nearlier binding of its own let*.\n\n24 of the 30 comparisons now diverge against the pre-fix backend.\n\nAlso correct the scanSetTargetsWithoutMacros comment, which claimed its\nmacro-free limit \"lines up\" with the backend's macro-use decline. True\nfor a body; false at top level across forms, where a macro expanding to\n(set! + -) leaves the name unrecorded and a later form still folds it.\nThat is pre-existing (#822's tracker is macro-blind the same way) and\nreproduces identically at 798cb607, so it is filed as #2212 rather than\nfixed here.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n---------\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>",
          "timestamp": "2026-08-04T05:30:45Z",
          "tree_id": "7adef1ce2dd485701fadaeb82787d9ad1bd6a010",
          "url": "https://github.com/kaappi/kaappi/commit/fbd9f4643a8fe15a94a2951559efdca49a26c5a4"
        },
        "date": 1785823180872,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.356961,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.33172,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.587946,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.994815,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004701,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.047533,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.314747,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.0584,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.698916,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.234025,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.627507,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.286174,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.802624,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.654116,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043819,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "ec875b3f0bb5e53ed94f4b1684d0f5b4db79ae90",
          "message": "Compact CLAUDE.md into docs/dev, and correct the drift found doing it (#2213)\n\n* Move CLAUDE.md's reference detail into docs/dev\n\nCLAUDE.md had grown to 1623 lines and was being read in full on every\nsession. Most of it was reference material rather than orientation: a\n~650-line SRFI implementation narrative (in places single 20,000-character\nparagraphs), the fiber reactor, the package manager, and file-organization\ntables duplicated from architecture.md.\n\nNone of it is deleted. Each passage moves to the docs/dev document that\nowns the subject, and CLAUDE.md keeps a pointer:\n\n  srfi-implementation-notes.md  new — the whole SRFI narrative\n  fibers-and-reactor.md         new — KEP-0001 reactor and parking\n  thottam.md                    new — package manager and manifest\n  architecture.md               now owns the file-organization tables\n  llvm-backend.md               gains the #1896 gate, the derivation walk,\n                                and the libkaappi_rt.a search path\n  cli-surface.md                gains the annotated flag surface\n  thread-value-sharing.md       gains the implementation map\n  adding-features.md            gains the printer cycle rule (#1954)\n\narchitecture.md's tables were stale enough to mislead — 7 compiler files\nagainst a real 11, 8 VM against 10, 21 primitives against 31 — and it\npointed back at CLAUDE.md for the current version. That cycle is gone.\n\nVerified by extracting every backticked identifier and issue reference\nfrom the old file and confirming each still resolves somewhere in\nCLAUDE.md, docs/dev, or .claude/rules. Also corrects the R7RS suite count\nto the measured 1,395 and points at tools/run-r7rs-suite.sh, since a bare\ninvocation exits 0 with failures (kaappi#2157).\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Correct three README claims that no longer match the code\n\nFound while verifying the README against the implementation rather than\nagainst itself. CLAUDE.md names README the single source of truth for\nKnown limitations, so a wrong entry there is the authority.\n\nThe WASI fiber note said the reactor backend is \"timer-only until\nKEP-0001 Phase 4\". Phase 4 has shipped: reactor.zig's WasiPollBackend\nmakes real poll_oneoff fd subscriptions. The actual behaviour is a\nhost-capability probe (primitives_io.zig:174) — ports flip to\nnon-blocking only if fd_fdstat_set_flags(NONBLOCK) succeeds, and only\nwhen it fails does the reactor fall back to timer-only waits.\n\nThe OS-threads note said threads \"cannot share mutable state directly\".\nThey can: a child thread mutating a top-level vector is observed by the\nparent, because VM.initForThread shares globals by pointer. That is the\nglobals route docs/dev/thread-value-sharing.md describes, and the\n14-tag refusal list does not apply to it. The section now covers both\nroutes, notes that mutexes and condition variables can only be shared\nthrough a global, and keeps the \"prefer channels\" guidance as advice\nrather than a false impossibility.\n\nThe library count said 14. R7RS Appendix A defines 16, confirmed against\ndocs/errata-corrected-r7rs.pdf, and all 16 import and work here —\n(scheme case-lambda) and (scheme r5rs) included, which are the two a\ncount of 14 omits.\n\nAlso folds the five per-OS platform paragraphs into a linked list. Every\nfact is kept; each port doc already carries the detail, and Windows and\nFreeBSD gain the links they were missing.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Teach the release skill to refresh the docs site's counts\n\nStep 5 recomputes the built-in procedure count and greps for stale\ncitations, but only within this repo. The docs site cites the same\nnumbers and is a separate repo, so nothing ever refreshed it: the site\nsat at 601 built-in procedures while this repo was at 689, and at 14\nstandard libraries against a real 16.\n\nAdds a second grep over ../kaappi.github.io, notes that it needs its own\ncommit, and records that the \"600+\" phrasing on prose pages is\ndeliberate — it never goes stale, so only docs/conformance.md, which\nmirrors CONFORMANCE.md, should carry the exact figure.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n---------\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-04T12:20:09+05:30",
          "tree_id": "28cc8e16f8ab49dbeb5f93a4c96003ac8a09280f",
          "url": "https://github.com/kaappi/kaappi/commit/ec875b3f0bb5e53ed94f4b1684d0f5b4db79ae90"
        },
        "date": 1785828116638,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.940312,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.542765,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.581398,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.837402,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004997,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.045584,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.297365,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.053876,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.384336,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.156596,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.533936,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.302503,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.736819,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.8518,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044893,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "d717d0b4d8e34df2e8dcc8b2fa55e8d533e78d54",
          "message": "Stop two shell drivers tripping over the .exe suffix (#2220)\n\n* Stop two shell drivers tripping over the .exe suffix\n\nFound running the whole of tests/scheme/**/*.sh on the Windows 11 ARM64\nreference VM. Neither script is reached by the Windows CI loop — it iterates a\nfixed list of eleven suite directories, and completions/ is not among them —\nso both had been failing there unobserved. The behaviour under test is fine in\neach case; only the harness was wrong.\n\ncompletions.sh generated its scripts into $TMP/$(basename \"$bin\").$shell and\nthen went on sourcing a hardcoded $TMP/kaappi.bash. On Windows the binary is\nkaappi.exe, so it wrote kaappi.exe.bash and every reader missed: 19 of 39\nchecks failed with \"No such file or directory\" and \"_kaappi: command not\nfound\". The generated names are now keyed to the *tool* — kaappi, thottam —\nwhich is the one spelling stable across platforms and across however the\ncaller spelled the binary. §2's loop already iterated tool names; its variable\nis renamed from bin to tool so it stops reading like a path.\n\nThe suffix is worth naming as a class, because it is invisible from POSIX and\nhalf-invisible from Windows. Runners spell the binary both ways: bin/kaappi.exe\nin the CI jobs, plain zig-out/bin/kaappi from a Git Bash checkout — and the\nbare spelling *works*, because MSYS appends .exe when executing. So a script\nthat only ever runs the result is fine; one that names the file, -x-tests it,\nor derives an output name from its basename is not. That is why THOTTAM, built\nas \"$(dirname \"$KAAPPI\")/thottam\", executed correctly on the box while the\nkaappi half of the same suite was failing. New shell-common.sh helper\nsibling_tool takes the suffix from the path the caller passed rather than from\nis_windows, so the two cannot drift apart.\n\naudit-baseline.sh moves to tools/. It is a developer report generator, not a\ntest: it drives `zig build` and takes an *output directory* as $1, the opposite\nof every driver under tests/scheme/, which takes the kaappi binary there.\nrun-all.sh never ran it — run_shell_suite globs a suite directory and no call\npasses tests/scheme itself — but any sweep of tests/scheme/**/*.sh picks it up,\nhands it the binary path, and gets `mkdir -p zig-out/bin/kaappi.exe` followed\nby a summary grep against a path that is not a directory. Living in tools/,\nbeside run-r7rs-suite.sh and run-gc-stress-suite.sh, makes that unreachable\nrather than merely unlikely. Its four references are updated in step.\n\nVerified on the win11 box, both spellings of the binary: completions.sh goes\nfrom 20 pass / 19 fail to 39 pass / 0 fail, exit 0. On macOS it stays 41 pass /\n0 fail (two more than Windows: zsh and fish are installed, so their -n gates\nrun). Full run-all.sh clean.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Run the four uncovered shell suites on Windows too\n\ncompletions, lsp, thottam and differential were outside the Windows CI\nloop's directory list. That list is a hand-maintained enumeration in two\nplaces in ci.yml rather than a glob, so a suite wired into run-all.sh is\ncovered on every platform except this one until someone edits both loops\n— and nothing says so out loud. completions/completions.sh had been\nfailing there the whole time, 19 of its 39 checks, seen only when\nsomebody swept tests/scheme/**/*.sh on the reference VM by hand.\n\nMeasured on that VM before wiring them in, because these run on every\nPR. The exact new list gives 46 pass, 0 fail, 28 skip (25 compile/\ngates, profile-json-escaping.sh, thottam-lifecycle.sh,\nrun-wasm-differential.sh — the last two are the newcomers' own skips:\ngit fixtures at POSIX paths, and no wasmtime on the runners).\n\ndifferential/run-differential.sh is the one real cost at ~9 minutes,\nagainst jobs that currently finish in about 6 and are capped at 40 and\n45. That roughly triples the step and still leaves most of the budget;\nit earns its place because cold-vs-warm .sbc cache agreement is exactly\nthe kind of thing a platform's path handling breaks.\n\nwindows.md now states the keep-in-step rule where the list is described,\nand its verification record is re-measured rather than adjusted: 46/0/28\non build 26200. The older 34/15/0 line is left as the point-in-time\nrecord it was, with the framing corrected so it no longer claims to\ndescribe the current CI set.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n---------\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>",
          "timestamp": "2026-08-04T22:26:27+05:30",
          "tree_id": "fbd02753ca25bb8d1e665855658c263bb5a4bf25",
          "url": "https://github.com/kaappi/kaappi/commit/d717d0b4d8e34df2e8dcc8b2fa55e8d533e78d54"
        },
        "date": 1785864582103,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.006302,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.222618,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.589212,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.858977,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.005546,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.045183,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.298468,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.054021,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.376192,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.166547,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.535739,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.304756,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.731238,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.839798,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.046371,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "48fe81d3f32b71d2f476075df51e7971b6ca0879",
          "message": "Move the REPL onto isocline for real multi-line editing (#2219)\n\n* Move the REPL onto isocline for real multi-line editing\n\nThe prompt read one physical line per call and joined continuation lines\nitself, so once Enter was pressed that line had left the editor: a typo on\nline 1 of a define, spotted on line 4, meant Ctrl-C and retyping the form.\nThis replaces linenoise with isocline, which holds a whole form in one buffer,\nso up/down move within the form and reach history only at its edges.\n\nThe vendored linenoise fork cannot close that gap. Its refreshMultiLine sizes\nthe screen with pure wrap arithmetic (rows = (pwidth+bufwidth+cols-1)/cols)\nand knows nothing about embedded newlines — which is why it folds pasted\nmulti-line text to \"[... N pasted lines ...]\" rather than drawing it. Teaching\nit newlines means rewriting its refresh engine, cursor motion, and up/down\nhandling. isocline is that rewrite, already done and shipping (it is Koka's\neditor). See kaappi#2218 for the full analysis, including why bestline is not\nthe answer.\n\nThe reader decides what is complete. parenDepth — a second, hand-written\nScheme scanner, 127 lines — drifted from the real one twice: kaappi#358 (char\nliterals and pipe-quoted symbols) and kaappi#542 (`#;` scanned as a line\ncomment). It is replaced by inputIncomplete, which asks\nReader.incomplete_input, the same scanner the file path uses, so the two\ncannot disagree about where a datum ends. The probe restores the newline the\neditor stripped: without it the reader refuses to finalize a token at\nend-of-buffer, since more bytes could extend it, and every bare atom typed at\nthe prompt would report UnexpectedEof and strand the session on \"  ... \". A\nnew record_spans flag keeps the probe from populating gc.source_spans with\ndatums it throws away — that table is never pruned.\n\nVendored at upstream 8d6dc1ef95b1b46711e66eb23d39d4467a0fcdac (v1.1.0), MIT.\nsrc/isocline.c #includes the other translation units, so it is one C file to\nthe build. Two patches, marked KAAPPI PATCH in the source and documented in\nvendor/isocline/PATCHES.md:\n\n  1. An input-completeness callback. Upstream submits on Enter unless the line\n     ends in a continuation character; a Lisp prompt needs the text, not the\n     keystroke, to decide.\n  2. Configurable history size. Upstream clamps every history to 200 entries\n     regardless of the request; repl.history-length defaults to 1000.\n\nEverything else falls out of the one-buffer model:\n\n  - findMatchingOpen and the accumulated_input splice are deleted. That hack\n    reached back across the continuation seam for paren matching; there is no\n    seam now, and isocline matches braces itself — limited to \"()\" because the\n    reader gives brackets no meaning (`0]` is KP1002).\n\n  - ic_highlight takes spans, so ~270 lines of ANSI emission become style\n    names and the c_allocator round-trip behind #234 has nothing left to get\n    wrong. Token rules are unchanged, split into scanHighlight so they stay\n    testable without a terminal, with 13 tests over spans rather than escape\n    substrings.\n\n  - ic_complete_word splits the word out of the buffer and splices the choice\n    back in, dropping the hand-rolled prefix arithmetic and its 1024-byte\n    ceiling, which silently discarded longer candidates. `,load` and `,import`\n    complete filenames now, which they never did.\n\nThree integration decisions, all recorded in docs/dev/repl.md. Brace insertion\nis off: auto-closing a paren makes every buffer balanced, and the completeness\ncallback would submit the moment one was typed — found by testing, not by\nreading. Prompt strings carry no escapes, since isocline measures the prompt\nto place the cursor; the theme reaches it through the ic-prompt style, with a\nnew ansiToIcStyle translating repl.color.*. And history persists on every\nsubmit with newlines escaped, so a crash no longer drops the session and\nmulti-line entries return editable rather than folded.\n\nWindows gets a real REPL for the first time. isocline drives the Windows\nconsole API directly — term.c and tty.c switch on _WIN32 — so the POSIX-only\nexclusion linenoise needed no longer applies; that platform had been falling\nback to a byte-at-a-time stdin loop with no editing, history, completion, or\nhighlighting. The build gate now keeps only WASI, and only so repl.zig still\ncompiles there: main.zig returns before reaching the REPL on that target.\n\nBehavior changes: comma commands now enter history, which isocline manages\nitself (recalling `,load foo.scm` seemed worth more than matching the old\nexclusion), and the \"  ... \" continuation prompt is gone — continuation lines\nare indented under the prompt instead.\n\nBehavior was verified by driving the real binary through a pty, not by\ninspection. The decisive case: type `(+ 1`, Enter, Up to line 1, ctrl-E, ` 10`,\nDown, `2)`, Enter → 13; line 1 was still editable after Enter. Also covered:\nmulti-line define, history recall of a multi-line entry, line/datum/block\ncomments spanning lines, strings across lines, #\\( literals, a stray close\nparen reported rather than hanging, and comma commands. The isocline patches\nwere verified the same way before the port, including running pristine\nupstream to confirm patch 2 is load-bearing (1000 entries stored where stock\nisocline stores 200).\n\nUnit suite, 2075 Scheme tests (0 fail, 1 skip), and zig fmt --check all pass;\ncross-compiles clean for x86_64-windows, aarch64-linux, aarch64-macos, and\nwasm32-wasi. Adds 12 tests for inputIncomplete, which had none, and 13 for\nscanHighlight. Docs: docs/dev/repl.md rewritten, vendor/isocline/PATCHES.md\nadded, plus windows.md, porting.md, architecture.md, understanding-map.md,\nREADME.md, CLAUDE.md, and CONTRIBUTING.md.\n\nNot verified: Windows was only cross-compiled, never run — the claim that its\nREPL works end-to-end rests on isocline's console backend, not on evidence.\n-Dgc-stress=true was also not run; it is worth a pass given the new\nper-keystroke reader allocations in inputIncomplete.\n\nCloses #2218.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\nClaude-Session: https://claude.ai/code/session_01KkyTMuGQGSqM1kpkM2aqGF\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Address review: align the last isocline gate, and test the theme bridge\n\nThree stale-comment/gate fixes and one genuine coverage gap, from the\nreview of this PR.\n\nmain.zig's `ic` still carried linenoise's POSIX-only exclusion, so it\nread `is_wasm or .windows` where build.zig and repl.zig both say\n`!is_wasm`. Three gates for one decision, and this was the odd one out.\nThe practical effect was smaller than it looks — repl.zig imports\nisocline.zig directly and is itself reachable from main.zig, so the\nwrapper compiled and type-checked on Windows regardless, and\nisocline.zig has no test blocks to lose. What the exclusion did cost was\nthe invariant: this import block is how a module's own tests become\nreachable, so the next test added to isocline.zig would have silently\nskipped the one platform the file exists to serve.\n\nTwo comments described code this PR deleted. `readReplLine`'s doc called\nthe plain stdin path \"the Windows fallback\" four lines after the block\nabove it correctly says only WASI falls back. And an inputIncomplete\ntest cited \"the highlighter's findMatchingOpen *does* pair brackets\" —\nfindMatchingOpen went with the linenoise matching-paren code. The\ndivergence it was describing is still real but different: scanHighlight\nstyles brackets with style_paren, and nothing pairs them, because\nsetMatchingBraces is given \"()\" alone.\n\nansiToIcStyle had no tests. It is the only bridge from config.zig's SGR\nescapes to isocline's style names, and every failure path returns \"\" —\nunrecognized escape, unparseable code, and a bufPrintZ that outgrows\napplyTheme's [32]u8 all render unstyled with nothing to notice. Three\ntests: the 16 colours plus the bold form, the inputs that must yield \"\"\n(including `none`'s empty string and a background colour, which must not\nbe mistaken for a foreground one), and — the one that would actually\ncatch drift — both built-in themes driven through the same eight fields\napplyTheme feeds, asserting each still maps. A table of hand-written\nescapes alone would keep passing while config.zig moved on.\n\nVerified: full unit suite, 2076 Scheme assertions, zig fmt --check, and\ncross-compiles for aarch64-windows, x86_64-windows, aarch64-linux and\n`zig build wasm`, plus the aarch64/x86_64 Windows *test* builds, which\nare what the gate change affects. The new tests were mutation-checked:\nthey fail when the expected style is wrong.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n---------\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-04T17:32:17Z",
          "tree_id": "58a45b703aaf5c74a4a78a4dd0f18f175423815f",
          "url": "https://github.com/kaappi/kaappi/commit/48fe81d3f32b71d2f476075df51e7971b6ca0879"
        },
        "date": 1785866811672,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.337154,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.487895,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.578788,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.050197,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00465,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046889,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.315182,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.06024,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.729586,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.242704,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.594024,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.283119,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.805151,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.654046,
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
          "id": "a7798d99eb3e3e8eec377251fd0f4bd97fdbb60e",
          "message": "Add paredit-style structural editing to the REPL (#2221)\n\n* Add paredit-style structural editing to the REPL\n\nFour keys now move a paren rather than a character: slurp (alt+shift+S),\nbarf (alt+shift+B), raise (alt+shift+R) and rotate (alt+y). On a Lisp\nprompt these are the edits worth having, and a character-oriented editor\nmakes every one of them tedious.\n\nThe transforms live in src/repl_sexp.zig as pure functions over\n(buffer, byte cursor), so they test without a terminal. The keys and the\nbuffer swap are KAAPPI PATCH 3 in the vendored editor; a pty-driven\nshell test covers that half, since nothing in Zig can reach it. This had\nto wait for the isocline migration — on one editable physical line per\ncall there is no whole form to restructure.\n\nkaappi#2216 proposed porting the four commands from bestline. Two of\nthem are not there to port: bestlineEditRaise is an empty stub, and\nbestlineEditRotate rotates the kill ring (emacs yank-pop) rather than\nthe datums of a form. The two that do exist walk runes with a mirror\nstack and no notion of strings, comments or character literals — the\nbug class the issue asked the port to avoid. So the scanner here takes\nReader.isDelimiter from reader.zig directly rather than copying it, and\nthe attribution is for the design and the keybindings, not the code.\n\nRotate keeps the head and cycles the arguments. Rotating the head too\nwould turn every call form into something unevaluatable ((+ 1 2) ->\n(1 2 +)), and the point of a cycle is that repeating it restores the\noriginal.\n\nAlso closes the divergence the issue noted in passing: the highlighter\npainted [ and ] like parens while the reader gives them no meaning\n(0] is KP1002). repl.isDelimiter is now an alias of Reader.isDelimiter,\nso the colors, the brace matcher, the reader and repl_sexp all agree.\n\nCloses #2216\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Make the REPL pty test fail loudly when the binary never starts\n\nReview of #2221 pointed at the exec path in the pty driver. The stated\nfailure mode does not exist — `pty.fork()` is called once at module top\nlevel, not in a loop, so a raising `os.execv` propagates and the child\nexits; it cannot fork again. Measured with a missing binary: process\ncount 596 -> 600, no growth.\n\nChasing it down did surface a real hole, and a worse one. A binary that\nnever started exited 77, which run-all.sh counts as a skip and reports\ngreen. The test could silently not-run. It now separates the two cases\nthat were being conflated: no output at all means the REPL did not\nstart, which fails; output without a prompt means no usable terminal,\nwhich still skips, because that is what keeps the emulated CI legs from\nflaking.\n\nThe bash side resolves $KAAPPI up front — a value with no slash through\nPATH, anything else as given — and fails with a clear message rather\nthan letting execv fail ambiguously. That also fixes the bare-command\nform, which dirname turned into $PWD/<name>.\n\nAlso mark against the raw buffer rather than the ANSI-stripped one.\nStripped indices are not stable: a read ending mid-escape leaves bytes\nthe regex cannot match yet, and they vanish once the rest arrives,\nshifting every index taken before that. Raw offsets only grow.\n\nThe child now execs or `_exit(127)`s, so it can never run the parent's\ncode and drop a traceback into the pty slave.\n\nRe-verified by mutation: with edit_sexp stubbed out the suite still\nexits 1, and each failure mode now returns the exit code it means.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n---------\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-04T19:51:00Z",
          "tree_id": "220148ceec35ec8df6df1beae427322b6199ae4b",
          "url": "https://github.com/kaappi/kaappi/commit/a7798d99eb3e3e8eec377251fd0f4bd97fdbb60e"
        },
        "date": 1785874784693,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.000411,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 5.981656,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.41491,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.159737,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004267,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.035801,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.220359,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.039242,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.066296,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.905619,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.197532,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.230073,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.281805,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.836963,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.034518,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "f74e87091d181a737aa0956cd14a886da3212145",
          "message": "Close the last two racing margins in srfi120.scm (#1870) (#2222)\n\n#2120 de-flaked five blocks in this file and pinned each in\nsrfi120-slow-setup.scm. Two of them were still racing a deadline\nafterwards, at 570 ms each -- the two smallest margins in the file, and\nthe two assertions netbsd-test actually went red on.\n\nBoth survived because \"schedule the deadline-bearing task LAST\" was read\nas removing every deadline, when it only removes the following *calls*.\nThe no-error-handler block's comment said so outright (\"nothing follows\nthe erroring schedule now, so there is no deadline left to lose\") while\n`should-not-fire`'s own 600 ms still had to outlast the erroring\ntimer-schedule! meant to stop the timer first. The timer-cancel! block\nscheduled `late` first, so its 600 ms covered the `early` receive as well\nas the cancel. The 200 ms pins #2120 left cannot see a 570 ms margin,\nwhich is why both looked covered.\n\nMargins are now measured rather than assumed -- each block's racy point\nwas injected with a delay and bisected for the value that breaks it:\n\n  block            was      now\n  task-remove      800 ms   800 ms   (unchanged)\n  reschedule      1000 ms  1000 ms   (unchanged)\n  period-0        2000 ms  2000 ms   (unchanged)\n  timer-cancel!    570 ms  1200 ms\n  no-handler       570 ms  1200 ms\n\ntimer-cancel! is fixed structurally, not by headroom: `late` is scheduled\nafter the `early` receive, which empties that window of deadlines\naltogether -- a 1.4 s stall between the receive and the schedule now\nchanges nothing, where 0.6 s used to fail. Only the cancel itself remains\ninside `late`'s 1200 ms. no-handler has no such reordering available, so\nits delay is widened to match the rest of the file.\n\nDetection is not traded away: both negative waits still outlast the delay\nof the task they disprove (R3), 1.5 s against 1200 ms.\n\nBoth slow-setup pins are raised 200 ms -> 800 ms, which exceeds the\nmargin the shape they replaced had, so each fails against that shape.\nMutation-tested: the new pins applied to the old blocks fail 3 of 5\nassertions, including both netbsd-test failures by name. The third is a\ncascade -- the negative wait returns early on the leaked value, so\ntimer-cancel! beats the erroring task and finds nothing to re-raise.\n\nAssertion counts unchanged (41 and 12). srfi120.scm 5.02 s -> 5.37 s,\nsrfi120-slow-setup.scm 3.80 s -> 5.49 s. Both files 25x under concurrent\nrun-all.sh load: 50/50.\n\nCloses #1870\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-04T20:47:09Z",
          "tree_id": "64741b458cab64db6a2ccb93aeacf58d7b5350b7",
          "url": "https://github.com/kaappi/kaappi/commit/f74e87091d181a737aa0956cd14a886da3212145"
        },
        "date": 1785878351892,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.957583,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.159905,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.563553,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.884068,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004938,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.045391,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.295501,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.056986,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.341157,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.162213,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.52503,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.305582,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.716301,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.766348,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045794,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "b92c85a5346c9274edde8c5ff208b7f8440f1d5e",
          "message": "Give a joined child's freed slots to the parent's quarantine (#2127) (#2223)\n\n* Give a joined child's freed slots to the parent's quarantine\n\nThe gc-stress use-after-free detector (#1687) could not see the one heap\nteardown that produces cross-heap dangling values in the first place.\nGC.deinit drained its quarantine unconditionally, so a joined SRFI-18\nchild's freed header slots went straight back to the allocator: the\nparent's next allocation recycled one, overwrote the FREED_OWNER\nsentinel, and the parent's next mark found a live-looking object. A\nstress run over a child-heap UAF was byte-identical to a release run and\nexited 0 -- for exactly the bug class the thread model makes most likely.\n\nThe drain itself is right; what was missing is that GC.deinit has two\nkinds of caller. At process exit there is nobody left to hold a dangling\npointer, so the allocator should have the slots back. At thread-join!\nthere is: a live parent with marks still to run. A GC can now name a\nquarantine_heir, and the join path names the parent, so the child's slots\nstay withheld until the parent's own release point -- and the panic that\n#1687 exists to raise actually fires.\n\nThe heir is set at the join site rather than in initForThread because the\nhandoff appends to the heir's quarantine, which has no lock; only the\njoining parent thread, past reapOsThread's thread.join(), knows nothing\nelse is still freeing on either GC.\n\nThis immediately turns #2027 into a deterministic panic in\nsrfi18-deepcopy-matrix-audit.scm, whose section E binds a child-created\nffi_function that the join aliases rather than copies. The file already\ndocuments that cell as `FAIL: #2027` and never dereferences the handle --\nthe collector is what trips, so no assertion can be commented out to\navoid it. It joins KAAPPI_GC_STRESS_SKIP under the existing \"real bugs\nthis gate found\" heading, for #2027's fix to delete.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Say that an heir with a different allocator gets no coverage\n\nThe heir paragraph described the choice as heir-or-drain, but naming an\nheir is only a request: quarantineHandOff refuses a heir whose allocator\nidentity differs, and refuses again if the transfer cannot be recorded,\ndraining in both cases. Neither refusal is reported anywhere, so a future\nteardown path wired across two allocators would read as covered and not\nbe. Say so where the decision is documented.\n\nReview feedback on #2223.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n---------\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-05T00:51:30Z",
          "tree_id": "5f7a0b1cba293ac23231838f84181341ce4742d1",
          "url": "https://github.com/kaappi/kaappi/commit/b92c85a5346c9274edde8c5ff208b7f8440f1d5e"
        },
        "date": 1785892995503,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.255621,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.62556,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.583356,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.966901,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00481,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.047618,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.315373,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.056187,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.817237,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.214982,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.621741,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.292963,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.824601,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.537982,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045839,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "e1accbb3173b555540be73512fb2aef4d096b0f9",
          "message": "Fix REPL comma-command TAB completion appending instead of replacing (#2225)\n\n* Fix REPL comma-command TAB completion appending instead of replacing\n\ncompletionCallback called ic.addCompletion directly for comma-commands\nlike ,help, bypassing ic.completeWord. isocline's ic_add_completion\ndefaults delete_before to 0, so it spliced the replacement in at the\ncursor without deleting the typed prefix first — TAB after ,h produced\n,h,help instead of ,help. Route the command-name branch through\nic.completeWord, same as scheme-identifier completion already does,\nso isocline computes the correct deletion from the word boundary.\n\nFixes #2224\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Bound REPL shutdown reap in the comma-completion regression test\n\nReview feedback on #2225: os.waitpid(pid, 0) after ,quit had no\ndeadline and the child's exit status went unchecked. Poll with\nWNOHANG up to 10s, kill and reap on timeout, and fail the test on a\nnonzero exit — so a future ,quit regression fails this test instead\nof hanging it (and, since the outer shell timeout only kills this\nscript's own pid, potentially the CI worker after it).\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n---------\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>",
          "timestamp": "2026-08-05T04:07:09Z",
          "tree_id": "6e17d93d8d719afef186bfad13142bf48946c05d",
          "url": "https://github.com/kaappi/kaappi/commit/e1accbb3173b555540be73512fb2aef4d096b0f9"
        },
        "date": 1785904766554,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.245023,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.088833,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.565924,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.95734,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004624,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.047225,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.308723,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.055784,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.731792,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.223572,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.604818,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.27998,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.789925,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.598997,
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
          "id": "9bc2de0dee0c23af91f79cdf0c72349d29f0e106",
          "message": "Root what the collector cannot see: SRFI-1 accumulators and the uid registry (#2228)\n\nTwo places parked a heap Value where the GC could not reach it and kept\nallocating, so the next collection reclaimed it and the code later read\nfreed memory.\n\nprimitives_srfi1 (#2160). buildList's caller-owned ArrayList(Value) is\ninvisible to the collector. That is harmless for elements the primitive's\nown args still reach, which is most of them -- but not for freshly\nallocated ones. kaappi#1027 rooted four callback-result accumulators and\nleft three siblings: list-tabulate (a callback result), zip (the row it\njust consed) and alist-copy (the entry it just copied). All three abort\nwith \"GC: marking freed object\" at three elements under -Dgc-stress=true;\nlist-tabulate also returns silently wrong data on a default build once the\nlist is long enough to cross the GC threshold.\n\nRooting inside buildList -- the fix the issue first suggested -- would not\nhelp: the element is already freed by the time the list gets built. The\nroot has to go on at the append, so all seven sites now share one\nappendRooted helper and buildList documents why it is not the place.\n\nrecord_uid_registry (#2161). The map does not own its keys, and\n%make-record-type-descriptor keyed off the uid argument's SchemeString\nbytes -- a string lib/srfi/237/base.sld makes fresh with symbol->string on\nevery call. Collect it and the key dangles, so a second definition with\nthe same uid stops finding the first and quietly builds a second,\nnon-interoperable type for one uid: exactly the R6RS guarantee\n`nongenerative` exists to provide, lost silently. Key by the new rtd's own\nowned uid copy instead, whose lifetime is the entry's -- the same thing\ngc_deep_copy.zig already does at its own insert into this map. The\nsyntactic path (vm_records.zig) keys off an interned symbol name and was\nalready safe.\n\nTests: src/tests_gc_runtime_stress.zig turns on the GC's runtime stress\nflag so the #2160 cases are deterministic at n = 3; pre-fix they abort\nunder -Doptimize=Debug and -Dgc-stress=true. #2161 is pinned as pointer\nidentity of the registry key, since observing the miss in-process needs\nthe freed bytes to be reused, which a unit test cannot arrange. Both also\nget corpus assertions that fail pre-fix -- srfi1-gc-stress.scm on a plain\nbuild as well as stressed, srfi237.scm on the stressed leg.\n\nThat lets the six files this gate found the bugs in come off\nKAAPPI_GC_STRESS_SKIP in ci.yml, as that list's own comment requires.\n\nCloses #2160\nCloses #2161\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>",
          "timestamp": "2026-08-05T11:10:53+05:30",
          "tree_id": "a465307999ebabddc41e0820db232fe1078b4aa1",
          "url": "https://github.com/kaappi/kaappi/commit/9bc2de0dee0c23af91f79cdf0c72349d29f0e106"
        },
        "date": 1785910333181,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.280883,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.964826,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.567328,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.939577,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004636,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.047281,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.309849,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.055618,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.655247,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.223715,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.580448,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.27493,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.774589,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.584749,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043005,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "9e50a1200f4a6c0dc0adc9bdb48c7f0043ac6c31",
          "message": "Stop discarding pasted input when the REPL drops out of raw mode (#2227)\n\n* Stop discarding pasted input when the REPL drops out of raw mode\n\nPasting a block with more than one top-level Scheme form into the REPL only\nevaluated the first form; everything after it silently vanished. Terminals\ncommonly deliver a pasted newline as a literal CR, the same byte a real Enter\nkeypress sends, so once the first form was complete on its own,\nisCompleteCallback submitted right there and ic_editline returned before the\nrest of the still-unread paste had even been read from the pty.\ntty_start_raw/tty_end_raw (vendor/isocline/src/tty.c) used TCSAFLUSH on every\nraw-mode transition, which discards exactly that unread input. Switch both to\nTCSADRAIN, which waits for pending output but leaves unread input alone.\n\nFixes #2226\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Detect signal-terminated REPL shutdown in the paste regression test\n\nAlso carry over the skip-vs-fail rationale comment from\nrepl-structural-editing-2216.sh at the same call, so a future reviewer of\nthis file doesn't have to rediscover why a missing prompt after real output\nis a skip rather than a failure.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n---------\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>",
          "timestamp": "2026-08-05T11:11:17+05:30",
          "tree_id": "949bd98179fea963b941f6800f56d10e45f13c3a",
          "url": "https://github.com/kaappi/kaappi/commit/9e50a1200f4a6c0dc0adc9bdb48c7f0043ac6c31"
        },
        "date": 1785911131993,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.264674,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.634688,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.590761,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.958973,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004699,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.047049,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.312081,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.055955,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.684729,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.224335,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.587427,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.285688,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.793822,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.704496,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044126,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "b02ecb256dc8a6adc73a82858145981edc6e0864",
          "message": "Give records and FFI handles an identity that survives a heap copy (#2229)\n\n* Give records and FFI handles an identity that survives a heap copy\n\nBoth issues are the same mistake in gc_deep_copy.zig, from opposite\ndirections: a value's identity was its address, and every thread boundary\ncopies into a heap where the address is necessarily different.\n\n#1932 — a record type's identity WAS its RecordType pointer, so the copy\nwas a disjoint type. A record returned by thread-join! printed as a\nwell-formed `#<<pt> 1 2>` while `pt?` answered #f and every accessor\nraised, which means a `cond` dispatching on the predicate silently took\nthe wrong branch. RecordType gains an `identity` u64 from a process-global\natomic counter, minted at definition and carried verbatim by the copy;\n`types.sameRecordType` replaces the four pointer comparisons behind\n`%record?`, `%record-ref`, `%record-set!` and SRFI 237's inheritance walk.\nGenerativity is untouched — two evaluations of a define-record-type form\nstill mint two identities — and that is the control the tests pin.\n\n#2027 — the `.ffi_library`/`.ffi_function` arm returned `src`, on the\nreasoning that a dlopen handle cannot be duplicated per-heap. True of the\nhandle; the WRAPPER is an ordinary object owned by one GC, and marking\nskips foreign-owner objects, so the receiver held a reference neither\ncollector could see. The sender's own collector reclaimed it — running or\nnot, so `channel-send` was affected too — and the recycled slot read back\nas `(0.0 . 0.0)`, an ordinary pair that passes every non-FFI type check.\nThe wrapper is now copied like `.native_fn`, with the process-global\nhandle and symbol shared by value. Refusing the tag was the other option\nand is why the parent-owned-handle controls are in the test: they work\ntoday and a refusal would have broken them.\n\nFour disabled audit assertions across three files are re-enabled, and two\nbug-presence pins are replaced rather than inverted (docs/audit-strategy.md:\n\"never assert that a bug is still present\" — #2027's own pin is the\ncautionary case).\n\nCloses #1932\nCloses #2027\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Fix the wasm build and the OpenBSD hang in the new FFI test\n\nTwo CI legs, two separate causes:\n\nwasm32 has no 64-bit atomic RMW, so `std.atomic.Value(u64).fetchAdd` on the\nrecord-type identity counter failed to compile. The counter stays u64 —\nunlike `next_gc_id` and the expander's scope ids it cannot tolerate\nwrapping, since two types sharing an identity are silently interchangeable,\nwhich is the bug this whole change is about. Instead the RMW is skipped\nentirely under `builtin.single_threaded`, which is how `zig build wasm`\nbuilds and where there is no concurrent minter to race with. A future\n32-bit target built WITH threads fails to compile on the atomic branch\nrather than racing silently.\n\nThe new FFI test hung on OpenBSD for 60s. Two things had to go wrong\ntogether: OpenBSD's libm exports no `fabs`, so every handle in the file\nfailed to construct; and the channel section's child then raised BEFORE\nits `channel-send`, leaving the parent blocked in `channel-receive`\nforever. Both are fixed rather than just the first — a test that deadlocks\nwhen its subject is unavailable is a worse failure than the one it was\nwritten to catch. The symbol is now `sqrt`, which ffi/basic.scm already\nproves resolvable on every leg; the child's send is wrapped in a `guard`\nthat sends a sentinel on failure, so a broken cell fails an assertion\ninstead of hanging; and a one-time probe skips the file cleanly where no\nlibm loads, the same shape srfi18-deepcopy-matrix-audit.scm uses.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Address review: one real UAF in a test, two vacuous assertions\n\nFive of the seven review findings were real. Verified each rather than\ntaking it on trust; two are declined with reasons.\n\nThe one that mattered: the new record-identity unit test read a FREED\nRecordType. `rt` is dereferenced for `identity` after two more gc1\nallocations, this bare GC has no root marker, and allocRecordTypeExtended\nroots only its `parent` argument — so under -Dgc-stress=true the header was\nswept before the last assertions. Probed it directly: the tag comes back an\ninvalid enum value. The test passed only because the garbage identity\nhappened not to collide with a real one. `rt_val` and `ext_val` are now\nrooted; re-ran under -Dgc-stress=true -Doptimize=Debug, where freed memory\nis poisoned, to confirm.\n\nTwo assertions could not fail. `(not (mrec2? (join-thunk ...)))` passes when\nthe join RAISES, because mrec2? answers #f to the (RAISED ...) list — and\nthat row is the control that constrains the whole fix. `(on-thread ...)` used\nas a truth value passes on a raise too, since on-thread answers a truthy\n(raised . msg). Demonstrated both against a deliberately raising thunk, then\nre-ran the two audit files against a pre-fix binary: the tightened\nlook-alike row now fails there, where before it passed vacuously.\n\nAlso: the matrix audit's section E header still described the aliasing this\nPR removed, contradicting the file's own class table twelve lines up; and\nthe channel cell's `thread-sleep!` guaranteed nothing about the child still\nrunning, so it could silently degrade into the cell above it — replaced with\na second-channel handshake that cannot deadlock from either side.\n\nDeclined, with reasons in the PR thread: splitting tests_gc_tracing.zig\n(1730 lines before this branch touched it, +1 line here, unrelated to either\nissue), and equating identities on gc_deep_copy's uid-reuse path — the\ndivergence is unobservable because the .record_instance arm retypes the\ninstance to the reused rtd, and overwriting that rtd's identity would\nsilently retype every instance already living under it in the destination\nheap. Probed all five nongenerative shapes, including the rtd and an\ninstance crossing together; all correct.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n---------\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>",
          "timestamp": "2026-08-05T08:14:56Z",
          "tree_id": "e0d811a9fab6298001e40c2bdcec8bad01eac78e",
          "url": "https://github.com/kaappi/kaappi/commit/b02ecb256dc8a6adc73a82858145981edc6e0864"
        },
        "date": 1785919425959,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.945144,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.825074,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.564146,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.885943,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004904,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.045246,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.29447,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.054313,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.378192,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.162046,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.520384,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.305726,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.695666,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.782346,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045259,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "5c9b8901679235d4fa912608b56e52914d8f4d35",
          "message": "Fix four SRFI-18 concurrency bugs from the v0.22.2 audit (#2129, #2194, #1982, #2125) (#2230)\n\n* Drive the scheduler for never-dispatched fibers in thread-join! (#2194)\n\nthread-join!'s never-started path polled fiber.status in a sleepNs loop\nwithout ever driving the cooperative scheduler. That is right for a\nmake-thread handle awaiting thread-start! from outside (#878) -- the\nstatus changes externally -- but a (kaappi fibers) spawn'd fiber can\nonly ever be dispatched by the joining thread's own scheduler, and the\npoll loop is exactly what starves it: the status never changes, so the\njoin hung forever (or reported a timeout) on a fiber that would have\ncompleted instantly. fiber-join on the same object returned immediately.\n\nDiscriminate the two by sched_idx, which addFiber alone sets: a\nmake-thread object is never added to any scheduler and leaves it at 0,\nso it keeps polling; a spawn'd fiber (sched_idx != 0) falls through to\nthe fiber path, which drives the scheduler. os_thread alone is not a\nsafe discriminator -- a handle about to be started has os_thread ==\nnull for the whole window before thread-start!'s std.Thread.spawn and\nmust keep polling.\n\nEvery regression probe is deadline-bounded so a regression fails loudly\nwith 'timed-out instead of wedging the test runner.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Unwind native SRFI-18 waits on thread-terminate! (#1982)\n\nThe bytecode safepoint polls VM.terminate_flag every 1024 instructions\n(#933), but only while executing bytecode. thread-sleep!, mutex-lock!\nand mutex-unlock!'s condvar branch each wait inside runSchedulerStep's\nnative loop, so a thread parked there never observed the flag:\nthread-terminate! flipped the handle's status to .errored from the\nparent, the join's poll exited immediately, and reapOsThread's\nthread.join() then blocked forever on a child that would never unwind.\n\nrunSchedulerStep now checks termination at the top of every loop\niteration and unwinds with VMError.Terminated, exactly like the\nsafepoint. The check reads both the VM's terminate_flag (an OS-thread\nchild reaches its parent-heap handle's flag that way) and the fiber's\nown terminated flag (a local fiber IS the handle), so the fix covers\nthe SRFI-18 waits, the (kaappi fibers) channel/fd waits, and the\nlocal-fiber sibling-terminate case in one place.\n\nSleepWait gains pollCapNs so a sleeping thread wakes at the 1ms\ncross-thread cadence and observes the flag; without it the sleep park\nblocks for its full duration with nothing to wake it. The cap applies\nonly when another OS thread exists to terminate this one; solo sleeps\nstay a single true reactor block. MutexWait/CondVarWait already had\ntheir caps, and their outer retry loops propagate the Terminated error\nthrough the existing try.\n\nThe wait-context duck-type comptime test moves from 2 to 3 poll caps\n(SleepWait's is a terminate-abort cap, not a resolution path) and\ndocuments why.\n\nRegression test: all four native-wait shapes now terminate promptly\nand the two controls (mutex released, condvar broadcast) still join\nnormally with the thunk's value. Shared mutexes/condvars are top-level\nglobals -- a lexically captured sync primitive is deep-copy-rejected at\nthread-start! and would make the terminate probes pass vacuously.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Report the owner thread handle, not the internal fiber, from mutex-state (#2125)\n\nMutex.owner tracks the fiber that acquired the lock, which is what\nabandonFiberMutexes compares against on fiber death. For an OS-thread\nchild that fiber is the child-heap current fiber (fiber 0 of the\nchild's own heap): mutex-state returned it, so the owner it reported\nwas not eq? to any thread the caller holds, and it was a dangling\npointer once the join freed the child heap (the #2127 quarantine was\nthe detector-side mitigation, not the fix).\n\nRecord the owner thread handle alongside the owner: a new\nMutex.owner_thread field, set at every owner write site. For an OS-\nthread child it is the parent-heap handle make-thread returned, so the\nparent's GC owns and marks it; for a local/main thread it is the owner\nfiber itself (the fiber IS the thread there). threadEntryFn stashes the\nhandle on the child VM (vm.thread_handle, foreign to the child GC and\nrooted by the parent, so no write barrier is needed), and mutex-lock!'s\nfast and slow paths resolve it the same way they resolve the owner,\nhonouring an explicit SRFI-18 owner argument. mutex-unlock! and\nabandonFiberMutexes clear both fields together.\n\nmutex-state returns owner_thread for the owned state; the two unowned\nstates are unchanged. The whole exposure is closed: the value handed\nout is always a parent-heap object that stays valid past join, so the\nobvious synchronisation idiom `(eq? (mutex-state m) t)` finally works.\n\nThe existing cross-heap-abandoned-mutex test's \"held\" probe was a\nworkaround for this (excluding the two unowned symbols); it is now the\nreal eq? comparison, which is also the regression shape -- it spun to\nits retry budget pre-fix. New regression test pins the issue's exact\nshape: child-held mutex reports the handle, thread?, the captured owner\nsurvives the join that frees the child heap, and the local-thread and\nexplicit-owner-argument cases are unchanged. GC tracing pins updated\nfor the new Mutex field.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Chain every thread's shared state to the root VM, never the spawning thread (#2129)\n\nthreadEntryFn's prologue dereferences the spawning thread's VM and GC:\nGC.initForThread reads parent_vm.gc for the shared symbol tables\n(shared_symbols = &parent.symbols, used by every symbol interning for\nthe thread's whole life), and VM.initForThread reads the parent's\nshared maps. freeChildResources had no interlock, so joining a thread\nthat had itself called thread-start! freed its GC/VM out from under the\ngrandchild -- mid-prologue (the deepCopy of its thunk interns symbols\ninto the freed table) or later, at its next symbol interning. The crash\nreproduced at 18/20 runs (ReleaseSafe) and 13/15 (gc-stress): \"a\nthread that spawns a thread and returns\" is an ordinary shape.\n\nChildren now receive the ROOT VM from threadStartImpl instead of the\nspawning thread's: VM.root_vm is resolved in initForThread by walking\nthe parent chain (`parent.root_vm orelse parent`, null on the root\nitself), and threadEntryFn uses it for both GC.initForThread and\nVM.initForThread. Every descendant therefore chains its symbol tables,\nforeign_symbols and shared maps to the root's, which lives for the\nwhole process -- a middle thread's own tables stay empty and its\nGC/VM can be freed at its join without anything a descendant holds\npointing into them. The VM-level shared maps were already root-owned\n(root.globals == middle.globals by pointer), so the only behaviour\nchange is the symbol-table root.\n\nThe thread_handle added for #2125 is recorded only when the handle is\nroot-heap (fiber.header.owner == root_vm.gc.id): a middle thread's\nhandle lives in the middle's heap and is freed at its join, while a\ngrandchild's mutex-state query can outlive that join -- a recorded\nmiddle-heap handle would dangle (the gc-stress detector caught exactly\nthis). Such a child falls back to its own current fiber (never freed:\ngrandchildren of a joined thread are un-joinable), the pre-#2125\nbehaviour.\n\nRegression test runs the discriminating shape 30 times (pre-fix it\ncrashed the process on the vast majority of runs) plus the two\ncontrols from the issue: a middle that joins its own child first, and\na middle that spawns nothing.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Address review comments on the SRFI-18 audit PR (#2230)\n\n- mutex-lock! (both paths): compute the owner and owner-thread values\n  before publishing either and store owner_thread first, so a concurrent\n  mutex-state can never observe a partially initialized owner pair;\n  mutex-state now gates on owner_thread alone (single-field read, no\n  cross-field race) instead of gating on owner and returning owner_thread.\n- runSchedulerStep's termination unwind now sets the same \"thread\n  terminated\" error detail the bytecode safepoint does, so a local fiber\n  terminated mid-wait surfaces a real message at the top level instead of\n  a contentless `error[KP9000]: error`.\n- waitTerminated moved above the ~40-line doc block it was stealing from\n  runSchedulerStep (Zig binds /// to the next declaration), and the loop-top\n  termination comment moved from the top of the function body to the check\n  it describes, next to the unrelated SRFI-181 guard it was shadowing.\n- SleepWait.pollCapNs documents the measured cost of the 1ms cap on child\n  threads (~5k involuntary switches for a pair of multi-second sleeps vs\n  33 without; linear in duration and thread count) and the notifier-based\n  follow-up.\n- srfi18-join-created-fiber-2194.scm pins the other half of the sched_idx\n  discriminator: a never-started make-thread handle joined with a deadline\n  times out (the #878 poll path) rather than raising the fiber path's\n  deadlock error, and the same handle then starts and joins normally.\n- srfi18-join-spawn-grandchild-2129.scm: 12 iterations instead of 30 (the\n  un-joinable grandchildren leak by design), and the header now documents\n  the known residual -- the grandchild's middle-heap handle is freed at the\n  middle's join and dereferenced (terminate_flag/status) for its whole\n  life; pre-existing, silent under the default allocator, a live\n  use-after-free under Guard Malloc. The test pins only the symbol-table\n  half this PR fixed; the handle half stays tracked in #2129.\n- docs/dev/thread-value-sharing.md and CLAUDE.md: the globals route and the\n  GC.initForThread/VM.initForThread table rows now say the shared symbol\n  tables and maps chain to the ROOT's, not the immediate parent's\n  (kaappi#2129) -- the distinction the fix turns on.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n---------\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>",
          "timestamp": "2026-08-05T20:11:16+05:30",
          "tree_id": "95a07608327520c43935329ac0c14def02170edf",
          "url": "https://github.com/kaappi/kaappi/commit/5c9b8901679235d4fa912608b56e52914d8f4d35"
        },
        "date": 1785942775449,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.016828,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.508448,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.557474,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.053801,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004855,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.044802,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.296341,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.05355,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.30413,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.171277,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.511165,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.300971,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.699406,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.638527,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045129,
            "unit": "seconds"
          }
        ]
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
          "id": "65bc8ff84bb335765b4ab28f2c972e9d23e024ba",
          "message": "Retire a joined thread's resources while its descendants are live (#2129)\n\nthread-join! unconditionally destroyed the joined thread's GC and VM\n(freeChildResources) even when that thread had itself started other\nthreads. A descendant dereferences its own fiber handle -- the\ndispatch-loop safepoint polls its `terminated` flag every 1024\ninstructions, and the terminal `status` store happens at exit -- for its\nwhole life, not just its startup prologue. That handle lives in the\nspawning thread's heap, so the join freed the grandchild's handle out\nfrom under it: a use-after-free for the grandchild's entire remaining\nlifetime, silent under the default allocator and a live crash under\nGuard Malloc. Reachable from any \"worker kicks off a background task and\nreports back\" shape, and from (srfi 120)'s make-timer inside a thread\n(the timer thread is meant to outlive make-timer, so the middle thread\ncannot join it -- which is why the crash was 24/30, not a corner).\n\nThe previous fix (PR #2230) chained every thread's shared symbol tables\nand maps to the ROOT VM, closing the prologue half. This closes the\nhandle half:\n\n- Fiber gains `live_descendants`, incremented in threadStartImpl on the\n  SPAWNING thread's own handle (vm.thread_handle, now set unconditionally\n  so the count is maintained for every thread, whatever heap the handle\n  lives in) and released by the child's threadEntryFn defer once the\n  child's OWN subtree has drained. The drain matters: my descendants'\n  defers dereference my fiber, so releasing my spawner's count early\n  would let its join free the heap I live in under a still-running\n  descendant. The wait cannot hang the spawner's join -- the join does\n  not join me, and the threads I wait for make progress independently.\n\n- reapOsThread now RETIRES the child_registry entry when the joined\n  thread has live descendants instead of freeing it; the last\n  descendant's defer frees the retired entry (fetchRemoveIfRetired) once\n  the subtree drains. thread-join! itself still returns immediately, and\n  retirement is bounded unless a descendant genuinely never finishes\n  (then the resources last until process exit, the #1792 pattern). The\n  markRetired re-read closes the race where the last descendant already\n  passed its fetchRemoveIfRetired window before the entry was retired.\n\n- mutex-lock!'s owner_thread reporting now guards the (now-unconditional)\n  thread_handle with a root-ownership check (reportableOwnerHandle), so a\n  middle-heap handle still never escapes into a mutex that can outlive\n  the middle's join -- the #2125 behavior is unchanged.\n\nTests: srfi18-join-spawn-grandchild-2129.scm grows a busy-grandchild\nvariant (safepoints + symbol interning past the join) and a deep-chain\ncontrol (middle joins g where g spawned an unjoined gg; the join chain\nmust wait for gg -- pinned observably, and it fails without this fix).\nsrfi120-thread-boundary.scm now asserts the make-timer-inside-a-thread\nshape live instead of commenting it out: the join raises the documented\n\"uncopyable type\" error cleanly instead of aborting the process.\n\nVerified: m7.scm 25/25 and the srfi-120 repro 25/25 clean on ReleaseSafe\nand under -Dgc-stress (issue measured 22/25 and 24/30 crashes pre-fix);\nfull run-all.sh 2085/2085; unit suite green including -Dgc-stress=true;\nWASM build still compiles.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>",
          "timestamp": "2026-08-05T21:49:44+05:30",
          "tree_id": "0b3ba722908755f4a8f449f6443cb1fae2643698",
          "url": "https://github.com/kaappi/kaappi/commit/65bc8ff84bb335765b4ab28f2c972e9d23e024ba"
        },
        "date": 1785948710012,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.301459,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.813651,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.561917,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.944593,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004633,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.04646,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.308392,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.05736,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.636149,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.237584,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.57093,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.275066,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.822825,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.602592,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043048,
            "unit": "seconds"
          }
        ]
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
          "id": "006b263e53a6ba8ec6b460d1019240be929c2ef0",
          "message": "Release v0.22.2\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>",
          "timestamp": "2026-08-05T23:00:19+05:30",
          "tree_id": "ca31edb5295e922e75cd3ebf59cb381daa97c52a",
          "url": "https://github.com/kaappi/kaappi/commit/006b263e53a6ba8ec6b460d1019240be929c2ef0"
        },
        "date": 1785953281921,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.334868,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.979594,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.566515,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.954446,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00463,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.04699,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.308918,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057278,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.641668,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.22866,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.586526,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.278009,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.831381,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.456433,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043538,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "bc7cad87bbb16eeb2d6c78b9ddb5c41dc420110e",
          "message": "Add a pi harness porting the Claude Code hooks (#2234)\n\nPorts the repo's .claude/hooks/* enforcement to pi extensions, so pi\nsessions get the same guards with pi's strengths on top:\n\n- zig fmt on every edit/write of a .zig file (zig-fmt-post.sh), skipped\n  for vendor/ and .zig-cache/\n- destructive bash command gate (bash-guard-pre.sh) with the same five\n  patterns, upgraded from a hard block to a confirm dialog (and still\n  blocked outright when there is no UI to ask)\n- DCO: every git commit gets -s injected before execution — the repo's\n  commit convention, previously advisory only\n- zig build test when the agent settles, run only when a .zig file\n  changed since session start (test-on-stop.sh, using agent_settled\n  which fires only when no retry/compaction/follow-up is left)\n\n.pi/settings.json enables /skill:name commands. The repo's Claude skills\nare already discovered by pi through the existing .agents/skills symlink,\nso no duplicate skills entry is needed.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>",
          "timestamp": "2026-08-06T01:01:27+05:30",
          "tree_id": "e011a113132273899cab71c5a0edf0349310e994",
          "url": "https://github.com/kaappi/kaappi/commit/bc7cad87bbb16eeb2d6c78b9ddb5c41dc420110e"
        },
        "date": 1785961436920,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.07159,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.915831,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.442244,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.187533,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00376,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.034823,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.23137,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.041772,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 1.853427,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.902043,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.180289,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.238592,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.323716,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.399445,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.035545,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "d827dd29e966bc6629992092be5ae368c4701bf8",
          "message": "Fix bundled-binary argv, stale-bundle failures, and -dirty build id (#2010, #1930, #2097) (#2232)\n\n* Fix bundled-binary argv, stale-bundle failures, and -dirty build id\n\nThree issues in the -Dbundle standalone path and the build-id machinery\nthat feeds it, fixed together because they are the same class:\n\n#2010: a bundled binary is the bundled program, so its whole argv belongs\nto that program's (command-line). cli.parse swallowed subcommand words\n(\"check\", \"fmt\", \"ast\", \"compile\") and pre-VM dispatch ran\n\"explain\"/\"doctor\"/\"test\" instead of the bundled program — silently,\nleaving a shorter argument list. Bundled mode now bypasses kaappi's\nargument parsing entirely (parseBundled) and skips the pre-VM subcommands\nand the --sandbox pre-scan; (command-line) is the full argv after argv[0].\n\n#1930: the .sbc's compiler hash folds in the producing binary's git build\nid, so a tree that moved (new commit, or clean<->dirty flip) between\nproducing a .sbc and building the bundler made the binary reject its own\npayload as foreign — \"invalid embedded bytecode\", which read like a\nserialisation bug. The fatal diagnostic now names the two build ids and\nthe fix (classifyEmbeddedRejection over the .sbc header), and the test\nharness no longer trips on the same mismatch: bundle_fixture_binary and\ncompile-toplevel-side-effects-2156.sh build the interpreter into an\nisolated prefix from the same source as the bundler and produce the .sbc\nwith that binary, so the two steps cannot disagree. New regression test\nbundle-args-2010.sh shares the existing fixture (a cache hit, not a third\nfull rebuild).\n\n#2097: gitBuildId counted untracked files as uncommitted changes, so a\nbrand-new file silently flipped every later build id to -dirty and\ninvalidated an existing zig-out/bin/kaappi built moments earlier. An\nuntracked file is not part of a tracked-source build's output; gitBuildId\nnow uses M  CHANGELOG.md\nM  build.zig\nM  docs/dev/cache.md\nM  docs/dev/test-runner.md\nM  src/bytecode_file.zig\nM  src/cli.zig\nM  src/main.zig\nM  tests/scheme/CLAUDE.md\nA  tests/scheme/compile/bundle-args-2010.sh\nM  tests/scheme/compile/compile-import-error-703.sh\nM  tests/scheme/compile/compile-preamble-gc-700.sh\nM  tests/scheme/compile/compile-toplevel-side-effects-2156.sh\nM  tests/scheme/compile/fixtures/bundle-replay/main.scm\nM  tests/scheme/shell-common.sh, keeping committed-but-modified\nand staged files dirty.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Address review comments on #2232\n\nTwo CodeRabbit findings, both valid:\n\n- bundle-args-2010.sh: KAAPPI was unused (SC2034). Add the\n  interpreter-as-oracle no-argument baseline via interp_stdout +\n  assert_tiers_agree, per the repo's tier-comparison convention\n  (tests/scheme/CLAUDE.md). With no args the bundled (command-line) is ()\n  and the interpreter's is (\"main.scm\"), so the fixture's conditional\n  cmdline print is silent on both tiers and the two must agree exactly.\n  The per-argument golden assertions stay golden on purpose: bundled\n  (command-line) intentionally differs from direct source execution.\n\n- build-id-untracked-2097.sh (new): the #2097 contract — an untracked\n  file must not mark the git build id -dirty — had no regression test.\n  Exercises gitBuildId end-to-end through {\"version\":\"0.22.2\",\"build_id\":\"006b263\",\"target\":\"aarch64-macos-none\",\"build_mode\":\"ReleaseSafe\",\"gc_stress\":false,\"sandbox_available\":true,\"features\":[\"r7rs\",\"kaappi\",\"ieee-float\",\"exact-closed\",\"exact-complex\",\"kaappi-fibers\",\"kaappi-reactor\",\"kaappi-diagnostics\",\"posix\",\"kaappi-threads\"],\"srfis\":{\"builtin\":[1,9,13,18,39,69,133,170,192,254,258,260],\"portable\":[0,2,4,5,6,7,8,11,14,16,17,19,23,25,26,27,28,29,30,31,34,35,36,37,38,41,42,43,44,45,46,48,51,54,57,59,60,61,62,63,64,66,67,70,71,74,78,86,87,90,94,95,98,101,111,112,113,115,116,117,118,120,123,125,126,127,128,129,130,131,132,134,135,136,137,139,140,141,143,144,145,146,147,148,149,150,151,152,153,156,158,161,162,164,165,166,167,168,169,171,173,174,175,178,180,181,185,188,189,190,193,194,195,196,197,201,202,203,207,209,210,213,214,215,216,217,219,221,222,223,224,225,227,228,229,231,232,233,234,235,236,237,238,239,240,241,242,244,247,248,250,251,252,253,255,257,259,263,264,267,270,271]},\"limits\":{\"initial_frame_capacity\":480,\"initial_register_capacity\":2048,\"gc_initial_threshold\":8192}} on\n  three isolated-prefix builds: pristine -> \"<hash>\", +untracked file\n  -> unchanged, +staged -> \"<hash>-dirty\". Skips when the working tree\n  is not pristine, since the contract is unobservable then.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Fix the oracle baseline's binary path in bundle-args-2010.sh\n\ninterp_stdout cds into its workdir, so the default relative\nzig-out/bin/kaappi path no longer resolved there (exit 127, empty\nstdout) and the new no-argument oracle baseline failed. Resolve an\nabsolute path up front, as the other tier-comparing scripts do.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Move the build-id test to the cache suite so it cannot race compile/ (#2232)\n\nThe new build-id-untracked-2097.sh broke CI (second run: 700/703 timed\nout at 300s, 2156 failed). Two compounding causes, both from putting the\ntest in the compile suite:\n\n- It stages a file in the shared working tree (phase C), which flips the\n  git build id for any OTHER concurrent builder. 2156 builds its .sbc\n  with a clean-tree interpreter and its bundler after, so the staged\n  window made the bundler reject the .sbc as foreign — the exact\n  kaappi#1930 mismatch class this PR fixes, reproduced locally.\n\n- Its three isolated-prefix builds run un-locked and concurrently with\n  the -Dbundle scripts' builds; on a cold 4-core runner the CPU\n  contention pushed the lock-waiting 700/703 past the 300s timeout.\n\nrun-all.sh runs the shell suites sequentially, Cache after Compile, so\nthe cache suite is the right home: the test runs alone (the other cache\nscripts never rebuild) on the ReleaseSafe units the compile suite just\nwarmed, and its staged phase races no one. Verified locally: compile\nsuite back to the first-run passing set, cache suite green, warm-cache\ncost of the three phases 1.3s.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Document why the build-id test lives in the cache suite\n\nAdds the reasoning (staged-phase tree mutation must not race concurrent\nbuilders; Cache runs after Compile in run-all.sh so the ReleaseSafe units\nare warm) to the test's own header, so the placement survives contact\nwith future edits.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Give the compile suite a realistic shell-test budget in CI\n\nThe Debug leg's -Dbundle fixture build is cold: the Build step above\nwarms only this leg's own optimize, so the compile suite rebuilds the\nwhole interpreter as ReleaseSafe from scratch (~180s idle, kaappi#1926)\nand under runner load has sat within seconds of the 300s default shell\ntimeout — passing at 270s in one run, timing out at >300s in the next,\nwith identical code. The per-file KAAPPI_TEST_TIMEOUT comment already\nstates the policy: catch hangs, don't race the slowest legitimate suite.\nRaise KAAPPI_SHELL_TEST_TIMEOUT to 600s for the test job's run-all.sh\n(the compile suite's legitimate budget), leaving the run-all.sh default\nuntouched for local runs and the other shell suites.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n---------\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>",
          "timestamp": "2026-08-06T10:37:32+05:30",
          "tree_id": "0fd276b1d9ef47a7767b68823bb553529e7cdd5e",
          "url": "https://github.com/kaappi/kaappi/commit/d827dd29e966bc6629992092be5ae368c4701bf8"
        },
        "date": 1785995065185,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.984792,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.484181,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.575803,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.827121,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004862,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.044854,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.294888,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.054604,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.334545,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.279165,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.517563,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.305397,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.711541,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.843427,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.048025,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "ebc0cb3299e49645097b11fc01c75c498a9a5a87",
          "message": "Fix three SRFI audit defects: hashmap comparators, bag clamps, eager-comprehension early exit (#2233)\n\n* Fix three SRFI audit defects: hashmap comparators, bag clamps, eager-comprehension early exit\n\nThree wrong-result/hang bugs found by the systematic audit, all in portable\nSRFI libraries. One PR because each is a small, self-contained library fix.\n\n(srfi 146 hash) discarded its comparator (#2044). Every constructor built a\nbare (make-hash-table), so key identity was always equal? regardless of the\ncomparator the caller supplied — 1 and 1.0 stayed distinct keys under a\ncomparator whose equality is =, and a case-insensitive string comparator\nnever matched Foo to foo, while the ordered (srfi 146) sibling got both\nright. All nine make-hash-table call sites now thread the comparator\nthrough; the built-in SRFI-69 table detects the <comparator> record and\nfalls into .custom mode, calling its equality and hash functions.\n\nSRFI-113 bags could hold negative multiplicities (#2085). bag-increment!\nignored the spec's \"but not less than zero\" clamp, and bag-product never\nvalidated n (the reference implementation's valid-n discards its result),\nso bag->list, bag-for-each and bag-fold — each expanding a multiplicity\nwith (= i count) — looped forever on a negative count, consing without\nbound. bag-increment! now drops the element when the result would be\nnon-positive, matching bag-decrement!; bag-product! clamps a negative n at\nzero; and the three loops test (>= i count) so no count value can hang\nthem, whatever route produced it.\n\nfirst-ec/any?-ec/every?-ec materialized the whole comprehension (#2179).\nfirst-ec expanded to list-ec and took car, and the two predicates ran the\nfull do-ec loop, so (first-ec #f (:integers i) i) hung despite SRFI 42\ngiving all three early-exit semantics. Each now allocates its own stop\nflag and sets it from the body; every %do-ec generator loop checks the\nflag before each iteration, so setting it unwinds the comprehension.\n\nRe-enables the disabled assertions for all three issues in\nsrfi146-differential.scm, srfi113-audit.scm and srfi42.scm (new early-exit\ntests with infinite generators and work measurement).\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Document first-ec's eager default and the cyclic-key depth-cap follow-up\n\nReview of #2233 flagged two non-blocking observations; this commit records\nboth where they belong.\n\nfirst-ec now evaluates its default argument eagerly — the new stop-flag\nshape seeds %result with default up front, where the old list-ec/car shape\nonly touched it when the comprehension was empty. That matches the SRFI 42\nreference implementation ((let ((result default) (stop #f)) ...) in\nec.scm), so it is more conformant, not a regression; the comment and the\nCHANGELOG entry now say so explicitly so it is not 'fixed' back later.\n\nAnd the #2044 side effect the test comment already noted — a\nmake-default-comparator hashmap keys in .custom mode and runs SRFI-128's\ndefault-hash, which recurses without a depth limit — is now spelled out\nwith its consequence: a cyclic key hits the stack cap (KP3008, uncatchable)\nwhere the old depth-capped native hash absorbed it. Tracked as kaappi#2235.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Stop comprehension generator steps early, and pin every changed call site\n\nCodeRabbit review of #2233 caught a real conformance gap in the early-exit\nmechanism (its other seven points were either word-level nits or requests\nthis repo's audit-file conventions already satisfy, or misread the native\nSRFI-69 comparator path the maintainer had verified).\n\nA stopped comprehension advanced every enclosing generator one extra time:\nthe reference's :until fusion folds the stop check into the loop's step\ntest (do-ec:do runs (loop ls ...) only when ne2? holds), and our own :do\nrule already guarded its step with (not s) — but the typed-generator rules\nstepped first and re-tested at the top of the next iteration. For :range\nthe extra step is pure arithmetic and invisible; for :port it read one\nextra datum, for :dispatched it called the generator procedure once more,\nand %parallel advanced every generator — observable with any stateful\ngenerator, and newly reachable since first-ec/any?-ec/every?-ec started\nstopping early (#2179). Every generator rule now guards its step with\n(unless s ...), matching the :do rule and the reference.\n\nRegression coverage: first-ec over :port reads exactly one datum,\nany?-ec over :port stops without over-reading, and first-ec over\n:dispatched / :parallel advances each generator exactly once.\n\nAlso from the review, two test-strengthening points adopted:\n- srfi113-audit.scm: bag-product with a negative n is now asserted to\n  yield an exactly empty bag (was a >=-on-size check), and the loop guard\n  is pinned with alist->bag negative stored counts — the one producer no\n  clamp covers, so only (>= i count) stands between it and a hang.\n- srfi146-differential.scm: every changed make-hash-table site\n  (hashmap-unfold, hashmap-map, hashmap-partition, alist->hashmap,\n  hashmap-intersection, hashmap-difference, hashmap-xor) now gets a\n  comparator-sensitive assertion using a comparator whose equality is =,\n  where 1 and 1.0 merge only if the comparator actually keys the table.\n\nCHANGELOG: correct \"nine call sites\" to \"ten calls across nine\nconstructors\" (hashmap-partition builds two tables), and note the\nguarded-step behavior in the #2179 entry.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n---------\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>",
          "timestamp": "2026-08-06T06:04:19Z",
          "tree_id": "2e8543fcf79e8ccc7eff846bf66ac3146ecd672a",
          "url": "https://github.com/kaappi/kaappi/commit/ebc0cb3299e49645097b11fc01c75c498a9a5a87"
        },
        "date": 1785998514849,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.18664,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.33057,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.436531,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.297057,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004447,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.036181,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.245829,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.042944,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.260805,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.056234,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.228869,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.222968,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.404673,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.840897,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.033237,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "e935fd49fd5193ccab48c9f23cba0dc7aed87c63",
          "message": "Replace /parallel-issues with /pr-groups (#2236)\n\n/parallel-issues optimised for file disjointness at issue granularity, so\nthat N concurrent sessions could work N issues without conflicts. Applied to\nthe 0.22.2 milestone it puts #1932 and #2027 in different sets — they touch\nthe same file — even though they are adjacent arms of one switch in\ndeepCopyValue. That buys parallelism at the price of two reviews of one diff\nand a conflict between the author's own branches.\n\n/pr-groups inverts the objective: group by cohesion so each set lands as a\nsingle PR, then run the same disjointness analysis one level up, across\ngroups. The parallelism verdict survives at the granularity where it is\nactually true, and the old paste-able launcher lines survive as wave output.\n\nThree steps carry the value, all of them learned grouping the 0.22.2 and\n0.22.3 milestones by hand:\n\nVerify before grouping. #2043 was scheduled into 0.22.3 and had in fact been\nfixed by #2174, which closed its four siblings (#1893, #1920, #1940, #1945)\nand missed it. Running the issue's own reproduction is what caught it, and\nscheduling fixed work discredits the rest of the plan.\n\nGround the file claims. An issue's diagnosis is a hypothesis and its line\nnumbers age; grep the named sites before pairing on them.\n\nCheck what a group blows in aggregate. Four issues grouped into\nprimitives_srfi18.zig would have pushed it past the 1500-line policy cap\nfrom 1472, so the group has to plan its split or become two PRs.\n\nOrdering keeps two land-first categories that were load-bearing in both\nmilestones: instrument before subject (a broken detector for the bug class\nthe others are in, #2127) and signal before work (anything making CI produce\nfalse reds, #1870/#1930/#2097).\n\nEvals are grounded in the two real milestones rather than invented, including\none asserting that a no-longer-reproducing issue is reported for closing and\nnot closed unilaterally.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-06T11:35:40+05:30",
          "tree_id": "de8748d4c70e9eab92e487c0aa9081822ac358bf",
          "url": "https://github.com/kaappi/kaappi/commit/e935fd49fd5193ccab48c9f23cba0dc7aed87c63"
        },
        "date": 1785999677996,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.247484,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.12465,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.451582,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.291704,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00454,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.037899,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.244831,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.04192,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.162115,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.003369,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.238346,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.251785,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.384251,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.775599,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.035216,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "c7b762025b870722df65d18568e91f2c321cf3c6",
          "message": "Classify a skill's evals.json as an inert docs-only path (#2238)\n\nThe format job's changed-path classifier lets a docs-only PR skip the\n~194 runner-minutes of build/test matrix. Its allowlist covers *.md,\ndocs/* and LICENSE, but not a skill's evals/evals.json, so a PR touching\nonly a SKILL.md and its sibling evals file runs the whole matrix for\ncontent no CI job reads.\n\nNothing in build.zig, tools/, .github/workflows or src/tests_*.zig\nreferences evals.json; the only hit in the tree is a prose comment. The\nglob is deliberately narrow (.claude/skills/*/evals/*.json) so\n.claude/settings.json, hook scripts and any other .json keep falling\nthrough to the full matrix, preserving the allowlist-never-denylist\nproperty.\n\nCloses #2237\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>",
          "timestamp": "2026-08-06T12:33:25+05:30",
          "tree_id": "db41386510be2146478f2a2a02fbede7477c8df4",
          "url": "https://github.com/kaappi/kaappi/commit/c7b762025b870722df65d18568e91f2c321cf3c6"
        },
        "date": 1786001781619,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.972554,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.873839,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.561373,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.838432,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004838,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.045067,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.294873,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.0544,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.334562,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.16902,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.519562,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.303304,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.713985,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.815574,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.047369,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "74b8d03b4d3c7cd66dc89d9c4ef99b6ea5039169",
          "message": "Bounds-check fixnum indices in u64 before narrowing to usize (#1912) (#2239)\n\n* Bounds-check fixnum indices in u64 before narrowing to usize (#1912)\n\nOn wasm32 (usize = u32) every vector-like accessor narrowed its index\nargument to usize INSIDE the bounds comparison, so a fixnum-range index\n(up to 2^47) wrapped to its low 32 bits before the check and could alias\nan in-range element: (vector-ref v 4294967297) silently read element 1,\nand vector-set! silently WROTE it. Native 64-bit builds were unaffected\nbecause usize is 64 bits there.\n\nFix by comparing in u64 before the narrowing, via two shared helpers\n(primitives.fixnumIndexInBounds / ...Inclusive) that carry the wasm32\nrationale in one place, applied at every affected site:\n\n  vector-ref/set!, vector-swap!, vector-copy!/reverse-copy!, substring,\n  string-ref/set!, string-copy!, bytevector-u8-ref/set!, bytevector-copy!,\n  parseOptionalRange (covers vector->list, string->vector, fill!,\n  reverse!, utf8->string, etc.), write-string, string-take/drop/-right,\n  string-replace, %record-ref/set! (+ /inherit and field-mutable?),\n  %numeric-vector-ref/set!, %record-split-args.\n\ntake and split-at walked their list in a narrowed usize counter; they now\nloop in i64 like drop already did, so a huge k walks to the end and raises\ninstead of silently returning a short list.\n\nNative error messages are unchanged on 64-bit: each site keeps its\noriginal error call and check order.\n\nLeft alone deliberately (separate class): large count/size arguments to\nallocation and read procedures (make-vector/string/bytevector,\nvector-unfold, string-pad, read-bytevector/string, iota), where the\nnative behavior is OOM or a huge overcommit rather than a clean catchable\nerror, so there is no native behavior to preserve.\n\ntests/scheme/smoke/large-index-bounds-1912.scm is extended from the\nvector-only probe to every fixed accessor, stays import-free so it runs\non wasm32, and is byte-identical across tiers (verified under wasmtime\n46.0.0); its KNOWN_DIFFS entry in run-wasm-differential.sh is deleted,\nas the harness's STALE check directs once the tiers agree. The\n% primitive half is covered by the internal-primitives audit, whose\n'(fails on wasm32)' annotations are now '(kaappi#1912)'.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Defer index narrowing until after bounds checks in write-string and %record-split-args; probe the right-side string accessors\n\nCodeRabbit review follow-up on #2239.\n\nwrite-string narrowed start_cp/end_cp to usize before the u64 bounds\nchecks, and %record-split-args narrowed suffix_len before its check. On\nthe shipped wasm32 build (.optimize = .ReleaseSmall) @intCast truncates\nsilently, and the raw-value checks still fire — correct there — but on a\nsafety-checked wasm32 build (usize = u32) the same @intCast would panic\nuncatchably, exactly the hazard makeNumericVectorFn's guard comment\nwarns about. Move both narrowings to after their checks pass; error\nmessages and check order are unchanged.\n\nThe probe test also gains string-take-right and string-drop-right, the\ntwo right-side accessors changed by the fix that the cases list omitted.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n---------\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>",
          "timestamp": "2026-08-06T08:15:42Z",
          "tree_id": "ca132050ec70e49e536a0330c1752a3cabc82118",
          "url": "https://github.com/kaappi/kaappi/commit/74b8d03b4d3c7cd66dc89d9c4ef99b6ea5039169"
        },
        "date": 1786005712286,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.07921,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.41116,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.425376,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.201529,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004498,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.036027,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.232559,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.040681,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.079896,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.920825,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.198917,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.231835,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.325188,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.737407,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.033435,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "cec32b6cab3e04c67041b85061fd35fae7b4aae3",
          "message": "Make the register file grow to its documented cap and report the limit as KP3008 (#2035) (#2240)\n\n* Make the register file grow to its documented cap and report the limit as KP3008 (#2035)\n\nA tail-position call replaces the current frame's code in place, but the\nframe's register window is unchanged — and until now nothing re-ensured\nroom for the callee's locals_count. The register file therefore silently\nstopped growing at the replaced frame's smaller window: 819 nested\ndynamic-wind extents (or a pure-Scheme stand-in of the same shape)\naborted an ordinary program at 4096 registers, 6% of the documented\n65536, and registerIndex reported the overrun as InvalidBytecode — a\ncatchable KP9001 \"internal error\" whose guard-swallowed error object\ncarried the bare message \"error\".\n\nEvery in-place replacement site now re-ensures the same bound callClosure\nguarantees when it builds a fresh frame — base + max(arg_count,\nlocals_count) + 1, so a variadic callee's rest slot is covered too:\ntail_call, tail_apply, tail_call_global, tail_call_cc's receiver, and\ntail eval. registerIndex returns StackOverflow (KP3008) for a register-\nfile overrun instead of InvalidBytecode, matching ensureRegisterCapacity\nand the frame stack, so the failure is uncatchable like every other VM\nlimit (#1886).\n\nTwo tests had been relying on the bug: \"re-entrant force is catchable\"\nin gc-root-growth.scm and the audit's \"direct re-entrant force\" case\npassed because (delay (force selfp)) died early at the 4096 cliff with a\ncatchable-but-degenerate error. That recursion is genuinely unbounded —\nthe SRFI-45 re-entrancy check only sees cycles whose thunk returns — so\nit now correctly runs to the register-file cap and is reported as an\nuncatchable stack overflow; the unbounded half moved to error-format.sh\nand the terminating R7RS 4.2.5 form is pinned instead. The 1000-deep\ndynamic-wind audit test is re-enabled, and error-format.sh pins that a\nregister-file exhaustion reports KP3008 and no guard swallows it.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Split the #2035 smoke coverage out of the #1191 regression file\n\ngc-root-growth.scm is a regression test for #1191 (native re-entrancy must\nnot panic with \"GC root stack overflow\") and now contains only that test.\nThe re-entrant promise and deep-dynamic-wind checks that pin the #2035\nregister-growth fix move to a dedicated smoke file named for the issue,\nkeeping each file scoped to the regression it guards.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n---------\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>",
          "timestamp": "2026-08-06T16:43:51+05:30",
          "tree_id": "c6036c47768dc6356f8b82f7ad8541e126c3f3ab",
          "url": "https://github.com/kaappi/kaappi/commit/cec32b6cab3e04c67041b85061fd35fae7b4aae3"
        },
        "date": 1786016914325,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.241049,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.346542,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.567431,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.953034,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004637,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046424,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.309902,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.056168,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.692858,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.223638,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.571575,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.281156,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.798022,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.626779,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043803,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "ff9fd4c046554762bc456de6e0117b3d912da2a6",
          "message": "Require a delimiter after prefixed numeric tokens (#2241)\n\nreadNumberPrefixed called the file-local readNumber/readIntegerWithRadix\ndirectly, bypassing the delimiter check the un-prefixed path gets from\nReader.readNumber. The one wrapper that did check, Reader.readIntegerWithRadix,\nhad no callers at all -- its guard had never executed since it was added in\n9e8cf95a. A sweep of 19 prefix spellings x 26 trailing characters found 382 of\n494 cells silently splitting one token into two datums: '#b1p4' read as (1 p4),\nchanging an enclosing list's length, and kaappi check reported such files clean.\n\nA single delimiter check after the body read in readNumberPrefixed closes all\n382 cells: tryReadInfNan already guards its own tail, the radix-10 complex\ngrammar consumes +...i as part of the token, and readHexFloatSuffix rejects\nmalformed float bodies. The dead Reader.readIntegerWithRadix wrapper is\ndeleted. '#x1p4z', '#e34zz', '#b101foo' and '#x1/2+3i' are now read errors,\nmatching string->number and the Chibi differential oracle; hex floats\n('#x1p4'), prefixed rationals ('#x1/2'), decimal-prefixed complex ('#d1+2i'),\nSRFI-169 separators ('#x1_f') and two-prefix combinations ('#e#x1p4') all\nstill read.\n\nEnables the 52 assertions in reader-delimiter-gaps.scm and the 7 in\nreader-exactness-gaps.scm that pinned the gap (the group-3 discriminating\ncontrol is updated: both bignum and fixnum rational tails are guarded now),\nand adds a Zig unit test covering both the rejected and must-keep-working\nspellings.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>",
          "timestamp": "2026-08-06T11:48:26Z",
          "tree_id": "2e19f06857f5a83d697ac08f0c6d9d64750df735",
          "url": "https://github.com/kaappi/kaappi/commit/ff9fd4c046554762bc456de6e0117b3d912da2a6"
        },
        "date": 1786018976292,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.329314,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.281431,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.576443,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.98353,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004829,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046893,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.313806,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057965,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.739201,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.224271,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.633366,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.284108,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.818796,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.649312,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043514,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "220e31a23b575d7e1dae4b66294c3a768a483995",
          "message": "Bound fmt's prefix-chain depth and name dangling #; errors (#2242)\n\nkaappi fmt's CST parser capped recursion for lists only: parseList\nchecked max_nesting, but a reader-prefix chain (' ` , ,@ #N=) or a #;\ndatum comment recursed through parsePrefixTarget without touching\nself.depth, so ~158000 prefixes overflowed the native stack and fmt\nexited 134 — and fmt --check, the documented CI gate, died the same\nway. Every prefix kind reached it, verified at 200000.\n\nThe prefix/datum-comment path now draws from the same max_nesting\nbudget as parseList, sharing one counter so mixed prefix+list nesting\nis rejected at the reader's own 1025 level; the printer's emitNode /\ncomputeMeasure recursion over the same chain is bounded by that cap.\nA dangling #; at end of input is reported as 'datum comment with no\ndatum' instead of being mislabelled 'quote/unquote with no datum'\n(ParseError gains DanglingDatumComment).\n\nRe-enables the disabled #2141 adversarial shell tests across all six\nprefix kinds and adds unit tests: every kind rejects cleanly past the\ncap, prefix and list nesting share one depth budget, and the dangling\n\n\n#; error is distinct from a dangling quote.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>",
          "timestamp": "2026-08-06T13:55:25Z",
          "tree_id": "c866c3ea6705ea1db16f43ffa8c59e9345cbdad6",
          "url": "https://github.com/kaappi/kaappi/commit/220e31a23b575d7e1dae4b66294c3a768a483995"
        },
        "date": 1786026503515,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.26675,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.379281,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.582946,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.97866,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004771,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.047292,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.314889,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057835,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.664012,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.22185,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.653961,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.279655,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.815122,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.632844,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043844,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "da126d91f1c62ced335ee5158011f5582a55c0c7",
          "message": "Isolate each LSP document's macros so define-syntax cannot leak across documents (#2244)\n\nrunDiagnostics compiled every open document against the server's single\nshared vm.macros table, so a define-syntax in one file changed how every\nother file was diagnosed: byte-identical text flipped from clean to KP2001\ndepending on what else the editor had open, and the leak survived didClose\nof the defining document (only a server restart cleared it). A plain\ndefine never leaked, because globals are never written by the diagnostics\npath — the macro table was the sole carrier.\n\nEach runDiagnostics run now resets the shared table to a baseline snapshot\ntaken at startup, before any document is opened. A document's own macros\nstill accumulate top-to-bottom across its forms (the same visibility kaappi\ncheck gives a standalone file — macro plus misuse in one file is still\nKP2001), but nothing written during a run survives to another document, so\nevery file gets the verdict it would get alone. Baseline values are rooted\nonce via extra_roots, since the VM's GC marking covers vm.macros only.\n\nEnables the two #1979 FAIL-marked assertions in tests/scheme/lsp/lsp.sh,\nretunes the didClose control for the now-clean third frame, and adds two\nregression guards: own-document macro misuse stays KP2001 with another\ndocument open, and a document defining its own macro still cannot see\nanother document's.\n\nSuite: 156 LSP assertions pass, incl. under -Dgc-stress=true; unit tests\npass.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>",
          "timestamp": "2026-08-06T20:20:09+05:30",
          "tree_id": "9b302134e751ec2163688b5157622f5c1e7e197f",
          "url": "https://github.com/kaappi/kaappi/commit/da126d91f1c62ced335ee5158011f5582a55c0c7"
        },
        "date": 1786029747538,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.977422,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.516255,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.563647,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.822045,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004852,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.045118,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.298372,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.054355,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.339171,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.16844,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.519809,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.302098,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.704119,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.750819,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044829,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "2d593e3c736ccc1235db3f27a4ab6bad2d439d10",
          "message": "Read radix-prefixed complex numbers per R7RS <complex R> (#2243) (#2245)\n\n* Read radix-prefixed complex numbers per R7RS <complex R> (#2243)\n\nThe #1929 delimiter fix turned every non-decimal radix complex spelling\ninto a read error, but #x1/2+3i, #x1+2i, #x1+i and #b1+1i are valid\nR7RS 7.1.1: <complex R> -> <real R> + <ureal R> i and its -/+i twins\nhold in every radix, and guile, Chez 10.4.1 and the project's own\nradix-10 path all read them. readIntegerWithRadix now consumes a complex\ntail with radix-valid digits and optional rational parts, producing an\nexact complex token exactly like the decimal path does for 1/2+3i, so\nread and string->number agree (6.2.7). The radix-10 complex branch of\nparseNumberText was the only parser gate on radix 10; it now parses the\nsplit forms in every radix, which also closes the documented TBD where\nstring->number returned #f for the valid R7RS complex 1/2+3i (Chibi and\nguile both accept it).\n\nThe guard rails stay: #b1+2i (2 is not a binary digit), #o1+8i, #x1+2\n(no i), #x1+2iz (glued tail) and the signless #x3i/#xi all still error\nin both parsers, and bignum components stay a loud error (kaappi#2182\nstance: an exact bignum part has no honest f64 value). The bare-sign\npure imaginary #x+i is grammar and reads as 0+1i, matching Chez.\n\nEnables the group-7 TBD assertions in reader-delimiter-gaps.scm, flips\nthe #x1/2+3i pins to accept-whole, and adds a new group-8 matrix\ncovering the accepted and rejected spellings plus string->number\nagreement. Extends the Zig unit test with the radix complex cells.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Address #2243 review: full <complex R> production, exactness honesty, radix-19 i-digit\n\nReview of the radix-complex change (kaappi#2243) found five valid issues;\nthis closes them all.\n\n- The signed pure imaginary with an explicit magnitude (+ <ureal R> i /\n  - <ureal R> i, e.g. #x+3i, #x+3/4i) is a genuine R7RS production that\n  readIntegerWithRadix and readNumber both missed -- #x+i read but the\n  identical-valued #x+1i errored, and #x0+3i read but #x+3i did not.\n  Both readers and string->number now accept it in every radix (Chez and\n  guile agree); the signless #x3i/#x3/4i spellings stay rejected.\n- string->number with an explicit radix argument (19-36) treats 'i' as an\n  ordinary digit (value 18), so the trailing-'i' complex detection is\n  gated on radix <= 18 in both the rational-branch guard and the complex\n  branch -- (string->number \"1/2i\" 19) is the rational 1/56 again.\n- The imaginary marker is case-insensitive in both parsers now: the\n  reader always accepted 1+2I, string->number only 'i' (a pre-existing\n  radix-10 divergence the new code extended to every radix).\n- string->number derives complex component exactness from the text\n  (integer/rational parts exact, decimals/exponents inexact) so its\n  tokens match the reader's exact-flagged ones; #e/#i still override.\n- Exact-flagged components can no longer silently carry a rounded value:\n  integer parts in (2^53, 2^63] (and non-representable bignums) and\n  rational parts beyond the exact-complex printer's recovery granularity\n  (floatToRational searches denominators up to 1e6) are rejected loudly\n  in both parsers, the kaappi#2182 stance, applied to the radix-10 paths\n  too. Shared radix-<ureal> parsing and the f64 round-trip tests now\n  live in bignum.zig so the two parsers cannot drift.\n\nPins: group 8 of reader-delimiter-gaps.scm grows the signed-magnitude,\ncase, and round-trip cells plus a new group 9 for the radix-19 digit\nbehavior; the Zig unit test covers #x+3i/#x+3/4i, #x1+2I, the 2^53 band,\nand the #e1e19+1i round-trip.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Fix critical f64ExactI64 panic and close the remaining review divergences\n\nThe second review round found a process abort reachable from a one-line\nprogram: f64ExactI64 did @intFromFloat(@floatFromInt(n)) and the top 512\ni64 values (2^63-512 .. 2^63-1) round UP to 2^63, which overflows the i64\ndestination -- a ReleaseSafe panic in (string->number\n\"9223372036854775807+2i\") and (read \"#x7fffffffffffffff+2i\"). Those\nvalues never round-trip, so they are rejected before the conversion now;\n-i64 range and 2^63 itself (a power of two) still pass.\n\nThe same review round also found four smaller read/string->number\ndivergences, all closed:\n\n- The signless pure-imaginary integer path in string->number lacked the\n  bignum fallback, so (string->number \"10000000000000000000i\") returned\n  #f while the reader read 0+1e19i exactly (45 significant bits). It now\n  falls back to parseBignumString + bignumExactInF64 like every other\n  integer component path.\n- Special-float imaginary parts: 3.0+inf.0i / +inf.0i read in the reader\n  but string->number's components used Zig parseFloat, which rejects\n  +inf.0. parseComplexComponent now names the four special spellings\n  explicitly, matching the reader's grammar.\n- The #1929 CHANGELOG entry still listed #x1/2+3i as a read error while\n  the new #2243 entry reinstated it; the list now names #x1zzz instead and\n  points at #2243.\n- The remaining complex?-wrapped string->number assertions were\n  strengthened to real-part/imag-part equality checks, and new cells pin\n  the inf/nan and bignum-magnitude agreement.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n---------\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>",
          "timestamp": "2026-08-07T00:29:45Z",
          "tree_id": "87f11dd3cb81bd0f850f9f161f0def341668c1e0",
          "url": "https://github.com/kaappi/kaappi/commit/2d593e3c736ccc1235db3f27a4ab6bad2d439d10"
        },
        "date": 1786064553141,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 2.842505,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 5.668575,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.389466,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.013899,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00434,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.033748,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.21135,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.038783,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.041654,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.82342,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.131106,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.224874,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.225699,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.823334,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.033924,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "ef0a9c9d5edb14ad51ceba6965986e7e320fa0a5",
          "message": "Stop file-backed library loads from abandoning the enclosing top-level form (#2012) (#2246)\n\nThe first top-level form whose evaluation loads a file-backed .sld\nthrough (environment ...) was silently abandoned partway through: side\neffects before the load persisted, everything after it (the form's own\ndefine or display) never happened, with no error and exit 0. The second,\nbyte-identical form worked because the library was loaded by then, so a\nprogram either behaved correctly or silently lost a whole top-level form\ndepending on whether some earlier form had touched the same library.\n\nenvironmentFn (primitives_r7rs.zig) reaches importSetChecked, and for a\nfile-backed library that path compiles + executes the library body by\nre-entering vm.execute (tryLoadLibraryFromFile -> loadLibrarySource).\nvm.execute begins with resetExecutionState, which zeroes frame_count,\nhandler_count and wind_count -- destroying the enclosing top-level\nform's frame. The nested call then returns success, so the outer\nrunUntil loop sees frame_count == 0 and exits cleanly. Registry-backed\nlibraries ((srfi 1), (scheme base)) never take that path, which is why\nthe issue's control table was so clean. Top-level (import ...) was\nspared because the binding merge happens in native code after the load\nreturns; only user forms with work after the load showed it.\n\nFix: route every nested-entry top-level thunk through\nrunTopLevelFunction (vm_eval.zig, the re-entrant-safe path eval and\ntop-level begin/cond-expand splicing already use since #1500), which at\nframe_count == 0 is identical to vm.execute but while an outer\nexecution is suspended pushes a frame above the live ones via\ncallWithArgs instead of resetting them away. The affected sites are the\nlibrary body form executor (loadLibrarySource), top-level include\n(evalIncludedForm), library body definitions (compileLibExpr),\ndefine-values (handleDefineValues), and the five define-record-type\nexpansion sites in vm_records.zig. A new VM method runTopLevelFunction\nexposes it to those modules.\n\nRegression test: tests/scheme/compliance/environment-file-sld-2012.scm.\nOn the buggy build its first-load probes fail loudly (undefined variable\n-- the defining form never bound) with exit 1; with the fix all four\npass. The native tier is unaffected (it runs top-level forms natively,\nso there is no enclosing VM frame to lose), verified by compiling the\nissue's repro with kaappi compile on both builds.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>",
          "timestamp": "2026-08-07T08:05:33+05:30",
          "tree_id": "b9e25b0eafa872e2eff0b19befc497028b74755f",
          "url": "https://github.com/kaappi/kaappi/commit/ef0a9c9d5edb14ad51ceba6965986e7e320fa0a5"
        },
        "date": 1786072013814,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.348717,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.211829,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.583827,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.008312,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.0047,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.04717,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.322208,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.058007,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.747152,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.258154,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.583934,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.281379,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.825356,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.605302,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043093,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "31532732e36c75d52d28d017cb289333a940737b",
          "message": "Clamp the completion subcommand-scan slice against a negative length (#2248)\n\nThe generated bash and zsh completion functions scan the words typed so\nfar — offset 1, up to the word before the cursor — to decide which\nsubcommand's flags to offer. The length is `cursor-index - 1`, which goes\nnegative when the cursor is still on the command word itself.\n\nbash's `${COMP_WORDS[@]:1:COMP_CWORD-1}` then errors outright (\"substring\nexpression < 0\"). zsh is worse: `${words[@]:1:$((CURRENT-2))}` feeds a\nnegative length, which zsh reads as \"count from the end\", so the loop scans\nnearly the whole line and misdetects a later word as the subcommand —\ncompleting that subcommand's arguments instead of the top level. Clamp both\nlengths to 0 in that case.\n\nThe completions suite gains a structural check that both scripts emit the\nclamp (runs on every CI leg, no shell needed) and a functional zsh drive\nthat sources the real `_kaappi` at CURRENT=1 and asserts it offers the top\nlevel rather than a subcommand's arguments. Reverting either guard fails\nthe new checks.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-08-07T12:32:45Z",
          "tree_id": "f38896a9636ca852524ad46bc119b02777726689",
          "url": "https://github.com/kaappi/kaappi/commit/31532732e36c75d52d28d017cb289333a940737b"
        },
        "date": 1786108068060,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.023063,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.055392,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.562703,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.913031,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004925,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.044602,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.294827,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.053869,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.311318,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.165629,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.513986,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.302772,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.716036,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.781843,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044309,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "da4072cb2d96d471ff4950c85d7756ef3ead1955",
          "message": "Fix cross-thread heap safety: reject cross-heap stores (#1924) and mark live children's roots (#1933) (#2247)\n\n* Fix cross-thread heap safety: reject cross-heap stores (#1924) and mark live children's roots (#1933)\n\nTwo halves of the same gap: each SRFI-18 OS thread has its own GC heap,\ntop-level bindings are shared by pointer, and nothing coordinates the\ntwo collectors on the mutation path. Both were deterministic\nuse-after-frees — #1924 on every run, #1933 wrong values or a hard\n\"GC: marking freed object\" panic under -Dgc-stress.\n\n#1924 — a child storing one of its own heap's objects into a shared\nparent-heap container (a record field, vector slot, pair, hash-table\nentry, promise's memoised value, or the globals map) left a pointer the\nparent's collector skips as foreign and the child's collector cannot\nsee a reference to; the value was freed by the child's GC or at its\njoin while the container still held it. The store is now rejected\nBEFORE it happens (memory.crossHeapStoreViolation, checked at every\ngeneral mutation site: set-car!/set-cdr!, vector-set!/vector-fill!,\n%record-set!/inherit, hash-table-set!, %promise-complete!/-merge!, the\nset_upvalue/set_box_local bytecode ops, and set_global/define_global),\nunless the value belongs to the container's own heap. The mutex-lock!\nowner pair is the one sanctioned exception and is exempt.\n\n#1933 — a parent-heap object referenced only from a live child's\nregisters was unreachable to both markers, so the parent's collection\nfreed it under the running child. The root's collector now stops every\nlive child at the dispatch-loop safepoint (or finds it already parked /\nin an FFI call) and marks its roots with the root's gc\n(markLiveChildRoots, wired as gc.child_marker; markVMRoots extracted\ninto the shared markVmRoots). Children report a quiescence state\n(CollectionState) from the safepoint, the park and callFfi; children\nspawned mid-collection wait on collection_in_progress before their\nfirst shared-globals read; dead (retired) children are skipped via a\nregistry thread_exited flag. The symbol-mutex section of markRoots no\nlonger wraps the child-marking, which would have deadlocked a child\nblocked in allocSymbol while deep-copying its thunk.\n\nRegression tests: srfi18-cross-heap-mutation-1924.scm (the full\nrejection matrix plus the immediate/Direction-B/mutex controls) and\nsrfi18-child-registers-1933.scm (the issue's hash-table + channel\nhandshake shape, with a guardian control proving the churn collects).\nsrfi18-sharing-model.scm pins the new mutation-refused rows;\nthread-value-sharing.md documents both fixes and the residuals.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Address review + fix gc-stress hang: cover all mutation sites, pin quiescent states, speed up stop-the-world\n\nSecond round on the #1924/#1933 PR. Three CI gc-stress timeouts were\ntraced to the stop-the-world dance: a child joining its own child blocks\nin a raw pthread join that never reached a safepoint, so the parent's\ncollector waited on it forever while the grandchild spun on\ncollection_in_progress (a livelock — channel-promoted-owner-1934 went\nfrom 0.15s to >40min); and the 1ms poll in the wait made every parent\ncollection with a live child cost ~1ms (pathological under -Dgc-stress,\nwhere collections run per allocation). The third timeout\n(srfi146-differential) is pre-existing — 3m on base, no threads.\n\nFixes:\n\n- reapOsThread's thread.join() reports the in-native quiescent state\n  (function-scope defer — a block-scoped one fired before the join, the\n  same trap as the park/FFI sites), so a joining child is marked, not\n  waited on.\n- The parent's wait spin-yields instead of sleeping 1ms; a running\n  child reaches its next safepoint within 1024 instructions.\n- setCollectionRunning is now guarded: resuming from a quiescent state\n  re-checks collection_stop and spins (publishing .stopped) until the\n  parent clears it, closing the TOCTOU where a .parked/.in_native child\n  resumed bytecode between the parent's observation and its mark.\n  callWithArgs' FFI-callback guard and the threadEntryFn startup\n  handshake route through it.\n- crossHeapStoreViolation now rejects ALL foreign-container stores (not\n  just foreign-heap values): a parent-owned value into a parent-owned\n  container needs the OWNER's generational write barrier for a young\n  value, and the owner's remembered set cannot be touched cross-thread.\n  Interned symbols stay allowed (permanent, promoted, never dangle).\n  The store check is also added at the six previously-missed general\n  mutation sites: list-set!, vector-copy!, vector-reverse-copy!,\n  hash-table-update!, hash-table-update!/default, hash-table-merge!.\n- Exited children's collection_stop is always released (separate armed\n  list); child_marker is stored/loaded atomically.\n- Tests: the rejection matrix now covers the six new sites, set-cdr!,\n  child-allocated hash keys, define via eval, and the\n  parent-value-into-parent-container rejection; the audit characterisation\n  tests that asserted the old store-anything behaviour are updated.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Narrow the parked window, cover vector-unfold!/map! and define-env writes\n\nThird round on the #1924/#1933 PR, from the second CodeRabbit pass.\n\n- parkOnReactor reports .parked across the blocking poll ONLY: the\n  post-poll code (sweepSharedWaiters, wakeReadyFiber, markRunnable)\n  mutates scheduler state that markVmRoots traverses, so reporting\n  quiescence there would race the parent's mark. The resume goes through\n  the guarded setCollectionRunning as before.\n- vector-map!/vector-unfold!/vector-unfold-right! write their step\n  procedure results into a caller-supplied destination; a shared\n  parent-heap destination now gets the same cross-heap store rejection\n  as vector-copy! (per result, so all-immediate runs stay legal).\n- define_global now applies the child-store rejection before the env\n  branch, matching set_global - covering a child eval-define into a\n  shared library or eval environment, not just the globals map.\n- The child-registers-1933 test churn is reduced 4x (100k iterations,\n  still verified to turn the pre-fix read into garbage) to keep the\n  gc-stress run at ~40s instead of ~160s.\n- docs/dev/thread-value-sharing.md globals row reworded to match the\n  strengthened predicate (any store into a not-owned container is\n  rejected, interned symbols excepted).\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Validate the promise-merge inner back-pointer store too\n\nThe %promise-merge! outer store (outer.value = inner.value) was checked,\nbut the matching inner store (inner.value = outer) was not: the comment\nclaimed the predicate's container-owner rule covered it, yet the check was\nnever actually called for that direction. Both directions now go through\ncrossHeapStoreViolation before any store or barrier, so the code matches\nits own comment. (In practice both promises come from one force chain and\nshare a heap; the added check is defensive and consistent.)\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n---------\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>",
          "timestamp": "2026-08-07T14:15:28Z",
          "tree_id": "92c0e6be16c055c9282805341ed216a33bec2df4",
          "url": "https://github.com/kaappi/kaappi/commit/da4072cb2d96d471ff4950c85d7756ef3ead1955"
        },
        "date": 1786114164589,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.99191,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.525925,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.564421,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.885064,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00496,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.045257,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.300292,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.054104,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.403467,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.182557,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.535297,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.298248,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.708702,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.75971,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044294,
            "unit": "seconds"
          }
        ]
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
          "id": "c6082f8730c93ead7efd3f570b2c11ad310c47cd",
          "message": "Release v0.22.3\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>",
          "timestamp": "2026-08-07T19:54:33+05:30",
          "tree_id": "ead42f58d21b287eaf026f8500443984e775065d",
          "url": "https://github.com/kaappi/kaappi/commit/c6082f8730c93ead7efd3f570b2c11ad310c47cd"
        },
        "date": 1786115160675,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.982831,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.215154,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.578042,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.880784,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004928,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.045269,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.300209,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.05424,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.55728,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.182648,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.534682,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.307483,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.712279,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.796729,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044809,
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
          "id": "f49f694886113974efe03a4fe2e37fbda1dad378",
          "message": "Bump the github-actions group with 3 updates (#2250)\n\nBumps the github-actions group with 3 updates: [DavidAnson/markdownlint-cli2-action](https://github.com/davidanson/markdownlint-cli2-action), [vmactions/freebsd-vm](https://github.com/vmactions/freebsd-vm) and [vmactions/netbsd-vm](https://github.com/vmactions/netbsd-vm).\n\n\nUpdates `DavidAnson/markdownlint-cli2-action` from 24.1.0 to 24.2.0\n- [Release notes](https://github.com/davidanson/markdownlint-cli2-action/releases)\n- [Commits](https://github.com/davidanson/markdownlint-cli2-action/compare/6bf21b07787794f89a243495939cd651942aeabe...21c1be1b93ad9ed58fa840aacc3f279cde2a72ff)\n\nUpdates `vmactions/freebsd-vm` from 1.5.2 to 1.5.3\n- [Release notes](https://github.com/vmactions/freebsd-vm/releases)\n- [Commits](https://github.com/vmactions/freebsd-vm/compare/77ed28d336d03fe19a3f4f7266c1d2c4714dd79d...83b151f58c6047089f4c80eb5ba2039d158ce093)\n\nUpdates `vmactions/netbsd-vm` from 1.4.4 to 1.4.6\n- [Release notes](https://github.com/vmactions/netbsd-vm/releases)\n- [Commits](https://github.com/vmactions/netbsd-vm/compare/bf34bcd909bb50856f934a67d09a8fbe2b966a1b...00081e82b14bc40114eb97f32b4455306828516b)\n\n---\nupdated-dependencies:\n- dependency-name: DavidAnson/markdownlint-cli2-action\n  dependency-version: 24.2.0\n  dependency-type: direct:production\n  update-type: version-update:semver-minor\n  dependency-group: github-actions\n- dependency-name: vmactions/freebsd-vm\n  dependency-version: 1.5.3\n  dependency-type: direct:production\n  update-type: version-update:semver-patch\n  dependency-group: github-actions\n- dependency-name: vmactions/netbsd-vm\n  dependency-version: 1.4.6\n  dependency-type: direct:production\n  update-type: version-update:semver-patch\n  dependency-group: github-actions\n...\n\nSigned-off-by: dependabot[bot] <support@github.com>\nCo-authored-by: dependabot[bot] <49699333+dependabot[bot]@users.noreply.github.com>",
          "timestamp": "2026-08-08T02:10:17+05:30",
          "tree_id": "cbcde3db941a584c142c261a79a9a4d06be003f1",
          "url": "https://github.com/kaappi/kaappi/commit/f49f694886113974efe03a4fe2e37fbda1dad378"
        },
        "date": 1786137227306,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.383656,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.506849,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.572699,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.050675,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004677,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046824,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.315063,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.056181,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.757039,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.248747,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.598175,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.286319,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.804306,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.665309,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043934,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "6ee91e23745eb447b52f2c09ec228ea3768070ec",
          "message": "Fix macro hygiene: use-site bindings can no longer capture template free references (#2003, #2074) (#2251)\n\n* Fix macro hygiene: use-site bindings can no longer capture template references (#2003, #2074)\n\nR7RS 4.3.2 requires a macro template's free reference to refer to the\nbinding visible where the transformer was specified. Two capture defects\nviolated this, both fired by an ordinary local binding at the use site:\n\n#2003 — a template free reference to a global *procedure* compiled as a\nby-name reference to the bare name, so `(let ((car (lambda (x)\n'HIJACKED))) (usecar (list 1 2)))` called the local instead of the global\ncar. Such references are now hygiene-renamed like any other\ntemplate-introduced identifier, and the run-time global lookup's\nhygienic-prefix fallback resolves the rename to the base global by name —\nimmune to use-site locals while still observing a same-environment\ntop-level redefinition (the semantics chibi and guile implement). Two\ncompanion changes keep the renamed references correct: isContinuationBarrier\nand the four tail-position fast paths (apply / call-with-values / call/cc /\neval) recognize a renamed spelling, which SRFI 248's guard re-raise needs\nfor correct multiple-value passing.\n\nThe one deliberate exception is a template *lambda formal* colliding with a\nglobal procedure, which keeps its bare spelling via an identity rename:\nSRFI 190's coroutine body binds to the template's `yield` formal by name,\nthe anaphoric-binding pattern that pre-#2003 behaviour made possible. This\nis deliberately not extended to let variables — #681 pins that a template\nlet variable named after a built-in must not capture use-site text.\n\n#2074 — template operator keywords (begin, lambda, letrec, cond, and, or,\nset!, do, ...) were inserted bare, so `(let ((begin 5)) (m 7))` compiled the\ntemplate's `(begin e)` as the call `(5 7)`. The operator keywords among the\nwell-known forms are now hygiene-renamed too; the compiler recognizes them\nthrough effective-name stripping. The small set that must keep its spelling\nfor structural matching — the definition/library forms, syntax-rules, the\naux syntax else, the pattern markers .../_ and the quote/quasiquote *value*\nsymbols — stays bare, while quote/quasiquote *form* heads are renamed (with\nstrip-aware quasiquote depth handling and hygiene-stripped rebuilt heads in\nthe compiler). `=>` in cond/case clauses is renamed as well, and the clause\ncompilers now recognize it through the hygiene strip, so a template's arrow\nis immune to a use-site local `=>`. cond-expand feature combinators\n(and/or/not/library) are likewise recognized through the strip.\n\nSRFI 190's tests that pinned the old anaphoric capture through *another*\nmacro's template are updated to the correct behaviour (a free `yield` in a\nhelper macro's template resolves at its own definition site, matching chibi\nand the SRFI reference implementation's syntax-parameter design). The\npreviously disabled audit (e) hygiene tests and the srfi-notest-batch\n#2003/#2074 tests are re-enabled, and the expand snapshot tests now compare\nthrough a gensym-id normalizer (the exact __hyg_N_ id is process-global).\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Address review: align FORMAL_FLAG comments with lambda-only scope (#2252); drop dead __nlet_ branch\n\nCodeRabbit and baijum both flagged that three FORMAL_FLAG comments\nclaimed the bare-spelling anaphoric exception covers \"lambda/case-lambda\"\nformals, but only lambda is handled. Nothing depends on case-lambda\nanaphora (SRFI 190 uses lambda), and renaming case-lambda formals\nhygienically like let-variables is the more consistent behaviour, so the\ncomments now state the lambda-only scope and cite #2252; a hygiene test\npins that a case-lambda formal does not capture a spliced body while a\nlambda formal keeps its anaphoric spelling.\n\nAlso drops the \"__nlet_\" alternative in isContinuationBarrier:\nstripHygienicPrefix does not strip __nlet_, so the branch was dead\n(named-let loop names are always locals and are resolved by the call\npath before the barrier check is reached).\nFix macro hygiene: use-site bindings can no longer capture template references (#2003, #2074)\n\nR7RS 4.3.2 requires a macro template's free reference to refer to the\nbinding visible where the transformer was specified. Two capture defects\nviolated this, both fired by an ordinary local binding at the use site:\n\n#2003 — a template free reference to a global *procedure* compiled as a\nby-name reference to the bare name, so `(let ((car (lambda (x)\n'HIJACKED))) (usecar (list 1 2)))` called the local instead of the global\ncar. Such references are now hygiene-renamed like any other\ntemplate-introduced identifier, and the run-time global lookup's\nhygienic-prefix fallback resolves the rename to the base global by name —\nimmune to use-site locals while still observing a same-environment\ntop-level redefinition (the semantics chibi and guile implement). Two\ncompanion changes keep the renamed references correct: isContinuationBarrier\nand the four tail-position fast paths (apply / call-with-values / call/cc /\neval) recognize a renamed spelling, which SRFI 248's guard re-raise needs\nfor correct multiple-value passing.\n\nThe one deliberate exception is a template *lambda formal* colliding with a\nglobal procedure, which keeps its bare spelling via an identity rename:\nSRFI 190's coroutine body binds to the template's `yield` formal by name,\nthe anaphoric-binding pattern that pre-#2003 behaviour made possible. This\nis deliberately not extended to let variables — #681 pins that a template\nlet variable named after a built-in must not capture use-site text.\n\n#2074 — template operator keywords (begin, lambda, letrec, cond, and, or,\nset!, do, ...) were inserted bare, so `(let ((begin 5)) (m 7))` compiled the\ntemplate's `(begin e)` as the call `(5 7)`. The operator keywords among the\nwell-known forms are now hygiene-renamed too; the compiler recognizes them\nthrough effective-name stripping. The small set that must keep its spelling\nfor structural matching — the definition/library forms, syntax-rules, the\naux syntax else, the pattern markers .../_ and the quote/quasiquote *value*\nsymbols — stays bare, while quote/quasiquote *form* heads are renamed (with\nstrip-aware quasiquote depth handling and hygiene-stripped rebuilt heads in\nthe compiler). `=>` in cond/case clauses is renamed as well, and the clause\ncompilers now recognize it through the hygiene strip, so a template's arrow\nis immune to a use-site local `=>`. cond-expand feature combinators\n(and/or/not/library) are likewise recognized through the strip.\n\nSRFI 190's tests that pinned the old anaphoric capture through *another*\nmacro's template are updated to the correct behaviour (a free `yield` in a\nhelper macro's template resolves at its own definition site, matching chibi\nand the SRFI reference implementation's syntax-parameter design). The\npreviously disabled audit (e) hygiene tests and the srfi-notest-batch\n#2003/#2074 tests are re-enabled, and the expand snapshot tests now compare\nthrough a gensym-id normalizer (the exact __hyg_N_ id is process-global).\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n---------\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>",
          "timestamp": "2026-08-08T07:04:32+05:30",
          "tree_id": "b9a78d2f6879b25918b908f5c3e8fc45188fd968",
          "url": "https://github.com/kaappi/kaappi/commit/6ee91e23745eb447b52f2c09ec228ea3768070ec"
        },
        "date": 1786155200906,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.008313,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.727748,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.568166,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.864778,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004942,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.045494,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.303449,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.054913,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.379161,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.177247,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.537767,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.299358,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.733734,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.755697,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.047398,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "a072706e19a299eee68bcd13afdb47c34077ab0c",
          "message": "Expand imported macros when computing LSP diagnostics (#2253)\n\n* Expand imported macros when computing LSP diagnostics\n\nThe language server compiled every top-level form in isolation without\nfirst running the file's `import` / `define-library` / `include` /\n`define-record-type` declarations. So an imported macro was never in\nscope when a later form was diagnosed. For SRFI 42's comprehension\nmacros (`list-ec`, `sum-ec`, `vector-ec`, ...) that turned valid code\ninto a phantom error: their `(if test)` is the comprehension's filter\nqualifier, but with the macro unexpanded the compiler saw a bare\none-armed R7RS `if` and reported KP2001 — a red squiggle under code that\nruns fine and that `kaappi check` (which has always run imports) accepts.\n\n`runDiagnostics` now classifies each top-level form through the same\n`TopLevelHead` machinery `kaappi check` and the runtime share, so the\nthree cannot drift: top-level `begin` and the selected `cond-expand`\nclause splice and are recursed into, the environment-establishing heads\nare run for their effect so later forms see the bindings and macros they\nintroduce, and everything else is compiled but not executed, exactly as\nbefore. The per-document macro reset (#1979), the first-error-only\npublish (#1980), and the whole-line range sentinel are all preserved.\n\nDiagnosing an `(import (srfi 42))` at all also requires the server to\nfind the file-based `.sld`, which it never set up: `vm.lib_paths` is now\nseeded with `~/.kaappi/lib` and the exe-relative `../lib` fallback via\nthe same `kaappi_paths` helpers `main.zig` uses.\n\nAdds LSP-suite coverage: the reported list-ec and Pythagorean-triples\nguards are diagnosed clean (cross-checked against `kaappi check`), while\na genuine top-level one-armed `if` still reports KP2001.\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* LSP diagnostics: resolve sibling libraries, sandbox side effects, isolate imported globals\n\nAddresses review of the imported-macro diagnostics change:\n\n- Sibling `.sld` resolution now matches `kaappi check`. `resolveLibraryPath`\n  never consults `current_lib_dir` (only `include` does), so setting it was not\n  enough to find a library beside the document. The document's own directory is\n  now prepended to `vm.lib_paths` for the run — the same thing `main.zig` does\n  for the file argument — so `(import (mylib))` of a neighbouring `.sld` is\n  resolved instead of reported as a phantom KP2001. The overclaiming comment is\n  corrected: `current_lib_dir` is for `include`, `lib_paths` for library imports.\n\n- Executed env-setup code can no longer corrupt the wire. Running an `import`\n  loads and *executes* the library's `begin` body (as `kaappi check` does); a\n  top-level `(display ...)` there would write straight to fd 1 between framed\n  responses. The VM's current-output-port is redirected to a discarding\n  in-memory port for the duration of each run and restored after; its buffer is\n  truncated per run so it never grows across the server's lifetime.\n\n- Imported value bindings no longer leak across documents. `importBinding`\n  writes value exports into `vm.globals`, which — unlike `vm.macros` — was never\n  reset per document, so a name imported while diagnosing one file stayed\n  resolvable (hover/completion) in another. Every global not present at startup\n  is now retracted at the start of each run, under the same write lock\n  `importBinding` takes and with a `global_version` bump — the globals analogue\n  of the existing per-document macro reset (#1979).\n\nNew LSP-suite coverage: a sibling `.sld` import diagnoses clean (cross-checked\nagainst `kaappi check`, and load-bearing for the lib_paths setup since the\nlibrary is not a built-in prefix); a library whose body prints is diagnosed\nclean with its output kept off the wire (control confirms `check` does execute\nthat body); and an imported binding is not hoverable in a document that does not\nimport it, while it stays resolvable in the one that does. 167 LSP checks pass.\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* LSP diagnostics: decode file URIs, lock globals prune, strengthen tests\n\nSecond review pass (CodeRabbit + local review):\n\n- File URIs are now converted to native paths before use. A new\n  `fileUriToPath` percent-decodes `%XX` (so a document under a path with spaces\n  resolves its sibling `.sld`/includes), accepts an empty or `localhost`\n  authority, and strips the leading slash before a Windows drive letter\n  (`file:///C:/x` -> `C:/x`). Both `current_lib_dir` and the doc-directory\n  `lib_paths` entry use the decoded path.\n\n- `pruneImportedGlobals` now holds `vm.globals_lock` across the whole\n  operation — iteration, key collection, and removal — instead of only around\n  the removals, so a concurrent child-thread reader can never observe a\n  half-pruned map. Nothing in the loop re-acquires the lock, so it cannot\n  deadlock.\n\n- Test hardening: the globals-isolation control now asserts the positive hover\n  payload (`\"result\":{\"contents\"`) instead of merely lacking a null result, so\n  an error or missing response can't pass it vacuously. A new sibling-`.sld`\n  isolation control opens a document in a *different* directory importing a\n  *fresh* library that lives only under the first document's directory, and\n  asserts it is unresolved (KP2001, cross-checked against `kaappi check`) —\n  proving the per-run `lib_paths` restore holds. A fresh library is required\n  because an already-loaded one would resolve from `vm.libraries` regardless.\n\nDeliberately not changed:\n- Enabling `sandbox_mode` during env-setup (a suggested hardening) would reject\n  every file-backed library load — `tryLoadLibraryFromFile` only allows embedded\n  libraries under sandbox — so `(import (srfi 42))` and every ecosystem import\n  would fail, reinstating the very false positive this PR removes and diverging\n  from `kaappi check`, which never sandboxes.\n- A comment records the residual edge (a C-FFI library writing to fd 1 during\n  load bypasses the Scheme-port redirect) and why closing it (OS-level dup2) is\n  left out.\n\n169 LSP checks pass; `zig build test` green; `zig fmt --check` clean.\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n---------\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-08-08T02:36:26Z",
          "tree_id": "d49ccf015b24686dbe08f66d335d4d1c01f5c09c",
          "url": "https://github.com/kaappi/kaappi/commit/a072706e19a299eee68bcd13afdb47c34077ab0c"
        },
        "date": 1786158085444,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.052489,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.211072,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.543659,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.797838,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004881,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046109,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.28345,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.052731,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.847896,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.114358,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.52658,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.26128,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.69135,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.96951,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.042117,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "212d2428eda309d118c64b584860934c71d7c702",
          "message": "Fix Windows LSP tests: build native file URIs for sibling-library cases (#2255)\n\n* Fix Windows LSP tests: build native file URIs for sibling-library cases\n\nThe LSP tests added in #2253 that make the server resolve a real sibling\n`.sld` from disk (`sibling-sld`, `stdout-guard`, the `globals-isolation`\ncontrol) failed on `windows-x64-test`/`windows-arm-test`. They built the\ndocument URI as `file://$TMP/...`, where `$TMP` under Git Bash is an MSYS path\n(`/tmp/...`), and passed it verbatim to a *native* `kaappi-lsp.exe`. The\n`check` controls beside them passed because MSYS rewrites path *arguments* to a\nWindows path, but nothing rewrites a path embedded in a URI string — so the\nserver's `fileUriToPath` produced an MSYS path it could not resolve, the\nsibling library was not found, and the assertions failed.\n\nAdd a `file_uri` test helper that runs the path through `native_path`\n(`cygpath -m` on Windows, identity elsewhere) and frames it as a proper URI:\n`file:///C:/...` for a drive-lettered path, `file:///tmp/...` for a Unix\nabsolute one. `fileUriToPath` already decodes both. Only the cases that resolve\na real file on disk are converted; URIs used purely as document keys are left\nalone. No behaviour change on macOS/Linux (native_path is identity there); the\nfull LSP suite stays 169/169 locally.\n\nSource is unchanged — this is a test-only fix.\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* lsp tests: percent-encode file_uri paths, add space/reserved-char case\n\nCodeRabbit review: native_path normalizes filesystem syntax only, so a\nspace, '#', '?', '%' or non-ASCII byte in $TMP or a fixture path landed\nunescaped in the textDocument/uri string. Percent-encode the converted\npath as UTF-8 after native_path (uri_encode, preserving '/' and the\ndrive-letter ':') so the URI is well-formed per RFC 8089 and round-trips\nthrough the server's fileUriToPath %XX decoding.\n\nNew regression case opens a document under 'proj with #% space/' whose\nsibling .sld resolves only if the encoding round-trips. The response URI\nassertion (%20/%23/%25) is the guard that fails if encoding is removed;\nthe clean-diagnostics assertion proves the encoded URI resolves end to\nend. '?' is deliberately not used — Windows filenames cannot contain it.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n---------\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-08-08T04:04:03Z",
          "tree_id": "a04bf4229a2298066bd8cf1bffd8b56024618f62",
          "url": "https://github.com/kaappi/kaappi/commit/212d2428eda309d118c64b584860934c71d7c702"
        },
        "date": 1786164002911,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.355264,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.349338,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.58553,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.048095,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004791,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.047023,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.318544,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.056737,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.751205,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.242893,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.630827,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.278486,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.830292,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.699194,
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
          "id": "ed37a085ee2080715b26b41f04216a34d5d07400",
          "message": "Validate syntax-rules ellipsis usage: template depth (#682) and pattern grammar (#2082) (#2256)\n\n* Validate syntax-rules ellipsis usage: template depth (#682) and pattern grammar (#2082)\n\nsyntax-rules accepted two kinds of ill-formed rules and answered\nsomething instead of erroring, both silent wrong-output defects in the\nR7RS 4.3.2 pattern language:\n\n- #682 (template side): a pattern variable used under FEWER template\n  ellipses than its pattern depth substituted the never-set `()` for the\n  matched input. instantiateEllipsis now rejects a directly-referenced\n  list binding whose depth exceeds the consuming ellipsis run\n  (1 + extra_ellipsis, so (x ... ...) flattening stays legal), and\n  instantiateTemplate rejects a list binding used with no ellipsis at\n  all. Legitimate nested, consecutive-ellipsis, and SRFI 149\n  excess-ellipsis shapes are untouched.\n\n- #2082 (pattern side): a list or vector pattern with more than one\n  ellipsis at its own level was accepted, and the surplus ellipsis\n  tokens were counted as fixed tail elements, so the trailing pattern\n  always took the last two inputs. parseSyntaxRules now validates every\n  rule's pattern at definition time (matching chibi and Guile, which\n  reject the define-syntax), honouring custom ellipsis identifiers and\n  the ellipsis-as-literal carve-out, and keeping first-position `...`\n  (a plain pattern variable per the matcher, e.g. srfi136's\n  `(cname field (... ...))` guard) legal.\n\nThe regression-test half of #682 was a test that never exercised the\ndefect: tests/scheme/smoke/ellipsis-depth-mismatch.scm only pinned the\nvalid case, and srfi149/srfi46 carried disabled FAIL assertions plus\nenabled pins of the wrong answers. Those are now flipped to assertions\nthat the mismatch RAISES (shown to fail against a build with the fix\nreverted), and Zig unit tests cover both issues plus the control shapes.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Address review: validate vector dotted tails, split ellipsis tests, SRFI-64 smoke harness\n\nThree review findings from PR #2256 review:\n\n- validPatternGrammar's dotted-tail branch recursed into pairs, but that\n  branch was unreachable (the while loop only exits once cur is not a\n  pair), and a vector dotted tail -- (_ . #(a ... b ...)) -- bypassed\n  validation entirely, accepting two ellipses in one vector pattern. The\n  branch now recurses into vectors; regression test added (verified to\n  fail against the pre-fix code).\n\n- Move the #682/#2082 ellipsis-validation tests out of tests_macros.zig\n  (1963 lines) into a dedicated src/tests_ellipsis.zig, wired via\n  vm_tests.zig like tests_macros_nested_sr.zig, per the 1500-line file\n  policy.\n\n- Convert tests/scheme/smoke/ellipsis-depth-mismatch.scm from the\n  verdictless display/exit style to the documented SRFI-64 harness\n  (imports (scheme process-context) and (srfi 64), test-begin/test-end,\n  exit 1 on fail-count), per docs/dev/testing.md. Verified to exit 1\n  against the unfixed build (212d2428) and pass with the fix.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n---------\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>",
          "timestamp": "2026-08-08T06:29:37Z",
          "tree_id": "ac0c72a75e5d03061be3a0a3e3e3e54e7e9b7eb8",
          "url": "https://github.com/kaappi/kaappi/commit/ed37a085ee2080715b26b41f04216a34d5d07400"
        },
        "date": 1786172576164,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.977846,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.561951,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.567238,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.878414,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004846,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.045549,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.299653,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.054941,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.398322,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.185045,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.55351,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.298586,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.704826,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.768751,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044765,
            "unit": "seconds"
          }
        ]
      }
    ]
  }
}