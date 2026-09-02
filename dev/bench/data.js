window.BENCHMARK_DATA = {
  "lastUpdate": 1788333209597,
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
          "id": "59e473cf7f01fbd8dd28d39e5767334b0891a83c",
          "message": "Fix SRFI-170 validation gaps and implement the posix-error protocol (Fixes #1977, #1978) (#2279)\n\n* Fix SRFI-170 validation gaps and implement the posix-error protocol (Fixes #1977, #1978)\n\nTwo audit findings (systematic audit v2, Phase 2.12) covered together\nbecause they touch the same file and the same raise helpers:\n\n#1977 — a mistyped argument was discarded rather than rejected:\n- (nice \"x\") was treated as \"no argument supplied\" and really renice'd\n  the process by the default +1; only the type test was missing.\n- platform.setEnv/unsetEnv discarded setenv(3)'s return, so an EINVAL\n  name (containing '=' or empty) returned normally while setting nothing.\n- create-directory/create-fifo silently defaulted the mode, create-temp-\n  file silently defaulted the prefix, and set-file-times stamped both\n  timestamps to now on a mistyped time argument.\n- The variadic specs had no upper bound, so surplus arguments were\n  accepted and ignored.\nEach now raises, set-file-times enforces SRFI-170's \"exactly one time is\nan error\" rule, and the seven variadic SRFI-170 signatures declare a new\n.range arity (min..max) so surplus arguments are an arity mismatch.\n\n#1978 — the spec's error protocol was absent and the taxonomy was wrong:\n- Added posix-error?, posix-error-name and posix-error-message. Every\n  SRFI-170 file error now captures the thread-local errno on the\n  condition object at the failing syscall (raiseFileError snapshots\n  std.c._errno() before any allocation); posix-error-name scans std.c.E\n  per-OS enums so the name (ENOENT/ENOTDIR/EACCES/ELOOP/...) is portable\n  even though the numbers differ; posix-error-message calls strerror(3).\n  Non-syscall raises (NUL pre-check, symlink-target-too-long, Windows\n  stubs) pass errno 0 explicitly so posix-error? stays false.\n- Argument-range validation (mode/uid-gid/nice/prefix) is now raised as\n  KP3007 invalid-argument via raiseArgError instead of a file error, so\n  file-error? answers #f for failures that never touched the filesystem.\n- file-info/user-info/group-info are pure value records but were listed\n  as UncopyableType; gc_deep_copy.zig now copies them by value across\n  the SRFI-18 boundary (directory-object stays uncopyable - live DIR*),\n  and the \"uncopyable type (port, continuation, etc.)\" messages name\n  the real uncopyable set instead of implying these records are in it.\n\nTests: the audit suite's disabled FAIL rows for both issues are enabled\n(the bug-pinning controls are removed), section G2 adds the posix-error\nprotocol matrix incl. errno survival through the thread boundary, the\ndeep-copy matrix audit flips the three SRFI-170 rows to cross, and\ntests_deepcopy.zig gains unit tests for the three copyable types, the\ndirectory-object refusal, and errno preservation on error-object copy.\nAll 2099 Scheme files + 1395 R7RS tests + unit suite (incl. -Dgc-stress)\npass; all 8 cross-compile targets and wasm still build.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Capture the real errno from statx on Linux (Fixes CI regression in #2279)\n\ndoStat's Linux path calls the raw statx(2) syscall, which reports failure\nby returning -errno as the syscall result rather than setting the libc\nerrno. The posix-error protocol (#1978) snapshots errno at the raise site,\nso on Linux a failed stat carried a stale thread-local: posix-error?\nanswered #f and posix-error-name/message could not name ENOENT/ELOOP.\ndoStat now reports the errno itself — statx's huge-usize raw result is\nbitcast back to isize and negated, and the libc paths read _errno() — and\nfile-info raises through raiseFileErrorCode with that value. Caught by the\nubuntu CI legs (the first attempt even panicked: an @intCast of the raw\nusize to c_int). Verified in an alpine container: the audit suite's\nposix-error matrix and all 49 protocol smoke tests now pass on x86_64\nLinux; macOS and the cross-compile matrix are unaffected.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Address review comments on #2279\n\nCode-review follow-ups (CodeRabbit + maintainer):\n\n- Bound  to 0..1 arguments — it was the one remaining variadic\n  SRFI-170 signature without an upper bound, so (nice 1 2 3) silently\n  ignored the surplus (the exact #1977 defect class). Audit pins it.\n- Thread the calling procedure name through validateMode and\n  expectPosixError, which hard-coded 'set-file-mode' / 'posix-error-name':\n  (create-directory d \"x\") reported a type error naming set-file-mode,\n  and (posix-error-message 42) named posix-error-name. Reached for the\n  first time by this PR's validation fixes.\n- Copy posix_errno out of the ErrorObject before gc.allocSymbol /\n  gc.allocString in posix-error-name/-message: the raw object pointer\n  must not survive an allocation unrooted (gc-safety rule).\n- set-file-times now rejects non-UTC time objects: a monotonic clock's\n  seconds are an arbitrary epoch and were being written to utimensat as\n  wall-clock time (SRFI-170 requires time-utc).\n- doStat's Windows widen failure no longer reads a stale errno (it is a\n  UTF conversion, not a syscall) — reports 0.\n- vm_dispatch's two inline native-arity switches now call the shared\n  vm_calls.checkNativeArity (made pub), so a future Arity variant is\n  edited once, not three times.\n- check_lint renders a range with the plural noun (\"0 to 1 arguments\").\n- platform.zig: drop the stale \"We ignore the return either way\" note —\n  unsetEnv now propagates the errno.\n- thread-value-sharing.md:287: 14-tag -> 11-tag refusal list.\n\nTests: audit adds (nice 0 'extra), the monotonic-time rejection plus a\nposix-time round-trip control for set-file-times, splits section H into\ncopies?/refused? so the directory-object refusal is actually pinned (the\nold out-of-thread helper returned #t for both a successful copy and a\nclean refusal), drops the locale-dependent strerror literal for a\nstring? check, and tests_deepcopy asserts every FileInfo/UserInfo field.\n\nFull suite green: 2099 Scheme files, 1395 R7RS, unit + gc-stress, wasm\nand all cross-compile targets.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n---------\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>",
          "timestamp": "2026-08-10T15:10:10+05:30",
          "tree_id": "34d52b57aea059bf5f3950e75e19c9d099d1f478",
          "url": "https://github.com/kaappi/kaappi/commit/59e473cf7f01fbd8dd28d39e5767334b0891a83c"
        },
        "date": 1786356935276,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.359135,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.565846,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.56452,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.034818,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004608,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.049571,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.305412,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.055954,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.855033,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.232895,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.676086,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.280126,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.773581,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.478451,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044857,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "6209f7fdcb00f5cf23aa10a7cdaa649d09e3f3cd",
          "message": "Fix SRFI 150 hygiene collapse: resolve field identity at expansion time (Fixes #2051) (#2280)\n\n* Fix SRFI 150 hygiene collapse: resolve field identity at expansion time (Fixes #2051)\n\nlib/srfi/150.sld carried field names from macro-expansion time to run\ntime inside `quote`. The compiler strips a `__hyg_N_` rename from any\nquoted datum (required for syntax-rules templates), so two field\nidentifiers the expander had correctly distinguished -- a macro\ntemplate's own field-name literal and the same-spelled identifier the\nuse site supplies, e.g. __hyg_2_a and a -- stripped to one runtime name\nand collapsed into a single field. All four of the reference suite's\nhygiene assertions failed on it; the attribution to #1832 (pre-existing\ntop-level binding of the colliding spelling) was wrong -- the no-binding\ncontrol fails identically.\n\nThe redesign resolves field identity entirely at macro-expansion time,\nwhile the renamed symbols are still in hand:\n\n- A constructor spec entry matches the current form's own fields by full\n  spelling (bound-identifier=? in this engine's rename-by-spelling\n  model, then inherited fields by hygiene-stripped spelling against the\n  parent's stored property (free-identifier=?), and resolves to a\n  numeric absolute layout index. named-constructor fills the field\n  vector by index; no runtime by-name lookup happens at all.\n- Each own field gets a runtime name for the rtd and accessor/mutator\n  creation: its stripped spelling, deduped with a numeric suffix when\n  two own fields strip to the same spelling. An own field matching an\n  inherited field's spelling is deliberately not deduped -- that is\n  ordinary shadowing. Constant field names get generated field-<index>\n  names, which also makes the SRFI's promised non-identifier field\n  names actually work (they previously errored in symbol->string).\n- The property table stores the total field count plus stripped-spelling\n  keys to absolute indices -- keys and indices only, no renamed symbols.\n- The emitted type-name binding is hygiene-stripped too: a\n  template-introduced __hyg_N_<t> reference whose base <t> is already\n  bound is intercepted by the #1832 referential-transparency alias\n  (loading the pre-existing global even inside the same expansion that\n  defines it), so accessors bound against the old record type whenever a\n  macro redefined an already-bound type name.\n\nThe reference suite passes in full (previously 21/25); the four\ntest-expect-fail cases are unmarked. tests/scheme/srfi/srfi150.scm gains\nthe issue's discriminating controls as regressions: the no-binding C5\nvariant, the non-colliding-spelling C6 control, the minimal repro, and\nconstant field names (including inherited constants).\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nEOF\n)\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Address review: field-name precedence, explicit (srfi 13) import, valid C5 control\n\nThree review findings on the SRFI 150 fix (kaappi#2051):\n\n- own-field-data interleaved each field's field-name and accessor-name\n  keys, so a label that was field j's field name and field i's accessor\n  name (i < j) resolved to the accessor's index. The SRFI 150 precedence\n  rule -- the field name wins -- only held when the coinciding field sat\n  at a lower index, which the reference suite's field-referral case\n  happened to exercise. Emit all field-name keys before all accessor-name\n  keys (in field order within each group), for both the full-spelling own\n  alist and the stripped-spelling property alist; add the discriminating\n  reversed-order shape as a regression test.\n- string-prefix?/string-index are (srfi 13) exports, previously reached\n  only through the vm.globals fallback (the #1831 hazard documented in\n  this file's header); import them explicitly via (only (srfi 13) ...).\n- The C5 regression control reused the spelling `a`, which the reference\n  suite binds at top level just above -- so it never tested the\n  \"no pre-existing binding\" claim. Use the unbound spelling `nb` for\n  both the template literal and the use site.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n---------\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>",
          "timestamp": "2026-08-11T13:30:36+05:30",
          "tree_id": "e624993ccdddefb3e33089984d4f40a03c25f0e7",
          "url": "https://github.com/kaappi/kaappi/commit/6209f7fdcb00f5cf23aa10a7cdaa649d09e3f3cd"
        },
        "date": 1786437117604,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.048015,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.975505,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.565163,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.870736,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.005181,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.047312,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.288196,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.053821,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.334925,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.136643,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.62624,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.303613,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.699701,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.812943,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.048875,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "f65c99129c242feedb2c0e9232b8bc41b2fd4312",
          "message": "Add bounded-step, resumable execution entry point (Fixes #2283) (#2284)\n\n* Add bounded-step, resumable execution entry point (Fixes #2283)\n\nThe WASM playground could only run programs through a synchronous WASI\n`_start` that blocks until completion, so its only runaway guard was a hard\n5 s `terminate()` on the Web Worker — which kills legitimately long-running,\nconstant-space programs like `((call/cc call/cc) (call/cc call/cc))` and\ndiscards output already produced.\n\nGive hosts a resumable, instruction-budgeted entry point instead, reusing the\nmachinery the SRFI-18 scheduler and GC already need: the dispatch-loop\nsafepoint, `error.Yielded`, and frames that live in the VM struct rather than\non the host C stack across a yield. A step budget is one more thing the\nsafepoint checks; when the outermost stepped loop reaches its deadline it\nreturns `error.Yielded` with `step_paused` set — between instructions, so\nevery stack and the ip are consistent and no rewind is needed.\n\nThe pause fires only in the outermost stepped `runUntil`, guarded by\n`step_active`, which runUntil save/restores exactly as it does\n`dispatched_from_scheduler`. A nested runUntil (eval, a native higher-order\ndriver's callback, a scheduler fiber slice, a file-backed library load) runs\nwith `step_active == false` and cannot pause, so a mid-form pause never\nstrands a half-finished native frame. beginStep/resumeStep arm stepping only\nwhen no scheduler exists, so a fibered program runs its scheduler slice to\ncompletion within a step rather than pausing mid-fiber.\n\n- VM: `beginStep`/`resumeStep` (vm_calls.zig), sharing `prepareTopLevelFrame`\n  and the success/error tails with `execute`; the pause is intercepted before\n  those tails so nothing is torn down while the form is merely suspended.\n- Driver: `vm_step.Stepper` iterates top-level forms like runFile — quick\n  forms and library declarations run to completion, ordinary forms are\n  stepped — under one shared budget, with matching result echoing and error\n  reporting, plus a cooperative stop flag wired through `vm.terminate_flag`.\n- WASM: `kaappi_step_*` C-ABI exports (wasm_step.zig, built rdynamic) the\n  playground drives instead of `_start`; stdout/stderr already stream through\n  WASI fd_write as produced (fd 1/2 are unbuffered).\n\nTests: src/tests_step.zig covers finish, pause/resume-to-batch-result, the\nconstant-space infinite program stepping forever, cooperative stop, and\nerror-then-continue; loop bounds scale down under -Dgc-stress. docs/dev/\nbounded-step.md documents the mechanism and the outermost-loop invariant.\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Address review: resumed-form root boundary, zero-budget, setup leak\n\nFixes from the PR #2284 review:\n\n- Root boundary (major): the Stepper pushed a redundant GC root for the\n  compiled function before beginStep and popped it after, which made\n  beginStep record the form's root-stack base one slot too high. On a\n  *resumed* form that raised, finishRunError then truncated to that stale\n  depth, leaving a bogus root the GC would later mark. The func is already\n  kept alive by gc.extra_roots (Compiler.init leaves it there on success), so\n  the manual root was unnecessary as well as harmful — dropped it, so the\n  recorded base matches the real one. New regression test drives a form that\n  pauses and then raises, then allocates in the next form (fails under\n  -Dgc-stress with the old boundary).\n\n- Zero budget (minor): step() clamped the deadline with `@max(budget, 1024)`;\n  a zero budget previously returned .running without reading any form, so a\n  host pumping kaappi_step_run(0) spun forever. Sub-1024 budgets cannot pause\n  earlier than the safepoint anyway. New test pumps budget 0 to completion.\n\n- Setup leak (minor): kaappi_step_setup's stepper-allocation failure path now\n  frees the source buffer ownedSource had taken ownership of, instead of\n  leaking one program's linear memory per failed setup.\n\nFull unit suite green (normal and -Dgc-stress); wasm end-to-end harness green.\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Fix reader complex-root LIFO violation exposed by the new VM fields\n\nThe bounded-step VM fields added in this PR changed the VM struct layout,\nwhich shifted GC collection timing enough to make the riscv64 CI job abort\ndeterministically in the R7RS suite: a minor collection marked a root slot\nholding a pointer-tagged null (`0xFFFC…0000`) and `toObject` panicked. The\nbatch execution path is otherwise byte-for-byte identical to main, and the\nsame suite passed on every other platform and under native gc-stress, so the\nstruct-size change only *revealed* a latent bug — it did not introduce one.\n\nThe bug is in the complex-number reader (kaappi#2166). `rootComplexReal`/\n`rootComplexImag` pushed the two `complex_root` component slots onto the LIFO\nroot stack once, lazily, and popped them only in `Reader.deinit`. When a\ncomplex or rational number was an element of a list, that persistent push\nlanded *between* the balanced `pushRoot`/`popRoot` pairs `readList`/`readDatum`\nwrap around every element. The list's `defer popRoot()` then popped the\nreader's slot instead of its own (`popRoot` is LIFO, not per-variable —\n.claude/rules/gc-safety.md), orphaning a live list root that dangled once its\nframe returned. Whether the dangling slot later crashed a collection depended\non GC scheduling and stack contents, so it hid on x86_64/aarch64/s390x/ppc64le\n(the stale bits read as a benign non-pointer) and fired only on riscv64.\n\nScope the component roots to a single number's tokenization instead of the\nReader's lifetime: `beginComplexRootScope` pushes both slots at the tokenizer\nentry (readNumber / readNumberPrefixed) and a `defer` pops them on exit, so the\nstack stays strictly nested with the surrounding list/datum roots. The\ncomponents still outlive the other component's allocation — the actual\nkaappi#2166 hazard — and the token→datum window that follows performs no\nallocation before `makeComplexOrRealV` (which roots its own args). The nested\nreadNumberPrefixed→readNumber pair opens the scope exactly once via the\n`complex_roots_pushed` guard.\n\nRegression test (tests_gc_root_boundary.zig): reading one complex/rational\ndatum must leave `root_count` unchanged. It fails \"expected 0, found 2\" on the\nold code (the leaked pair) and passes with the fix — deterministic and\nplatform-independent. Verified: riscv64 R7RS now runs panic-free, the full\nunit suite is green normally and the reader/root/numeric/step tests under\n-Dgc-stress, and complex arithmetic still reads correctly.\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n---------\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-08-23T05:06:16+05:30",
          "tree_id": "cc36e571b5f7beb9670af5f178d3a3f7c825dc6a",
          "url": "https://github.com/kaappi/kaappi/commit/f65c99129c242feedb2c0e9232b8bc41b2fd4312"
        },
        "date": 1787443900576,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.059856,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.970765,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.547554,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.896893,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004881,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.04658,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.279932,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.053545,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.560108,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.145201,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.593236,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.301872,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.680732,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.779303,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.048379,
            "unit": "seconds"
          }
        ]
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
          "id": "4a6ba93151a81ca0d3681d83413482b4e20cd1e3",
          "message": "Release v0.23.0\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>",
          "timestamp": "2026-08-23T07:04:59+05:30",
          "tree_id": "99df048dc2fdefd2a925a5de23acb8d2cfc5f48c",
          "url": "https://github.com/kaappi/kaappi/commit/4a6ba93151a81ca0d3681d83413482b4e20cd1e3"
        },
        "date": 1787451962846,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.657807,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.483615,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.576732,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.087228,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004726,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.049033,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.314243,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.058221,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.916164,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.224279,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.701785,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.281271,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.836046,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.636878,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.04994,
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
          "id": "ba59191dc304886dd69e52e5d689aea085687029",
          "message": "Bump vmactions/openbsd-vm in the github-actions group (#2282)\n\nBumps the github-actions group with 1 update: [vmactions/openbsd-vm](https://github.com/vmactions/openbsd-vm).\n\n\nUpdates `vmactions/openbsd-vm` from 1.4.5 to 1.4.6\n- [Release notes](https://github.com/vmactions/openbsd-vm/releases)\n- [Commits](https://github.com/vmactions/openbsd-vm/compare/c941015845c0f0c429676840963dc63b226d4f69...e6c68b637a12e83519688d115d57d5b0b53923cd)\n\n---\nupdated-dependencies:\n- dependency-name: vmactions/openbsd-vm\n  dependency-version: 1.4.6\n  dependency-type: direct:production\n  update-type: version-update:semver-patch\n  dependency-group: github-actions\n...\n\nSigned-off-by: dependabot[bot] <support@github.com>\nCo-authored-by: dependabot[bot] <49699333+dependabot[bot]@users.noreply.github.com>",
          "timestamp": "2026-08-23T11:39:48+05:30",
          "tree_id": "095b671d249dd38b86facf916ef97b7f84397eea",
          "url": "https://github.com/kaappi/kaappi/commit/ba59191dc304886dd69e52e5d689aea085687029"
        },
        "date": 1787467400809,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.312566,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.785646,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.569287,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.023455,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004781,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.048028,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.308568,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.056162,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.854656,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.207565,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.654809,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.286801,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.807513,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.639254,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045267,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "a18a3b54508f2b2ac8a7ea222bb87ceb79e8ffa6",
          "message": "Enforce lambda-style arity in top-level define-values (Fixes #550) (#2286)\n\nTop-level `(define-values <formals> <expr>)` is intercepted by\n`handleDefineValues` in vm_eval.zig rather than compiled through the normal\n`call-with-values`/consumer-lambda desugaring. Its handwritten binding logic\nmatched formals to values only up to whichever ran out first: it bound a\nprefix, ignored extras, left missing names uncreated, and continued. So every\nfixed-arity mismatch that produced a *single* value ran silently with exit 0 —\n`(define-values (a b) (values 1))`, `(define-values () 42)`,\n`(define-values (a b) 1)` — while the identical definition one scope in already\nraised, because the compiler desugaring enforces the arity through a lambda.\n\nRewrite the handler to match values to formals with lambda-style arity, exactly\nas R7RS 5.3.3 / SRFI 244 specify: a fixed list requires an exact count, a dotted\nlist a minimum, a bare identifier collects all values with no constraint. The\ncheck runs before any global is defined, so a mismatch leaves no partial\nbindings and raises the same KP3003 (`ArityMismatch`) the internal path does —\nreplacing the KP2001 the multi-value arm used to return for the same condition.\n\nThe genuine top-level path fires only for a bare top-level form (not one in a\nlet/lambda body, nor one handed to `eval` with an immutable `(environment ...)`,\nwhich raises KP3007 first), and a top-level raise flips the whole file's exit\ncode — so it cannot be asserted from a SRFI-64 file. Cover it out-of-process in\ntests/scheme/errors/define-values-toplevel-arity-550.sh (exit code + KP3003 for\nevery mismatch shape, exit 0 + output for every well-matched shape), add Zig\nunit tests exercising handleDefineValues directly, and retire srfi244.scm's\nnow-obsolete \"silently accepted\" probes.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-08-23T13:21:04+05:30",
          "tree_id": "2c8ee64b784b1baa37aaa4b2f42f5f3636d53ccb",
          "url": "https://github.com/kaappi/kaappi/commit/a18a3b54508f2b2ac8a7ea222bb87ceb79e8ffa6"
        },
        "date": 1787473625870,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.313996,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.282685,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.623772,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.018883,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.005008,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.048766,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.322366,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057088,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.934788,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.216192,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.704133,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.293289,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.805439,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.698439,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045888,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "6a196dd9dbb5c0d9aef4ef1f57f44684baa1486c",
          "message": "thottam: strict SemVer tag parsing, npm-style ^/~ ranges, and constraint diagnostics (#2287)\n\n* thottam: strict SemVer tag parsing, npm-style ^/~ ranges, and constraint diagnostics\n\nFix three thottam version-resolution defects from the Phase 6E audit.\n\nSemver.parse now rejects tags that are not SemVer 2.0.0 §2 versions:\na fourth dot-separated component (v2.0.0.nightly-UNRELEASED), leading\nzeroes (v01.02.03), and Zig integer-literal spellings such as the '+'\nsign and '_' digit separators (v1_0.0.0 parsing as 10.0.0). Components\nare parsed by a hand-rolled digit loop instead of std.fmt.parseInt\n(#2130).\n\nSemver.parse additionally records how many components were written, and\nthe caret/tilde matchers use it: ~1 is >=1.0.0 <2.0.0 (not ~1.0.0's\n>=1.0.0 <1.1.0), and ^0.0 is the whole 0.0.x line rather than exactly\n0.0.0 (#2131).\n\nresolveVersion now distinguishes a malformed constraint from an\nunsatisfiable one, naming the offending comma-separated part (and\ndiagnosing the undocumented four-part ceiling) instead of reporting\neverything as 'no version matching'. Operator/version whitespace\n(>= 1.0.0) is accepted per node-semver. InvalidPackageName is handled\nin main rather than leaking a raw Zig error name, a trailing pkg@ is an\nabsent version, and an empty build: line is an absence, not a command\n(#2132).\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* thottam: distinguish git ls-remote failures and tighten docs/tests per review\n\nAddress review feedback on the #2130/#2131/#2132 PR:\n\n- resolveVersion gains a git_failed outcome so a failed 'git ls-remote'\n  (missing/private repo, no network) is reported as 'failed to list tags'\n  rather than folded into 'no version matching' — an IO failure should not\n  read as an unsatisfiable range. doInstall prints the distinct message.\n- Docs no longer claim a candidate tag must be exactly X.Y.Z: one- and\n  two-component tags (v1, v1.2) are accepted leniently, only extra\n  components and leading zeroes are rejected.\n- Drop the unreachable i == 0 guard in parseConstraintsDiag (splitScalar\n  always yields a token, so the empty-spec path returns via\n  parseSingleConstraint) and explain why.\n- Quote $THOTTAM in the malformed-constraint lifecycle loop, and add a\n  lifecycle check that an unavailable repository is a fetch error, not\n  'no version matching'.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n---------\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>",
          "timestamp": "2026-08-23T09:25:49Z",
          "tree_id": "d8b504c5b8570a06a98c27038a4fd1a4c168472a",
          "url": "https://github.com/kaappi/kaappi/commit/6a196dd9dbb5c0d9aef4ef1f57f44684baa1486c"
        },
        "date": 1787479140373,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.479917,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.931756,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.470757,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.447604,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004857,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.041888,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.255478,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.045999,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.490282,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.014418,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.407103,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.259239,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.509185,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.972557,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.0384,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "7e8bc4e92c8c71c3de2d7f8bf7a2fe0085d8c921",
          "message": "thottam: verify the installation, enforce --locked provenance, tolerate CRLF (#2288)\n\n* thottam: verify the installation, enforce --locked provenance, tolerate CRLF (#2133, #2135, #2137)\n\nThree audit findings in the package manager's state handling, fixed together\nbecause they share the same files and the same root cause class — thottam\ntreating a lockfile it did not write (CRLF-normalised, truncated, or\nhand-edited) as trustworthy, and reading the wrong half of the install state.\n\nverify (#2135): doVerify walked the lockfile and never consulted\ninstalled.txt, so a package that is installed but absent from the lockfile\nwas silently dropped from verification and the run still printed \"All\npackages verified\". An empty or binary-garbage lockfile did the same. It now\nwalks installed.txt instead: every installed package must have a lockfile\nentry at the SHA it is actually checked out at, a malformed lockfile line\nfails the run rather than being skipped, and a mismatching pair prints the\nfull SHAs so the message cannot render two different values identically.\n\n--locked (#2137): locked installs compared only the SHA and took the clone\nURL from the invocation, then overwrote the lockfile's recorded provenance\nwith it — so a fork sharing history passed the check and the lockfile came\nto attest to the fork. The lockfile entry is now read once: the recorded\nsource is the clone URL, an explicit ::url that disagrees is refused before\nany clone, and a --locked install never rewrites the recorded source.\n\nCRLF (#2133): a checkout normalised to CRLF left a trailing \\r in the\nrecorded SHA, so verify reported \"MISMATCH (locked: X, actual: X)\" and\n--locked handed \"<sha>\\r\" to git checkout. Every reader of thottam.lock and\ninstalled.txt now strips the trailing \\r.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* thottam: tighten malformed-lockfile validation, drop dead code, add coverage\n\nReview follow-up for the #2133/#2135/#2137 PR:\n\n- Delete getLockedSha, now unused — its only caller was the removed import\n  in thottam.zig, and the #2137 fix deliberately moved away from the\n  SHA-only accessor.\n- Reject empty name/SHA/source fields in doVerify's lockfile structure pass\n  (a line like \"pkg  source\" or \"pkg sha \" is now MALFORMED, not an\n  ordinary mismatch).\n- Add a CRLF regression test for isInstalled.\n- Strengthen the lifecycle suite: assert the UNLOCKED package name, a\n  MALFORMED line, the --locked source-URL-mismatch diagnostic and that the\n  fork is refused before any clone, a byte-for-byte lockfile restore check\n  via cmp, and a control that a matching ::url is accepted.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n---------\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>",
          "timestamp": "2026-08-23T11:35:21Z",
          "tree_id": "d36b8d2adce2c32acdd7901d2873b3796ebeeec7",
          "url": "https://github.com/kaappi/kaappi/commit/7e8bc4e92c8c71c3de2d7f8bf7a2fe0085d8c921"
        },
        "date": 1787486998509,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.051277,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.144695,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.430066,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.200171,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.003785,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.036166,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.220165,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.042308,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 1.819705,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.872136,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.247357,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.241208,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.294362,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.416345,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.036645,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "59a6552093a3005392b6a1ef5266c2dbf26bed52",
          "message": "thottam: fix version re-pins, ownership-aware removal, and state-file name validation (#2289)\n\n* thottam: fix version re-pins, ownership-aware removal, and state-file name validation (#2134 #2136 #2138 #2144)\n\nFour audit findings in the package manager, each a place where thottam\nreported one thing and did another.\n\n#2134 — version pinning was a dead end. 'install pkg@ver' on an\nalready-installed package short-circuited on isInstalled before the\nrequested version was looked at, exiting 0 while leaving the old version\nin place — a provisioning script that pins and checks the exit status is\ntold it succeeded. And 'update' ran 'git pull' unconditionally, so a pin's\ndetached HEAD surfaced git's own unactionable advice and one pinned\npackage failed the whole-tree update. Install now resolves the requested\nversion before the already-installed check and re-checkouts (rebuild,\nre-copy, re-record) when the checkout differs; update detects the\ndetached HEAD and says plainly what the package is pinned to, skipping it\ninstead of failing the tree. 'install pkg@<version>' is the way to move a\npin, and it now works.\n\n#2136 — removal deleted library files by name with no ownership record.\nTwo packages shipping lib/kaappi/shared.sld: removing one unlinked the\nfile the other still relied on, leaving it reported as installed but\nbroken, and installs silently overwrote each other's copies. A new state\nfile, ~/.kaappi/thottam.files, records every installed file per package;\nremove unlinks only files no other installed package claims, and installs\nwarn when they overwrite a file another package owns. Empty directory\nskeletons left by removal are pruned.\n\n#2138 — kaappi.pkg's name: and source: fields were parsed, copied and\nnever read; version: was parsed by nothing. Since the manifest is only\nread after cloning, source: could never be the clone URL. The fields are\ndeleted from the parser and the documented grammar; only depends: and\nbuild: are read, and every other key (name:, version:, source: included)\nis ignored by construction. Third-party packages are sourced via ::url or\nKAAPPI_ORG.\n\n#2144 — list/verify/update built filesystem paths from unvalidated\npackage names read back from installed.txt and thottam.lock, while\ninstall and remove validated. A hand-edited or corrupted state file could\nsend git -C outside . Every consumer now inherits the guard:\nlist and update-all skip invalid names, update validates its argument at\nentry, and verify names invalid entries MALFORMED and fails.\n\nThe lifecycle suite's disabled FAIL: #NNNN checks are re-enabled and\nextended (pin re-install, pin move, pinned-update no-op, shared-file\nremoval, overwrite warning, empty-dir pruning, corrupted-state handling,\ninert-manifest installs): 133 assertions, all offline against local bare\nrepositories.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* thottam: keep the installed-file manifest authoritative across update (review)\n\nReview feedback on #2289 found one real gap: doUpdate copied the pulled\nlib tree but never refreshed thottam.files, so the #2136 ownership\nguarantee lapsed after any pull. If an upstream release of package A\nadded lib/kaappi/shared.sld (already owned by B), 'thottam update A'\ncopied the file and recorded nothing; a later 'thottam remove B' then\nsaw no other claimant and unlinked the file out from under A — exactly\nthe bug the manifest set out to close, reachable via the update path.\n\nThe copy+record block that install used is factored into a shared\nsyncInstalledFiles used by both install and update: collect the new file\nset, warn about files another package claims, copy, unlink files this\npackage previously owned that the new version dropped (unless another\npackage still claims them — the re-pin orphan case, where an upstream\ndeletion left a stale copy the rewritten manifest could no longer find),\nthen record the set. Install and update now keep on-disk state and the\nownership record in lockstep.\n\nAlso: document that the newest copy of a shared file stays authoritative\n(removal does not restore the previous contents), wire the previously\nunused sha_v100 into the v1.0.0 pin control assertion, and add two\nlifecycle regressions — an update that adds a shared file must record\nthe ownership so removing the other claimant keeps it, and an update\nthat drops a shared file must keep the other package's copy and drop the\nrecord so removing the updated package cannot delete it.\n\n145 lifecycle assertions (was 133), 1723 unit tests, all offline.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n---------\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>",
          "timestamp": "2026-08-23T13:25:38Z",
          "tree_id": "18c56a33879f57abfb445c5828da76ca0ae5d0da",
          "url": "https://github.com/kaappi/kaappi/commit/59a6552093a3005392b6a1ef5266c2dbf26bed52"
        },
        "date": 1787493823728,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.312801,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.698395,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.573317,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.018031,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004705,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.04853,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.322289,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.056045,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.816637,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.219325,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.665945,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.28032,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.788545,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.553425,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043395,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "566b53549929f20bbfa796b336a5d9a8bd528ec5",
          "message": "thottam: resolve git through PATH instead of hardcoding /usr/bin/git (Fixes #2152) (#2290)\n\n* thottam: resolve git through PATH instead of hardcoding /usr/bin/git (Fixes #2152)\n\nrunGit/runGitCapture hardcoded /usr/bin/git on every non-Windows platform.\nThat path exists on macOS and CI's Linux images but on none of the three\nsupported BSDs -- FreeBSD and OpenBSD install git in /usr/local/bin, NetBSD\nin /usr/pkg/bin -- so every git-backed operation (install, update, ls-remote\nversion resolution) failed there, leaving thottam non-functional on platforms\nKaappi ships binaries for.\n\nResolve the binary through PATH the same way `kaappi compile` discovers a C\ncompiler (native_compiler.zig) and test_selection locates its git: search\nPATH for the first readable `git` and hand the absolute path to execve, so\nthe child never depends on PATH resolution. A missing git is now a distinct\nerror.GitNotFound that install/update report with a cause, instead of the old\nsilent 127 that surfaced as \"Failed to clone repository\".\n\nStop swallowing the spawn failure too: runPassthrough's child now prints\n\"cannot execute <argv[0]>: <errno>\" before exiting 127, so a FileNotFound on\nthe git binary and a genuine clone failure are no longer indistinguishable in\nthe logs -- the second defect that hid the first across three CI runs.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* thottam: require executable git and route GitNotFound through every call site\n\nReview follow-up to #2152 (the PATH-resolution fix), closing the gaps the\nreviewers found in the diagnostic half:\n\n- findInPath now requires an executable regular file, not merely a readable\n  one. A non-executable file or a directory named git no longer shadows a\n  later real git and then fails at execve instead of falling through to the\n  next PATH entry. X_OK (not R_OK) keeps an execute-only git working; Windows,\n  which has no execute bit, accepts any regular (already .exe-suffixed) file.\n\n- The missing-git diagnostic is now wired through every call site that can\n  surface it, not just clone/pull. resolveVersion gains a git_not_found\n  outcome, checkoutVersion re-raises GitNotFound, and the update flow's\n  symbolic-ref probe distinguishes it from a detached HEAD. A shared\n  missingGit() helper prints the one message, so a git-less\n  `install pkg@\">=1.0.0\"`, `install pkg@tag` on an installed package, and\n  `update pkg` each say \"git not found in PATH\" instead of the old \"failed\n  to list tags\" / \"Failed to checkout version\" / bogus \"pinned\" misdiagnoses.\n\n- runCapture mirrors runPassthrough's execve diagnostic: it saves the real\n  stderr before /dev/null'ing it, so a git that resolves but will not exec\n  is no longer a silent 127 through ls-remote version resolution.\n\n- The findInPath test builds its PATH with platform.path_list_sep (fixing the\n  Windows unit-test failure) and asserts the executability requirement — a\n  non-executable fixture is skipped, the executable one resolves, and the\n  resolved path runs.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n---------\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>",
          "timestamp": "2026-08-23T15:13:30Z",
          "tree_id": "95229bc36eea6b66e4995492a8922c3336dacf5c",
          "url": "https://github.com/kaappi/kaappi/commit/566b53549929f20bbfa796b336a5d9a8bd528ec5"
        },
        "date": 1787500147404,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.068033,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.221544,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.552796,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.877137,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004872,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.04647,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.28262,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.053131,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.377341,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.151319,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.59671,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.30389,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.685234,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.909946,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.046274,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "e5bd7747e235ff10a1a7a8866eb695016165ab88",
          "message": "Fix fmt round-trip, lexer, idempotence, and width audit findings (#2291)\n\n* Fix fmt round-trip, lexer, idempotence, and width audit findings\n\nFive defects from the systematic audit (Phase 6), all in the formatter\nand the reader it mirrors:\n\n- #2079: a lone CR now ends a `;` comment, per R7RS 7.1.1. The reader's\n  comment scan stopped only at `\\n`, so a classic-Mac-line-ending file\n  swallowed everything after the first `;`. fmt's CST lexer mirrors the\n  fix, and the pinned \"known deviation\" test and doc section are updated.\n\n- #2080: `kaappi fmt` no longer reports a user syntax error as \"internal\n  error\". `verifyRoundTrip` reads the original first and reports the\n  reader's own KP1xxx diagnostic with its position; the internal-error\n  wording is reserved for a genuine mismatch between two successfully-read\n  datum sequences.\n\n- #2142: `hasBodyBlank` counted head-line items by index while the printer\n  counted code items, so a same-line block comment shifted the body\n  boundary and broke idempotence. It now counts code items the same way.\n\n- #2143: fmt's atom scan ran to the next delimiter, so a `#`-led lexeme\n  glued to an identifier split differently than the reader's identifier\n  scan. Non-`#` atoms now end at the first non-<subsequent> byte, matching\n  readSymbol, while `#`-led atoms keep their interior-`#` carve-outs.\n\n- #2149: fmt measured line width in bytes, so Unicode identifiers counted\n  double/triple against the 80-column budget. Width is now measured in\n  Unicode code points, in both `measure` and the printer's column cursor.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Address review feedback: line/col for lone CR, UTF-8 width, OOM message\n\n- reader.getLineCol/recordSpan now count a lone CR and CRLF as one line\n  ending (R7RS 7.1.1), matching the #2079 comment change, so a user syntax\n  error in a CR-only file reports the right line. Both go through a shared\n  lineColAt helper.\n\n- fmt_print.columnCount validates each UTF-8 sequence with utf8Decode, so a\n  malformed lead byte (e.g. 0xC2 followed by an ASCII byte) counts as one\n  column rather than swallowing the following byte. Made pub for direct\n  testing.\n\n- verifyRoundTrip gains an `oom` variant so an allocator failure during the\n  check is reported as \"out of memory\", not as a formatter mismatch.\n\n- Fix a dangling scanAtom -> scanHashAtom reference in a scanHash comment.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n---------\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>",
          "timestamp": "2026-08-23T19:12:14Z",
          "tree_id": "9d0faf8e1d0d889eb0bdc97e3f68498988ef4652",
          "url": "https://github.com/kaappi/kaappi/commit/e5bd7747e235ff10a1a7a8866eb695016165ab88"
        },
        "date": 1787514631514,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.373326,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.857712,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.584848,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.9897,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004754,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.050729,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.307715,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.074399,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.925498,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.213091,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.684448,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.283001,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.87827,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.647286,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045126,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "0154fe845c490109b217d3ec8ea1c8ec9aecc4cd",
          "message": "Rewrite SRFI 166 to fix the v2 audit findings (#2292)\n\n* Rewrite SRFI 166 to fix the v2 audit findings\n\nComplete reimplementation of the monadic formatting library against the\nSRFI 166 specification, replacing the fixed 13-slot state vector with\nfirst-class, extensible state variables and adding the missing\n(srfi 166 base) library.\n\nCore (lib/srfi/166/base.sld):\n- fn and with are now macros (fn binds state variables into a lexical\n  environment; with dynamically binds them and restores only the bound\n  variables, so col/row output position survives the form) (#2054, #2056)\n- add an output state variable slot; displayed returns a formatter\n  argument as-is instead of rendering it as #<procedure> (#2054, #2063)\n- numeric honours radix with precision, sign-rule, comma-rule,\n  comma-sep and decimal-sep, and consults their state-variable defaults;\n  numeric/comma inserts separators; numeric/si honours base/separator\n  and sub-unit prefixes (#2061)\n- escaped no longer adds delimiters, honours esc-ch (#f doubles the\n  quote) and renamer; maybe-escaped quotes on an embedded quote/escape\n  (#2059)\n- tab-to does nothing on a tab stop and does not divide by zero on a\n  zero tab width (#2058)\n- padded/trimmed/fitted measure with string-width and honour the\n  ellipsis state variable (#2062)\n- written-shared/pretty-shared label non-cyclic sharing via a shared\n  structure walker (#2064)\n\nSub-libraries:\n- (srfi 166 pretty): pretty breaks lines at width, pretty-shared labels\n  sharing (#2064)\n- (srfi 166 columnar): columnar/tabular align and pad, wrapped honours\n  width and word-separator?, wrapped/char splits at width, justified\n  full-justifies, line-numbers streams, zero columns produce a blank\n  line (#2065)\n- (srfi 166 unicode): real terminal-width model (wide=2, combining=0,\n  ANSI=0) with substring-terminal-width returning substrings and\n  terminal-aware overriding string-width/substring/width (#2066)\n\nMissing names now exported (joined/dot, numeric/fitted, trimmed/lazy,\nmake-state-variable, writer, substring/width, substring/preserve,\ndecimal-align, word-separator?, ambiguous-is-wide?, pretty-with-color,\nstring-terminal-width/wide, substring-terminal-width/wide,\nsubstring-terminal-preserve) (#2067)\n\nSigned-off-by: Baiju Muthukadan <baiju@muthukadan.net>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Address SRFI 166 review findings\n\nFix the correctness and termination issues raised in review:\n\n- wrapped/char now consumes at least one character per line, so a width\n  smaller than a single character cannot loop (#2292 review)\n- columnar/tabular thread the string-width state variable into padding\n  and minimum-width measurement instead of measuring with string-length\n- columnar resolves real widths in (0,1) as a fraction of the available\n  width instead of treating them as unspecified\n- justified subtracts the mandatory single space per gap from the\n  padding budget, so lines land exactly on the requested width\n- line-numbers formats in the current radix and leaves width/alignment\n  to columnar instead of baking in a five-column pad\n- from-file closes its input port on every exit path via\n  call-with-input-file\n- pretty threads radix/precision through the flat and broken paths, and\n  leaves shared/cyclic data flat (with labels) rather than looping or\n  dropping labels\n- upcased/downcased run their formatters under the active state so\n  string-width and friends reach nested formatters\n- substring-terminal-preserve keeps Unicode bidi formatting characters\n- written keeps the readable radix when precision is also bound (the\n  spec applies precision only at radix 10)\n- import (scheme cxr) explicitly for the caddr accessor\n\nRow rendering now indexes into vectors instead of walking line lists on\nevery row.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Address follow-up SRFI 166 review findings\n\n- columnar/tabular render each column formatter under its resolved\n  width (binding the width state variable), so a wrapped column wraps\n  at the column width rather than the default\n- upcased/downcased case-convert segment-by-segment, leaving ANSI\n  control sequences (whose letters are case-sensitive) untouched\n- pretty breaks an acyclic shared datum (which carries no datum labels\n  under plain pretty) instead of flattening it as one overflowing line\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n---------\n\nSigned-off-by: Baiju Muthukadan <baiju@muthukadan.net>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>",
          "timestamp": "2026-08-24T06:57:37Z",
          "tree_id": "d887e546bfe56ed3efc55597d305ff97aaf2110b",
          "url": "https://github.com/kaappi/kaappi/commit/0154fe845c490109b217d3ec8ea1c8ec9aecc4cd"
        },
        "date": 1787556948656,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 2.495699,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.228775,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.337206,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 1.807843,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.003684,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.030271,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.182768,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.033869,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 1.739274,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.720747,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.085546,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.197133,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.074789,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.710147,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.030517,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "e96c185c7d71e0ec38d8bb198cb8f43bc45b7afa",
          "message": "Make equal? recurse into record fields (structural record equality) (#2295)\n\n* Make equal? recurse into record fields (structural record equality)\n\nR7RS §6.1 leaves records in the \"all other cases\" clause for equal?,\nso the result is implementation-defined. Kaappi compared record\ninstances by identity only, which made it the lone holdout among\nnative-R7RS implementations: Gambit, Guile, and Chibi all recurse into\nfields, and the report's own (non-normative) \"print the same\" rule of\nthumb points the same way.\n\ndeepEqualWithVisited now has a record_instance arm: two instances are\nequal? only when they share the same record type (compared by identity,\nso a type that crossed an SRFI-18 thread boundary still matches,\nkaappi#1932) and their fields are pairwise deep-equal?. Records route\nthrough the same VisitedMap as pairs and vectors, so cyclic records\nterminate. eq?/eqv? stay identity-based, as §6.1 requires.\n\n- distinct-but-equal records => #t; different types or differing fields\n  => #f; nested and procedure-bearing fields recurse correctly\n- Zig unit tests in src/tests_records.zig and a Scheme smoke test under\n  tests/scheme/smoke/record-equal-2293.scm\n- CONFORMANCE.md SRFI 9 section records the decision and its §6.1 basis\n\nFixes #2293\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Update SRFI 9 test: equal? on records is now structural\n\nThe record arm in equal? makes two distinct instances of the same type\nwith equal fields compare #t, so the srfi9 equivalence block no longer\nholds for equal?. Keep the identity assertions for eqv?/eq?; assert\nequal? returns #t for the distinct-but-equal pair.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Hash records structurally, matching the new structural equal?\n\nMaking equal? recurse into record fields (kaappi#2293) broke the\nhash/equality contract: deepEqual became structural while valueHash\nstill hashed records by address, so a default SRFI 69 table\n(equal? + valueHash) silently lost every record entry once the table\ngrew past a tiny mask. Same bug class as the f64vector fix in #2023.\n\nAdd a record_instance arm to valueHashDepth that folds the record\ntype's identity (the discriminator sameRecordType gates on — a type\nthat crossed an SRFI-18 thread boundary keeps its identity at a new\naddress) with the first few field hashes, capped like the vector arm.\nCyclic fields are absorbed by the MAX_HASH_DEPTH sentinel. Flip the\nnow-stale identity-fallback comment.\n\nAlso pin that member/assoc find records structurally (they share the\ndeepEqual path), and that equal records hash alike.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n---------\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>",
          "timestamp": "2026-08-24T14:47:25+05:30",
          "tree_id": "147027ee7c2dded320eb6f7551a668b6f9b9a857",
          "url": "https://github.com/kaappi/kaappi/commit/e96c185c7d71e0ec38d8bb198cb8f43bc45b7afa"
        },
        "date": 1787565380893,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.364214,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.49406,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.561623,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.044966,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004945,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.048175,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.308476,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.056164,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.781897,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.22622,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.685079,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.279384,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.819363,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.440785,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043887,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "57c686979558025883b31cfc757ff035a25170ec",
          "message": "Fix LSP protocol/lifecycle and diagnostics drift (#2297)\n\n* Fix LSP protocol/lifecycle and diagnostics drift\n\nThe language server diverged from `kaappi check` on diagnostic values and\nbroke the LSP protocol in six independent ways, both surfaced by the\nPhase 6D audit. The two surfaces now share the analysis, not just the\nserializer, so they can no longer drift.\n\nProtocol and lifecycle (kaappi#1980):\n- a request with unusable params answers -32602 InvalidParams instead of\n  going silent and stranding the client on that id\n- a malformed/missing/zero Content-Length header no longer ends the whole\n  session; the frame is skipped and the next one resynchronised\n- shutdown before initialize errors -32002, and requests after shutdown\n  error -32600\n- exit without a prior shutdown exits with status 1\n- lineColToOffset clamps to the end of the requested line, not the end of\n  the document, so a column past end-of-line no longer resolves a symbol on\n  a later line\n- a null/float request id answers an Invalid Request with id null rather\n  than a fabricated id 0\n\nDiagnostics (kaappi#1981):\n- runDiagnostics drives the exact `kaappi check` analysis\n  (src/check.zig `analyzeSource`, extracted for this), so a whole-file read\n  error is reported, every failing form and every KP4xxx lint reaches the\n  editor, and ranges carry the real span instead of a whole-line 0..999\n  sentinel\n\nThe LSP driver (tests/scheme/lsp/lsp.sh) enables all previously disabled\n#1980/#1981 assertions and keeps a control beside each, and\ndocs/dev/diagnostics-json.md now notes the `check --diagnostics=json`\nstdout exception and the shared analysis.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Fix unbounded LSP diagnostic serialization and review nits\n\nThe fixed 1024-byte serializer in runDiagnostics silently dropped any\nfinding whose message exceeded the buffer — a legal ~1000-char identifier\nmakes KP4001 embed it verbatim — and, with two findings, left a `[,`/`,]`\nthat corrupted the publishDiagnostics array. Serialize through an\nallocating writer (the same shape check.zig's reportJson uses) and gate\nthe comma separator on the buffer rather than the index, so a finding that\nfails to serialize can never corrupt the array.\n\nAlso:\n- fold the finding sort into analyzeSource so no caller can forget it\n- unify the -32600 message on \"Invalid Request\"\n- don't fabricate id 0 for an initialize sent as a notification\n- soften the header-resync comment to \"best-effort\"\n- document that `kaappi check` adds severity-2 warnings (KP4001)\n\ntests/scheme/lsp/lsp.sh gains a long-message regression asserting both\nKP4001 findings are published and the diagnostics array is not corrupted.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Append the diagnostics comma only after a finding serializes\n\nReorder the separator so it is emitted after the finding has been written\nsuccessfully, not before. This closes the OOM-only `,]` path where the last\nfinding's serialization failed after its comma was already appended,\nleaving a trailing comma in the array. The comment now describes the\nguarantee accurately.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n---------\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>",
          "timestamp": "2026-08-24T21:22:47+05:30",
          "tree_id": "5397629a48465bae234b549d31eef7361aaa47a3",
          "url": "https://github.com/kaappi/kaappi/commit/57c686979558025883b31cfc757ff035a25170ec"
        },
        "date": 1787589562039,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.287452,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.168489,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.60036,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.991633,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004785,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.048399,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.306413,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.055965,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.858768,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.211235,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.683316,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.287453,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.801086,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.676227,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.046093,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "4634030c01f3903305f79eedfeecd1f0bbd59cbe",
          "message": "Fix WASM file-backed .sld loading and command-line/lib-path setup (Fixes #2108, #2109) (#2298)\n\n* Fix WASM file-backed .sld loading and command-line/lib-path setup (Fixes #2108, #2109)\n\nTwo independent wasm32 tier divergences from the audit v2 Phase 4D sweep, fixed together:\n\n#2108: platform.openRead had no WASI branch, so resolveLibraryPath's\nexistence probe failed for every candidate path and no file-backed .sld\nwas importable on wasm32 even when the host mounted the directory. Give\nopenRead the same preopened-dir (fd 3) path_open branch that\nfile_utils.readWholeFile already uses.\n\n#2109: main.zig's WASM entry returned before vm.command_line_args and\nvm.lib_paths were populated, so (command-line) returned '() and a .sld\nbeside the program was invisible. Repopulate both from the WASI argv the\nbranch already iterates.\n\nAdd tests/wasm/library-load.scm and tests/wasm/command-line.scm (wired\ninto CI) as regression tests, and remove the two run-wasm-differential.sh\nKNOWN_DIFFS entries now that the tiers agree again.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Propagate WASI arg-append failure; fix stale KNOWN_DIFFS description\n\nCodeRabbit review: cmd_args.append used \"catch return\", which exits 0 when\nargument setup runs out of memory and the script never runs. Use \"try\" so\nthe error reaches mainInner's exit-1 path.\n\ntests/scheme/CLAUDE.md still described large-index-bounds-1912.scm as a\nKNOWN_DIFFS probe after its entry was deleted when #1912 was fixed; split\nthe description so only deep-nesting-print.scm is a known divergence.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n---------\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>",
          "timestamp": "2026-08-24T23:21:09+05:30",
          "tree_id": "faa167818a75a1c7e25662ba842f34850a4053da",
          "url": "https://github.com/kaappi/kaappi/commit/4634030c01f3903305f79eedfeecd1f0bbd59cbe"
        },
        "date": 1787596084107,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 2.665165,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 5.007186,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.355614,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 1.854209,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.003659,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.030125,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.192585,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.034281,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 1.73562,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.771651,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.012254,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.192073,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.09946,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.755532,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.029723,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "998e4af3846cac15dd788f909866ddec4eff69b5",
          "message": "Ignore .zig-global-cache directory (#2299)\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>",
          "timestamp": "2026-08-24T23:29:58+05:30",
          "tree_id": "38fe816c2b1d720b6625b043dacdcc2578326910",
          "url": "https://github.com/kaappi/kaappi/commit/998e4af3846cac15dd788f909866ddec4eff69b5"
        },
        "date": 1787598696857,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.094888,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.35969,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.55422,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.851913,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004854,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.04654,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.27992,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.05402,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.43181,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.151616,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.600708,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.304828,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.699317,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.80735,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.046402,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "cb00facfce05b3080b4936dd0c6b83fcf53d6a6e",
          "message": "Rewrite SRFI 28 format to walk the format string linearly (#2300)\n\nformat walked the format string with a string-ref index loop. Kaappi\nstores strings as UTF-8 and indexes by codepoint, so string-ref s i is\nO(i), making format O(n^2) in the format-string length -- a 200 KB\nformat string took ~36 seconds.\n\nRead characters from an open-input-string port instead, which advances\nthrough the bytes once (O(n)). Every directive (~a, ~s, ~%, ~~, unknown\n~x pass-through, and a trailing lone ~) is preserved byte-for-byte;\nverified identical output against the previous implementation.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-08-25T06:02:33+05:30",
          "tree_id": "f4bcc8cc3a8f94df798fbeff2fa1a1991c5ba79a",
          "url": "https://github.com/kaappi/kaappi/commit/cb00facfce05b3080b4936dd0c6b83fcf53d6a6e"
        },
        "date": 1787620846763,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.076635,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.305994,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.548375,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.846182,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004877,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046552,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.279993,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.053877,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.45428,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.150014,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.606064,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.304087,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.703635,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.792206,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045498,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "8e378e1c4c4790a5bdaef7d5948e861d99ac3091",
          "message": "Bound default-hash recursion depth in SRFI 128 (#2301)\n\ndefault-hash recursed over pairs/vectors with no depth limit. Since #2044\nthreaded the comparator through (srfi 146 hash), a make-default-comparator\nhashmap keys its table via default-hash, so a cyclic key ran the recursion\ninto the KP3008 stack cap — an uncatchable process abort (regressed from the\nnative equal? hash, whose MAX_HASH_DEPTH=8 cap silently absorbed the cycle).\n\nThread a depth argument through the pair/vector recursion and, past a cutoff\nmirroring the native precedent (MAX_HASH_DEPTH=8, a fixed DEEP_CUTOFF_HASH),\nfold in a constant sentinel instead of recursing. The cutoff is a fixed\nconstant, never derived from the object, so two equal? keys still hash alike;\nacyclic values nesting less than the cutoff deep hash exactly as before.\n\nCyclic keys remain \"an error\" under the spec, but the failure mode is now a\nbounded, terminating hash instead of a process abort.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-08-25T06:03:08+05:30",
          "tree_id": "a98489401bf36daf262b262d1651cd11811b6afb",
          "url": "https://github.com/kaappi/kaappi/commit/8e378e1c4c4790a5bdaef7d5948e861d99ac3091"
        },
        "date": 1787626540466,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 2.647623,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.896179,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.360355,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 1.852499,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.003595,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.030829,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.192983,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.034853,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 1.710985,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.786682,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.032593,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.209593,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.138852,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.769389,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.031605,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "4f2d84c8cabf9598e209f5781923875a76c62209",
          "message": "Subtract custom-port read-ahead from port-position (#2302)\n\nportPositionFromCustomPort returned get-position verbatim, but a custom\nport holds its own unconsumed lookahead: the tail of the last read!\nburst (read_buf), a pushed-back peek_byte, and peek_extra. get-position\nreports the SOURCE position; port-position must report the PORT\nposition. So after a burst read! that fetched several bytes, or after\nany peek, port-position over-reported.\n\nApply the same ahead/behind adjustment the fd-backed branch already uses\nin portPosition: subtract unconsumed read-ahead, add pending write\nbuffer. This also satisfies SRFI 181's requirement that port-position\ncalled before a peeked element is read return the cached pre-peek\nposition.\n\nCloses #1996\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-08-25T06:03:30+05:30",
          "tree_id": "5418e5704892097b6b8eb4045af57eb3ae2b7d05",
          "url": "https://github.com/kaappi/kaappi/commit/4f2d84c8cabf9598e209f5781923875a76c62209"
        },
        "date": 1787626671640,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.301015,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.485871,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.576034,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.007444,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004674,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.048677,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.309503,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.056189,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.809486,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.218662,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.672261,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.283357,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.786327,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.673879,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045037,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "dc08a626c96adebd8088bfb551701bd19e0a5bb9",
          "message": "Dedup reactor ceil-to-ms rule: Windows backend calls msFromNs (#2304)\n\nThe nanoseconds-to-milliseconds ceil was written twice by hand in\nreactor.zig. Only the epoll copy (msFromNs) was named, reachable from a\ntest, and compiled on every target; the Windows backend restated the same\narithmetic inline, with a comment citing msFromNs as the authority.\n\nHave WindowsEventBackend.wait call msFromNs and translate its i32/-1\nconvention to the Windows u32/INFINITE one at the call site (-1 becomes\nINFINITE; a positive result is clamped to INFINITE-1). msFromNs was\nalready at platform-neutral file scope, so no move was needed. Behavior\nis unchanged on every reachable input.\n\nAdd an exact-mapping unit test pinning the rows from the issue table\n(null, 0, 1 ns, 1 ms, 1.5 ms ceil, u64 max clamp) so the shared rule is\nasserted directly. Cross-compiled for x86_64-windows to exercise the\ngated branch.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-08-25T06:04:21+05:30",
          "tree_id": "e1439580e5d450603600818fd35306c1c2a38440",
          "url": "https://github.com/kaappi/kaappi/commit/dc08a626c96adebd8088bfb551701bd19e0a5bb9"
        },
        "date": 1787626685431,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.089154,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 5.257068,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.422093,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.276447,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004194,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.037946,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.22922,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.040169,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.09353,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.943138,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.257552,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.221125,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.331013,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.698166,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.035408,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "6c31408d522321a1ba737e0a4bad27171289142d",
          "message": "Route top-level import through load's evaluator and attribute errors to the loaded file (#2303)\n\nload compiled each form of the loaded file as an ordinary expression, so a\ntop-level (import ...) was evaluated as an application: (scheme base) was\napplied and base looked up as a variable, failing with KP3001. The error\nwas also attributed to the loader's file and line, because the loaded thunk\ncarried no source name of its own.\n\nRoute each form (default global-env case) through vm.handleTopLevelForm\nfirst — the same dispatch a script or the REPL uses — so import,\ndefine-library, begin, cond-expand and the rest are handled by the\nimport/library machinery, and fall through to compilation only for plain\nexpressions. Compile those with compileExpressionWithMacrosAt, naming the\nreader and thunk with the loaded file's path so captureErrorLocation\nattributes any raised diagnostic to the loaded file:line, and run via\nrunTopLevelFunction so a load nested under a suspended caller frame stays\nre-entrant.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-08-25T06:03:55+05:30",
          "tree_id": "515b23b929b4f678702e7f272e47ffbc182f00a4",
          "url": "https://github.com/kaappi/kaappi/commit/6c31408d522321a1ba737e0a4bad27171289142d"
        },
        "date": 1787626707623,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.091945,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.477698,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.578019,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.911838,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00524,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046923,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.283117,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.053559,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.40551,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.157797,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.627662,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.3067,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.716921,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.87317,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.046505,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "59aa54f881f4ce3fad0c6b8c3b046069e6727a88",
          "message": "Deduplicate GC remembered set to keep minor collections linear (#2305)\n\nGC.writeBarrier appended a mutated old-gen container to remembered_set on\nevery write with no membership check, so a container mutated n times queued\nup to n identical entries. The minor mark phase then marked each entry, and\nmarking a large container is O(capacity) -- making a fill quadratic in\nwrites. hash-table-set! fires the barrier twice per insert, so filling one\n150k-entry table queued ~300k entries and stalled for seconds in the mark\nphase.\n\nAdd an in_remembered_set flag bit (from Object.Flags spare padding) set when\na self-owned container is appended and cleared when it leaves the set\n(pruneRememberedSet drops it, or a full collect drains it). The barrier stays\nO(1) and the minor mark phase becomes O(distinct containers) instead of\nO(writes). Foreign containers (cross-thread shared mutation, #1924) keep the\npre-existing unconditional append so their owning GC's flag is never touched.\n\nFilling a 150k-entry hash table now scales linearly (~180ms, no multi-second\nspikes) instead of exhibiting per-size cliffs.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-08-25T06:04:37+05:30",
          "tree_id": "20efcac84cab39416dd96b2ce00103f72d011f64",
          "url": "https://github.com/kaappi/kaappi/commit/59aa54f881f4ce3fad0c6b8c3b046069e6727a88"
        },
        "date": 1787627710225,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.337201,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.273616,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.562667,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.018906,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004708,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.047771,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.309231,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.054788,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.879777,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.201783,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.649694,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.27979,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.788581,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.619453,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045457,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "bb1082a7d9c5ec33728c7eefc4fd04a63f415969",
          "message": "Make char-numeric? cover all Unicode Nd digits (#2306)\n\nisUnicodeNumeric used a hand-written list of 36 BMP \"digit zero\" bases,\nmissing all 310 supplementary-plane Nd (decimal digit) code points across\n27 ranges — so char-numeric? answered #f for e.g. U+1D7CE MATHEMATICAL\nBOLD DIGIT ZERO and U+104A0 OSMANYA DIGIT ZERO, disagreeing with the\ntable-driven neighbours and with SRFI 14's char-set:digit.\n\nAdd a numeric_ranges table (General_Category=Nd, all planes) to the\ngenerated unicode_tables.zig via gen_unicode_tables.py, and have both\nchar-numeric? and digit-value consult it. digit-value is kept in lockstep\nbecause R7RS requires it to return a value for every char char-numeric?\nreports as #t; each Nd range is a contiguous 0..9 run, so the value is the\noffset from the range base.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-08-25T06:05:03+05:30",
          "tree_id": "7af4493280e72b83c9bd896a9538c19d6a01534d",
          "url": "https://github.com/kaappi/kaappi/commit/bb1082a7d9c5ec33728c7eefc4fd04a63f415969"
        },
        "date": 1787628239668,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.05734,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.69631,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.548432,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.86433,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004939,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046576,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.28301,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.053427,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.370435,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.15188,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.592445,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.3025,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.687081,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.77297,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.04561,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "3c11014dfcee10ec9a9aca47082587ddf5d3a64d",
          "message": "Validate SRFI 231 entry-point arguments to match the reference (#2319)\n\nSix reference-parity guard clauses, one per filed issue, each with a\nguarded regression test in its per-module suite:\n\n- interval-contains-multi-index?: a multi-index whose length differs\n  from the interval's dimension is now an error, not a silent #f (#2312)\n- storage-class-data->body: built-in classes reject wrong-typed data\n  instead of returning it as a would-be body via identity (#2313)\n- make-array: setter must be a procedure or #f, checked at construction\n  so mutable-array?/array-setter cannot misreport the object (#2315)\n- make-specialized-array, make-specialized-array-from-data, and the two\n  specialized-array-default-* parameters reject non-boolean\n  safe?/mutable? values (#2316)\n- specialized-array-share: mapper must be a procedure, checked even for\n  empty new-domains where it would never be invoked (#2317)\n- array-tile: a scalar slice-width is legal only on a positive-width\n  axis; empty axes take the explicit-vector form (#2318)\n\nVerified by running the reference test suite's 330 error-expectation\ntests against kaappi: 322 passed before, 330 after. All seven\ntests/scheme/srfi/srfi231-*.scm suites pass. #2314 (array-packed?\nzero-offset) is deliberately excluded -- it is a semantic change that\nbelongs to its own PR.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>",
          "timestamp": "2026-08-25T04:32:21Z",
          "tree_id": "e70fd8acd704dbb6d551d8b9305bb6f56f9a3617",
          "url": "https://github.com/kaappi/kaappi/commit/3c11014dfcee10ec9a9aca47082587ddf5d3a64d"
        },
        "date": 1787634718686,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.640692,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.272237,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.566639,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.10622,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004635,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.048042,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.307178,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.055846,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.681526,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.218396,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.683842,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.281962,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.802022,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.632075,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044234,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "dbc3bfdc868af73a16d028b4a49d73bbc305eab6",
          "message": "Fix array-packed?: consecutive increasing indices from any body base (#2322)\n\nThe spec defines array-packed? as #t when the elements, in lexicographic\norder, are stored in the body with increasing and consecutive indices --\nthe first visited index may have ANY base. The port demanded a zero base,\nso every non-zero-offset view (array-extract being the common case)\nwrongly reported #f; the reference checks only stride-1 between\nlexicographic neighbors and treats length-1 axes as trivially packed.\n\nConsequence beyond the predicate: specialized-array-reshape's fast path\nalready computed its base from the first indexer value, so offset views\nnow reshape in place, sharing the body like the reference, instead of\nerroring or copying.\n\nTests: packed-on/offset extract/translate/reverse/sample/empty cases\n(views suite, which owns the view constructors), plus an in-place\nreshape write-through proof. Docs: the reshape simplification note in\nsrfi-implementation-notes.md now records the corrected packed semantics.\n\nVerified: all seven tests/scheme/srfi/srfi231-*.scm suites pass, the\nspec document's own worked examples still pass (66 automated checks),\nand the reference test suite's 330 error-expectation tests stay 330/330.\n\nCloses #2314\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>",
          "timestamp": "2026-08-25T05:50:04Z",
          "tree_id": "804f1d6cf7dd584858f897e8233babbd866f7437",
          "url": "https://github.com/kaappi/kaappi/commit/dbc3bfdc868af73a16d028b4a49d73bbc305eab6"
        },
        "date": 1787640782189,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.346118,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.595758,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.580975,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.002882,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.005295,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.048486,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.30936,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.056306,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.721023,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.216163,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.682364,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.28603,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.806964,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.671263,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045155,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "1114b38004df526381db951b49ed7510e5342f45",
          "message": "Validate array-copy options and combinator function arguments (#2326)\n\nTwo reference-parity guard sets completing the SRFI 231 validation\nwork, both reported by the SRFI's author:\n\n- array-copy/array-copy! validate their own mutable?/safe? options\n  (#2320): mutable? never flows through a validating constructor, so a\n  truthy wrong-typed value silently produced an unfrozen array, and\n  safe? errors were attributed to the inner constructor. %check-boolean!\n  moves to arrays.sld's internal helper exports for views.sld to reuse.\n- array-map, array-for-each, array-fold-left/right, array-any,\n  array-every, array-outer-product, and array-inner-product (f and g)\n  reject non-procedure function arguments at call time (#2321); the\n  lazy combinators previously deferred the failure to first element\n  access, and eager ones succeeded silently over empty domains where f\n  is never invoked. array-reduce already checked.\n\nVerified: all seven tests/scheme/srfi/srfi231-*.scm suites pass, the\nspec document's worked-example corpus still passes, and the reference\ntest suite's 330 error-expectation tests stay 330/330.\n\nCloses #2320\nCloses #2321\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>",
          "timestamp": "2026-08-25T07:04:23Z",
          "tree_id": "0a80b478bfcc54f58b83555f3a1bc3ca4a96d2f7",
          "url": "https://github.com/kaappi/kaappi/commit/1114b38004df526381db951b49ed7510e5342f45"
        },
        "date": 1787643768212,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.095486,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.00332,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.558496,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.869033,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004882,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046354,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.285346,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.053764,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.363816,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.150976,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.637518,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.303581,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.694811,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.79004,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.046079,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "63b5002647ab1a9e289dece975ad2594d43ff92e",
          "message": "Correct SRFI 260 rationale: generated symbols intern deliberately (#2308)\n\nThe SRFI 260 header and srfi-implementation-notes.md both claimed Kaappi\nhas no uninterned symbols, so write/read invariance falls out for free.\nThat is false: SRFI 258 shipped uninterned symbols 51 minutes later\n(GC.allocUninternedSymbol). generate-symbol's invariance is a deliberate\nchoice — it interns via GC.allocSymbol — not the absence of an\nalternative. State the real reason and warn against 'simplifying' onto\nthe uninterned allocator, which would break eq? round-trip.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-08-25T14:55:31+05:30",
          "tree_id": "93029e0943ae0da60f4a432725ba8a1c5b776b06",
          "url": "https://github.com/kaappi/kaappi/commit/63b5002647ab1a9e289dece975ad2594d43ff92e"
        },
        "date": 1787653809588,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.370604,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.349241,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.573555,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.018092,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004705,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.04874,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.322164,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.056469,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.686293,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.214878,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.690907,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.281532,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.811835,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.604161,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044768,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "6f9e508b70e1747f251e0d45939c41c27e590c35",
          "message": "Preserve local-macro forms in expand so the dump round-trips (#2327)\n\nkaappi expand claimed a round-trip guarantee (feeding its output back\npreserves behavior) but broke it for let-syntax/letrec-syntax. It expanded\nthe body against the global macro set, resolving a use of a locally-bound\nkeyword against the OUTER binding, then re-emitted the inner binding it\nnever applied — so a shadowed (let-syntax ((c ...)) (c)) dumped as the outer\nc's expansion and round-tripped to a different answer.\n\nLeave let-syntax/letrec-syntax entirely unexpanded (the local transformers\nare never built in the expand path); the compiler builds them on a real run,\nand re-reading re-establishes the inner binding. Round-trip fidelity of the\nbinder's spelling also requires that a macro-generated define-syntax (a SRFI\n139 syntax parameter) be registered, so registerEnvForExpand now runs on the\nEXPANDED form rather than the original.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-08-25T16:00:20+05:30",
          "tree_id": "7877b9490319c5d5e8f03ca28c740dd37be97291",
          "url": "https://github.com/kaappi/kaappi/commit/6f9e508b70e1747f251e0d45939c41c27e590c35"
        },
        "date": 1787663843645,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.034574,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.746393,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.552942,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.770217,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00498,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046476,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.283332,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.054145,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.906735,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.150966,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.517665,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.258228,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.786022,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.9096,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.041367,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "c1b2abdff2e7f065ad96f7625cf4d311b5c39747",
          "message": "Track macro-expanded set! of a primitive at native top level (#2325)\n\nkaappi compile tracks top-level rebindings so folding does not inline a\nprimitive whose name will be reassigned (#822), but collectRedefinedNames\nmatched only a literal define/set!/begin head. A top-level macro use that\nexpands to (set! + -) matched none, so a later (+ ...) folded against the\nstale primitive and the native binary printed 7 where the interpreter\nprinted 3.\n\nAdd collectRedefinedNamesMacroAware: in the native read loop, expand a\nhead-position syntax-rules macro (bounded depth, no_collect-guarded,\nprocedural SRFI-211 transformers excluded) and scan its expansion for the\ndefine/set! targets it introduces, recording them stripped of any hygiene\nprefix. llvm_emit's inline-primitive dispatch now also consults the\nwhole-program set_targets map (isReboundGlobal), matching how IR.isRedefined\nalready gates constant folding.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-08-25T16:00:31+05:30",
          "tree_id": "1abdfb552e9620dfedebd8d66b6f53132f558e3e",
          "url": "https://github.com/kaappi/kaappi/commit/c1b2abdff2e7f065ad96f7625cf4d311b5c39747"
        },
        "date": 1787664059247,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.388944,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.680808,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.578412,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.046947,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004708,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.047932,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.309888,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.055615,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.839688,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.21687,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.658667,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.280371,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.801807,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.660702,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045166,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "aaa44b01a6afe8a815c9841ebb7947eac56261b8",
          "message": "Reclaim descriptors on EMFILE before failing an open (#2324)\n\nopen-input-file, open-output-file and open-directory raised as soon as\nthe OS reported EMFILE/ENFILE, even though the fd-holding ports and\ndirectory streams were unreachable and reclaimable. A legal program that\nabandons fd-holders faster than the GC allocation-count threshold trips\nthen failed at a normal ulimit -n and succeeded at a larger one.\n\nAdd platform.OpenError.FdExhausted to single out EMFILE/ENFILE, and force\na full collection (GC.collectFull) and retry the open once before raising.\nOnly FdExhausted triggers the retry; every other errno still raises the\ncorrect file error immediately.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-08-25T16:00:35+05:30",
          "tree_id": "74057000d9e340a85949c05d64f77fd21a6ca9db",
          "url": "https://github.com/kaappi/kaappi/commit/aaa44b01a6afe8a815c9841ebb7947eac56261b8"
        },
        "date": 1787664076306,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.335448,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.259879,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.566094,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.018597,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004699,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.048424,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.309711,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.055996,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.746742,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.219847,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.707137,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.275053,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.809494,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.602399,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044431,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "1f25ba20352041584c556310d60af966284a5dfb",
          "message": "Let --lib-path shadow a bundled (srfi N) (#2323)\n\nresolveLibraryPath probed the cwd-relative \"\" and \"lib/\" prefixes before any\n--lib-path entry, so a bundled library under ./lib silently beat a --lib-path\ndir meant to override it. That made A/B comparisons of two implementations of\nthe same SRFI vacuous: the bundled copy was measured while the run looked like\nit used the shadow. Both `kaappi --help` and CLAUDE.md document --lib-path as\ntaking precedence (auto-added dirs come after it), so search every lib_paths\nentry before the cwd fallbacks. findBundledSource is reordered to match its\n\"same search order\" contract.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-08-25T16:00:39+05:30",
          "tree_id": "56143b3475b956b8f931fca125ebb609cf8684d3",
          "url": "https://github.com/kaappi/kaappi/commit/1f25ba20352041584c556310d60af966284a5dfb"
        },
        "date": 1787664299030,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.341604,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.597664,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.595669,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.049427,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.005368,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.048733,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.309855,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.056107,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.760444,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.208382,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.702729,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.287283,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.82852,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.715114,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045704,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "423ef45efb386a4409e1df96042542226e88b1e3",
          "message": "Compile top-level define-values in program order, not the preamble (#2311)\n\nThe --compile path recorded every top-level form handleTopLevelForm claims\ninto the .sbc preamble, which the artifact replays before any compiled form.\nHoisting is correct for the five isEnvSetup() declarations, but define-values\nis ordinary program code whose producer can depend on an earlier top-level\nform, so replaying it first reorders execution and fails where the interpreter\nsucceeds (e.g. (define x 1)(define-values (a b)(values x 2)) errored with\nundefined variable 'x').\n\nRestrict preamble hoisting to isEnvSetup() heads; let define-values fall\nthrough to ordinary compilation via its existing compilable lowering\n(compileDefineValues), so it keeps its position in the compiled stream. Its\nproducer is still not executed at compile time.\n\nAdd a compile/*.sh regression test (native/artifact tier) asserting the bundled\nbinary prints (1 2) and exits 0, plus an env-setup control that stays hoisted.\nUpdate docs/dev/cache.md, which had documented #2200 as an open limitation.\n\nCloses #2200\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-08-25T16:00:42+05:30",
          "tree_id": "1f75b9ca3cd37ff7440d41b506beaa4d639ab95d",
          "url": "https://github.com/kaappi/kaappi/commit/423ef45efb386a4409e1df96042542226e88b1e3"
        },
        "date": 1787665449149,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.546985,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.379885,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.492583,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.563833,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004794,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.04319,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.274752,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.046542,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.459056,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.128313,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.412791,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.261063,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.553349,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.959058,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.039861,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "7a82c59384a4391cd8d03def81843a4b20dfa213",
          "message": "Correct fuzz.yml gc-stress timeout and stale wall-time comment (#2307)\n\n* Correct fuzz.yml gc-stress timeout and stale wall-time comment\n\nThe gc-stress legs budgeted timeout: 300 minutes on the strength of a\ncomment claiming the pre-fuzz unit phase takes ~35 min locally and to\nbudget more on a hosted runner. Measured whole-leg wall time (checkout,\nZig install, build, full unit suite, and the bounded fuzz runs) is\n10-13 min on the hosted runner (#2164) — the ~35 min figure predates\n#1802/#1804/#1809, when ReleaseSafe stopped 0xAA-filling '= undefined'\nbuffers. A 300-minute budget is a five-hour non-bound: a livelocked\ncollector would sit for hours before the runner killed it. Lower both\nlegs to 45 min (generous headroom over 10-13 min without being absurd)\nand rewrite the comment to cite the real measurement. Run counts\nunchanged.\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Set gc-stress timeout to 60 min over the 11-40 min observed range\n\nIssue #2164 measured the whole gc-stress leg at 10-13 min (Aug 1, 2026),\nbut the Aug 11-25 runs measure 11-40 min per leg (median ~20, worst 40.2\non Aug 20) as the suite and corpus grow. 45 min left only ~12% headroom\nover the worst observed leg; 60 restores ~50% while still cutting a\nlivelocked collector from 5 h to 1 h. Comment now cites both ranges.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n---------\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-08-25T16:00:54+05:30",
          "tree_id": "3683cfbab138feb618e446a4c353e4c5cde86aa8",
          "url": "https://github.com/kaappi/kaappi/commit/7a82c59384a4391cd8d03def81843a4b20dfa213"
        },
        "date": 1787665616990,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.333128,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.002368,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.601614,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.114036,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004801,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.048231,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.309203,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.055504,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.725545,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.22227,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.687065,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.287048,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.82399,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.695063,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045137,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "dffd8510c5f2c3d0cc156aba75d5576d5e934a39",
          "message": "Render offending value's identity in type errors (#1899) (#2310)\n\n* Render offending value's identity in type errors (#1899)\n\nprimitives.safeValueDescription printed symbol, string, vector, bytevector,\nrational and bignum as opaque #<tag>s, and characters (immediates) as #<char>\n-- dropping the one thing a type-error message needs: which value was wrong.\nIt now renders identifying content: a symbol's name, a bounded quoted string\nprefix, a vector/bytevector length summary, a rational's num/den, a small\nbignum's value, and a character's #\\ form.\n\nThe \"safe\" properties are preserved: no allocation or VM callback (bignums\nbeyond u128 fall back to #<bignum> rather than allocate scratch to stringify),\nbounded output (fixed 128-byte writer, plus string/symbol truncation), and no\nrecursion into heap structure (compound types get a one-level summary, so a\ncyclic value cannot loop).\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Update the two docs that stated the old opaque-rendering contract\n\nadding-features.md:75 still told contributors safeValueDescription\n'deliberately does not dereference heap payloads' and renders every symbol\nas #<symbol> -- both false after this PR. audit-strategy.md's D3 dimension\ndescribed the opaque rendering as live; F10 (the dated 2026-07-31 findings\ntable) is kept as history per its own preamble, so it stays.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n---------\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-08-25T16:13:46+05:30",
          "tree_id": "b2465b34b1c31c86b0db41b838a9d5f424627170",
          "url": "https://github.com/kaappi/kaappi/commit/dffd8510c5f2c3d0cc156aba75d5576d5e934a39"
        },
        "date": 1787668952243,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.367815,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.447875,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.583743,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.980276,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004656,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.047678,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.3068,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.055789,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.817288,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.199194,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.655834,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.281,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.773599,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.637273,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044413,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "9bcc06ba9d5da64d0122f9b43331cd4a1cf64bbf",
          "message": "Reject subcommand-scoped CLI flags at global scope (#2330)\n\nThe global flag loop accepted --check and --no-opt in any position with no\nscope check. --no-opt was merely inert there, but --check is one hyphen-pair\nfrom the check subcommand whose contract is that nothing executes, so\n'kaappi --check foo.scm' silently RAN the file it meant only to analyse.\n\ncli.parse now tracks the active inline subcommand and rejects a top_level=false\nflag (usage error, exit 2) unless its owning subcommand word preceded it,\nnaming that subcommand and — for --check — pointing at the check subcommand as\nthe likely intent. The owner is derived data-driven from cli_spec's globalSubset\nmembership via owningSubcommand, and a comptime check pins every scoped flag to\nexactly one subcommand so the reject path always has an owner to name.\n'kaappi fmt --check' and 'kaappi ir --no-opt' keep working.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-08-25T18:24:51+05:30",
          "tree_id": "589a4b9c07043f8a6f8be4117b4dca9ea1bba201",
          "url": "https://github.com/kaappi/kaappi/commit/9bcc06ba9d5da64d0122f9b43331cd4a1cf64bbf"
        },
        "date": 1787669053992,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.355466,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.568191,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.592874,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.99887,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004783,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.047608,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.308154,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.055264,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.781497,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.233792,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.6381,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.284101,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.79564,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.667284,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.046423,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "45951828823b99a7f77cb12f358b98294ff8dfcf",
          "message": "Accept unresolvable SRFI 211 transformer-specs under kaappi check (#2329)\n\nkaappi check (and the LSP) run compile-only static analysis, executing\nnothing. Two valid SRFI 211 transformer-spec shapes could therefore not be\nresolved and were wrongly reported as KP2001 'invalid syntax' (exit 1) even\nthough the program compiles and runs: a runtime-bound Transformer used as a\nbare-symbol alias, and an er/lisp-macro-transformer expression that\nreferences a global bound only at run time. Since check never executes the\nearlier define, the globals lookup and the transformer-expr eval both come\nback empty and resolveTransformerSpecRec fell through to InvalidSyntax.\n\nUnder analysis (check_lint.active != null) accept these still-unresolvable\nspecs as a benign catch-all placeholder macro so the file is clean and later\nuses of the keyword compile too. A normal run is unaffected: the branch is\nonly reached when nothing has executed. Genuine invalid detection is kept\nintact: a non-symbol/non-pair literal, a bare alias to a bound\nnon-transformer value (e.g. a procedure), and a malformed-arity er-macro\nform are all still reported.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-08-25T18:33:23+05:30",
          "tree_id": "29113c9471816d347985304f8157aea2e66440a4",
          "url": "https://github.com/kaappi/kaappi/commit/45951828823b99a7f77cb12f358b98294ff8dfcf"
        },
        "date": 1787669071988,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.954536,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.265512,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.560124,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.833546,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004863,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046477,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.285731,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.053412,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.412739,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.137955,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.608903,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.30134,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.68079,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.791993,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045863,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "296c198166026a768feefd0e58c10e9b5f1ee5e7",
          "message": "Run top-level call/cc forms wholly in the VM natively (#2119) (#2332)\n\nA top-level form whose own evaluation captures a full continuation was\nlowered with its outer structure native and only the call/cc\nsubexpression eval-fallbacked to the VM. The captured continuation then\nspanned only that subexpression, so invoking it from a later top-level\nform (e.g. a for-each callback) re-ran just the subexpression and\ndelivered its value into a native context that had already completed and\ncould not re-run -- the enclosing set!/define store never fired again,\nsilently keeping the pre-capture value: (set! result (+ 100 (call/cc ...)))\nkept 100 where the interpreter gives 142.\n\nForce any top-level form that may capture a full continuation onto\nwhole-form VM evaluation (a single passthrough), so the captured\ncontinuation spans the entire form and a later resume re-runs its tail,\nmatching the pure-VM tier per the continuation-strategy doc's behavioral\nequivalence guarantee.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-08-25T18:50:04+05:30",
          "tree_id": "91f030418270f5c9f10b4959e047b88663f25b6a",
          "url": "https://github.com/kaappi/kaappi/commit/296c198166026a768feefd0e58c10e9b5f1ee5e7"
        },
        "date": 1787669709547,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.961877,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.827201,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.558015,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.836149,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004883,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046703,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.282416,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.053322,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.332261,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.127767,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.600052,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.300374,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.680094,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.792118,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.046174,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "7ecbdf3525fd1ed420979506407a2a673721d025",
          "message": "Make the untraced env-map invariant explicit and checkable (#2331)\n\nFunction.env and Transformer.def_env are raw *StringHashMap(Value) pointers\nthat no GC switch traces. They are safe only by an unwritten rule: the map\nis GC-reachable through its paired env_val/def_env_val, EXCEPT when it is one\nof the VM-rooted library registries markVmRoots traces (lib_env, retired_envs,\npending_lib_envs, current_lib_env), where the paired value may be NIL. A\nfuture call site handing a private map a NIL paired value would silently lose\nevery binding at the next collection, looking identical to the safe sites.\n\nDocument the invariant on both fields and make it checkable: a VM predicate\nisGcRootedEnvMap plus a globals.assertEnvMapInvariant that, in debug/test\nbuilds only, fires the moment a construction site violates it. Wired into the\none Function.env site (compileExpressionInEnv) and the three Transformer\ndef_env sites, reaching the VM through a registered callback so the compiler\nneed not import vm.zig (mirroring #1812's current_lib_name_lookup). Compiled\nout of release builds, so no shipped behavior or perf change.\n\nCloses #1962\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-08-25T18:58:27+05:30",
          "tree_id": "a15e861c18fe9d0f46020fe63a74c7fd24233d86",
          "url": "https://github.com/kaappi/kaappi/commit/7ecbdf3525fd1ed420979506407a2a673721d025"
        },
        "date": 1787670921721,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.046866,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.938692,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.432254,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.178391,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.003761,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.036436,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.219127,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.042144,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 1.852855,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.87251,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.225384,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.235038,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.299348,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.415922,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.036874,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "ad52ca4cd2ff221ef874285cc9640bc88726f8f5",
          "message": "Guard the WASM differential against a stale kaappi.wasm (#2328)\n\n* Guard the WASM differential against a stale kaappi.wasm\n\nrun-wasm-differential.sh only checked that a module existed, never that it\nwas built from the tree under test. run-all.sh has no `zig build wasm` step,\nso a local run compared today's interpreter against whatever module happened\nto sit in zig-out/ — producing confident, specific FALSE tier divergences\nagainst an old engine (or, silently, a clean PASS that tested nothing).\n\nAdd a freshness gate: if any interpreter source compiled into the module\n(src/, build.zig{,.zon}, vendor/) is newer than the module, SKIP (77) with a\nmessage to run 'zig build wasm' instead of reporting divergences against a\nmodule of unknown provenance. Only the binary's inputs are checked, so editing\na test or doc does not trip it. `find -newer` is plain POSIX. Also surface the\nmodule size in the preamble. Wire run-all.sh to build the module up front when\nzig and wasmtime are both present, so the common local path runs the leg\ninstead of skipping; it degrades to the SKIP when the toolchain is absent.\n\nCloses #2197\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Fail closed on WASM freshness scan and name the full input scope\n\nAddresses CodeRabbit review: exit 77 when the find scan itself cannot\nestablish freshness (instead of proceeding on an empty result), and report\nthat the module was verified newer than all interpreter build inputs\n(src/, build.zig{, .zon}, vendor/) rather than only src/.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n---------\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-08-25T19:26:18+05:30",
          "tree_id": "0cd3ad1159a4f60182c2309c2ef36df1826c92d6",
          "url": "https://github.com/kaappi/kaappi/commit/ad52ca4cd2ff221ef874285cc9640bc88726f8f5"
        },
        "date": 1787671427450,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.438491,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.511063,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.584076,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.107319,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004753,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.048232,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.30752,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057066,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.879507,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.241337,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.689383,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.284853,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.803737,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.648788,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044847,
            "unit": "seconds"
          }
        ]
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
          "id": "423efd2d5e5f281ce30c6e2f6179a68597f03f55",
          "message": "Release v0.24.0\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>",
          "timestamp": "2026-08-25T20:25:43+05:30",
          "tree_id": "b2b738088c2540e45a348b3655d8892f3f48d353",
          "url": "https://github.com/kaappi/kaappi/commit/423efd2d5e5f281ce30c6e2f6179a68597f03f55"
        },
        "date": 1787672736315,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.937508,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.954029,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.559796,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.843633,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004876,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046388,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.283552,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.053377,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.329622,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.129305,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.604143,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.300327,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.672506,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.765401,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045962,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "90c5bf90ae7c757c9f007648ce90189d27ef0769",
          "message": "Report call_cc/call_ec as medians and widen the PR-gate noise floor (#2334)\n\nThe PR benchmark gate presented run-to-run noise with the same confidence\nas real results, in two distinct ways.\n\ncall_cc and call_ec were emitted as single-shot measurements with a\nhardcoded \"min 0, max 0, iterations 1\", while every other row is a median\nover 5 runs with real dispersion. A ~45ms unrepeated sample on a shared\nrunner is one scheduling hiccup away from tripping the 1.20x threshold,\nturning an unrelated PR red. zig build bench now repeats the depth-0\nmeasurement 5 times and reports the median with real min/max/iterations,\nmatching benchmarks/common.scm; run-benchmarks.sh parses those fields\ninstead of hardcoding the single-shot marker (kaappi#2101).\n\nSeparately, the gate's own base-vs-base spread reaches ~1.62x for the same\ncommit on a shared runner, yet the threshold was 120% — so a red check sat\nwell inside the measured noise and meant nothing. Raise it to 175%: above\nthe noise floor, still catches a genuine >=2x regression (kaappi#1906).\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-08-25T23:31:13+05:30",
          "tree_id": "62a0a06e2ba53745c202e6991aefb5c60aea9d7e",
          "url": "https://github.com/kaappi/kaappi/commit/90c5bf90ae7c757c9f007648ce90189d27ef0769"
        },
        "date": 1787683408165,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.512192,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.892315,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.582851,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.174679,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004711,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.048361,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.314901,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.058776,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.885468,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.255253,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.706023,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.287624,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.835933,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.767203,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.049871,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "0f499465681c4c8e2a72f7f5ff7f5a5109205c54",
          "message": "Widen the bare-error gate to src/ffi.zig and fix misclassified FFI ranges (#2335)\n\nThe `Check bare TypeError regression` CI gate scanned only\n`src/primitives*.zig` for `return PrimitiveError.TypeError`, so it never\nsaw `src/ffi.zig` — wrong path (glob excludes ffi.zig) and wrong spelling\n(all 27 sites are `return error.TypeError`). Both blind spots hid the same\nfile, and among its returns the narrow-integer range checks were\nmisclassified: a wrong *magnitude* surfaced as KP3002 (type error) instead\nof KP3007 (invalid argument), so a caller catching `error-object-code`\ncould not tell a wrong type from a value that is simply too large.\n\nWiden the gate on both axes and across the taxonomy: it now scans all of\n`src/`, both `error.Foo` and `PrimitiveError./VMError.Foo` spellings, and\nTypeError/IndexOutOfBounds/InvalidArgument. Test files legitimately use\n`error.TypeError` in `expectError`, so `src/tests_*.zig` is excluded. A\nbacklog of bare sibling returns in the primitives (kaappi#2020/#2021/#2022)\nremains out of scope here, so the gate is once again a ratchet with a\nBASELINE that may only decrease — exactly the shape it had for TypeError\nbefore kaappi#1868 drove it to zero.\n\nReclassify the FFI argument checks in `validateArgsDetailed`: a value of\nthe right kind that does not fit the declared narrow/`c_int` type, or a\nstring that violates a size/content constraint, now returns\n`error.InvalidArgument` (KP3007), while a genuine type mismatch stays\n`error.TypeError` (KP3002). `mapFfiError` preserves the tag instead of\nflattening every FFI failure to TypeError. The remaining marshalling and\nsignature fall-throughs funnel through `mapFfiError` and carry a\n`// bare-ok` reason; the argError/indexError helper definitions in\nprimitives.zig get the same annotation their typeError sibling already had.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-08-25T23:33:02+05:30",
          "tree_id": "805f12635a0159bc47ec0cf8a63415c70e84dc86",
          "url": "https://github.com/kaappi/kaappi/commit/0f499465681c4c8e2a72f7f5ff7f5a5109205c54"
        },
        "date": 1787683544334,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.047031,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.291303,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.439348,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.185447,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.003863,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.035889,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.219264,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.041424,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 1.853247,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.876192,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.234144,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.245416,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.281105,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.412665,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.036564,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "645d2bba6d60d2d4f3fdc6bda45ba956627d8091",
          "message": "pr-groups: work each PR on its own git worktree (#2336)\n\nThe pr-groups skill planned the groups but said nothing about how to\nexecute them once a wave starts. Launching concurrent implementation\nsessions in the shared checkout means they collide on files and on the\nworking tree, and a fix can land on main by accident.\n\nDocument the execution half: one git worktree per group, branched off\nmain, with a self-contained brief and a commit/PR wrap-up contract\n(regression test, DCO sign-off, per-issue Closes keyword). Bake in the\ntwo operational failures that each cost a session in practice — a\nbackgrounded test run that stalls waiting on a notification, and\nconcurrent builds serialising on the Zig cache lock looking hung — plus\nthe reminder that one worktree's green run does not prove main is green.\n\nAdd eval #5 covering the \"start the wave\" behaviour.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-08-25T19:02:58Z",
          "tree_id": "535555475b2bbabbbba3d8a04af73d979afeb1ca",
          "url": "https://github.com/kaappi/kaappi/commit/645d2bba6d60d2d4f3fdc6bda45ba956627d8091"
        },
        "date": 1787685034917,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.407817,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.35227,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.57014,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.050149,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004674,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.048018,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.307422,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057181,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.839549,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.238747,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.66755,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.282488,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.794084,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.621578,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.04442,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "259f918732b1dc4eba933456ac67d4d908a24450",
          "message": "ci: stop docs-only PRs blocking on the skipped test matrix's required checks (#2338)\n\nThe docs-only fast-path skipped the `test` job at the job level. GitHub does\nnot expand a skipped matrix job into its per-leg check names -- it reports one\ncheck under the raw template `test (${{ matrix.os }}, ${{ matrix.optimize }})`\n-- so the five required contexts (`test (ubuntu-latest, ReleaseSafe)` etc.)\nwere never reported and every docs-only PR sat at BLOCKED on phantom\n\"Expected -- Waiting for status\" checks (kaappi#2337). The classifier itself is\ncorrect; its safety premise (\"a skipped job reports Success to branch\nprotection\") holds for standalone required jobs (wasm, riscv64-test) but not\nfor a matrix job whose expanded legs are individually required.\n\nOption 2 from the issue: the `test` job no longer carries a job-level\n`if: docs_only`, so its matrix always expands and always reports the five\ncontexts. The docs-only short-circuit moves per-step onto `env.DOCS_ONLY`, so\neach leg still reports success on a docs-only PR while skipping the build and\nsuites -- costing ~5 runner startups (seconds), not the ~194 build/test\nminutes. Correct the `format` classifier comment that asserted the\nnow-disproven premise, so the matrix job is not \"simplified\" back.\n\nOnly `test` needs this; every other heavy job is either not a required context\nor a standalone job that skips cleanly.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-08-25T19:00:23Z",
          "tree_id": "359864fc7c96ce902d5e048eac26c3ded2561a38",
          "url": "https://github.com/kaappi/kaappi/commit/259f918732b1dc4eba933456ac67d4d908a24450"
        },
        "date": 1787687017316,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.9363,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.29621,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.560855,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.812177,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.005149,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046115,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.281707,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.053457,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.574733,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.133392,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.5829,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.307755,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.668151,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.817397,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045789,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "6565e7835a905b22b666feceed3ac1dd766ef6d4",
          "message": "SRFI 231: validate boolean options and reshape strided views (#2351)\n\n* SRFI 231: validate boolean options and reshape strided views\n\nTwo anomalies reported by Brad Lucier (SRFI 231 author) after v0.24.0, both\n\"it is an error\" conditions the implementation failed to enforce or reshapes\nit wrongly rejected.\n\nlist->array/vector->array accepted a non-boolean mutable?/safe? option and\nspecialized-array-reshape accepted a non-boolean copy-on-failure?, silently\nreturning a wrong-typed array instead of raising. Add %check-boolean! at each\nsite, matching the reference implementation's per-argument checks.\n\nspecialized-array-reshape only handled the array-packed? case, so it raised\n\"not affinely representable\" for a reversed (negatively-strided) view whose\nelements are still affinely reachable by stepping the body backwards. Replace\nthe packed-only shortcut with a faithful port of the reference's NumPy\n_attempt_nocopy_reshape: probe the affine indexer for base + per-axis strides,\ndrop size-1 axes, greedily match adjacent-axis volume groups, and verify\nC-contiguity within each group. Genuinely non-affine reshapes still raise;\nbody sharing is preserved.\n\nRegression tests mirror the reference suite's reversed / per-axis-flipped /\narray-sample'd reshapes and its non-affine test-error cases.\n\nCloses #2350\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* SRFI 231: address reshape review nits (docs + attribution)\n\nFollow the PR review on the reshape port:\n- Trim the stale section banner that still described the old packed-only\n  simplification (contradicting the rewritten file header).\n- Note why unassigned newstrides left at 0 are safe (only width-1 new axes\n  keep 0, whose (index - lower) term is always 0, so the value is unobserved).\n- Add the NumPy BSD 3-Clause attribution the reference carries, since the\n  loop-1..loop-4 matching is a line-by-line translation of\n  _attempt_nocopy_reshape.\n\nComments only; no behavior change.\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n---------\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-08-26T05:59:48+05:30",
          "tree_id": "f0e2d146726aca8444a847ad0c1c4ff72933e21b",
          "url": "https://github.com/kaappi/kaappi/commit/6565e7835a905b22b666feceed3ac1dd766ef6d4"
        },
        "date": 1787709313667,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.953683,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.387151,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.57233,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.81978,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004858,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.04621,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.282546,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.053456,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.52086,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.121562,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.582839,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.309553,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.670991,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.836407,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.046431,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "603d3cd682894262f63af0a378267bab5dd4d9f6",
          "message": "srfi-158: begin range generators with start; gflatten yields nothing for empty lists (#2339)\n\nTwo defects in lib/srfi/158-impl.scm, both ported faithfully from the\nSRFI's own reference implementation (chibi-scheme reproduces each):\n\n#2055 -- make-range-generator's three-argument case coerced start with\n(- (+ start step) step).  The round trip achieves the spec's exactness\ncontagion but does not leave an already-inexact start alone: the\nsequence began with 0.10000000000000009 instead of 0.1, and when step\ndwarfed start, the addition rounded start away entirely and the\nsubtraction returned 0.0 -- (make-range-generator 1e-20 1.0 1.0) began\nwith 0.0.  The spec's \"The sequence begins with start\" is explicit.\nCoerce with exact->inexact only when step is inexact; an inexact start\nnow passes through untouched, and exact/exact stays exact.\n\n#2057 -- gflatten's refill ran exactly once instead of until it held a\nnon-empty list, so an empty list from the source reached car and raised\na type error.  The spec's \"yields the elements of the lists produced\nby the given generator\" means a list with no elements contributes no\nelements.  The refill now loops; exhaustion still sticks.  This is the\nnatural shape of a filtering map (gmap returning '() for every rejected\nelement), which previously could not be flattened at all.\n\nBoth fixes diverge deliberately from the reference implementation and\nfrom chibi-scheme; the spec text is unambiguous in each case, and the\ndivergence is noted in comments at both sites.\n\nTests: the eight assertions the audit file had parked under ;; FAIL\nmarkers are enabled (and the three raises? pins for gflatten's raising\nbehaviour removed), plus a new consecutive-empty-sub-lists regression --\nthe case a refill that loops only once more still misses.  All nine\nfail on the old library; with the fix srfi158-audit reports 355 passes\nand exit 0, every other suite importing (srfi 158) passes, and\nzig build test is green.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-08-26T06:02:50+05:30",
          "tree_id": "9632254f0d5bb29009393f8277bfca940a4cb5f8",
          "url": "https://github.com/kaappi/kaappi/commit/603d3cd682894262f63af0a378267bab5dd4d9f6"
        },
        "date": 1787709364106,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.729232,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.638382,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.503902,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.683984,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004849,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.044513,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.273237,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.047098,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.464125,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.111798,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.473097,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.26501,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.545105,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.9614,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.040786,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "e510eaaf2acdc1bef4b5afa61961f938649dfd7a",
          "message": "docs: correct SRFI 248 caveat count and document script top-level echo (#2341)\n\nREADME.md and CONFORMANCE.md claimed SRFI 248's delimited continuations\nhave exactly two observable caveats and asserted the list was complete.\nThere is a third, documented in lib/srfi/248.sld's header and demonstrated\nhere: the prompt is a single metacontinuation cell per thread shared by\nevery fiber, so a with-unwind-handler/guard body must not span a fiber\nsuspension point while another fiber runs delimited control (the prompts\ncross silently), and a user call/cc capture must not cross a\nwith-unwind-handler boundary (the guarded body re-runs exponentially --\n2^n-1 times instead of n, 255 where 8 is correct at n=8 -- and the\nprocess still exits 0).\n\nAlso surface, in user-facing docs, that running a script echoes every\nnon-void top-level expression's value to stdout (previously documented\nonly in docs/dev/fuzzing.md): a top-level guard yielding #f or a map used\nfor effect inserts a datum into otherwise structured output, and no flag\ndisables it. Chibi and Guile print nothing running the same file.\n\n#2252 needs no change: the FORMAL_FLAG comments in\nsrc/expander_instantiate.zig were already scoped to lambda formals only\nby #2251 (6ee91e23), and the behavior matches -- verified via kaappi\nexpand: a case-lambda formal colliding with a builtin is hygiene-renamed\nwhile the identical lambda formal keeps its bare spelling, and\ntests/scheme/hygiene/template-binds-builtin-name.scm passes.\n\nCloses #2038\nCloses #1994\nCloses #2252\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-08-26T06:06:36+05:30",
          "tree_id": "f84b2d820aa03659224ac9cc8fa1cdef21b0e312",
          "url": "https://github.com/kaappi/kaappi/commit/e510eaaf2acdc1bef4b5afa61961f938649dfd7a"
        },
        "date": 1787713240286,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.343353,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.754108,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.581159,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.032426,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004695,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.047988,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.305184,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.055909,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.756664,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.233513,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.6549,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.29183,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.78242,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.642951,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.04628,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "f9b575209dfd4ae662444571c5967a531817ac90",
          "message": "fmt: pin the #2143 lexeme-glue and #2080 diagnostic fixes in fmt-adversarial (#2340)\n\nBoth issues were fixed on main by #2291 (fmt's atom scan now ends at the\nfirst non-<subsequent> byte exactly like Reader.readSymbol, and\nverifyRoundTrip reports the reader's own KP1xxx diagnostic when the\noriginal does not read), but fmt-adversarial.sh — the file both issues\npoint at — still lacked the shapes their own bodies name:\n\n- #2143's byte-mutation campaign tripped the round-trip guard on a `#(`\n  glued after an identifier: `(import#(scheme base))` and a datum-label\n  vector glued to one. The comment/vector glues were covered; these two\n  guard-tripping forms were not.\n- #2080's diagnostic path had a single case in fmt.sh (`#\\qqq`); the\n  other three error classes of its table (`#\\xZZ`, `(a . . b)`, form\n  feed) were untested anywhere, and fmt-adversarial.sh had none at all.\n\nEvery new case fails on the pre-fix lexer (verified by rebuilding with\n220e31a2's src/fmt.zig): the glue cases trip the round-trip guard and\neach diagnostic case reports \"internal error\" instead of the reader's\nKP1xxx. With the fix: fmt-adversarial 81/81, fmt.sh 38/38, zig build\ntest green.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-08-26T06:02:46+05:30",
          "tree_id": "3b7c36c6d024b35fe6e64db3bce71249f0de408f",
          "url": "https://github.com/kaappi/kaappi/commit/f9b575209dfd4ae662444571c5967a531817ac90"
        },
        "date": 1787713259182,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.3928,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.967642,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.597134,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.039411,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004715,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.0486,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.308367,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057314,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.863392,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.235698,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.675212,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.287857,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.819179,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.688031,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045761,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "499662f5ccbf393b4a00b6d85f091041945ab625",
          "message": "SRFI-254: guardian weak resurrection and transport-cell weak keys (#2011, #2006) (#2348)\n\nGuardian resurrection followed the spec's 'weakly resurrected'\nhypothetical only halfway: markGuardianStrong marked every ready-queue\nelement in the strong mark phase, and the resurrect branch inside\nprocessWeakRefs marked the watched object as it moved each entry, so a\nsecond guardian (or a second registration in the same guardian) watching\nthe same object probed it as reachable and starved for as long as the\nfirst held it — permanently, if the first was never drained (#2011).\n\nprocessWeakRefs now implements the hypothetical directly:\n\n  * every registered element of every guardian is probed against the\n    frozen mark state before any element is resurrected in that round,\n    so N watchers of one object all fire in the same collection;\n  * ready-queue contents, freshly resurrected elements, and retained\n    representatives are recorded in a per-collection weak_resurrected\n    set — kept alive (a settle pass materializes the marks once every\n    weak decision is made) without ever counting as reachable;\n  * ephemeron keys and transport-cell keys probe with keptAlive\n    (marked or weakly resurrected), preserving the spec's kept-alive\n    reading: a key held only by a guardian's ready queue neither breaks\n    its ephemeron nor breaks its cell.\n\nTransport cell keys were held strongly — cells never broke and every\nregistration pinned its key forever (#2006). The .transport_cell mark\narms now defer the key to a new pending_transport_cells list (the value\nfield stays strong, per 'Except as noted, all newly chosen locations\nare strongly holding') and processWeakRefs breaks every cell whose key\nis neither reachable nor kept alive: broken reads #t, the key reads\n#f, the value survives. A weak key no longer blocks an object guardian\nwatching the same object. Registration stays permanent (the non-moving\ncollector never transports a cell, so (tg) always returns #f) — that\nhalf of the degeneracy is conformant and unchanged; the doc-truth in\nCONFORMANCE.md, the SRFI notes and the type/primitive comments now say\nboth halves.\n\nTests: the audit's pinned one-of-two and never-breaks assertions are\nflipped to the spec answers and extended (same-guardian double\nregistration, re-arming guardians, cross-cycle ready-queue hold,\nstays-broken); 5 Zig GC-semantics tests in tests_srfi254.zig and 3\nrewritten tracing tests in tests_gc_tracing.zig pin the same behavior\ndeterministically (enabled=false GC, explicit collect()). All of them\nfail on the unfixed collector. Verified: audit 189/189 (ReleaseSafe,\n3x under -Dgc-stress=true), R7RS suite 1395/1395 under gc-stress,\nrelated srfi18/srfi-254 suites green, native tier via kaappi compile.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-08-26T06:07:35+05:30",
          "tree_id": "9418bdc40a556d70d8dff6de808f5e9bb0bb0cda",
          "url": "https://github.com/kaappi/kaappi/commit/499662f5ccbf393b4a00b6d85f091041945ab625"
        },
        "date": 1787713300082,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 2.495937,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.806039,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.344366,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 1.864105,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.003683,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.029589,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.183231,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.038125,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 1.746935,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.739193,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.009904,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.213815,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.094298,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.89145,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.029042,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "92346fabc6076a03b97afbb2e73a9e90013da30f",
          "message": "thottam: regression tests for state-file name validation (#2144) (#2346)\n\nThe code fix for #2144 — isValidPkgName guarding every read path out of\ninstalled.txt / thottam.lock in list, update and verify — landed with\n#2289, but nothing pinned the behaviour: reverting those five guards\nwould have passed the whole suite.\n\nThis adds the missing regression tests in src/tests_thottam.zig. They\ndrive doList/doUpdate/doVerify (now pub, with Config, so the test file\ncan run them against a throwaway $KAAPPI_HOME) with a traversal-shaped\nname planted in the state files, capture what the commands print via a\npipe swap of fd 1/2 (the commands write straight to the descriptors;\npipe/dup/dup2 are CRT calls on Windows too), and assert:\n\n- doList lists the real package and never prints the hostile line\n- doVerify names a hostile lockfile or installed.txt line as MALFORMED\n  and fails verification (pre-fix: the lockfile form exited clean, the\n  installed.txt form was reported as UNLOCKED after joining the name\n  onto src_dir for getPkgSha)\n- doUpdate rejects a hostile command-line name with the same loud error\n  as install/remove (pre-fix: NotInstalled)\n- update of every package skips hostile names silently (pre-fix: it\n  announced the package and ran git in the directory the traversal\n  names — TmpHome creates that directory as a plain non-repo so a\n  regression fails by assertion instead of killing the runner)\n\nAll five fail with the guards stripped and pass with them.\n\nOne adjacent gap found running the issue's repro: main()'s update\nhandler did not list InvalidPackageName, so 'thottam update <bad-name>'\nprinted the proper message and then Zig's raw 'error:\nInvalidPackageName' line. Install and remove already suppress it that\nway (kaappi#2132); update now does too.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-08-26T06:02:54+05:30",
          "tree_id": "4a6dc5e63d355c0cabb4383a684873948a017a90",
          "url": "https://github.com/kaappi/kaappi/commit/92346fabc6076a03b97afbb2e73a9e90013da30f"
        },
        "date": 1787713333464,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.391516,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.651403,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.569769,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.04362,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004603,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.048256,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.31099,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057299,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.849959,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.239469,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.659829,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.290388,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.796854,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.647415,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045931,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "aba2468011db77d0c944de993d6af39b7e2a7a5d",
          "message": "control: align tail-position/dynamic-wind error taxonomy; purge %unwind-to-escape (#2036, #2037) (#2343)\n\n* control: align tail-position and dynamic-wind error paths; purge %unwind-to-escape (#2036, #2037)\n\n#2036 — three control-flow error paths diverged from every other\nprimitive:\n\n- tail_call_cc's non-procedure receiver returned a detail-less\n  VMError.NotAProcedure, surfacing as KP3005 with the literal message\n  \"error\"; the same call one position away gave KP3002 naming the value.\n  The else arm now mirrors the non-tail path's typeError.\n- dynamic-wind's argument checks were Scheme-level `(error ...)`, so\n  error-object-code answered #f and the offending value was demoted to\n  an irritant. The checks now go through a native %check-procedure\n  (primitives.typeError), giving KP3002 with the value in the message.\n- compileCallCCTail / compileCallWithValuesTail / compileApplyTail\n  reported a proper-but-wrong-length operand list as KP2001 \"invalid\n  syntax\", abandoning the whole top-level form. Such lists now route\n  through the ordinary call path, so the runtime arity check reports\n  KP3003 exactly as the same form one position away does; improper\n  lists remain genuine syntax errors. The native tier's apply mirror\n  comment (llvm_emit_forms.zig) is updated to match — its <2-operand\n  abandon produces the identical runtime error via the eval fallback.\n\n#2037 — %unwind-to-escape was missing from\nvm_bootstrap.internal_helpers, so user code could pop the wind stack\nand the underflow surfaced as \"type error in '%pop-wind'\". It is purged\nnow, and popWindFn's underflow guard reports KP9001 (\"wind stack\nunderflow in '%pop-wind'\") per gc-safety-and-error-handling.md.\n\nOne deviation from the issue's fix shape, found the hard way: the\nclaimed \"pristine snapshot taken before the purge\" does not exist —\nregisterStandardLibraries snapshots globals into\nlibraries.internal_bindings only AFTER vm_bootstrap.install purges\n(both main.zig init paths and testing_helpers). Purging alone therefore\nbreaks every `guard` with\n`undefined variable '__kaappi_base__%unwind-to-escape'` (verified by\ntemporarily removing the seed). install() now seeds the entry itself,\nbefore the remove, which is order-independent and covers init paths\nthat never register libraries.\n\nTests: 4 disabled audit assertions enabled, plus new purge, guard-path,\nand tail-arity assertions (each fails without its fix — the pre-fix\nvalues KP3005/#f/KP2001/reachable were captured on the baseline\nbinary); the three direct-call %unwind-to-escape audit tests are gone\nwith the reachability they pinned, replaced by a guard-driven\nafter-thunk ordering pin. New Zig unit test in tests_libraries.zig\nlocks the purge+seed pair. Full unit suite, R7RS suite (1395),\nerror-format, error-object-code, continuation, guard-1988, and native\ncompile suites green. BASELINE (bare error-taxonomy returns) unchanged\nat 28.\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* vm_dispatch: route tail call/cc type error through primitives.typeError\n\nReview nit on #2343: the tail path formatted the receiver with\nprinter.valueToString (a heap-allocated full print), while the non-tail\nsibling goes through primitives.typeError's safeValueDescription\n(bounded, cycle-safe, no allocation) -- identical for ordinary values\nbut able to diverge for exotic or cyclic receivers. The arm now calls\ntypeError directly and converts through mapNativeError, which passes\nthe already-set detail through untouched. Audit-pinned messages are\nbyte-identical (control audit 200/200; unit suite 1823 passed / 7\nskipped, exit 0).\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n---------\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-08-26T06:05:44+05:30",
          "tree_id": "b6652cb3dbf76875e20f0be10ff0bfd7a9dd9f8d",
          "url": "https://github.com/kaappi/kaappi/commit/aba2468011db77d0c944de993d6af39b7e2a7a5d"
        },
        "date": 1787713401767,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.341755,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.765976,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.568818,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.032259,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004754,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.047963,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.306158,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.056034,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.778948,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.23307,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.661943,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.285562,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.780573,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.653233,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.046993,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "5b01dfb71332b937772a5b0ddfd0126b84c26835",
          "message": "wasi: make `zig build test -Dtarget=wasm32-wasi` a real gate and run the suite under wasmtime (kaappi#2153) (#2349)\n\nThe wasm32-wasi unit suite did not compile (~20 errors: 32-bit usize\narithmetic, platform-facade gaps in code the test module pulls in), so\nthe WASI reactor backend had no compile gate anywhere and the binary\nwas never executed by any test.\n\nDirection (a) of the issue, with direction (b)'s documentation for the\none piece no runtime can host:\n\n* The suite now compiles: WASI arms for platform.zig's write-open\n  family / openNullSink / DirIter (fd_readdir) / dl* / argsIterate, the\n  process-spawn sites (thottam_proc, test_runner, test_selection,\n  doctor, native_compiler), testing_helpers' fd-pair family, and\n  32-bit-safe FFI test constants. build.zig marks the wasm test module\n  single-threaded (matching the wasm executable), adds the atomics CPU\n  feature (std's futex plumbing analyzes atomic waits even\n  single-threaded; only waits need shared memory, and this module never\n  waits), defaults it to ReleaseSmall (Debug exceeds wasmtime's\n  per-function locals limit in the comptime-generated FFI dispatchers;\n  ReleaseSafe crashes the LLVM wasm32 backend on a float constant-pool\n  selection), and installs zig-out/bin/unit-tests.wasm.\n* The installed binary runs green under\n  `wasmtime run --dir=. --dir=/tmp`: 1542 passed, 209 skipped, 0 failed\n  of 1751 - the same test count as the native suite. This executes\n  WasiPollBackend's CLOCK path for real (addTimer/removeTimer/\n  popExpiredTimers/msFromNs and the scheduler/fiber halves).\n* The fd suites skip on wasm with per-test comptime gates, and\n  testing_helpers.wasmNoFdPairs panics if a test reaches a pair\n  constructor without its skip: WASI p1 has no pipe/socketpair creation\n  syscalls and wasmtime leaves sock_open unimplemented, so a guest\n  cannot construct any EAGAIN-capable fd; poll_oneoff even rejects fd\n  subscriptions on every obtainable fd with BADF (probed on wasmtime\n  48). porting.md Stage 3 now documents this boundary explicitly\n  instead of listing a criterion the backend cannot meet.\n* Bug found by the new gate: make-bytevector/make-string silently\n  allocated a truncated (much smaller) object for absurd lengths on\n  wasm32 - the i64 length truncated inside @intCast before the GC\n  payload cap could see it (the #1912 class). primitives.fixnumFitsUsize\n  now checks in u64 before narrowing; the fixnum-length absurd-payload\n  regression test runs on wasm and fails without the fix.\n* platform.zig's WASI opens now resolve paths through the preopen table\n  the way wasi-libc does (relative -> CWD preopen, absolute -> longest\n  preopen-name prefix), replacing the hardcoded fd 3.\n* Two feature assertions that assumed \"unit tests never build for WASM\"\n  (kaappi-threads, (library (srfi 18))) now expect each platform's\n  correct answer; features' sandbox_available likewise.\n\nCI: the wasm job gains a step that runs the compile gate and executes\nthe binary under wasmtime (the runner is already installed there).\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-08-26T06:08:55+05:30",
          "tree_id": "74ac555eb88599636887ba36875c0927339e3c85",
          "url": "https://github.com/kaappi/kaappi/commit/5b01dfb71332b937772a5b0ddfd0126b84c26835"
        },
        "date": 1787713508189,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.092079,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.573529,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.407302,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.202629,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004513,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.036769,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.224057,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.040362,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.23013,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.894731,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.253253,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.2337,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.294074,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.829753,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.034961,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "6ed6eb95f8882bbfe04b4511d1bd76abf9f5dee4",
          "message": "Preserve fiber fault identity and fix (kaappi fibers) argument diagnostics (#2204, #2002) (#2342)\n\nA VM-level fault in a fiber body lost both its error code and its message\nat the fiber boundary (#2204): the dispatch loop's error arm dropped the\nVMError tag, vm.last_error_detail was never copied into the fiber's saved\nstate, and fiber-join re-raised a substituted KP3007 \"fiber error (no\nexception value)\" — a different condition, so a guard clause discriminating\non the code could never match. The loop now converts the fault into the\nsame coded ErrorObject withExceptionHandlerFn hands a guard (via the\nnewly-pub nativeErrorToErrorObject, the shared error-coding boundary),\nbefore anything can overwrite the detail, and stages it in\nvm.current_exception, the one channel saveCurrentFiber already transports\nto the joiner. Uncatchable errors (StackOverflow, ExecutionTimeout,\nTerminated), continuation jumps, and Scheme-level raises keep their\nexisting behavior. fiber-join now reports e.g.\nKP3002 \"type error in 'car': expected pair, got 5\" for a (car 5) inside a\nspawned fiber, identical to the same fault outside one.\n\nTwo argument-diagnostic mislabels in (kaappi fibers) (#2002):\nmake-channel's u32 capacity range rejection was reported as a type error\nwhose \"expected non-negative exact integer\" text described exactly the\nvalue it got; it is now argError (KP3007) naming the real bound\n(\"an exact integer between 0 and 4294967295\"), with a bignum handled as\nthe range case it is and only genuinely non-integer arguments staying\ntypeError. And a bad timeout to channel-send/channel-receive was blamed on\na procedure named 'thread' — timeoutToDeadlineNs's hardcoded name; the\ncaller now passes its own name through, which also fixes the same message\nfrom thread-join!/mutex-lock!/mutex-unlock! timeouts.\n\nBASELINE for the bare error-taxonomy gate drops 28 -> 27: the reraise\nfallback's return is now annotated bare-ok (it sets its own detail, and\nsince #2204 is only reachable for uncatchable faults and conversion OOM).\n\nTests: +20 assertions in tests/scheme/audit/primitives_fiber-audit.scm\n(129 -> 149 passes) and +5 tests in src/tests_fibers.zig, all verified to\nfail without the fixes and pass with them; full zig build test green,\nfiber filter also green under -Dgc-stress=true.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-08-26T06:10:09+05:30",
          "tree_id": "61484c761f9eb0c50cfbf5bbe9e843d9c1ed82bc",
          "url": "https://github.com/kaappi/kaappi/commit/6ed6eb95f8882bbfe04b4511d1bd76abf9f5dee4"
        },
        "date": 1787715063313,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.344221,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.283432,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.565858,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.026977,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004669,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.048264,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.305497,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.056046,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.876092,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.247431,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.661317,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.274925,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.811027,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.610985,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045315,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "f5ef594b6f9589fb842246de9720022e9c2687cd",
          "message": "records: carry field names on R7RS define-record-type rtds (#2088) (#2345)\n\nAn R7RS positional define-record-type produced an rtd with zero own field\nnames: handleDefineRecordType called allocRecordType (count only), never\npopulating own_field_names/own_field_mutable. record-type-field-names\ntherefore answered #() -- a well-formed but false result -- and\nrecord-accessor, record-mutator and record-field-mutable? all failed with\n\"index 0 out of range for length 0\" on such a type (SRFI 240's whole\nreason for existing is that the R7RS and R6RS syntaxes produce\ninteroperable types; the R6RS-clause and make-record-type-descriptor\npaths already carried the metadata).\n\nAll three R7RS emit paths now record each field's name and mutability\n(mutable iff the clause names a mutator, R7RS 5.5.1):\n\n- handleDefineRecordType (top level and library bodies) allocates via\n  allocRecordTypeExtended -- parentless/generative/transparent, exactly\n  the shape allocRecordType built, plus the field metadata.\n- expandRecordTypeDefines (leading-define body scanning) and\n  compileDefineRecordType (general dispatch) emit the metadata through\n  %make-record-type, which gains an optional third argument: a list of\n  (name-string . mutable?) pairs, the same convention\n  %make-record-type-descriptor's field-specs use. Count-only callers\n  keep the two-argument form.\n\nThe rtd representation is unchanged -- own_field_names/own_field_mutable\nalready existed and were already traced by the GC switches (raw owned\nbytes, like RecordType.name); R7RS rtds now simply populate them, and\ngc_deep_copy's metadata-ful slow path carries them across thread\nboundaries. Stale comments that documented the old behavior\n(types_record.zig's \"0 for a plain R7RS record type\",\ngc_deep_copy.zig's fast-path rationale) are updated.\n\nTests:\n- tests/scheme/srfi/srfi240-audit.scm: the four assertions disabled\n  under \"FAIL: #2088\" are enabled (with the pinned broken-behavior set\n  flipped to assert the fixed behavior), plus new coverage: by-name\n  record-accessor, immutable-mutator rejection, out-of-range index\n  rejection, a zero-field type staying legitimately #(), and a\n  body-local define-record-type carrying its names.\n- src/tests_records.zig: unit tests for the top-level and body-local\n  desugarer paths asserting own_field_names/own_field_mutable on the\n  rtd.\n- tests/scheme/audit/internal-primitives-audit.scm: %make-record-type\n  arity assertions updated for the optional third argument, plus\n  positive and rejection tests for the field-specs form.\n\nEvidence: srfi240-audit 81/81 pass (9 failures without the fix),\ninternal-primitives-audit 255/255, srfi9/57/131/136/137/150/237/240\nall pass, R7RS suite 1395/0, zig build test green, and a no-import\nrecord program through `kaappi compile` prints its field names.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-08-26T06:14:41+05:30",
          "tree_id": "39157d0b7b4efd89dc0cfbcd07ebc3110c9d8536",
          "url": "https://github.com/kaappi/kaappi/commit/f5ef594b6f9589fb842246de9720022e9c2687cd"
        },
        "date": 1787715366020,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.939026,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.454008,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.555831,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.811681,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00496,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.04616,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.284658,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.053533,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.374855,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.136201,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.583453,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.306018,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.688405,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.762866,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045963,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "5b211d179af46d5915bbdac19d7e99cc696cc99d",
          "message": "Error taxonomy sweep: bounds -> KP3006, value rejections -> KP3007, real procedure names (#2020/#2021/#2022) (#2347)\n\nThree coupled error-taxonomy defects, fixed together because they share\ntwo helpers and one audit file:\n\nrange branches now use indexError (KP3006) and argError (KP3007 for\nstart > end, the case 'kaappi explain KP3007' names verbatim), so\nsubstring and string-copy -- one operation under two names per R7RS\n6.7 -- finally agree on the code. Direct sites fixed in\nprimitives_bytevector (bytevector-u8-ref/-set!, bytevector-copy!,\nstring->utf8), primitives_vector (vector-copy!, vector-swap!,\nvector-reverse-copy!, vector-unfold!(-right)!, vector-append-subvectors),\nprimitives_string (string-copy(!), string->list, string->vector UTF-8\noffset conversions), primitives_string_ext (string-replace), and the\nlist-walk family (list-tail, take, drop, take-right, drop-right now\nreport KP3006 when k walks off a proper list, matching list-ref; a\nnon-pair element is still a type error).\n\ntype branch and the range branch shared one message. Each conflated\nbranch is split: the type branch keeps typeError, the domain branch\nbecomes argError with wording that names the value. Covers byte ranges\n(0-255), negative lengths (make-vector/-string/-bytevector/-list/\n-s8vector), the integer->char Unicode domain, enumerated rejections\n(number->string radix, null-environment version, hash bound, s8vector\nelement range, transcoded-port codec/eol-style/error-mode), immutability\n(set-car!/set-cdr!, string-set!, vector-set!, vector-fill!, ... -- 'got\nhash-table keys, ffi name-length/param-count guards, make-time's\nnanosecond range, random bounds/seeds, thread-start! on a started\nthread, and exact on inf/nan.\n\nhelpers hardcoded a placeholder. parseStartEnd and callPredOrCharset in\nprimitives_string_ext now take the procedure name from each of their\ncall sites (20 SRFI-13 procedures blamed the real, unrelated procedure\n'string'; the predicate check blamed 'string operation').\nnumberTypeError/ratPartsVal/complexPartsOf/cmpPair/toF64Ext in\nprimitives_arithmetic thread the real name from + - * / < > <= >= =\nmax min abs quotient remainder modulo gcd lcm expt sqrt sin cos tan\nasin acos exp log magnitude angle numerator denominator, so '+' names\nitself like its neighbour '/'.\n\nAlso converts the 18 bare PrimitiveError.IndexOutOfBounds/InvalidArgument\nreturns in primitives_string_ext.zig to indexError/argError calls: the\ncode was right but no detail was set, losing the index and length.\n\nCI bare-error ratchet BASELINE lowered 28 -> 10 (all 18\nprimitives_string_ext.zig sites cleared; the remainder are\nVM-infrastructure guards in vm_calls/vm_dispatch_helpers/\nvm_continuations/fiber_wait plus io/fiber guards).\n\nTests: tests/scheme/audit/error-taxonomy-audit.scm rewritten -- every\ndisabled ';; FAIL:' assertion is now live (164 assertions, 0 failures),\nthe TODAY pins of the old behaviour are gone, and a self-naming sweep\nasserts all 20 SRFI-13 procedures and the arithmetic operators name\nthemselves, which catches any future shared-helper hardcode by name.\nRunning the pre-fix audit file against the fixed binary fails exactly\nthe 31 TODAY pins, proving the change is visible. Pinned wordings\nupdated in internal-primitives-audit (srfi160 element range) and\nprimitives_srfi181-audit (transcoded-port codec symbols); two stale\nprose comments corrected.\n\nzig build test: 1744 pass, 7 skip. bash tests/scheme/run-all.sh:\n717 pass / 0 fail, R7RS suite 1395 pass / 0 fail.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-08-26T07:37:41+05:30",
          "tree_id": "eb3af1e77646b5c1afa78ce86155fcb259f80582",
          "url": "https://github.com/kaappi/kaappi/commit/5b211d179af46d5915bbdac19d7e99cc696cc99d"
        },
        "date": 1787715805335,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.747341,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.913058,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.520532,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.674768,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004595,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.043173,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.267819,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.051309,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.309459,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.080397,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.482833,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.281574,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.55366,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.695049,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045547,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "2d4a8a9e0c3b858839254373e463cbb67d9bc8fa",
          "message": "Finish the SRFI 166 rework: truly lazy trimmed/lazy and immutable state variables (#2344)\n\nThe #2292 rewrite left two specified behaviors unimplemented:\n\n- trimmed/lazy was a non-lazy alias of trimmed/right, so the spec's\n  defining property -- \"safe to use with an infinite amount of output,\n  e.g. from written-simply on an infinite list\" -- did not hold: a\n  circular list under written-simply hit a hard KP3008 stack overflow\n  inside the output capture.  The writer now streams one token at a time\n  (%write-stream; written/-shared/-simply thread each chunk through the\n  output state variable), and trimmed/lazy installs a counting output\n  hook that unwinds the generator itself via call/cc once the width\n  budget is spent, restoring the hook by hand on both exit paths.\n\n- make-state-variable accepted the immutable flag but nothing enforced\n  it; the spec allows an immutable variable to be \"only dynamically\n  bound with with, and not set with with!\", so with! on one is now an\n  error.\n\nTwo stack-safety rewrites came along with the streaming change, both\npinned by the audit: extract-shared-objects is an explicit enter/exit\nworklist (a 50,000-element list no longer overflows -- the exit-event\ntiming preserves the cycle-vs-sharing distinction exactly), and the\nwriter's list/vector spines are tail-recursive.  Dead helpers\n(%shared-ref-prefix/%shared-ref-cdr) were folded into the streamer.\n\nThe audit gains 26 assertions: the two fixed behaviors (which abort the\naudit with KP3008 / fail on the pre-fix tree), plus spec examples the\nsuite never covered -- numeric/fitted's three hash examples, joined/dot,\nthe writer state variable, written's cycle-vs-sharing labelling, the\ncomma-sep and decimal-align state variables, wrapped's word-separator?\ntokenization, escaped's renamer, string-terminal-width/wide, and the\nSRFI's own columnar+pretty+justified worked example.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-08-26T07:38:20+05:30",
          "tree_id": "2aee4ebb3b1a41a149fa57d84008b7f5c33c893b",
          "url": "https://github.com/kaappi/kaappi/commit/2d4a8a9e0c3b858839254373e463cbb67d9bc8fa"
        },
        "date": 1787716350594,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.045621,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.458106,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.440654,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.185307,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.003767,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.035716,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.22073,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.042084,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 1.932833,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.879745,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.227929,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.233247,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.307848,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.380305,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.036492,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "fe924b40fc38bd0031a292d052fbde826a79bbd9",
          "message": "SRFI 231: fix the spec-audit deviations (#2353-#2362) and vendor the official test suite (#2363)\n\n* SRFI 231: implement u1-storage-class, fix char default and float checkers (#2353, #2354, #2355)\n\nu1 is now a real storage class -- a direct port of the reference\nimplementation's bit-packing over u16vector (body = (vector valid-bit-count\nu16vector), little-endian within each u16, #f copier as in the reference),\nnot a #f stub: the spec mandates uX for X=1, documents exactly this\nrepresentation, and kaappi ships the (srfi 160 u16) substrate it needs\n(#2353). The spec's own board example (reshape of an extracted u16vector\nbit string into the upper-triangular 3x3 matrix) now reproduces exactly.\nf8 stays #f (as in the reference itself); f16 stays #f as a documented\nscope reduction -- the reference implements software half-floats.\n\nchar-storage-class's default is now #\\null (NUL, U+0000) per the\nreference's defaults list and the official test suite; the spec prose's\n#\\0 (digit zero) is stale relative to its own reference (#2354).\n\nf32/f64 checkers accept only inexact reals and c64/c128 only complexes\nwith inexact real and imaginary parts, matching the reference exactly;\nsafe-mode array-set! no longer silently coerces exact values (1/3 into\nc64 used to narrow through f32 precision) (#2355).\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* SRFI 231: interval-scale rejects non-positive and non-integer scales (#2357)\n\nThe spec requires a length-d vector of positive exact integers and the\nreference validates scales up front; without the check a negative scale\non a zero-width axis or a rational scale silently produced a\nplausible-looking interval instead of an error.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* SRFI 231: validate plain-array multi-indices, unsafe getter arity, and constructor arguments (#2358, #2362, #2359)\n\nmake-array now wraps its getter and setter in index checks exactly as\nthe reference's %%make-safer-array does: out-of-domain, wrong-arity,\nand empty-domain calls on ANY generalized array (including the lazy\narray-map/translate/permute/curry results built through it) error\ninstead of running the closure on arbitrary input -- this one gap was\n124 of the 138 failures in a full run of the official SRFI 231 test\nsuite (#2362).\n\nThe row-major indexer now rejects multi-indices longer than the array's\ndimension even on the unsafe path, where they were silently dropped --\nthe reference's fixed-arity getters reject wrong arity regardless of\nsafe? (#2358).\n\nmake-specialized-array and make-specialized-array-from-data validate\ntheir storage-class argument up front, and make-specialized-array runs\nthe storage-class checker on an explicit initial-value at construction,\nboth matching the reference (#2359).\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* SRFI 4: re-export the missing u64/s64 homogeneous vector family (#2361)\n\nSRFI 4's own surface is all ten kinds (u8..f64 incl. u64/s64); the hub\nre-exported only eight, so a legal (import (srfi 4)) program failed on\nu64vector/s64vector even though the (srfi 160 u64/s64) substrate\nlibraries existed all along.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* SRFI 231: per-procedure argument validation and upfront element checks in the combinators (#2359)\n\nNon-array arguments are now rejected with a message naming the procedure\nat every entry point (array-map, for-each, folds, any/every, outer and\ninner product, the four ->list/->vector conversions, list->array and\nvector->array's non-list/non-vector/bad-storage-class inputs) instead of\nsurfacing as internal %record-ref type errors, matching the reference.\nlist*->array/vector*->array validate the dimension argument up front.\n\nlist->array and vector->array additionally validate every element\nagainst the storage class's checker before filling, as the reference\ndoes -- the raw fill path skips checking, which for bit-packed u1\nsilently corrupted the body instead of erroring (#2353 follow-on).\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* SRFI 231: array-decurry and array-block honor the once-per-element access guarantee; array-assign! checks values (#2356, #2359)\n\narray-decurry copies its AofA argument up front (as the reference does)\nbefore validation and fill: the user-visible outer getter now fires\nexactly once per element instead of once per validation probe plus once\nper result element (measured 9x on a 2x3 case, unbounded in the result\nvolume). array-block validates the copy rather than re-reading the\noriginal, restoring once-per-element access (was 2x).\n\narray-assign! validates every source element against the destination's\nstorage-class checker even when the destination is an unsafe specialized\narray -- the raw setter path silently corrupted bit-packed u1 bodies\nwhere the reference errors (\"should check anyway\", per the official\nsuite's commentary).\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* compiler: CaptureScan knows guard compiles its body into closures (#2360)\n\nA legal (scheme base) program combining nested do loops with a guard in\nthe inner body failed with a spurious 'type error in arithmetic' at the\ninner loop's termination test. Root cause: guard desugars to\n(with-exception-handler (lambda (var) clauses...) (lambda () body...)),\nso every reference inside a guard is a capture -- but CaptureScan's\nclosure-form whitelist (lambda, case-lambda, delay, delay-force) did\nnot include guard. The do-variable captured by the guard's thunk\ntherefore stayed unboxed until the guard's own lambda was compiled\nmid-loop, emitting box_local INSIDE the loop while the loop test,\ncompiled earlier, still read the register raw; the second inner\niteration then handed the box object itself to =.\n\nFix: add guard to the whitelist so the enclosing do's pre-loop capture\npass (the #803 boxing invariant) boxes the variable before the loop\nstarts. Any compiler form that wraps sub-expressions in an internal\nlambda must be listed there -- the comment now says so.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* tests: vendor the official SRFI 231 suite as a permanent conformance asset\n\ntests/scheme/srfi/srfi231-official.scm is the SRFI's own test suite\n(test-arrays.scm by Bradley J Lucier, MIT license retained; 744 test\nsites, ~8,800 evaluations with the random loops) adapted from its Gambit\nflavor to portable R7RS. It is the broadest single conformance asset in\nthe tree and the one that exposed the #2362 family -- 124 official-suite\nfailures invisible to kaappi's own hand-written SRFI 231 tests.\n\nThe suite is GENERATED, never hand-edited:\n\n    python3 tests/scheme/srfi/srfi231-official-transform.py\n\nreads the pristine upstream source vendored in\nsrfi231-official-fixtures/ (commit recorded in the generated header;\nthe .gambit suffix keeps fmt.sh's corpus sweep from demanding it be\nR7RS-readable) and applies both the Gambit->R7RS adaptation and the\nkaappi vendoring postlude. Fixtures resolve relative to the suite itself\nand PGM convolution outputs go under TMPDIR, so the suite never writes\ninto the tree regardless of cwd.\n\nConventions:\n- Known kaappi-vs-reference divergences are accounted in a table of test\n  ids (f16 deferral, the unsafe-view UB choice, Gambit's immutable-string\n  expectation), each with its issue reference. The suite exits nonzero\n  only on UNEXPECTED failures -- or when a known divergence stops\n  diverging, which means the entry is stale and hiding real coverage\n  (prune it). Current state: 8,769 passed, 231 error-message-only, 9\n  known divergences, 0 unexpected.\n- Error-expecting tests pass on any error; only Gambit's message text\n  differs.\n- run-all.sh gets a per-file timeout override (600s default for this\n  file, KAAPPI_SRFI231_OFFICIAL_TIMEOUT) since the suite runs ~150s\n  cold-cache -- the isolated KAAPPI_HOME compiles the SRFI's libraries\n  fresh every run.\n\nFull run-all.sh with the new suite: 718/718 Scheme files, 1395/1395\nR7RS, exit 0. docs/dev/testing.md documents the asset.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* ci: skip the official SRFI 231 suite on the Debug and gc-stress legs\n\nThe vendored srfi231-official.scm is allocation-heavy at suite scale\n(8,778 evaluations plus PGM convolutions over a 512x512 image; ~77s warm\nReleaseSafe, ~150s cold-cache under run-all's isolated KAAPPI_HOME).\nUnder Debug that is 10-20x -- past even its own 600s run-all timeout\noverride -- and under gc-stress it is the same quadratic\nallocation-against-live-heap shape as the existing TOO SLOW UNDER STRESS\nexclusions. Both legs already have named skip lists for exactly this;\nthe hand-written srfi231*.scm suites keep the SRFI covered on every leg,\nand the official suite still runs on every default-timeout leg.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* compiler: box every do-referenced local -- the capture whitelist was unenumerable (#2360 review)\n\nThe review on #2363 confirmed the guard fix but showed the identical\ncorruption still live through let-values, let*-values, parameterize, and\nreceive -- and the same is true of ANY user macro expanding to a\ncapturing lambda, which no pre-expansion whitelist can see (receive is\nexactly that: a syntax-rules macro over call-with-values + lambda; it\nfails today with the same box-object-to-arithmetic crash). Enumerating\nclosure-introducing forms is unsound by construction, so the scan now\ncollects every symbol referenced in the do's test, commands, steps, and\nresult expressions and boxes each resolvable local before the loop.\n\nOver-boxing is safe: get_box_local/set_box_local lazily box raw\nregisters, so a marked local whose box_local never executed still reads\nand writes correctly (verified: a skipped conditional do followed by a\nread of the captured variable).\n\nCost, measured: the full benchmark suite is flat-to-faster (fib 2.67->\n2.56s, nqueens 2.80->2.77s, primes 0.359->0.343s, tak 1.93->1.80s\nmedians); the worst case is a pure-counting do loop whose only\nreferences are its own step/test -- ~2x on that micro (147ns vs 74ns\nper iteration vs the equivalent named let), one box per variable per\nloop entry, off the back-edge. A future refinement that recovers it\nsoundly would be lowering guard/let-values/parameterize via the\nexpander so a scan over fully-expanded code sees explicit lambdas.\n\nRegression tests extended with the review's let-values, parameterize,\nand macro->lambda cases (all asserted 6).\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n---------\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>",
          "timestamp": "2026-08-26T07:16:09Z",
          "tree_id": "aca393764bf216fc6f80eed81a1109bed3deb865",
          "url": "https://github.com/kaappi/kaappi/commit/fe924b40fc38bd0031a292d052fbde826a79bbd9"
        },
        "date": 1787731502711,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.131813,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.097724,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.448568,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.184832,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.003794,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.03598,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.22105,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.042329,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 1.866176,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.878261,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.234096,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.248468,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.314505,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.457719,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.036568,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "75f62d344aa0d4cdc10109826fe7bd2c9efddb1d",
          "message": "thottam: unit-tier regression guard for ownership-aware removal (#2136) (#2364)\n\n* thottam: unit-tier regression guard for ownership-aware removal (#2136)\n\nThe ownership-manifest fix for #2136 (unlink only files no other installed\npackage still claims) landed in #2289 with coverage in thottam_state.zig and\nthe git-backed thottam-lifecycle.sh. That shell test needs a git remote and\nis skipped by `zig build test`, so the removal path had no guard in the unit\nsuite that runs on every build.\n\nAdd a network-free end-to-end test that lays out two packages sharing\nlib/kaappi/shared.sld in $KAAPPI_HOME/src (as a clone would), installs both\nthrough the real file-sync path, and drives the real doRemove: removing one\npackage must keep the shared file the other still claims, and removing the\nlast claimant finally deletes it. This fails against removal-by-name, which\nwalked the removed package's own source tree and unlinked shared.sld\nunconditionally.\n\ndoRemove and syncInstalledFiles are made pub so the test can drive them,\nmatching doList/doUpdate/doVerify which are already pub for the same reason.\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* thottam: assert the collision warning and manifest claim in the #2136 test\n\nAddress two review notes on the ownership-removal regression test:\n\n- The second install overwrites a file kaappi-one's manifest already claims;\n  warnIfClaimed makes that audible on stderr. syncPkg now returns the captured\n  output so the test asserts the \"also provided by kaappi-one\" warning — the\n  only unit-tier place that observes the loud-not-silent half of the fix.\n\n- The test claimed doRemove drops kaappi-two from thottam.files but only\n  observed installed.txt. Assert the manifest directly with state.fileClaimedBy:\n  kaappi-one's claim on the shared file survives kaappi-two's removal, and no\n  claim remains once the last claimant is gone.\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n---------\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-08-26T07:35:51Z",
          "tree_id": "24368b540459566ea54f5c65deaeca5fc54cde1a",
          "url": "https://github.com/kaappi/kaappi/commit/75f62d344aa0d4cdc10109826fe7bd2c9efddb1d"
        },
        "date": 1787732332443,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.083313,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.554649,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.442402,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.180971,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.003796,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.03589,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.220656,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.042321,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 1.82943,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.882305,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.225069,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.239097,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.310602,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.458601,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.036916,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "f6014f62f5b3dadb34d3520506811f88d0830dec",
          "message": "Cache .sld libraries and importing programs (#1888) (#2370)\n\n* Cache .sld libraries and importing programs (#1888)\n\nThe bytecode cache never engaged for a program that imports: .sld files\nwere never cached in either direction, and any of the eight top-level\ndeclaration heads refused the main file's cache outright, so 92% of the\ntest corpus recompiled everything it touched on every run.\n\nLibrary loads use \"structure from source, code from cache\": the entry\nstores the compiled body functions, the define-syntax transformers as\ndata, and an ordered event log; a HIT re-parses the (hash-validated)\n.sld and walks its declarations through the ordinary loader — imports\nreally load, exports are re-derived by name, cond-expand re-selects,\ndefine-record-type runs as data — but replays cached functions and\ntransformers wherever the cold path compiled. Running the body against\nthe reconstructed lib_env is what makes this safe where serializing\nvalues cannot be: closures capture the live environment, record types\nand every other runtime value are created exactly as cold, and the\nexport table comes out of the normal export-name lookup, so exports\ncontributed by include-library-declarations or cond-expand are present\nwarm for the same reason they are present cold (the failure mode of the\nold pre-#1888 cache-read path).\n\nInvalidation is layered on the key: each entry records its include\nfiles (path + content hash) and file-backed dependencies (relative\npath, resolved path, content hash), re-validated before a warm replay\nstarts. Editing a dependency stales every entry that transitively\nimported it; a --lib-path change that re-resolves a dependency\nelsewhere misses. Libraries whose cond-expand consulted library\navailability ((library ...) requirements, srfi-<n> feature ids) are\nnever cached — that answer depends on the live registry, not on\nanything a key can hash.\n\nThe two hazards that forced caching off are addressed: collected\nfunctions are rooted in gc.extra_roots for the load's duration (the\nserializer can no longer walk freed memory — the old use-after-free),\nand main files no longer refuse the eight heads: each becomes a\npositional declaration slot (its verbatim source span, re-dispatched\nthrough handleTopLevelForm on a HIT), keeping top-level order so the\n#2200 reorder class cannot arise.\n\nAlso fixes the reader's quadratic span recording: lineColAt rescanned\nfrom byte 0 per datum, so reading one large nested datum (every .sld)\ncost O(n^2) — profiling showed it, not compilation, dominated each\nload. A monotone line/col cursor answers incrementally; cold srfi-64\nloads drop 27.5ms -> 11.4ms and warm runs to 8.5ms on this machine.\n\nFormat v13: entry-kind byte, program slot section, library\ntransformer/event/include/dependency sections, TAG_CLOSURE. Older\nentries read back as ordinary misses. kaappi check / the LSP never\nwrite library entries (analysis-mode placeholder transformers must not\npoison one); --sandbox, --no-ir-opt, WASM and embedded/bundled loads\nstay outside the cache.\n\nTests: tests/scheme/cache/library-cache-1888.sh pins the issue's\nverification checklist (HIT on second run; program/library/include/\ndependency edits miss; --lib-path re-resolution misses; export-set\ncompleteness cold vs warm; exit-code parity); the differential corpus\ngoes from 40/345 files populating the cache to 354/368 with cold==warm\nbyte-identical; unit + gc-stress suites green.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Address review: program-entry staleness, root safety, registry deps\n\nEight findings from the review of #1888, each with a regression check in\ntests/scheme/cache/library-cache-1888.sh (now 34 assertions):\n\n- Program entries carry include/dependency records, validated before a\n  HIT replays anything. A program's compiled slots embed imported-macro\n  expansions exactly like a library body's, so editing an imported\n  library's macros must stale the program entry too — previously only\n  ENTRY_LIBRARY entries tracked this, and the old eight-head refusal had\n  been the (accidental) guard.\n\n- Dependencies found via the registry short-circuit are recorded too:\n  file-backed libraries stamp their resolved path and source hash as\n  Library provenance, so an import order that loads the dependency\n  earlier can no longer hide it from the importer's entry.\n\n- All warm-path root dropping is by pointer identity (funcs and\n  transformers of the deserialized entry), never by truncation — the\n  load's own body execution can append longer-lived roots above the\n  deserialize roots (a fiber awaiting thread-join!, a rootedSlot\n  eval-cache entry) that truncation would silently unroot. The\n  beginWarmLoad miss paths now drop those roots as well instead of\n  pinning one compiled body per stale entry for the process lifetime.\n\n- endWarmLoad's desync path pops the collector frame before erroring, so\n  a swallowed include-form desync cannot leak the frame and shift every\n  enclosing load's collector by one.\n\n- runFile only replays ENTRY_PROGRAM entries with a slot stream: a\n  LIBRARY entry shares its cache key with running the .sld directly, and\n  the old \"legacy no-slots\" fallback was exactly the misfire path (dead\n  code for its stated purpose — the VERSION check rejects pre-v13\n  entries). The kind mismatch now reads as an ordinary miss.\n\n- Declaration slots carry the reader's fold-case state (a #!fold-case\n  directive falls inside an earlier form's span), so a folded\n  (IMPORT ...) is claimed as a declaration on the warm run too.\n\n- The reader's monotone cursor is advanced to the datum's start BEFORE\n  reading it; the old flow queried the start after nested children had\n  pushed the cursor past the end, taking the O(offset) backward rescan\n  for every enclosing list — the quadratic span recording the cursor\n  was meant to remove.\n\nThe include/dependency sections are now shared by the program and\nlibrary entry kinds (layout change within v13; golden/endian and fuzz\nfixtures regenerated).\n\nAll suites green: unit, gc-stress, differential (368/368, cache\nexercised 354/368), full run-all (2114 pass / 0 fail).\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Address second review round: corrupt-read leaks, run-record completeness\n\nFindings from the second review pass (one new inline comment plus the\nCodeRabbit sweep), each verified before fixing:\n\n- Corrupt-cache reads leaked their partially-read sections: `errdefer`\n  does not fire on `return null`, so every truncation/corruption exit in\n  the deserializer's tail skipped its own cleanup and the outer funnel\n  only freed sections already attached to the result. The tail's corrupt\n  exits now return BytecodeError.CorruptedFile (the errdefers and the\n  funnel both run), with a thin wrapper mapping non-OOM errors back to a\n  plain miss for every caller — readFileWithTopLevel, cache status's\n  loadability dry-run, and the fuzz loader see identical behavior. The\n  include section also reorders its reads so nothing can fail between\n  the path dupe and the assignment that makes the loop's errdefer own\n  it. A truncation-sweep unit test pins leak-freedom (it failed before\n  the fix).\n\n- writeTransformer now enforces the reader's per-slice caps on\n  literal_bound / captured_locals / bound_free_refs /\n  def_site_local_refs — the writer-refuses-what-the-reader-rejects\n  contract (kaappi#2113); an oversized transformer is a loud\n  LimitExceeded, not a permanent silent miss.\n\n- tests_fuzz's freeLoaded double-freed bundled_files/preamble after\n  freeDeserializeResult had already reclaimed them.\n\n- beginWarmLoad's nesting-overflow path now pops the depth marker push()\n  leaves behind; without it one 9-deep import chain permanently shifted\n  every enclosing collector and skipped their root removal.\n\n- Main-file top-level includes feed the run recorder after all: the\n  structure-depth flag is now bumped around runFile's head dispatch, so\n  `#!`-free structure reaches openIncludeFile (a runtime eval's include\n  still records nothing).\n\n- A program's dependency records now inherit each loaded library's own\n  include/dependency closure (recorded where the records are at hand:\n  endWarmLoad and a successful endColdLoad), because a program's slots\n  embed the library's macro expansions, which can change through any\n  file in that closure — an include-file edit now stales the importing\n  program too. When a dependency is unrecordable (a library that\n  declined caching, or whose entry write failed) the run is poisoned and\n  the program entry declines rather than serving stale slots forever\n  (--timings: \"not cached: uncacheable dependency\").\n\n- Library entries moved to their own cache-key namespace\n  (cache.pathForLibrary): running a .sld directly writes a PROGRAM entry\n  at the same source path the import path uses for the LIBRARY entry,\n  and the shared key meant each access pattern clobbered the other's\n  entry every time it ran.\n\n- Declaration-only programs (an import-only script) are cacheable: the\n  reader rejected func_count == 0 for every non-library kind, so those\n  entries could never read back.\n\n- timings: the JSON libcache object carries the decline reason; the\n  library-cache shell test now asserts the PROGRAM entry misses on every\n  transitive invalidation, uses a side-effecting library to discriminate\n  the direct-.sld check from a body-thunk misfire, and covers the new\n  scenarios (39 assertions).\n\nAll suites green: unit, gc-stress, differential (368/368, cache\nexercised 354/368), full run-all (2114 pass / 0 fail), wasm build.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Record run dependencies even when the library entry write fails\n\nRound-3 review finding: endColdLoad's write-failure branch (LimitExceeded,\nUnsupportedConstant, or any other write error) neither recorded the run\ndependency nor poisoned the run, so the program entry was written with no\nrecord of that library at all — editing the library's macros then left\nthe program HIT serving stale compiled slots, exactly the silent-staleness\nclass the surrounding commit closes. The four new writeTransformer caps\nmade oversized transformer fields a fresh trigger for precisely this\nbranch.\n\nThe run records do not depend on the entry existing — recordsValid\nre-resolves and re-hashes the filesystem — so the fix records the\ndependency and inherits the library's include/dependency closure on a\nfailed write instead of poisoning, keeping program caching enabled and\ncorrect (poisoning would have declined the program entry entirely).\n\ntests/scheme/cache/library-cache-1888.sh grows a section for it (44\nassertions now): a library carrying a literal nested past the .sbc depth\ncap (write refused with a reason), whose importer still HITs warm with\nthe dependency recorded, and whose macro edit then misses the program\nentry and runs the new expansion.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n---------\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>",
          "timestamp": "2026-08-26T21:35:30Z",
          "tree_id": "a4f712503bb964ed675c3a8b40f2b918d125926a",
          "url": "https://github.com/kaappi/kaappi/commit/f6014f62f5b3dadb34d3520506811f88d0830dec"
        },
        "date": 1787782984042,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.303024,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.985063,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.561909,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.997488,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004941,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.047396,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.308388,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.055296,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.956209,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.262109,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.628237,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.271723,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.775694,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.701007,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.046266,
            "unit": "seconds"
          }
        ]
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
          "id": "767d54ec468a377ecac00f3954b7bc159f0c8fcf",
          "message": "Release v0.25.0\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>",
          "timestamp": "2026-08-27T03:23:17+05:30",
          "tree_id": "15f1080975eb314d0b2bdbcb35975a04c367bea1",
          "url": "https://github.com/kaappi/kaappi/commit/767d54ec468a377ecac00f3954b7bc159f0c8fcf"
        },
        "date": 1787784308470,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.080387,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.906551,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.428385,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.193751,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004002,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.03581,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.221005,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.041726,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 1.924844,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.868284,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.239737,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.231373,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.311159,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.403554,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.035889,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "205baa070f8a815f9beb5cce18bdc164ee136fa2",
          "message": "Document that ~/.kaappi/lib shadows a checkout's lib/ for .sld work (#2375)\n\nThe library search order checks $KAAPPI_HOME/lib (default ~/.kaappi/lib)\nbefore the exe-relative <exe>/../lib (= zig-out/lib, populated from the\ncheckout). That order is deliberate -- a from-source binary must never\nshadow a user's install (kaappi#1523) -- but it means a developer who has\never installed Kaappi has their working-tree .sld edits silently shadowed\nby the last release: a bare `zig-out/bin/kaappi file.scm` loads the old\ninstalled copy, so the edit looks like a no-op and neither a rebuild nor\n`kaappi cache clear` helps, because it is the wrong source file being read,\nnot a stale cache of the right one (kaappi#2352).\n\nrun-all.sh already exports a fresh mktemp KAAPPI_HOME for the whole run, so\nthe suite always exercises the working tree; the hazard is confined to\nad-hoc invocations, which need a `KAAPPI_HOME=$(mktemp -d)` prefix. Document\nthis next to the build/test instructions in CLAUDE.md and docs/dev/testing.md,\nand pin the suite's existing isolation with a comment so it is not narrowed\nto cache-only later.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-27T12:06:31+05:30",
          "tree_id": "aae6d83d25d4ef12dcd931bf7e49256a9b03527e",
          "url": "https://github.com/kaappi/kaappi/commit/205baa070f8a815f9beb5cce18bdc164ee136fa2"
        },
        "date": 1787814951143,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.088776,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.225098,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.433103,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.183673,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004067,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.035973,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.223077,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.044017,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 1.915403,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.868937,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.235197,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.239807,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.305638,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.475367,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.036304,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "e07d9b8a7f5d29f022b59677727e3d3ead3ef830",
          "message": "Check %make-record field count; import (srfi 192) on WASM (#2374)\n\n* Check %make-record field count; import (srfi 192) on WASM\n\nTwo independent internal-primitive/library fixes.\n\n%make-record ignored the supplied field count against the record type's\nnum_fields: too few values padded the instance with #<undefined> -- a\ntruthy, printable value that escaped into user code and only misbehaved\nfar from the cause -- and too many were silently dropped, neither raising\n(kaappi#1915). It now raises argError (KP3007) naming both counts. The\nportable record SRFIs (57/131/136/150/237) always build a full positional\nfield list, so an exact check leaves them untouched (verified).\n\n(srfi 192) was excluded from wasmAvailable for no reason: all four of its\nprocedures already worked on WASM through the vm.globals fallback, so only\nimport-by-name and the derived cond-expand feature id were broken, and a\nportable probe-then-fallback took the wrong branch for a working feature\n(kaappi#2019). Dropped from the exclusion switch, leaving its three\nneighbours (kaappi_ffi/srfi_18/srfi_170), which have real reasons.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Flip the SRFI 237 audit's #1915 arity pins to the fixed behavior\n\nThe SRFI 237 audit pinned the pre-fix behavior of the no-protocol subtype\nconstructor, which funnels through %make-record: it asserted that an extra\nconstructor argument was accepted and shifted the layout, and that too few\nleaked an uninitialized field. Now that %make-record checks its field count,\nthat constructor raises catchably on the wrong count, so those two pins fail\nand the two disabled \"raises catchably\" assertions are the correct ones.\n\nFlip them, matching the internal-primitives audit already updated in this\nbranch. Missed on the first pass because the fix's local check ran only the\nunit suite and internal-primitives audit, not the full Scheme corpus that\nCI's `test` legs run; verified now with a full run-all.sh (2114 pass, 0 fail).\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Address review: TestContext + pin the KP3007 message counts\n\nTwo CodeRabbit findings on the #1915 tests:\n\n- Convert the tests_records.zig regression to th.TestContext, the\n  documented setup for a multi-eval test (src/CLAUDE.md), instead of a\n  hand-rolled GC/VM pair.\n\n- The audit's mismatch tests only checked that evaluation raised, so they\n  would pass even if the KP3007 message named neither count. Add assertions\n  that the message names the expected and the supplied count in both\n  directions (2/1 too few, 2/3 too many) -- the substantive half of #1915.\n\nDeclined the suggestion to move the audit assertions to a bug-named file:\nthe audit suite is the home #1915 itself designates (\"Add both directions to\ntests/scheme/audit/internal-primitives-audit.scm, where they currently sit\ndisabled behind ;; FAIL: TBD markers\"), and the bug-named regression is the\ntests_records.zig unit test.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n---------\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-27T14:26:01+05:30",
          "tree_id": "ac7251a597f9e449c1ff4a510b82a994e949624e",
          "url": "https://github.com/kaappi/kaappi/commit/e07d9b8a7f5d29f022b59677727e3d3ead3ef830"
        },
        "date": 1787823484991,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.995914,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.737226,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.55246,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.83026,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.005111,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046307,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.288104,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.053357,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.318631,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.122584,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.597827,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.298178,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.685927,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.78335,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.046632,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "efafe15dee36b3b30ba5ad5fbaaa724669251f96",
          "message": "Make the minor collection's mark generational (#2372)\n\n* Make the minor collection's mark generational (#1961)\n\nA minor collection used to perform a full transitive mark —\nmarkValueInner had no generation check, so minor and full collections\ncost the same to mark and only the sweep differed. This makes the minor\nmark actually generational, gated on the prerequisites the issue's\ndesign analysis identified, plus the further edge-audit the gc-stress\nsuite demanded.\n\nCore:\n- GC.minor_marking: while set, markValueInner treats the old generation\n  as opaque (old objects are never swept by sweepYoung, so they need no\n  mark) — the minor mark now costs O(live young) instead of O(live\n  heap). clearOldMarks is dropped from minorCollect: nothing marks an\n  old object during a minor and every sweep clears the marks it sees.\n- keptAlive/weakReachable answer \"alive\" for old objects during a\n  minor: the old generation survives every minor, so an ephemeron with\n  an old key must not break and a guardian watching an old object must\n  not resurrect — the decision defers to the next full collection.\n\nRemembered-set completeness (what makes the above safe):\n- Promotion scan (sweepYoung): the write barrier only fires for\n  containers already old, so edges created while a container was young\n  are recorded when the container is promoted (referencesYoung scan).\n- Full-collect re-scan (sweepOld): a full collection drains the\n  remembered set up front and never promotes, so surviving old→young\n  edges are re-recorded while the old heap is walked anyway.\n- Missing write barriers found by the audit and fixed: guardian\n  registration in invokeGuardian (registered grows at every\n  registration), Function.constants appends (compiler addConstant,\n  .sbc deserializer, gc-stress test helpers), define/set!/define-syntax\n  into a mutable SchemeEnvironment's map (opcode handlers and\n  compileDefineSyntax — the root-marked globals/lib_env maps need no\n  barrier), the running fiber's param_overrides put, and\n  trackOwnedMutex's append.\n- FiberScheduler.markRoots now calls markFiberState for every resident\n  fiber, the running one included: a promoted fiber is opaque to the\n  minor mark, and a running fiber's stale saved snapshot must stay\n  traced because full collections still walk it through the .fiber arm\n  — a value freed by an intervening minor would turn that walk into a\n  use-after-free.\n\nTests: the pre-#1961 sentinel (a minor marks through an old object with\nno remembered-set entry) flips to pin the opposite — the barrier is\nload-bearing and a missing one is a use-after-free; new pins for the\npromotion scan, the full-collect re-scan, the weak-predicate deferral\n(old ephemeron key / guardian entry through a minor), the running old\nfiber, and the minor_old_skips counter proving the mark stops at the\ngenerational boundary while a full mark does not; end-to-end smoke test\nfor an old guardian's registered entry, a parameterize'd value on the\npromoted main fiber, and a large old heap under young churn.\n\nDocs: .claude/rules/gc-safety.md and\ndocs/dev/gc-safety-and-error-handling.md now describe the mechanisms\nthat make the barrier load-bearing (they previously read as though it\nalready were); the wrong \"weak structures never enter the remembered\nset\" comment in gc_collect.zig is corrected.\n\nValidated: zig build test and -Dgc-stress=true (1862/1863 tests), the\nR7RS suite (1395/1395, also under a gc-stress binary), and\ntests/scheme/run-all.sh (2115 pass, 0 fail).\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Address review: barrier the begin-wrapped define-syntax env store; scope set_global's barrier to the successful store\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Address review: global_cache, retired-fiber, and transformer barriers; shared helpers; regression pins\n\nFour confirmed correctness holes the review found in the barrier audit:\n- Function.global_cache stores (get/set/define/call/tail_call global, all\n  six sites incl. fresh-cache allocation): a cached value can be orphaned\n  by a later rebinding before this function's own next global op clears\n  the slot, and the generational minor mark reaches the orphaned young\n  value only through the remembered set. Barrier every cache store.\n- The retire paths run saveCurrentFiber AFTER retireSlot queued the slot\n  for reuse, so a retired fiber can lose its scheduler residency — and\n  with it markFiberState's unconditional pass — while staying\n  heap-reachable. saveCurrentFiber now enrolls an old fiber in the\n  remembered set wholesale via the new GC.rememberObject (the bulk\n  snapshot has no per-field barriers; the errored path's young\n  ErrorObject is exactly one such edge).\n- tx.def_env_val stores (both the plain and begin-wrapped paths):\n  resolveTransformerSpec can hand back a pre-existing promoted\n  transformer via the SRFI 147/211 alias paths, so the store can write a\n  young environment into an old transformer.\n- tx.let_syntax_peer_vals snapshot stores: same aliased-transformer\n  hazard; barrier each peer value.\n\nEfficiency/consistency/altitude from the review:\n- The env-map barriers now skip the interaction-environment wrapper\n  (.owned == false — its map IS the root-marked globals map), whose\n  enrollment would have re-walked every global once per minor, forever;\n  both opcodes now apply the identical rule.\n- GC.rememberObject: one flag-checked enrollment helper for\n  writeBarrier's owned branch, the promotion scan, the full-collect\n  re-scan, and saveCurrentFiber — the #2196 dedup contract lives in one\n  place instead of three hand-rolled blocks.\n- GC.appendFunctionConstant: one append+barrier funnel for\n  Function.constants across the compiler, the .sbc deserializer, and the\n  tests; the ~28 hand-copied pairs (five of them provable no-ops on\n  immediates) collapse onto it.\n- clearOldMarks deleted everywhere — minorCollect's mark-bit invariant\n  makes it dead in fullCollect too — and minorCollect resets\n  minor_marking via defer so the invariant is structural. The vm.zig\n  param_overrides comment no longer inverts which mechanism (markFiberState\n  vs the barrier) is authoritative.\n\nRegression tests per the every-fix-needs-a-test rule: real-path pins for\ninvokeGuardian's registration (eval + manual promotion + minor → the\nentry is probed and resurrected) and for define/set! into a promoted\nmutable SchemeEnvironment (eval through the real opcode path, minor, read\nback intact); mechanism pins for the constants funnel\n(appendFunctionConstant vs raw append), the global_cache store shape, and\nthe retired-fiber enrollment (rememberObject vs none), each with a\ndiscriminating control.\n\nValidated: zig build test and -Dgc-stress=true green, R7RS 1395/1395,\nthe #1961 smoke test, markdownlint.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Apply the shared envStoreBarrier rule to the compiler's env stores (review nit)\n\nThe two compile-time lib_env.put barriers in compileDefineSyntax (plain\nand begin-wrapped) kept the bare isEnvironment test after f78f3ee4 gave\nthe opcode handlers the .owned exclusion — and the path is reachable:\n(eval '(define-syntax k rules) (interaction-environment)) enrolls the\nwrapper, whose map IS the root-marked globals map, after which every\nminor re-walks all of globals (mark + prune) until process exit.\n\nThe rule now lives once, in GC.envStoreBarrier (isEnvironment and\n.owned, then writeBarrier on the wrapper): both opcode handlers and both\ncompiler sites call it. Pinned by the reviewer's exact repro in\ntests_core_eval.zig — a promoted interaction-environment wrapper takes a\ndefine-syntax through eval and must not appear in the remembered set,\nwhile the store itself lands (the macro expands afterwards).\n\nValidated: zig build test and -Dgc-stress=true green, R7RS 1395/1395,\nthe #1961 smoke test, markdownlint.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* referencesYoung: never enroll the borrowed-globals environment wrapper (review follow-up)\n\nenvStoreBarrier closed the barrier route onto the interaction-environment\nwrapper, but the promotion scan and the full-collect re-scan could still\nenroll it: referencesYoung's .scheme_environment arm walked the whole map\nwith no .owned check, so a promoted wrapper was enrolled the moment any\nglobals value was young at promotion or full-collect time — the common\ncase in a real program — after which the entry never prunes while any\nglobal stays young, reintroducing the O(#globals) walk per minor that the\nbarrier exclusion exists to prevent (markVmRoots already marks every\nglobals value each collection; the walk is pure redundancy).\n\nThe arm now returns false for .owned == false wrappers, which by\nconstruction (interaction-environment is the only such constructor) borrow\nthe owning VM's root-marked globals map; a child-thread wrapper's map\nvalues are foreign to that GC and isYoungPointer skips them anyway. This\nalso drops any stale wrapper entry at the next prune.\n\nThe wrapper-exclusion test now pins both routes deterministically: a young\nglobal is defined between the wrapper's two promotion collections, so the\npromotion-scan moment really sees a young value in the wrapper's map —\nthe exact shape that enrolled the wrapper before this fix (the previous\nversion passed only because every other global happened to be old at\npromotion time).\n\nValidated: zig build test and -Dgc-stress=true green, R7RS 1395/1395,\nthe #1961 smoke test, markdownlint.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* State the minor mark's cost precisely: live young plus remembered-container fields (review nit)\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n---------\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>",
          "timestamp": "2026-08-27T14:28:23+05:30",
          "tree_id": "989d2e73d9ac02b8a2e026b9bb159a125245c142",
          "url": "https://github.com/kaappi/kaappi/commit/efafe15dee36b3b30ba5ad5fbaaa724669251f96"
        },
        "date": 1787823700766,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.314465,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.817311,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.560875,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.134962,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004904,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.048632,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.309812,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.056454,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.829494,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.238903,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.630116,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.277685,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.724786,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.641182,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.046205,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "18d97ce33861f09bc09fb67e7a38eea73caaa3d6",
          "message": "Wire up kaappi.pkg name: and source:; drop version: from the grammar (#2376)\n\n* Wire up kaappi.pkg name: and source:; drop version: from the grammar\n\nThe manifest documented four fields but thottam read only depends: and\nbuild:, so name: and source: were inert -- a manifest could name a\ndifferent package, or declare a source, and the install neither checked\nnor recorded either (kaappi#2138). version: was never a field at all.\n\nname: is now consistency-checked against the package being installed: a\nmanifest that names a different package is a packaging error and the\ninstall refuses before recording anything. It stays optional, but a\nmismatching name: is never accepted.\n\nsource: is recorded as the lockfile's provenance on a bare-name install\n(no ::url), so `thottam list` shows `(from: ...)` and a later --locked\ninstall fetches from it -- surfaced with a one-line note, since the\nmanifest is then steering where the package comes from. It cannot redirect\nthe first clone: thottam reads the manifest only after cloning, so the\ninitial fetch URL is always the command-line ::url or the KAAPPI_ORG\ndefault. A ::url that disagrees with source: warns (a fork/mirror is\nlegitimate) and the URL actually fetched is what reaches the lockfile,\nnever the manifest's claim. --locked mode is untouched: the lockfile stays\nauthoritative and the manifest's source: is ignored (#2137).\n\nversion: is dropped from the documented grammar -- thottam locks by git\nSHA, so a manifest version means nothing -- and it keeps being ignored\nlike any unknown key.\n\nRegression tests: the parser unit tests now pin all four read fields (and\nthe empty-value-is-absent rule); the lifecycle shell suite's #2138 scenario\nis rewritten from \"these fields are inert\" to cover the name-mismatch\nrefusal, provenance recording with its note, the ::url-vs-source warning,\nand the no-name install.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Address review: name-check clean exit, locked scoping, URL normalize\n\nFive findings from @baijum on the #2138 wire-up:\n\n- [P2] ManifestNameMismatch was not in the install command's top-level exit\n  set, so it fell through to `return err` and Zig's default handler printed\n  the raw error name as a second line -- the #2132 duplicate-message pattern.\n  Add it to the std.process.exit(1) set, and pin the raw name's absence in\n  the lifecycle test.\n\n- Scope the name: and source: reconciliation to unlocked installs. In\n  --locked mode the lockfile vouches for the exact SHA, so the manifest at\n  that SHA is not re-litigated -- this makes \"--locked mode is untouched\"\n  actually true (the name check previously ran in every mode). Pinned both\n  directions in the lifecycle suite.\n\n- [P3] The source: comparison was a strict string equal, so a trailing `/`\n  or a `.git` suffix -- the same remote -- warned as a divergence, training\n  users to ignore the warning. Compare canonicalized (trailing slash and\n  .git stripped); a scheme difference (http vs https) is a real downgrade\n  and still warns. Unit-tested in tests_thottam.zig.\n\n- [P4] The provenance note went to stdout while the reconciliation warning\n  went to stderr; send the note to stderr too so `install > log` keeps both.\n\n- [P4] A refused install left its fresh checkout in $KAAPPI_HOME/src, which\n  `list`/`verify` don't know about and a later install would reuse via the\n  dirExists guard. Remove it on the refusal path -- but only when this\n  invocation created it, never an already-installed package's tree.\n\nDeclined nothing; all five addressed. docs/dev/thottam.md updated for the\nlocked-mode scoping and the URL normalization.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n---------\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-27T10:43:28Z",
          "tree_id": "3a687b4ca3e26d7161ae8c1c41967c064e1a2b43",
          "url": "https://github.com/kaappi/kaappi/commit/18d97ce33861f09bc09fb67e7a38eea73caaa3d6"
        },
        "date": 1787830012743,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.364157,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.945943,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.55972,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.145532,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004891,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.048268,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.313407,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057111,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.838049,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.23486,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.631478,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.282315,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.728052,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.63627,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.046571,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "b2f908eab5bafcfe04a27a47498218465de198d7",
          "message": "Skip the root-marked map walk for .owned == false env wrappers (#2377) (#2378)\n\nThe interaction-environment wrapper (the only .owned == false\nconstructor) wraps vm.globals, every value of which markVmRoots marks\neach collection regardless — so the valueIterator walks in\nmarkObjectContents and markValueInner were idempotent redundancy.\nBoth arms now return early on !se.owned, mirroring the referencesYoung\nguard from #2372's review round. A child-thread wrapper's map values\nare foreign to that GC and the owner check skips them anyway.\n\nCost only, never unsafe: the skipped walk could only re-mark values\nanother root had already marked.\n\nRegression test in tests_gc_tracing.zig pins the new semantics — an\n.owned == false wrapper rooted alone no longer keeps its map's values\nalive (fails on main, passes with the skip).\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>",
          "timestamp": "2026-08-27T10:44:17Z",
          "tree_id": "7e546e0785550358cc72cb6037178db89305dfef",
          "url": "https://github.com/kaappi/kaappi/commit/b2f908eab5bafcfe04a27a47498218465de198d7"
        },
        "date": 1787830448197,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.294331,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.27163,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.56319,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.100189,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004996,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.048415,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.315689,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.056481,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.855385,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.23151,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.647499,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.281258,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.725269,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.683867,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.046972,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "3318997ca863d43a20432df44d24393e44674dbd",
          "message": "tests: pin the KP3007 diagnostic in the SRFI 237 arity audit (#2381)\n\nFollow-up to #2374. A CodeRabbit review comment on that PR (which merged\nfirst) noted the srfi237 audit's #1915 arity tests used raises? alone, so a\ngeneric catchable error would pass without the count-naming message. Assert\nthe KP3007 diagnostic shape via message-of, matching the strengthening that\nlanded for the internal-primitives audit in #2374.\n\nThe layered subtype constructor fills the parent level first, so the message\nnames the parent rtd's sub-construction counts, not the subtype's -- the\ntests check the stable \"field(s) but ... value(s) were supplied\" shape rather\nthan coupling to that split.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-27T10:53:03Z",
          "tree_id": "9dd0c405a72b7ad274b6ef04280200db89f2d57e",
          "url": "https://github.com/kaappi/kaappi/commit/3318997ca863d43a20432df44d24393e44674dbd"
        },
        "date": 1787831851231,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 5.164009,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.108676,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.557651,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.095358,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004898,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.048168,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.314547,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.056554,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.784394,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.231808,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.637859,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.277152,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.713256,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.632001,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045501,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "a6cf52dba05c70fe7f4ef999b1dda2457b44b585",
          "message": "Implement SRFI 231 f16-storage-class as software half-floats (#2383)\n\n* Implement SRFI 231 f16-storage-class as software half-floats (#2379)\n\nf16-storage-class was bound to #f — a scope reduction carried over from\n#2353 — even though the u16vector substrate it needs is shipped and the\nreference implementation's codec (generic-arrays.scm 1449-1601) is pure\narithmetic over it: no host bit-reinterpretation anywhere, so it ports\nto R7RS-small directly. The spec's #f escape clause is written for\nimplementations *lacking* the substrate, which this is not.\n\nThe codec is a faithful transliteration of the reference's\nf16->double/double->f16, hand-expanded from its defining macro for the\none instantiation (mantissa-width 10, exponent-width 5, bias 15):\n%f16-decode/%f16-encode as library-internal defines plus a fresh %ilogb\nloop (halving/doubling, exact at every step). Gambit-ism substitutions,\neach semantics-preserving: ##flonum->fixnum (flround x) -> (exact\n(round x)) since R7RS round IS ties-to-even; flscalbn x n -> (* x\n(expt 2.0 n)) since every scale factor is a power of two within f64's\nexact range, preserving the scale-exactly-then-round-ONCE shape; the\n##flcopysign sign test -> (or (< x 0.0) (eqv? x -0.0)); flfinite?/\nflnan? -> finite?/nan?. The structure that makes the reference correct\nis preserved: the subnormal branch scales by 2^24 directly (one\nrounding at the subnormal ulp), mantissa carry after rounding bumps\nthe exponent exactly (sending the 65520.0 tie up to +inf.0 while\n65519.9 stays 65504), -0.0 round-trips both ways, and 2^-25 ties to\neven -> 0. NaN payloads canonicalize to #x7FFF (sign/payload not\nportable; decode yields +nan.0 either way). Class wiring mirrors the\nf32/u16 entries: %flonum-checker, fill encoded once by the maker,\nu16vector-copy!, data->body via %checked-data->body.\n\nTests: exhaustive 65536-pattern round-trip in\nsrfi231-storage-classes.scm through the public getter/setter (the\nreference's own validation strategy, tightened to a full sweep — every\nnon-NaN pattern re-encodes exactly, 2046 NaN payloads identified), plus\ndirected edges (1.0/#x3C00, -0.0/#x8000, ±inf, NaN, max finite,\n65520.0 overflow tie, subnormal and carry ties, negatives). The old\n(test-equal #f f16-storage-class) is replaced by check-storage-class\ncoverage.\n\nOfficial suite: divergence ids 98/148/149 pruned. Id 150 turned out to\nbe overloaded — it was hiding two pre-existing c64/c128 row failures\n(the reference backs complex classes with even-length f32/f64vector\npairs, kaappi uses native c64vector/c128vector) alongside its f16 row;\nit stays, re-scoped to that accurate reason (#2382). Regenerated, never\nhand-edited: 10922 passed, 231 error-message-only, 5 known divergences,\n0 unexpected failures, 0 resolved divergences — evaluation count up\nfrom 8879 now that f16 paths complete (array-copy/appends with real\nhalf-float rounding through the random-builder blocks are the external\noracle the issue asked for). arrays.sld needs no widening table: this\nport's array-copy goes through the generic checker/setter path.\n\nDocs: storage-classes.sld header and srfi-implementation-notes.md now\nsay 16 real / 1 deferred (f8); testing.md's divergence-reason examples\nupdated; CHANGELOG Added entry.\n\nValidated: srfi231-storage-classes.scm 202 passes, the official suite\ngreen as above, and tests/scheme/run-all.sh (720 Scheme files, R7RS\n1395/1395; 2115 pass, 0 fail).\n\nCloses #2379\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Harden srfi231-official divergence accounting with exact counts (review)\n\nBoth reviewers flagged the same gap on #2383: known-divergence matched\nby numeric id alone, but test id 150's form runs once per storage-class\nrow (16 evaluations), so its c64/c128 entry would absorb a failure in\nANY row under the id — including the f16 row this PR just made live. A\nregressed f16 would print DIVERGENT-EXPECTED and still exit 0; the\nepilogue only gated on failed-tests and resolved-divergences, so the\ndivergence count silently going 5 -> 6 failed nothing.\n\nThe granularity limitation is pre-existing (the old entry lumped\nf16+c64+c128 the same way), but before this PR every row under the id\nwas expected to fail, so nothing could hide; rows expected to PASS\nunder a shared id is the new situation.\n\nFix, per the review's suggested shape (stays inside the existing\narchitecture, no renumbering of upstream ids): each entry becomes\n(id expected-count . reason) — 147/1, 150/2, 351/2 — report-failure\ncounts per-id observations into diverged-counts, and the epilogue\nfails the suite on any mismatch in either direction: zero observed is\nthe existing stale-entry DIVERGENCE-RESOLVED; more than expected is a\nnew DIVERGENCE-COUNT-MISMATCH (an undocumented failure is hiding under\nthe id); fewer is the same mismatch with an over-accounting message\n(re-count it). The suite is deterministic (fixed SRFI 27 seeds), so\nthe counts are stable run to run.\n\nNegative test (scratch copy, not committed): corrupting the f16 row's\ngood-data fixture to an s16vector — the exact hiding scenario — now\nyields 'DIVERGENCE-COUNT-MISMATCH 150: expected 2 diverging\nevaluations, observed 3' and exit 1; before this commit it exited 0.\n\nAlso takes the optional %ilogb review nit: clamp the halving/doubling\nloop to [-15, 16] (bail once the classification — '<= -15', 'in\n[-14,15]', '>= 16' — is decided), bounding it to ~31 iterations for\nastronomical doubles instead of ~1000. No observable change: the\nexhaustive sweep and all directed edges are byte-identical, and\nencode of 1e300/-1e300/5e-324/-5e-324 lands on ±inf/±0 as before.\n\nValidated: storage-classes 202 passes; official suite 10922 passed /\n0 unexpected / 0 resolved / 0 count mismatches; fmt corpus 938 files\nzero-drift idempotent.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n---------\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>",
          "timestamp": "2026-08-27T12:58:53Z",
          "tree_id": "1b7c41c6c055a3bc9e61c2b45e2f3a2a168c0c51",
          "url": "https://github.com/kaappi/kaappi/commit/a6cf52dba05c70fe7f4ef999b1dda2457b44b585"
        },
        "date": 1787837863987,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.986192,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.634608,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.540421,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.770797,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.005287,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.045077,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.283947,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.054324,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.871038,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.113995,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.504158,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.26428,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.642391,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.057461,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.041804,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "901309c499aae85764509d3134d3ff75c58467f7",
          "message": "docs(windows): point the aarch64 strip/native unblock at Zig 0.18.0 (#2386)\n\nThe upstream fix for the aarch64-windows private-threadlocal miscompile\n(ziglang#31865, #1607/#1613) missed the 0.17.0 window: the issue is now\nclosed and re-milestoned to 0.18.0, and 0.17.0 has still not shipped as\nof 2026-08 (latest stable remains 0.16.0). Update every \"0.17.0 bump\"\nreference in the Windows dev doc accordingly.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-08-27T19:42:34+05:30",
          "tree_id": "890c128ab91b8ae46681d0b9a159734ca0a14a6d",
          "url": "https://github.com/kaappi/kaappi/commit/901309c499aae85764509d3134d3ff75c58467f7"
        },
        "date": 1787840432098,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.284665,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.522068,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.581453,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.112719,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.005067,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.048376,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.316386,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057124,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.854131,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.234076,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.651303,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.282006,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.726699,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.708487,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045551,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "fb703515a36e8fa280c482ce579496b9487fa00a",
          "message": "Close the last srfi231-official divergence-accounting gaps (#2383 review) (#2385)\n\n* Close the last srfi231-official divergence-accounting gaps (#2383 review)\n\nTwo CodeRabbit threads were still open when #2383 merged; the reviewer's\npost-merge assessment verdicts both valid (and declines the third, the\nsigned-zero eqv? finding, with rationale on the PR):\n\n- testing.md described only the zero-observed and greater-than-recorded\n  mismatch cases; the epilogue's third case -- fewer than recorded but\n  nonzero, \"the entry over-accounts (re-count it)\" -- is now documented\n  too, alongside the never-executed case added here.\n\n- The epilogue's (when (vector-ref executed-tests id) ...) guard skipped\n  entries whose id never executes: if a future regeneration drops a\n  test form entirely, its table entry passes silently -- observed count\n  zero, but neither DIVERGENCE-RESOLVED nor a mismatch fires. An\n  unexecuted id is now a failure with its own wording,\n  DIVERGENCE-NEVER-EXECUTED (\"its test form is gone from the suite;\n  prune the entry\"), counted into the mismatch total that gates the\n  exit status. Suite regenerated from the transform, never hand-edited.\n\nValidated: the real suite is unchanged-green (10922 passed, 5 known\ndivergences, 0 unexpected, 0 resolved, 0 count mismatches -- all three\nreal ids execute); a negative scratch-copy with a correctly-quoted\nbogus entry '(9999 2 . ...) prints DIVERGENCE-NEVER-EXECUTED 9999 and\nexits 1, where the old guard exited 0 silently; fmt corpus 938 files\nzero-drift idempotent.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Add generation-time known-divergence id guard to the transform (#2385 review)\n\nReview suggestion (non-blocking) on #2385: the scanner already collects\nevery generated test id in test_meta, so a generation-time assertion --\nevery known-divergence id must appear in the scanned set -- catches the\ndropped/renamed-upstream-form case instantly at the regeneration step,\ninstead of one ~150 s suite run later. Complement, not replacement: the\nruntime DIVERGENCE-NEVER-EXECUTED epilogue stays authoritative for CI\n(it guards the committed artifact even when nobody regenerates).\n\nThe ids are parsed out of NEW_REPORT's table with a strict regex; an\nempty parse fails too, so the guard cannot rot silently if the entry\nformat drifts. The assertion runs before open(OUT, 'w'), so a failed\nregeneration writes nothing and cannot clobber a good artifact.\n\nValidated: normal regeneration exits 0 and leaves the committed\nsrfi231-official.scm byte-identical; a scratch copy of the transform\nwith id 351 renumbered to 9999 aborts with 'known-divergence ids with\nno test form in the generated suite: [9999]', exit 1, no output file.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n---------\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>",
          "timestamp": "2026-08-27T14:20:34Z",
          "tree_id": "dfeabc4cc62b491ed23a0e18ff664fd15d36f30f",
          "url": "https://github.com/kaappi/kaappi/commit/fb703515a36e8fa280c482ce579496b9487fa00a"
        },
        "date": 1787842835723,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.96592,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.072512,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.558886,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.823802,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.005222,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.045807,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.281678,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.053563,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.328285,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.121549,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.625957,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.306616,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.636005,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.839095,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.046091,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "1503d1d4d639c62c84f7bf0573545d4a9aeab4f0",
          "message": "Switch SRFI 231 c64/c128 bodies to the reference representation (#2387)\n\n* Switch SRFI 231 c64/c128 bodies to the reference representation (#2382)\n\nc64/c128 storage classes were backed by native c64vector/c128vector,\nso the reference implementation's data shape -- an even-length\nf32/f64vector of interleaved re/im pairs -- was rejected by\nmake-specialized-array-from-data, diverging on the official suite's\ntest-150 fixtures (known-divergence id 150, kaappi#2382).\n\nTwo findings settled the design. First, the spec's data? contract --\n\"returns #t if and only if data->body returns a body sharing data with\ndata, without copying\" -- makes a converting data->body illegal, so\naccepting that data shape is possible only by actually using it as the\nbody; the spec explicitly allows either representation (\"another\nimplementation ... might make another choice\"). Second, Kaappi's\nc64vector/c128vector already use the identical byte layout (2\nconsecutive f32s/f64s per element, never boxed, per\nsrc/types_numeric.zig), so switching is a change of type tag, not of\nmemory shape -- and reference fidelity is what reference-coupled\nportable code and the official suite's fixtures interoperate with, the\nsame philosophy as the u1 and f16 ports.\n\nImplementation: a %complex-storage-class helper ports the reference's\nmake-complex-storage-classes -- getter reassembles the interleaved\npair (an inexact zero imag stays complex, kaappi#2269, exactly like\nthe native decode), setter explodes into the two float slots, maker\nfills alternating re/im, length halves the physical float count,\ncopier is the float-vector block copy, and data?/data->body accept\nexactly the even-length float vectors, zero-copy identity. The\nnow-unused (srfi 160 c64)/(srfi 160 c128) imports are dropped.\n\nUser-visible consequences (CHANGELOG Changed entry): (array-body A)\nfor a c64/c128 array reports the float vector; the storage-class\ncopier counts floats (2 per complex element); c64vector/c128vector\ndata is no longer accepted directly.\n\nTests: check-storage-class learns a body-units-per-element option\n(2 for the complex classes) for its copier exercise; a dedicated\nrepresentation section in srfi231-storage-classes.scm pins data?\nacceptance/rejection (even, odd, c64vector), data->body identity,\ninterleave round-trips, setter explosion, and maker fill; and\nsrfi231-arrays.scm adds the end-to-end zero-copy proof --\nmake-specialized-array-from-data over an f32vector shares so\nthoroughly that mutating the caller's vector is visible through the\narray.\n\nOfficial suite: divergence id 150 pruned and the suite regenerated.\nBefore pruning, the #2385 accounting flagged the resolution on its\nown -- 'DIVERGENCE-RESOLVED 150 -- prune it from known-divergences' --\nthe enforcement working as designed. The known-divergence table is\nnow down to the two unavoidable entries: 147 (Gambit string\nmutability) and 351 (unsafe-view checking).\n\nValidated: srfi231-storage-classes 219 passes, srfi231-arrays 90,\nofficial suite 10924 passed / 3 known divergences / 0 unexpected /\n0 resolved / 0 count mismatches, fmt corpus 938 files zero-drift\nidempotent, run-all.sh 2115 pass 0 fail (720 Scheme files, R7RS\n1395/1395).\n\nCloses #2382\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Address review: complex copier takes logical-element offsets (#2387)\n\nAll seven review comments were valid; the substantive one is a real\nbug in the port. The reference does NOT install the raw float copier\nfor c64/c128 -- generic-arrays.scm:137-140 defines\nc64vector-copy!/c128vector-copy! as x2-scaling wrappers over the float\nblock copy, and the class macro installs those wrappers, so its copier\ntakes LOGICAL complex-element offsets, the same units as every other\nstorage-class field. Installing float-copy! raw made kaappi's complex\ncopier the only field in the only class indexed in a different unit:\nreference-coupled code doing (copier to 1 from 0 2) would silently\ncopy half the data at an odd float offset -- real parts landing in\nimaginary slots, no error. Nothing in-tree calls the copier, so no\nsuite caught it. Fixed with the reference's own wrapper shape:\n  (lambda (to at from start end)\n    (float-copy! to (* 2 at) from (* 2 start) (* 2 end)))\n\nThe review also showed the units-per-element test knob had adapted\nthe suite to the bug rather than detecting it. check-storage-class is\nreverted to its original shape (logical units, no knob) and its\ncopier exercise now runs twice -- the full aligned range AND a\nnon-zero at/start copy (shifted 1 body 1 3), which distinguishes the\ntwo granularities: a raw-float copier passes the aligned copy while\nmisplacing data at every other offset. Pinned across all 15\ncopier-bearing classes (storage-classes suite 219 -> 249 passes); the\nreviewer's exact repro (copier to 1 from 0 2) verified by hand.\n\nAlso from the review:\n- maker: a uniform fill (eqv? on re/im -- the default 0.0+0.0i, the\n  overwhelmingly common make-specialized-array path) collapses to one\n  native make-float-vector fill instead of 2n interpreted stores;\n  -0.0/0.0 and NaN mismatches still take the loop.\n- data?/data->body: the even-length predicate is hoisted once and\n  data->body reuses %checked-data->body (byte-identical message), so\n  the two can no longer drift apart -- the spec's iff-contract the\n  comment quotes.\n- transform: the NEW_REPORT example still named the id-150 entry this\n  PR deletes; reworded to a live one (a third unsafe-view evaluation\n  under the 351 entry) and regenerated -- never hand-edited.\n- CHANGELOG: dropped the 'copier counts floats' consequence; with the\n  wrapper there is no user-visible copier divergence at all.\n\nValidated: all 231 suites green (storage-classes 249, arrays 90);\nofficial suite 10924 passed / 3 known divergences / 0 unexpected /\n0 resolved / 0 count mismatches; fmt corpus 938 files zero-drift\nidempotent.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n---------\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>",
          "timestamp": "2026-08-27T15:38:15Z",
          "tree_id": "d601c4261085798376a808a2434ef5206645accd",
          "url": "https://github.com/kaappi/kaappi/commit/1503d1d4d639c62c84f7bf0573545d4a9aeab4f0"
        },
        "date": 1787847515362,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.325732,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.955668,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.557387,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.123148,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004925,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.048469,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.313929,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.056253,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.803286,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.26452,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.638343,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.274732,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.707719,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.628584,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045948,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "0a7960142146874a33718fbff4199f203fcb0ba8",
          "message": "Ratify the check/--sandbox compile-time macro execution policy (#2393)\n\ndocs/dev/check.md claimed a same-file macro use expands \"without running\nanything\" — false since er-macro-transformer shipped (v0.22.0, #1811):\nexpandProceduralMacro calls the call_proc_for_macro VM hook\nunconditionally when the transformer spec is statically resolvable, and\nthe spec expression itself is evaluated at definition time. Specs\nunresolvable without execution get a benign placeholder (#2007, #2329).\nKEP-0006 flagged the sentence (Unresolved question 3) and called the\npolicy the one item with security consequences if skipped; its \"As\nimplemented\" Divergence 8 records that the design note was never\nwritten.\n\nThis writes it down. The new decision note ratifies KEP-0006's\ncandidate (a) — macro-defining code is compile-time code, not sandboxed\nprogram code, Racket's stance — which the shipped behavior already\nmatches, and documents the --sandbox capability model: the sandbox is\nenvironmental (a restricted global environment constructed before any\nsource is read), not temporal, so a transformer body running at\nexpansion time — before the program's own top level — is confined by\nexactly the program's capability set. All claims verified against\nsrc/expander.zig, src/vm.zig, src/compiler_define_syntax.zig,\nsrc/primitives.zig, src/vm_library.zig, and empirically with a v0.25.0\nbinary (a file-writing transformer runs under plain check, is refused\nunder check --sandbox, and --timeout bounds a looping transformer).\n\nCloses #2389\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-27T23:26:36+05:30",
          "tree_id": "d9c5ab5972bde9a7cc238d1e346cc58eaad426c3",
          "url": "https://github.com/kaappi/kaappi/commit/0a7960142146874a33718fbff4199f203fcb0ba8"
        },
        "date": 1787853802570,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.306202,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.526222,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.578246,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.098547,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004904,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.048032,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.314801,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.05631,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.88824,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.234052,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.655795,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.280353,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.711579,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.620247,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.046279,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "10a5be17f03f637e9a8a17406f97f2b3e26bfe82",
          "message": "Add channel identity comparators to (kaappi fibers) (#2397)\n\n* Add channel identity comparators to (kaappi fibers) (kaappi#2394)\n\nKEP-0002 §2 promised that eqv?/equal? compare the SharedChannel pointer\nfor promoted channel stubs; none of that shipped, and the issue's\ndiscussion settled the promise as the SRFI-128 comparator surface\n(option 1b) instead of extending the global predicates:\n\n- channel=? — #t iff both operands are channels backing the same\n  SharedChannel (or the same unpromoted local channel); carries the\n  same foreign-owner check as channel-send, like channel-closed?.\n- channel-hash ch [bound] — hashes the shared pointer, consistent with\n  channel=? by construction; mirrors (hash obj [bound]) (SRFI 69).\n- channel-comparator — (make-comparator channel? channel=? #f\n  channel-hash) built by calling the real (srfi 128) make-comparator,\n  lazy-loaded on demand (embedded for --sandbox and WASM, like\n  (srfi 181)); the three procedures are the (kaappi fibers) registry's\n  pristine exports, immune to top-level shadowing of those names.\n\nunboundedHash is now pub so channel-hash shares the exact unbounded\nhash rendering. eq?/eqv?/equal? stay stub-identity, as the KEP's\n2026-08-27 as-implemented amendment records.\n\nTests: unit tests in src/tests_fibers.zig (local identity, stub\nunification across threads, hash-table dedup both ways, lazy\ncomparator construction) plus tests/scheme/smoke/channel-identity-2394.scm\nfor the end-to-end scenario. Docs: new section in\ndocs/dev/thread-value-sharing.md covering the comparator surface, the\npromotion/hash-stability caveat, and the SRFI-113 sets-don't-honor-\ncomparators gap.\n\n* Signed-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* DCO remediation commit for Baiju Muthukadan <baiju.m.mail@gmail.com>\n\nI, Baiju Muthukadan <baiju.m.mail@gmail.com>, hereby add my Signed-off-by to this commit: 68cb86effcbeed04329e659a91f84fef8fe4877a\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Address review: promotion-stable hash, thread-safe comparator, SRFI-113 fix (kaappi#2394)\n\nEvery finding from the #2397 review, verified against the code first:\n\n- Promotion-stable channel hash (CodeRabbit, baijum): promoteChannel\n  preserves the promoting channel's tagged Value as\n  SharedChannel.identity_seed (written before publish), and channel-hash\n  hashes that seed in every representation -- a table keyed before the\n  first cross-thread send stays reachable after promotion rewrites the\n  original in place, and every stub hashes the one seed. The unpromoted\n  path routes through valueHash, so (channel-hash ch) = (hash ch) on\n  every target including wasm32's 32-bit usize; the copied mixing\n  constant is gone.\n- Worker-thread lazy-load hazards (baijum): threadStartImpl pre-loads\n  (srfi 128) on the spawning VM before any child can struct-copy the\n  registry (ensureComparatorLibraryLoaded, best-effort). The process's\n  first make-thread is necessarily the root, so the load is always\n  pre-children and read-only afterwards -- no child ever lazy-loads\n  into the shared bucket storage, and the loaded exports live on the\n  root heap where markVmRoots marks them.\n- channel-comparator is cached on the VM like default_random_source\n  (default_channel_comparator, marked unconditionally in markVmRoots):\n  repeat calls return the same record.\n- The embedded (srfi 128) is now the last-resort source on native after\n  a disk miss too (baijum): a release binary or -Dbundle-src standalone\n  with no lib tree loads it from the binary; disk keeps precedence.\n- A stale last_error_detail no longer misroutes the lazy-load error\n  (reset before the load, ffi.zig callFfi precedent; the swallow path\n  clears again so nothing leaks to the next unrelated error).\n- checkChannelOwner extracted (baijum): the sixth and seventh inline\n  copies of the foreign-owner gate became the helper's call sites, and\n  channel=? binds each operand exactly once.\n- SRFI-113 sets/bags honor their comparator (baijum):\n  %make-empty-set/%make-empty-bag pass it to make-hash-table, so\n  (set (channel-comparator) a b) dedups stubs; detectMode keeps the\n  native fast path for the standard comparators, whose equality fields\n  hold the real eq?/eqv?/equal?.\n- wasm32-baseline: a natural u64 demands align 8 against Header's 4,\n  breaking destroyHook's @fieldParentPtr -- identity_seed carries an\n  explicit header-matching alignment.\n- Tests: insert-promote-lookup regression, comparator caching, SRFI-113\n  set dedup, worker-thread-first comparator use; the two multi-step\n  unit tests moved to th.TestContext. Docs rewritten accordingly.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Address round-2 review: seed never dereferenced, off-root load refused, default-comparator fast path (kaappi#2394)\n\nThe four #2397 round-2 findings, each verified before fixing:\n\n- valueHash dereferenced identity_seed (baijum): the dispatch chain\n  (isString/isSymbol/isPair/...) reads .tag through pointer bits, so the\n  seed -- which may point at a swept object, a foreign-heap object, or a\n  reused address -- was a racy read at best and content-hashing of an\n  unrelated object at worst. channel-hash now routes through\n  primitives_hashtable.identityHash (now pub, u64 bits): the pure\n  fall-through arm, bit-identical to valueHash for a live channel on\n  every target, zero dereference.\n- make-default-comparator regression (baijum): routing SRFI-113 sets\n  through their comparator put the default comparator -- the common\n  portable case -- on .custom with two closure bridges per probe. The\n  hashtable bridge now recognizes an unregistered default comparator\n  (equality is srfi.128's default-equality binding and\n  registered-comparators is '()) and installs the native equal?/hash\n  pair instead; late registrations opt out (a table captures its\n  construction-time behavior, which SRFI 128 permits) and a rename of\n  the library internals degrades silently to .custom. Smoke tests pin\n  both directions: equal?-table behavior before registration, and a\n  registered channel-comparator extending the default comparator after.\n- residual off-root load (baijum): ensureComparatorLibraryLoaded now\n  refuses to load on a non-root VM (root_vm guard) and returns success;\n  threadStartImpl clears the loader detail on the swallowed failure, and\n  channel-comparator folds that detail into its raised message before\n  clearing it -- so a broken disk 128.sld yields \"channel-comparator:\n  failed to load (srfi 128): LibrarySourceReadError while loading\n  library from .../128.sld\" and the next unrelated error stays clean.\n  Comments corrected: the hook is thread-start!, not make-thread.\n- Verified end to end with a shadowed broken 128.sld via --lib-path.\n\nFull suite: unit 1873 pass / 7 skipped, fibers green under gc-stress,\nrun-all.sh 2116 pass / 0 fail, wasm builds, fmt and markdownlint clean.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n---------\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>",
          "timestamp": "2026-08-28T08:08:36+05:30",
          "tree_id": "90fe886bacebd6c541f283d06be5a7694a9cb2c1",
          "url": "https://github.com/kaappi/kaappi/commit/10a5be17f03f637e9a8a17406f97f2b3e26bfe82"
        },
        "date": 1787887120690,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.103453,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.90543,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.415272,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.266449,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004812,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.045195,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.234533,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.044868,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.307939,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.902232,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.253664,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.254068,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.301656,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.911931,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.037892,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "8f75f63e03fd40dfb3e37d8a592fc063aa66afa1",
          "message": "Re-port SRFI 241 and 202 on er-macro-transformer (KEP-0006 step 5) (#2398)\n\n* Re-port SRFI 241 and 202 on er-macro-transformer\n\nKEP-0006's implementation-plan step 5 named these two libraries as the\nacceptance test for er-macro-transformer: both were pure-syntax-rules\nports whose every helper macro carried a custom %%% ellipsis identifier\njust so the literal ... token could be matched as data. Each library is\nnow a single procedural transformer that compiles the pattern language\nby ordinary list processing, which lifts all four of the 241 port's\ndocumented limitations: arbitrary sub-patterns under an ellipsis,\nmandatory patterns after the ellipsis in lists and vectors, the SRFI's\nellipsis-aware quasiquote inside clause bodies (a let-syntax rebinding\naround each body), and the spec's cata evaluation order (operators run\nonly after the guard passes). The 202 re-port also gains SRFI 2's bare\nbound-variable claw and vector patterns in quasiquoted claws.\n\nAll pattern keywords are recognized through the ER compare, which is\nhygiene-stripped name equality; the findings on where that is and is not\nsufficient are recorded on kaappi#2388. The stale SRFI 148 header claim\nthat Kaappi \"has no er-macro-transformer support\" is corrected in\npassing (false since v0.22.0); 148 keeps the reference's portable branch\nbecause the Chibi branch needs a binding-aware compare.\n\nCloses #2391\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Address #2398 review: expansion-error and bundle-tier coverage\n\nThree review findings on the SRFI 241/202 er-macro re-port:\n\n- tests/scheme/errors/srfi-241-expansion-errors-2391.sh: the six verr\n  diagnostics in lib/srfi/241.sld (misplaced ellipsis, multiple\n  ellipses, invalid cata pattern/variable, and %match-qq's two template\n  shape errors) fire while match expands, so the SRFI-64 suite's runtime\n  guards can never reach them; one malformed form per diagnostic,\n  asserting nonzero exit and the KP2002 message text.\n\n- tests/scheme/compile/srfi-241-202-bundle-2391.sh (+ fixture): the\n  compiled-artifact smoke the .scm suites cannot provide. kaappi compile\n  refuses .sld-resolved imports (kaappi#1743), so the route is the\n  -Dbundle standalone binary, built with bundle_fixture_binary's\n  same-source/isolated-prefix discipline but a separate fixture — srfi\n  imports would make the shared bundle-replay .sbc bytes depend on the\n  srfi search path. Interpreter output is the oracle; both tiers agree\n  on all three lifted-capability lines.\n\n- docs/dev/srfi-implementation-notes.md: the engine-facts intro\n  over-attributed coverage. The SRFI suites cover the macro behavior and\n  the new errors suite the diagnostics; KAAPPI_HOME isolation and .sld\n  staleness are library-cache-1888.sh's; the zig-out/lib refresh step is\n  an uncovered workflow footgun and now says so.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n---------\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-28T08:09:00+05:30",
          "tree_id": "cf44b40bd5d5109e12047a2444fb75e00dec98be",
          "url": "https://github.com/kaappi/kaappi/commit/8f75f63e03fd40dfb3e37d8a592fc063aa66afa1"
        },
        "date": 1787887483809,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.911538,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.111721,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.568316,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.858297,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.005193,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046497,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.284519,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.060965,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.389327,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.120265,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.657007,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.305638,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.619068,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.808293,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045658,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "5e1680f22dd435085b7c500e5c24c21dd2da60db",
          "message": "Add the -Dgc-stress rooting tests for procedural-transformer calls (#2399)\n\n* Add the -Dgc-stress rooting tests for procedural-transformer calls\n\nKEP-0006 step 1 shipped its reentrant-VM-during-compile machinery for\ner-macro-transformer without the exit-criterion test proving the rooting\nholds under forced collection. The no-collect window in\ncompiler_macro.zig, the pushRoot discipline in\nexpander.expandProceduralMacro, the extra_roots append, and the\ndefine-time rooting around vm.evalDatumForMacro all existed, but nothing\nexercised them with collections firing around the transformer call.\n\nThree new tests drive an allocation storm (scaled down under\n-Dgc-stress=true, where every allocation collects) through each rooting\nseam: the use path (transformer conses heavily, then re-reads the input\nform and embeds fresh material in the expansion the compiler keeps\nwalking after the deferred collections fire), the define-time path\n(transformer-spec eval allocates with collections live), and the SRFI\n213 procedure-result re-entry hop (both hops allocate across the rooted\nform and lookup values).\n\nThe SRFI 211/213 engine-seam block moves from tests_macros.zig (already\nover the 1500-line policy) into the new tests_macros_procedural.zig so\nthe new tests do not grow the oversized file.\n\nCloses #2390\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Reword the #2390 test banner to what mutation testing actually pinned\n\nThe PR #2399 review mutation-tested the claim that a single unrooted\nvalue in the transformer-call stretches panics deterministically: it\nholds for the no-collect window (bypassing it panics all three tests),\nbut removing the three individually-named explicit roots at once still\npasses, because each value stays reachable through a redundant cover.\nPresent the window as the primary protection and the explicit roots as\ndefense-in-depth these tests corroborate but do not isolate, and record\nwhy an exclusive-hold construction is not reachable from Scheme-level\ntest code: the covers are the compile boundary's source-tree rooting and\nthe allocators' argument auto-rooting custody chain (not the VM register\nfile, which markVmRoots only marks for live frames), and breaking that\nchain depends on compiler-internal allocation ordering.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n---------\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-28T08:09:16+05:30",
          "tree_id": "cb8dcefde91d6010b05361c4e1f8a0eecdce795d",
          "url": "https://github.com/kaappi/kaappi/commit/5e1680f22dd435085b7c500e5c24c21dd2da60db"
        },
        "date": 1787888694526,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 5.301568,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.070496,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.571073,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.012681,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004882,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.04755,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.306029,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.055188,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.751077,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.234147,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.6415,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.280347,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.715589,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.673485,
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
          "id": "50e84a9d70ed2408cd1251e127bc19aeecbc582a",
          "message": "Add the kaappi-shared-channels cond-expand feature identifier (KEP-0004 Phase 2) (#2402)\n\n* Add the kaappi-shared-channels cond-expand feature identifier (KEP-0004 Phase 2)\n\nThe gate cleared long ago — kaappi#1487 and #1489 closed 2026-07-13/14 and\nKEP-0002 fully shipped in v0.15.0/v0.16.0 — but the identifier never\nlanded. It rides the same non-wasm branch as kaappi-threads: cross-thread\nchannel promotion requires OS threads, and on wasm32-wasi the notifier is\na no-op nothing ever calls (KEP-0002 §5).\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Add kaappi-shared-channels to the BSD docs' capability lists\n\nEach of the three BSD pages enumerates the capability identifiers to say\nnone is gated on that platform. The claim stays true — all five are\npresent on every BSD — but the list would have under-counted from this\nPR onward.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n---------\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-28T06:59:17Z",
          "tree_id": "36cc46ade78417a952681021970f8c3fd3320414",
          "url": "https://github.com/kaappi/kaappi/commit/50e84a9d70ed2408cd1251e127bc19aeecbc582a"
        },
        "date": 1787902769782,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.878937,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.176818,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.537549,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.784688,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.005165,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.0457,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.281555,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.054009,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.846159,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.086345,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.525275,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.253145,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.619477,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.013566,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.041699,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "a12406bde7f741bfe9a01041bf87ff4f68cf211b",
          "message": "Make er-macro compare binding-aware free-identifier=? and land the four-quadrant test (#2401)\n\n* Make er-macro compare binding-aware free-identifier=? (#2388)\n\nKEP-0006 (as amended 2026-08-27) resolved Unresolved question 2 against\nSRFI 211's contract: compare is free-identifier=? — \"the two identifiers\ndenote the same binding, or both are unbound.\" The shipped compare was\nhygiene-stripped name equality. The #2398 re-port evidence (SRFI 241/202)\nshowed name-based compare held up in real library code but recorded\nconcrete observable weaknesses (a shadowed values claw, macro-generated\nsame-spelled identifiers), so this implements option (a): reuse the\nliteral-matching machinery syntax-rules already has, exposed a second\nway.\n\n- erCompareFn now classifies each argument (use-site local slot via\n  UseSiteBindingCheck.resolve / def-env binding identity / free) and\n  compares, mirroring matchPattern's literal branch outcome for outcome.\n  Because symbols are interned, a bare-rename product is the same object\n  as a use-site token of that spelling, so erRenameSymbol records\n  identity entries under the invocation scope: the classic\n  (compare <token> (rename 'kw)) shape is recognized from the rename\n  record (order-independent), and two plain use-site tokens stay\n  reflexive — the pairwise input-comparison idiom keeps working.\n- Lands the KEP-0006 four-quadrant acceptance test that was never\n  written, as an ER/syntax-rules parity suite: every quadrant (else\n  fires; shadowed else refuses; macro-introduced else; the => variants\n  including macro-introduced => under shadowing) runs BOTH systems\n  against the same expected value — pinning KEP-0018 UQ6 (\"an ER macro\n  is exactly as hygienic as a syntax-rules one\") as a contract.\n- Flips the audit pin that existed precisely so a stronger compare\n  shows up as a test change, and updates the SRFI 211 .sld header and\n  srfi-implementation-notes accordingly (including the 241/202 keyword\n  bullet and the shared reserved-form deviation: a spelling the hygiene\n  engine keeps bare — else, _, ... — is shadowed by a use-site local for\n  macro-introduced occurrences in both systems; identifiers the engine\n  can mark, like =>, stay hygienic).\n\nA pre-existing vm.eval quirk uncovered while writing the Zig tests\n(keyword-name reuse across evals in one process -> bare CompileError;\nreproduces on origin/main) is filed separately as kaappi#2400; the new\ntests use unique names with a comment pointing there.\n\nCloses #2388\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>\n\n* Qualify the compare reflexivity claim in the docs (#2388)\n\nCodeRabbit review: two plain use-site tokens stay reflexive only for a\nspelling this invocation did not also bare-rename — a transformer that\nboth renames 'kw for its keyword checks and pairwise-compares use tokens\nof that same spelling under a local shadowing gets #f. The expander\ncomment already stated the qualified rule; align the .sld header and the\nimplementation notes with it.\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Address review: def-env rename agreement, rename-vs-rename reflexivity (#2388)\n\nTwo behavior fixes from the #2401 review:\n\n- A def-env-marked rename (#1812 branch of renameForHygiene, taken for a\n  name bound in the transformer's own library when used outside it) never\n  compared equal to a bare use-site reference, though both denote the\n  same imported binding. erCompareFn now answers that pair from the bare\n  side: equal when the use site can resolve the spelling (it is in the\n  use-site globals — the library was imported) and no local shadows it.\n  Regression-tested with a library-defined transformer in srfi211.scm's\n  t211 helperlib.\n- (compare (rename 'kw) (rename 'kw)) answered #f under a use-site local\n  shadow of the spelling, breaking free-identifier=? reflexivity for the\n  hoisted-rename style the 241/202 ports use. The naive args-equal guard\n  cannot work (the use token and the bare rename product are the same\n  interned object — that identity is quadrant 2's whole problem), so the\n  bare/bare branch instead consults whether the spelling occurs in the\n  macro-use input: occurrence means a use-site token is in play (the\n  quadrant rule applies); absence means both arguments are the\n  invocation's own rename products and compare is reflexive. The input is\n  reached through a pointer to expandProceduralMacro's rooted slot, so a\n  moving GC updates it.\n\nAlso from the review: the ER/syntax-rules parity guarantee is now stated\nfor the auxiliary-keyword spellings it actually covers (reserved forms,\nmacro keywords, gensym-marked renames), with the VOID-sentinel divergence\npinned as the boundary in srfi211.scm; and the three stale name-based\ncompare claims in lib/srfi/241.sld and lib/srfi/202.sld — which cited\nkaappi#2388 for the opposite semantics — are flipped, with 241's\nexported-bindings non-effect note re-reasoned (an exported binding is a\nglobal, and globals are not use-site local slots).\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Address second review round: bounded input walk, plainer docs (#2388)\n\n- erFormMentionsSymbol now hangs no more: R7RS datum labels make the\n  macro-use input genuinely circular (#2404), so the walk carries a node\n  budget and a depth cap (both non-allocating), with exhaustion counted\n  conservatively as occurrence — the quadrant rule then applies, refusing\n  under shadowing and never wrongly accepting. Regression test pins\n  termination on a circular input (a define initializer, not a\n  test-assert operand: wrapping a cyclic datum in a body-position macro\n  hits the pre-existing collectSetTargets hang, reproduced on origin/main\n  and noted on #2404).\n- The unsettled compare shape is now stated plainly instead of being\n  called \"the quadrant-2 case\": a spelling that occurs in the input AND\n  was bare-renamed this invocation, compared under a use-site local\n  shadow, is the demanded refusal when one argument is that input token\n  and a known-wrong (broken reflexivity) answer when both arguments were\n  the invocation's own rename products — interned symbols make the two\n  representationally identical, and a distinguishable wrapper for bare\n  rename products would break the compiler's bare matching of the\n  reserved forms macros emit (.sld header + implementation notes +\n  erCompareFn doc).\n- erDefEnvAgreesWithBare's comment no longer asserts an import that may\n  not have happened: the globals hit is the same class of\n  over-approximation the whole-def-env import copy makes (an unrelated\n  same-named use-site global answers #t too; verified against the\n  review's testlib4 probe).\n- lib-bound-var is now actually exported from (t211 helperlib), so the\n  def-env regression test covers the exported-binding path its label\n  claims (the free-ref planting path stays covered by lib-twice).\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Fix #2404 completely: bound collectSetTargets against cyclic macro inputs\n\nThe #2404 instance filed from the #2401 review (erFormMentionsSymbol)\nwas fixed by the previous commit; this closes the pre-existing member of\nthe same class found while verifying it: compiler.collectSetTargets\nwalks the macro-use form's cdr spine with no bound — the scan's depth\ncap counts only car recursion — so a cyclic macro operand re-emitted\ninto a body position (e.g. a test-assert operand) hung the compiler,\nreproducible on origin/main.\n\nBoth spine loops (the main walk and the let-syntax bindings walk) now\ncarry SET_SCAN_SPINE_CAP = 1M steps per list level. Exhausting it marks\nthe scan truncated on budgeted paths — the same\nloses-optimization-never-correctness degradation the expansion budget\nalready takes (set_targets_all boxing), with Part B correcting misses at\nreal-expansion time; null-budget callers (define-syntax specs, the LLVM\nbackend's scanSetTargetsWithoutMacros) just stop, taking the same\ncorrect-late path. One million per level is far beyond any real form\n(the suites' p99.99 prescan count is ~1.7k).\n\nFixed-arity patterns terminate at the pattern's end and ellipsis\npatterns at matchEllipsis's MAX_ELLIPSIS_VALUES cap — probed, both fine.\nRegression test: tests/scheme/hygiene/cyclic-macro-input-2404.scm covers\nthe scanner (fixed and ellipsis patterns), the compare walk, and the\ncombined test-assert wrapper shape; srfi211.scm's circular-compare test\nkeeps its define-initializer shape so it pins compare's walk alone.\n\n#2403 (erRenameDatum's root-stack abort on circular input) remains\ndeliberately untouched: rename has no finite answer for an unfoldable\ncycle, so its fix is a semantic decision belonging to that issue.\n\nCloses #2404\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Propagate set!-scan truncation on every caller (#2401 review)\n\nCodeRabbit review of the SET_SCAN_SPINE_CAP change: a null-budget scan\nthat hit the cap kept a partial target set with no signal — and a missed\nset! target leaves a local unboxed (continuation-unsafe, #1168) and\nfoldable (IR.isRedefined). The same exposure pre-dates the spine cap:\nthe depth cap also reported nothing on null-budget paths. Both are now\nclosed.\n\nSetScanBudget gains an `expand` flag, so a non-null budget no longer\nimplies \"speculatively expanding\": structure-only scans walk literally\n(the define-syntax/let-syntax shortcuts are outcome-equivalent there)\nand report depth/spine truncation like any budgeted scan. The callers:\n\n- Part B (Compiler.scanSetTargets in expandAndCompileMacroUse) now\n  propagates truncation to set_targets_all — the same\n  every-name-is-a-target conservatism the top-level pre-scan uses.\n- scanSetTargetsWithoutMacros (LLVM backend) returns the truncation and\n  its caller eval-fallbacks the whole form via makePassthrough — the\n  tier has no set_targets_all switch, and a passthrough form is compiled\n  by the full VM compiler with its own conservative machinery (same\n  action #2119 takes for continuation-capturing forms).\n\nThe define-syntax/let-syntax spec walks keep their structure-only,\nnon-propagating budget: a set! that only materializes when the spec's\nown macros run is caught at the macro's real use site, the documented\ncorrect-late path.\n\nTests (tests_prescan.zig): scanSetTargetsWithoutMacros reports\ntruncation on a cyclic form and does not hair-trigger on an ordinary\none; a wrapper-shape cyclic macro operand (the minimal form verified to\nhang origin/main — a plain top-level use never reaches the scan) keeps\nset! boxing correct under continuation capture. The cyclic hygiene\nsuite gains the wrapper shape and its comment now names it as the\ndiscriminator.\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Native tier: a truncated scan falls back for the rest of the program\n\nCodeRabbit follow-up on the truncation propagation: eval-fallbacking only\nthe truncated form left later forms folding against a possibly-stale\nprimitive table. The truncated form is VM-executed, so a macro-produced\n(set! + *) inside it rebinds at run time — but collectRedefinedNamesMacro\nAware can no more see through the truncation than the scan could, and\nkaappi compile never executes forms to find out; a later natively lowered\n(+ 5 2) then folded to 7 while the interpreter printed 10 (#2212's\ndivergence class, reopened through the truncation path).\n\nFrom the first truncated scan to the end of the file, every top-level\nform is now a passthrough (VM-evaluated; execution order preserved, so\nforms lowered before the truncation stay temporally correct). Only\npathological inputs reach the caps, so ordinary files keep their native\nlowering.\n\nRegression: tests/scheme/compile/native-truncated-scan-fallback-2404.sh —\ncyclic wrapper operand (the minimal scan-truncating shape), then a macro\nrebinding +, then a fold-sensitive (+ 5 2): both tiers must print 10.\nControls pin that the fallback is engagement-gated (no cyclic form ->\nunchanged lowering) and that plain arithmetic after a truncated form\nstill evaluates correctly.\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n---------\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-28T17:34:32+05:30",
          "tree_id": "c675e38c7acc25374ee11d43e3fbf7f854691f84",
          "url": "https://github.com/kaappi/kaappi/commit/a12406bde7f741bfe9a01041bf87ff4f68cf211b"
        },
        "date": 1787921429527,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.327067,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.829078,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.565135,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.964981,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004915,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.047647,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.303829,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.055613,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.812526,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.233283,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.65896,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.275451,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.70655,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.607185,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045183,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "cfbc99f036a6fe57512e5604893d0d5c2889fe4d",
          "message": "Implement SRFI 273: extensions to data (type-)checking (#2411)\n\n* Implement SRFI 273: extensions to data (type-)checking\n\nPortable (srfi 273) layered on (srfi 253): define-check, advisory\ndeclare-checked, define-values-checked (with real per-value checks,\nreceiving the form's values exactly once via call-with-values), and the\ncheck-impl? auxiliary syntax, which strips to its datum so an unknown\nimplementation-specific name is an unbound variable — the spec's\n(values-checked ((check-impl? uint)) -1) is an error here too. The\nlibrary re-exports the whole (srfi 253) vocabulary so importing it alone\nsuffices.\n\nThe => return-value checking SRFI 273 specifies for the 253 forms was\nalready folded into 253.sld by the original port (the SRFI 253 sample\nimplementation carries it) — the decision is recorded in\ndocs/dev/srfi-implementation-notes.md. What it lacked, now fixed there:\n\n- lambda-checked with empty or rest formals dropped the => clause on\n  the floor ((lambda-checked () => (integer?) ...)) expanded to a body\n  with a bare => in it); both shapes now check their returns.\n- Multi-value => checks never worked: the terminal expansion spliced N\n  predicates into values-checked against a single value expression —\n  an ellipsis-count mismatch that compiled to garbage. New\n  %check-results wraps one (lambda (v . more)) layer per predicate\n  (hygiene gives each recursive level fresh names), rotating each\n  checked value to the tail so value k meets predicate k and the order\n  is restored at the outermost layer; the predicate list is reversed\n  first so the innermost layer carries the first predicate. A count\n  mismatch is an error, as values-checked's own \"number of values and\n  predicates should match\" already is.\n\nTests: new tests/scheme/srfi/srfi273.scm (102 assertions incl. the\npairing pins that fail under the old layering), plus define-checked =>\ncoverage in srfi253.scm. Counts updated everywhere (179 SRFIs, 163\nportable); kaappi features and the final-status guard both pick 273 up\nfrom the .sld.\n\nCloses #2408\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Address review: => fast path, count-first gate, message-pinned tests\n\n- Single-predicate => now expands to the same let shape values-checked\n  uses instead of the call-with-values tower: the common case is back at\n  parity with main (46k vs 39k jiffies per 300k calls here, was 989k).\n  Like values-checked it does not count values itself — a body returning\n  zero or several still fails the predicate, because Kaappi propagates\n  multiple values through a single-variable let binding and no predicate\n  matches the resulting values object.\n- %cr-gate now checks the value/predicate count BEFORE the rotation\n  tower runs, so a short or long value list is diagnosed as \"number of\n  values and predicates should match\" whatever the predicates are,\n  instead of a mispaired predicate firing first with a misleading\n  message. The tower rides in the gate's body — as a receiver operand\n  it would be evaluated eagerly, running checks before values exist\n  (caught by the suite on the first cut).\n- The count-mismatch tests assert on that error message (via a guard\n  helper, since test-error matches conditions, not messages) with\n  distinct predicates in both directions, so neither can pass via a\n  predicate failure instead.\n- check-case assertions now use test-equal on the dispatched symbol —\n  'int/'other and 'small/'other pairs — so a wrong clause choice fails\n  the test instead of passing on any truthy body (five sites).\n- declare-checked declares => as a literal, matching every other\n  =>-aware macro of the port, so the return-check clause cannot\n  silently capture an unrelated form in that position.\n\nrun-all.sh: 724 scheme files + R7RS 1395 pass; srfi273 105, srfi253 108.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n---------\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>",
          "timestamp": "2026-08-28T17:37:08+05:30",
          "tree_id": "5455288fbaa1e7c9f7012f50b7bdb0249cb5ea1d",
          "url": "https://github.com/kaappi/kaappi/commit/cfbc99f036a6fe57512e5604893d0d5c2889fe4d"
        },
        "date": 1787922065661,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 2.919182,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 5.685519,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.384854,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.081951,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004374,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.03477,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.207867,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.038399,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.171258,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.827322,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.167911,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.223173,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.222642,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.804942,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.035017,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "c92284a63b5a287a5d563785ccf8d2d75de7ed0c",
          "message": "Make er rename reject a circular datum instead of aborting (#2403) (#2406)\n\n* Make er rename reject a circular datum instead of aborting (#2403)\n\n`rename` on a circular macro-use input recursed forever, pushing two GC\nroots per level, until the root stack panicked — uncatchable, process\ngone, from five ordinary lines (`(m #0=(zz . #0#))`).\n\n- expander.erRenameDatum walks with a visited-on-active-path set keyed on\n  Object address (stable in this non-moving GC). Only a back-edge is\n  refused: shared-but-acyclic `#1=` data still renames. A cycle raises a\n  catchable InvalidArgument whose message reaches the user through the\n  new globals.set_error_detail_for_macro hook (write-side sibling of\n  error_detail_for_macro; the expander cannot import vm.zig), so a\n  transformer's own guard sees the condition and an uncaught one reports\n  as syntax-error[KP2002] instead of aborting.\n- compiler.collectSetTargets needed guards for that diagnosis to surface\n  at all: the set! pre-scan expands macros best-effort, swallows the\n  rejection, and kept walking the same cycle. Rebased over #2401 (whose\n  SET_SCAN_SPINE_CAP bounded the spine with a step count): the main\n  spine walk now runs Floyd's tortoise-and-hare instead — exact (a cycle\n  is caught in ~2λ steps, not after a million, and a legal over-cap\n  spine is walked fully rather than truncated), since every body path\n  that resumes iteration advances exactly one cdr (the let-syntax\n  two-cdr jump became a sub-walk for that reason); the bindings loop\n  keeps #2404's step cap (the one inner spine the tortoise does not\n  cover); and the walk's self-recursions charge the depth cap so a\n  car-side cycle stops at the cap instead of overflowing the native\n  stack.\n\nThe macro-free circular-code-in-code-position family (IR fold abort,\ncompileSyntaxBody hang) is unchanged and tracked as #2405. #2404 itself\nwas fixed in #2401 (bounded erFormMentionsSymbol) and is regression-\ncovered here only through that PR's tests, which this rebase keeps\ngreen.\n\nTests: unit (tests_macros_procedural, tests_prescan), Scheme\n(srfi211.scm guard/shared cases, errors/er-rename-circular-2403.sh\nmessage+exit pin). Full suites green on the rebased tree: unit\n1890/1897 (+7 skip), gc-stress 1897/1897, run-all 2121/2121, R7RS\n1395/1395.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Tighten circular-rename exit assertion to require status 1 (#2406 review)\n\nThe uncaught KP2002 path must be fatal: a CLI regression that printed\nthe diagnostic but returned success (exit 0) would have passed the old\n0-or-1 check.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n---------\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>",
          "timestamp": "2026-08-28T20:46:22+05:30",
          "tree_id": "84b9cac364a44000602a256a9d75b308c03ad479",
          "url": "https://github.com/kaappi/kaappi/commit/c92284a63b5a287a5d563785ccf8d2d75de7ed0c"
        },
        "date": 1787932636792,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.222731,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.365049,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.584309,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.99759,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.005004,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.047454,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.304817,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.055216,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.837522,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.183098,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.650956,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.283234,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.709,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.596906,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045399,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "f0937b21fe390cfd4434777e612de64f0ffba17f",
          "message": "Implement SRFI 274: extended list conversion procedures (#2412)\n\n* Implement SRFI 274: extended list conversion procedures\n\nPortable port of Peter McGoron's reference implementation (MIT); no\nengine changes. Every conversion gains optional start/end range\narguments and accepts dotted and circular lists whenever end is\nsupplied, never inspecting the cdr of the endth pair.\n\nThe sub-library layout follows the SRFI itself rather than extending\n(scheme base): the extended names deliberately shadow existing\nbindings, and since v0.22.1 Kaappi enforces R7RS 5.2 (a double import\nof one identifier with different bindings is an error), the extended\nvariants must live in libraries a program opts into. The bare\n(srfi 274) is a thin alias re-exporting (srfi 274 base) so srfi-274\nanswers as a cond-expand feature id and the SRFI is counted by\n'kaappi features'.\n\nTwo port adaptations, both recorded in srfi-implementation-notes.md:\nthe reference's ideque-unfold / <type>vector-unfold constructions are\nreplaced by handing the bounded, always-proper range from (srfi 274\nbase)'s list-copy to the underlying one-argument converter — Kaappi's\n(srfi 134) exports no ideque-unfold, and importing all twelve full\n(srfi 160 <type>) surfaces for their unfold would be heavy. One\nleniency remains: (srfi 274 134)'s start-only improper-list case is\nsilent because Kaappi's simplified (srfi 134) never walks its input —\ninherited from that port, not from SRFI 274.\n\nFixes #2409\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Address review: string error messages, correct who, single-walk ranges\n\n- (srfi 274 internal): errors now build a \"<who>: <msg>\" string message\n  (R7RS 6.11) instead of passing the who symbol to error, matching every\n  other (error ...) site under lib/; new range-list helper checks a range\n  once under the caller's name and copies it. That replaces the double\n  argcheck! walk in (srfi 274 160 base) and (srfi 274 134), and gives\n  list->string's range errors their own name instead of list-copy's\n  (they surfaced through the list-copy delegation).\n- tests: actually load the bare (srfi 274) alias — cond-expand's\n  (library ...) clause only probes existence, never the body; replace the\n  vacuous per-type binding assertion (same identifier on both sides) with\n  an eqv? identity check against a prefixed per-type import; pin the\n  three documented leniencies (circular streams/generators without end\n  are infinite — stream-ref based, since stream->list would not\n  terminate; 134 start-only improper is silent) and pin the new\n  error-message shape and list->string attribution via guard.\n- CONFORMANCE: fix the portable-SRFIs heading count missed by the\n  179->180 sweep (167 SRFIs: 164 importable); drop (srfi 274 internal)\n  from the importable sub-library catalogues here and in the notes\n  header — internal is plumbing, its own header says not to import it.\n- notes: the improper-without-end bullet now names all three silent\n  paths (134 start-only; 41/158 circular without end, where laziness\n  means nothing walks off the end) instead of only 134's; the\n  port-adaptation wording follows range-list.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Fix the last stale features count: 12 + 164\n\nCodeRabbit caught that CLAUDE.md's features note (line 196, mirrored\nthrough the AGENTS.md symlink) still said 'kaappi features --json'\nreports 'the 12 + 163' after the SRFI 274 port made it 164 portable\nlibraries. The 179->180 / 163->164 sweep missed this instance because\nit greps for '163 portable', not '12 + 163'. Swept the tree for every\nremaining '163'/'179' variant; this was the only one left.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n---------\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>",
          "timestamp": "2026-08-28T22:20:38+05:30",
          "tree_id": "638d68e209d7a5e6628ad266d85e1341826912d0",
          "url": "https://github.com/kaappi/kaappi/commit/f0937b21fe390cfd4434777e612de64f0ffba17f"
        },
        "date": 1787938338831,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.915106,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.603323,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.559845,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.846891,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.005174,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046252,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.286355,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.053702,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.395992,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.140196,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.628642,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.300557,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.615564,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.809154,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.04561,
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
          "id": "2575692140a9f44f52d68408aa1822e298c11f59",
          "message": "Bump the github-actions group with 3 updates (#2419)\n\nBumps the github-actions group with 3 updates: [xyzzylabs/setup-zig](https://github.com/xyzzylabs/setup-zig), [vmactions/freebsd-vm](https://github.com/vmactions/freebsd-vm) and [vmactions/netbsd-vm](https://github.com/vmactions/netbsd-vm).\n\n\nUpdates `xyzzylabs/setup-zig` from 1.0.2 to 1.0.3\n- [Release notes](https://github.com/xyzzylabs/setup-zig/releases)\n- [Changelog](https://github.com/xyzzylabs/setup-zig/blob/main/CHANGELOG.md)\n- [Commits](https://github.com/xyzzylabs/setup-zig/compare/09d85d9dbb73308882e7a26e61a8f706eed40df1...df7066a4910fe13f4643390dbbd8ce6a785fff63)\n\nUpdates `vmactions/freebsd-vm` from 1.5.3 to 1.5.5\n- [Release notes](https://github.com/vmactions/freebsd-vm/releases)\n- [Commits](https://github.com/vmactions/freebsd-vm/compare/83b151f58c6047089f4c80eb5ba2039d158ce093...f0552d3b69211736abd97f02ff3d4674c56b73b1)\n\nUpdates `vmactions/netbsd-vm` from 1.4.6 to 1.4.7\n- [Release notes](https://github.com/vmactions/netbsd-vm/releases)\n- [Commits](https://github.com/vmactions/netbsd-vm/compare/00081e82b14bc40114eb97f32b4455306828516b...6334c835de4c04a59fe59f0f8f071e02a2f0bab3)\n\n---\nupdated-dependencies:\n- dependency-name: xyzzylabs/setup-zig\n  dependency-version: 1.0.3\n  dependency-type: direct:production\n  update-type: version-update:semver-patch\n  dependency-group: github-actions\n- dependency-name: vmactions/freebsd-vm\n  dependency-version: 1.5.5\n  dependency-type: direct:production\n  update-type: version-update:semver-patch\n  dependency-group: github-actions\n- dependency-name: vmactions/netbsd-vm\n  dependency-version: 1.4.7\n  dependency-type: direct:production\n  update-type: version-update:semver-patch\n  dependency-group: github-actions\n...\n\nSigned-off-by: dependabot[bot] <support@github.com>\nCo-authored-by: dependabot[bot] <49699333+dependabot[bot]@users.noreply.github.com>",
          "timestamp": "2026-08-29T05:48:24+05:30",
          "tree_id": "f061f6f2cd316256063aa5c844ef2502b4dff838",
          "url": "https://github.com/kaappi/kaappi/commit/2575692140a9f44f52d68408aa1822e298c11f59"
        },
        "date": 1787965072673,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.426811,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.751509,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.574285,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.976544,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004966,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.047922,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.304087,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.05576,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.787602,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.233945,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.728096,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.286003,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.761274,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.747289,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045303,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "c52d585bc1c50be3bcbde3bab6f1a18ce5fd9c64",
          "message": "Avoid float constant-pool in angleFn on wasm32-wasi (#2421) (#2425)\n\n* Avoid float constant-pool in angleFn on wasm32-wasi (#2421)\n\nLLVM cannot select an i32 ConstantPool<float 0.0> node under baseline\nwasm in ReleaseSafe, so the generic 'zig build -Dtarget=wasm32-wasi'\ncross build of kaappi and kaappi-lsp aborted the compiler inside\nprimitives_numeric.angleFn. Only the flonum arm materialized a float\nconstant into atan2; branching on the sign bit instead is bit-exact\nwith atan2(0.0, f) for every input (positive/negative, both zeros,\ninfinities, NaN propagation) and sidesteps the constant pool entirely.\n\nThe two paths CI already built — 'zig build wasm' (ReleaseSmall) and\n'zig build test -Dtarget=wasm32-wasi' — were green all along; only the\ngeneric ReleaseSafe -Dtarget shape hit the bug, so the wasm job gains a\ncompile-only canary for exactly that shape, and a unit test pins the\nrewritten arm to atan2's exact results.\n\nCloses #2421\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Run the wasm32-wasi canary last so it cannot shadow the tested artifact\n\nThe kaappi#2421 compile canary (zig build -Dtarget=wasm32-wasi) installs\na ReleaseSafe zig-out/bin/kaappi.wasm, overwriting the ReleaseSmall\nbinary that 'zig build wasm' produced. Placed mid-job it let the four\nlater wasmtime steps (parallel pool, platform gates, library-load,\ncommand-line) and the cross-tier differential silently exercise the\nwrong binary. Move it to the very end of the wasm job — after the\ndifferential — and note in its comment that it must stay last. The\nintervening native-oracle 'zig build' installs plain 'kaappi', not\nkaappi.wasm, so there is no other collision.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n---------\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-29T13:55:01+05:30",
          "tree_id": "87dbfa4b7a6195e37e1e98504eac57dff43d336f",
          "url": "https://github.com/kaappi/kaappi/commit/c52d585bc1c50be3bcbde3bab6f1a18ce5fd9c64"
        },
        "date": 1787994044300,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.042955,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.579005,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.433082,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.182863,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004052,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.035862,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.22375,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.042076,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 1.872255,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.890969,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.247635,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.241346,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.287576,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.437597,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.036657,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "cc636d9c3afd7f74966022ccfbf3a3f6161ce012",
          "message": "Set FD_CLOEXEC on isocline history/debug files (#2423) (#2426)\n\nThe vendored isocline opens its history file (history_load/history_save)\nand its IC_DEBUG_TO_FILE debug log (debug builds only) with plain fopen,\nwhose descriptors are inheritable across exec. Once KEP-0022's\nspawn-process lands, that violates the guarantee that a child inherits\nonly the three stdio slots: Linux is exposed, while macOS is masked by\nPOSIX_SPAWN_CLOEXEC_DEFAULT. All four handles are transient (each fopen\nis paired with an fclose in the same function), so the exposure is a\nspawn racing one of those open windows from another thread — narrow, but\nreal, and setting the flag is correct hygiene regardless.\n\nThis is KAAPPI PATCH 6 to the vendored copy: after each successful\nfopen, fcntl(fileno(f), F_SETFD, FD_CLOEXEC), guarded #ifndef _WIN32\n(Windows has no fcntl; the wasm32-wasi build never compiles isocline).\nDocumented in vendor/isocline/PATCHES.md so it is re-applied on the next\nvendor update, and CLAUDE.md's patch count is brought up to date (it\nstill said four; main already carried five).\n\nNo regression test: every one of these fds is closed before the isocline\nAPI call returns, so FD_CLOEXEC on it cannot be observed from outside\nwithout interposition. The KEP-0022 Phase 1 fd-hygiene suite (#2414) is\nthe designated end-to-end guard once spawn-process exists.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-30T00:03:49+05:30",
          "tree_id": "fecdcc58b199985efb29cfad63b1e01324c9bbfc",
          "url": "https://github.com/kaappi/kaappi/commit/cc636d9c3afd7f74966022ccfbf3a3f6161ce012"
        },
        "date": 1788030697631,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.047147,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.888103,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.439513,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.183253,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.003961,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.036435,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.222613,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.042684,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 1.900915,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.875957,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.237343,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.240137,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.264126,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.430175,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.036253,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "4740b545c8d7fe4556891919f140aff083491d84",
          "message": "Restore fiber state on every wait error exit; cut the 2200 compile test to one build (#2429, #2430, #2431) (#2432)\n\n* Restore the waiting fiber's window on every runSchedulerStep exit (#2429)\n\nrunSchedulerStep restored `me` in its epilogue only, and five `try`s inside\nthe dispatch loop return without ever reaching it: parkOnReactor,\nrestoreFiber(next_idx), and the three saveCurrentFiber calls on the\nYielded, errored-dispatch and completed-dispatch paths. All five surface\nVMError.OutOfMemory, which is catchable -- unlike the Terminated return\nabove them, which errors.isUncatchable unwinds past every handler.\n\nBy the time the three saveCurrentFiber calls run, restoreFiber has already\nloaded a SIBLING's registers, frames, handler stack and wind stack into the\nVM, and saveCurrentFiber only copies VM->fiber; nothing puts `me` back.\nparkOnReactor is reached at the top of a later iteration with that same\nsibling state still loaded. Returning OOM from any of them therefore left\nvm.current_fiber, sched.current_idx and the whole VM window belonging to the\nsibling -- and a Scheme `guard` that caught the OOM resumed `me`'s bytecode\nagainst another fiber's registers. That is the #1487\ndispatch-from-stale-snapshot corruption reached by a different route, in the\nsingle shared body behind channel-receive/-send, fiber-join, thread-join!,\nmutex-lock!, condition-variable waits and thread-sleep!.\n\nAn errdefer declared right after the entry saveCurrentFiber now runs the\nepilogue's restore on every error exit. It is declared before the `driving`\nand driving_waits defers, so on unwind it runs after both -- the same order\nthe normal epilogue sees. restoreFiber's `catch {}` cannot fire: its four\nensureXxxCapacity calls each return early when the need is already met and\nnever shrink, and `me` was current on entry, so the VM stacks were already\nlarge enough for the snapshot saveCurrentFiber had just taken of them.\nSwallowing is the right failure mode regardless -- the capacity checks\nprecede every memcpy, so a failure is all-or-nothing and leaves exactly the\npre-fix state, and returning a second error (or panicking) while already\nunwinding an allocation failure has nothing better to offer.\n\nThe regression test drives the loop directly and forces the error exit with\nTerminated rather than an injected OOM. Terminated reaches the identical\nexit deterministically, and the fix is the one errdefer covering every error\nreturn rather than a per-error patch. gc.oom_countdown could not have driven\nit in any case: the OOM here comes from ensureXxxCapacity/growFiberXxx,\nwhich allocate from the raw allocator the injector does not count. Two\nspinning siblings rather than one, because thread-yield! is advisory and\nno-ops unless some other fiber is runnable -- and `me` is excluded from that\nfor the whole drive, so a lone sibling never yields back and spins inside\nrunUntil forever.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-Authored-By: Claude <noreply@anthropic.com>\nClaude-Session: https://claude.ai/code/session_016mKdjyytpEKCSU2hepD21M\n\n* Unpark the fiber when a SRFI-18 wait errors out (#2430)\n\nthread-join!'s fiber path, mutex-lock! and mutex-unlock!'s\ncondition-variable branch each arm the parked state -- `.waiting`,\n`timed_out`, `waiting_on`, a #1530 waiter_index enrolment and, when timed, a\nreactor timer -- and then reached both `try ctx.reactor.addTimer` and `try\nrunSchedulerStep` with nothing to undo it. Both failure sources return\ncatchable errors, so a Scheme `guard` could resume on a fiber the scheduler\nstill believed was parked. \"Running fiber marked parked\" is the precondition\nfor the #1487 dispatch-from-stale-snapshot corruption, and the waiter_index's\ndeliberate tolerance of a stale entry (indexWakeOn revalidates\n`status == .waiting`) is exactly what a lying `.waiting` defeats -- clearing\nthe status is therefore also what retires the index entry, so no explicit\nde-enrolment is needed.\n\nthreadJoinFn additionally never called removeTimer on its error path, so a\npending deadline could outlive the fiber and later fire against whatever\naddFiber reused that slot for. It was also missing the success-path\nremoveTimer its two siblings have: a local wake cancels the timer for us, but\nclearing deadline_ns without it strands any that survived -- and a null\ndeadline_ns is precisely what stops a later cleanup from finding it.\n\nPR #2428 introduced this shape for the one site it added\n(parkForThreadStatus), as a local struct. That becomes the shared\nunparkOnError helper and the three remaining sites errdefer it.\n\nAlso barriers the three sites' `waiting_on` stores, matching the channel\nwaits and parkForThreadStatus. Not a live bug -- a scheduler-resident fiber\nis marked unconditionally every collection via markFiberState, and\nreferencesYoung's fiber arm documents the remembered-set path as\nbelt-and-braces -- but residency ends the moment retireSlot runs, and the\nbarrier is a deduplicated append.\n\nThe regression tests reach the error exits through a SRFI 181 custom port\nwhose read! callback blocks: a real program raising a real catchable error\n(runSchedulerStep's own custom-port-callback guard), and deterministic where\nthe OOM the issue describes has no reproducer. `waiting_on` is what\ndiscriminates, since that guard already restores status and timed_out and\ndrops the timer before returning; all three tests fail pre-fix with it still\nholding the joined fiber, the mutex, or the condition variable. `status` is\ndeliberately not asserted even though it is the field the issue names:\nvm_calls.prepareTopLevelFrame leaves the main fiber `.completed` when its\nform finishes, so by the time eval returns it reads the same either way.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-Authored-By: Claude <noreply@anthropic.com>\nClaude-Session: https://claude.ai/code/session_016mKdjyytpEKCSU2hepD21M\n\n* Cut compile-define-values-order-2200.sh to one full build (#2431)\n\n`test (ubuntu-latest, Debug)` -- a required check -- intermittently failed\nwith this script killed at the 600s KAAPPI_SHELL_TEST_TIMEOUT, roughly one\nrun in fourteen on main.\n\nNot a Debug-build cost: the script never builds Debug. build.zig defaults to\nReleaseSafe and the script ran a bare `zig build`, so on that leg it built\nReleaseSafe artefacts into a cache holding only Debug ones -- three full COLD\nbuilds (an interpreter to produce the .sbc, then one `zig build -Dbundle=`\nper bundled program). The ReleaseSafe legs prime that cache with the job's\nown build first, which is why only the Debug leg ever reached the ceiling,\nand why it was intermittent rather than reliable.\n\nThree changes, all aimed at the build count rather than the timeout:\n\n  * fixture_interpreter in shell-common.sh -- the \"build an interpreter with\n    the same build id as the bundler\" step (#1930) extracted from\n    bundle_fixture_binary and shared. The first caller in a run pays for it;\n    the rest get a Zig cache hit and a no-op reinstall.\n\n  * One bundled program instead of two. The repro and the control that\n    proved the fix was not an over-restriction fold into a single file: the\n    define-values depends on an earlier top-level define, and the file\n    imports (scheme write) for its display, so an artifact that hoisted the\n    define-values dies on `undefined variable 'x'` and one that dropped the\n    import from the preamble dies on `display`. vm_eval.topLevelHead\n    classifies purely on the head symbol, with no dependence on whether an\n    import has been seen, so folding them changes nothing about which path\n    either form takes.\n\n  * -Doptimize=ReleaseSafe named explicitly on every build. It is already\n    the default, so nothing compiles differently -- but naming it is what\n    keeps these builds on one cache key instead of inheriting whatever mode\n    a job happens to pass.\n\nrun-all.sh's longest-first classifier learns the new helper's name, so a\nfuture script that only calls fixture_interpreter still sorts early.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-Authored-By: Claude <noreply@anthropic.com>\nClaude-Session: https://claude.ai/code/session_016mKdjyytpEKCSU2hepD21M\n\n* Address PR #2432 review\n\nFour findings, all confirmed against the code.\n\nWithdraw the waiter_index enrolment when a park is undone. Clearing `status`\nstops a stale entry ever waking the wrong fiber -- `indexWakeOn` validates\nevery index it walks -- but it does not remove it, and only a later wake\nnaming the same key would. A park abandoned on an object nothing ever wakes\n(a condition variable nobody signals, a mutex nobody unlocks, a fiber that\nnever completes) therefore stranded one map key and list for the scheduler's\nlifetime, one per failure on a fresh object. `markRoots` does not trace those\nkeys either, so clearing `waiting_on` left them unrooted garbage that could\nnever be matched again. New FiberScheduler.withdrawWaiter is enrollWaiter's\ninverse; unparkOnError calls it before clearing `waiting_on`, since that field\nis the key. The three regression tests now assert both that no key lists this\nfiber and that the failed park added no net key -- a before/after delta rather\nthan an empty-index check, because mutex-lock!'s holder fiber is legitimately\nparked on a channel and owns a key of its own. Verified to fail without the\nwithdrawal (`indexed=true`, with `waiting_on` already VOID).\n\nStop fixture_interpreter printing its path. Every caller had to wrap it in a\ncommand substitution, where Bash keeps `$$` at the outer script's pid -- so\nthe pid build_lock recorded named a process that was not the one holding the\nlock, and the waiter's steal-a-dead-holder check was reasoning about the wrong\nprocess. It now builds and returns status only; fixture_interpreter_path is a\nseparate pure function, safe anywhere. build_unlock is ownership-checked to\nmatch: a bare `rm -rf` let a late holder whose lock had already been stolen\ndelete the NEW holder's lock and admit a third writer to the shared prefix.\n\nGive fixture_interpreter_path the `.exe` suffix on Windows, where\n`zig build --prefix` installs `kaappi.exe`. The build check tests the path\nwith `-x`, and MSYS appends `.exe` when executing but not when a test operator\nnames the file, so the bare spelling reported a failed fixture build on a\nWindows box holding a perfectly good interpreter.\n\nMake the compile test's import control real, by importing `(srfi 8)` and using\n`receive`. The reviewer is right that `display` proved nothing -- it is\nexported from `(scheme base)` too -- but `write-simple` would not have fixed\nit: every BUILT-IN library's bindings are also ambient in script mode, so that\nprogram runs identically with the import line deleted outright. Measured, not\nassumed. `receive` comes only from lib/srfi/8.sld and is unbound without its\nimport, so the control now fails if the preamble stops carrying imports.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-Authored-By: Claude <noreply@anthropic.com>\nClaude-Session: https://claude.ai/code/session_016mKdjyytpEKCSU2hepD21M\n\n---------\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-authored-by: Claude <noreply@anthropic.com>",
          "timestamp": "2026-08-30T09:19:45Z",
          "tree_id": "4b7b96ee79ecc4c4b0eca616bfebc59df178e24a",
          "url": "https://github.com/kaappi/kaappi/commit/4740b545c8d7fe4556891919f140aff083491d84"
        },
        "date": 1788083900567,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.321766,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.887564,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.561898,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.804552,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004939,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.047902,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.304884,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.056056,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.878405,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.249132,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.655392,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.275925,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.708102,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.667153,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045119,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "9e473ae9ad6a60fe75142fc840bbbd6a5f4f5c35",
          "message": "Document that import-dependence controls need a portable .sld, not a built-in (#2437)\n\nA test control whose stated job is to prove an `import` is load-bearing —\nthat it reaches the artifact's preamble and gets replayed — is silently\nvacuous when it rests on a built-in library. In script mode every built-in\nlibrary's bindings are ambient, so a top-level `import` of `(scheme base)`,\n`(scheme write)`, etc. is purely additive: the program resolves those\nprocedures whether it imports them or not. Even `write-simple`, exclusive to\n`(scheme write)`, resolves ambiently, so the natural instinct to reach for a\n`(scheme write)` procedure is exactly the trap.\n\nRecord the rule in the \"interpreter is the oracle\" section of\ntests/scheme/CLAUDE.md, next to the tier-difference notes, with the\n`(srfi 8)`/`receive` shape as the worked example: `receive` comes only from\n`lib/srfi/8.sld` and is a KP3001 undefined-variable error without its import,\nso the assertion has teeth.\n\nSweep of the two places a preamble-replay control makes sense —\ntests/scheme/compile/*.sh (32 files) and tests/scheme/differential/probes/ —\nfound no other instance. The one known case,\ncompile-define-values-order-2200.sh, was already fixed by PR #2432; the\ndifferential probes deliberately never `import` (it makes them uncacheable),\nso that genre of control cannot live there.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-30T16:06:18+05:30",
          "tree_id": "3bffd5baa45066be7ca99d6149cec84c04670029",
          "url": "https://github.com/kaappi/kaappi/commit/9e473ae9ad6a60fe75142fc840bbbd6a5f4f5c35"
        },
        "date": 1788087125543,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.073385,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.712948,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.433129,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.211953,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.003963,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.035968,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.220621,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.041633,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 1.836074,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.874606,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.229767,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.238128,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.661989,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.444575,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.03658,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "1b7c636846a1ffe1250df6be2d9a62eea0d8ded3",
          "message": "Make build_lock's steal group-aware so a killed script can't orphan a build (#2438)\n\nbuild_lock stole a lock whenever its recorded holder pid was dead, equating\n\"the launcher is gone\" with \"no work is in flight.\" That does not hold when the\nholder was killed rather than exiting: run-all.sh kills a shell script that\noverruns SHELL_TIMEOUT, but the `zig build` the script forked is not reaped with\nit. The next waiter saw a dead pid, stole the lock, and started its own install\ninto the same shared fixture prefix (.zig-cache/kaappi-test-fixtures/) while the\norphan was still writing -- a half-written interpreter or bundled binary that\nsurfaces as an unrelated-looking flake and gets re-run rather than diagnosed.\n\nFix the lock invariant itself rather than only the two fixture builders, since\nbuild_lock guards every script that forks its own `zig build` (the fixture\nbuilders, ensure_runtime_lib, srfi-241-202-bundle-2391.sh). run_shell_worker now\nlaunches each script under `set -m` so it leads its own process group, and the\nSHELL_TIMEOUT path signals the whole group (negative pid) instead of the lone\nscript pid -- so a clean timeout takes the forked build with it. build_lock's\nsteal then requires BOTH the recorded leader pid AND its process group to be\ngone, so a build orphaned by any other means -- still a member of the dead\nleader's group -- keeps blocking the steal until it actually finishes.\n\nThis is the process-group option from the #2432 review; the alternative\n(per-invocation prefix + atomic rename) would have removed the interleaving\nwindow only for the two fixture builders and left build_lock's steal unsound for\nits other callers.\n\nThe regression test is a deterministic simulation of the race: it plants a lock\nwhose pid file names a process that has already exited while a marker it spawned\nsurvives in that same process group (standing in for the orphaned build), then\nasserts a second build_lock caller does not steal until the group empties.\nVerified it fails without the shell-common.sh change (the second writer steals\nat once) and passes with it; the full `bash tests/scheme/run-all.sh` stays green\n(732 pass, 0 fail; R7RS 1395 pass).\n\nCloses #2434\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-30T16:36:42+05:30",
          "tree_id": "80445c520ff34887443622e24914cd8421a45097",
          "url": "https://github.com/kaappi/kaappi/commit/1b7c636846a1ffe1250df6be2d9a62eea0d8ded3"
        },
        "date": 1788090351288,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.314754,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.320586,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.578563,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.987856,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004963,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.048764,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.304933,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.05616,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.885893,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.232905,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 2.164003,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.283619,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.715189,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.631948,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045492,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "8fea440ec0b2842166b481e7f07e01d77d1b8ad4",
          "message": "Unpark and withdraw local-channel waits on every error exit (#2433) (#2439)\n\n* Unpark and withdraw local-channel waits on every error exit (#2433)\n\nThe two defects PR #2432 fixed for the three SRFI-18 park sites were still\npresent in primitives_fiber.zig's local-channel waits, which that PR left\nuntouched.\n\nGap 1 — channelSendLocal armed the parked state (.waiting, waiting_on, a\n#1530 waiter_index enrolment and a reactor timer) and then reached both\n`try addTimer` and `try runSchedulerStep` with nothing to undo it. Both\nsources return a *catchable* OutOfMemory, so a Scheme `guard` swallowing it\nwould resume on a fiber the scheduler still believes is parked — the #1487\ndispatch-from-stale-snapshot precondition. The receive side already had catch\nblocks; the send side was the odd one out. It now mirrors them, including the\nthird instance the issue table missed: the dispatched yield-retry re-park's\nbare `try addTimer`.\n\nGap 2 — no local-channel cleanup path withdrew the waiter_index entry.\nClearing status stops a stale entry waking the wrong fiber but does not remove\nit; only a later wake naming the same key would, so a park abandoned on an\nobject nothing wakes stranded one map key and list for the scheduler's\nlifetime. Every local error path now calls sched.withdrawWaiter before\nclearing waiting_on (which is the key).\n\nblockOrDeadlock's enrollWaiter (the remaining local site) is left as is: it\nparks deliberately and returns the uncatchable Yielded, so no guard can resume\n`me` while it is parked — a live waiter a wake will compact, not an abandoned\none. Documented inline. The promoted/shared-channel paths use a separate\nregistry (enrollSharedWaiter/removeSharedWaiter) whose catch blocks already\nunwind correctly and are untouched.\n\nRegression tests: two SRFI-181 custom-port probes whose read! callback blocks\non a timed local channel-receive / channel-send, raising runSchedulerStep's\ncustom-port-callback error from inside the armed in-call park. Both fail\nagainst the pre-fix source (waiting_on still set, entry still indexed) and\nassert both halves via expectUnparked. The dispatched flat-park re-park sites\narm no runSchedulerStep — only addTimer — so their error path is OOM-only,\nwhich the injector cannot reach (#2435).\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Restore status/timed_out in the channel runSchedulerStep error paths (#2433 review)\n\nBoth channel-wait runSchedulerStep catch blocks leaned on runSchedulerStep's\n#2429 epilogue to put me.status back to .running. But that epilogue's errdefer\nis armed only AFTER the initial `try sched.saveCurrentFiber()`, so an OOM in\nthat first save returns with me still .waiting; and the epilogue forces only\n.running, never resetting a timed_out that a timer wake set mid-drive. Since\nOutOfMemory is catchable, a Scheme guard could then resume with stale park\nstate. Restore me.status = .running and me.timed_out = false explicitly in both\nhandlers, matching primitives_srfi18.unparkOnError.\n\nNot test-coverable: the custom-port probe reaches runSchedulerStep's own\ncallback-blocked guard, which pre-restores status/timed_out before returning;\nthe leak is on the deeper first-saveCurrentFiber OOM path, which the injector\ncannot reach (raw allocator, #2435) — same limitation as the addTimer-only\nsites.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n---------\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-30T12:55:25Z",
          "tree_id": "8d0ba9fa04b1215a00287c166432be52155cfa93",
          "url": "https://github.com/kaappi/kaappi/commit/8fea440ec0b2842166b481e7f07e01d77d1b8ad4"
        },
        "date": 1788097258245,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 2.557508,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.097372,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.332528,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 1.848358,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.003824,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.028999,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.182342,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.039986,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 1.699113,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.720042,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 0.968286,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.190674,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.070487,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.793522,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.030113,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "3b8199472c05dab19f6a88d0be9ef54efc8ec4de",
          "message": "Give the OOM injector a raw-allocator counterpart the fiber scheduler paths need (#2435) (#2440)\n\n* Give the OOM injector a raw-allocator counterpart the fiber scheduler paths need (#2435)\n\n`gc.oom_countdown` fires from `GC.maybeCollect`, so it only ever intercepts\nallocations that go through the GC. Every allocation made straight from the\nraw allocator — the VM's growable register/frame/handler/wind stacks, the\nfiber snapshot buffers, the reactor timer heap, the scheduler's\n`driving_waits` list, bignum limb scratch, and the bytecode/IR/constant\npools — is invisible to it. Those are exactly the allocations behind the\nfiber scheduler's OOM error paths (#2429, #2433), so their regression tests\ncould not be written with the injector the docs presented as exhaustive.\n\nAdd `memory.OomAllocator`: a test-only wrapper over a backing allocator with\nits own countdown, independent of `oom_countdown` (a form's raw and GC\nallocation sequences are unrelated). It ticks on `alloc` and refuses `remap`\nonce spent, so an `ArrayList`/timer-heap growth cannot slip past an armed\ninjector, while `null` (the default) forwards untouched so a VM built on it\nconstructs normally until a test arms it. A `builtin.is_test` guard makes a\nproduction reference a compile error.\n\nCorrect the three docs that presented `oom_countdown` as reaching \"every\nallocation a form performs\" — it reaches every *GC* allocation — and point\neach at the raw-allocator counterpart: `docs/dev/testing.md`,\n`docs/dev/gc-safety-and-error-handling.md`, `.claude/rules/gc-safety.md`,\nand the field comment in `memory.zig`.\n\nTests: two allocator-mechanism tests (a raw `allocSliceNoFill`; ArrayList\ngrowth — the `addTimer`/`driving_waits` shape), plus an end-to-end test in\n`tests_gc_root_boundary.zig` proving a real VM's register-file growth is\nreachable by `OomAllocator` and never by `oom_countdown`.\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Address review: gate growth in OomAllocator, make it thread-affine; add the #2429 OOM regression test\n\nReview fixes on the raw-allocator OOM injector (#2440):\n\n- A growing resize/remap now participates in the countdown. The injector\n  treated resize as a pure in-place op and never ticked a successful remap, so\n  under a FixedBufferAllocator a nonzero budget let later ArrayList/PriorityQueue\n  growths bypass injection and resize could even grow at countdown 0. It now\n  gates on growth (new_len > mem.len), fails a growth once the budget is spent,\n  and consumes one unit only when a growth actually succeeds; shrink/no-op\n  forwards untouched.\n\n- Injection is now thread-affine. GC.initForThread hands an SRFI-18 child the\n  parent's gc.allocator — the same OomAllocator pointer — so arming while a\n  child allocated raced the owning thread on `countdown`. Only the constructing\n  thread is injected now; every other thread forwards untouched and never reads\n  or writes `countdown`. Deterministic injection is a single-threaded notion\n  anyway.\n\n- Docs say \"allocations mediated by maybeCollect\", not \"every allocXxx\":\n  allocSymbol and allocFunction skip maybeCollect too.\n\nNew tests:\n\n- OomAllocator: a growing resize/remap is gated (shrink/no-op always forwards),\n  and a successful in-place growth consumes a nonzero budget (reviewer's\n  FixedBufferAllocator case); only the owning thread is injected.\n\n- The #2429 regression the injector was built to unblock: a raw-allocator OOM\n  during a scheduler drive, failing the growFiberXxx snapshot save that runs\n  while a sibling's window is loaded, must still restore the waiting fiber's\n  window. The sibling of the existing Terminated-driven probe, now driving the\n  actual OutOfMemory the bug is about. Verified it fails without the errdefer\n  (current_idx/current_fiber/frame_count all name the sibling) and passes with\n  it, in normal and -Dgc-stress builds.\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n---------\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-08-30T21:32:37+05:30",
          "tree_id": "c332b1291beb1f804c7c03d55702d928bf129438",
          "url": "https://github.com/kaappi/kaappi/commit/3b8199472c05dab19f6a88d0be9ef54efc8ec4de"
        },
        "date": 1788108093012,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.266111,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.066737,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.574274,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.969305,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.005038,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.048711,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.313094,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.055835,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.729731,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.237404,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.648566,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.285352,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.751327,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.71548,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044702,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "ffb7d3c982447477400a22fa56e0c271f82819a0",
          "message": "Add (kaappi process): posix_spawn subprocess support, POSIX Phase 1 (#2414) (#2442)\n\n* Add (kaappi process): posix_spawn subprocess support, POSIX Phase 1 (#2414)\n\nKEP-0022 Phase 1: a spawn-based (never fork-based) subprocess API with\nchild stdio exposed as ordinary reactor-integrated pipe ports, a new\nthread-affine Process heap type, blocking process-wait, and a\nclose-by-default fd discipline. POSIX only; reactor reaping is Phase 2\nand Windows is Phase 3, so the library is unregistered on WASM/Windows\nand (cond-expand ((library (kaappi process)) ...)) gates correctly.\n\nThis is a fresh implementation drawing on the two prior attempts (the\nreviewed PR #2441 and a follow-up iteration), and resolves all nine\nblocking review findings from #2441 — each with a regression test:\nthe glibc-2.29 comptime gate for addchdir_np (the release floor is\ngnu.2.28), real close-by-default for descriptors Kaappi itself\ninherited, POSIX_SPAWN_SETSIGDEF so children do not inherit the\nruntime's SIGPIPE=SIG_IGN (whose flag VALUE is 0x10 on the BSDs, not\nthe 0x04 of macOS/glibc/musl — POSIX names the flags but not their\nvalues), registry-backed zombie reaping, cycle- and NUL-guarded\nargv/env/directory marshalling, GC quiescence around the blocking\nwaitpid on child-thread VMs, and EPIPE surfaced as a catchable\nKEP-0005 file-error on explicit writes/flushes instead of a silently\ndropped buffer.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Close the NetBSD exec-window kill race; report OpenBSD exec failures\n\nTwo platform gaps the reference-VM matrix surfaced (kaappi#2414):\n\nNetBSD's posix_spawn is an in-kernel syscall whose child completes its\nexec after the parent's call has returned, and a signal posted before\nthat exec has fully finished is dropped outright — measured at 5/40\nimmediate SIGTERMs lost, and both prior attempts' NetBSD breakage. A\nCLOEXEC-pipe EOF barrier measured insufficient (8/40 still lost: the\nkernel closes close-on-exec fds before the child's signal state is\nfinal), so spawn now waits on kqueue's NOTE_EXEC — the kernel's own\nexec-completed notification — with NOTE_EXIT and a 20 ms timeout as\nthe fallbacks. 40/40 immediate kills deliver, in 0.77 s total.\n\nOpenBSD's userland posix_spawn has no channel to report the child's\nexec failure, so spawning a missing program 'succeeded' and the child\nexited 127. A pre-flight access(X_OK) on slash-containing program\npaths raises the same errno-carrying file-error as every other\nplatform; PATH-searched bare names keep the POSIX-sanctioned fallback.\n\nVerified on the NetBSD 10.1 and OpenBSD 7.9 reference VMs: full unit\nsuite 1858/1858 on both.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Reclaim descriptors via GC before failing a spawn pipe (#1993 parity)\n\nThe openbsd-test CI leg's low ulimit -n caught the spawn-loop rooting\ntest raising 'cannot create stdout pipe' partway through: a program\nthat abandons process handles faster than the GC's allocation-count\nthreshold trips leaves their parent-end pipe fds open until a\ncollection, and spawn's pipe(2) lacked the EMFILE/ENFILE recovery\nopen(2) has had since #2324 — collect once, retry once.\n\nThe new regression lowers RLIMIT_NOFILE to a small headroom above the\nfds already open and burns three pipes per spawn so exhaustion arrives\nwell before a natural collection could mask it; mutation-verified (the\ntest fails with the retry disabled).\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Address kaappi#2442 review: real F_DUPFD_CLOEXEC values, no spawn-path panic\n\nFive review fixes and one decline:\n\n- platform.fcntlDupCloexec hardcoded fcntl command 6, which is not\n  F_DUPFD_CLOEXEC on any target (macOS: F_SETOWN, Linux: F_SETLK), so\n  the dup silently never happened and thottam's failed-execve\n  diagnostic (#2152) wrote to an invalid descriptor. The command now\n  comes from std.c's per-target F table, with the value OpenBSD's\n  entry omits (10, in the OS since 5.0) supplied explicitly.\n- allocProcess reserves the unreaped-list slot before creating the\n  Process, so list-growth OOM raises through the existing error union\n  instead of aborting the VM from a user-reachable path.\n- The close-by-default BSD fallback probes the descriptor range inline\n  instead of materializing up to 65k entries per spawn; the ArrayList\n  remains only for the genuinely sparse /proc/self/fd listing.\n- ignoreSigpipe upgrades only a SIG_DFL disposition, preserving an\n  embedder's own SIGPIPE handler (their handler still sees the signal\n  and the write still returns EPIPE).\n- docs/dev/architecture.md primitive-file count 31 -> 32; a test\n  comment that contradicted its own assertion rewritten.\n\nDeclined: splitting primitives_io.zig — the file-size policy exempts\nprimitives files' breadth, and 2391 of its 2450 lines predate this PR.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Harden the spawn stdio plumbing per the kaappi#2442 deep review\n\nTen reviewer findings, each reproduced on a reference machine, plus one\nCodeRabbit errno nit — all with regression tests:\n\n- Pipe ends handed back in 0..2 (launcher closed a std stream) corrupted\n  the slot actions; both ends are now lifted above the stdio range via\n  F_DUPFD_CLOEXEC before any action names them.\n- Darwin's POSIX_SPAWN_CLOEXEC_DEFAULT closes even fds 0..2 unless an\n  action references them, so a plain 'inherit spawn lost all three\n  streams; each open inherited slot now gets addinherit_np. Fixing this\n  exposed that the fd-hygiene scan's own probe shell parks the (now\n  live) stdin at its fd-10 save slot during  redirection — the\n  probes close stdin up front so they cannot detect their own\n  bookkeeping.\n- File actions run sequentially in the child, so a stdout/stderr swap\n  through low-fd caller ports read slots an earlier dup2 had already\n  rewritten; low redirect sources are staged into >= 3 CLOEXEC dups.\n- posix_spawn_file_actions_init / posix_spawnattr_init returns were\n  ignored; both are checked and destroy arms only after success. All\n  action/attr failures now report the RETURNED error number — these\n  functions do not set errno.\n- An input redirect port's software read-ahead left the kernel offset\n  past the logical position; seekable fds are rewound by the pending\n  count, unseekable ones with pending bytes are rejected.\n- The post-spawn success flag disarmed all fd cleanup before three\n  fallible allocations; cleanup now stays armed with per-slot ownership\n  transfer, and the one untracked-child OOM path kills and reaps the\n  fresh child. A 400-point oom_countdown sweep asserts descriptor\n  balance across every failure point.\n- tests/scheme/process was missing from run-all.sh's reachability/\n  verdict inventories and from the gc-stress suite runner (which also\n  never exported KAAPPI, silently skipping the child-script round trip).\n- The close-by-default scan's 65536 cap exempted valid high fds\n  (FreeBSD reference VM runs RLIMIT_NOFILE=117153): FreeBSD now uses\n  addclosefrom_np(3) — kernel-side, unbounded — and the NetBSD/OpenBSD\n  scan runs to the full soft limit.\n- A child-thread VM blocking in the vfork-style spawn (or the NetBSD\n  exec barrier) starved parent collections; the spawn stretch now uses\n  the same setCollectionInNative protocol as process-wait.\n- The GC sweep's best-effort port flush used a BLOCKING write, so\n  collecting an abandoned pipe port with pending output against a\n  child that never reads wedged the collector; the fd is flipped\n  O_NONBLOCK for the teardown drain (a no-op for regular files, whose\n  flush still completes).\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Right-size the spawn OOM sweep for the emulated CI legs\n\nriscv64-test hit its 30-minute job budget: the OOM sweep's 400\nblind-countdown evals each recompiled the spawn expression and, past\nthe failure window, performed a full spawn+wait — expensive under\nQEMU. The spawn is now compiled once and the sweep measures the\ncall's actual GC-allocation count (a huge-countdown dry run), covering\nexactly the failure window (~14 iterations) instead of hundreds of\nasserting-nothing successes. Mutation-verified at the new size:\ndisabling the fd-cleanup defer fails the sweep with 3 leaked\ndescriptors per injected failure.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Close the round-3 kaappi#2442 review findings on the spawn plumbing\n\nSix reviewer findings plus three CodeRabbit items, each with a\nregression (and the two behavioral ones mutation-verified locally, the\nFreeBSD one mutation-verified on the reference VM):\n\n- The post-spawn kill/reap covered only allocProcess failure; an\n  errdefer now spans the port constructions too, kills and reaps the\n  fresh child (blocking waitpid — no zombie window), records the\n  SIGKILL status, and drops the registry entry. The OOM sweep spawns a\n  self-killed sleep 30 instead of true, so an abandoned live child is\n  visible, and asserts the registry empties.\n- parseRedir reconciles input read-ahead BEFORE draining buffered\n  output: on a bidirectional port the old order wrote the parent's\n  buffer at the stale read-ahead offset (ABCDEF became ABCDEFX; now\n  AXCDEF, and the child reads from the logical position).\n- The sweep's teardown O_NONBLOCK flip mutates the shared open-file\n  description; the prior flags are now restored before the close so\n  dup/dup2 aliases stay blocking, and a failed flip skips the\n  blocking-capable drain instead of falling through.\n- The high-fd close test's shell <&70000 probe was vacuous on FreeBSD\n  (its sh rejects the operand); the probe now asks the OS's own fd\n  inventory (procstat / /proc/self/fd / /dev/fd) with an fd-2 control,\n  and fails on the FreeBSD VM when addclosefrom_np is disabled with\n  the old cap restored.\n- Staging is skipped when a redirect source already equals its slot:\n  dup2(n,n) is collision-free and still names the fd for Darwin's\n  CLOEXEC_DEFAULT, so explicit stdio inheritance works under a full\n  fd table (tested by filling to EMFILE at a lowered-but-comfortable\n  limit — zero-free rlimit starves the CHILD's exec instead, aborting\n  dyld as (signaled . 6)).\n- FreeBSD's initializers return -1 with the error in errno; negative\n  init results are normalized from errno before raising.\n- The fallback scan's limit is clamped to maxInt(fd_t) (overflow, not\n  coverage); the sweep-flush test sizes fit 16 KiB fixed pipes while\n  still overfilling 64 KiB ones; the stdio shell suite's gate uses a\n  dedicated absent-library status so real failures cannot skip it.\n\nVerified: unit suite + run-all (2131/0) + gc-stress slice on macOS;\nFreeBSD 1866/0, NetBSD 1865/0, OpenBSD 1865/0 on the reference VMs.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Address the round-4 kaappi#2442 findings without touching shared fd state\n\nFive reviewer findings, three of which were the failing CI legs:\n\n- The GC sweep no longer toggles O_NONBLOCK at all: the flag lives on\n  the shared open-file description, so even a save/restore leaves\n  dup/dup2 aliases transiently non-blocking and can overwrite their\n  concurrent flag changes. The teardown drain is gated on seekability\n  instead — a seekable fd is a regular file whose blocking write\n  completes without a peer (preserving the historical flush-on-collect\n  for file ports), while pipes/sockets/FIFOs/ttys drop their remainder\n  outright, per the best-effort contract.\n- killAndReapFresh checks the kill result before any blocking wait,\n  publishes a child-thread VM via setCollectionInNative around the\n  reap (the #1933 protocol), and reports failure so the errdefer keeps\n  the registry entry for the WNOHANG sweeps instead of forgetting the\n  pid.\n- The EMFILE-fill self-redirect test skips when a plain spawn cannot\n  survive the full table — QEMU binfmt needs a spare descriptor to\n  load the interpreter, which is why riscv64-test, ppc64le-test and\n  s390x-test all failed in it — while real kernels keep the full\n  assertion behind the staging-impossible control.\n- The OOM sweep's registry assertion runs BEFORE collectFull (which\n  would drop an unreachable Process whose child still lives), and the\n  epilogue requires a bounded transition to waitpid ECHILD, failing on\n  a persistent still-running child. Mutation-verified: no-op'ing the\n  errdefer fails with three abandoned registry entries.\n- The sweep-bound test's flushed prefill drops to 4096 bytes (at most\n  one pipe page even under Linux's per-user pipe-page soft limit) with\n  a 68000-byte unflushed tail.\n\nVerified: unit suite + run-all 2131/0 on macOS; FreeBSD 1866/0.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n---------\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-08-31T22:52:56+05:30",
          "tree_id": "90480f990a51edf114804c54bfd7392035334c8d",
          "url": "https://github.com/kaappi/kaappi/commit/ffb7d3c982447477400a22fa56e0c271f82819a0"
        },
        "date": 1788199225125,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.33142,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.970907,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.562922,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.00089,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004864,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.047859,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.309885,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.056205,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.779145,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.220476,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.638396,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.282201,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.707016,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.643904,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.04492,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "8b0f35044d14c32babb71a9787619c63668aece7",
          "message": "Park process-wait on reactor child-exit readiness (KEP-0022 Phase 2) (#2445)\n\n* Park process-wait on reactor child-exit readiness (#2415)\n\nKEP-0022 Phase 2. The reactor gains a per-process registry alongside its\nfd registrations: kqueue watches children via EVFILT_PROC + NOTE_EXIT\n(registered by pid), epoll via pidfd_open(2) registered for\nread-readiness (the pidfd's lifetime is the registration's). On exit\nreadiness the reactor reaps exactly once — waitpid WNOHANG, status into\nproc.status, the child off the unreaped registry — and wakes every\nparked waiter. No SIGCHLD handler exists anywhere, so children spawned\nby C FFI libraries stay unobserved.\n\nprocess-wait now parks the calling fiber instead of blocking the OS\nthread: a dispatched fiber takes the flat yield-retry park, the main\nfiber drives the scheduler in place, and 'timeout: rides the reactor\ntimer heap with Python's contract (#f on expiry, child lives; a stored\nstatus outranks a fired timer — the channel delivery-wins precedent).\nThe Phase-1 blocking waitpid survives as the no-scheduler fallback and\nas the degradation when the kernel refuses the watch.\n\nThe races and disciplines that shaped the shape:\n\n- An exit that beats the arm posts no kernel event, ever — every\n  registration is followed by one WNOHANG probe (arm-then-probe), and an\n  ESRCH arm refusal reaps the same way.\n- \"Armed iff a waiter is parked\": the last waiter's withdrawal drops the\n  registration, so zombie discipline for never-waited children stays\n  with the Phase-1 sweeps instead of the registry pinning Processes\n  alive. Reactor.markRoots traces registered Processes and waiters.\n- Reaps outside the reactor (process-status, the WNOHANG sweeps, the\n  blocking fallback) wake parked waiters themselves — a waiter must\n  never depend on an event whose registration was already dropped.\n- Every error exit from a park unwinds the full park state\n  (waiter entry, timer, waiting_on, timed_out) — the #2433 discipline.\n\nGroup kill shipped in Phase 1; this adds its acceptance test (the\nchild's own child is dead after 'group: #t), the fiber-starvation test\n(a slow child must not starve a sibling — the wait can only resolve\nafter the sibling's 11th turn), and the timeout-contract tests, at the\nreactor level, the primitive level, and in the Scheme suite.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Degrade to a polled park when the kernel cannot watch a process\n\npidfd_open(2) is ENOSYS before Linux 5.3 and under Rosetta's x86_64\nsyscall translation (the podman amd64 test leg), so every registration\nfails there and process-wait fell back to the Phase-1 blocking waitpid —\nwhich is not a degradation but a deadlock for any program whose child\nexits only after a sibling fiber acts (the fiber-starvation test hung\nforever in wait4 instead of failing).\n\nReplace that arm with polledWait: a WNOHANG probe every 20 ms, parked on\nthe reactor timer heap between probes, driving in place for every caller\n(a dispatched fiber included — with no kernel event to wake a flat park,\na yield-retry would need to tell its polling timer from the user's\ntimeout: deadline, while a bounded drive needs no such split). The\nblocking path survives only where it always was: no scheduler, no\ntimeout.\n\nThe three kernel-watch reactor tests skip when pidfd_open probes ENOSYS\n— the polled degradation is covered by the tests_process eval tests,\nwhich pass under Rosetta with the same profile as main.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Split the reactor's OS backends into reactor_backends.zig\n\nreactor.zig crossed the 1500-line policy bound when the process-watch\nregistry landed (PR #2445 review). The dispatch-versus-backend line is\nthe natural seam: the four readiness multiplexers (kqueue, epoll,\npoll_oneoff, WSAEventSelect+pipes) consume only the reactor's normalized\nleaf types (ReadyEvent, Interest, NotifierBackend) and share nothing\nelse with the core, so they move wholesale together with the per-poll\nbuffer bound and NetBSD's versioned __kevent50 binding (which the\nnotifier's ring also uses, re-exported). msFromNs is aliased back so\ntests_reactor_parity's external reference is unchanged. Pure code\nmotion — 1641 lines becomes ~830 + ~850.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Never report a failed reap as a timeout; surface ECHILD as an error\n\nPR #2445 review (CodeRabbit): when the reactor's exit event finds\nwaitpid reporting ECHILD — something outside Kaappi (a C FFI library's\nwait(-1)) reaped our child — it wakes the parked waiters with no status\nstored, and the wake path flips timed_out for every .waiting fiber it\nreports. A timed process-wait then returned #f well before its\ndeadline, an untimed one could return #f at all (a contract violation),\nand the polled fallback would spin at its cadence forever on the same\nECHILD.\n\ntimed_out alone is no longer a verdict anywhere: the flat retry's\ndiscriminator and the drive path's tail both require the deadline to\nhave actually passed before reporting #f, a spurious pre-deadline wake\nfalls through to re-registration (which fails ESRCH on the vanished\npid) and resolves through the polled path, and polledWait now probes\nwaitpid inline so a persistent non-EINTR failure raises the same\ncatchable \"cannot wait for process\" file-error the blocking path\nraises. A flat retry entering that degradation also hands it the\npreserved absolute deadline (never the recomputed-and-extended one) and\ndetaches its stale timer first.\n\nAlso from the same review: the two blocking reap loops in\ntests_reactor now fail the test on a persistent waitpid error instead\nof hanging the suite. Regression test: reap a spawned child directly\nbehind the registry's back, then assert both a generously-timed and an\nuntimed process-wait raise file-error promptly — neither #f nor a hang.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Fix a stale comment: the reactor process tests fork, not std.process.Child\n\nThe section header still described the first draft's spawn mechanism;\nthe helper switched to raw fork() (the Io-based Zig 0.16 Child API is\nnot worth the ceremony here) before the tests ever landed.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n---------\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>",
          "timestamp": "2026-09-01T01:29:47Z",
          "tree_id": "759c973bbb1815a8fa4333f23f6af22282ea9094",
          "url": "https://github.com/kaappi/kaappi/commit/8b0f35044d14c32babb71a9787619c63668aece7"
        },
        "date": 1788228473965,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.231246,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.536661,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.558956,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.953835,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.005045,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.049012,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.303439,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.055354,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.760241,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.217562,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.643481,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.280651,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.712338,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.621087,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044178,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "5cdfc118d5c6f90ea113a0d81dfca53131d97ac3",
          "message": "Always check SRFI 231 array-ref and array-set! (#2449)\n\nAn array built with safe?: #f handed the user the raw, unchecked\naccessor, so an out-of-domain multi-index still computed a body offset.\nWhen that offset landed inside the body it silently read or clobbered a\ndifferent, valid element. On a 2x3 u8 array, (array-ref a 0 5) returned\nelement (1 2), and (array-set! a 99 0 5) overwrote it -- no error either\ntime. Only an index wild enough to escape the body entirely was loud,\nand then the diagnostic came from the storage layer naming a flat offset\nthe user never wrote.\n\nThis was the default path: specialized-array-default-safe? is #f.\n\nThe spec makes safe?: #t *add* argument checking to the getter and\nsetter; it never says an unsafe array may return a wrong answer. The\nSRFI's author has since removed the distinction from the reference\nimplementation for the same reason, which is what this follows: the\nuser-visible getter and setter are now always wrapped, and an internal\nunchecked pair is kept on the array for bulk operations, which generate\ntheir own in-domain indices and so cannot present a bad one.\n\nValues are still validated on the way into a body, since an unchecked\nstore is what actually corrupts -- u1 silently drops bits. The check is\nskipped only where provably vacuous: a generic destination manipulates\nevery value, and a same-storage-class copy reads values that already\nsatisfy the destination's checker.\n\narray-safe? still reports what the caller asked for; it just no longer\ngates checking.\n\nTwo consequences beyond the fix. The vendored official suite recorded\nthis as known-divergence 351 (\"unsafe specialized views are unchecked\nper the spec text; the reference happens to check\"); that entry is now\nresolved and pruned, taking the suite from 2 unexpected failures to 0\nagainst the pruned list. And bulk operations over safe arrays no longer\nre-validate indices they just generated, which roughly halves their\ncost -- a 200x200 f64 array-copy goes from 0.348 s to 0.178 s.\n\nReported by Brad Lucier (gambiteer).\n\nCloses #2448\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-09-01T09:29:02+05:30",
          "tree_id": "777df9a8e43e69f1b6b196b08a97a6fe29b58234",
          "url": "https://github.com/kaappi/kaappi/commit/5cdfc118d5c6f90ea113a0d81dfca53131d97ac3"
        },
        "date": 1788237546165,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.930813,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.220599,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.561851,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.811487,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.005309,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046244,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.294309,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.061661,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.416904,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.122722,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.623617,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.30927,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.633471,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.84468,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.046972,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "3fce40d2d278013ad0d078d75fa4dec09553940a",
          "message": "Port (kaappi process) to Windows: CreateProcess, Job Objects, handle reaping (#2450)\n\nKEP-0022 Phase 3. Windows has neither fork/exec nor signals, so nothing\nhere is a translation of the POSIX backend — three substitutions carry it.\n\nSpawn is CreateProcessW with an explicit inherit list. There is no argv\nvector on Windows: the child's C runtime parses one command line back with\nCommandLineToArgvW's rules, so argv is joined by platform.buildCommandLineW,\nthe encoder thottam already used for git. Inheritance is confined to a\nPROC_THREAD_ATTRIBUTE_HANDLE_LIST naming exactly the three stdio handles,\nwhich is a *stronger* close-by-default guarantee than the POSIX\nenumerate-then-close scan: nothing Kaappi inherited from its launcher or\nacquired through FFI can reach the child, and there is no enumerate/spawn\nrace to document.\n\nA process group is a Job Object. TerminateProcess kills exactly one process\nand CREATE_NEW_PROCESS_GROUP only re-routes console Ctrl+C — neither reaches\na grandchild, while a child of a job member joins the job automatically. So\nnew-group: creates one and assigns the child before its primary thread is\nresumed (CREATE_SUSPENDED): a child that ran even briefly outside the job\ncould spawn a grandchild the tree-kill would miss. The job deliberately\nomits KILL_ON_JOB_CLOSE, so an abandoned Process leaves its group running\nexactly as an abandoned POSIX process group does.\n\nReaping is the process HANDLE — the reactor's wait object, the\nGetExitCodeProcess source and the TerminateProcess target at once — so the\nProcess owns it for its whole lifetime and only freeObject closes it. It\njoins WaitForMultipleObjects' wait set in WindowsEventBackend; a signaled\nhandle is reported with ReadyEvent.proc set, because the key is a process id\nthat would otherwise be mistaken for a same-numbered descriptor (the kqueue\nprecedent). Liveness is the handle's signaled state, never GetExitCodeProcess'\nSTILL_ACTIVE, which a child exiting 259 is indistinguishable from.\n\nSignals have nothing to map onto, so signal: folds into the exit code\nTerminateProcess stamps: 128 + n, the shell convention, and a status is that\nplain integer rather than (signaled . n). signal: 0 stays an existence probe.\n\nThe primitive layer keeps everything platform-independent — option parsing,\nredirection validation, the Process object and its ports, the whole Phase-2\nfiber park — and picks one of process_posix.zig / process_win.zig at\ncomptime, so neither OS's syscall surface is analyzed on the other. The seam\nis three types in types_process.zig plus reapNonBlocking, which reactor.zig\nand gc_sweep.zig share so neither has to know which OS reaped.\n\nVerified on the win11 ARM64 reference VM and, under x64 emulation, on the\nx86_64 build: 1836 unit tests pass on each (including the new cmd.exe suite,\nwhose tree-kill assertion queries the Job Object's own process-id list), and\nthe new process-portable.scm passes its 18 cases on both — argv quoting\nround trip and grandchild-dies-too included. macOS stays at 2133/0 across\nthe full suite, with the process tests green under -Dgc-stress=true.\n\nCloses #2416\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-09-01T09:52:44+05:30",
          "tree_id": "b67cd7af7a5db8dba37f9bddd371b929c48a7899",
          "url": "https://github.com/kaappi/kaappi/commit/3fce40d2d278013ad0d078d75fa4dec09553940a"
        },
        "date": 1788239058190,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.306885,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.471299,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.575475,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.971876,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004956,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.048671,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.306888,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.055248,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.765957,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.233293,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.673173,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.290064,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.725131,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.680978,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045089,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "b29386c18e2e0dff8ea458ae8012a57aa45aaef2",
          "message": "Give apply and call-with-values a non-tail resumable path (#2451) (#2452)\n\n* Give apply and call-with-values a non-tail resumable path\n\nA continuation captured under a non-tail (apply f ...) or\n(call-with-values p c) could not be resumed once the call had returned:\n\n  error[KP3000]: continuation cannot resume across a returned native call\n\nBoth reached their callee through a native primitive's vm.callWithArgs — a\nfresh runUntil under a Zig frame that is gone by the time the continuation\nis reinstated. Tail position was already exempt, because compileApplyTail\nand compileCallWithValuesTail emit tail_apply, which replaces the frame in\nthe dispatch loop. That asymmetry is what made the restriction impossible\nto predict from the outside: map, for-each, vector-map, vector-for-each and\nstring-for-each are fine in both positions; apply and call-with-values only\nin tail. R7RS-small requires all of them to be fully re-entrant.\n\nAdd a non-tail `apply` opcode. It flattens the operand list and hands the\ncallee to callValue, so the callee gets an ordinary VM frame that a\ncontinuation snapshot copies like any other. call-with-values now applies\nits consumer through apply/tail_apply in both positions, over the value\nlist returned by a new internal %call-with-values->list — which also keeps\nthe two type checks callWithValuesFn did, before the producer runs, so a\nbad consumer is still reported as call-with-values rather than as the\n`apply` the form compiles into. In tail position that is a small\nimprovement of its own: the consumer check used to be tail_apply's bare\n\"apply: not a procedure\".\n\nTwo corners deliberately stay on the native route, and are documented in\nREADME \"Known limitations -> Continuations\": call-with-values' producer,\nand an apply flattening more than 255 arguments (#649 requires that to\nwork at all, and a call frame's argument count is one byte, so the opcode\nfalls back to callWithArgs rather than rejecting the call the way\ntail_apply does).\n\nDiagnostics are unchanged in wording and order. The opcode reproduces\napplyFn's typeError texts, including its tortoise-and-hare rejection of a\ncircular final list, because non-tail position is where\ntests/scheme/compile/native-apply-lowering-1803.sh pins the interpreter's\ndiagnostics against the LLVM backend's; the backend keeps routing both\npositions through @kaappi_apply, so the resumability guarantee is\ninterpreter-only.\n\nThe opcode is appended to the end of the OpCode enum, not placed beside\ntail_apply: an opcode's number is part of the .sbc encoding, and while the\ncache load path rejects a foreign build by compiler hash,\nsrc/testdata/fuzz-seed.sbc patches that hash in at comptime and simply\ndecoded as garbage when the numbering shifted. The /bytecode-isa skill's\nchecklist gains that reason and the four steps the build did not catch.\n\nSRFI 231's two continuation test groups stop emitting 11 KP3000\ndiagnostics per run and now execute, reaching the library's own documented\ndivergence instead: %array-copy-impl (lib/srfi/231/views.sld) fills the\ndestination directly rather than accumulating first, so a getter that\nre-invokes a captured continuation after the copy returns overwrites the\narray already returned. Recorded as known-divergence ids 737-741 (one fill\nloop; array-append/stack/block/decurry all delegate to array-copy).\n\nCloses #2451\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Point the two carved-out corners at their follow-up issues\n\nBoth were named without a tracking number when they were carved out of\n#2451's scope: call-with-values' still-native producer (and the misleading\n\"apply: last argument must be a list\" a resume there reports) is #2453,\nand SRFI 231's direct-fill array-copy is #2454.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Review: move the apply body into vm_dispatch_helpers, use th wrappers\n\nThree CodeRabbit findings on #2452; two applied.\n\nFile size. The apply handler took vm_dispatch.zig from 1472 to 1590 lines,\npast the 1500-line policy. The body moves to vm_dispatch_helpers.zig as\n`dispatchApply` — the file that already holds operand readers, register-\nwindow validation and rest-argument building for every other opcode, so\nthis is the existing seam, not a new one. The arm keeps only what a helper\ncannot express: the `continue` that resumes a restored continuation in that\ndispatch loop, and the ip rewind a parked fiber's retry needs. 1490 lines.\n\nRepairing the staged-over operand register moved with it. The register is\nclobbered by `dispatchApply`, so `dispatchApply` restores it on the\nYielded-retry path instead of every caller having to remember to — which\ncollapses the arm's error mapping to the same shape as the `call` opcode's.\n\nTests. The five new unit tests each do one evaluation and one check, which\nis what docs/dev/testing.md's `th.expectEval*` wrappers are for; the two\nthat assert a symbol become `expectEvalTrue` over an `eq?`. tests_\ncontinuations.zig has no prior wrapper use, but the guidance is the doc's,\nnot the file's.\n\nDeclined the third: a preceding `define` in the same literal `begin` does\nNOT bypass the fast-path gate. `globalBindingStillGenuine` reads the live\nglobal environment, and a top-level `begin`'s children are compiled and run\none at a time, so the definition has executed by the time the use compiles.\nPinned for both names in the Scheme suite and the unit tests rather than\njust asserted.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n---------\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-09-01T08:18:49Z",
          "tree_id": "b97950517197d0eb8a9cb3fd2c8be52d8584aff8",
          "url": "https://github.com/kaappi/kaappi/commit/b29386c18e2e0dff8ea458ae8012a57aa45aaef2"
        },
        "date": 1788254065933,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.334856,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.328113,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.583941,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.943849,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004921,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.047146,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.310994,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.056496,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.719496,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.217382,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.647119,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.28786,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.726619,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.674068,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044727,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "4aa2bab13522a185639856833dd09a05b5ae847c",
          "message": "Add run-process and the process-timeout condition (KEP-0022 Phase 4) (#2455)\n\n* Add run-process and the process-timeout condition (KEP-0022 Phase 4)\n\n`spawn-process` gives you a child and three ports; getting a captured\nstring out of it correctly does not follow. Feed a child's stdin and then\nread its stdout and you deadlock the moment either side passes the pipe\nbuffer, and reading stdout to EOF before stderr deadlocks on a child that\ntalks on both. This is the bug Python's `communicate()` exists to work\naround, with a thread per stream and a `select` loop.\n\nKaappi already has the better answer, so `run-process` uses it: a feeder\nfiber writes `input:` and two drain fibers read the pipes, all three\nrunning while `process-wait` parks. Nothing blocks the thread and nothing\ndeadlocks, and the whole procedure is 90 lines of Scheme rather than a\nselect loop in Zig.\n\nThat is also why it is Scheme. Spawning and joining fibers is dispatch-loop\nwork a native frame cannot do, so `run-process` is a `bootstrapStub` whose\nbody `vm_bootstrap.install` evaluates -- the same route `map` and\n`for-each` take, and `%process-spawn` was added in Phase 1 as the stable\nentry point for exactly this. The install is gated on that primitive being\nregistered rather than on a mode flag, because the library is absent in two\nplaces for two unrelated reasons: WASM omits the module outright, and\n`--sandbox` skips every `.sandbox = false` spec. Evaluating the definition\nin either would have taken VM startup down on an undefined variable.\n\n`timeout:` needs somewhere to put what the child produced before it\nstalled, since the values return never happens. It raises a condition\ncarrying it: `process-timeout?`, `process-timeout-stdout`,\n`process-timeout-stderr`, built on a new `ErrorType` following the\n`channel_timeout` precedent. The partial output rides `uncaught_reason`\nrather than the irritants list -- an uncaught timeout prints its irritants,\nand a child that wrote megabytes before stalling should not print them.\n\nFour choices worth naming. `timeout:` implies `new-group: #t`, because\n`process-kill` refuses `'group:` on a child sharing the parent's own group\nand because the group kill is what lets the drains reach EOF when a\ngrandchild inherited the pipe. The kill is SIGKILL: a timeout is a bound,\nand a child ignoring SIGTERM would make it a suggestion. stdin is `'null`\nunless `input:` is given, so a one-shot capture never blocks on the\nterminal. And `output: 'bytevector` exists because the default path ends in\n`utf8->string`, which would otherwise fail a binary-producing child with a\ntype error naming a procedure the caller never called.\n\nNative-tier coverage extends the existing compile script rather than adding\na second one: `run-process` has its own reason to be there, since a\ncompiled binary runs `vm_bootstrap.install` from `runtime_exports.zig`\nrather than from `main.zig`.\n\n`docs/dev/subprocess.md` is new and covers all four phases -- the file\nlayout, the three park tiers, the thread-affinity rule, the two redirection\nrejections that are easy to trip over, and what the subsystem deliberately\ndoes not have.\n\nCloses #2417\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Make the run-process tests portable to NetBSD and OpenBSD\n\nTwo failures on the OpenBSD CI VM, both mine, both about assuming what a\nPOSIX box has.\n\nThe concurrent-drain test generated its bulk output with `yes | head -c`.\nOpenBSD's head has no -c, so the child exited non-zero and the assertion\nfailed for a reason unrelated to draining. `dd count=` is no better: on a\npipe it counts read() calls, not bytes. So the generator is /bin/cat and\nthe parent's own input is the bulk data — one case stdin -> stdout, one\nstdin -> stderr, both past the pipe buffer. All three streams at once is\nstill covered, portably, in process-run.scm, whose child is kaappi itself.\n\n`directory:` is not a portable option at all: NetBSD's and OpenBSD's libc\nhave no posix_spawn_file_actions_addchdir_np, so spawn-process rejects it\nthere with KP3007 rather than silently ignoring it. The test now asserts\nboth outcomes precisely -- the cwd on platforms that support it, that exact\ncode on the two that don't. A bare catch-all guard would have passed\neverywhere for the wrong reason, which is how an assertion becomes\ndecorative.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Pin the spawn-failure test to what POSIX actually guarantees\n\nThe Scheme suite asserted that a program that does not exist raises a file\nerror, using a bare name. OpenBSD returned (127 \"\" \"\") instead, and it is\nwithin its rights: POSIX leaves it unspecified whether a failed PATH search\nfails at posix_spawnp or lets the child exec fail and exit 127. OpenBSD's\nlibc does the search in the child, so the parent's spawn succeeds.\n\nThe strict assertion now uses an absolute path, where every supported\nplatform reports at the spawn -- which is what the unit suite was already\ndoing, and why it passed on the same VM.\n\nThe bare-name case is not dropped: it is pinned to whichever of the two\nPOSIX permits, so the difference is recorded rather than invisible, and\nthe test tightens when kaappi#2456 closes the gap with an exec error pipe.\nThat issue is why this is a test fix and not a shrug -- 127 is a plausible\nexit code for a program that really ran, so a mistyped command currently\nlooks like a completed run on OpenBSD.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Give riscv64 the same timeout headroom the Debug and macOS legs got\n\nThe riscv64 leg was cancelled at 30:21 with nothing in the log but the\nrunner terminating orphaned zig processes -- the exact signature the\ntimeout comment on the `test` matrix already describes twice. Healthy runs\nthere were sitting at 22-26 min against a 30-min cap before this branch,\nand the subprocess suites are expensive on that leg specifically: every\nchild a process test spawns is a whole /bin/sh emulated through binfmt\nQEMU, so it pays a large multiple of what the same tests cost natively.\n\n30 was a hang-bound when the suite was smaller. It is now exactly what the\ncomment says to avoid -- a cap that races the suite -- so this is the same\nfix, for the same reason, as PR #1635 (macOS) and PR #1728 (Debug).\n\nThe bulk-drain test also drops from 200_000 bytes to 70_000. Past the\n64 KiB pipe buffer is the only property it needs; the rest was byte\ntraffic the emulated legs paid for nothing.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Address review: refuse an unbounded timeout, and fix three vacuous tests\n\nFive findings from the review, all verified against the code first.\n\n`timeout:` with an explicit `new-group: #f` could hang forever. `grouped`\nhonored the override, so the timeout path issued a child-only SIGKILL; a\ngrandchild holding the child's stdout keeps the write end open, drain-into\nnever sees EOF, and the join blocks with no bound -- `quietly` catches\nexceptions, it does not bound time. The call then neither returned nor\nraised, so the bound `timeout:` promises was simply void. The suite already\nasserted that mechanism in the tree-kill test; nothing covered the override.\nThe combination is now refused at option-parse time, since it cannot deliver\nwhat it promises, and the kill branch is unconditionally the group form.\n\nThree tests did not test what they claimed:\n\n- The EPIPE feed used 65536 bytes, which is *exactly* Linux's default pipe\n  capacity rather than past it, so the write could land in the buffer whole\n  and never break; the `st = 0` assertion passed either way. Now 256 KiB, in\n  both the Zig and the Scheme suite.\n- process-run.scm used current-jiffy and jiffies-per-second without\n  importing (scheme time). They resolved anyway; that is luck, not a\n  contract.\n- The bulk-drain test scaled to 4096 bytes under -Dgc-stress -- below the\n  pipe buffer, so the stress leg ran a backpressure test that could not\n  fail. The scale-down is gone: the cost under stress is per allocation, and\n  a bulk read is a handful of them, so the byte count was never what made\n  that leg slow.\n\nSix single-assertion tests now use th.expectEvalTrue directly, per the\ntesting guideline. The local expectTrue stays for the tests that share one\ninteraction environment across several evals, with a comment saying so --\nmixing the two inside one test leaves gc_instance dangling when the\nhelper's context deinits.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Assert that the overlap tests overlap, not that they are fast\n\n`(< dt 0.75)` for two 0.4s children failed on a loaded macOS CI runner. The\nmachine had simply been slow; the test reported a concurrency bug that did\nnot exist.\n\nA wall-clock budget is the wrong instrument for this property. What the test\nmeans to check is that one run-process call's internal drain fibers do not\nblock another call's wait — so assert exactly that: record each call's start\nand end, and require the two intervals to intersect. A serialized\nimplementation yields disjoint intervals however fast or slow the machine\nis, because the second call could not have started until the first returned.\nNo budget, nothing to tune, and it cannot pass for the wrong reason either.\n\nBoth the Zig and the Scheme version also had to spawn both fibers before\njoining either: joining the first before spawning the second serializes them\nby hand and makes the assertion unsatisfiable — which is how the first draft\nof this fix failed.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n---------\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>",
          "timestamp": "2026-09-01T12:51:33Z",
          "tree_id": "67c6899913b27d0dd2556388e6e05f687e17ec71",
          "url": "https://github.com/kaappi/kaappi/commit/4aa2bab13522a185639856833dd09a05b5ae847c"
        },
        "date": 1788269708678,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.896272,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.585014,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.548902,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.786939,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004689,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046969,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.291391,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.063003,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.442041,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.104176,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.621093,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.303683,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.613732,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.838616,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045845,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "e8070ab0838b0ff23d4afc50724adbdb06c3b62f",
          "message": "Make SRFI 231 array-copy continuation-safe (#2461)\n\n* Make SRFI 231 array-copy continuation-safe (#2454)\n\n%array-copy-impl filled the destination directly: one interval-for-each\npass calling the source's getter and the destination's setter per index,\ninto a dest allocated before the loop. A getter that captured a\ncontinuation and re-invoked it after array-copy returned kept writing\ninto the array the first copy had already handed back, so the caller's\narray silently mutated under it -- the official suite's own case 737\nread ((4 1) (1 1)) where ((1 1) (1 1)) was required. The spec's whole\ndocumented difference between array-copy and array-copy! is that the\nnon-! one must be safe under exactly this.\n\narray-copy now collects every source value through a functional\naccumulator (no set!, so a re-entry re-runs the collection from its\ncapture point and materializes its own destination) before allocating\nthe destination, then fills it in a second pass. array-append, -stack,\n-block and -decurry delegate to array-copy, so one change resolves all\nfive known-divergence ids (737-741), which are pruned here.\narray-copy! keeps the direct fill, which the spec explicitly permits;\nthe assembly.sld header note about the four ! twins being pure aliases\nof the now-safe path is updated to match.\n\nMeasured on the 200x300 copies the perf note asked for: no regression\n(0.327s -> 0.327s specialized u8, 0.403s -> 0.395s generic-getter per\ncopy) -- one extra cons per element against a loop that already\nallocates a rest list per apply is noise.\n\nCo-authored-by: ZCode <noreply@z.ai>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Collect array-copy's values into a scratch vector, not a cons list (review)\n\nThe cons accumulator the first cut used holds N pairs live (2N more\ntransiently across the reverse) for exactly the same continuation\nsemantics a pre-sized scratch vector gives: the review's suggested\nshape -- a lexicographic index threaded functionally through the walk,\n(cons val acc) becoming (begin (vector-set! buf k val) (+ k 1)) -- so\nthe two passes now share one %domain-walk helper (they differed only in\nleaf body and could not drift out of order-agreement), and at 1M\nelements total pair allocations drop 18.0M -> 16.0M with the N live\npairs gone. The churn that remains is the library apply shape every\nfill loop already shares (kaappi#2464).\n\nThe copy-out's no-continuation-here claim is also corrected: a\ndestination storage class from make-storage-class contributes\nuser-written setter code there, so a capture re-enters with the\ndestination already allocated and hands back the same object (identical\ncontents) -- the same residual the reference implementation has; the\ncomments and CHANGELOG now say so instead of asserting an absolute.\n\nCo-authored-by: ZCode <noreply@z.ai>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n---------\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-authored-by: ZCode <noreply@z.ai>",
          "timestamp": "2026-09-01T16:14:02Z",
          "tree_id": "8988f1e7eec585b519c67bc0da0af75deb0a2177",
          "url": "https://github.com/kaappi/kaappi/commit/e8070ab0838b0ff23d4afc50724adbdb06c3b62f"
        },
        "date": 1788281768926,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.32406,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.949911,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.562163,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.937856,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004452,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.04786,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.300155,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.056359,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.954474,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.210457,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.662571,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.271313,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.703104,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.640784,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.046326,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "997a2a259d7ef4e093cf36b3c9fcea4d5bd0973b",
          "message": "Report OpenBSD exec failures at the spawn; close wrapped and test fds by default (#2462)\n\n* Report OpenBSD exec failures at the spawn, and close wrapped/test fds by default (#2456, #2424, #2422)\n\nThree fd-hygiene fixes around exec, one per issue:\n\nreport the child's exec failure, so a bare program name the PATH search\nmissed \"succeeded\" and the child exited 127 -- indistinguishable from a\nprogram that ran and failed. That platform now spawns through fork +\nexecvp with a CLOEXEC error pipe (CPython subprocess's mechanism): the\nchild installs the same redirections the file actions carried, closes\nevery inherited non-CLOEXEC fd >= 3, writes its exec errno to the pipe\nand only then _exits 127; a successful exec closes the pipe via\nFD_CLOEXEC, so the parent's read returns exactly at the exec and the\nerrno rides the same catchable file error every other libc reports. The\nparent resuming only at the exec is also the signalability property the\nNetBSD exec barrier exists to restore, gained for free here. The\nadvisory access() pre-flight for slash-paths is superseded and removed.\nThe bare-name assertions in process-run.scm (written leniently for this\ngap) and tests_process_run.zig are strict again; reproduced before/after\non the OpenBSD 7.9 aarch64 reference VM.\n\nFD_CLOEXEC state, so on Linux and the BSDs every spawn-process child\ninherited it (a live kaappi-net socket could reach the child). The wrap\n(makeFdPort) now sets FD_CLOEXEC -- safe by construction, since Kaappi\nexecs only through spawn-process, whose stdio install clears the flag\non exactly the child's slots. A foreign side that wants a child to\ninherit its descriptor must prepare the fd itself.\n\nmakeBidiFdPair, bench_reactor's makePipe) and the hand-rolled fork/exec\nplumbing in test_runner.zig and test_selection.zig called pipe(2) and\nsocketpair(2) directly, bypassing platform.pipe's CLOEXEC discipline.\nAll routed through platform.pipe / setFdCloexec; no direct std.c.pipe or\nstd.c.socketpair call remains outside platform.zig in test/dev code.\n\nCo-authored-by: ZCode <noreply@z.ai>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Guard setFdCloexec/getFdFlags for Windows: fcntl does not link there\n\nmakeFdPort's new unconditional FD_CLOEXEC call (kaappi#2424) pulled\nplatform.setFdCloexec into the Windows link for the first time, and its\nplain extern fcntl has no CRT counterpart -- both windows-cross legs\nfailed at lld-link with 'undefined symbol: fcntl'. Both fd-flag helpers\nnow no-op for Windows targets like they already did for wasm: FD_CLOEXEC\nis a POSIX exec concept, and process_win confines child inheritance to\nan explicit stdio handle list, a stronger guarantee than any\nclose-by-default scan, so there is nothing for the flag to do there.\n\nCo-authored-by: ZCode <noreply@z.ai>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Give the timeout-content tests loaded-runner headroom\n\nThe timeout tests that assert WHAT the drain recovers (\"partial\",\n\"printed\", \"half\", \"up\") all used 250-500 ms deadlines, which assume\nthe child gets a scheduling slot before the kill. On a loaded runner it\ndoes not always: the openbsd-test leg failed process-spawn-2414.sh this\nway (expected '(4 70000 err)\\npartial', got no partial), and on the\nOpenBSD reference VM under four CPU hogs the same shape loses its output\n11/50 times on unmodified main (4aa2bab1) and 4/50 on this branch -- a\npre-existing test race, not a spawn-path change (the fork+exec path, if\nanything, sampled better). The engine is behaving correctly: a kill that\nlands before the child ever wrote drains an honest empty string.\n\nEvery such deadline now has seconds of headroom (2 s, 3 s where a\ngrandchild interpreter must start up too); the deadline's job in these\ntests is only to fire eventually, and the assertion is about the\nrecovered content. Re-verified under the same CPU-hog load: 0/50.\n\nCo-authored-by: ZCode <noreply@z.ai>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* ci: retrigger workflows for 97e5076c\n\nThe pull_request event for 97e5076c was lost — the branch and PR head\nboth point at it, but Actions shows zero runs for that SHA (the two\nprior pushes triggered normally). An empty commit to force a fresh\nsynchronize event; no content change.\n\nCo-authored-by: ZCode <noreply@z.ai>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n---------\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-authored-by: ZCode <noreply@z.ai>",
          "timestamp": "2026-09-01T18:02:53Z",
          "tree_id": "3582afb745e3e61d8e34b18fc8272436077eca01",
          "url": "https://github.com/kaappi/kaappi/commit/997a2a259d7ef4e093cf36b3c9fcea4d5bd0973b"
        },
        "date": 1788288596664,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.273142,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.246428,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.563154,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.980661,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004449,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.064223,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.305908,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.056293,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.804267,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.211756,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.642774,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.284105,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.222084,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.667845,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.046528,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "17fe3fbe33671b43faceafe12d62250559c87723",
          "message": "Discard expected-error stderr in the stepper tests (#2447) (#2465)\n\n* Discard expected-error stderr in the stepper tests (#2447)\n\ntests_step looked like it killed the unit-test binary in the aarch64\npodman container: after the two expected-error stepper tests the output\nended in a red warning block and a \"failed command: .../unit-tests\n--listen=-\" line with no pass/fail summary. It never crashed. The two\ntests legitimately drive the runFile-style error path, whose KP3002\ndiagnostics go to the process's real stderr; zig's build runner captures\nthat fd, and a step whose captured stderr is non-empty -- even a fully\ngreen one -- is rendered with a red ' w' marker, the stderr, and a red\n\"failed command\" provenance line, while the default summary mode prints\nno summary at all for a successful run. Expected output plus silent\nsuccess reads exactly like a crash.\n\nVerified in kaappi-builder-arm64 on the exact repro from the issue: the\nfiltered run exits 0 with all 13 tests passing (reproduced the display\nunder a pty byte-for-byte), the full suite runs to completion --\n1990/2010 passed, 20 skipped, 0 failed, exit 0 -- and running the test\nbinary directly prints \"All 13 tests passed\". Nothing was ever lost.\n\nFix the confusion at its source: a new QuietStderr test helper (the same\ndup/dup2 juggling the fuzz harness uses for stdout) redirects fd 2 onto\nthe null sink for the two expected-error stepper tests, so a green run\nof that filter is now completely silent everywhere. With it, the issue's\nrepro command prints nothing and exits 0, and the full container suite\nshows no warning marker on the unit-tests step. The helper is\nmutation-tested: breaking the dup2 round-trip fails its unit test.\n\nSide finding, out of scope here: 'process-wait phase2: group kill\nreaches the child's own child' fails under a container whose PID 1 never\nreaps adopted orphans (e.g. 'podman run -d ... sleep infinity'): the\nkilled grandchild stays a zombie, kill(pid, 0) keeps succeeding, and the\nESRCH poll times out. The issue's one-shot 'bash -c' PID 1 reaps, so\nthat test passes in the reported environment.\n\nCo-authored-by: ZCode <noreply@z.ai>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Guard QuietStderr.deinit against wasm sema of dup2 (#2447)\n\nThe wasm CI job failed at the wasmtime door with \"unknown import:\nenv::dup2 has not been defined\": init/initOnto bail at comptime under\nis_wasm, so their bodies are never analyzed on that target, but deinit\nwas guarded only by the runtime if (!self.active) return; -- semantic\nanalysis of platform.dup2(...) ran regardless and exported the call as\na wasm import that nothing defines. The comptime bail is now the first\nstatement of deinit as well, and a doc note on the method records the\nrule: on WASI every method that names dup/dup2 needs the guard, because\neven an unreachable-at-runtime call generates the import.\n\nVerified: the tests_step filter stays silent and green, the helper's\nown unit test passes, the wasm32-wasi test binary no longer imports\nenv::dup/env::dup2, and the CI invocation (wasmtime run --dir=.\n--dir=/tmp zig-out/bin/unit-tests.wasm) reports 1628 passed;\n295 skipped; 0 failed.\n\nCo-authored-by: ZCode <noreply@z.ai>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n---------\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-authored-by: ZCode <noreply@z.ai>",
          "timestamp": "2026-09-02T05:46:09+05:30",
          "tree_id": "be88c47fce8a24568c3be1ca401c77226ce8ff28",
          "url": "https://github.com/kaappi/kaappi/commit/17fe3fbe33671b43faceafe12d62250559c87723"
        },
        "date": 1788310917363,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.270634,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.282676,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.563164,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.932285,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004443,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.050013,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.300429,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.055733,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.837296,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.212612,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.707366,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.283297,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.689081,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.634631,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.046578,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "f7d6173a730ca9c3336501ef59afa8e547dc25e8",
          "message": "apply/call-with-values: resumable cwv producer (#2453) and unit-wide gate decline for redefined names (#2457) (#2467)\n\n* Report KP3000 when a resumed call-with-values producer returns past its native driver (#2453, part 1)\n\nA continuation captured inside call-with-values' PRODUCER, resumed after\nthe form returned, did not report the honest 'continuation cannot resume\nacross a returned native call' (KP3000) that every other returned-native-\ncall resume raises. The producer's frame was pushed by callThunk with\nreturns_to_native = false, so its late return fell through the dispatch\nloop's raiseDeadNativeReturn check and delivered the value into a stale\nregister of the enclosing bytecode frame, which the following apply then\nmisread: 'error[KP3002]: apply: last argument must be a list', blaming an\noperand the user never wrote.\n\ncallThunkReturningToNative pushes the closure frame with\nreturns_to_native = true, the same marker callWithArgs-driven natives\n(map, fold, hash-table-walk, ...) already get for their callbacks, so the\nresumed producer's return raises the accurate catchable error instead.\ncallWithValuesFn and %call-with-values->list both use it for their\nproducer call. Native and native-closure thunks push no VM frame and are\nunchanged.\n\nThe superinstruction lowering's own producer stops running under a native\nframe entirely in part 2; this fix keeps the diagnostic accurate for every\nroute that still drives it natively -- the by-name call a declined fast\npath compiles to, once the name is restored to the genuine binding.\n\nTests: tests/scheme/continuations/callcc-cwv-native-kp3000-2453.scm --\nnon-tail and tail, asserting the KP3000 message (the guard encloses the\ncapture: a resume restores the handler stack as of capture time, so a\nguard entered after the form returned cannot see the error).\n\nCo-authored-by: ZCode <noreply@z.ai>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Lower call-with-values' producer with an ordinary call opcode (#2453, part 2)\n\n#2451 moved call-with-values' consumer into the dispatch loop; the producer\nkept running under the native %call-with-values->list frame, so a\ncontinuation captured inside it still could not be resumed after the form\nreturned -- R7RS-small requires call/cc to produce fully re-entrant\ncontinuations, and call-with-values is a core procedure.\n\nThe lowering now emits, in order:\n\n  - a call of %call-with-values-check, which type-checks BOTH operands\n    exactly where callWithValuesFn did -- producer first, before anything\n    runs, same typeError texts -- so a bad producer or consumer is still\n    reported as call-with-values, not as the apply the form compiles into,\n    and not after the other operand's side effects;\n  - an ordinary `call` of the producer (0 args): its frame is a VM frame in\n    the caller's bytecode, copied by continuation capture and restored by\n    resume like any other, so a resume re-enters the producer's body and\n    its return delivers through the normal frame path;\n  - a new `values_list` opcode (dst:u16, src:u16, appended last in the\n    OpCode enum per the .sbc numbering constraint) that spreads the\n    produced value -- single, or a MultipleValues object from values --\n    into the fresh argument list the following apply reads;\n  - the same apply/tail_apply of the consumer as before.\n\nA resume therefore re-runs the spread and the consumer with the newly\nproduced values. %call-with-values->list is gone: nothing emits it, and\nthe native callWithValuesFn (the by-name route a declined fast path\ncompiles to) keeps part 1's honest KP3000 for its own producer.\n\nREADME's Known limitations drops the producer corner from the restricted\nlist; the exempt list now credits both halves. New opcode documented in\ndocs/dev/bytecode.md, the OpCode count gate and the four files quoting it\nupdated (33).\n\nTests: tests/scheme/continuations/callcc-cwv-producer-reentry-2453.scm --\nnon-tail and tail producer re-entry, several/no values, a resume\nre-spreading newly produced values, and the ordinary semantics plus all\nthree diagnostic shapes (bad consumer before the producer runs, bad\nproducer, both bad producer-first, consumer arity).\n\nCo-authored-by: ZCode <noreply@z.ai>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Decline the five fast paths for names the compilation unit redefines (#2457)\n\nA top-level redefinition of apply, call-with-values, eval, call/cc or\ncall-with-current-continuation was ignored by any procedure body compiled\nBEFORE the redefinition ran, in both tail and non-tail position: the body\nsilently ran the builtin and discarded the user's procedure. R7RS 5.3.1\nmakes a top-level definition essentially an assignment, so which binding a\ncall resolves is a run-time question; `globalBindingStillGenuine` answered\nit by reading the live global environment at COMPILE time, which is wrong\nwhenever compile order and definition order differ. #2033 fixed the\ndefine-first order that way; the use-first order kept baking in the builtin.\n\nEstablished while investigating (the issue's caveat): the #2033 gate is the\nONLY interpreter-tier decision that bakes these names in -- its decline path\nresolves by name at run time (isContinuationBarrier routes these names away\nfrom call_global toward the same by-name get_global + call, and neither the\ncompiler's nor the IR's constant folders fold them). Pre-#2452 the same gate\ndecided the in-body non-tail path, which is why the issue's A/B was clean.\nThe native tier has a second, independent gate: emitApplyForm's\nrebound_globals/native_fns sets are populated in emission order, so it had\nthe same use-before-define hole for the one name it lowers structurally.\n\nThe interim fix (the issue's cheaper option; the run-time-decision redesign\nis the recorded follow-up): drivers that know the whole compilation unit\npre-scan its top-level define/define-values/set! targets (through begin and\ncond-expand splices, like check.zig's lint collector), and\nglobalBindingStillGenuine declines for those names everywhere in the unit.\nThat costs the superinstruction only in programs that shadow these names at\nall -- the programs whose semantics were wrong. Wired into the file runner\n(cold and .sbc-HIT replay), stdin scripts, `kaappi compile`'s .sbc pass,\n`kaappi check` (reusing its existing collected set), and the native backend:\ncompileNative installs the same scan and emitApplyForm's `rebound` consults\nit, so the compiled binary honours a later redefinition too.\n\nEvery spine the scan walks is a guarded SpineWalk and the curried-define\npeel is step-capped: a datum-label cycle in code position (`(begin .\n#0=(1 . #0#))`, the #2405 family) must reach the run loop's own KP2001\ndiagnosis, not spin in the pre-scan.\n\nLeft on the legacy compile-time answer, deliberately: the REPL and `eval`\n(no future knowledge), and a redefinition that only materializes when a\nmacro expands. Library bodies inherit the enclosing run's set when there is\none (conservative, never wrong).\n\nThree tests moved, each because a unit-wide define of these names now\ndeclines the superinstruction for the whole file, which would conflate what\nthey pin with the gate's resolution rules: the begin-sibling-define pair\nfrom callcc-native-driver-reentry-2451.scm to top-level-redefinition-2033.scm,\nand the two tail_call_cc receiver-arity pins from the primitives_control\naudit to callcc-correctness.scm (the audit file redefines call/cc at top\nlevel, so the opcode's own diagnostic is unreachable from it).\n\nTests: tests/scheme/compliance/top-level-redefinition-order-2457.scm (all\nfive names, both positions, use-before-define plus define-first control,\nset! and begin-spliced redefinitions, non-procedure redefinition, car/map\ncontrast); tests/scheme/compile/native-apply-redefinition-order-2457.sh\n(compiled binary agrees with the interpreter for both orders, and a clean\nprogram keeps its native @kaappi_apply site with zero eval fallbacks); a\nZig unit test for the collector's shapes and non-captures.\n\nCo-authored-by: ZCode <noreply@z.ai>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Wrap README's line-initial issue refs in code spans (MD018)\n\nA wrapped line beginning with `#2451` parses as an ATX heading missing\nits space, which is the exact MD018 trap .markdownlint-cli2.jsonc names\n(the #1836 bug) and what turned the format job red on this PR. Wrap both\nissue refs of the call-with-values sentence in code spans - the wording\nstays as written; only the line-initial hash stops being heading syntax.\n\nCo-authored-by: ZCode <noreply@z.ai>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Give every check analysis entry point the exact unit target set (#2457)\n\n`kaappi check` installed the lint's user_defined set as the\nsuperinstruction gate's whole-unit target set. That set misses top-level\n`set!` targets, so a unit using `apply` early and assigning it late kept\nthe fast path during check's compiles while a run of the same file\ndeclines it - analysis and execution could disagree about what a form\ncompiles to. The install also lived in `run`, so the shared\n`analyzeSource` path (the language server, kaappi#1981) got no gate at\nall.\n\nCollect the gate set separately, with\n`compiler_passthrough.collectUnitTopLevelTargets` - the same scan a run\ninstalls, set! targets included, define-syntax names excluded - and\ninstall it in `analyzeSource` itself with the existing defer-based\ncleanup, so `run`, `analyzeForTest`, and the LSP all analyse under the\nexact set and only for the duration of the analysis. The lint keeps its\nown user_defined set, whose extra define-syntax names remain\nconservative for the unbound-variable warning.\n\nCo-authored-by: ZCode <noreply@z.ai>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Split the builtin gate and set! pre-scan out of compiler.zig\n\ncompiler.zig crossed the 1500-line file-size cap this PR pushed it over\n(1739 on main, 1751 after). Move the one cohesive section the PR grew -\nthe redefinition-awareness machinery - to a new compiler_gate.zig,\nverbatim: `globalBindingStillGenuine` (the builtin-bypass gate behind\nthe five superinstructions, including the #2457 unit-targets check) and\nthe `set!` pre-scan that feeds it (`SetScanBudget`,\n`collectSetTargets`, `scanSetTargetsWithoutMacros`, and the prescan\ncounters). Both halves answer the same question - can a compile-time\ndecision that a name still resolves to its built-in survive until the\ncode runs - for two redefinition routes; neither emits bytecode.\n\nCall sites updated (compiler.zig's compile paths, native_compiler.zig,\ntests_prescan.zig) and architecture.md's compiler table gains the row.\ncompiler.zig lands at 1406 lines; behavior is unchanged - the unit and\nScheme suites, including the #2457 ordering regressions and the native\ntier, pass as before.\n\nCo-authored-by: ZCode <noreply@z.ai>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n---------\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-authored-by: ZCode <noreply@z.ai>",
          "timestamp": "2026-09-02T08:46:02+05:30",
          "tree_id": "50f7d49ad6b3c08ebde43aeeb2494bc9e5e8bbf3",
          "url": "https://github.com/kaappi/kaappi/commit/f7d6173a730ca9c3336501ef59afa8e547dc25e8"
        },
        "date": 1788321495025,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.005575,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.044807,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.561214,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.867025,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004639,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046935,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.290514,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.053862,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.393927,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.147514,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.646628,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.297557,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.640167,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.769752,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.0453,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "c644b25197a4826a563ff2d9114436c3fb62f6f4",
          "message": "Add missing [Unreleased] CHANGELOG entry for #2467 (#2474) (#2476)\n\nPR #2467 (resumable call-with-values producer, unit-wide redefinition\ngate, values_list opcode) landed without an [Unreleased] entry. Add\n### Fixed entries for #2453 and #2457 and a ### Changed entry for the\nnew opcode, per the issue's outline.\n\nCloses #2474\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-authored-by: Claude <noreply@anthropic.com>",
          "timestamp": "2026-09-02T11:07:45+05:30",
          "tree_id": "1fd8b302b04714ee0be7e876e5fc1a98fbfad8de",
          "url": "https://github.com/kaappi/kaappi/commit/c644b25197a4826a563ff2d9114436c3fb62f6f4"
        },
        "date": 1788329191471,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.04214,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.753206,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.460306,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.186663,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.003727,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.036396,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.229934,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.042554,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 1.864311,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.894447,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.252936,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.24087,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.284266,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.470047,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.036065,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "ce0137242f842a77d61ab3cfb9db52e9099736c3",
          "message": "Detach SRFI-18 OS threads and back off in cross-thread waits (#2446) (#2468)\n\n* Detach SRFI-18 OS threads and back off in cross-thread waits (#2446)\n\nsrfi18-join-spawn-grandchild-2129.scm hung intermittently on NetBSD under\nCPU load, and the first investigation read gdb's \"frozen PC, no syscall\"\nchild thread as the kernel stranding a freshly created LWP. The kernel's\nown per-LWP view (ps -s) showed the process with 23 LWPs, 18 runnable,\nburning three CPUs: 17 threads leaving thread-sleep! spinning in\nmemory.spinLock inside withdrawCrossThreadWaiter at priority 25-27, while\nthe holder -- preempted inside the kevent ring wakeCrossThreadWaiters\nissues under the lock -- sat runnable at priority 0 and never ran again.\n\nTwo NetBSD 4BSD-scheduler facts combine into that. First, a nice-0 LWP's\npriority is 63 - estcpu/2048 - 20 and the per-tick accumulation is capped\nat 18*2048, so running can take a thread no lower than 25 -- but\nsched_lwp_collect, run in _lwp_wait on the JOINING LWP, adds the reaped\nLWP's estcpu with no cap, and sched_lwp_fork copies the joiner's estimate\ninto every LWP it creates. The interpreter thread joins every middle\nthread; after three joins it is at priority 0 and so is every thread it\nspawns from then on -- born below every ordinary process, which under CPU\ncontention starves them outright (the \"child parked at\npthread__create_tramp+0 forever\" of the original report). A 40-line C\nprogram reproduces it: join three busy threads, then a trivial child of\nmain takes 0.8 s to run under four burners; detach them instead and it\ntakes 0 ms, like the no-join control. Second, sched_yield requeues only\nbehind LWPs of the same priority, so a crowd spinning -- or yielding -- on\na lock held by a preempted thread never lets it back in.\n\nSo: SRFI-18 OS threads are detached the instant they are spawned (a\ndetached LWP is freed at exit with no estcpu transfer) and thread-join!\nwaits on a per-spawn exit flag (Fiber.os_exit) the child raises after its\noutermost defer, which covers exactly what pthread_join covered. And every\ncross-thread wait that was a pure spin -- memory.spinLock, the GC\nstop-the-world handshake on both sides, GlobalsRwLock, and the new reap\nwait -- goes through platform.spinBackoff: 32 spins, 64 yields, then\nsleeps doubling from 32 us to 1 ms, so a waiter leaves the run queue and a\npreempted holder gets its turn. Neither changes the uncontended path.\n\nOn the NetBSD 10.1 aarch64 reference VM (40 s bound per run), unmodified\nmain hung 5 of 8 runs under four CPU burners and 4 of 10 under eight; the\nbackoff alone still hung 4 of 8; with the detach as well, 0 of 20 under\nfour burners (and 0 of 10 of srfi18-terminate-native-wait-1982.scm, the\nother test the CI kill hit) and 0 of 30 under eight. Regression tests pin the\ntwo properties the hang needed: contenders on a held spin lock must not\nburn CPU (four spinners cost 518 ms of CPU across a 120 ms hold before),\nand thread-join! must not return before the child's whole epilogue.\nPostmortem: docs/dev/postmortems/2026-09-02-netbsd-spinlock-starvation.md.\n\nCo-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Note the upstream NetBSD estcpu fix and its netbsd-10 gap (#2446)\n\nNetBSD fixed sched_lwp_collect's missing ESTCPULIM in sched_4bsd.c rev\n1.48 (2026-03-01) and pulled it up to netbsd-11 (ticket #233), but not to\nnetbsd-10, so every 10.x release -- the reference VM and the CI image --\nstill has the bug. Record that where the postmortem and the NetBSD port\ndoc describe the defect, so nobody reads them as \"report this upstream\"\nor as \"the detach can go once the kernel is fixed\": it stays for as long\nas 10.x is a supported target.\n\nCo-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Address review on #2468: synchronize the CPU-burn test, pin the backoff schedule, tighten the docs\n\n- The contention test now waits for all four workers to reach the lock\n  call before the 120 ms hold starts, so a loaded box cannot let them\n  acquire it uncontended after the unlock and pass vacuously; and a\n  clock_gettime failure skips the test instead of comparing garbage.\n- The pub phase constants now have the consumer their comment promised:\n  tests_platform.zig checks that spinBackoff's spin and yield phases do not\n  sleep, that the first iteration past them sleeps >= 32 us, and that the\n  capped one sleeps >= 1 ms.\n- Docs: the reactor guide's wait inventory names the reapOsThread exit-flag\n  wait; the postmortem's Status carries the fixing commit, its LWP table\n  accounts for all 23 rows, its priority formula includes the nice offset\n  (as does netbsd.md's) so the 25 floor derives on the page, and the\n  process-TIME lesson defers to the per-LWP columns.\n\nCo-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n---------\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-authored-by: Claude Fable 5.1 <noreply@anthropic.com>",
          "timestamp": "2026-09-02T05:17:50Z",
          "tree_id": "5b9f7d35e0d4c7d3964a0916ab961b5fdf6feddc",
          "url": "https://github.com/kaappi/kaappi/commit/ce0137242f842a77d61ab3cfb9db52e9099736c3"
        },
        "date": 1788329757477,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.313321,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.772569,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.59801,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.999578,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004667,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.048177,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.304969,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.055319,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.777503,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.219861,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.657983,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.303951,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.723082,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.71136,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045544,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "ebc418ed73711dd57390d375f9203893f973a441",
          "message": "CI: require a CHANGELOG.md entry for src/lib/vendor changes unless labeled no-changelog (#2475) (#2477)\n\nA PR that changes src/, lib/ or vendor/ but not CHANGELOG.md now fails\nthe new 'changelog' job, unless the PR carries the 'no-changelog'\nlabel. The label is read live via gh pr view rather than from the\nreplayed event payload, so applying the label and re-running the job is\nenough -- no new push needed (a re-run replays the original event).\n\nScope and semantics per #2475: all of src/, lib/ and vendor/ (wider\nthan the src/ + lib/srfi/ gate dropped in #2103), tests/-only and\ndocs-only changes outside the gate, presence-only check -- entry\nwording stays with the author. The file list comes from the same\npaginated pulls/files endpoint the format classifier uses.\n\nValidated by dry-running the decision logic against 12 synthetic\nchanged-file sets (src/lib/vendor alone, with CHANGELOG.md, with the\nlabel, tests-only, docs-only, workflow-only, prefix near-miss,\nmixed). No CI-script test harness exists in the repo; noted in the PR.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\nCo-authored-by: Claude <noreply@anthropic.com>",
          "timestamp": "2026-09-02T06:09:36Z",
          "tree_id": "9a4cb0afb289fac048a8e95930d279810a567bac",
          "url": "https://github.com/kaappi/kaappi/commit/ebc418ed73711dd57390d375f9203893f973a441"
        },
        "date": 1788333207321,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.953322,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.094736,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.57193,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.842288,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004766,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.04763,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.29872,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.054908,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.524368,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.164586,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.610071,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.303225,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.638308,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.788325,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045952,
            "unit": "seconds"
          }
        ]
      }
    ]
  }
}