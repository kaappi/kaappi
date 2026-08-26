window.BENCHMARK_DATA = {
  "lastUpdate": 1787732333518,
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
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "95daff9964f6a80d03e28dbf48923b1cb874b1b9",
          "message": "Fix SRFI-178 bitvector-logical-shift shifting the wrong way (#2083) (#2258)\n\nThe spec says count>=0 is a logical left shift (toward lower indices,\nout[i] = bvec[i + count]) and count<0 a right shift (toward upper\nindices, out[i] = bvec[i - |count|]), with vacated elements filled with\nbit. Both sign branches were inverted relative to the reference\nimplementation: the left branch wrote out[i] = bv[i - count] and the\nright branch out[i] = bv[i + |count|], so every non-zero shift moved\nbits in the wrong direction. The loop bounds were coupled to the wrong\nformulas and had to move with the fix (left: i in [0, n-count), right:\ni in [|count|, n)).\n\nEnabled the four audit assertions that were disabled pending this fix\n(the first two are the SRFI's own test/quasi-ints.scm cases verbatim)\nand corrected the two bitvector-logical-shift values in srfi178.scm\nthat had pinned the buggy behavior. The count-0 identity and full-length\nshift controls still pass, and 1024 differential cases now agree with\nthe reference implementation.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>",
          "timestamp": "2026-08-08T08:09:55Z",
          "tree_id": "3301fbf213433c2bccaf1c32a0717b2abd538a1c",
          "url": "https://github.com/kaappi/kaappi/commit/95daff9964f6a80d03e28dbf48923b1cb874b1b9"
        },
        "date": 1786178638905,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.067996,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.417034,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.412054,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.177457,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004411,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.036573,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.232921,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.041351,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.124157,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.932887,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.183698,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.227809,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.312034,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.861764,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.036636,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "d2a8d2c8fde5963207bad3c2bad8df0bcc10ce54",
          "message": "Persist #!fold-case across read calls on the same port (#2259)\n\nR7RS 7.1.1: a #!fold-case directive affects reading 'from the same port'\nfrom the point it appears on. readDatumFn built a fresh Reader per call,\nso the flag died with it: the first (read p) folded, the second did not.\n\nStore the mode on the Port (Port.fold_case). Each call's Reader is seeded\nfrom it, and the Reader's final flag is written back after a successful\nparse — the string-port, incremental fd and post-EOF sites in readDatumFn\nall persist; the peek-byte-only path only seeds, since a lone byte cannot\nhold a directive. #!no-fold-case resets the same field.\n\nThe within-call chunk-boundary handling (Reader.saw_directive) is\nuntouched: a split directive is still re-parsed from the kept buffer, and\nthe write-back only fires once a datum parse succeeds.\n\nRe-pin the Port field inventory in tests_gc_tracing.zig (plain bool, no\nGC obligation).\n\nFixes #2175.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>",
          "timestamp": "2026-08-08T14:03:02+05:30",
          "tree_id": "bdd85902106599d408e02ba35e39890ee2d2436f",
          "url": "https://github.com/kaappi/kaappi/commit/d2a8d2c8fde5963207bad3c2bad8df0bcc10ce54"
        },
        "date": 1786179749294,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.333281,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.937971,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.577313,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.008749,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00471,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.047483,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.310925,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.05602,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.715746,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.185461,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.627206,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.283412,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.781275,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.634834,
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
          "id": "395e9d6eaaf6b4af00fb0c882f4a5eb83f9a8a63",
          "message": "Fix rational→flonum conversion past f64 range; close the m/2^k complex read-back gap (#2183, #2182) (#2257)\n\n* Fix rational->flonum conversion when a side alone leaves f64 range (#2183)\n\n(inexact (/ 1 (expt 2 1074))) was 0.0 instead of the min subnormal, and\n(inexact (/ (+ (expt 2 1030) 1) (expt 2 1000))) was +inf.0 instead of\n2^30, because every rational->f64 path computed toF64(num)/toF64(den):\neach side saturates to inf independently, so the quotient was wrong\nwhenever one side alone overflowed while the true quotient was\nrepresentable. inf/inf gave nan on the parser paths (string->number,\nread), which had no band-aid, and inexact only survived via a special\nquotient/remainder retry that caught inf/inf alone.\n\nAdd types.rationalToF64: both magnitudes are normalized to their top 64\nsignificant bits, the quotient is computed to 64+ significant bits with\na u128 division (a plain f64/f64 ratio of truncated operands is off by\n1-2 ulp, and a short quotient loses mantissa precision), rounded to 53\nbits with round-half-to-even, and the removed power of two is re-applied\nwith a frexp + exact-power multiply that rounds through the subnormal\nrange correctly -- including the exact tie at 2^-1075, which\nstd.math.ldexp mishandles (rounds it up to the min subnormal).\n\nAll five call sites now route through it: types.toF64, primitives.toF64\n(which also fixes SRFI-18 getSleepSeconds), toF64Ext, inexactFn (band-aid\ndeleted), and applyExactness's .inexact arm. Verified bit-for-bit against\na correctly-rounded Python oracle over 3301 cases spanning powers of two\nfrom 2^-1100 to 2^1100, random bignum ratios, lopsided numerator/\ndenominator sizes, and the m/2^k round-trip shape.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Accept bignum rational complex parts; close the m/2^k read-back gap (#2182)\n\nPR #2181's exact-complex printer emits m/2^k spellings (odd mantissa up\nto 2^53, denominator 2^k up to 2^1074) for tiny exact-flagged\ncomponents, but the reader's complex grammar stopped at i64 rational\nparts, so (write #e1e-300+1i) could not be read back: a loud read error,\npinned in both directions by tests. #2183's scaled conversion makes the\nread-back safe (m/2^k converts back to exactly the f64 that produced\nit), so the grammar can open up.\n\nBoth parsers now accept bignum rational complex parts -- real, imaginary,\nand signed pure-imaginary -- gated on exact f64 representability via a\nshared helper (bignum.parseRationalToF64 + rationalExactInF64): a\nrational like 10^25/3 whose value would silently round stays a loud\nread error (and string->number #f), preserving the never-masquerade\npolicy of #2243. The reader's four bignum-rational paths (readNumber and\nreadIntegerWithRadix, numerator- and denominator-overflow) gain a complex\ntail mirroring the i64-rational path, converting the real part through\ntypes.rationalToF64; string->number's parseComplexComponent routes\nthrough the same helper, so the two grammars cannot drift.\n\nAlso closes a small adjacent parity gap: the i64-rational-real path's\nimaginary part now runs the same round-trip exactness check as the main\ncomplex path, so 1/2+123456789012345678901234567890i is a loud read\nerror instead of silently rounding an exact-flagged component (the\nreader previously accepted it; string->number always returned #f).\n\nPins flipped: reader-exactness-gaps section 7 and the paired tests_numeric\ncell now assert the round-trip; the m/2^k shapes join the round-trip\nmatrix; gate rejections pinned; new scheme + unit tests cover #2183's\ninexact conversions end to end.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Document the rational->f64 and bignum-rational complex fixes in the changelog\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Route SRFI-18 sleep's rational arm through the shared scaled conversion\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Guard rationalExactInF64 against a zero numerator\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Address review: top-binade overflow, gate upper bound, radix imag, sticky-remainder rounding\n\nCodeRabbit and baijum's review found five real issues in the first pass:\n\n- Off-by-one overflow guard: frexp's significand is in [0.5, 1), so the\n  whole top binade [2^1023, 2^1024) lands on e == 1024 and is\n  representable -- (inexact (/ (+ (expt 2 1024) 1) 2)) was +inf.0\n  instead of 8.98846567431158e307. Guard is now e > 1024 with an exact\n  two-step scale through 2^1023 for e == 1024.\n\n- rationalExactInF64 had no upper bound: 2^2001/2 (power-of-two-reduced\n  to a huge value) passed the gate and converted to an exact-flagged\n  +inf.0. The normal-range branches now require bl <= k_eff + 1024.\n\n- tryComplexTailBigRational's imaginary magnitude ignored radix: a hex\n  literal read the imag as decimal (12 instead of 18). The scan now uses\n  the radix digit predicate and parses non-decimal magnitudes with\n  parseRadixUrealToF64.\n\n- The bignum-rational tail's imaginary part was not gated by\n  exactIntegerRoundTrips, so a bignum integer imag silently rounded\n  while claiming exactness. Now gated like the sibling paths.\n\n- The dead zone between the i64 limit and the bignum path: power-of-two\n  denominators in (10^6, i64max] (1/2^40+1i, the printer's own m/2^k\n  output) were rejected. The i64 path now shares the same exactness gate\n  (i64RationalExactInF64) in both the reader and parseRationalToF64.\n\n- Rounding precision: with operands truncated to 64 bits, a quotient\n  within ~2^-63 of a rounding tie could round the wrong way. Operands\n  are now reduced to 128 significant bits (u192 division) and the\n  division remainder is used as a sticky bit for half-ties, making the\n  conversion correctly rounded for all but the measure-zero case of a\n  true value within ~2^-128 of a tie. Verified bit-for-bit against a\n  correctly-rounded oracle over 5607 rationals including adversarial\n  half-ulp tie constructions, the top binade, and the subnormal tail.\n\nNew regression tests cover all of the above (unit + scheme), and the\nradix-prefixed bignum-rational complex cells CodeRabbit asked for are in\nthe round-trip matrix.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n---------\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>",
          "timestamp": "2026-08-08T15:29:31+05:30",
          "tree_id": "0c0aeca608c79f1a10832dded40726fc7efae5c0",
          "url": "https://github.com/kaappi/kaappi/commit/395e9d6eaaf6b4af00fb0c882f4a5eb83f9a8a63"
        },
        "date": 1786184649358,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 2.981891,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.7239,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.400864,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.119955,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004147,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.035137,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.223621,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.043271,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.172669,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.88608,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.162897,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.2351,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.279807,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.766569,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.039608,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "681af651ba741c55acc4c28c81c751361fc7788b",
          "message": "Make syntax-rules count-consistency depth-aware; seed empty-match depths (Fixes #682, #2082) (#2260)\n\n* Make syntax-rules count-consistency depth-aware; seed empty-match depths (#682)\n\nThe #682 fix (#2256) rejected every depth mismatch but one class of\nlegitimate SRFI 149 excess input: a depth-1 variable zipped against a\ndepth-2 driver whose group count differs. instantiateEllipsis compared\nellipsis counts across DEPTHS and raised EllipsisCountMismatch, so a\nlegal macro like\n\n    ((_ (a ...) ((b ...) ...)) '(((a b) ...) ...))\n\nerrored on (ragged (x y) ()) where chibi (the SRFI's reference\nimplementation) and guile both expand to (). Two root causes:\n\n1. The count check was not depth-aware. R7RS 4.3.2 requires equal\n   counts only among variables matched at the same depth; SRFI 149\n   rule 2 zips a shallower variable against the driver (min counts).\n   joinRepeatCount now enforces equality only within a depth and\n   otherwise takes the min, keeping the kaappi#78 same-depth error.\n\n2. matchEllipsis seeded every ellipsis binding with depth 1 and only\n   corrected it per repetition, so a nested variable matching ZERO\n   repetitions ((b ...) ... against ()) kept depth 1, never qualified\n   as a driver, and the run died with EllipsisNoPatternVariable.\n   Bindings are now seeded from the pattern structure (patternVarNesting\n   + 1), which agrees with the per-repetition formula when it runs.\n\nCloses #682 and #2082 (fixed by #2256 but never closed): the under-use\nand two-ellipses-per-pattern checks are verified on main, and this\ncompletes the remaining edge of the depth validation.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Address review: per-depth count validation, structural under-use check (#682)\n\nReview of #2260 found two correctness gaps in the first cut:\n\n1. The same-depth count check was order-dependent. joinRepeatCount latched\n   the \"driver depth\" to the FIRST referenced binding, so a leading shallow\n   variable made a genuine R7RS 4.3.2 / kaappi#78 mismatch between two\n   deeper same-depth drivers silently zip instead of erroring (m2 errors\n   but m does not). The check now validates one count per depth, then takes\n   the minimum across depths — order-independent.\n\n2. The under-use check only fired when the consuming ellipsis run was\n   instantiated, so an outer run matching ZERO repetitions let a deeper\n   under-use silently expand to (). The check is now structural: the\n   outermost run that references a binding computes its full consumption\n   depth (this run + consecutive ellipses + the inner ellipses it sits\n   under in elem_template) and raises EllipsisDepthMismatch up front. This\n   also covers vector patterns, whose ellipsis runs must be detected inside\n   the vector data (patternVarNestingWalk now mirrors the list semantics\n   matchPattern uses).\n\nAll new tests fail against the pre-review build and pass here: the m-shape\nin error-format.sh and tests_ellipsis.zig, the vector/nested empty-match\nunder-use cases in tests_ellipsis.zig and the smoke suite, plus the\ncorrect-depth empty-match control.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n---------\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>",
          "timestamp": "2026-08-08T15:45:39Z",
          "tree_id": "e89687ba0d81013007203e2733e5b3cefaad7529",
          "url": "https://github.com/kaappi/kaappi/commit/681af651ba741c55acc4c28c81c751361fc7788b"
        },
        "date": 1786206053174,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.322447,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.258385,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.576459,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.006174,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004687,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.047372,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.317166,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.05626,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.82478,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.240613,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.634216,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.284988,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.799747,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.647014,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.0446,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "161e142d969226ade12c53dc9628273c68d0d531",
          "message": "Fix c64/c128 zero-imaginary decode and complex hashing; pin #751 string->number exactness (#2261)\n\n* Normalize zero-imaginary c64/c128 elements and hash complex values\n\nTwo SRFI-160 bugs share a seam: decodeElement always materialized a\nComplex for c64/c128 elements, and number-hash could not hash one.\n\n#1951: a zero-imaginary (+0.0) element decoded to a Complex whose\nwrite output read back as a different type. decodeElement now decodes\n+0.0 imaginary to a plain real, matching make-rectangular and the\nstandalone complex printer; -0.0 keeps its sign and stays Complex.\n\n#1950: c64/c128 comparators could not hash any value because number-hash\nis abs-based and abs rejects Complex. number-hash now hashes a genuine\ncomplex by its components, so the comparator contract (equal values,\nequal hashes) holds for complex elements and default-hash handles\nstandalone complex numbers too.\n\nRegression tests: the audit file's #1950/#1951 cells are enabled, and\n#751's string->number complex exactness repros are pinned in the smoke\nsuite (the fix itself landed in #2181; the issue stayed open).\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Make number-hash total over SRFI-160's element domain; pin c64 -0.0\n\nCodeRabbit review follow-ups on #2261.\n\nnumber-hash's real branch inherited the pre-existing non-finite gap\n((exact (floor +inf.0)) raises), and the new complex branch routed\nnon-finite components straight into it — so a c64/c128 comparator was\nstill unusable on a vector with an infinite component, which SRFI 160\nlegitimately allows. Non-finite reals now map to fixed buckets (NaN,\n-inf.0, +inf.0) before the floor/exact path; the = contract still holds\n(+inf.0 = +inf.0 share a bucket, +nan.0 = +nan.0 is #f).\n\nTests: non-finite hash cells (real, complex, comparator, equal-hash) and\nthe parallel c64 -0.0-imaginary round-trip test, mirroring the c128 one.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n---------\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>",
          "timestamp": "2026-08-08T17:13:05Z",
          "tree_id": "4118253d04a41d762cc1639ac9c8af2e2e7b6bcd",
          "url": "https://github.com/kaappi/kaappi/commit/161e142d969226ade12c53dc9628273c68d0d531"
        },
        "date": 1786211446497,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.990748,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.922454,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.570986,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.853252,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00494,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.045827,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.302043,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.05418,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.319378,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.179054,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.555736,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.308133,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.705362,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.780368,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044895,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "6b1795651cc1710f0b3056890b49acbf14eee4a0",
          "message": "Fix SRFI-18 cross-thread state: symbol interning depth (#1935), mutex/terminate state machine (#1984), cross-thread continuation invoke (#1936) (#2262)\n\n* Fix SRFI-18 cross-thread state: symbol interning depth, mutex/terminate state machine, cross-thread continuation invoke\n\nThree Phase 5 audit findings (wrong-result, R7RS/SRFI-18 violations) in the\nSRFI-18 cross-thread machinery:\n\n#1935 - symbol interning was one thread level deep. GC.initForThread\npointed a child at its IMMEDIATE parent's symbol table, and a child GC's\nown 'symbols' field is never populated (its internings go to\nshared_symbols) -- so a grandchild interned into a table nothing else\nconsults: (eq? 'alpha (string->symbol \"alpha\")) at thread depth 2 was #f,\nan R7RS 6.5 violation, and the depth-1 ownership stamping that makes\nsymbols the one safe cross-heap write did not reach depth 2. Chain every\ndescendant to the ROOT's symbol table, foreign_symbols and owner id. The\nproduction path was already masked at depth 2 by #2230 passing the root\nVM to threadEntryFn; the latent trap in initForThread itself is now gone.\n\n#1984 - four SRFI-18 state-machine defects:\n  * mutex-unlock! never cleared 'abandoned' (spec: \"makes it\n    unlocked/not-abandoned\") -- a plain unlock of a mutex whose previous\n    owner died raised a spurious abandoned-mutex-exception on the next\n    lock.\n  * thread-terminate! destroyed an already-finished thread's result --\n    the terminated flag was stored before the status guard, and\n    thread-join! tests it first, so terminating a joined thread\n    retroactively erased what it returned. Terminating a finished thread\n    is now a no-op (\"If the _thread_ is not already terminated\").\n  * mutex-lock! accepted a terminated thread as owner -- per spec \"if T\n    is terminated the _mutex_ becomes unlocked/abandoned\"; the old code\n    recorded the dead thread as owner, permanently deadlocking every\n    later lock.\n  * self-termination joined as uncaught-exception with a void reason\n    instead of terminated-thread-exception -- the join reads the HANDLE\n    fiber, a different object from the thread's own current fiber, so the\n    handle's terminated flag is now set too.\n\n#1936 - invoking a continuation captured on another OS thread (reached\nonly through the shared-globals path, bypassing the deep-copy refusal)\noverwrote the invoking VM with the capturing thread's saved frames and\nproduced a value on which every R7RS type predicate answers #f -- a value\noutside the type lattice. Every continuation-invoke site now checks the\ncontinuation's owning GC and raises a catchable error instead.\nSame-thread invocation is unaffected.\n\nEach fix carries a regression test that fails without it (Scheme tests\nunder tests/scheme/srfi/, a GC unit test, and the audit file's pinned\n'TODAY' behaviours updated to the spec-correct ones). Two existing tests\nare updated: srfi18-mutex-state-owner-2125 (explicit owner must now be a\nlive thread) and srfi18-terminate-native-wait-1982 (the timed-lock case\nnow actually parks the child instead of passing only via the erase-a\nfinished-result bug).\n\nFull suite: 2093 Scheme/R7RS tests pass, 1716+ unit tests pass, and the\nunit suite stays green under -Dgc-stress=true.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Address review: wake fast-path waiters, self-contained same-thread control, contended slow-path test, stale audit header\n\nReview findings on #2262, all verified against the code:\n\n* mutexLockFn's fast-path terminated-owner release now wakes local waiters\n  (ctx.sched.wakeMutexWaiters) like the slow path already did, so a waiter\n  enrolled from a previous foreign unlock observes the release instead of\n  sitting parked until its poll cap or the deadlock error.\n* The #1936 test's 'same continuation still works on its own thread'\n  control invoked a top-level continuation, which re-enters the capture\n  point and never returns to the assertion -- the verdict was silently\n  skipped (5 passes, not 6). The control now captures and invokes a\n  continuation inside the assertion.\n* Added a contended variant of the terminated-owner mutex test that parks\n  through the waited path of mutexLockFn, exercising its separate copy of\n  the transition (previously only the uncontended fast path was pinned).\n* Rewrote the audit file's stale '-- BUG:' header above the lc-12/lc-13\n  assertions (now '#1984 FIXED', obsolete line numbers removed).\n\nThe 'critical' review claim that the slow-path branch skips the reactor\ntimer / deadline_ns cleanup is not applicable: that cleanup runs above the\nbranch (primitives_srfi18.zig:1686-1687, before the owner resolution), and\nrunSchedulerStep's epilogue already restores me.status to .running -- no\ncode change needed there.\n\nVerified: full suite 2093 pass / 0 fail; unit tests 1716 pass; new and\nupdated tests pass under -Dgc-stress=true.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n---------\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>",
          "timestamp": "2026-08-08T20:09:46Z",
          "tree_id": "996e499aeddb0a51c916842575a39fe078eb5003",
          "url": "https://github.com/kaappi/kaappi/commit/6b1795651cc1710f0b3056890b49acbf14eee4a0"
        },
        "date": 1786221894320,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.01632,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.650348,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.593333,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.894013,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.005295,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.04656,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.302079,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.055025,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.445659,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.185997,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.579217,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.307104,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.744192,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.842122,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045558,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "042421e258a320442a69b471cd9a8ae4603668bc",
          "message": "Honor top-level redefinitions of the five tail fast-path names (Fixes #2033) (#2263)\n\n* Honor top-level redefinitions of the five tail fast-path names (#2033)\n\ncompiler.zig's tail-position dispatch sent (apply ...), (eval ...),\n(call/cc ...), (call-with-current-continuation ...) and (call-with-values ...)\nto hand-written superinstructions guarded only by resolveLocal/resolveUpvalue.\nA *global* rebinding of the name was never consulted, so a program that\nredefined one of them at top level got its own definition everywhere except in\ntail position, where the builtin ran instead and the user's procedure was\nsilently discarded. R7RS 5.3.1 makes a top-level definition essentially an\nassignment, so both positions must resolve the user's binding.\n\nThe fix gates each fast path on the compile-time global binding, mirroring\nIR.isRedefined and lookupGlobalLocked's resolution order (raw name, then the\nhygienic-prefix fallback to the bare name). set! targets in the enclosing form\nand the restricted-env not-found case decline the fast path the same way the\nfold gate does; a truncated pre-scan (set_targets_all) conservatively blocks\ntoo. The gate costs nothing at run time — it only decides which bytecode the\ncompiler emits.\n\nAdjacent fixes the gate forced:\n\n- Compiler-synthesized references in the let-values / let*-values /\n  define-values / case-lambda / define-record-type desugarings minted bare\n  apply/call-with-values symbols that were indistinguishable from user text\n  and would have been routed to a user redefinition. They now carry the\n  base-binding prefix (#1715) so they stay bound to the pristine (scheme base)\n  procedures, and the dispatch recognizes the prefixed spelling as immune.\n  ir.zig lowers a base-prefixed special-form head as a passthrough so it\n  still reaches compileForm's dispatch instead of bypassing it as a plain call.\n- The LLVM native backend's emitApplyForm mirrored the interpreter's old\n  tail-applies-ignore-rebinding behavior; it now gates on the module's\n  rebound/native redefinitions the same way (#1803 parity).\n- define-values' single-name desugaring also synthesized a bare\n  consumer; it is base-prefixed too.\n\nTests: a new compliance suite (all five names, non-procedure redefinitions,\nhygiene-renamed macro-template references, set!-in-form, desugaring immunity),\nthe previously disabled audit assertions re-enabled with real top-level\nredefinitions, a Zig unit test, and the native apply-lowering test's rebound\ncase updated to the corrected expectation. Full suite: 700 Scheme files and\n1395 R7RS assertions green.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Address review: R6RS record coverage, native <2-operand gating, doc cleanup\n\nReview findings on PR #2263:\n\n- CodeRabbit: the define-record-type test used R7RS constructor-first\n  syntax, where (parent ...) parses as a field spec — it never reached the\n  R6RS inherited-constructor paths in vm_records whose synthesized apply\n  references this fix touches. Replace it with top-level R6RS clause-syntax\n  records that exercise BOTH inherited-ctor variants: the protocol-less\n  split-args path and the protocol path. Both fail on main (the bare apply\n  resolved to the user's redefinition) and pass here. While in those paths,\n  the remaining bare synthesized references (list/append/car/cdr) get the\n  same base-binding-prefix treatment as apply, so a redefinition of any of\n  them cannot corrupt inherited record construction either.\n\n- baijum: emitApplyForm's '<2 operands' early return fired before the\n  rebound check, so a REBOUND apply in tail position with one operand\n  abandoned native compilation of the whole scope (correct result via the\n  eval fallback, but a needless de-opt and a doc/behavior mismatch). Gate\n  the early return on !rebound so that shape takes the generic indirect\n  call, matching the interpreter's #2033-gated ordinary call path; update\n  the llvm_emit_forms and llvm-backend.md bullets to say 'unrebound'.\n\n- baijum: buildLetValues' doc comment still described the removed\n  is_tail-dependent outermost-vs-nested reasoning; trim it to the\n  base-prefixed unconditional-reference behavior that is now the whole\n  truth.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n---------\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>",
          "timestamp": "2026-08-09T12:48:27+05:30",
          "tree_id": "cf19394bd8a7397d6495f8312dc5ebd119a026d1",
          "url": "https://github.com/kaappi/kaappi/commit/042421e258a320442a69b471cd9a8ae4603668bc"
        },
        "date": 1786261930365,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.343413,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.925938,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.57718,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.018789,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004776,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.04715,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.316494,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.056074,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.80206,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.240429,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.587061,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.281492,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.822763,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.626756,
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
          "id": "8e4b801479054785c5801b1f6a3d55ad8ea05233",
          "message": "Splice definition-context begins in body scans (Fixes #2075) (#2267)\n\nA begin-wrapped internal define in a let-family body escaped to the\nglobal environment unless an enclosing procedure existed. R7RS 4.2.3\nrequires a definition-context begin to behave exactly as if the wrapper\nwere absent, so\n\n  (let ((g 'outer)) (begin (define g 'inner)) g)\n\nmust answer 'inner at top level — the same answer it already gave\ninside a lambda — and must not overwrite a top-level g. It answered\n'outer, and the define_global that escaped the let silently replaced\nthe unrelated global with 'inner.\n\nTwo halves of the same defect:\n\n1. scanBodyDefs only recognized literal define-family heads as body\n   elements and never descended into a begin, so a begin-wrapped define\n   was neither pre-declared into the body's letrec* region nor compiled\n   as a body definition. The scan now unwraps spliceable begins\n   (recursively, mirroring the IR lowerer's shadow test for a begin\n   head) before its three passes run, so definitions inside them join\n   the letrec* region like unwrapped ones — mutual recursion, define-\n   record-type, define-values and define-syntax included.\n\n2. compileDefine chooses local vs define_global on in_body_scope, which\n   only the procedure-body paths set. The let-family bodies\n   (compileBodyForms' other callers) were missing it, so a definition\n   reached at compile time — a macro expansion producing one, or a\n   begin the scan could not splice — became a global at top level while\n   the identical text inside a lambda bound a local. compileBodyForms\n   now sets in_body_scope like compileBody and compileSyntaxBody do.\n\nThe native tier inherits both halves via its existing interpreter\nfallback for begin-spliced defines (pinned in\nnative-let-internal-define-root-1854.sh), which the new cases verify\nstill agrees with the interpreter's now-correct answers.\n\nAlso flips the srfi188.scm assertions that pinned the wrong answers,\nenables the four disabled R7RS-required ones, and rewrites the SRFI 188\n.sld header, whose flagship claim that the begin-wrapped form evaluates\nto 'outer at top level was the doc-truth half of this bug.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>",
          "timestamp": "2026-08-09T16:58:08+05:30",
          "tree_id": "5d2abea7563f759442a4c0c4e01e398af33dbc0b",
          "url": "https://github.com/kaappi/kaappi/commit/8e4b801479054785c5801b1f6a3d55ad8ea05233"
        },
        "date": 1786277189435,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.452564,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.334852,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.594058,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.035733,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004747,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046891,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.313853,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.057674,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.804002,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.234943,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.669461,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.281094,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.79181,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.69477,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.046483,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "7c1223ff434c5df6d9ad3906205ec15721ddbfec",
          "message": "REPL: click inside the input to move the edit cursor (#2264) (#2265)\n\n* REPL: click inside the input to move the edit cursor (#2264)\n\nAdd opt-in SGR mouse support to the REPL, behind a `repl.mouse: true`\nsetting in ~/.kaappi/config (default off, so drag-to-select behavior never\nchanges unasked). A left click inside the current input repositions the\nedit cursor, on single-line, wrapped, and multi-line forms alike; clicks\noutside the editing area are safe no-ops.\n\nThis is the fifth Kaappi patch to vendored isocline (PATCHES.md):\n\n- Tracking: emit ?1000h (button presses, deliberately not ?1002h/?1003h\n  motion) + ?1006h (SGR coordinates) around each edit session, gated\n  `#if !defined(_WIN32)` — the Windows console reads INPUT_RECORD structs,\n  not a byte stream, so SGR has nothing to decode there; a follow-up needs\n  its own Console-API path (MOUSE_EVENT arm + ENABLE_MOUSE_INPUT, with\n  GetConsoleScreenBufferInfo for the anchor instead of ESC[6n).\n- Decode: `ESC[<b;x;yM|m` lands in the CSI decoder's \"special byte\" catch\n  and the generic parser only takes two parameters, so the three-part SGR\n  mouse event is intercepted right after the special-byte check. The\n  coordinates cannot fit the code_t keycode space, so the event is stashed\n  on the tty (tty_set_mouse_event) and surfaced as a single\n  KEY_EVENT_MOUSE code.\n- Anchor: the mouse reports absolute screen coordinates while isocline\n  works relative to the prompt, so the editor queries ESC[6n once per edit\n  session, right after the prompt is written, and maps the click through\n  the existing edit_set_pos_at_rowcol / sbuf_get_pos_at_rc machinery\n  (prompt width, continuation prompt, and line wrapping already handled).\n  A terminal that does not answer leaves the anchor unset and clicks\n  become no-ops. A delayed DSR response now decodes to KEY_NONE, which the\n  edit loop ignores instead of inserting a NUL.\n\nNew pty test tests/scheme/smoke/repl-mouse-click-2264.sh plays the\nterminal emulator: it answers the DSR query and feeds SGR presses relative\nto that anchor, asserting on what the evaluator prints (single-line and\ncontinuation-row clicks, plus a mouse-off run proving the bytes are\ninert). Also fixes the stale \"three patches\" count in the isocline.zig\nmodule doc, which PATCHES.md had already outgrown.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Harden the mouse-click pty test: fix undefined variable, add wrap case\n\nThree changes to tests/scheme/smoke/repl-mouse-click-2264.sh, two from\nCodeRabbit review:\n\n- The timeout-failure path referenced `typed`, undefined since the case\n  tuple was renamed to `send_bytes`; a timed-out echo would raise NameError\n  instead of recording the failure.\n- New narrow-pty (20-column) run exercises an automatically wrapped row:\n  \"(list 1 2 3 4 5 6)\" spills onto two visual rows and a click on the\n  wrapped row lands before the '4', proving the wrap-aware\n  sbuf_get_pos_at_rc mapping (the wrap threshold leaves 11 content columns\n  on a 20-column terminal, with the cursor column reserved).\n- The failure-report loop variable is renamed to match.\n\nThe wide runs now also assert with `send_bytes` instead of the undefined\n`typed`.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* REPL mouse: never eat type-ahead in the DSR anchor query, act on press only\n\nMaintainer review of #2265 raised the one blocking concern: the per-prompt\nESC[6n anchor query ran through tty_read_esc_response, which consumes the\nfirst queued byte and bails if it is not ESC. Typing ahead between forms is\ncommon in a REPL — press Enter, start typing the next form while the\nprevious one evaluates — so the first character of the next input was\nsilently lost for repl.mouse: true users, and the anchor was unset for that\nline anyway.\n\nNew tty_read_dsr_response in tty.c reads the response (ESC [ row ; col R)\nand pushes back every byte it read on any failure path, in order, so a\nqueued keystroke or a key sequence sent as ESC (arrows, Alt+key) still\nreaches the edit loop. The only consequence of an unreadable response is an\nunset anchor — clicks no-op for that line, input is never lost. A response\nthat arrives after the reader gave up decodes to KEY_NONE and is ignored\n(covered by the KEY_NONE guard). editline.c now uses it instead of\ntty_read_esc_response + ic_atoz2.\n\nAlso: the SGR decoder now carries the press/release flag ('M' vs 'm') on\nthe mouse event, and edit_mouse_click repositions on press only — with\n?1000h a single click reports both, so previously it moved the cursor\ntwice (idempotent but a redundant refresh per click).\n\nThe pty test gains a fourth run: submit a form and immediately type the\nnext one with no idle between; it asserts both results print, i.e. the\nDSR query ate nothing. Verified to fail without the push-back.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* docs: note that the DSR anchor query never consumes type-ahead input\n\nReflects the tty_read_dsr_response guarantee in docs/dev/repl.md: bytes\nthat are not a well-formed response are pushed back to be read as keys.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* REPL mouse: cap the DSR restore at TTY_PUSH_MAX, fix the tty_cpush guard\n\nMaintainer review (round 2) found a memory-safety bug in the type-ahead\nfix: the DSR reader's push-back path could write up to 66 bytes into the\n32-byte cpushbuf. The digit buffer was 64 bytes and the restore pushed\n1 (c) + n + 2 ('[' + ESC) back-to-back; tty_cpush's overflow guard tested\npush_count — the high-level code pushback buffer — while the writes land\nin cpushbuf via cpush_count, so it never tripped and no assert fired. The\nmismatched guard is pre-existing upstream, but this reader is the first\ncaller able to push back more than a couple of bytes.\n\nTwo fixes:\n\n- tty_read_dsr_response now caps the digit buffer at TTY_PUSH_MAX - 2\n  (29 digits; a real cursor report is a handful), so a restore is at most\n  32 bytes, and additionally skips the restore entirely if\n  cpush_count + n + 3 would exceed TTY_PUSH_MAX (defensive against\n  leftover bytes). A garbled or hostile 30+ digit CSI simply fails the\n  read; nothing is corrupted.\n- tty_cpush's guard now checks cpush_count, the counter the writes\n  actually use.\n\nThe pty test gains a fifth run: a 40-byte CSI of digits/semicolons with no\nR terminator, delivered while the DSR query is pending. It asserts the\nREPL survives and a later form still evaluates; verified to crash the\nchild (SIGTRAP via the OOB) without the fix.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* docs: record the DSR restore cap and the tty_cpush guard fix in PATCHES.md\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n---------\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>",
          "timestamp": "2026-08-09T11:32:22Z",
          "tree_id": "2eba0db4c143db8a6a88949ddc61f5ef8ef67f8e",
          "url": "https://github.com/kaappi/kaappi/commit/7c1223ff434c5df6d9ad3906205ec15721ddbfec"
        },
        "date": 1786277480831,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.348249,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.395516,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.58013,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.074869,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004703,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046909,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.313985,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.055902,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.744885,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.250482,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.594864,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.274429,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.794726,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.614696,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045841,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "55708cfa6d02cd3b86a74483f6305e108398fc35",
          "message": "Store complex components as Values: exact complex arithmetic, make-rectangular, write/real-part, reader (#2268)\n\n* Store complex components as Values: exact complex arithmetic, make-rectangular, write/real-part, reader (Fixes #2166)\n\nComplex stored its components as two f64s plus exactness flags, so every\nconsumer had to choose between honest-but-inexact and exact-but-wrong:\n(+ 3/2+1i 1/2) returned inexact 2.0+1.0i, (make-rectangular\n9007199254740993 1) silently rounded 2^53+1, (exact? (make-rectangular\n(expt 10 400) 1)) claimed an exact infinity, and (write z) printed 3/2+1i\nwhile (real-part z) returned inexact 1.5.\n\nComponents are now Values (fixnum/bignum/rational/flonum) with no flags:\n\n- + - * / and expt with an integer exponent run componentwise over the\n  exact tower, which is exact-closed; the interim unary-negation\n  special-case dissolves.\n- make-rectangular never touches an f64; 2^53+1 and 10^400 survive\n  digit-exactly.\n- write prints components through the normal numeric printer (the\n  f64-unrounding path is deleted), so write and real-part agree.\n- The reader and string->number build components digit-exactly at any\n  size; the #2182/#2243 f64 round-trip gates dissolve.\n- eqv?/equal?/memv/assv/eqv-keyed hash tables compare components with\n  numeric eqv?, and hash by component value.\n- Per R7RS 6.2.2 a stored complex is never mixed-exactness; a zero imag\n  demotes, except that a literal's inexact zero imag stays complex\n  ((real? -2.5+0.0i) => #f) while an exact one demotes\n  ((integer? 3+0i) => #t).\n- .sbc: TAG_COMPLEX now writes the two component constants; the golden\n  byte test is updated.\n\nGC: complex is now a Value-bearing heap type (mark/sweep/deep-copy arms\nadded; the field pin re-pinned). The reader roots scanned complex\ncomponents until the datum constructor converts them.\n\nTest updates: the interim-slice assertions in the #2166/#2167 compliance\nsuite now pin the full behavior; the gate assertions in the reader\ndelimiter/exactness-gap suites and tests_numeric pin the digit-exact\nreads; new coverage for arithmetic, make-rectangular, write/real-part,\nreader, string->number, expt, and hash tables.\n\nSigned-off-by: bmuthuka <bmuthuka@users.noreply.github.com>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Fix GC use-after-free in radix complex reader; address review findings\n\n- HIGH: rootComplexImag now performs the lazy root registration too.\n  readIntegerWithRadix parses the imaginary part first (tryComplexTail\n  stores a heap imag via rootComplexImag) and only then builds the real\n  part, so with only rootComplexReal registering the slots the imag was\n  unrooted across that allocation — (read \"#x1/2+3/4i\") aborted with\n  'GC: marking freed object' under -Dgc-stress=true (found in review and\n  by the gc-stress-scheme CI job).\n- Printer: the +i/-i unit spelling is only used for an exact ±1 fixnum;\n  an inexact ±1.0 prints its magnitude, so write preserves exactness\n  (0.0+1.0i writes +1.0i, not +i which would read back exact).\n- expt with an exact integer exponent uses square-and-multiply (O(log n)\n  instead of O(n)): (expt +i 1000000000) => 1 no longer hangs.\n- inexact on an all-inexact complex returns it unchanged, keeping\n  -2.5+0.0i complex instead of demoting it to the real -2.5.\n- Unary (- z) and the (/ z) conjugation use IEEE negation (negate2), so\n  an inexact zero component flips its sign bit (0.0 -> -0.0).\n- makeFixnumChecked checks the i48 range before touching gc_instance, so\n  in-range values never need the GC in reader-only contexts.\n- .sbc: VERSION bumped 11 -> 12 (TAG_COMPLEX payload is incompatible);\n  the writer validates components are real before serializing; the\n  fuzz-seed fixture is regenerated; the round-trip test and the\n  sbc-constants probe now cover bignum/rational components.\n- toComplexParts (f64) removed as dead; complexPowGeneral's unused gc\n  parameter removed; string->number propagates OutOfMemory instead of\n  returning #f on the signless pure-imaginary path.\n- Tests: gc-stress regression tests for the radix complex literals\n  (#x1/2+3/4i, #x800000000000+99999999999999999999i), gc-tracing tests\n  for complex components, a deep-copy test with a bignum component, the\n  stale comments fixed, and the '1/2+3i real part is exact' pin enabled.\n\nSigned-off-by: bmuthuka <bmuthuka@users.noreply.github.com>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Root the bignum component across allocRational in the .sbc round-trip test\n\nThe new exact-complex constant in the bytecode round-trip test stored an\nunrooted bignum real across the allocRational in the second argument, so\n-Dgc-stress=true (collection on every allocation) freed it before\nallocComplex stored the dangling pointer: 'GC: marking freed object' in\nthe gc-stress CI job (found in review). Root it for the two allocations.\n\nSigned-off-by: bmuthuka <bmuthuka@users.noreply.github.com>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n---------\n\nSigned-off-by: bmuthuka <bmuthuka@users.noreply.github.com>\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>",
          "timestamp": "2026-08-09T14:39:44Z",
          "tree_id": "ea699a2622bbe92926388825d3ccf01692fe9139",
          "url": "https://github.com/kaappi/kaappi/commit/55708cfa6d02cd3b86a74483f6305e108398fc35"
        },
        "date": 1786288486047,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.250877,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.862564,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.563016,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.976347,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00463,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.047276,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.304958,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.05655,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.746478,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.173357,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.58854,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.273561,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.789046,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.613227,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044094,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "88432dd1563027afaf6e3fc274425202feff71a5",
          "message": "Split repl.zig along its natural seams (#2266) (#2270)\n\n* Split repl.zig along its natural seams (Fixes #2266)\n\nrepl.zig had grown to ~1,590 lines, over the 1,500-line guideline, with\ngenuinely tangled coupling: the REPL loop, the isocline callbacks\n(completeness, completion, highlighting, structural editing), and the\ncomma-command dispatch all lived in one file. The split is pure motion —\nno behavior changes — so the unit tests that covered the pure functions\nand the pty smoke tests that covered the loop still pass unchanged.\n\nThree seams, three new files:\n\n- repl_highlight.zig: the token scanner (scanHighlight), the isocline\n  highlighter callback, and the theme-to-isocline style bridge\n  (ansiToIcStyle, applyTheme), with all of its unit tests. Driven by\n  Reader.isDelimiter and config.zig's theme escapes, so colors cannot\n  disagree with the parse.\n- repl_commands.zig: the comma-command dispatch (handleCommand, returning\n  tri-state so `,quit` can end the REPL rather than continue it), the\n  handlers, the command-name completion helpers, and the usage table.\n- repl_eval.zig: the read -> compile -> execute -> print driver\n  (evalInputInner and friends, with EvalMode), shared by the main loop\n  and the commands, plus the pretty-print terminal width.\n\nrepl.zig keeps the main loop, line editing, the completeness/completion/\nsexp-edit callbacks, and inputIncomplete's tests — now ~490 lines, and\nthe new files are each well under the limit. The dependency graph is\nacyclic: repl -> {highlight, eval, commands}, commands -> eval.\n\nAlso dropped the write-only `theme` global (assigned at startup, never\nread), and updated docs/dev/repl.md's file map plus the repl.zig file\nreferences in docs/dev/crash-reporting.md and docs/dev/porting.md.\n\nVerified behavior-identical against the pre-split binary: unit tests\n(plain and -Dgc-stress), the full Scheme suite (2097 pass), the six\nrepl-* pty smoke tests, `zig build wasm`, and a pty-driven pass over\nevery comma command (byte-identical output to the original binary).\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Address review: GC-safe ,import/,expand, tidy moved helpers\n\nCodeRabbit review of #2270 flagged that the moved ,import and ,expand\nhandlers skip two GC-safety steps the rest of the codebase takes (see\n.claude/rules/gc-safety.md): the ,import spine write\n`Pair.cdr = pair` had no writeBarrier, and the ,expand datum and its\nexpansion were unrooted across the allocating expander calls. Both are\npre-existing (the code moved verbatim from repl.zig), but they are\nbehavior-identical to fix and this PR is where that code lands in its\nnew home, so harden it now:\n\n- ,import: barrier the old->young cdr edge after a collection promotes\n  the spine, matching primitives_fiber.zig / bytecode_file_read.zig;\n  also declare the pair const and drop the `_ = &pair` suppression.\n- ,expand: root expr before expandMacro and the expansion before\n  stripUsertextMarkers, mirroring evalInputInner's own rooting of read\n  datums (pushRoot + defer popRoot, LIFO-safe here).\n\nPlus three low-value cleanups of the moved code: ,apropos now uses\nstd.mem.indexOf instead of the hand-rolled containsSubstring (same\nempty-needle semantics), describeSymbol drops its unused allocator\nparameter, and docs/dev/repl.md's intro names all four REPL files.\n\nDeliberately not done in this PR: the ,load path-escaping gap (fixing\nit changes behavior and wants its own regression test — filed\nseparately) and collapsing evalInputInner's duplicated print blocks\n(control-flow risk in a pure-motion split; both copies pre-existing).\n\nVerified: unit tests (plain and -Dgc-stress), full Scheme suite (2097\npass), the six repl-* pty smoke tests, `zig build wasm`, and the pty\ncommand matrix against the pre-split binary (still byte-identical).\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n---------\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>",
          "timestamp": "2026-08-09T17:02:01Z",
          "tree_id": "814d1cadf3a4b77044665877e9d01bb8703c1ca5",
          "url": "https://github.com/kaappi/kaappi/commit/88432dd1563027afaf6e3fc274425202feff71a5"
        },
        "date": 1786297081633,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.933419,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.050128,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.583881,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.834753,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004955,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.045557,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.289583,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.055682,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.356782,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.158163,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.574651,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.311336,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.727524,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.814207,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045167,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "7606c110749f644aac5568ca37d608782af4ae61",
          "message": "Keep an inexact zero imaginary part complex in make-rectangular, write, and c64/c128 decode (Fixes #2269) (#2271)\n\n* Keep an inexact zero imaginary part complex in make-rectangular, write, and c64/c128 decode (Fixes #2269)\n\nmake-rectangular demoted an inexact zero imaginary part to the real\ncomponent while the reader kept it complex, so the constructor and the\nliteral 1.5+0.0i disagreed, and the printer collapsed an inexact-zero-imag\ncomplex to its bare real — (write 1.5+0.0i) printed 1.5, which reads back\nas a different value, violating R7RS 6.2.7's number->string round-trip.\n\nPer R7RS 6.2.6's worked examples, an explicitly inexact zero imaginary\npart keeps the value complex ((real? -2.5+0.0i) => #f); only an exact\nzero demotes. Chez, Guile, chibi, and Gambit all behave this way.\n\n- make-rectangular now routes through makeComplexOrRealLiteral (the\n  reader's exact-zero-only demotion) instead of makeComplexOrRealV.\n- The complex printer collapses only an exact zero imag, emitting the\n  full form (\"1.5+0.0i\" / \"1.5-0.0i\") for the inexact case, so write\n  and number->string round-trip through read.\n- c64/c128 decodeElement preserves a +0.0 imaginary part instead of\n  demoting it to a plain real, so SRFI-160 refs agree with the\n  standalone constructor.\n\nTests: re-pinned the srfi160 control/decode assertions and the\nmake-rectangular demotion tests to the new behavior, added regressions\nfor the decomposition and write/read round-trips (starting from the\nreader value, the discriminating probe), and kept (real? -2.5+0.0i)\n=> #f green in the R7RS suite.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Extend exact-zero-only demotion to the arithmetic tower and make-polar (review #2271)\n\nReview feedback: the PR fixed make-rectangular, the reader, and the\nprinter, but the same demotion survived in two other construction sites\n— the arithmetic tower (+ - * /) built results through makeComplexOrRealV,\nwhich demoted ANY zero imag, and make-polar demoted an inexact 0.0 imag\nthrough the f64 makeComplexOrReal path. Chez, Guile, chibi, and Gambit\nkeep an inexact zero imag complex everywhere: (+ 1.0+2.0i 1.0-2.0i) is\n2.0+0.0i, (* 1.5+0.0i 2.0), (- 1.5+2.0i 0.0+2.0i), (+ 1.5+0.0i 0), and\n(make-polar 1.5 0.0) are all (real? => #f).\n\n- makeComplexOrRealV and makeComplexOrRealLiteral were identical except\n  for the demotion rule; collapsed into one exact-zero-only\n  makeComplexOrRealV, now the single Value-component construction site\n  for the reader, string->number, make-rectangular, arithmetic, and\n  exact/inexact conversion.\n- make-polar now demotes only an EXACT zero angle ((make-polar 1.5 0) =>\n  1.5) and keeps an inexact zero imag complex ((make-polar 1.5 0.0) =>\n  1.5+0.0i), preserving -0.0 ((make-polar 1.5 -0.0) => 1.5-0.0i).\n- (exact 1.5+0.0i) still demotes to 3/2 (exact zero), and (- z z) for an\n  exact z still yields exact 0, as the references do.\n- Regression tests for the arithmetic and make-polar cases, plus the\n  exact-zero survival pins.\n\nThe f64 transcendental paths (sin/cos/tan, sqrt, expt, exp, log, asin)\nare intentionally unchanged: they still demote an exactly-zero or\nbelow-1e-15-noise imaginary result via makeComplexOrReal and the\npre-existing epsilon guard, a deliberate noise-suppression design that\nis orthogonal to the construction-site rule (noted in the CHANGELOG).\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* make-polar: demote only a numerically-zero exact angle; test-helper and import tidy-ups (review #2271)\n\nReview follow-up: the make-polar guard tested the angle's EXACTNESS rather\nthan that it is ZERO, so a tiny exact nonzero angle whose sin underflows to\n0.0 demoted incorrectly: (make-polar 1.5 (/ 1 (expt 10 400))) returned the\nreal 1.5 while Chez, Guile, chibi, and Gambit all keep 1.5+0.0i (real? => #f).\nRequire isZeroValue(args[1]) alongside the exactness check; the exact-zero\nangle pin (make-polar 1.5 0) => 1.5 is unchanged, and a regression covers the\nunderflow path, which the existing pins did not exercise.\n\nAlso per review: convert the make-rectangular unit test to th.TestContext\n(the documented multi-evaluation helper, docs/dev/testing.md) and import\n(scheme process-context) in tests/scheme/smoke/complex-neg-zero.scm so its\nexit calls do not rely on kaappi registering exit ambiently.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n---------\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>",
          "timestamp": "2026-08-09T17:53:23Z",
          "tree_id": "4a9db3eaf2e334d18ea106d395840efe241d3be2",
          "url": "https://github.com/kaappi/kaappi/commit/7606c110749f644aac5568ca37d608782af4ae61"
        },
        "date": 1786299948956,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.038368,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.095877,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.459412,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.19378,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.003761,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.035174,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.223541,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.041636,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 1.85257,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.912868,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.184398,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.240797,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.31139,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.322015,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.036308,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "c692aed681e62ee31bb146464ba9ebb7ae0b0328",
          "message": ",load: build the form as Values so paths with quotes or backslashes load (Fixes #2273) (#2274)\n\n* Fix ,load mangling paths with quotes or backslashes (#2273)\n\nThe command spliced the path into a (load \"...\") string literal, so the\nreader's escapes broke or changed it: a quote ended the string (reader\nerror), a backslash started an escape (\\s is invalid, \\t decodes to a\nTAB and loads a different file). On Windows every path uses backslashes,\nso ,load was effectively broken there for normal use.\n\nBuild the form as Values instead — a load symbol, a Scheme string holding\nthe raw path bytes, and the two pairs — and evaluate it through a new\nrepl_eval.evalInputValue that shares the compile/execute/print driver\nwith the text path (the loop body was extracted into evalExpr so the\nerror handling, stack trace, multiple-values printing, and _ binding\nstay byte-for-byte the same). No escaping to get wrong, and the old\n1024-byte path limit is gone.\n\nThe pty smoke test creates files whose names contain a quote, a\nbackslash, and the literal \\t sequence and asserts each loads; all\nthree fail on the old code (unterminated string, invalid escape, and\ncannot-open-file on the TAB-mangled name).\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Root path/symbol values only after assignment (kaappi#2274 review)\n\nThe previous ,load handler declared the two locals as = undefined, rooted\ntheir slots, and only then assigned the allocString/allocSymbol results.\nBut allocXxx copies its bytes and calls maybeCollect() before returning, so\nthe collection during that call marks a slot still holding undefined. In\nDebug and ReleaseSafe the 0xAA fill keeps isPointer false, but under\nReleaseFast the slot is genuinely uninitialized: bits that happen to look\nlike a pointer make markRoots dereference a bogus address. Assign first,\nthen root, matching the ,expand and ,import handlers in this file.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n---------\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>",
          "timestamp": "2026-08-09T18:40:43Z",
          "tree_id": "11dcf8948be341b0d0a6bbf2789cd1612a4a06c2",
          "url": "https://github.com/kaappi/kaappi/commit/c692aed681e62ee31bb146464ba9ebb7ae0b0328"
        },
        "date": 1786302990925,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.101684,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.895877,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.433625,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.201107,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00379,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.035431,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.229697,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.042121,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 1.878348,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 0.956293,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.192534,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.24381,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.339722,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.401928,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.035918,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "cb71bd209d00d8f728e8ce0d04a00c7378026dcf",
          "message": "Remove syntax-rules rule/literal caps; fix define-property in templates (Fixes #2184, #2089) (#2275)\n\n* Remove the syntax-rules 32-rule and 32-literal caps (Fixes #2184)\n\nparseSyntaxRules parsed into fixed [32]Value stack buffers and rejected\nthe 33rd rule or literal with a bare KP2001 InvalidSyntax, making a\nlegal macro fail as if it were malformed. R7RS places no bound on\neither count, and a 33+ rule dispatcher macro is a normal shape.\n\nThe buffers are now growable ArrayLists (raw allocator, never\nGC-triggering; every held Value is a subpart of the rooted spec), with\na u16 guard where the old cap used to make Transformer.num_rules\noverflow unreachable.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Keep define-property bare in templates and dispatch it on the legacy path (Fixes #2089)\n\nA syntax-rules template emitting define-property failed with 'undefined\nvariable' two ways: the keyword was missing from the expander's\nreserved_template_forms, so the template head was hygiene-renamed to\n__hyg_N_define-property (well_known_forms alone does not stop the\nrename - instantiateTemplate consults isTemplateReserved); and even\nleft bare, the legacy compileForm path that compiles macro expansions\nhad no define-property dispatch, only the IR path did.\n\ndefine-property now sits in both reserved_template_forms and\nwell_known_forms (mirroring define-values), and compileForm dispatches\nit like the IR path.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Merge srfi 42's split qualifier macro back into a single %do-ec\n\nThe qualifier processor was split into %do-ec (generators) and\n%do-ec-more (grouping/command/control/guard) purely to dodge the\nengine's old 32-rule cap. With that cap gone the merged form is 34\nrules - back to one macro, with the workaround comment rewritten.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Update CHANGELOG for the syntax-rules cap removal and define-property fix\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Broaden the parseSyntaxRules GC-safety comment to cover the body-scan caller\n\nThe comment credited resolveTransformerSpecRec for rooting the spec,\nwhich is right for the primary caller but not for the define-syntax\nbranch of the lambda/let body scan (compiler_lambda.zig), which calls\nparseSyntaxRules directly without a root. Safety holds there for a\ndifferent reason - nothing in the parse loops GC-allocates and\nallocTransformer dupes the slices before it can collect - so the\ncomment now states the guarantee in terms of what this code itself\nensures, with an explicit warning not to add a GC-triggering call to\nthe loops.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n---------\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>",
          "timestamp": "2026-08-09T20:07:37Z",
          "tree_id": "4f72d54ea8c1d1a4a5f67079c0c2ef1ff28f4bf5",
          "url": "https://github.com/kaappi/kaappi/commit/cb71bd209d00d8f728e8ce0d04a00c7378026dcf"
        },
        "date": 1786308225631,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.266241,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.956004,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.562442,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.978641,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00468,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046857,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.304812,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.055533,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.765175,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.180279,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.584985,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.277058,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.785844,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.589952,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044776,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "ac6d5bf25a52e639799c0deea4f2df9bc81c2da0",
          "message": "Fix all eight SRFI-146 audit findings (2045, 2046, 2047, 2048, 2049, 2050, 2052, 2053) (#2276)\n\n* Make mapping/hashmap constructors and unfolds keep the first duplicate key (Fixes #2045)\n\nThe spec (SRFI 146, Constructors) says the first association wins for\nmapping, mapping-unfold, and their /ordered and hash twins, and the Note\nexplicitly contrasts this with mapping-set.  Both libraries inserted with\nreplace semantics, so the last duplicate key won -- the opposite of the\nspecified precedence, and the opposite of the sibling mapping-adjoin and\nalist->mapping/alist->hashmap procedures in the same files.\n\nmapping/mapping-unfold now accumulate with %rbt-adjoin (the same first-wins\nhelper mapping-adjoin uses); hashmap/hashmap-unfold guard their\nhash-table-set! with an exists? check, matching hashmap-adjoin and\nalist->hashmap.  mapping/ordered, mapping-unfold/ordered inherit via their\naliases.  The reference implementation accumulates with mapping-adjoin too.\n\nRe-enables the six duplicate-key assertions in the differential suite and\ndrops the pins that recorded the wrong answers.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Only run mapping-key-predecessor/-successor's failure thunk when no key exists (Fixes #2046)\n\nThe spec tail-calls `failure` only when no preceding/succeeding key is\ncontained in the mapping.  The implementation passed `(failure)` as the\nfold's seed, so the thunk ran on every call -- even when the answer\nexisted and the thunk's value was discarded.  A thunk that raises (the\nnatural spelling of \"this is a bug\") therefore raised on the success\npath, and a logging/counting thunk fired on every lookup.\n\nBoth procedures now fold over a (found . key) accumulator and invoke\n`failure` only after the fold, when nothing was found.  The reference\nimplementation tail-calls `failure` only on the empty branch.\n\nRe-enables the three successor/predecessor assertions in the differential\nsuite and drops the pin that recorded the spurious invocation.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Make mapping=?/hashmap=? return #f for mappings with different key comparators (Fixes #2047)\n\nThe spec (SRFI 146, Submappings) says it is \"explicitly not an error\" to\ninvoke mapping=? on mappings that do not share the same key comparator, and\nthat #f is returned in that case.  Both %mapping=? and %hm=? compared\nsizes and walked the associations without ever looking at either mapping's\nkey comparator, so two mappings built with different comparators compared\n#t -- and, worse, the comparison silently used mapping1's equality on\nmapping2's keys.  The reference implementation opens %mapping=? with\n(eq? (mapping-key-comparator mapping1) (mapping-key-comparator mapping2)),\nso \"share the same comparator\" means object identity.\n\nBoth helpers now open with that eq? check.  The 3+ mapping variadic clauses\nare unaffected: each adjacent pair already shares the same comparator by\ntransitivity.\n\nRe-enables the four \"different comparators\" assertions in the differential\nand reference suites.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Give make-mapping-comparator an ordering predicate and make-hashmap-comparator a hash function (Fixes #2048)\n\nThe spec (SRFI 146, Comparators) is explicit about why these exist: \"The\nexistence of comparators returned by make-mapping-comparator allows\nmappings whose keys are mappings themselves\".  Both constructors passed #f\nfor the ordering/hash slots of make-comparator, so a mapping could not be\nkeyed by mappings at all -- comparator-ordered? was #f and building such a\nmapping raised.\n\nmake-mapping-comparator now wires in mapping-ordering, the lexicographic\nordering the spec describes: compare key/value pairs in increasing key\norder, keys with the key comparator, values with the value comparator, and\nthe mapping that runs out of pairs first sorts smaller.  The reference\nimplements this by walking two tree generators in parallel; walking the two\nsorted alists is the same comparison.\n\nmake-hashmap-comparator now supplies the hash function the reference\nimplementation itself ships: a constant (srfi/146/hash.scm leaves a real\nhash as a TODO).  The spec only requires an implementation-dependent hash\nconsistent with the equality, and a constant is always consistent; it is\nwhat keeps hashmap-keyed tables a linear scan rather than something\ncorrect, matching the reference exactly.\n\nRe-enables the five reference-suite assertions (mapping-keyed mapping, <?:\ncase 1/2/3, hashmap-keyed hashmap -- the last was pinned under #2044,\nwhose comparator fix landed separately and which this hash function\ncompletes) and the two differential-suite assertions, and drops the pins\nthat recorded the missing slots.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Return a procedural default unchanged from hashmap-ref/default (Fixes #2049)\n\nThe spec defines hashmap-ref/default as \\\"semantically equivalent to, but\nmay be more efficient than, (mapping-ref mapping key (lambda ()\ndefault))\\\" -- the default is a VALUE, not a thunk, so a procedure passed\nas the default must be returned as-is.  The implementation forwarded the\ndefault to SRFI 69's hash-table-ref, whose third argument is a failure\nthunk: hashTableRefFn invoked any procedural default with no arguments and\nreturned its result in place of the procedure.  A dispatch table or memo\nof thunks therefore had its fallback called at lookup time.\n\nSwitches to hash-table-ref/default, which takes a plain default value; the\nordered sibling mapping-ref/default already had the right shape, and this\nrestores the differential agreement.  Non-procedure defaults were never\naffected, which is why the existing suite did not notice.\n\nRe-enables the differential assertion and its agree() oracle.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Make mapping-any?/mapping-every? return #t/#f, not the predicate's value (Fixes #2050)\n\nThe spec says mapping-any? \\\"Returns #t if any association of the mapping\nsatisfies predicate, or #f otherwise\\\", and identically for mapping-every?.\nBoth were implemented as accumulating folds that kept the predicate's own\nreturn value, so a predicate returning a truthy non-#t value (e.g. the\nvalue itself, in the common (lambda (k v) v) shape) leaked that value out\ninstead of #t.  The hashmap twins accumulate into a boolean flag, so the\ntwo halves of the same SRFI disagreed for identical predicates.\n\nBoth now coerce the fold result to a literal boolean; the reference\nimplementation returns literal #t/#f too (mapping-any? escapes with (return\n#t) and falls through to #f; mapping-every? is (not (mapping-any? (lambda\n(k v) (not (predicate k v))) mapping))).\n\nRe-enables the two differential agree() assertions.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Accept the single-mapping form in the ten submapping comparison predicates (Fixes #2052)\n\nAll five signatures are (predicate comparator mapping1 mapping2 ...) with\nzero-or-more trailing mappings, so one mapping is a legal argument list and\nthe prose is vacuously satisfied by it.  Each case-lambda started at three\narguments, so the one-mapping form raised instead of returning #t -- and\nthe variadic set-theory procedures in the same files (mapping-union m,\nmapping-intersection m, ...) already accept it, so the omission was\nspecific to the comparison predicates rather than a house convention.\n\nEach of the ten case-lambdas (mapping=?/<?/>?/<=?/>=? and their hashmap\ntwins) now opens with an unconditional ((vcmp m1) #t) clause, exactly like\nthe reference implementation, which returns #t for the degenerate case of\nthe strict predicates too.\n\nRe-enables the three single-mapping assertions in the differential suite\nand drops the pin that recorded the raise.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Delete the discarded double folds in mapping-map and mapping-find (Fixes #2053)\n\nBoth procedures contained a complete first copy of their fold whose result\nwas thrown away, then recomputed the same fold.  mapping-map ran a\nside-effecting proc twice per association (the spec deliberately gives it\nno \\\"no guarantees how many times\\\" licence, unlike its neighbours) and was\n2x slower than necessary; mapping-find was 2x slower too, its redundant\npredicate calls permitted but the wasted work not.  Results were correct\nin both cases.  The hashmap siblings are single-pass, which is why the\ndifferential suite caught it.\n\nThe fix is to delete the discarded expression from each.  mapping-find's\nsingle remaining fold keeps the (pair? acc) short-circuit of the second\ncopy; mapping-map keeps the fold inside %make-mapping.\n\nRe-enables the differential agree() assertion that counts proc invocations.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Keep the strict submapping predicates antisymmetric across different key comparators (review of #2047)\n\nThe #2047 identity guard on %mapping=? leaked into mapping<?/mapping>?\nthrough their (and <=? (not =?)) shape: %mapping<=? is structural, so two\nsame-content mappings built with different (but structurally identical)\ncomparator objects compared < in BOTH directions -- non-antisymmetric,\nwhere pre-PR behaviour and the reference (whose <? is defined without\nconsulting =?) both gave #f/#f.\n\nThe strict predicates now carry their own (eq? ...) key-comparator guard.\n%mapping<=? stays structural, matching the reference; same-comparator\nproper-subset semantics are unchanged.  The hash side mirrors the ordered\nside exactly.\n\nAlso from review:\n- completes the #2052 single-mapping coverage to all ten predicates\n  (mapping<?/>?/>=? and hashmap<?/>?/<=?/>=? were untested),\n- pins the spec value of the #2050/#2049/#2053 fixes with direct\n  assertions on the defective side, so they fail even if both libraries\n  were to regress together rather than disagreeing,\n- regression tests for the antisymmetry fix, verified to fail without it.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n---------\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>",
          "timestamp": "2026-08-10T05:51:12+05:30",
          "tree_id": "8effcb2f0fda8e906ecf41edab9998fcd5189552",
          "url": "https://github.com/kaappi/kaappi/commit/ac6d5bf25a52e639799c0deea4f2df9bc81c2da0"
        },
        "date": 1786323412829,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.232112,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.484669,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.574231,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.983292,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004704,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046994,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.305558,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.055559,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.83515,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.174072,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.591407,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.284568,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.792724,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.561803,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.04536,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "ffa87145d79aa287e90b071192fe864d4b4971be",
          "message": "Fix four SRFI audit findings: and-let*, SRFI 222, set->bag!, random seed (#2277)\n\n* Fix four SRFI audit findings: and-let*, SRFI 222, set->bag!, random seed (2073, 2072, 2086, 1913)\n\nFour independent SRFI conformance defects, one PR:\n\n- #2073: and-let* with claws and an empty body returned #t instead of the\n  last claw's value (eval[(AND-LET* (CLAW))] = eval_claw[CLAW] in the SRFI 2\n  formal semantics). The expansion now ends on the last claw and returns its\n  value for all three claw shapes, keeping the #f short-circuit.\n\n- #2072: (srfi 222) exported 5 of the spec's 10 procedures, make-compound\n  did not flatten nested compounds, and compound-subobjects was the bare\n  record accessor, raising on a non-compound. The library now ships all ten\n  procedures with spec semantics: flattening make-compound, a one-element-list\n  compound-subobjects, and compound-map/-map->list/-filter/-predicate/-access.\n\n- #2086: set->bag! only inserted set elements the bag did not already hold,\n  silently dropping the set's contribution to existing elements. It now\n  increments unconditionally (bag-increment! b k 1), matching the reference\n  implementation and chibi-scheme.\n\n- #1913: %random-port-make-from-seed accepted an all-zero seed, putting the\n  xoshiro256** state at its degenerate fixed point (zero bytes forever). The\n  sibling entry points already rejected it; the raw seed primitive now does\n  too. Unit test added alongside the Scheme-level test.\n\nEach fix enables the disabled regression tests that pinned it. Full Scheme\nsuite: 703 pass (the single WASM differential failure is pre-existing, verified\nagainst the clean tree).\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n* Make (srfi 222) self-contained: local filter/append-map instead of vm.globals fallback\n\nCodeRabbit review caught that filter and append-map are not (scheme base)\nbindings: they are tagged .srfi_1 and reach lib/srfi/222.sld only through\nkaappi's vm.globals fallback for library bodies (lookupGlobalLocked in\nvm_dispatch_helpers.zig), which other R7RS implementations do not have.\n\nThe SRFI 222 reference implementation defines its own filter, and\nlib/srfi/217.sld does the same, so this library now defines both helpers\nlocally using only R7RS base functionality. Verified by poisoning the\nglobal filter/append-map bindings before importing (srfi 222): the library\nstill loads and behaves correctly.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>\n\n---------\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>",
          "timestamp": "2026-08-10T08:19:15+05:30",
          "tree_id": "368ab01a277d570f09ed4660e29324d5ca2ca960",
          "url": "https://github.com/kaappi/kaappi/commit/ffa87145d79aa287e90b071192fe864d4b4971be"
        },
        "date": 1786332020903,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.230582,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.990166,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.560255,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.983902,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004622,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046898,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.301467,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.056327,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.73538,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.173447,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.584265,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.282245,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.771137,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.458734,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.04314,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "56b189830bc55868d68bc4060d62bf1d16a7696a",
          "message": "Implement the full SRFI-189 spec surface: all 82 names with spec signatures (Fixes #2087) (#2278)\n\nlib/srfi/189.sld exported 24 names, of which 23 were spec names: 59 of the\nspec's 82 identifiers were absent, four signatures were narrower than the\nspec requires, and `either` was exported without ever being defined, so a\nprogram importing it failed at the point of use. cond-expand answered yes\nto both feature tests throughout, so portable code had no way to detect\nthe gap.\n\nThe library is now a port of the reference implementation, exporting all\n82 spec identifiers with their spec signatures:\n\n- maybe-ref/either-ref take a required failure procedure and an optional\n  success procedure (default values) instead of only the container; the\n  Left payload is readable again through either-ref's failure argument\n  and either-swap.\n- maybe-bind/either-bind are variadic in the mprocs, short-circuiting\n  Nothing/Left immediately; the spec defines the result as if compose had\n  been applied, and the implementation inlines a local loop over the\n  mprocs through maybe-ref/either-ref.\n- either-filter/either-remove take obj ... for the Left payload.\n- values->maybe/values->either invoke a producer thunk rather than\n  taking bare values, per the spec's values protocol.\n- The list-protocol procedures (maybe->list, either->list,\n  maybe->list-truth, either->list-truth) return a copy of the payload,\n  so mutating a result cannot corrupt an immutable container.\n- The phantom `either` export is gone.\n\nA Just/Right/Left may hold zero or more payload objects, stored as a\nlist, so a Just with no payload is not Nothing (success with no values),\nas the spec requires. The syntax group (maybe-if, maybe-and, maybe-or,\nmaybe-let*, maybe-let*-values, either-guard, ...) is portable\nsyntax-rules over the library's own bindings.\n\nThe audit suite's 18 disabled FAIL: #2087 assertions are now live, the\nold-signature tests were updated to the spec, and the export-completeness\nsection grew to cover each spec group (protocol conversions, trivalent\nlogic, sequence ops, map/fold/unfold, compose, generation and two-values\nprotocols). 237 assertions pass, plus the older srfi189.scm regression\nfile. Full Scheme suite: 703 pass; R7RS suite: 1395 pass.\n\nOne known engine interaction, documented in compileGuard: when no guard\nclause matches, kaappi's guard re-raises in its own dynamic environment\nand does not resume the original raise-continuable site, so the reference\nsuite's continuable-reraise edge check cannot pass until that engine\ndeviation is addressed. Matching raises are caught into a Left and\nnon-matching raises propagate; both are pinned in the audit.\n\nSigned-off-by: Baiju Muthukadan <baiju.m.mail@gmail.com>",
          "timestamp": "2026-08-10T10:15:10+05:30",
          "tree_id": "0dba96808e9ecf18b78e6be0f7d3cf7e8d0e9619",
          "url": "https://github.com/kaappi/kaappi/commit/56b189830bc55868d68bc4060d62bf1d16a7696a"
        },
        "date": 1786339231903,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.213376,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.110483,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.578728,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.954365,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004641,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.047134,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.302173,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.056387,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.77386,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.154052,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.582496,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.282872,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.765021,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.666517,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044707,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
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
      }
    ]
  }
}