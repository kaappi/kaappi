window.BENCHMARK_DATA = {
  "lastUpdate": 1785232881672,
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
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "f7a136dbbcc0826aed08d26d85cef7014f270fc7",
          "message": "Add understanding map and /quiz comprehension skill (#1664)\n\n* Add understanding map and /quiz comprehension skill\n\nAI-assisted development generates code faster than a human forms a\ntheory of it. The existing harness (CLAUDE.md, rules, memory) solves\nthe machine side of that gap — every session cold-starts into full\ncontext — but nothing maintained the human side.\n\ndocs/dev/understanding-map.md is the policy: it classifies subsystems\ninto a core tier, where the maintainer holds the theory (values/heap\nlayout, GC, IR + register contract, continuations/wind, expander\nhygiene, fibers/reactor, cross-thread ownership), and a fenced tier,\nwhere a contract of spec + tests makes shallow understanding a\ndeliberate, safe choice. It carries the decision rule, per-tier\nobligations, fence-integrity rules, and the reification ladder\n(tacit → documented → checklisted → machine-checked).\n\nThe /quiz skill is the practice: a prediction-with-commitment\ncomprehension quiz on a core-tier subsystem, graded against the\ncurrent code and live runs (never docs), with results appended to a\nper-user ledger at ~/.kaappi/quiz-ledger.md — outside the repo so it\nsurvives worktrees and stays private.\n\nAlso adds the missing /parallel-issues entries to both skill tables:\nthe harness doc claims to cover every component but didn't list it.\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>\n\n* Address review: /quiz argument contract, prep wording, MD040\n\nMake /quiz's subsystem aliases canonical ledger keys mapped to the\nunderstanding map's numbered core-tier sections, and define how a\nsrc/ file argument resolves (owning core section's alias, or — for a\nfile no core section lists — fenced-tier, explicit-request-only, with\nthe file as syllabus and its path as ledger key). Reword the harness\ndoc's protocol summary so \"code is ground truth\" no longer reads as\n\"skip the docs\" (the map is the syllabus; docs are read last for\ndrift detection). Add the MD040 language tag on the decision-rule\nfence.\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-19T15:00:16+05:30",
          "tree_id": "5a490fd8c9ab59b5cd9fcd4ba023e4acc2d4cd19",
          "url": "https://github.com/kaappi/kaappi/commit/f7a136dbbcc0826aed08d26d85cef7014f270fc7"
        },
        "date": 1784455858232,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 2.596931,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.852031,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.573377,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.604789,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.005515,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.038073,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.325951,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.050311,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.124241,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.199049,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.013804,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.328414,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.090009,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.911925,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.028928,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "9da7b393aa7895c63ab0b601e9002d495b8886b6",
          "message": "Harden fiber timed-mutex regression test against QEMU flake (#1665)\n\nThe netbsd-test CI job (a cross-compiled x86_64-netbsd binary in a\nresource-constrained QEMU VM) intermittently failed this KEP-0001 Phase 2\n(#1440) regression test on its `(< wait-elapsed 0.3)` assertion. That bound\nis an absolute wall-clock magnitude on a single sample: when the host\nbriefly deschedules the whole VM near the 0.05s timer expiry, the\nhost-backed clock advances and the sample balloons past 0.3s even though the\nfix is present.\n\nWidening the bound is not an option — the broken build resolves at ~0.7s, so\nany bound loose enough to never flake would also let a genuinely broken build\npass, destroying the regression signal. Instead, assert the ordering the\nregression is actually about: the busy sibling now timestamps its own\ncompletion, and the test checks the timed lock resolved before that\n(wait-elapsed < busy-elapsed). Both samples come from one clock, so a\nslow/loaded VM stretches them together and cannot invert their order — a\npause that inflates wait-elapsed necessarily happened before the sibling\nfinished and inflates busy-elapsed by the same amount. A premise check keeps\nthe sibling comfortably outlasting the timeout, and both timing checks now\nprint the measured values on failure instead of a bare boolean.\n\nVerified the regression is still caught by temporarily neutering the per-tick\ntimer pop in runReactorTick: the test then fails with wait-elapsed just after\nbusy-elapsed, exactly the pre-#1440 behavior.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-19T17:16:58+05:30",
          "tree_id": "48d125a4c01012651e9b22421b51a0e5923d9891",
          "url": "https://github.com/kaappi/kaappi/commit/9da7b393aa7895c63ab0b601e9002d495b8886b6"
        },
        "date": 1784463651126,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.074539,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.708097,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.92222,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.558178,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006707,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.05287,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.513398,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070295,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.202077,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.993752,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.514624,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.478858,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.734423,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.886521,
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
          "id": "b68e1456cde8548b04db36fda21f9bf3e7bc7f12",
          "message": "Add CI guard that fails on non-final SRFIs (#1671)\n\nKaappi intends to ship only SRFIs that have reached final status, but nothing\nenforced it — a stray lib/srfi/<n>.sld for a draft or withdrawn SRFI (or one\nthat gets withdrawn later) would go unnoticed. An audit of the current 78\nimplementations against the canonical registry found them all final; this keeps\nit that way.\n\ntools/check-srfi-status.sh cross-references two derived sources so there is no\nsecond list to drift: the implemented set from `kaappi features --json`\n(builtin + portable, plus SRFI 261 which has no .sld), and each SRFI's status\nfrom admin/srfi-data.scm in the srfi-common repo (what srfi.schemers.org itself\nrenders). The registry is fetched rather than vendored so a newly added SRFI is\nvalidated against its real current status, not a snapshot a contributor could\nmismark.\n\nWired into the test job on one matrix leg, reusing its built binary; kept out\nof run-all.sh since that runs in every leg and this makes a network request.\nExit 77 (SKIP, registry unreachable) maps to a CI warning so a network blip\nnever reds an unrelated change, while a genuine non-final SRFI exits 1.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-19T20:31:05+05:30",
          "tree_id": "bdcab7161917df36e6dc53009457df703a29db54",
          "url": "https://github.com/kaappi/kaappi/commit/b68e1456cde8548b04db36fda21f9bf3e7bc7f12"
        },
        "date": 1784477718578,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.168209,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.982019,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.720627,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.453636,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.005196,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.04094,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.398713,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.053371,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.617459,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.550975,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.168319,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.375711,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.354432,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.357808,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.035445,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "9f6bfe1b051a64ff6f1040dd0e118f8159df972a",
          "message": "Implement SRFI 264 (String Syntax for Scheme Regular Expressions) (#1672)\n\nSSRE is a compact, PCRE-inspired string syntax for regular expressions that\ntranslates to the SRE S-expressions of SRFI 115. Add it as the portable\nlibrary (srfi 264): lib/srfi/264.sld is a faithful port of Sergei Egorov's\nMIT-licensed reference implementation, wrapped in an R7RS define-library over\n(srfi 115). The parser and unparser are pure Scheme; the only runtime\ndependency is `regexp` from SRFI 115 (used by ssre->regexp).\n\nExports ssre->sre, ssre->regexp, sre->ssre, ssre-definitions, ssre-bind, and\nssre-unbind. The derived (srfi srfi-264) alias and the `cond-expand srfi-264`\nfeature id work with no extra code, and `kaappi features` picks 264 up from\nthe build-time lib/srfi scan.\n\nOne deviation from the reference: ssre-syntax-error? checked (string? (cadr x))\nfor the source field, but `fail` raises it as a char list, so the guard was\ndead and a raw list escaped instead of a formatted error object. Check list?\nso ssre-fancy-error runs and syntax errors surface as proper error objects.\n\nTests:\n- tests/scheme/srfi/srfi264.scm runs the upstream conformance corpus (2751\n  parser/unparser cases) verbatim, with an exit-on-failure epilogue so\n  run-all.sh and CI catch regressions.\n- tests/scheme/srfi/srfi264-behavior.scm (SRFI-64) covers ssre->regexp\n  matching through SRFI 115, the ssre-bind/ssre-unbind lifecycle, and the\n  error-object regression above.\n\nBump the SRFI count 78 -> 79 (69 portable) in README, CONFORMANCE, CLAUDE.md,\nthe understanding map, and CHANGELOG.\n\nCloses #1666.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-19T21:41:01+05:30",
          "tree_id": "12992f7a55381f98a73fc76c64810d3ddb4f5e45",
          "url": "https://github.com/kaappi/kaappi/commit/9f6bfe1b051a64ff6f1040dd0e118f8159df972a"
        },
        "date": 1784479778735,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.320551,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.211575,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.898406,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.407293,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006345,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.053468,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.5025,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.071109,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.405298,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.953459,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.625655,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.438714,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.836249,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.704866,
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
          "id": "64901a5f3e04c491e4b8da6cb60f45d34d125d8e",
          "message": "Add /vm-test skill for on-hardware UTM VM testing (#1676)\n\n* Add /vm-test skill for on-hardware UTM VM testing\n\nThe BSD/Linux-arch/Windows ports are validated on a fleet of local UTM\nVMs, but the power-on step and the per-platform build-anywhere/execute-on-\ntarget recipe (cross-compile on the Mac, ship the tree + zig-out + the two\ntest binaries, run on the box) lived scattered across docs/dev/*.md and\nsession memory. This skill consolidates that into one runnable procedure\nand automates the mechanical, error-prone parts.\n\nvm-up.sh maps an ssh alias to its utmctl VM name, launches UTM if needed,\nstarts the VM, and blocks until SSH answers. SKILL.md carries the per-VM\ntable (target triple, admin tool, file signature, deps) and the ship/run\nsteps, encoding the traps these ports have hit: Alpine must be -musl\n(static; no glibc loader), test binaries are selected by file signature\nnot mtime (stale-binary footgun), sync is tar-over-ssh with\nCOPYFILE_DISABLE (rsync is absent on OpenBSD; AppleDouble files fail the\nfmt suite), plus OpenBSD's nobtcfi patch, NetBSD's swap/full-paths, and\nWindows' distinct PowerShell/Git-Bash flow.\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>\n\n* Harden /vm-test recipe against masked failures (review)\n\nAddress the CodeRabbit review on #1676. All six were real correctness bugs\nin commands the skill tells you to run:\n\n- Test-binary selection now fails closed: clear stale staged copies first,\n  then skip the cp entirely when no target-arch binary is found, so a\n  missing build can't ship an old binary.\n- Group the ulimit-carrying $RUNPREFIX in a { …; } before chaining the unit\n  and thottam suites — the semicolons in RUNPREFIX otherwise break the &&\n  chain and let a failed unit suite be masked by the last command's status.\n- Propagate run-all.sh's real exit status instead of the trailing echo's,\n  so an automated caller sees a failed VM run.\n- Invoke bash by full path on NetBSD (new $BASH var; /usr/pkg/bin/bash) —\n  the non-login PATH lacks /usr/pkg/bin, so bare bash fails there. Also\n  apply $RUNPREFIX to run-all.sh (CI raises the same limits for it).\n- Windows: select the test .exe by PE machine type, not mtime (x64 and\n  aarch64 outputs coexist in the cache), and create C:\\tmp\\kaappi-vm before\n  extracting into it (tar -C won't make the dir).\n\nGrouping/exit-status semantics verified with stubbed suites.\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-19T16:55:37Z",
          "tree_id": "98030aef571978f0d060e13a8a7e85d40b65dc34",
          "url": "https://github.com/kaappi/kaappi/commit/64901a5f3e04c491e4b8da6cb60f45d34d125d8e"
        },
        "date": 1784485061892,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.506789,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.313928,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.689149,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.43308,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006479,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.046159,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.390529,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.058133,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.095815,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.517289,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.366927,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.425337,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.52515,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.892488,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.03769,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "03322f2da8a8728aad75717c940253d83fb10478",
          "message": "Implement SRFI 259 and SRFI 229 (tagged procedures) (#1673)\n\nSRFI 259 (Tagged procedures with type safety) is built on SRFI 229\n(Tagged Procedures); neither was implemented. Both land as portable\n.sld libraries loaded on demand.\n\n- (srfi 229): the portable R7RS reference implementation (Marc\n  Nieper-Wisskirchen), reproduced verbatim under its MIT terms.\n  Documented caveat of that portable design: every tagged procedure is\n  retained in a global list for identity tracking, so tagged procedures\n  are never garbage-collected. A native, leak-free implementation (a tag\n  slot on the closure object) is a possible follow-up.\n- (srfi 259): a portable layer over (srfi 229). The single SRFI 229 tag\n  carried by a procedure is an opaque, unexported <tag-set> record\n  mapping each protocol's private, unforgeable key to its tag value, so\n  no code can forge a tag or read another protocol's tag -- the \"type\n  safety\" of the title. define-procedure-tag binds a\n  constructor/predicate/accessor triple; re-tagging preserves other\n  protocols' tags and replaces the same protocol's tag. The <tag-set>\n  also records the original underlying procedure so re-tagging re-wraps\n  it directly instead of nesting wrappers.\n\nThe SRFI 259 repository ships only a Chez-specific sample using native\nmake-wrapper-procedure; this provides the equivalent behavior on the\nportable SRFI 229 primitives instead.\n\nThe srfi-229 / srfi-259 cond-expand feature ids and (library (srfi N))\nprobes derive automatically (#1649); (features) stays platform-only\n(#1517). The build-time lib/srfi scan now reports 70 portable SRFIs.\n\nAdds a 39-assertion SRFI-64 suite (tests/scheme/srfi/srfi259.scm)\ncovering both SRFIs: tag round-trip, closure capture, case-lambda/tag,\npredicate isolation across protocols, accessor error paths, tag\npreservation and replacement, and call-through. Updates SRFI\ncounts/lists in CLAUDE.md, README.md, CONFORMANCE.md, and the\nunderstanding map (78->80 total, 68->70 portable).\n\nCloses #1667.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-19T23:09:31+05:30",
          "tree_id": "a4db7499998e0fcedbf37fe81ab08ba3b00be71c",
          "url": "https://github.com/kaappi/kaappi/commit/03322f2da8a8728aad75717c940253d83fb10478"
        },
        "date": 1784486121158,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.329313,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.827663,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.899027,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.60188,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006322,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.053037,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.498403,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.06852,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.417081,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.953701,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.565182,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.435892,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.829161,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.733164,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045311,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "9ace0b26c3afbff63e12f9f8495abd175c62bcbc",
          "message": "Add SRFI 260 (Generated Symbols) (#1674)\n\ngenerate-symbol mints a fresh symbol on every call with a unique,\nunpredictable name. The point of the SRFI is that — unlike an uninterned\nsymbol (SRFI 258) — a generated symbol keeps write/read invariance:\nprinted and read back it is eq? to the original. Kaappi interns every\nsymbol by name and has no uninterned symbols, so that property is free;\nthe whole SRFI reduces to interning a fresh, unpredictable name.\n\nThe one primitive interns \"<pretty>.<counter>.<128-bit-hex>\": a\nprocess-global atomic counter is a hard in-process uniqueness guarantee\nindependent of entropy quality (and of SRFI-18 threads, which share the\nstatic), while platform.osRandomBytes supplies 128 bits of OS entropy for\nthe unpredictability. The optional pretty-name is a display-only prefix.\n\nWired as the 10th built-in SRFI through a single primitives.Lib tag, so\navailability, the srfi-260 cond-expand id, (srfi srfi-260) SRFI-261\nresolution, and the kaappi features listing all derive automatically —\nno second list to maintain.\n\nCloses #1668\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-20T01:57:14+05:30",
          "tree_id": "a864a9187a193f26cc320ced04364e9d7abeb23c",
          "url": "https://github.com/kaappi/kaappi/commit/9ace0b26c3afbff63e12f9f8495abd175c62bcbc"
        },
        "date": 1784494558162,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.258248,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.75985,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.657299,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.19275,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006153,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.041689,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.401658,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.058684,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.815981,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.406621,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.258999,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.398297,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.365053,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.783956,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.03701,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "b2e6a9f78575611414bf84139c6cb425ef5d1f2e",
          "message": "Implement SRFI 258 (uninterned symbols) (#1675)\n\nAdd string->uninterned-symbol, symbol-interned?, and\ngenerate-uninterned-symbol as the built-in (srfi 258) library. An\nuninterned symbol is a symbol never eqv? to any other, even one built\nfrom the same name — useful for macro programming and guaranteed-unique\nidentifiers.\n\nSymbols already compare by object identity, so equality needed no new\ncode: two uninterned symbols from equal strings, and an uninterned\nsymbol versus its like-named interned twin, are all distinct for free.\nThe only new state is a Symbol.interned flag. allocUninternedSymbol\nbypasses the interning table, so an uninterned symbol is an ordinary\ncollectable object (swept once unreachable) rather than a permanent\nroot; deep copy preserves uninterned-ness across SRFI-18 thread\nboundaries. Per the SRFI, an uninterned symbol has no readable external\nrepresentation: write emits an unreadable #<uninterned-symbol name> form\nand read rejects it, deliberately breaking write/read invariance.\n\nThe gensym counter for generate-uninterned-symbol is a 32-bit atomic\n(wasm32 has no 64-bit atomics); wrap-around is harmless since identity\nis guaranteed by allocation, not the name.\n\nThe library registers through the Lib enum, so kaappi features, the\nsrfi-258 cond-expand id, and (import (srfi 258)) plus the SRFI 261\nfallbacks all derive automatically. Now 83 SRFIs (11 built-in).\n\nCloses #1670.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-20T02:48:16+05:30",
          "tree_id": "71755bde84bfa0201258ac8960cac901d14db33c",
          "url": "https://github.com/kaappi/kaappi/commit/b2e6a9f78575611414bf84139c6cb425ef5d1f2e"
        },
        "date": 1784498112064,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.067213,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 10.298857,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 1.039554,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.965326,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006717,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.054774,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.563387,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.07116,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 4.205429,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 2.163666,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.499286,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.476004,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.760517,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.912516,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045491,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "32dccea48d4833af53e9c39544b159423decea41",
          "message": "Implement SRFI 257: pattern matcher with backtracking (#1678)\n\n* Implement SRFI 257: pattern matcher with backtracking (#1644)\n\nPort Sergei Egorov's reference implementation as portable libraries:\n(srfi 257) plus the misc and box sublibraries. The optional rx\nsublibrary needs SRFI 264 and is deferred.\n\nThe reference match is a CPS protocol of macro-generating macros\n(Petrofsky extraction, classify via nested let-syntax), and porting it\nsurfaced seven general expander/compiler defects, each fixed with a\nregression test in tests_macros.zig:\n\n- let-syntax templates could not reference an enclosing function's\n  locals: transformers now record definition-site lexical free refs\n  (def_site_local_refs) and renameForHygiene keeps them unrenamed when\n  the current frame cannot resolve them, so the normal upvalue path\n  applies; same-frame refs keep the shadow-proof rename+alias path\n- hygienic-capture alias injection could shadow a generated let-syntax\n  macro whose base name collides with a user variable; macro-bound\n  names are now skipped\n- injected aliases now read through boxes: they copy the slot's current\n  is_boxed and markLocalBoxedBySlot flips every same-slot local\n- quasiquote template symbols are data and are no longer hygiene-\n  renamed (2-bit nesting depth; depth-matching unquote resumes\n  expression mode)\n- a hygiene-renamed, unbound identifier now matches an unbound\n  syntax-rules literal of its base name (cm-match's <...>/<_> tokens)\n- pattern-var values substituted into nested syntax-rules templates are\n  wrapped in __hyg-usertext provenance markers, instantiated in\n  substitute-don't-rename mode, and stripped at the compile boundary --\n  without this every expansion generation re-renamed spliced user text\n  under a fresh scope, severing binders from references (the root cause\n  of broken non-linear patterns)\n- literal_bound now resolves a literal's definition-site binding\n  through the full lexical chain, matching the use-site check, so\n  literals bound in enclosing frames (non-linear pattern variables\n  inside generated backtracking lambdas) compare correctly\n\n111 of the reference suite's 112 assertions pass; the exception\ncompares boxes with equal?, which is implementation-specific. Two\nSRFI-241 catamorphism towers in the suite exceed the macro-expansion\nstep limit (runaway expansion, documented). Ships a 22-assertion smoke\nsuite in run-all plus the full port under tests/scheme/srfi/slow/.\n\nCloses #1644\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n* Address review feedback on SRFI 257\n\n- fix the upstream ~if-id-member reference bug: the non-identifier\n  fallback branch expanded an unbound yv where it meant xv, breaking\n  patterns whose atom is not a symbol (sr-match clauses with literal\n  numbers); note the deviation in the library header\n- wire the SRFI-64 failure exit code in both test suites (capture the\n  runner before test-end, exit 1 on failures) per tests/scheme\n  conventions, and cover ~etc+/~etc=/~etc**, the (f -> x) cata\n  operator, and non-symbol sr-match patterns in the smoke suite\n- fix the stale \"Portable SRFIs\" heading count in CONFORMANCE.md\n- rebase over SRFI 264 (#1672): counts move to 80 SRFIs / 70 portable;\n  the rx sublibrary is now unblocked and tracked as a follow-up\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n* Harden stripUsertextMarkers and make expansion context threadlocal\n\nReview follow-ups on the SRFI 257 machinery:\n\n- stripUsertextMarkers now terminates on cyclic inputs (tortoise-hare\n  on the cdr spine, cf. countPairs, plus a depth cap on nested\n  descent) — a macro invoked with a datum-label literal like\n  #0=(1 . #0#) previously hung the walk at every expansion call site —\n  and descends into vector literals so a user-text splice inside #(e)\n  cannot leak a marker pair into runtime data\n- the per-expansion expander context (active_custom_ellipsis,\n  active_literals, active_def_local_refs, active_use_check) is now\n  threadlocal: expansion is reachable from SRFI 18 child-thread\n  compile paths, and plain module globals let concurrent compilers\n  clobber each other's hygiene state\n- CONFORMANCE.md and the library header no longer claim SRFI 264 is\n  unavailable (it landed in #1672); the rx sublibrary stays a\n  follow-up\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n* Address third review round on SRFI 257\n\n- fix a second upstream reference bug: ~seq-append and ~seq-append/ng\n  computed (x-length xv) before consulting the type predicate, so\n  matching (~string-append ...) against a non-string (or\n  (~vector-append ...) against a non-vector) raised a type error\n  instead of failing the pattern; the codegen now gates on (x? xv),\n  with smoke tests for all three mismatch shapes\n- make the remaining shared expansion state thread-safe: scope_table /\n  scope_table_count become threadlocal (they are per-expansion caches,\n  saved/restored around each expansion), and next_scope_id /\n  gensym_counter are bumped atomically so renames stay process-unique\n- raise the stripUsertextMarkers descent cap to 4096 and document why\n  a cap is sound (markers exist only in the freshly built template\n  skeleton, whose nesting is bounded by the expansion limits; the\n  compileForm safety net covers any survivor)\n- root freshly allocated Values across subsequent allocations in the\n  marker-wrap, quote, and quasiquote instantiation paths, per the GC\n  safety guidelines\n- exercise a real provenance marker in the vector-splice regression\n  test (a symbol datum; fixnums are never wrapped) and fix the stale\n  SRFI 264 note in the slow suite header\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n* Address fourth review round on SRFI 257 machinery\n\n- strip vector-valued expansions too: the compile-boundary call sites\n  gated on isPair, so a macro whose whole expansion is #(e) skipped\n  stripping and leaked a marker into the vector constant; regression\n  test added\n- bound unwrapUsertext's chain walk: construction never stacks\n  wrappers, so legitimate chains are one layer; the bound keeps user\n  data forged as marker pairs — including a cyclic\n  #0=(__hyg-usertext . #0#) — from hanging the walk (the marker name\n  lives in the __hyg_ namespace the expander already reserves);\n  regression test added\n- widen quasiquote nesting depth to 3 bits (0-7, saturating) and add a\n  nested-quasiquote macro-vs-direct equivalence test. Towers whose\n  unquotes fully unwind at depth >= 3 turn out to be rejected by the\n  runtime quasiquote evaluator itself, macro or no macro — a separate\n  pre-existing limitation noted in the test\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n* Make forged cyclic marker chains fully inert\n\nRouting the forged #0=(__hyg-usertext . #0#) datum through a macro (as\nthe review asked the regression test to do) exposed a real hang beyond\nthe bounded unwrap: when the chain unwraps to itself, the strip walk's\nre-examine step and the marker-splice instantiation path could loop.\nBoth now treat a chain that unwraps to a marker pair as opaque data,\nand the regression test passes the cyclic datum through expansion.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-20T03:34:42+05:30",
          "tree_id": "0201b9ec44dd57f1d57225a6a3a9b8cbd0f9d789",
          "url": "https://github.com/kaappi/kaappi/commit/32dccea48d4833af53e9c39544b159423decea41"
        },
        "date": 1784500591224,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.186974,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.208364,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.651235,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.304488,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006261,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.042,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.373092,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.053658,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.984498,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.444774,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.247192,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.417647,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.415903,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.025592,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.037074,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "a4d02495f55e05e5e0b393d7ab81f363d3263a25",
          "message": "Implement SRFI 248 (minimal delimited continuations) (#1677)\n\nAdd (srfi 248): with-unwind-handler, empty-continuation?, and the extended\ntwo-variable guard, as a Filinski shift/reset over Kaappi's stack-copying\ncall/cc.\n\nEnabling VM change: a \"sticky\" exception handler (ExceptionHandler.sticky).\nraise/raise-continuable invoke it in place without popping, so a call/cc\nsnapshot taken while it handles includes it and resuming re-arms the prompt\n(reset0 semantics) — what lets coroutine generators work across yields.\nempty-continuation? combines the immediate tail-call latch (native_call_was_tail,\nset by every tail-call opcode) with the sticky handler's frame_count baseline,\nso a raise in tail position of a non-tail-called helper is correctly non-empty.\n\nSavedHandler is now the same type as ExceptionHandler, so captureContinuation\nhands the live handler stack straight to allocContinuation instead of building\na [MAX_HANDLERS]SavedHandler buffer on the stack of every call/cc. That buffer\npredates this branch; dropping it makes the continuations benchmark ~1.4x\nfaster than main rather than ~1.2x slower.\n\nThe public (srfi 248) is a portable lib/srfi/248.sld; the three helper\nprimitives (%call-with-unwind-handler, %unwind-raise-empty?,\n%pop-unwind-handler!) ship in a built-in sub-library (srfi 248 primitives)\nthat the .sld imports and does not re-export.\n\nAll SRFI 248 examples pass — coroutine generators, for-each->fold, effect\nhandlers, and empty-continuation?. Three documented caveats: delimited\ncontinuations are single-shot (resuming the same k twice crosses a native\nframe), the handler runs at the raise point rather than after unwinding, and\nthe metacontinuation cell is per-VM (not fiber-local).\n\nTests: tests/scheme/srfi/srfi248.scm (SRFI-64) and src/tests_srfi248.zig.\n\nCloses #1669.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-20T09:12:43+05:30",
          "tree_id": "2e3315f0e1d9ce61ab77ce043985683293f71870",
          "url": "https://github.com/kaappi/kaappi/commit/a4d02495f55e05e5e0b393d7ab81f363d3263a25"
        },
        "date": 1784521025759,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.321863,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.735022,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.94078,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.713705,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006382,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.054352,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.507821,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070835,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.634813,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 2.00487,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.608372,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.435409,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.831269,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.652418,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045914,
            "unit": "seconds"
          }
        ]
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
          "id": "0687dc40a50acc4b6c870c5c69c407973c55a13f",
          "message": "Release v0.21.0\n\nCo-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>",
          "timestamp": "2026-07-20T12:36:56+05:30",
          "tree_id": "7fcb72049611f3ebdc96c149330446a35f45a370",
          "url": "https://github.com/kaappi/kaappi/commit/0687dc40a50acc4b6c870c5c69c407973c55a13f"
        },
        "date": 1784533868668,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.329331,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.954391,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.973215,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.589273,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006498,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.05454,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.511352,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070531,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.646771,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 2.00724,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.596225,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.437622,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.831128,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.678571,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043622,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "ad7435469bf7c5368eeae99820b7d62dec6fad1b",
          "message": "Remove the duplicate install script (#1683)\n\n* Remove the duplicate install script\n\ninstall.sh in this repo was served by nothing: no build step, no workflow,\nno release artifact referenced it. The only copy anyone runs is\ndocs/install.sh in kaappi.github.io, served at kaappi-lang.org/install.sh,\nwhich is also what the post-release workflow curls and tests.\n\nKeeping a second copy was not free. The two had drifted — the served copy\nwas three hardening commits ahead (KAAPPI_VERSION/KAAPPI_NO_VERIFY, redirect\nbased tag discovery that avoids the API rate limit, a safe stdlib swap) —\nso \"fix install.sh\" in this repo shipped nothing to users, which is exactly\nhow the missing libkaappi_rt.a install went unnoticed. A stale pointer in\ndocs is a wrong sentence; a stale script is a wrong executable that looks\nauthoritative.\n\ndocs/dev/porting.md's Stage 6 now says where the installer lives and what a\nnew platform needs from it — it never mentioned the installer at all, which\nis how the uname-vs-artifact name mismatches (NetBSD's kernel port, the BSDs'\namd64, Linux's ppc64le) keep having to be rediscovered. docs/dev/netbsd.md's\nporting-surface table points at the real path.\n\nThe post-release workflow now asserts the full chain after each release —\narchive present, doctor clean, and a compiled binary that runs — so the\ninstaller regressing to interpreter-only cannot pass CI again. It needs a\nZig step: the runner's cc is GCC, which cannot consume the IR the backend\nemits, and cc_search_order picks it ahead of the preinstalled clang.\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>\n\n* Run the install-script check on every hosted OS/arch\n\nThe installer's platform detection is where its bugs have historically\nlived — NetBSD's uname reporting the kernel port, the BSDs' amd64, Linux's\nppc64le against the artifacts' powerpc64le — and it was only ever exercised\non ubuntu-latest. macOS additionally resolves the exe path through\n_NSGetExecutablePath + realpath rather than /proc/self/exe, which is what\nthe new libkaappi_rt.a assertions depend on to find <exe>/../lib.\n\nriscv64, s390x and ppc64le are left out: no hosted runner executes them\nnatively, and they are interpreter-tier, so there is no archive to assert.\n\nfail-fast is off so one platform's failure does not mask another's.\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>\n\n* Record in CLAUDE.md that install.sh lives in the docs repo\n\nNothing in this repo pointed at the installer after its stale duplicate was\ndeleted, so the next session to be asked about it would rediscover the same\ntrap. Names the real path, why no copy lives here, and what CI checks it.\n\nAlso states the other half explicitly in the native-backend section: the\nruntime archive search does not include ~/.kaappi/lib, so an archive placed\nthere is invisible to kaappi compile. That is exactly the wrong conclusion\nthe search-order list invites, and it is what the Windows install docs got\nwrong until this branch.\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-20T16:07:26Z",
          "tree_id": "2627b5cfdb4a0152c757aac26ef0f02713a15ddb",
          "url": "https://github.com/kaappi/kaappi/commit/ad7435469bf7c5368eeae99820b7d62dec6fad1b"
        },
        "date": 1784565747189,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.993642,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.871761,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.915373,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.438947,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006752,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.053816,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.506911,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.06904,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.301267,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.970286,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.530925,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.47666,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.713081,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.796586,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045251,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "e2c4a8fa0b9d3299689670c6de5be75e316ce8b1",
          "message": "Close the remaining SRFI 115 gaps against the reference (#1681) (#1684)\n\nThe #1680 backtracking rewrite deliberately left every SRE form outside\nits scope. Chibi's own regexp test corpus (chibi is the SRFI 115 reference\nimplementation) flagged them; this closes all of them, entirely within the\nportable lib/srfi/115.sld.\n\nNewly implemented:\n- look-behind / neg-look-behind (%run-behind scans backwards, floored at\n  the search start, which is now threaded through the matcher; handles\n  variable-length bodies)\n- grapheme / bog / eog (full UAX #29: CR-LF, Hangul syllables including\n  conjoining jamo, regional-indicator pairs, combining marks)\n- title-case/title and symbol char sets\n- (&)/(and) and (-)/(difference) char-set operators\n- word as a whole word, and (word+ cset ...)\n\nSemantics fixed:\n- w/ascii / w/unicode now restrict/widen their char sets instead of being\n  no-ops\n- named submatch lookup: regexp-match-submatch et al. accept the (-> name)\n  symbol, first matched group of a repeated name wins, unknown errors\n- w/nocapture actually suppresses submatches\n- (~ a b ...) complements the union of its arguments, not their sequence\n\nEvery <cset-sre> compiles to a node %match-one decides, so ~/&/- never\nre-enter the backtracking matcher. The three Unicode properties (scheme\nchar) cannot answer -- Lt, S*, and the UAX #29 break classes -- ship as\nrange tables inside the .sld, generated by the new\ntools/gen_srfi115_charsets.py (regenerate on a Unicode version bump).\n\nChibi corpus 75/79; the 4 residual failures all use `digit`, a chibi\nextension not in SRFI 115 that Kaappi rightly rejects. Repo srfi115.scm\ngrown 90 -> 141 checks; full Scheme suite green.\n\nCo-authored-by: Claude Opus 4.8 <noreply@anthropic.com>",
          "timestamp": "2026-07-20T22:25:54+05:30",
          "tree_id": "b7919440e28fb355c483995cb524c71507bbf271",
          "url": "https://github.com/kaappi/kaappi/commit/e2c4a8fa0b9d3299689670c6de5be75e316ce8b1"
        },
        "date": 1784568608879,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.329983,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.877018,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.946735,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.594924,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006388,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.05474,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.513547,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070333,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.581139,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 2.004578,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.597567,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.433951,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.81431,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.621233,
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
          "id": "e5b9049e4d141660b016e805267ee887066dbe50",
          "message": "Root heap locals in prettyPrint tests against gc-stress sweeps (#1685)\n\nThe fuzz workflow's gc-stress variant crashed in \"prettyPrint clause form\nindentation\" (run 29720271494, issue #1682): the test held clause1 in an\nunrooted Zig local while the next makeList allocated, and under\n-Dgc-stress=true that allocation's collection swept clause1's pairs. The\nfinal makeList then slice-rooted the dangling value and markValueInner\nsegfaulted reading the freed header.\n\nThe bug usually hides: the freed Pair slot is typically reused by the very\nnext same-size allocation, so the dangling clause1 aliases clause2 and the\noutput silently becomes (cond (#f 2) (#f 2)) — which the old startsWith\nassertion accepted. That is why twelve prior scheduled fuzz runs passed.\nThe assertion is now an exact string compare, so under gc-stress the\nunrooted variant fails in both failure modes (content mismatch or crash).\n\nAlso root `body` in the neighboring body-form test, which stayed safe only\nbecause allocSymbol happens never to collect.\n\nFixes #1682\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-20T23:14:17+05:30",
          "tree_id": "4350531545ce8405a9cb6531c72320f45ff8a665",
          "url": "https://github.com/kaappi/kaappi/commit/e5b9049e4d141660b016e805267ee887066dbe50"
        },
        "date": 1784571330341,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.956971,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.649937,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.933151,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.577101,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006388,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.05478,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.507972,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069799,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.613269,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 2.008713,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.601928,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.430574,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.851179,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.64506,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043299,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "a1d1b2d04b09d4ec816ae426eff697d9f219ff18",
          "message": "Root test locals held across never-collecting allocations (#1682 follow-up) (#1686)\n\nExhaustive audit of every unit-test file for the silent variant of the\n#1682 use-after-free (an unrooted heap local swept under -Dgc-stress=true,\nthen aliased by the next same-size allocation so shape-only assertions\nstill pass): no live instance exists. The #1401 campaign plus the rooting\ndiscipline in the newer test files already cover every collecting-call\nsite; the seeming hits fall to gc.enabled = false (tests_srfi254,\ntests_srfi258) or to allocation paths that never call maybeCollect.\n\nTwo sites do hold a heap value across an allocating call that merely\n*happens* never to collect, the situation PR #1685 roots `body` for:\n\n- \"bignum compare\" holds `a` across a second parseBignumString, which\n  builds its Bignum via raw create+trackObject with no maybeCollect.\n- The bytecode-cache mid-run-GC test holds f0/f1 across further\n  makeReturnConstFunc calls, safe only because allocFunction never\n  collects.\n\nRoot both per that convention so neither silently breaks if those paths\never gain a collection point. Verified with the full unit suite and with\n-Dgc-stress=true filtered to the two files (Debug and ReleaseSafe).\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-20T18:34:29Z",
          "tree_id": "5debc6630ed28765c29e9c0974110b9fb7d8ae10",
          "url": "https://github.com/kaappi/kaappi/commit/a1d1b2d04b09d4ec816ae426eff697d9f219ff18"
        },
        "date": 1784574419444,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.980452,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.79294,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.911932,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.443658,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006713,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.053142,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.508113,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.067543,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.307188,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.971421,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.530153,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.469229,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.703887,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.614534,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044519,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "10b56fe4d4870a905e9536e69aac165ea50af1b0",
          "message": "Detect mark-time use-after-free deterministically under gc-stress (#1687) (#1690)\n\nThe #1682 dangling-local bug survived twelve nightly gc-stress runs\nbecause both existing defenses structurally miss marking-time UAF: the\nDebug 0xAA poison makes a freed header's owner read as some other GC's\nid, so markValueInner's #958 foreign-owner skip silently absorbs it, and\nwhen the freed slot is recycled by the next same-size allocation the\nowner is valid again and the corruption is invisible.\n\nTwo mechanisms close those escape modes, comptime-gated so release\nbuilds pay nothing:\n\n- Freed-owner sentinel (Debug or gc-stress): poisonAndDestroy stamps\n  Object.owner with the reserved FREED_OWNER id (0xFFFF_FFFF, skipped by\n  nextGcId) after the poison memset, and markValueInner/weakReachable\n  panic with \"GC: marking freed object (use-after-free)\" on reading it —\n  a deterministic, attributable failure instead of a lucky segfault.\n\n- Free-quarantine (gc-stress only): freed header slots are withheld from\n  the allocator and released oldest-first, only past a 4 MiB per-GC cap\n  and only between a later collection's mark and sweep phases, so every\n  slot survives at least one full mark after its free and the sentinel\n  stays readable instead of the slot aliasing a recycled live object.\n  GC.deinit and the two arena resets that never collect\n  (shared_channel.resetForReuse, bench_channel.freeArena) drain it.\n\nVerified per the issue's acceptance criterion: both the synthetic\nunrooted-local-into-makeList case and the actual #1682 test with its\n#1685 rooting fix reverted panic with the freed-object message on 8/8\ngc-stress runs (previously: twelve silent runs before one crash). Full\nunit suite green in normal, Debug, and gc-stress builds; wasm/Linux/\nWindows/FreeBSD cross-compiles and the stress binary's Scheme smoke +\nSRFI-254 weak-ref suites all pass.\n\nCloses #1687\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-21T01:25:42+05:30",
          "tree_id": "a5953a2ffaeba5451d658a9f1002f86df73bc6f4",
          "url": "https://github.com/kaappi/kaappi/commit/10b56fe4d4870a905e9536e69aac165ea50af1b0"
        },
        "date": 1784579326254,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.271046,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.093734,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.969513,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.461018,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006411,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.054798,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.54007,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070744,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.58533,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.993798,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.588764,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.437098,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.80456,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.653055,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045185,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "f72e5479d527c4f84e567657d15ab09fb0925512",
          "message": "Fuzz report: file pre-fuzz unit-test failures per variant with the failing test names (#1689)\n\n* Report fuzz-job unit-test failures under per-variant titles with test names\n\nFollow-up to #1682, closes #1688. When the fuzz job failed without a\ncrash marker, the report job filed everything under the shared \"Fuzz CI:\ninfrastructure or build failure\" issue, even though fuzz-run.log already\nnamed the crashing test — triage started from \"toolchain download, apt\nflake, runner OOM?\" when the answer was in the downloaded artifact.\n\nThe report job's fuzz routing is now three-way: crash marker → finding\nissue (unchanged); no marker but the log's test summary counts a\nfailed/crashed/leaked test → a dedicated deduped issue per variant\n(\"Fuzz CI: unit-test failure (gc-stress variant)\") with the failing test\nnames extracted from the error lines and panic-trace frames, plus the\ntargeted hint that a gc-stress-only crash usually means a GC rooting bug\n(.claude/rules/gc-safety.md, #1401, #1682); anything else keeps the\nshared infra issue. The variant comes from the failed build command\nechoed at the end of the log, not the artifact directory name, which the\nsingle-artifact download layout makes unreliable (#1584, #1620). Both\nmatrix variants classify independently when both fail.\n\nThe log excerpt is also anchored by pattern now instead of tail -c 2000:\nthe #1682 crash trace only made the excerpt because it happened to sit\nat the end of the log. The excerpt starts at the first test-failure\nreport, compile diagnostic, or Build Summary line (raw tail as\nfallback), bounded head+tail when the failure section is long.\n\nValidated with a local harness: the filing script extracted from the\nYAML, a stubbed gh, and nine synthetic artifacts/ layouts (flattened and\nper-name, both variants, marker present, dedup-append, mixed\nunit-test+flake, oversized section, missing artifacts, diff-job\nregression).\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n* Classify the other variant's log even when one variant crashed\n\nReview follow-up (CodeRabbit on #1689): the crash-marker branch ran\nexclusively, so when variant A found a fuzz crash while variant B\nindependently failed (unit-test failure or flake), B's failure was\nsilently dropped — neither filed nor collected for the infra issue.\n\nThe crash finding is still filed first, but every uploaded fuzz-run.log\nis now classified; only logs sitting next to a crash marker (that\nvariant IS the finding already filed) are skipped, which also stops a\nsecond crashing variant's log from being misread as a unit-test\nfailure. A crash with no other logs files exactly the finding issue, as\nbefore. The residual gap — a variant that died before uploading any\nartifact while the other crashed — is not detectable from artifacts\nalone, since the aggregate needs.fuzz.result does not say which matrix\nlegs failed.\n\nHarness gains the two scenarios: crash + other-variant unit-test\nfailure files both issues; crash + other-variant flake files the\nfinding plus the infra issue with the flake log excerpted.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-20T20:00:25Z",
          "tree_id": "5908be958937441d9fbf441f8a851863fbee2da5",
          "url": "https://github.com/kaappi/kaappi/commit/f72e5479d527c4f84e567657d15ab09fb0925512"
        },
        "date": 1784579646009,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.28008,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.910464,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.966686,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.461132,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006416,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.054339,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.531623,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.07109,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.596127,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.996885,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.574359,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.432686,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.811318,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.637871,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043671,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "bf764591cd2d569965d4c08434fd6b552c3b6ec6",
          "message": "Document 16 excluded final SRFIs with rationale (#1707)\n\n* Document 16 excluded final SRFIs with rationale\n\nRecord which final SRFIs are excluded from implementation and why,\nso the decision isn't relitigated. Two categories: 7 meta/ecosystem\nSRFIs already covered by existing Kaappi features, and 9 non-standard\nreader syntax SRFIs that would fundamentally alter the parser.\n\nCo-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>\n\n* Reference SRFI exclusions doc and roadmap from CLAUDE.md\n\nAdd a summary line at the end of the SRFI libraries section pointing to\ndocs/dev/srfi-exclusions.md and the implementation roadmap (issues\n#1691–#1706, four milestones).\n\nCo-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.6 <noreply@anthropic.com>",
          "timestamp": "2026-07-21T02:05:21+05:30",
          "tree_id": "db82600c4cad0cca4a536a1a7351df2218a780a4",
          "url": "https://github.com/kaappi/kaappi/commit/bf764591cd2d569965d4c08434fd6b552c3b6ec6"
        },
        "date": 1784582816832,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.987622,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.336411,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.917399,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.360712,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006742,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.053185,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.507099,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068073,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.287931,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.965493,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.514985,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.472276,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.754872,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.748405,
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
          "id": "8209892aee9952a2d62b473d73610ac8322d0f38",
          "message": "Add CLAUDE.md for docs/dev/ directory (#1708)\n\nGives Claude Code quick orientation when working inside developer\ndocumentation — directory layout, key documents by task, and conventions\nfor adding or editing docs.\n\nCo-authored-by: Claude Opus 4.6 <noreply@anthropic.com>",
          "timestamp": "2026-07-21T02:12:50+05:30",
          "tree_id": "c6aefe127bb375451489ec36e51018b1239ac38b",
          "url": "https://github.com/kaappi/kaappi/commit/8209892aee9952a2d62b473d73610ac8322d0f38"
        },
        "date": 1784584016627,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.98823,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.024997,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.913726,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.409326,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006751,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.052579,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.50679,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068049,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.286511,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.962409,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.517688,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.472067,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.706647,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.825647,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045377,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "fe05ec92023362cf0920b925d24d3aab557a8190",
          "message": "Add 15 portable SRFIs (Phase 1 — quick wins, high value) (#1709)\n\n* Add 15 portable SRFIs (67, 95, 129, 135, 162, 171, 185, 190, 194, 221, 223, 228, 234, 252, 253)\n\nSRFI Phase 1 — quick wins, high value. All are pure portable .sld\nimplementations with comprehensive test suites:\n\n- 67  Compare Procedures (195 tests)\n- 95  Sorting and Merging (62 tests)\n- 129 Titlecase (18 tests)\n- 135 Immutable Texts (106 tests)\n- 162 Comparators sublibrary (46 tests)\n- 171 Transducers with (srfi 171 meta) sub-library (48 tests)\n- 185 Linear adjustable-length strings (14 tests)\n- 190 Coroutine Generators (8 tests)\n- 194 Random data generators (11404 tests)\n- 221 Generator/accumulator sub-library (18 tests)\n- 223 Bisecting search (16 tests)\n- 228 Composing Comparators (82 tests)\n- 234 Topological sorting (13 tests)\n- 252 Property testing (105 tests)\n- 253 Data (type) checking (105 tests)\n\nTotal supported SRFIs: 85 → 100 (11 built-in + 88 portable + SRFI 261).\n\nCloses #1692, closes #1696.\n\nCo-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>\n\n* Address review: missing imports, ASCII-only char range, SRFI 261 count\n\n- Add (scheme process-context) import to 8 test files that use (exit 1)\n  without it (srfi129, srfi162, srfi171, srfi185, srfi190, srfi221,\n  srfi223, srfi234)\n- Raise SRFI 252 max-char from 128 to #x110000 so char/string/symbol\n  generators cover full Unicode (surrogate filter was already in place)\n- Mention SRFI 261 in CLAUDE.md SRFI libraries section to reconcile\n  the 11 + 88 + 1 = 100 count\n\nCo-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 4.6 <noreply@anthropic.com>",
          "timestamp": "2026-07-21T07:24:41Z",
          "tree_id": "f6c77e2c5618b7f16c1260e1de16653ed2db79d6",
          "url": "https://github.com/kaappi/kaappi/commit/fe05ec92023362cf0920b925d24d3aab557a8190"
        },
        "date": 1784620903253,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.297555,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.818274,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.980399,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.579084,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006355,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.054589,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.547167,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.071151,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.497479,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 2.102959,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.568749,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.424914,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.81082,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.571877,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043261,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "46d0a57f280a4bacf5a81ea60b345941e1128a62",
          "message": "Extend fuzzing beyond x86_64 to ARM64 and big-endian targets (#1710)\n\n* Extend fuzzing beyond x86_64 to ARM64 and big-endian targets\n\nThe Fuzz workflow ran only on x86_64 Linux, so two bug classes had no\nfuzz coverage: aarch64 code generation in the LLVM native backend, and\nbyte-order bugs — the .sbc codec's littleToNative conversions are no-ops\non little-endian, so an endian bug there is invisible until a big-endian\nmachine runs it.\n\n- fuzz, native-diff, and oracle-diff now run natively on x86_64 AND arm64\n  (ubuntu-24.04-arm). The arm64 native-diff leg is the only fuzz coverage\n  of aarch64 codegen; the arm64 fuzz legs re-exercise the NaN-box pointer\n  assumptions and GC write barriers on ARM's memory model.\n\n- New cross-diff job (tests/fuzz/cross-diff.sh) diffs the same Kaappi build\n  on the host vs a foreign arch under QEMU (s390x/riscv64/ppc64le). Zig\n  0.16's fuzzer cannot instrument a cross-compiled target (\"no fuzz tests\n  found\"), so a black-box host-vs-target differential is the portable\n  substitute — and because both sides are the same interpreter on the\n  deterministic portable subset, any output difference is definitively an\n  architecture bug. s390x is the big-endian canary.\n\n- The report job files one finding issue per platform/arch, attributed\n  from a file each job plants in its artifact (fuzz-platform.txt/arch.txt)\n  rather than the artifact directory name, which download-artifact erases\n  for single-artifact runs. It loops over every marker so a crash on one\n  arch never swallows another's.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n* Attribute fuzz findings by variant, not just platform\n\nAddresses the CodeRabbit review on #1710. The fuzz job planted\nfuzz-platform.txt but never the variant, so two downstream problems in the\nreport job:\n\n- The crash title used only the platform, so a default-variant crash and a\n  gc-stress crash on the same platform collapsed into one issue thread.\n- report_unit_test_failure recovered the variant by grepping fuzz-run.log\n  for -Dgc-stress=true — coupled to zig's failure-output format.\n\nPlant fuzz-variant.txt alongside fuzz-platform.txt (matrix.variant is right\nthere), upload it, and add a variant_of() helper mirroring platform_of().\nThe crash title and job id now include the variant, and report_unit_test_\nfailure reads the planted file. variant_of keeps the log grep as a fallback\nfor artifacts predating the planted file — verified that zig does echo the\nfailing build command (with -Dgc-stress=true), so the fallback is real, not\njust defensive.\n\nReport-classifier scenario suite extended to 13 cases: same-platform\nboth-variant crashes now file two distinct issues, and the gc-stress\nlog-fallback path is covered.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-21T16:35:49+05:30",
          "tree_id": "52f847817b68f84886d875be8f6d871f67dccc73",
          "url": "https://github.com/kaappi/kaappi/commit/46d0a57f280a4bacf5a81ea60b345941e1128a62"
        },
        "date": 1784634164737,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.296237,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.093734,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.997295,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.614108,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006408,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.055847,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.552726,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.071375,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.51794,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 2.120786,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.599706,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.432685,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.843847,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.651352,
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
          "id": "55e5bc6ae00d696fc49503f95a73d70d4e0660db",
          "message": "Add 12 SRFI data-structure libraries: 44, 101, 153, 161, 167, 168, 178, 209, 214, 217, 224, 225 (#1712)\n\n* Add SRFI 44 (Collections) and SRFI 225 (Dictionaries)\n\nSRFI 44: generic collection operations (fold, size, contains?, add/delete,\netc.) dispatched via runtime type-case across list, vector, string, a new\nalist-map record, and the existing (srfi 69) hash-table / (srfi 113)\nset and bag. No object system in Kaappi, so dispatch is a closed set of\nconcrete types rather than Tiny-CLOS-style extensible generics.\n\nSRFI 225: a Dictionary Type Object (DTO) abstraction unifying alists and\nhash tables behind one generic dict-* API, built around dict-find-update!\nas the core primitive. Ships eqv-alist-dto, equal-alist-dto, and\nhash-table-dto/srfi-69-dto.\n\nBoth are independent library files with no shared dependency between them,\nfollowing the existing portable-SRFI conventions in lib/srfi/*.sld. Scope\ndecisions and naming-collision notes are documented in each file's header.\n\n239 tests pass for SRFI 44, 101 for SRFI 225.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* Add SRFI 101 and SRFI 214 as portable libraries\n\nSRFI 101 (purely functional random-access pairs/lists): a genuine\nskew-binary random-access list implementation (Okasaki) giving O(1)\ncons/car/cdr and O(log n) list-ref/list-set/list-tail/length/list?,\nmatching the spec's stated complexity except for append (O(n), documented\nas likely unachievable at O(log n) for a generic persistent structure).\nShadows 44 (scheme base) identifiers within its own library scope.\n\nSRFI 214 (flexvectors): a mutable growable-vector record wrapping a\nnative vector backing store with capacity doubling, delegating read-only\nwhole-vector operations to the built-in (srfi 133).\n\nBoth include SRFI-64 test suites (120 assertions for 214, ~370 logical\nassertions expanding to 8779 with stress-test loops for 101), covering\nthe spec's own worked examples plus persistence and complexity-sensitive\nedge cases.\n\n* Add SRFI 167, 168, and 209 as portable libraries\n\nSRFI 167 (Ordered Key Value Store): in-memory okvs/engine implementation\nbacked by (srfi 146) mappings over bytevector keys ordered by (srfi 128)'s\nbytevector comparator. Transactions get real atomicity/rollback via\ncopy-on-write mapping snapshots, no locking needed since there is no\nconcurrent access. engine-pack/unpack implement an order-preserving\ntag+value encoding (booleans, exact integers, strings, symbols) modeled on\nthe FoundationDB tuple layer.\n\nSRFI 168 (Generic Tuple Store Database): nstore layered directly on SRFI\n167 — tuples are stored keys-only via engine-pack/okvs, queried via\nengine-prefix-range + in-memory pattern matching. Reproduces the SRFI's own\nblog/triplestore worked example end to end.\n\nSRFI 209 (Enums and Enum Sets): enum types/sets with a boolean\nmembership-vector representation. define-enum/define-enumeration required\nworking around an expander limitation where quoting a pattern variable\ndirectly inside a macro that is both self-recursive and generated by an\nenclosing macro doesn't substitute correctly — routing the lookup through\nthe flat (non-recursive) name-dispatch macro instead sidesteps it. Also\nhad to route enum<->enum-type's mutual reference through an id+registry\nindirection rather than direct record fields, since Kaappi's printer loops\non cyclic record fields and SRFI-64 prints every value it's given.\n\n74 + 26 + 125 = 225 test assertions across the three new suites, all\npassing; full existing tests/scheme/srfi/*.scm suite (125 files) still\ngreen.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* Add SRFI 161, 178, and 217 as portable libraries\n\nSRFI 161 (Unifiable Boxes): union-find with path compression and union\nby rank, per the spec's own suggested implementation strategy.\n\nSRFI 178 (Bitvector library): a record wrapping a byte-per-bit\nbytevector, matching the spec's own reference strategy (\"a whole byte\nto represent each bit ... favoring simplicity/speed over compactness\").\n\nSRFI 217 (Integer Sets): a sorted, duplicate-free list wrapped in a\nrecord rather than the spec's Patricia-trie reference representation\n— correct and simple, trading the spec's near-constant-time complexity\nfor straightforward O(n) operations, documented in the file header.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* Add SRFI 153 and 224 as portable libraries\n\nBoth are records wrapping a sorted list (153: by the SRFI 128 comparator's\nordering predicate; 224: by fixnum key) rather than the specs' respective\nbalanced-tree/Patricia-trie reference representations — O(n) per operation\nin exchange for a straightforward, obviously-correct implementation.\nDocumented in each file's header.\n\nSRFI 153 additionally handles comparators with no ordering predicate\n(e.g. SRFI 128's eq-comparator): sortedness is vacuous for such a\ncomparator, so osets built on one just keep insertion order (deduplicated)\ninstead of erroring — needed because the spec's own oset-map example\nconstructs exactly such an oset.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* Update SRFI counts for Phase 2 data-structure batch\n\n105 -> 117 total SRFIs (93 -> 105 portable), reflecting the 12 new\nlibraries added in this batch (44, 101, 153, 161, 167, 168, 178, 209,\n214, 217, 224, 225).\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* Address review: dedup/rotation/ordering bugs surfaced by CodeRabbit\n\n- srfi/153: %dedup only removes adjacent duplicates, which only holds\n  once a list is sorted. The unordered-comparator path in %build skips\n  sorting (nothing to sort by for e.g. eq-comparator), so it needs an\n  order-independent dedup instead — fixes real duplicate leakage for\n  osets built on unordered comparators.\n- srfi/178: bitvector-map/bool and bitvector-map!/bool called f with a\n  single list argument instead of applying it to the bit booleans (a\n  broken values-list->args helper masqueraded as a splat). Both were\n  untested; added regression tests. make-bitvector-accumulator also\n  double-reversed its accumulator, silently correct only for palindrome\n  inputs — fixed and re-tested with a non-palindrome input.\n- srfi/224: fxmapping-union built its result with %make-fxmapping\n  directly instead of %build, breaking the ascending-key-order invariant\n  when a later mapping supplies a smaller key than one already folded\n  in. fxmapping-intersection/combinator never actually called proc to\n  combine values — it filtered m1's keys but kept m1's values unchanged.\n  Both fixed and regression-tested.\n- srfi/168: documented (not fixed) a real but narrower limitation —\n  nstore prefixes must be pairwise non-prefixing when multiple nstores\n  share an engine, since %all-tuples prefix-scans the packed bytes\n  directly. Not triggered by the spec's own worked example (a single\n  nstore); a real fix would need a redesigned key encoding with an\n  explicit prefix delimiter, which risks destabilizing the\n  already-verified reference example for a narrower edge case.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* Fix oset-accumulate: preserve first-generated duplicate, not last\n\nacc is built newest-generated-first via cons, but was passed to %build's\nkeep-first?=#t unreversed — meaning \"keep the first element in the list\"\nactually kept the most-recently-generated duplicate, not the first, for\nany two generated elements equal per the comparator. The spec requires\n\"the first such element prevails.\" Reversing acc before %build fixes it.\n\nRegression test generates an exact 1, then an inexact 1.0 (equal under\nthe comparator's =, distinct objects), and confirms the exact 1 survives.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-22T09:43:11+05:30",
          "tree_id": "81cbbe011a4ef6de05ff70602d40247850047114",
          "url": "https://github.com/kaappi/kaappi/commit/55e5bc6ae00d696fc49503f95a73d70d4e0660db"
        },
        "date": 1784695677752,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.820336,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.670722,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.828306,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.865802,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006474,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.050833,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.437841,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.063865,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.757649,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.667716,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.461858,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.403921,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.65565,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.941937,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.04139,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "2f2f4930eb1f94a0d0cc72aed5f37eac419fb4eb",
          "message": "Add 20 SRFI binding/control and misc libraries (closes SRFI Phase 2) (#1722)\n\n* Add SRFI 216 (SICP Prerequisites) and SRFI 238 (Codesets)\n\nSRFI 216: portable SICP compatibility shim (true/false/nil,\nthe-empty-stream, runtime, random, parallel-execute, test-and-set!,\ncons-stream, stream-null?), built on Kaappi's built-in SRFI 18 and\nSRFI 27. Deviates from the reference implementation's (runtime) (which\nmultiplies instead of dividing by jiffies-per-second) and its\noutput-capturing parallel-execute; both deviations are documented in\nthe file header along with the global-vs-local shared-state limitation\nof Kaappi's deep-copying SRFI-18 threads.\n\nSRFI 238: generic codeset lookup API (codeset?, codeset-symbols,\ncodeset-symbol, codeset-number, codeset-message) instantiated with\nthree portable codesets built from real ISO standards instead of the\nOS-sourced errno/signal codesets in the SRFI's own reference\nimplementations: 'iso3166 (70 verified countries), 'iso639 (183\nentries, essentially the complete ISO 639-1 alpha-2 set), and\n'iso15924 (88 verified scripts). The file header documents these as\nrepresentative, individually-verified subsets rather than exhaustive\nregistries.\n\n26 and 50 SRFI-64 tests pass respectively; full tests/scheme/srfi/\nsuite (99 files, ~27.9k tests) still passes with these two added.\n\n* Add SRFI 46, 203, and 242 as portable libraries\n\nSRFI 46 (Basic Syntax-rules Extensions) is a re-export: Kaappi's\nsyntax-rules already implements both specified extensions natively\n(custom ellipsis identifiers, tail patterns), verified against the\nspec's own examples.\n\nSRFI 203 (SICP Picture Language) implements the spec's actual minimal\nAPI (canvas lifecycle, draw-line, a placeholder rogers painter, and\nimage-file painters) using an in-memory SVG document as the canvas,\nsince Kaappi has no window system or image codec.\n\nSRFI 242 (The CFG Language) implements the static-label subset (cfg,\nexecute, halt, bind, label*, call). Dynamic labels (labels), finally,\npermute, and the define-cfg-syntax*/define-cfg-label* extension forms\nare out of scope — they need a dominance-based free-variable analysis\nand/or syntax-case-level macro extensibility that a portable\nsyntax-rules transformer can't reasonably provide. Rationale and an\nescape-hatch pattern for real loops are documented in the file header.\n\n* Add SRFI 156, 226, 236, and 239 as portable libraries\n\nSRFI 156 (Syntactic combiners for binary predicates) and SRFI 236\n(Evaluating expressions in an unspecified order) are direct ports of\nthe SRFIs' own portable reference implementations.\n\nSRFI 226 (Control Features) is enormous — 12 sub-libraries unifying\ndelimited continuations, continuation marks, parameters, fluids,\npromises, exceptions, and threads. This implements the reduced subset\nthat's honestly buildable as a portable library on Kaappi's existing\ncall/cc, dynamic-wind, and make-parameter: (srfi 226 control prompts)\n(escape-only, via call/cc), (srfi 226 control continuations)\n(non-composable continuations, continuation-barrier as a pass-through,\nunwind-protect), and (srfi 226 control times). Composable\ncontinuations, continuation marks, fluids, and the exceptions/\nconditions/threads libraries need either genuine new VM primitives or\nidentifier-macro support R7RS syntax-rules doesn't guarantee; scope\nand rationale are documented in lib/srfi/226/control/prompts.sld.\n\nSRFI 239 (Destructuring Lists) implements `list-case` from scratch\n(the SRFI's own sample implementation is R6RS-only) via a syntax-rules\nmacro that classifies clauses by head shape and dispatches on the\nscrutinee's pair/null/atom-ness, handling `_` placeholders without\never emitting a lambda with a duplicate parameter name.\n\nSRFI 206 (Auxiliary Syntax Keywords) is not implemented. Its own\nspec text states no portable syntax-rules-only implementation is\npossible — the core feature (auxiliary keywords from independent\nlibraries matching via free-identifier=?) needs identifier-property\nsupport at the expander level. A reduced shell that accepts the\nsyntax but drops that matching semantics would provide no real value\nover just writing an ordinary error-raising macro directly, so it's\nexcluded rather than shipped as a misleading stub.\n\n* Add SRFI 7, 188, 201, and 251 as portable libraries\n\n- SRFI 7 (feature-based program configuration language): a near-verbatim\n  port of the SRFI's own cond-expand-based reference macro, with an added\n  explicit else-error clause since Kaappi's cond-expand silently no-ops on\n  an unmatched clause instead of erroring.\n- SRFI 188 (splicing let-syntax/letrec-syntax): implemented as plain\n  delegates to the non-splicing forms. True splicing is confirmed\n  unachievable in Kaappi (its body scanner only recognizes a literal\n  leading define/define-record-type/define-syntax token, not a\n  macro-produced begin), matching the SRFI's own statement that no\n  portable R7RS implementation is possible.\n- SRFI 201 (syntactic extensions to core bindings): pattern-matching\n  lambda/define/let/let*/or, exported under the SRFI's own reference\n  names (mlambda, cdefine, named-match-let-values, match-let*-values,\n  or/values) rather than shadowing scheme-base's lambda/define/let/let*/or\n  directly. Shadowing those names with any non-trivial syntax-rules\n  transformer was found to trigger a real Kaappi engine bug (infinite\n  macro expansion, or a GC root-count underflow surfacing much later in\n  an unrelated library's define-record-type) -- documented in detail in\n  the library header.\n- SRFI 251 (mixing definitions with expressions in bodies): mixed-lambda/\n  mixed-define/mixed-let/mixed-let* implement the spec's T translation\n  (each maximal run of definitions opens a fresh nested scope) rather\n  than shadowing core forms, for the same reason as SRFI 201. Documents\n  two scope limitations found via testing against the SRFI's own worked\n  examples: the static forward-reference check isn't enforced, and a\n  body-local macro that produces a definition isn't recognized when used\n  from a nested scope different from where it was defined.\n\n70 SRFI-64 tests across the four suites, all passing.\n\n* Add SRFI 71 (Extended LET-syntax for multiple values)\n\nExtends let/let*/letrec so a binding can destructure the multiple\nvalues an expression returns, while staying backward compatible with\nordinary single-value bindings including named let.\n\nTwo Kaappi-specific engine constraints shaped the implementation,\ndocumented in the file header:\n\n- Once a library redefines a core special-form name, that name can't\n  be used to reach the original form from anywhere else in the same\n  program -- not via a separate helper library that never touches the\n  name (its reference gets silently recaptured by whatever shadows the\n  name at the final expansion site), and not via renaming on import\n  (see kaappi/kaappi#1718). So named let and letrec are built from\n  lambda/define only, which this library leaves untouched.\n- define-values does not provide letrec*-style mutual/forward\n  visibility the way plain define does, confirmed with zero macros\n  involved. So letrec's variables are pre-declared with plain define\n  (one per flattened name) and then assigned via call-with-values +\n  set!, not routed through define-values.\n\n* Add SRFI 86 (MU and NU simulating VALUES and CALL-WITH-VALUES)\n\nmu/nu are ported as-is (the spec's own two-line macros). alet/alet*\nimplement the binding-spec forms that compose cleanly with mu/nu's CPS\nstyle: plain bindings, multi-value destructure (wrapped and flat\nshorthand, proper and dotted-rest), escape procedures, mutually\nrecursive rec groups, and effects-only clauses. The Scsh-style\nopt/cat/key positional and keyword argument sub-language, the\nand-integration and whole-alet-as-procedure forms, and named alet/alet*\nare out of scope -- see the file header for what and why. alet and\nalet* are both sequential (left-to-right visibility) rather than alet\nbeing truly parallel, a scope reduction documented in the same header.\n\n* Add SRFI 165 (The Environment Monad)\n\nIndependent implementation (the spec links an external, dependency-\nheavy sample rather than inlining one). Environments are an\nassociation list wrapped in a record, keyed by the environment-variable\nobject via eq?; a computation wraps a plain (environment -> results)\nprocedure directly, since ask/local/fn/with all need direct environment\naccess that the compute-only make-computation surface can't provide on\nits own. define-computation-type (an O(1)-access optimization over what\nthis already provides, not new observable behavior) is not implemented.\n\n* Add SRFI 247 (Syntactic Monads)\n\ndefine-syntactic-monad threads a fixed set of state variables through\nlambda/define/case-lambda/let*-values/procedure-call/named-let-loop use\nsites at compile time. The spec's own sample implementation is R6RS\nsyntax-case only (source not inlined in the document); this is an\nindependent syntax-rules implementation, verified against every one of\nthe spec's own worked examples (all match exactly, including the\nlambda-parameter shadowing rule and the let-loop threading example).\n\nTwo Kaappi-specific engine quirks shaped the implementation, both\ndocumented in the file header and worth tracking upstream:\n- A syntax-rules definition generated by another macro's template,\n  whose own literals list includes `let` specifically, fails to\n  recognize `let` at the use site -- every other literal tried in the\n  identical nested shape (lambda, define, case-lambda, let*-values)\n  works fine. Routing dispatch through a second, non-nested macro\n  sidesteps it.\n- Re-collecting one ellipsis-bound pattern variable wholesale (via its\n  own nested ellipsis) from inside a different, sibling ellipsis's\n  per-iteration template doesn't expand correctly; resolving one\n  variable at a time via recursion instead does.\n\n* Add SRFI 5, 51, and 244 as portable libraries\n\nSRFI 5 (A compatible let form with signatures and rest arguments) is a\nfaithful port of the SRFI's own syntax-rules reference implementation;\nit redefines let directly (no scope reduction needed -- the reference\nalgorithm is already plain portable syntax-rules). Verified against\nboth the full regression suite and its own test suite with no\nregressions or delayed corruption from the let redefinition.\n\nSRFI 51 (Handling Rest List) is a direct port of the SRFI's own full\nreference implementation: rest-values plus the arg-and/arg-ands/\nerr-and/err-ands/arg-or/arg-ors/err-or/err-ors checking macros.\n\nSRFI 244 (Multiple-value Definitions) is a re-export: define-values is\nalready a built-in Kaappi special form, so this is a conformance\nstatement rather than new functionality, like SRFI 46.\n\nSRFI 212 (Aliases) is not implemented. Its own spec text states\nplainly: \"A portable Scheme implementation is not possible\" -- transferring\na binding so two identifiers share the same location, for any binding\ntype including syntax, needs syntax-case-level (or R6RS alias-native)\nidentifier/location introspection that a syntax-rules-only system can't\nprovide.\n\n* Update SRFI counts and exclusions for Phase 2 completion\n\n137 SRFIs now supported (up from 117): 11 built-in, 124 portable,\nplus SRFI 261 (import-resolver convention) and SRFI 226 (sub-libraries\nonly, no bare (srfi 226) file) as the two special-cased entries that\ndon't appear as bare numbers in kaappi features' scan.\n\nAdds SRFI 206 and 212 to docs/dev/srfi-exclusions.md as a new\n\"macro-system-dependent\" category (18 excluded total, up from 16) --\nboth SRFIs' own spec text states a portable syntax-rules-only\nimplementation isn't possible, gated on the same syntax-case-level\nwork tracked in KEP-0006/0007.\n\nCloses the SRFI Phase 2 milestone: issue #1691 (data structures) was\nalready merged; this closes #1698 (binding & control forms) and #1706\n(miscellaneous), both fully accounted for -- every listed SRFI is\neither implemented or explicitly excluded with rationale.\n\n* Address CodeRabbit review findings on PR #1722\n\nFixed:\n- SRFI 165: computation-each/computation-forked crashed on zero\n  computations (dereferenced (cdr '()) before the empty check)\n- SRFI 226: the default prompt tag is now always available, even before\n  any enclosing call-with-continuation-prompt, per spec (\"a continuation\n  prompt tagged with the default prompt tag is available in the initial\n  continuation of each thread\"). Documented, rather than fixed, that the\n  default abort handler only approximates the spec's \"reinstall the\n  prompt and resume\" semantics, since that needs composable\n  continuations this port explicitly excludes.\n- SRFI 238: codeset-symbol/-number/-message/-symbols now reject a\n  non-symbol codeset argument (\"it is an error to pass a codeset\n  argument of some other type\"), distinct from an unrecognized-but-valid\n  codeset symbol, which the spec says must stay lenient (treated as an\n  empty codeset).\n- SRFI 239: two bugs. A second clause of the same shape (pair/null/atom)\n  used to silently overwrite the first instead of being reported as a\n  mistake -- pair/null/atom are exhaustive and disjoint, so a shape\n  never legitimately needs two clauses. The atom clause's `_` now gets\n  the same discard-without-binding treatment the pair clause already\n  had, for consistency with the documented \"_ means don't bind this\"\n  contract (no independently observable behavior difference, since a\n  bound-but-unused `_` is behaviorally identical to an unbound one).\n- SRFI 216: added a genuine overlap/rendezvous test for\n  parallel-execute -- the existing tests (every thunk ran, a race lands\n  on a legal value, no lost updates under a lock) all also pass a\n  purely serial fake implementation. Verified the new test fails against\n  a hand-written serial fake before adding it.\n- SRFI 251: rewrote the named-mixed-let test. It previously nested its\n  definition inside a begin/if, making the named mixed-lambda's body a\n  single top-level form -- %251-body's one-form base case fired\n  immediately and returned it untranslated, exercising none of\n  %251-defs's actual collect-and-close-the-group logic. Verified the\n  new version by temporarily breaking that logic and confirming the\n  test catches it.\n- docs/dev/srfi-exclusions.md: removed dangling references to\n  keps/0006-explicit-renaming-macros.md and\n  keps/0007-full-syntax-case-support.md -- neither exists in the keps\n  repo (only KEPs 0001-0005 do) -- replaced with a reference to the\n  actually-tracked issue #1699. Removed the \"Revisiting these decisions\"\n  section entirely: pure roadmap/future-work commentary redundant with\n  each SRFI's own Why-excluded/Scope-of-change entries, against this\n  repo's own \"roadmap and future work go in issues, not docs\" rule.\n\nDeclined, after checking the actual spec text rather than the review\ncomment alone:\n- SRFI 238's codeset-symbol/codeset-number \"fast path\" (return code\n  as-is when it's already the target type) is spec-mandated, not a bug:\n  the spec says \"If code is a symbol, return it as-is,\" unconditioned on\n  codeset validity. Caught this by fetching the spec directly after an\n  initial (wrong) attempt to also gate the fast path on codeset\n  validity, which would have broken that guarantee.\n- SRFI 236's exact \"zero values\" test for zero-expression\n  `independently` is not a spec assertion (the spec leaves the result\n  unspecified) but a regression check on the ported reference\n  implementation's own deterministic behavior -- kept, with the test\n  description reworded to make that distinction explicit rather than\n  reading as a spec-conformance claim.\n\nFull regression: 1940/1940 Scheme tests pass, Zig unit suite passes.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-22T15:51:39+05:30",
          "tree_id": "1168901441cb74bf0830a8e45aaaeb53fe06dbca",
          "url": "https://github.com/kaappi/kaappi/commit/2f2f4930eb1f94a0d0cc72aed5f37eac419fb4eb"
        },
        "date": 1784717946008,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.362516,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.717401,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.951909,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.54422,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006309,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.054065,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.52474,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070167,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.594203,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 2.027233,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.578567,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.430751,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.871583,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.592573,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043548,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "860beb34eff127508a063d565c66814138ebf7f7",
          "message": "Add 12 SRFI libraries, exclude 2, defer 1 (SRFI Phase 3) (#1728)\n\n* Add SRFI 30 and SRFI 62 wrapper libraries\n\nBoth are already-implemented R7RS reader syntax (nested block comments\nand datum comments); these are thin marker libraries with no exports\nso (import (srfi 30)) / (import (srfi 62)) succeed.\n\n* Add SRFI 169 (Underscores in numbers) and SRFI 270 (Hex float constants)\n\nBoth are genuine reader/lexer changes, not portable libraries:\n\n- SRFI 270: #x1.2p3-style hex float syntax in readIntegerWithRadix/\n  readHexFloatSuffix (reader_tokens.zig), sharing digit decoding with\n  string->number via bignum.parseHexFloat (bignum.zig), since the spec\n  requires string->number to also understand this syntax. The one new\n  procedure the spec adds, write-hexadecimal-float, is fully portable\n  (lib/srfi/270.sld) -- exact rational arithmetic via (exact x) gives a\n  flonum's precise value without needing raw bit access, so it round-trips\n  bit-exactly including subnormals, signed zero, and complex numbers.\n\n- SRFI 169: a single underscore as a digit separator strictly between two\n  digits anywhere in a numeric literal, in any radix. The digit-scanning\n  loops across reader_tokens.zig (readNumber's mantissa/exponent/\n  imaginary-part loops, readIntegerWithRadix, scanDenominatorDigits,\n  SRFI 270's readHexFloatSuffix) now tolerate an embedded underscore\n  without stopping the scan early; actual validation and stripping is\n  centralized in bignum.stripUnderscores, called from parseDecimalReal,\n  parseHexFloat, parseBignumString, and directly before each remaining\n  parseInt call. Misplaced underscores (leading, trailing, doubled, or\n  adjacent to a sign/./exponent-marker//radix-prefix) are rejected, not\n  silently accepted or dropped.\n\nFiled #1724 for a small pre-existing, unrelated gap noticed along the\nway: string->number's small-integer path inherits Zig std.fmt.parseInt's\nown (more permissive) underscore tolerance, wrongly accepting \"1__2\" as\n12 -- not something either SRFI asks to fix, since neither touches\nstring->number's decimal-integer path by design.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* Add SRFI 70 (Numbers), excluding its incompatible NaN-comparison clause\n\nSRFI 70 predates R7RS and argues that 0/0 (NaN) should be an illegal\nargument to <, <=, >, >= rather than silently comparing false. R7RS\nlater overrode that stance explicitly (\"all the predicates return #f\"\non +nan.0), and Kaappi already implements the R7RS rule throughout its\narithmetic, so this port deliberately omits that clause and does not\ntouch =, <, <=, >, >= at all.\n\nWhat's implemented as a pure .sld wrapper (no engine changes): the four\nnew exact-floor/exact-ceiling/exact-truncate/exact-round convenience\nprocedures, and shadowed quotient/remainder/modulo/gcd/lcm/expt that\nextend their domain to exact rationals (quotient/remainder/modulo also\ninherit Kaappi's existing inexact-real support) and fix `(expt 0 n)`\nfor negative exact n to return +inf.0 instead of raising a\ndivision-by-zero error, while leaving inexact +/-0.0's existing\nIEEE-signed behavior untouched. Every case is verified against SRFI\n70's own worked examples and reference implementation.\n\n* Add SRFI 29 (Localization)\n\nMessage-bundle localization: declare-bundle!/localized-template with the\nspec's exact locale fallback (package+language+country -> +language ->\npackage-only), current-language/current-country/current-locale-details\naccessors, and best-effort store-bundle!/load-bundle! persistence via\n(scheme file) + SRFI 170's temp-file-prefix. Also exports a format that\nextends (srfi 28)'s directives with SRFI 29's ~N@* absolute positional\nreference, needed for translations that reorder arguments.\n\nResolves two spec inconsistencies (documented in the file header): the\nSpecification section's signature heading spells the store procedure\n\"store-bundle\" but every other occurrence including the reference\nimplementation uses \"store-bundle!\", used here; and \"Bundle Searching\"\nsays an exhausted fallback should raise an error while\nlocalized-template's own procedure spec and reference implementation\nreturn #f, followed here.\n\nUpdates the SRFI count/list in CLAUDE.md, README.md, and CONFORMANCE.md\n(124 -> 125 portable, 137 -> 138 total).\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* Add SRFI 54 (Formatting) and SRFI 94 (Type-Restricted Numerical Functions)\n\nSRFI 54 implements `cat`, a free-sequence (type-directed, order-independent)\nstring formatter, ported from the spec's reference implementation with its\ncustom syntax-rules argument-parsing macros replaced by an equivalent\n`%cat-extract` function threaded through `let*-values` — easier to verify\nline-by-line against the spec's worked examples, nearly all of which are\nreproduced verbatim in the test suite.\n\nSRFI 94 adds thin type-checking wrappers (real-exp, real-ln, real-log,\nreal-sin/cos/tan/asin/acos/atan, real-sqrt, real-expt, integer-sqrt,\ninteger-expt, integer-log, quo, rem, mod, ln) around existing Kaappi\nprimitives. It deliberately does not re-export the spec's other seven\nsame-named replacements (abs, atan, make-rectangular, make-polar, quotient,\nremainder, modulo): four already satisfy the restriction natively, and the\nother three (quotient/remainder/modulo) would create an R7RS-ambiguous\nbinding against (scheme base) — see the .sld header for the full rationale.\n\nAlso documents a real gap found in `expt`: a negative real base with a\nnon-integer exponent (e.g. `(expt -8 1/3)`) returns +nan.0 instead of the\ncorrect complex result, unlike `sqrt` which handles negative reals properly.\nreal-expt's guard avoids this path entirely, matching the spec's own\nreference implementation.\n\nUpdates the SRFI count/list in CLAUDE.md, README.md, and CONFORMANCE.md\n(137->139 supported, 124->126 portable). Related but not closed: #1697 and\n#1700 each batch several other SRFIs alongside 54 and 94.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* Add SRFI 215 (Central Log Exchange)\n\nPortable (srfi 215): send-log plus the current-log-fields and\ncurrent-log-callback parameters, matching the spec's \"one procedure,\ntwo parameters, eight constants\" surface exactly (EMERGENCY..DEBUG,\n0-7). current-log-callback is a single dynamically-scoped slot with no\nregister/unregister API, per spec -- installed via parameterize or a\ndirect call, exactly like current-output-port. Its default value\nbuffers messages until a real callback replaces it, then flushes them\nin order via the parameter's converter (which Kaappi runs once per\nreplacement, never on parameterize's restore). Field values are\nwritten to a string unless already string?/bytevector?/exact-integer?/\nerror-object?; SEVERITY and MESSAGE are stored as given.\n\n44 SRFI-64 tests cover all eight severities, message structure,\nexplicit and ambient (current-log-fields) fields, value conversion,\nthe two spec-mandated error conditions, severity-based filtering\n(entirely the callback's own job, per spec), multiple receivers via a\nhand-rolled fan-out callback, and both forms of \"unregistering\" a\nreceiver. Full tests/scheme/run-all.sh suite (546 Scheme files + 1395\nR7RS tests) passes.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* Add SRFI 207 (String-notated bytevectors) and fix kaappi fmt for it\n\n#u8\"...\" is a genuine reader change (readByteStringLiteral in\nreader_tokens.zig, a deliberately separate function from the ordinary\nstring reader since the escape grammar and direct-character rules\ndiffer: direct characters must be printable ASCII, and \\xHH; decodes to\nexactly one raw byte 0-255, not a UTF-8-encoded codepoint). Also adds\nthe four procedures most directly tied to the notation itself\n(bytestring, bytevector->hex-string, hex-string->bytevector,\nwrite-textual-bytestring) -- the full spec defines ~25 procedures across\nan independent bytestring-processing library (padding, trimming,\nsearch, join/split, base64) that issue #1705 didn't scope in and this\nport doesn't implement, documented as a deliberate reduction in the\nlibrary's header.\n\nkaappi fmt has its own separate comment-preserving lexer (fmt.zig) that\ndidn't know about #u8\"...\" at all -- its scanHash only matched #u8( (the\nlist form), so #u8\"hello\" fell through to scanAtom, which stops at any\ndelimiter including '\"', splitting one token into two (\"#u8\" then a\nseparate string). Its own round-trip safety net correctly caught this\nas \"formatting would change the program\" rather than silently\ncorrupting anything, but it needed the actual fix: a new scanHash arm\nthat recognizes the #u8\" prefix and delegates to scanString's existing\nescape-aware boundary scanning (which only needs to find the real\nclosing quote, not decode escape semantics, so it works unchanged for\nthis different escape grammar).\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* Add SRFI 180 (JSON)\n\nPortable JSON reader/writer built on SRFI 158's generator/accumulator\nabstraction (already in this codebase, used by other ports like\n(srfi 225)): json-generator turns JSON text into a stream of events via\na coroutine generator over a recursive-descent parser, json-fold is a\ngeneric foldts-style iterator over that stream, json-accumulator is the\nwriter-side mirror, and json-read/json-write are the convenience\nport-based entry points most callers use.\n\nType mapping: null <-> the symbol 'null, true/false <-> #t/#f, array <->\nvector, object <-> an alist keyed by symbols. Numbers are read via a\nstrict RFC 8259 character-by-character grammar check before handing the\nvalidated substring to string->number, so exactness follows Kaappi's own\nnumeric-literal rules for free. Strings handle all short escapes plus\n\\uXXXX including UTF-16 surrogate pair combination, rejecting unescaped\ncontrol characters and unpaired surrogates per RFC 8259.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* Add SRFI 192 (Port Positioning)\n\nport-position, set-port-position!, port-has-port-position?, and\nport-has-set-port-position!? -- built-in (no lib/srfi/192.sld), gated\nbehind a new srfi_192 Lib tag. Positions are plain exact-integer byte\noffsets for every port kind; the spec's opaque \"implementation-dependent\nobject\" alternative for textual ports and the dedicated\ni/o-invalid-position-error condition type are not implemented (any\nfailure raises an ordinary error instead), documented in the primitives'\nown doc comments.\n\nString ports already tracked their own position for free (string_pos,\nstring_out_len). The real engine work is fd-backed ports: a new\nplatform.seek (POSIX lseek, Windows _lseeki64 -- wiring up a previously\ndead, unused extern -- and WASI fd_seek, which needs its own whence_t\nenum rather than a bare c_int, caught by the wasm32-wasi cross-compile\ncheck) plus correcting the OS's raw offset for whatever this port's own\nsoftware buffers have read ahead of (peek_byte, peek_extra, read_buf) or\nnot yet flushed behind (write_buf) -- otherwise position would silently\ndrift from what a subsequent read-then-position or position-then-read\npair expects. set-port-position! on an fd port discards the read-ahead\nbuffers (stale once the position jumps) and, per spec, flushes pending\nwrites first even when the position won't change.\n\nVerified: unit tests including a regression for the buffered-read-ahead\ncorrection and the flush-before-seek behavior; cross-compiled for\nwasm32-wasi, x86_64-windows, x86_64-linux, aarch64-macos.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* Reconcile SRFI counts and exclusions for Phase 3\n\n149 SRFIs supported (12 built-in, 135 portable, plus SRFI 261's\nresolver convention and SRFI 226's sub-library-only libraries), up from\n137/11/124 -- Phase 3 added 12 implemented SRFIs (29, 30, 54, 62, 70,\n94, 169, 180, 192, 207, 215, 270) and 2 newly-excluded ones (58, 208).\n\ndocs/dev/srfi-exclusions.md: added SRFI 58 (Array Notation) to the\nexisting \"Non-standard reader syntax\" category next to SRFI 163, which\nalready documents the identical typed-array-infrastructure blocker;\nadded a new \"Value-representation-dependent SRFIs\" category for SRFI\n208 (NaN procedures), whose bit-level NaN introspection Kaappi's\nNaN-boxing value representation makes categorically unrepresentable,\nnot merely unimplemented. 18 excluded SRFIs -> 20.\n\nCONFORMANCE.md: added a detailed coverage section for the newly\nbuilt-in SRFI 192, and table rows plus reduced-scope footnote entries\nfor the newly portable SRFIs (70 and 207 ship a reduced scope; the\nother 10 are full implementations).\n\nAlso fixes a small inconsistency from three independent contributors\n(two background agents plus this integration pass) each partially\nupdating the same dense count paragraph in CLAUDE.md -- rewritten once,\ncompletely, from kaappi features --json's authoritative output rather\nthan merging partial edits.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* Address CodeRabbit review findings on PR #1728\n\nVerified each finding directly against current code (and spec text via\nindependent WebFetch where the finding hinged on spec interpretation)\nbefore fixing or declining, per established project practice.\n\nFixed (7 genuine bugs):\n\n- string->number: a hex float whose mantissa overflows i64 (radix 16)\n  fell into the plain-integer overflow fallback, which doesn't\n  understand '.'/'p' and wrongly returned #f. Check for hex-float\n  syntax before attempting the plain-integer parse.\n- bignum.parseHexFloat: a pathologically long exponent digit run\n  overflowed the i32 accumulator and panicked (a real crash) in the\n  default ReleaseSafe build. Cap accumulation; any exponent magnitude\n  this large already saturates to +inf.0/0.0 regardless.\n- port-position/set-port-position!/port-has-port-position?: didn't\n  check is_open, so a closed port's stale fd (reused by the OS for an\n  unrelated file) could be silently repositioned or reported as valid.\n- set-port-position!: discarded read-ahead/peek buffers before the\n  underlying seek was confirmed to succeed; reorder to discard only on\n  success.\n- Output string ports: set-port-position! plus a shorter write\n  truncated everything after the write instead of overwriting in\n  place, unlike a seekable fd-backed port's OS-provided lseek+write\n  semantics. Added a write-cursor (string_out_pos) independent of the\n  buffer's total extent (string_out_len).\n- SRFI 215 current-log-callback: the converter flushed buffered\n  messages in one pass, but proc isn't actually current yet while its\n  own flush runs -- a message proc sent reentrantly via send-log\n  landed back in the buffer and was stranded until some unrelated\n  future callback replacement. Loop the flush until the buffer is dry.\n  Confirmed by repro before fixing.\n- SRFI 215 current-log-callback: an invalid (non-procedure) argument\n  cleared the buffer before attempting to use it, permanently losing\n  already-buffered messages even though the install itself failed.\n  Validate proc before touching the buffer.\n\nFixed (1 real but narrower issue, given a more robust fix than the\nminimal one needed):\n\n- SRFI 215's default buffering callback grew without limit before any\n  real callback was ever installed. The spec permits any\n  \"implementation-defined number\" with no stated overflow behavior, and\n  the original unbounded choice was a deliberate, documented reading of\n  that clause -- but a program whose only SRFI-215 user is a dependency\n  that logs routinely, and which never itself installs a callback,\n  would leak memory for its entire run. Capped the buffer, dropping the\n  oldest half at once when full (O(1) amortized) to keep a rolling\n  window of recent activity instead of growing without bound or (with\n  naive one-at-a-time eviction) paying O(cap) per call indefinitely.\n\nFixed (2 confirmed nitpicks, mechanical and low-risk):\n\n- SRFI 207's bytevector<->hex-string and %ascii-string? used indexed\n  string-ref/string-set! loops; Kaappi strings are UTF-8 byte arrays\n  with no fast codepoint-index path, so string-ref/string-set! are\n  O(k) per call and an indexed loop over a whole string is O(n^2).\n  Confirmed by reading utf8IndexToByteOffset directly. Rewrote to walk\n  string->list/list->string sequentially (both genuinely O(n),\n  confirmed by reading their implementations too).\n- reader_tokens.zig's readByteStringLiteral repeated an identical\n  3-line whitespace-skip loop 4 times across its line-continuation\n  escape handling. Extracted skipIntralineWhitespace.\n\nDeclined (1 finding, doesn't hold up against the spec text):\n\n- SRFI 215's send-log validating SEVERITY range / MESSAGE type. Fetched\n  the spec directly: it enumerates exactly two required validations for\n  send-log (odd-length plist, non-symbol key) and is conspicuously\n  silent on severity/message types -- those constraints are documented\n  as properties of a well-formed message (what a correct caller\n  produces), not as input validation send-log itself must perform.\n  Adding it would be unrequested speculative validation.\n\nAll 10 findings were genuine and independently verified (a different\noutcome from some earlier review rounds in this project, e.g. PR #1722,\nwhere a finding didn't survive verification) -- 9 fixed, 1 declined\nwith spec citation. Every fix has a regression test that fails without\nit. Full suite green: zig build test, 1952/1952 Scheme tests (557\nfiles + 1395 R7RS), kaappi fmt corpus (727 files, zero drift).\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* CI: bump Debug leg timeout from 30 to 40 minutes\n\nThe Debug leg has been running at its timeout ceiling with no real\nheadroom: a clean baseline run on this branch completed in 29:03, then\nafter this PR's own new tests landed, two consecutive reruns timed out\nat 30:16 and 30:21 -- both times the log shows nothing but the runner\nterminating orphaned zig/build processes at the 30:00 mark, not a test\nfailure. The suite has grown enough that the 30-min cap stopped being\na hang-bound (per the comment already at this call site) and started\nbeing exactly the \"race the suite\" problem that comment warns against.\nSame fix as the macOS/PR #1635 recurrence.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* CI: pin test job's check name independent of matrix.timeout\n\nThe test job had no explicit name, so GitHub auto-generated its check\nname from every matrix property present for a given combination --\nincluding include-only ones like timeout. Bumping the Debug leg's\ntimeout (30 -> 40, previous commit) silently renamed its check from\n\"test (ubuntu-latest, Debug, 30)\" to \"...Debug, 40\". Branch protection\nrequires that exact old string, so the renamed check can never be\nsatisfied again -- it sits \"Expected -- Waiting for status to be\nreported\" forever, blocking merge.\n\nPin the name to just os+optimize so a future timeout tweak can't repeat\nthis. The other four legs' names are unchanged (they already matched\nthis shape with no timeout override); only Debug's changes, from\n\"test (ubuntu-latest, Debug, 30)\" to \"test (ubuntu-latest, Debug)\" --\nbranch protection's required check list needs updating to match.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-23T01:41:22+05:30",
          "tree_id": "cb7d4a064b8aa77ca733306e53069346d18db15c",
          "url": "https://github.com/kaappi/kaappi/commit/860beb34eff127508a063d565c66814138ebf7f7"
        },
        "date": 1784753295360,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.976923,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.447585,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.92367,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.402175,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006723,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.053532,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.508897,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068301,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.290885,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.976158,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.535025,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.468936,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.731031,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.771908,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044958,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "d8853a26901293789bf4a02e59da1954a0b7d251",
          "message": "Add SRFI 181 custom ports (#1730)\n\n* Add SRFI 181 custom ports (closes #1727; transcoded ports split to #1729)\n\nImplements make-custom-binary-input-port, make-custom-binary-output-port,\nmake-custom-textual-input-port, make-custom-textual-output-port,\nmake-custom-binary-input/output-port, and make-file-error. This is the\nSRFI deferred out of Phase 3 (#1728) for being disproportionately\ncomplex: Port has never held a Scheme Value field before, and custom\nports need their read!/write!/get-position/set-position!/close/flush\nhooks to be Scheme procedures -- the first Value-bearing fields Port has\nhad, plus the first time a port needs to call back into Scheme\nreentrantly.\n\nTwo research passes and a design review (full spec fetch, tracing the\nGC marking switches and the reentrant-call/fiber-parking mechanism)\nproduced a validated design and caught concrete bugs before they\nshipped: a memory leak (missing freeObject/objectSize sites -- 5\ngc_collect.zig touch points needed, not the obvious 3), a\nuse-after-free trap (Kaappi strings reallocate their whole backing\nbuffer in place on a differing-byte-width string-set!, so a read!\ncallback's buffer must never be cached across the call), and a\nsilent-data-loss ordering bug (portWriteBytes has two fd-handling\nsteps, not one -- a custom port's branch must precede both).\n\nTranscoded ports (make-transcoder, codecs, eol-styles, the raise\nerror-handling mode) are split into #1729: the raise mode specifically\nneeds vm.callHandler's continuable-raise machinery, which is\narchitecturally harder than the custom-port plumbing itself.\n\nDesign:\n- Port.custom_backend: ?*CustomBacking holds the 6 callback Values\n  (read!/write!/get-position/set-position!/close/flush), following the\n  existing random_gen field's \"owned pointer, freed with the port\"\n  shape. GC-marked via a shared markPortValues helper wired into all\n  three marking switches (referencesYoung, markObjectContents,\n  markValueInner) plus the two dedicated freeObject/objectSize arms.\n- GC.allocCustomPort follows allocMultipleValues's slice_roots\n  template (rootArgs1/rootArgs2 cap out at 2 Values; this needs up to\n  6 protected across one allocation).\n- readOneByte/portWriteBytes (the single byte source/sink every port\n  primitive already funnels through) gained a custom-port branch each,\n  reusing the existing UTF-8 decode/encode pipeline by exploiting that\n  Kaappi strings are already UTF-8 byte arrays internally.\n- Custom port callbacks run through vm.callWithArgs, which always\n  executes with dispatched_from_scheduler forced false. A callback\n  that tries to block (another port's I/O, thread-sleep!) is rejected\n  with a catchable error via a new, narrow vm.in_custom_port_callback\n  counter (checked in fiber.waitForFd and threadSleepFn) instead of\n  risking the confirmed native-stack-overflow a silent recursive\n  scheduler drive would otherwise allow under concurrent fibers.\n- port-position/set-port-position!/port-has-port-position? (SRFI 192)\n  gained custom-port branches for free integration with get-position/\n  set-position!. close-port/flush-output-port gate their callback\n  invocations on is_open/non-#f so a double-close or a #f flush never\n  double-invokes or misfires.\n\n150 SRFIs now supported (13 built-in, up from 12). Doc counts\nreconciled across both CLAUDE.md files, README.md, and CONFORMANCE.md\nfrom `kaappi features --json`. Cross-compiles clean for Windows x86_64\nand WASM (zero platform-specific code -- every operation is a Scheme-\nlevel callWithArgs call). Full regression green: zig build test\n(including -Dgc-stress=true), 1953 Scheme tests (558 files + 1395\nR7RS).\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* Address CodeRabbit review findings on PR #1730\n\nVerified each finding directly against current code before fixing or\ndeclining, per established project practice.\n\nFixed (3 genuine bugs):\n\n- writeBytesToCustomPort: re-allocated and copied the entire shrinking\n  \"remaining\" slice into a fresh bytevector/string on every partial-\n  write iteration, even though write! never mutates its buffer -- O(n^2)\n  for a callback that only accepts a small chunk per call (the exact\n  \"one-at-a-time\" pattern this PR's own test file already exercised).\n  Confirmed via a 20000-byte write through a 1-byte-at-a-time callback\n  (12ms after the fix). Now allocates once and varies start/count.\n- closePort: didn't flush a custom output port before invoking\n  close_proc, unlike setPortPositionOnCustomPort (which already flushes\n  before seeking) and the fd path's drainWriteBuffer. R7RS: \"If port is\n  an output port, it is flushed before being closed.\" Confirmed via a\n  custom port simulating internal buffering (data relies on flush! to\n  emit) that silently lost it on close-port without the fix.\n- raiseCustomPortCallbackBlocked's error message said \"tried to block\n  on another port's I/O\", but the function is also raised from\n  threadSleepFn for thread-sleep! -- misleading for that case. Now\n  covers both.\n\nAdded (1 nitpick, genuinely strengthens coverage):\n\n- A new GC-stress test that passes allocCustomPort's callback arguments\n  in deliberately unrooted (from the test's own perspective) and forces\n  a collection via the runtime gc.stress field during the allocator's\n  own maybeCollect() call -- the existing two tests pre-root the\n  callbacks externally, so neither could actually detect a regression\n  in allocCustomPort's own slice_roots usage specifically. Verified by\n  temporarily removing the slice_roots assignment and confirming this\n  new test (and only this one) fails.\n\nDeclined (1 finding, real but out of scope for this PR):\n\n- types.zig exceeds the 1500-line policy (1627 lines). Confirmed this\n  predates this PR entirely (1605 lines on main already, before SRFI\n  181's 22-line addition) -- an organic, 105-commit history of one-more-\n  heap-type additions past the file's own documented ~500-line target.\n  A proper split is a repo-wide structural change touching call sites\n  across dozens of files (every heap type here is referenced from\n  primitives files, memory.zig, gc_collect.zig, every vm*.zig file,\n  printer.zig, and more) -- exactly the kind of \"heavy lift\" this\n  project scopes into its own focused PR rather than bundling into a\n  feature PR's already-large diff (same reasoning that split transcoded\n  ports into #1729). Filed as #1731 with a suggested first-cut split\n  and context for whoever picks it up.\n\nAll 5 findings were genuine and independently verified: 3 fixed with\nregression tests (each proven to fail without its fix), 1 test-coverage\nnitpick added, 1 declined with a filed follow-up and clear reasoning.\nFull suite green: zig build test, 1953/1953 Scheme tests (558 files +\n1395 R7RS).\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-23T08:26:57+05:30",
          "tree_id": "6f3c27fa2051390321fc7f6e8eb65a59c6ffad5a",
          "url": "https://github.com/kaappi/kaappi/commit/d8853a26901293789bf4a02e59da1954a0b7d251"
        },
        "date": 1784777130134,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.981008,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.429176,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.908313,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.379089,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006674,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.052694,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.50594,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.067996,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.333013,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.954859,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.509003,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.469617,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.717967,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.765668,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.04513,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "c06791039e6e42003aabc7714481635e49fd78ae",
          "message": "Add SRFI 181 transcoded ports (#1732)\n\n* Add SRFI 181 transcoded ports\n\nCompletes SRFI 181 alongside the custom ports already shipped in #1730:\nmake-transcoder, native-transcoder, codecs (utf-8-codec/make-codec),\neol-styles, the replace/raise error-handling modes, transcoded-port,\nbytevector->string/string->bytevector, and the i/o-decoding-error?/\ni/o-encoding-error?/i/o-encoding-error-char/unknown-encoding-error?\ncondition accessors.\n\nClosing the registry-shadows-a-same-named-.sld gap this uncovered (the\nsame one SRFI 248 already solved) required moving (srfi 181) off its\ndirect registry entry onto a real lib/srfi/181.sld backed by a new\n(srfi 181 primitives) sub-library — so it's now sandbox-embedded like\n(kaappi parallel), and reclassifies from builtin to portable in\n`kaappi features` (150 SRFIs: 12 builtin, 136 portable; doc counts\nreconciled in CLAUDE.md/README.md/CONFORMANCE.md).\n\nPort.transcode (a wrapped_port Value plus plain Codec/EolStyle/ErrorMode\nenums) follows custom_backend's precedent for GC integration. The decode/\nencode loops funnel through readOneByte/portWriteBytes exactly like every\nother port, committing one character per call so a fiber park (which\nreruns the whole native call from scratch) never loses partial progress;\nCRLF lookahead reuses the wrapped port's own peek_byte, the same\nmechanism read-line's CR/CRLF handling already relies on. raise mode\nneeded a mechanism custom ports never did: primitives_control.\nraiseContinuable (factored out of raise-continuable itself) signals a\ncontinuable condition and resumes after the handler returns, safe from\nretry-from-scratch since a reentrant runUntil always runs with\ndispatched_from_scheduler forced false. v1 supports only the UTF-8\ncodec; latin-1-codec/utf-16-codec are not exported at all rather than\nbound to always-failing procedures.\n\nCloses #1729.\n\n* Freeze unknown-encoding-error-name's string, per spec\n\nSRFI 181 requires unknown-encoding-error-name's result to be immutable\n(\"it is an error to mutate this string\") -- the same contract Kaappi\nalready enforces for symbol->string via flags.immutable. make-codec was\nreturning the caller's own make-codec argument verbatim: mutable unless\nthe caller happened to pass a literal, and aliased to the caller's own\nstring object either way.\n\nFixed by round-tripping through string->symbol/symbol->string, the only\nportable way to freeze a string's exact content without a new native\nprimitive. Caught by review; the first regression test written for this\npassed even without the fix, since it used a string literal (already\nimmutable via the reader's own quoted-data handling) rather than a\ngenuinely mutable string -- fixed to use string-copy instead, and added\na second test confirming the condition doesn't alias the caller's string.",
          "timestamp": "2026-07-23T13:26:08+05:30",
          "tree_id": "b6f482577a9467a005b9fea3727c7b190f9727f7",
          "url": "https://github.com/kaappi/kaappi/commit/c06791039e6e42003aabc7714481635e49fd78ae"
        },
        "date": 1784795715526,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.015114,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.282341,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.591024,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.95212,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.005569,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.039385,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.337135,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.048046,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.841725,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.30274,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.147056,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.361894,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.281067,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.733492,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.033847,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "cbf4dbe4d2f1115b4f390230a4733963ce125ba2",
          "message": "Add 7 SRFI libraries, exclude 3, reduce 1 (SRFI Phase 4 slice 1) (#1733)\n\n* Add 7 SRFI libraries, exclude 3, reduce 1 (SRFI Phase 4 slice 1)\n\nImplements SRFI 59 (Vicinity), 90 (Extensible hash table constructor,\nreduced scope), 112 (Environment Inquiry), 123 (Generic accessor and\nmodifier operators), 126 (R6RS-based hashtables, non-weak baseline),\n173 (Hooks), and 193 (Command line) from issue #1703.\n\nA new shared native primitive surface (src/primitives_sysinfo.zig,\n`(kaappi sysinfo)`) backs the script-path/version/platform inquiries\nthese libraries need: %script-path (vm.script_path, resolved once in\nrunFile -- absolute, `.`/`..` normalized, symlinks never followed) feeds\nboth SRFI 59's program-vicinity and SRFI 193's script-file/\nscript-directory; %implementation-version/%os-name/%cpu-architecture\nfeed SRFI 112.\n\nSRFI 88 (Keyword objects) and SRFI 89 (Optional/named parameters) are\nexcluded rather than implemented. SRFI 88's postfix-colon syntax\nreinterprets already-valid R7RS identifiers (breaking real, unrelated\nuses like the `(prefix lib id:)` import modifier and `:::`-style custom\nsyntax-rules ellipsis identifiers) in exchange for compatibility with\njust one of several competing, never-standardized keyword conventions\nacross the Scheme ecosystem. SRFI 89's named-parameter matching needs a\nruntime type check during macro pattern matching that plain\nsyntax-rules cannot express -- confirmed via the reference\nimplementation, which resorts to define-macro for exactly this reason;\nno mainstream syntax-rules-only Scheme has ported it faithfully either.\nSRFI 227 (Optional arguments), already implemented, covers the\noptional-positional-parameter niche instead. Full rationale for both in\ndocs/dev/srfi-exclusions.md, including why a working prototype of\nlambda*/define* as native compiler forms was reversed as disproportionate.\n\nSRFI 106 (Basic socket interface) is also excluded: raw sockets belong\nin the kaappi-net ecosystem package, which already covers this space\nwith TLS support core deliberately doesn't have.\n\n157 SRFIs now supported (12 built-in, 143 portable), up from 150.\n23 SRFIs excluded (was 20).\n\n* Address PR #1733 review: script-path lifetime, sandbox scope, vicinity gaps\n\n- resolveScriptPath: normalize \".\"/\"..\" in absolute paths too, not just\n  relative ones (regression test: script-path-normalization.sh)\n- vm.script_path: free the previous allocation in runFile, free on VM\n  deinit (root VM only), and share (never free) it with child SRFI-18\n  threads via initForThread\n- kaappi_sysinfo: stop blocking the whole library under --sandbox; rely on\n  the per-primitive sandbox flag so only %script-path opts out and the\n  other sysinfo procedures stay reachable\n- SRFI 59 program-vicinity: track vm.current_lib_dir (already maintained\n  as \"whatever file is currently loading\" for .sld/include resolution, now\n  also for `load`) instead of the static top-level script path, so a\n  nested load reports its own directory while active\n- SRFI 59 library-vicinity/implementation-vicinity: return real\n  directories ($KAAPPI_HOME/lib, the running executable's own directory)\n  instead of \"\", which silently meant \"current directory\"\n- SRFI 59 home-vicinity: fall back to USERPROFILE on Windows when HOME is\n  unset\n- Fix osName's doc comment and CLAUDE.md's SRFI total (208 = 157 + 28 + 23,\n  not 27)\n- srfi193.scm: accept Windows path separators in the script-file/\n  script-directory assertions (was failing windows-arm-test)\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* Fix script-path-normalization.sh to not hardcode a POSIX path spelling\n\nWindows CI failed: the test asserted the raw $tmpdir (an MSYS /tmp/...\nspelling from Git Bash's mktemp) against kaappi's own output, but kaappi\nprints native paths -- a backslash-separated, write-escaped Windows path\nunder a Git-Bash-translated temp directory, per tests/scheme/CLAUDE.md's\nown \"don't bake POSIX-only spellings into assertions\" guidance. Compare\nkaappi's output for a clean path against its output for a \"../\"-laden\npath to the same file instead, so the test never needs to predict the\nexact spelling on any given host.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-23T19:13:58Z",
          "tree_id": "f5888e97a8951889b596b38ab1b5b684ef1b1cec",
          "url": "https://github.com/kaappi/kaappi/commit/cbf4dbe4d2f1115b4f390230a4733963ce125ba2"
        },
        "date": 1784836422348,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.345868,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.026928,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.892785,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.400492,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006311,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.053963,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.502997,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069366,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.574566,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.908126,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.583309,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.430315,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.809545,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.667976,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044217,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "630f16a225baccd323a93ec3a13c5c60bbba98dc",
          "message": "Address PR #1733 second-round review: Windows paths, stale sandbox docs (#1734)\n\n* Address PR #1733 second-round review: Windows paths, stale sandbox docs\n\n- extractDir (vm_library.zig): recognize '\\' as a separator on Windows\n  too, matching vicinity:suffix?'s own platform split -- a Windows\n  `(load \"dir\\file.scm\")` was reporting program-vicinity as \"\" instead\n  of \"dir\\\" while loading, since extractDir only searched for '/'\n- Fix stale sandbox documentation in lib/srfi/59.sld and primitives.zig\n  left over from the earlier fix that stopped blocking the whole\n  `(kaappi sysinfo)` library under --sandbox: SRFI 59 is still\n  unavailable under --sandbox, but because it's a non-embedded .sld\n  file (blocked wholesale), not because of kaappi_sysinfo's own gate\n- Move the nested-load program-vicinity regression out of srfi59.scm\n  into its own file (srfi59-nested-load-vicinity.scm), per this\n  project's \"name bug regressions after the bug\" convention\n\nNot applied: using shell-common.sh's native_path in\nscript-path-normalization.sh. native_path converts via `cygpath -m`\n(forward-slash mixed style), but %script-path's actual Windows output\nis backslash-separated and write-escaped -- a format native_path\nwouldn't produce, so it can't build a matching expected value. The\ntest's existing self-referential comparison (clean path vs. \"../\"-laden\npath to the same file) sidesteps needing to predict the exact spelling\nat all, and is already verified passing on both windows-arm-test and\nwindows-x64-test in CI.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* Fix inconsistent procedure count in 59.sld sandbox comment\n\nSaid \"three of its four procedures\" but (kaappi sysinfo) has seven\nprimitives now (3 reachable + 4 sandbox-excluded), not four. Describe\nthe three by what they are instead of by a count.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-24T02:31:13+05:30",
          "tree_id": "99a948767e165370e2d430929da3a509f46cc33c",
          "url": "https://github.com/kaappi/kaappi/commit/630f16a225baccd323a93ec3a13c5c60bbba98dc"
        },
        "date": 1784842858325,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.983317,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.518741,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.912027,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.367203,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006567,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.052552,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.501848,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.067693,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.320823,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.944663,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.51852,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.470933,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.739299,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.765631,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043996,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "45cafd216e4b978bc35d53bdae61435b032930c5",
          "message": "Add SRFI 120, exclude 21 and 230 (SRFI Phase 4 slice 2) (#1735)\n\n* Add SRFI 120, exclude 21 and 230 (SRFI Phase 4 slice 2, closes #1702)\n\nSRFI 120 (Timer APIs) ships as a portable library with zero engine\nchanges: each make-timer spawns a dedicated SRFI-18 thread coordinated\nthrough a (kaappi fibers) control channel, with all mutating calls\n(schedule/reschedule/remove/exists) implemented as synchronous\nrequest/reply over fresh one-shot reply channels.\n\nSRFI 21 (real-time multithreading) and SRFI 230 (atomic operations) are\nexcluded: both need architecture Kaappi's SRFI-18 doesn't have (a\nuserspace-scheduled thread model with enforced priority inheritance, and\nshared mutable memory across threads' otherwise-independent heaps,\nrespectively). See docs/dev/srfi-exclusions.md for the full rationale.\n\nAlso discovered and documented (but did not fix, as out of scope for a\nportable-library change): calling SRFI 120's procedures on one timer from\nmore than one thread produces nondeterministic memory corruption, even\nthough a bare two-thread channel round trip with none of this library's\nother machinery does not reproduce it in isolation. The library's own\nheader comment and test suite treat single-calling-thread as a hard\nrequirement until that engine-level issue is investigated separately.\n\n158 SRFIs implemented, 25 tracked, 25 excluded (208 total).\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* Address PR #1735 review: spec-conformance fixes for SRFI 120\n\nThree genuine spec-conformance bugs found by review, all verified\nagainst the actual SRFI 120 spec text before fixing:\n\n- make-timer-delta only accepted full-word units (hours, seconds, ...);\n  the spec's required baseline vocabulary is the abbreviated symbols\n  (h/m/s/ms/us/ns). Both are now accepted.\n- timer-cancel! never re-raised a task's preserved error. The spec is\n  explicit: \"the procedure raises the preserved error if there is\" --\n  timer-cancel! is now synchronous (like the other operations) and\n  raises whatever condition caused the timer to stop, including a\n  re-raising error-handler's own condition.\n- A negative timer-delta (e.g. (make-timer-delta -1 's)) silently\n  produced a negative fire-at instead of being rejected, unlike the\n  plain-integer branch which already enforced non-negativity.\n\nAlso fixed: the SRFI 21/230 exclusion doc claimed both \"extend SRFI 18\",\nbut SRFI 230 is a standalone interface that merely notes an SRFI-18-based\nimplementation is possible.\n\nDocumented (not fixed, out of scope): the spec requires a task to be able\nto cancel/reschedule other tasks on the same timer, which this\nimplementation cannot do (thunks run synchronously inside the timer's own\nmessage loop, so a reentrant call from within a thunk deadlocks). A real\nfix needs either reentrant reply-channel semantics or per-task threads,\nand the latter would hit the same cross-thread channel bug already\nflagged as out of scope in the original PR.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* Fix timer-cancel! sentinel to survive the cross-thread channel hop\n\n%no-error-sentinel was a freshly-consed list sent from the timer thread\nto the caller over a channel. channel-send/receive deep-copies non-symbol\nheap values across threads' independent GC heaps, so the copy arriving\nin the calling thread was `equal?` but never `eq?` to the sender's own\nbinding -- timer-cancel! always mistook its own sentinel for a real\npreserved condition and raised it. Switched to a bare symbol, which\nsurvives the hop intact because Kaappi interns symbols through a table\nshared across every thread's heap (the same reason the 'schedule/'stop/\netc. message tags elsewhere in this file already work via `case`).\n\nAlso closes the edge case CodeRabbit flagged: a task that (raise #f)s\nwith no handler is now correctly re-raised by timer-cancel! instead of\nbeing confused with \"nothing was preserved\" (both previously looked\nlike plain #f).\n\n* Address PR #1735 third-round review: tagged stop-reply, id-return, doc fixes\n\nConfirmed and fixed against the SRFI 120 spec text and this codebase's\nactual behavior:\n\n- Replace the %no-error-sentinel value comparison with a tagged reply\n  pair, ('ok . #f) or ('error . condition), for the (stop) message. A\n  bare sentinel -- symbol or not -- compared by eq?/eqv? can never fully\n  rule out collision with a task's own raised condition (R7RS `raise`\n  accepts any object); tagging the pair makes the distinction structural\n  instead of relying on an unlikely value. Added a regression test that\n  raises the exact symbol the old sentinel used, proving the collision\n  this design point closes.\n- timer-reschedule! now returns the task id on success, matching \"the\n  procedure returns given id\" (it previously returned #t).\n- make-timer-delta now rejects non-integer n, matching \"n must be an\n  integer\".\n- Import (srfi 1) explicitly for filter rather than relying on it being\n  incidentally visible without a declared dependency.\n- Fixed a stale doc comment claiming preserved task errors have no\n  retrievable accessor -- timer-cancel! has re-raised them since the\n  previous commit.\n- Documented (as a known limitation, not fixed) that a task thunk running\n  longer than %reply-timeout-seconds makes concurrent requests see false\n  \"not responding\"/timeout answers, since %timer-loop services `control`\n  only between thunks; SRFI 120 tasks are meant to be short callbacks, so\n  a full liveness-aware reply protocol is left as a documented gap.\n- Tightened three tests that either ignored a channel-receive's result\n  (so a timer that silently never fired could still pass) or used a\n  fixed thread-sleep! to wait for a background task to run (replaced with\n  a channel signal sent immediately before the task raises).\n\nVerified two other CodeRabbit claims from this same round against actual\nKaappi behavior and declined them: `exit` and `filter` are both reachable\nfrom bare (scheme base) in top-level script execution regardless of\ndeclared imports (confirmed empirically and via precedent -- 43 existing\nsrfi test files already call exit without importing (scheme\nprocess-context), and lib/srfi/216.sld already imports (srfi 18)\nunconditionally the same way this library does), so adding cond-expand\nguards or a (scheme process-context) import would be unrequested churn\naddressing no observable bug.\n\n---------\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-24T10:02:45+05:30",
          "tree_id": "2bfadb4f6b121938a53c05e54a05bf1f5eb4e7b4",
          "url": "https://github.com/kaappi/kaappi/commit/45cafd216e4b978bc35d53bdae61435b032930c5"
        },
        "date": 1784869894278,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.356468,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.381419,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.90511,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.412713,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006319,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.054181,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.515244,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.071238,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.523627,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.89808,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.594672,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.436413,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.808304,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.663322,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045023,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "b0b4029997a65f24a40c5f542bef218de71512cb",
          "message": "Add SRFI 57/237/240/137/136/131, exclude 99/100/150 (SRFI Phase 4 slice 3, closes #1695) (#1736)\n\n* Add SRFI 237/240/137/136/131, exclude 99/100/150 (SRFI Phase 4 slice 3)\n\nCloses 8 of #1695's 9 SRFIs (57 remains open, tracked separately).\n\nSRFI 237 (R6RS Records, refined) is the one record-system SRFI needing\nreal engine changes, since a portable macro cannot synthesize the\nidentifiers R6RS's auto-naming record syntax requires: RecordType\n(types.zig) gained parent/own_field_names/own_field_mutable/uid/sealed/\nis_opaque fields (parent is the only new heap pointer, traced in all\nthree gc_collect.zig mark-graph switches; RecordType is fully immutable\nafter construction, so none of this needs a write barrier), and\nvm_records.zig's define-record-type desugarer gained a parallel R6RS-\nclause-syntax path dispatching alongside the original R7RS one.\nInheritance/protocol composition (including R6RS's own two-protocol\nworked example) uses a \"materialize the parent instance via its own\nconstructor, then re-extract its fields\" strategy instead of R6RS's own\nCPS n/p threading -- behaviorally identical, but needs no per-level\nspecial-casing regardless of protocol mixing at any depth. SRFI 240\n(Reconciled Records) is a thin syntactic-reconciliation layer over 237,\nexactly as its spec describes.\n\nGetting SRFI 136/131 (and any future SRFI reusing the name\ndefine-record-type) to work at all needed one more fix: Kaappi hardcoded\ndefine-record-type as a non-overridable special form in\nhandleTopLevelForm, checked before any macro table -- so no portable\nlibrary could ever give that name new meaning via define-syntax, even\nthough compiler.zig's compileForm already prioritized macros over\nspecial forms for every non-top-level use (its own comment cites SRFI\n219 redefining `define` as existing precedent for exactly this\nprinciple). handleTopLevelForm/isSpecialTopLevelForm now check for a\nuser macro literally named define-record-type first. This closes the\ngap only for top-level use; library-body use of a shadowing\ndefine-record-type is a documented, un-closed gap, same limitation as\nthe R6RS-clause syntax itself.\n\nSRFI 137 (Minimal Unique Types), 136 (Extensible record types, with its\nsignature CPS-style introspection macro), and 131 (ERR5RS Record Syntax\nreduced, with by-name rather than positional constructor field\nresolution) are pure portable Scheme built on (srfi 237)'s procedural\nlayer. SRFI 99, 100, and 150 are excluded: 99 and 100 both need\nidentifier synthesis from string concatenation at macro-expansion time\n(the same fundamental syntax-rules limitation as already-excluded SRFIs\n89/206/212); 150 needs SRFI 147/148's custom-macro-transformer support,\nwhich SRFI 147's own spec text says isn't portably implementable either.\n\nAlso documents a narrow, un-root-caused compiler quirk found while\nbuilding 136/131: calling one %-prefixed forward-referenced global as a\ndirect argument expression to another, inside a closure passed to map,\nraised a spurious \"undefined variable\" for the inner call -- reliably\nfixed by routing through an extra wrapper function, but worth a\ndedicated investigation later.\n\n* Add SRFI 57 (Records), fully closing issue #1695\n\nRecords with inheritance via \"schemes\" -- a named, reusable field-label\nlist that a type or another scheme can extend, with multiple schemes\nmergeable at once (left-to-right append + delete-duplicates), plus\nrecord-update/record-update!/record-compose for functional update,\nin-place update, and cross-type field composition.\n\nDeliberately does not port the spec's own reference implementation\ntechnique (macro-expansion-time identifier comparison via let-syntax):\na previously-undiscovered expander bug makes any let-syntax upstream of\na define-syntax in the same expansion chain fail to compile. Sidesteps\nit by doing all field-list merging/dedup/lookup on ordinary quoted\nsymbols at run time instead -- simpler than the reference design, not\njust a workaround, and needs no engine changes.\n\nThis closes SRFI Phase 4 issue #1695 in full (57/131/136/137/237/240\nshipped, 99/100/150 excluded).\n\n* Address CodeRabbit review: fix real bugs, document remaining gaps\n\nTwo genuine SRFI 57 spec violations, found by re-verifying against the\nactual spec text rather than trusting the earlier implementation:\n\n- record-compose had import precedence backwards (last import was\n  winning collisions; the spec's \"left to right, dropping any repeated\n  fields\" means the first import should win, matching delete-duplicates\n  semantics used elsewhere in this same spec).\n- define-record-type's field accessors/mutators were polymorphic\n  (resolving via the instance's own actual rtd) when the spec requires\n  them to be monomorphic (\"It is an error to pass an accessor a value\n  not of type <type name>\"); only scheme accessors are meant to be\n  polymorphic.\n\nAlso added: define-record-scheme/define-record-type's \"type-clause\nonly\" shorthand forms, runtime conformance/label-membership checks for\nrecord-update and record-update! (call-time, not expansion-time, since\ntarget is an ordinary value in this design -- documented), and an\nexplicit (srfi 237 primitives) import.\n\nOn the SRFI 237 engine side (used by 131/136/137/57 too): reject a\nsealed parent type per R6RS (both the define-record-type desugarer and\n%make-record-type-descriptor), check nongenerative-uid reuse for actual\nequivalence rather than reusing unconditionally, reject field counts\nthat would overflow the u8 field-count representation instead of\nletting @intCast panic, and make cross-thread deep-copy of a\nnongenerative record type reuse the destination VM's own registration\ninstead of minting a second, non-interoperable type with the same uid.\n\nLeft as documented, not fixed: SRFI 57's labeled record expressions\n(`(type-name (label expr)...)`) would need every scheme/type name to be\na macro rather than an ordinary value, conflicting with this library's\ncore design choice (see lib/srfi/57.sld's header); record_uid_registry\nhas the same lock-free cross-thread staleness tradeoff already accepted\nfor the pre-existing `macros` map, not a new regression.\n\nAlso fixes two documentation issues: a typo/garbled sentence in\nCLAUDE.md's SRFI 137 paragraph, and two self-contradicting statements\nin docs/dev/srfi-exclusions.md (an overgeneralized Gauche comparison,\nand a scope note that claimed SRFI 131 covers shorthands its own\n\"why excluded\" section says it drops).\n\n* Address second CodeRabbit pass: critical GC bug, nominal conformance\n\nCritical: fixed a permanent-GC-disable bug in vm_records.zig. Several\nblocks used `no_collect += 1; errdefer no_collect -= 1;` followed by a\nmanual mid-block `no_collect -= 1` and then MORE fallible operations\n(compileAndRunDefine) still inside the errdefer's scope. If any of those\nlater operations failed, the errdefer fired on top of the already-applied\nmanual decrement, underflowing the u32 counter and permanently disabling\nGC for the rest of the process. Fixed by replacing the errdefer + manual\ndecrement pair with a single unconditional `defer`, matching the pattern\ngc_deep_copy.zig already uses correctly. Applied to all 8 occurrences of\nthis shape in the file, including 4 pre-existing ones in the R7RS\nhandleDefineRecordType path (same file, same bug, latent before this PR).\n\nSRFI 57: replaced structural scheme conformance (\"has the right field\nnames\") with nominal conformance (\"was actually declared to extend this\nscheme\"), per the spec's own semantics. A record instance only carries a\npointer to its raw rtd, which has no room for this library's own scheme\nmetadata, so conformance now looks up a type's declared ancestry from a\nnew side table (%srfi57-registry, populated once per define-record-type)\nrather than checking field-name overlap. This closes a real gap: a\nsame-shaped but unrelated type used to pass every scheme predicate,\naccessor, and record-update/record-compose target check. Also added:\nrecord-compose now validates that each import actually conforms to its\ndeclared type/scheme, and that every explicit override label is a real\nfield of the export type (previously an import's raw field overlap was\nenough, and export labels went unchecked into %make-record positionally).\n\nAlso fixes two narrower gaps found in the same pass: cross-thread\ndeep-copy of a nongenerative record type was registering the copy in the\ndestination VM using the SOURCE's uid string as the hash key (a\ndangling-pointer risk once the source heap is freed) -- now keys by the\ncopy's own, destination-owned uid string. And the R6RS\ndefine-record-type desugarer's nongenerative-uid reuse had the same\nmissing equivalence check already fixed on the %make-record-type-descriptor\nprimitive in the previous commit -- factored fieldsEquivalent out as a\nshared, exported helper and applied it here too.\n\nTwo pre-existing test bugs surfaced by the nominal-conformance fix (both\nrelied on structural coincidence rather than declared conformance) are\ncorrected: `person` and `cp` in the test suite now actually declare the\nschemes their own tests assume they conform to.\n\n* Update CLAUDE.md's SRFI 57 writeup to reflect nominal conformance + no_collect fix\n\n* Fix SRFI 237 record-name binding and add generative clause support\n\nTwo more real gaps found by CodeRabbit's third pass, both in the R6RS\ndefine-record-type desugarer this PR added:\n\n- The declared record name itself (e.g. `point`) was never bound to\n  anything -- only a hidden, redefinition-stable internal alias\n  (`__record_type_point`) was. SRFI 237's own spec is explicit: \"As an\n  expression, this keyword evaluates to the underlying record\n  descriptor.\" Fixed by binding the declared name to the same rtd value,\n  alongside (not instead of) the internal alias, which inheritance/\n  self-reference still needs.\n\n- SRFI 237 adds a `(generative)` clause to R6RS's clause set, mutually\n  exclusive with `(nongenerative ...)`. It wasn't recognized at all, so\n  a spec-valid declaration fell through to the R7RS parser and failed.\n  Added as a clause keyword; parses as a no-op (a record type is already\n  generative by default) and is rejected in combination with\n  `nongenerative`.\n\nBoth verified against the actual SRFI 237 spec text before fixing.\nRegression tests added to tests/scheme/srfi/srfi237.scm; the\ngenerative+nongenerative rejection is verified via a standalone script\ninstead (a malformed top-level define-record-type is a compile error\nthat aborts the whole file, not a catchable exception a SRFI-64 suite\ncan assert against in-process).",
          "timestamp": "2026-07-24T21:25:23+05:30",
          "tree_id": "5d3586c48e5a89633f33fd3f0e39d0cc4ef5123d",
          "url": "https://github.com/kaappi/kaappi/commit/b0b4029997a65f24a40c5f542bef218de71512cb"
        },
        "date": 1784910978295,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.00241,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.853093,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.912306,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.394613,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006598,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.052864,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.508733,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068203,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.290659,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.958571,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.513155,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.47536,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.698233,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.726246,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045236,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "996051e0974bc1d7f442edfbc7587fcf48a19855",
          "message": "Add SRFI 160/66/74, fix SRFI 4 f32 precision (#1694 vector family) (#1737)\n\n* Add SRFI 160/66/74, fix SRFI 4 f32 precision (#1694 vector family)\n\nAdds a native NumericVector heap type (11 element kinds, u8 stays a\nbytevector alias) backing SRFI 160's homogeneous numeric vector\nlibraries, with the full SRFI-133-shaped extended surface implemented\nonce generically in portable Scheme over six minimal Zig primitives.\nSRFI 4 becomes a thin re-export over this substrate, which also fixes\na real bug in the old wrapped-vector implementation: f32vector never\nactually truncated to 32-bit precision. SRFI 66 (octet vectors) and\nSRFI 74 (binary blobs) are pure-portable additions over bytevectors,\nneeding only one new primitive (%host-big-endian?) so `(endianness\nnative)` is correct on kaappi's own big-endian CI targets.\n\nIssue #1694's array family (SRFI 25/47/58/63/164/179/231) remains open\nand tracked separately: three mutually incompatible API lineages plus\na reader-syntax SRFI, out of scope for one slice.\n\n* Fix CodeRabbit review findings: length overflow, complex sign printing\n\n- %make-numeric-vector: reject a length whose element count would\n  overflow usize before narrowing (unreachable on 64-bit targets given\n  the fixnum range, but a real panic-instead-of-catchable-error gap on\n  wasm32); same defense-in-depth check in allocNumericVectorFill,\n  mirroring allocVectorFill's existing pattern.\n- printer.zig: c64/c128 numeric-vector elements printed a doubled sign\n  for +inf/-inf/+nan imaginary parts (formatFlonum already includes its\n  own sign for these) and lost the sign of a -0.0 imaginary part (`<`\n  is false for negative zero). Factored the already-correct handling\n  from the standalone Complex printer arm into a shared helper.\n- srfi160.scm: strengthened three tests that couldn't actually catch a\n  wrong-direction fold-right/unfold-right/unfold! (commutative combiner,\n  index-only unfold callback) into order-sensitive ones.\n\nNot changed, with reasoning: CodeRabbit's suggestion to relocate the\nSRFI documentation additions out of CLAUDE.md/CONFORMANCE.md contradicts\nthis repo's own established convention (every prior SRFI-adding PR\ndocuments there; kaappi.github.io is end-user docs only per root\nCLAUDE.md). Its file-size-split suggestion for types.zig/memory.zig\nflags a pre-existing condition unrelated to this PR — both files were\nalready ~150-300 lines over the 1500 cap before this change, accumulated\nacross many prior SRFIs; splitting them is a large, separate refactor\ndisproportionate to one SRFI PR's scope.",
          "timestamp": "2026-07-25T01:26:04+05:30",
          "tree_id": "4b417a6073039a761e9dd2ed9a396a01dc1041d4",
          "url": "https://github.com/kaappi/kaappi/commit/996051e0974bc1d7f442edfbc7587fcf48a19855"
        },
        "date": 1784925284748,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.278905,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.140903,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.887334,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.400751,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006369,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.053304,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.497015,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068984,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.471225,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.951958,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.572697,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.43482,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.805104,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.596886,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043397,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "a814ffde3d3bd500ed3faaf546499fc4d1ef780c",
          "message": "Add SRFI 25, multi-dimensional array primitives (#1694 array family) (#1739)\n\n* Add SRFI 25, multi-dimensional array primitives (#1694 array family)\n\nPure portable Scheme (lib/srfi/25.sld) -- arrays are spec-defined as\nheterogeneous with no relationship to SRFI 4/160's numeric vectors, so\na define-record-type wrapping a plain vector is spec-sufficient. One\nrecord covers both simple (row-major backing vector) and share-array\n(affine view: base array + index-translation mapper) arrays; views\nrecurse into the base array's own ref/set! rather than its raw vector,\nso nested views compose correctly for both reads and writes.\n\nConfirms and corrects the \"three mutually incompatible lineages\"\nframing in issue #1694: SRFI 164 is actually a compatible extension of\n25 (identical shape representation), not a separate lineage, making it\na comparatively cheap follow-on. SRFI 47/63 (63 supersedes 47) is the\nreal incompatible lineage (array-set!'s value-last vs. value-second\nargument order is a silent-data-corruption-class conflict). SRFI 231\n(supersedes 179) is a third, much larger, unrelated redesign (118\nbindings). SRFI 58's reader syntax is written specifically against\n47/63's naming. All four remain open, tracked separately.\n\n* Fix CodeRabbit review findings: shape aliasing, arity/index validation\n\n- lib/srfi/25.sld: make-array/array/share-array now deep-copy the\n  caller's shape vector before storing it in the array record. Per\n  spec, \"an array does not retain a dependence to the shape array\" --\n  without the copy, a caller mutating their own shape object (shape\n  returns an ordinary, caller-visible mutable vector of pairs) could\n  retroactively corrupt an already-constructed array's bounds while\n  its backing store keeps the size computed at construction time.\n- make-array now rejects more than one fill-value argument instead of\n  silently discarding all but the first.\n- The packed-index-array form of array-ref/array-set! now requires the\n  index array to be 0-based, per spec (\"a 0-based 1-dimensional\n  array\"), instead of silently accepting any lower bound.\n- srfi25.scm: added regression tests for all three fixes, and wrapped\n  the share-array fixtures in let/let* instead of top-level defines\n  for cleaner test isolation.\n- CLAUDE.md: a line starting with \"#1694\" was being parsed as an ATX\n  heading attempt by markdown linters; reworded so it doesn't start\n  the line.",
          "timestamp": "2026-07-25T08:11:07+05:30",
          "tree_id": "bbb6102013228c9dce445b78550a4e63981ea2ab",
          "url": "https://github.com/kaappi/kaappi/commit/a814ffde3d3bd500ed3faaf546499fc4d1ef780c"
        },
        "date": 1784949459090,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.281301,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.002534,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.928057,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.407502,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006624,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.053803,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.510388,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069983,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.598937,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.927427,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.587934,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.44324,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.836557,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.697104,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044821,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "154e3506fe80900cca1cf915e0937f7d35392806",
          "message": "Add SRFI 164, enhanced multi-dimensional arrays (#1694 array family) (#1740)\n\n* Add SRFI 164, enhanced multi-dimensional arrays (#1694 array family)\n\nPure portable Scheme (lib/srfi/164.sld), no engine work. A documented,\ncompatible extension of SRFI 25 -- identical shape representation,\nshare-array copied verbatim -- so implemented as its own independent\nlibrary (record accessors don't cross library boundaries, and this\nSRFI's array needs a third mode SRFI 25's record has no room for).\n\nOne record covers three modes: simple (own row-major vector, as in\n25), shared/view (base array + index-translation mapper, same\nrecursive-delegation design as 25's share-array -- backs share-array,\narray-transform, array-reshape, and array-index-share), and virtual\n(a getter/optional-setter pair with no backing storage at all --\nbacks build-array, index-array, and array-index-ref's non-scalar\ncase).\n\narray-transform's transform uses a different calling convention than\nshare-array's mapper per the spec's own explicit contrast (one vector\nin/out vs. separate variadic arguments/multiple values) -- adapted\nwith a one-line wrapper, which works for a non-affine transform\nsince the shared/view mode never checked or exploited affineness.\narray-index-ref/array-index-share (APL-style generalized indexing)\nshare one resolver. array-reshape aliases the source's backing\nvector when simple, per spec, and recomputes via row-major rank\notherwise. array->vector is a live view only for simple arrays --\ndocumented as a deliberate scope reduction, since a non-simple live\nview isn't achievable with a literal R7RS vector in portable Scheme.\n\nTwo self-caught bugs during implementation, both instructive: a\ndeeply-nested first draft of the index-resolver mis-balanced its own\nclosing parens (kaappi check catches this immediately -- worth\nrunning on any new portable library before executing it), and once\nthat was fixed by flattening into named top-level helpers, the\nresolver closure took a rest parameter but every call site passed an\nalready-built list as one argument, silently double-wrapping it and\nproducing \"index out of range\" errors far from the real mistake.\n\n* Fix CodeRabbit review findings: shape-specifier coercion, build-array contract\n\n- Every shape-taking procedure (make-array, array, share-array,\n  build-array, index-array, array-transform, array-reshape) now\n  coerces its shape argument through ->shape before use, per spec:\n  \"the procedures in this specification that require a shape can\n  accept a shape-specifier, as if converted by the procedure\n  ->shape\". Previously only ->shape itself did this conversion, so\n  passing a raw specifier (e.g. #(2 4)) directly to make-array -- the\n  spec's own worked example -- raised a car/cdr type error instead of\n  working. ->shape's own output is already a fresh, non-aliased\n  vector, so this also satisfies the \"does not retain a dependence on\n  the shape argument\" rule without a separate copy.\n- ->shape now validates lo <= hi and exactness for both bound forms,\n  matching the validation `shape` already had.\n- build-array's getter/setter now match the spec's actual contract\n  (getter takes one index-vector argument; setter takes an\n  index-vector then the value) via a boundary adapter, instead of\n  the library's internal variadic-indices/value-first convention\n  that had leaked into the public API. Updated array-index-ref's own\n  use of build-array to match.\n- Documented, rather than implemented, the spec's \"should\" (not\n  \"must\") recommendation that array? also be true of plain R7RS\n  vectors (gvectors) -- doing so would need a parallel plain-vector\n  code path through every array-* procedure, a much larger change\n  than this PR's scope.\n- Added regression tests for the ->shape-coercion fix (one per\n  affected procedure), ->shape's bound validation, and packed-index\n  argument handling (vector and rank-1 array forms, plus their three\n  rejection cases) that had no coverage at all.\n\nFull regression suite (1974 tests) and unit tests still green. One\ncompile-import-error-703.sh flake on an initial run (same flake seen\non PR #1739, unrelated subsystem) reproduced as passing standalone\nand on a clean full rerun.",
          "timestamp": "2026-07-25T04:49:39Z",
          "tree_id": "9bed326883f68ba3f2344e530050f6a9962b4e93",
          "url": "https://github.com/kaappi/kaappi/commit/154e3506fe80900cca1cf915e0937f7d35392806"
        },
        "date": 1784957328748,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.27196,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.50592,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.899828,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.488024,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006377,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.053372,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.499704,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069381,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.53747,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.928412,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.572571,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.440707,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.801707,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.646194,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.046121,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "a44274124dd36c9c4d15c1c86f4dd16d7ca6cefd",
          "message": "Add SRFI 63, homogeneous and heterogeneous arrays (#1694 array family) (#1747)\n\n* Add SRFI 63, homogeneous and heterogeneous arrays (#1694 array family); exclude 47\n\nSRFI 63 supersedes SRFI 47 outright (its own page says so), implementing\nall 9 of 47's procedures plus 4 new ones (list->array, array->list,\nvector->array, array->vector) and 20 prototype-generator procedures (vs.\n47's 13). Confirmed incompatible with SRFI 25/164, already shipped\nearlier in this array family: array-set!'s value argument is second here\n(not last), make-array takes a type/fill prototype (not a bounds-shape\nobject), and every dimension is a plain zero-based size.\n\nOne <uarray> record covers simple arrays (kind-dispatched to the\nalready-shipped (srfi 160 <tag>) procedures for 12 of the 20 element\nkinds, falling back to a plain vector for the rest) and shared views\n(recursive delegation into the base array's own ref/set!, matching the\npattern from SRFI 25/164). list->array/array->list use a rank-nested\nlist structure while vector->array/array->vector use a flat vector plus\nexplicit dimensions -- confirmed via the spec's own examples rather than\nassumed, since the two pairs looked parallel but aren't.\n\nSRFI 47 moves to docs/dev/srfi-exclusions.md as permanently superseded.\n170 SRFIs now supported (169 -> 170); 9 tracked for future work (231,\nand issue #1699's 7 macro/syntax SRFIs); 29 excluded.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* Fix CodeRabbit findings: vectors/strings as arrays, prototype fill, bounds\n\nConfirmed against the primary SRFI 63 spec text before fixing:\n\n- array? must not be disjoint from vector/string (\"Arrays are not\n  disjoint from other Scheme types\" -- vectors/strings are rank-1\n  arrays in their own right). array-rank, array-dimensions,\n  array-in-bounds?, array-ref, and array-set! now dispatch across\n  <uarray> records, plain vectors, and plain strings via new\n  %array-like-* helpers; make-shared-array can now take any of the\n  three as its base too.\n- make-array now propagates a non-empty prototype's own origin element\n  as the fill value (\"the new array is filled with the element at the\n  origin of prototype\"), instead of always using the kind's zero-ish\n  default. The prototype-generator procedures (A:fixZ8b etc.) needed a\n  matching fix: they were building a zero-length store regardless of\n  whether a fill argument was given, so the value could never actually\n  be read back.\n- Shared-view array-ref/array-set! now validate indices against the\n  view's own declared dimensions before delegating through the mapper,\n  matching array-in-bounds? -- previously a mapper that didn't itself\n  bounds-check could make an out-of-range view index silently return\n  an in-bounds base element.\n- list->array now rejects a negative or non-integer rank up front\n  instead of recursing until stack exhaustion.\n\nequal?'s array-comparison branch stays scoped to genuine <uarray>\nrecords (documented as a deliberate reduction) since plain R7RS\nequal? already handles vector/string comparison correctly.\n\n31 new SRFI-64 assertions (65 -> 96) covering all of the above plus\nregression coverage for everything from the initial implementation.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-25T17:09:23+05:30",
          "tree_id": "4ad0d1013230d7e307d9626a8d93f74824a38392",
          "url": "https://github.com/kaappi/kaappi/commit/a44274124dd36c9c4d15c1c86f4dd16d7ca6cefd"
        },
        "date": 1784981948818,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 2.870186,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.749183,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.612456,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.02771,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.005722,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.03948,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.35109,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.05097,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.926134,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.338458,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.153176,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.381723,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.313163,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.874535,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.034764,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "8f513eaf073cbeca137cd3e23002ff2975153483",
          "message": "Add SRFI 231 intervals + misc helpers (#1694 array family, phase 1a) (#1749)\n\n* Add SRFI 231 intervals + misc helpers (#1694 array family, phase 1a)\n\nFirst of several slices implementing SRFI 231 (\"Intervals and Generalized\nArrays\") -- the last remaining piece of #1694's array family. At 118\nbindings (101 procedures/parameters + 17 storage-class singletons), this\nSRFI is roughly 5-10x larger than any prior slice and structurally\nunrelated to SRFI 25/164/63 already shipped: intervals are a genuinely new\nopaque type (two parallel vectors of exact-integer lower/upper bounds,\narbitrary sign) rather than a shape-object or plain-size model.\n\nThis slice covers only the interval layer plus the misc permutation/\ntranslation helpers -- fully self-contained, zero dependency on arrays or\nstorage classes, and independently testable. New internal sub-libraries\n(no bare (srfi 231) yet, matching the (srfi 160 base) + per-tag precedent):\n\n- lib/srfi/231/misc.sld: translation?, permutation?, index-rotate,\n  index-first, index-last, index-swap.\n- lib/srfi/231/intervals.sld: the <interval> record and all 26 interval\n  procedures -- construction (both 1-arg and 2-arg make-interval forms),\n  accessors, interval-for-each/fold-left/fold-right (general d-dimensional\n  lexicographic traversal calling callbacks with separate positional\n  index arguments), dilate/translate/permute/scale, intersect (returns #f\n  on no overlap, not an error), cartesian-product, and projections\n  (returns two values via `values`, split via take/drop from the\n  already-built-in (srfi 1)).\n\nEvery calling convention and error condition was confirmed against the\nprimary spec text and reference implementation before writing any code,\nincluding two procedures (translation?/permutation?) whose exact\nvalidation rule the spec states only in prose, and interval-fold-right's\n\"all f evaluations before any operator application\" requirement (a naive\nreverse-order fold interleaving f and operator would violate this even\nthough it looks equivalent for pure f).\n\nRemaining phases (storage classes, core array type, views/sharing,\ncombinators, multi-array assembly) are tracked as follow-up slices under\n#1694; (srfi 231) itself is not yet importable.\n\nAlso files #1748: tests/scheme/compile/compile-import-error-703.sh has now\nflaked 3 times in full run-all.sh runs across recent slices (never\nstandalone) with a concrete root-cause theory -- unrelated to this PR's\ndiff, passed both standalone and on a clean full rerun here.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* Fix CodeRabbit findings: reject malformed intervals/permutations/indices\n\nConfirmed against the primary SRFI 231 spec text before fixing:\n\n- make-interval now rejects a 3rd+ argument instead of silently\n  discarding it (the spec's signature is arg1 plus one optional arg2,\n  not arbitrary trailing arguments).\n- interval-subset? now errors on mismatched dimensions instead of\n  returning #f -- confirmed the spec's own \"assumes ... the same\n  dimension d\" precondition makes this an error condition, with #f\n  reserved for same-dimension intervals that fail the bound check.\n- interval-contains-multi-index? now rejects non-exact-integer\n  multi-index entries instead of silently comparing them numerically\n  (a coordinate like 1.5 would otherwise pass the <=/< bounds checks\n  and be treated as \"contained\").\n- interval-dilate/translate/permute/scale now validate that their\n  diff/translation/permutation/scales vector length matches the\n  interval's own dimension before calling vector-map, which silently\n  stops at the shortest input on a length mismatch (R7RS, matching\n  map) rather than erroring -- a too-short or too-long vector would\n  otherwise silently produce a wrong-rank result.\n- interval-intersect now requires all argument intervals to share one\n  dimension up front, instead of only ever iterating up to the FIRST\n  interval's own axis count -- a first interval with fewer axes than a\n  later one previously never even looked at the extra axes, silently\n  returning a lower-rank \"intersection\" instead of rejecting the\n  mismatch.\n- index-rotate/index-first/index-last/index-swap now validate their\n  n/k/i/j preconditions, confirmed against the spec's own exact\n  wording for each -- including the asymmetric boundary that\n  index-rotate's k may equal n (inclusive, the identity permutation)\n  while index-first/-last/-swap's k/i/j must be strictly less than n\n  (exclusive). index-last previously produced a vector containing -1\n  and missing an element for an out-of-range k, which isn't a valid\n  permutation at all.\n\n17 new SRFI-64 assertions (62 -> 79) covering all of the above plus\nregression coverage for existing behavior.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-25T13:35:09Z",
          "tree_id": "b4afba9cabd8833e5f61648f88b7573dcc5a48dc",
          "url": "https://github.com/kaappi/kaappi/commit/8f513eaf073cbeca137cd3e23002ff2975153483"
        },
        "date": 1784988493456,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.289341,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.297525,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.887234,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.447788,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006379,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.053701,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.499688,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069209,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.527479,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.934597,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.569695,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.434235,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.800298,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.668069,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.046425,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "3a570b4bc48aceb873e7294500c924da3fb5d42c",
          "message": "Add SRFI 231 storage classes (#1694 array family, phase 1b) (#1750)\n\n* Add SRFI 231 storage classes (#1694 array family, phase 1b)\n\nSecond of several slices implementing SRFI 231 (\"Intervals and\nGeneralized Arrays\") -- see lib/srfi/231/intervals.sld (phase 1a,\nmerged) for the overall roadmap. This slice adds the storage-class\nabstraction: a 9-field record (getter, setter, checker, maker, copier,\nlength, default, data?, data->body) managing a specialized array's\nbacking store, plus all 17 required storage-class global variables.\n\nlib/srfi/231/storage-classes.sld: 14 of the 17 map directly onto this\ncodebase's existing infrastructure with zero new engine work -- 11\nnumeric kinds (s8/s16/s32/s64/u16/u32/u64/f32/f64/c64/c128) reuse the\nalready-shipped (srfi 160 <tag>) procedures, u8 reuses plain R7RS\nbytevector procedures (matching u8's bytevector-alias treatment\nthroughout this codebase), and generic/char reuse native vector/string\ndirectly via the spec's own verbatim reference definitions. The\nremaining 3 (u1, f8, f16) have no Kaappi-native representation and are\nbound to #f, matching the spec's explicit \"shall define... to #f\"\npermission for implementations lacking the underlying type -- the\nreference implementation itself does the same for f8.\n\nEvery checker predicate encodes the exact range/type rule for its kind\n(e.g. s8: exact integer in [-128,127]), confirmed against the same\nper-kind rules already established for SRFI 63's kind-dispatch table.\n\nAlso confirmed (test-writing detail worth recording): reading a\ncomplex number back from a c64/c128 NumericVector always produces a\ngenuinely complex-tagged value, even with a zero imaginary part --\nunlike make-rectangular at the Scheme level, which collapses eagerly.\nThis is a pre-existing Kaappi representation characteristic, not a bug;\nthe test suite uses numeric equality (=) rather than equal? where this\nmatters.\n\n(srfi 231) itself remains not importable -- still tracked under #1694.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* Exercise storage-class-copier in the shared test helper\n\nCodeRabbit finding: the test helper covered 8 of the 9 storage-class\nfields but never called storage-class-copier, so a wrong copy\nprocedure would have passed every existing assertion undetected. Adds\na copy-then-verify step to the shared helper, exercised across all 14\nreal storage classes (14 new assertions, 123 -> 137).\n\nDeclined a second finding (import (scheme complex) for\nmake-rectangular): verified against Kaappi's own primitives table\n(src/primitives_numeric.zig) that make-rectangular/real-part/imag-part\nare registered as members of .scheme_base directly, alongside\n.scheme_complex and .scheme_r5rs -- unlike strict R7RS, where they are\n(scheme complex)-only, this implementation already exposes them from\n(scheme base), so no import is missing.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-25T22:12:03+05:30",
          "tree_id": "ec2f912bd9bd9989c325f78e4683b8a9dba2d2ad",
          "url": "https://github.com/kaappi/kaappi/commit/3a570b4bc48aceb873e7294500c924da3fb5d42c"
        },
        "date": 1784999728009,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.28029,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.349681,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.884297,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.40641,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006354,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.053663,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.4973,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069169,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.534873,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.927574,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.588197,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.434712,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.80321,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.653315,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043899,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "c2382e14981e5829e70219468c3e95497a78325b",
          "message": "Add SRFI 231 core array object (#1694 array family, phase 2) (#1751)\n\n* Add SRFI 231 core array object (#1694 array family, phase 2)\n\nThird of several slices implementing SRFI 231 (\"Intervals and\nGeneralized Arrays\") -- see lib/srfi/231/intervals.sld (phase 1a) and\nlib/srfi/231/storage-classes.sld (phase 1b, both merged) for the\noverall roadmap. This slice adds the array type itself: a domain (an\ninterval) plus a getter, with an optional setter making it mutable,\nand an optional storage-class/body/indexer making it specialized.\n\nlib/srfi/231/arrays.sld: one <array> record covers all four\ncombinations (plain immutable, plain mutable via closures, specialized\nmutable, specialized frozen-immutable) -- specialized-only fields are\nsimply #f on a plain array. array?/mutable-array?/specialized-array?\nconfirmed as a non-strict hierarchy (specialized => array and mutable\n=> array, but specialized and mutable are orthogonal -- array-freeze!\ncan make a specialized array immutable in place, and a closure-backed\nsparse array, per the spec's own example, can be mutable without being\nspecialized at all).\n\nConfirmed two conventions that don't match either prior array SRFI in\nthis codebase exactly: array? is disjoint from vector/string (matching\n25/164, NOT 63's \"vectors are rank-1 arrays\" rule -- easy to get\nbackwards, since getting this wrong was the single biggest miss when\nimplementing 63), while array-set!'s value argument is SECOND (matching\n63, not 25/164's value-last). Getters/setters are always called with\nseparate positional index arguments, never a packed vector/list.\n\nmake-specialized-array's indexer generalizes SRFI 63's 0-based-only\nrow-major offset to arbitrary (including negative) lower bounds: shift\neach axis by its own lower bound first, then apply the standard\nrow-major stride computation using the interval's own widths.\nmake-specialized-array-from-data wraps externally supplied data (e.g.\nan existing (srfi 160 <tag>) vector) as a new array's body with zero\ncopying, confirmed via a real vector-mutation-through-the-array test.\n\nspecialized-array-default-safe?/mutable? are genuine SRFI 39\nparameters, as the spec requires (a documented difference from the\npredecessor SRFI 179, where they were plain variables).\n\n(srfi 231) itself remains not importable -- still tracked under #1694.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* Address CodeRabbit nitpicks: early-exit array-packed?, 0-dim/empty tests\n\n- array-packed? now escapes via call/cc on the first packing mismatch\n  instead of always scanning the full domain -- harmless today since\n  specialized arrays are always packed right after construction, but\n  avoids a full interval-volume traversal once a later phase's\n  view/share/reverse procedures can produce non-packed arrays.\n- Added test coverage for zero-dimensional arrays (a single element,\n  accessed via a thunk-shaped getter/array-ref with no indices, for\n  both a plain and a specialized array) and empty-domain arrays (some\n  axis has lower = upper, so no multi-index can ever be valid -- any\n  access is rejected either via the explicit domain check in safe mode\n  or the storage layer's own bounds check on the resulting zero-length\n  body in unsafe mode). 13 new assertions (50 -> 63).\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-25T18:06:40Z",
          "tree_id": "cfa34740f249b6c819ab69f05c391b00b3c1c8f8",
          "url": "https://github.com/kaappi/kaappi/commit/c2382e14981e5829e70219468c3e95497a78325b"
        },
        "date": 1785005048514,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.280716,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.363761,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.887954,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.414683,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006378,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.0535,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.499586,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069087,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.555468,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.926546,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.560132,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.44076,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.79388,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.656009,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.04408,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "fa3743b61625f481f18067c3ae02bc1412bdfe3c",
          "message": "Add SRFI 231 views, sharing, and reshaping (#1694 array family, phase 3) (#1752)\n\nFourth of several slices implementing SRFI 231 (\"Intervals and\nGeneralized Arrays\") -- see lib/srfi/231/intervals.sld for the overall\nroadmap. This slice adds the 11-procedure \"views/sharing/reshaping\"\ncluster the spec's own \"Sharing generalized arrays\" section names as a\nnatural unit: specialized-array-share (the foundational primitive),\narray-extract, array-translate, array-permute, array-reverse,\narray-curry, array-tile, array-sample, array-copy/array-copy!, and\nspecialized-array-reshape.\n\nlib/srfi/231/arrays.sld (phase 2, already merged) gets one small,\npurely additive change: %make-array/%safe-getter/%safe-setter/\n%make-lex-indexer are now exported for this and later phases' sibling\nlibrary files to build genuinely specialized arrays with custom\nindexers, the same way (srfi 160 base)'s %uvec-* helpers exist only\nfor that package's own per-tag files.\n\nlib/srfi/231/views.sld: extract/translate/permute/reverse/sample all\nshare one 3-way dispatch shape (specialized -> specialized-array-share;\nmutable-non-specialized -> make-array with getter+setter; immutable ->\nmake-array with getter only), with the output mirroring the input's\nmode exactly. array-curry and array-tile break this pattern\ndeliberately -- their OUTER array is unconditionally plain immutable/\nnon-specialized regardless of input mode (confirmed by an explicit\nspec quote for curry: \"B is always an immutable array... computed anew\nfor each call\", i.e. never cached), while their INNER\nelements/tiles follow the same 3-way mirroring as everything else.\n\narray-permute needed real care to get the index-rearrangement direction\nright (apply the permutation's inverse to the new multi-index to\nrecover old coordinates) -- verified against both of the spec's own\nworked examples, including the rank-4 one showing it's the new getter's\nown parameter *list* that gets permuted, not a runtime rearrangement.\narray-tile's last-slice truncation (when an axis width doesn't divide\nevenly by a uniform slice size) is spec-sanctioned via an explicit\nmin(), not an error -- verified against the spec's own 6x6 non-uniform\nworked example exactly, including the truncated case.\n\nspecialized-array-reshape deliberately implements a conservative\nsimplification of the reference implementation's full NumPy-derived\nmulti-group stride-matching algorithm: it succeeds zero-copy whenever\nthe source is already array-packed? (the overwhelmingly common case,\ne.g. reshaping a fresh array-copy result) via a plain row-major\nreindex, and otherwise behaves exactly as the spec allows for a failed\ndetection (error, or forced-copy-then-retry when copy-on-failure? is\n#t). This never wrongly claims an affine map exists, but is more\nconservative than the full algorithm for some non-packed-but-still-\naffinely-reshapable arrays -- verified identical to the full algorithm\non both of the spec's own worked examples (a packed reshape succeeding;\na array-sample'd non-packed reshape failing, then succeeding with\ncopy-on-failure?).\n\narray-copy and array-copy! are implemented identically (a direct fill\nloop), a deliberate, documented scope reduction versus the spec's\noptional extra call/cc-safety guarantee for array-copy specifically\n(accumulate-to-a-list-before-filling) -- getters that escape and\nre-invoke a captured continuation mid-copy are exotic enough not to\njustify the added complexity for this phase.\n\n(srfi 231) itself remains not importable -- still tracked under #1694.\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-25T19:22:24Z",
          "tree_id": "51d17351f93a3fee98ec8369f58c05734ebfaebe",
          "url": "https://github.com/kaappi/kaappi/commit/fa3743b61625f481f18067c3ae02bc1412bdfe3c"
        },
        "date": 1785009716820,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.139127,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.743474,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.652961,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.233982,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006246,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.042183,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.363283,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.054663,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.122165,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.450183,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.242532,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.409978,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.374582,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.884071,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.034042,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "04f15e672efc71b160e0a10446f5be84c0f1d938",
          "message": "Add SRFI 231 bulk combinators and conversions (#1694 array family, phase 4) (#1753)\n\n* Add SRFI 231 bulk combinators and conversions (#1694 array family, phase 4)\n\nFifth of several slices implementing SRFI 231 (\"Intervals and\nGeneralized Arrays\") -- see lib/srfi/231/intervals.sld for the overall\nroadmap. This slice adds array-map/for-each/fold-left/fold-right/\nreduce/any/every, array-outer-product/inner-product, and the 8 flat and\nnested list/vector conversion procedures (array->list, list->array,\narray->list*, list*->array, array->vector, vector->array,\narray->vector*, vector*->array) -- 17 bindings in total.\n\narray-map/for-each/fold-left/fold-right/any/every are all variadic over\narrays, requiring exact domain equality (interval=, not just matching\nshape) across every argument array. array-reduce is the one exception:\nfixed 2-arg, single array only, and hard-errors on an empty array with\nno safety-flag opt-out, using a private sentinel object rather than a\nseed value (there is no safe placeholder that couldn't collide with a\nreal element).\n\narray-fold-left calls its operator as (operator acc e0 e1 ...);\narray-fold-right calls it as (operator e0 e1 ... acc) -- accumulator\nLAST, not first. Confirmed via the spec's own formal reference\ndefinition that elements are always passed as separate positional\narguments, never packed into one list argument, and verified the\ndivergence is real (not just notational) against the spec's own\nworked examples: (array-fold-left - 0 a) and (array-fold-right - 0 a)\ngive different results for the same non-associative operator.\n\narray-inner-product's compositional definition (curry + permute + copy\n+ outer-product + map + reduce) needed care in two places the spec's\nown prose pseudocode gets subtly wrong, both confirmed only by reading\nthe reference implementation directly: it omits the required second\nargument to array-curry on its second call, and its stated\npreconditions don't mention that the shared axis's width must be\nnonzero (needed because the inner reduction would otherwise call\narray-reduce on an empty array).\n\nlist*->array/array->list*/vector*->array/array->vector* infer or\nproduce a per-dimension shape from nested-list/vector structure\n(recursion depth = target dimension, sibling lengths at each level\nmust match -- a ragged structure is rejected). The empty-collection\nedge cases are genuinely undomesticable by intuition alone and were\nverified by hand-tracing all four of the spec's own worked examples\nagainst the actual algorithm: (list*->array 0 '()) yields a RANK-0,\nvolume-1 array whose single element IS the empty list, while\n(list*->array 1 '()) yields a genuinely EMPTY rank-1 array -- these\nlook superficially similar but are entirely different shapes.\nvector*->array/array->vector* delegate to the list* versions via a\nstructure-preserving nested-vector<->nested-list conversion rather\nthan duplicating the whole shape-inference algorithm in vector form.\n\n(srfi 231) itself remains not importable -- still tracked under #1694.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* Validate vector*->array's nested-vector shape; drop dead helper\n\nCodeRabbit finding: %nested-vector->nested-list (which vector*->array\ndelegates to) had no vector?/depth check before calling vector->list,\nunlike the list path (%check-nested-list validates via list? at every\nrecursion level and raises a domain-specific \"not the right shape\"\nerror). A malformed nested vector would instead crash with a raw\nvector->list type error. Fixed by validating vector? at each recursion\nlevel before delegating, matching the list path's error message and\nirritants -- rectangularity itself is still validated for free once\n%check-nested-list runs on the converted result.\n\nAlso removed %vector-every, defined but never called anywhere in this\nfile (a leftover from the same helper pattern used in sibling files\nwhere it IS needed).\n\n1 new regression assertion (55 -> 56).\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-26T06:25:43+05:30",
          "tree_id": "a945ea0e6cf5da2ec5246e63003206fac4083d70",
          "url": "https://github.com/kaappi/kaappi/commit/04f15e672efc71b160e0a10446f5be84c0f1d938"
        },
        "date": 1785029658317,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.345456,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.094976,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.91286,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.460183,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006373,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.054464,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.505166,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.072741,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.530366,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.961158,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.590876,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.438201,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.833703,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.682412,
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
          "id": "34e15133a27c823053078175621ebb3505263913",
          "message": "Add SRFI 231 multi-array assembly (#1694 array family, phase 5) (#1754)\n\n* Add SRFI 231 multi-array assembly (#1694 array family, phase 5)\n\nFinal content phase of SRFI 231: array-assign!, array-stack(!),\narray-decurry(!), array-append(!), array-block(!) (9 bindings). All\nfour stack/decurry/append/block constructors follow the established\nvirtual-array-then-array-copy pattern; their `!` twins are aliases,\nconfirmed safe by reading the reference implementation directly (the\ntwo only diverge under multi-shot continuation re-entry, which the\nspec itself declares undefined). array-block needed a two-pass design:\nfull per-axis width-consistency validation (reusing array-curry +\narray-permute + index-first) followed by cheap single-pencil probing\nfor offsets, both confirmed against the reference implementation.\n\nOnly the merge into a public lib/srfi/231.sld plus docs/SRFI-count\nbookkeeping remains for the whole SRFI (#1694).\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* Strengthen array-block test coverage with position-dependent blocks\n\nCodeRabbit review of #1754: every test block was a uniform constant\nalready sitting at a zero lower bound, so the local-index/block-lower\nremap in array-block's assembled getter (assembly.sld:259) could be\nmissing, sign-flipped, or otherwise wrong and every assertion would\nstill pass -- any index inside a constant, zero-based block returns\nthe same value regardless of whether the arithmetic is correct.\n\nReplaced the four const-array blocks with array-translate'd blocks\ncarrying distinct nonzero lower bounds and position-tagged values, so\neach assertion now depends on the real local coordinate. Verified the\nnew test actually catches the bug class: temporarily dropping the\nblock-lowers addition turned 0 failures into 12, confirming the fix\ncloses a real gap rather than just adding assertions.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-26T09:15:39+05:30",
          "tree_id": "e17d18ea65ba1ca63b0f3f04ba731b412444ae03",
          "url": "https://github.com/kaappi/kaappi/commit/34e15133a27c823053078175621ebb3505263913"
        },
        "date": 1785039818760,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.284387,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.416287,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.893852,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.416302,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006388,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.053715,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.497987,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069212,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.524828,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.93126,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.576853,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.434035,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.815633,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.65073,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044278,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "c5eb3c9811dc0566660ad33b568d261eb4aa0b87",
          "message": "Finalize SRFI 231: public lib/srfi/231.sld hub, close #1694 (#1755)\n\n* Finalize SRFI 231: public lib/srfi/231.sld hub, close #1694\n\nMerges the 7 internal phase files (misc, intervals, storage-classes,\narrays, views, combinators, assembly — Slices 8-13) into a public,\nbare-importable (srfi 231) re-export hub, following the (srfi 4) thin\nre-export precedent. The 118-binding public surface is confirmed an\nexact bijection against the reference implementation's own export\nclause, with the 4 %-prefixed internal helpers in (srfi 231 arrays)\ncorrectly excluded.\n\nAlso moves SRFI 179 from tracked to excluded: SRFI 231's own abstract\nstates it is \"a revised and improved version of SRFI 179\" (a breaking\nrevision, not a strict superset like 47/63 — see\ndocs/dev/srfi-exclusions.md for specifics).\n\nBumps the tracked SRFI count 170->171 across CLAUDE.md, README.md, and\nCONFORMANCE.md, all cross-checked against the canonical SRFI registry:\n171 implemented + 7 tracked + 30 excluded = 208, matching exactly.\n\nThis closes issue #1694 (the numeric-vector and array family) in full:\n4/160/66/74 (vector family) and 25/164/63/231 (array family, with 47\nand now 179 excluded as superseded) are all shipped.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* Add full public-export completeness audit to the hub test\n\nCodeRabbit review of #1755: the hub smoke test only exercised 14\nrepresentative bindings, so it couldn't catch the hub silently\ndropping some OTHER name from its claimed 118-binding surface (a typo\nor missed addition in lib/srfi/231.sld's own export clause).\n\nAdded a single assertion referencing all 118 exported identifiers by\nname, in the same order as the hub's own export clause -- evaluating\nit requires every one to resolve, so a missing export fails the\nassertion immediately rather than going unnoticed. Verified the check\nactually works: temporarily dropped array-block! from the hub's export\nclause and confirmed the audit assertion failed (16 pass, 1 fail)\nbefore restoring the real file.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-26T10:55:16+05:30",
          "tree_id": "19a2bc944dbc69ad1e1c2f6cb7a317cfbf78ad04",
          "url": "https://github.com/kaappi/kaappi/commit/c5eb3c9811dc0566660ad33b568d261eb4aa0b87"
        },
        "date": 1785045867883,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 2.417104,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.690055,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.504299,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.472516,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004873,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.031798,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.28291,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.042137,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.335787,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.128729,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 0.931677,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.307786,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.054815,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.813534,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.027284,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "8221fd0429993177149d81e279b0b3283e878890",
          "message": "Fix CLAUDE.md: the 7 tracked macro/syntax SRFIs are issue #1699, not untriaged (#1756)\n\nPR #1755's SRFI-count reconciliation correctly identified 72, 139, 147,\n148, 149, 211, 213 as the 7 still-tracked final SRFIs, but wrongly\ncalled them \"untriaged; no issue filed\" -- issue #1699 (\"Implement\nSRFI macro & syntax extension libraries\") already tracks exactly this\nset, filed and open. Caught by checking `gh issue list` after the\nfact, not by any verification built into the original edit.\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-26T10:59:58+05:30",
          "tree_id": "e4145f3453f6df3a8a80a2b2185619f356991aef",
          "url": "https://github.com/kaappi/kaappi/commit/8221fd0429993177149d81e279b0b3283e878890"
        },
        "date": 1785047057936,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.27975,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.220866,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.894887,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.409087,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006408,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.053375,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.498585,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069058,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.541488,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.931807,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.565725,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.433913,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.799244,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.661465,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043728,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "2e3b70a53dd6b3c2501bdd05fbbf2871e264d37a",
          "message": "Add SRFI 139 (syntax parameters) (#1757)\n\nFirst of 4 tractable pieces of issue #1699 (SRFI macro & syntax\nextension libraries) picked up after issue #1694 closed. Despite being\ngrouped with 6 SRFIs needing real expander/compiler work, 139 needs\nnone: let-syntax already implements exactly syntax-parameterize's own\nsemantics (adjust the live macro table for a bounded compile extent,\nthen restore it), so lib/srfi/139.sld is a 2-form, 6-line library.\n\nVerified against both of the spec's own worked examples (forever/\nabort, lambda^/return) plus 2 adversarial cases -- nested\nsyntax-parameterize of the same keyword, and a body-local variable\nsharing a name with the macro's own internal continuation identifier\n-- both passing without any implementation changes.\n\nBumps the SRFI count 171->172, reconciled against the canonical\nregistry: 172 implemented + 6 tracked + 30 excluded = 208.\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-26T13:03:49+05:30",
          "tree_id": "4b70b5b99b5adceee9fd87b2cd4b0636bcad3ac6",
          "url": "https://github.com/kaappi/kaappi/commit/2e3b70a53dd6b3c2501bdd05fbbf2871e264d37a"
        },
        "date": 1785053514670,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.302535,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.596801,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.889038,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.412917,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006401,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.053974,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.500314,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069164,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.538497,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.94864,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.564177,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.441065,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.790539,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.601312,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043321,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "0bf6f03c849d30a05e7584b2ef8fd5f0a2baf207",
          "message": "Add SRFI 149 (basic syntax-rules template extensions) (#1758)\n\n* Add SRFI 149 (basic syntax-rules template extensions)\n\nSecond of 4 tractable pieces of issue #1699. Like SRFI 139, this needed\nno engine changes despite being grouped with SRFIs that do: Kaappi's\nexpander already implements both of this SRFI's extensions --\nconsecutive ellipses directly after one template element, and letting\na pattern variable be followed by more ellipses than its own\npattern-matched depth, with the excess replicating a shallower sibling\nat the innermost position.\n\nThe spec's own prose gives no worked example for the genuinely-new\nnonzero-depth-excess case, so this needed fetching the reference\nimplementation's expand-template algorithm to understand precisely\nwhat \"innermost\" means, then confirming empirically (against both of\nthe spec's own worked examples, my-append and foo, plus 2 more) that\nKaappi's binding-driven design -- live per-binding depth reduction --\nproduces the identical result via a different mechanism than the\nreference's free-variables-at-this-dimension scan.\n\nlib/srfi/149.sld is a trivial (export syntax-rules) re-export, the\nsame shape as SRFI 46's own \"these R7RS extensions are already native\"\nlibrary. New Zig unit tests in tests_macros.zig plus the usual SRFI-64\nsuite. One pre-existing, unrelated gap found and deliberately left\nalone: an ellipsis with no driving variable at all silently produces\nan empty result instead of erroring -- predates this SRFI and isn't a\ncase it needs to support; fixing it is a separate, broader project.\n\nBumps the SRFI count 172->173, reconciled against the canonical\nregistry: 173 implemented + 5 tracked + 30 excluded = 208.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* Fix markdown lint: avoid #1699 starting a line in CLAUDE.md\n\nCodeRabbit review of #1758: a line starting with \"#1699\" triggers\nMD018 (no-missing-space-atx), since Markdown parses a leading # as an\nATX heading. Reworded to keep it mid-line.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-26T14:34:36+05:30",
          "tree_id": "cb0dd54a0cc59ab0c7c9f7fab318a3187d86d2ad",
          "url": "https://github.com/kaappi/kaappi/commit/0bf6f03c849d30a05e7584b2ef8fd5f0a2baf207"
        },
        "date": 1785059045733,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.278715,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.023719,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.887319,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.389266,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006348,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.05338,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.497781,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068974,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.48396,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.965794,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.561787,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.429299,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.796559,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.585379,
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
          "id": "f0ac6759c0c2c9a20422d556d583176d8da7fad8",
          "message": "Ship lib/kaappi/ in the release library tarball (#1759)\n\nThe \"Bundle portable libraries\" release step enumerated lib/srfi/ and\nlib/chibi/ -- a list that predates lib/kaappi/ -- so every release from\nv0.18.0 through v0.21.0 shipped a kaappi-lib.tar.gz without\nlib/kaappi/parallel.sld, and (import (kaappi parallel)) failed with\n\"library not found\" on any stock install even though the library is\ndocumented, correct in the tree, and embedded in the binary for\n--sandbox/WASM. Pack the whole lib/ tree instead of an enumerated\nsubset so a future subdirectory cannot be silently dropped.\n\nThe acceptance suite never caught this because it only imported\nbuilt-in libraries (srfi 1/69), which resolve with no libraries\ninstalled at all -- and it runs from the repo checkout, where\ncwd-relative ./lib and the binary's <exe>/../lib fallback both resolve\nthe full source tree, masking any tarball gap. Add one disk-loaded\nimport per shipped lib/ subdirectory, run from a neutral directory\nwith a copied binary so only the installed ~/.kaappi/lib can satisfy\nthem; the (kaappi parallel) test reproduces the exact #1741 failure\nagainst a pre-fix tarball and passes with the fixed one.\n\nFixes #1741\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-26T09:15:50Z",
          "tree_id": "f79b683b5e354b05183cc33208a64dc0a87d1702",
          "url": "https://github.com/kaappi/kaappi/commit/f0ac6759c0c2c9a20422d556d583176d8da7fad8"
        },
        "date": 1785059334032,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.272342,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.775122,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.919443,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.396947,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006451,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.053764,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.50264,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069423,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.543474,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.932813,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.580197,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.441576,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.805693,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.661727,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045113,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "8c69cbc8f8057433f2b7aad3b614e5eb919615cc",
          "message": "Add SRFI 147 (custom macro transformers) (#1760)\n\n* Add SRFI 147 (custom macro transformers)\n\nThird of 4 tractable pieces of issue #1699, and the first that\ngenuinely needed an engine change. R7RS's <transformer spec> only\naccepts a literal (syntax-rules ...) form; this SRFI extends it to\nalso accept a macro use that itself expands (possibly through several\nsteps) to one -- letting a library define its own\ntransformer-generating-transformer, e.g. the spec's own worked\nexample, a syntax-rules* that auto-wraps multi-form templates in\nbegin. This is exactly what SRFI 148's em-syntax-rules needs, the\nreason this SRFI was implemented.\n\ncompileDefineSyntax/compileLetSyntax/compileLetrecSyntax now route\nevery transformer-spec through a new resolveTransformerSpec, which\nexpands a non-literal spec via the same expander.expandMacro every\nordinary macro call already goes through, looping (depth-bounded)\nuntil it bottoms out at a literal syntax-rules form. Two of the\ngrammar's other alternatives -- bare-keyword aliasing and\nbegin-wrapped-definitions -- are deliberately not implemented, since\nneither is needed by SRFI 148.\n\nVerifying against just the spec's own example wasn't enough --\nbash tests/scheme/run-all.sh caught two real, generalizable bugs no\namount of SRFI-147-specific testing alone would have found:\n\n1. A LIFO root-stack violation: an early draft rooted the resolved\n   spec via pushRoot + defer popRoot() inside compileLetSyntax's\n   per-binding loop, but the same iteration pushes an unrelated root\n   right after, so the deferred pop silently removed the wrong (most\n   recent) entry instead. Surfaced only in srfi257.scm's heavily\n   macro-based library as an unrelated-looking \"invalid syntax\" error.\n   Fixed by popping immediately and explicitly, never via defer across\n   a stretch that itself calls pushRoot -- now documented in\n   .claude/rules/gc-safety.md, whose glob also grew to cover\n   compiler*.zig/expander.zig.\n2. A parent-scope-chain visibility gap: the macro lookup only checked\n   self.macros, unlike the established expandAndCompileMacroUse path,\n   which merges every ancestor Compiler scope's macros first -- a\n   nested child scope (e.g. a let-syntax inside guard's desugared\n   lambda, as SRFI 64's own test-equal produces) never automatically\n   inherits an enclosing scope's macros.\n\nBumps the SRFI count 173->174, reconciled against the canonical\nregistry: 174 implemented + 4 tracked + 30 excluded = 208.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n* Fix ancestor-scope shadowing order in resolveTransformerSpec\n\nCodeRabbit review of #1760: the ancestor-chain merge populated\nnearest-to-farthest (matching expandAndCompileMacroUse's own existing\npattern), but since a hash map's put() overwrites, this means a\nFARTHER ancestor's macro definition wins over a NEARER one when both\nredefine the same name -- backwards from correct lexical shadowing.\n\nConfirmed via a 3-level nested-lambda reproduction: an outermost\nmk-transformer definition wrongly won over a middle-scope redefinition\nthat should have shadowed it. Fixed by collecting the ancestor chain\nfirst, then populating farthest-to-nearest (self.macros last of all),\nso a nearer scope's put() call correctly happens after a farther one's.\n\nDeliberately not fixed in expandAndCompileMacroUse itself: it's the\nmost heavily-exercised path in the entire macro system, the scenario\nneeds 2+ ancestor generations redefining the exact same macro name\n(rare, never observed causing a problem there), and touching it\ncarries regression risk disproportionate to this PR's actual scope --\nworth its own dedicated fix.\n\nAlso fixes a markdown-lint nit (blank lines around fenced examples in\ngc-safety.md) and switches a manually-constructed GC/VM test to the\nestablished th.TestContext helper.\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-26T20:17:10+05:30",
          "tree_id": "d9c5a05d813bbc52cf3d2b74d38808e12a28449d",
          "url": "https://github.com/kaappi/kaappi/commit/8c69cbc8f8057433f2b7aad3b614e5eb919615cc"
        },
        "date": 1785079333164,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.134434,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.426043,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.650484,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.238276,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006155,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.043289,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.373584,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.054549,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.168129,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.43825,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.239222,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.405442,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.383051,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.805854,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.036393,
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
          "id": "b5dabae02d77837a641d1093ec0cf942160cecd9",
          "message": "Bump the github-actions group with 2 updates (#1738)\n\nBumps the github-actions group with 2 updates: [actions/checkout](https://github.com/actions/checkout) and [vmactions/freebsd-vm](https://github.com/vmactions/freebsd-vm).\n\n\nUpdates `actions/checkout` from 7.0.0 to 7.0.1\n- [Release notes](https://github.com/actions/checkout/releases)\n- [Changelog](https://github.com/actions/checkout/blob/main/CHANGELOG.md)\n- [Commits](https://github.com/actions/checkout/compare/9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0...3d3c42e5aac5ba805825da76410c181273ba90b1)\n\nUpdates `vmactions/freebsd-vm` from 1.5.0 to 1.5.2\n- [Release notes](https://github.com/vmactions/freebsd-vm/releases)\n- [Commits](https://github.com/vmactions/freebsd-vm/compare/5a72679103d223925653750faa878a143340fbd0...77ed28d336d03fe19a3f4f7266c1d2c4714dd79d)\n\n---\nupdated-dependencies:\n- dependency-name: actions/checkout\n  dependency-version: 7.0.1\n  dependency-type: direct:production\n  update-type: version-update:semver-patch\n  dependency-group: github-actions\n- dependency-name: vmactions/freebsd-vm\n  dependency-version: 1.5.2\n  dependency-type: direct:production\n  update-type: version-update:semver-patch\n  dependency-group: github-actions\n...\n\nSigned-off-by: dependabot[bot] <support@github.com>\nCo-authored-by: dependabot[bot] <49699333+dependabot[bot]@users.noreply.github.com>",
          "timestamp": "2026-07-26T21:19:48+05:30",
          "tree_id": "52428b465ec8c835eff5d0b2d880a43741db8d10",
          "url": "https://github.com/kaappi/kaappi/commit/b5dabae02d77837a641d1093ec0cf942160cecd9"
        },
        "date": 1785083208902,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.973826,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.014041,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.92491,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.466193,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006612,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.052518,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.50808,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.067369,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.320004,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.967904,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.499548,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.481464,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.689994,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.745343,
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
          "id": "963d3c78b1469da02f3356bcf2efd18ea25c9387",
          "message": "Reseed the default random source in fork(2)ed children (#1761)\n\nThe default SRFI 27 source is created eagerly at VM startup, so a forked\nchild — e.g. every http-listen-prefork worker, which forks via the FFI —\ninherited the parent's exact PRNG state: all workers continued the same\nstream and drew identical \"random\" values (identical kaappi-web session\nids across workers, and a child's draws exactly equal to the parent's).\n\nA pthread_atfork child handler now marks the source stale. The handler\nitself only writes one word: in the forked child of a multithreaded\nparent, anything that can take a libc lock or allocate is off-limits.\nThe next touch of the default source — every path funnels through\ngetRS — reseeds it in place from OS entropy: in place so the heap object\ncaptured by (srfi 27)'s load-time default-random-source binding stays\nthe live default, and flag-cleared-first so an explicit randomize!/\npseudo-randomize!/state-set! in the child stays authoritative.\n\nWindows and WASI have no fork; the handler is compiled out there.\nCross-compiled x86_64-linux, aarch64-windows, aarch64-netbsd, and wasm;\nfull unit + Scheme suites green (1986 pass).\n\nRegression tests: tests/scheme/ffi/fork-reseed.scm (real fork via FFI —\nthe child's 8 draws were element-for-element identical to the parent's\nbefore this fix) and a state-replay unit test in tests_random_port.zig.\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-26T21:20:10+05:30",
          "tree_id": "b2e96de4d809d631ff1ed3722f4a634a23f790b2",
          "url": "https://github.com/kaappi/kaappi/commit/963d3c78b1469da02f3356bcf2efd18ea25c9387"
        },
        "date": 1785083472932,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.301921,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.638808,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.948636,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.434615,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006497,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.055054,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.509945,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.06978,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.552324,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 2.001987,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.61036,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.440979,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.852601,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.741837,
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
          "id": "845b75622e3d7a4eac3e7d63f6adee32918a3075",
          "message": "Extend SRFI 147 with begin-wrapped and bare-alias transformer specs (#1762)\n\nDeeper research for SRFI 148 (reading its reference implementation, not\njust the spec prose) found that em-syntax-rules's own core mechanism\n(em-syntax-rules-aux1/aux2) bottoms out through exactly\n`(begin (define-syntax a spec) a)` -- a private helper definition\nfollowed by a bare reference to it. Both grammar alternatives this\nneeds (begin-wrapped definitions, and bare-keyword aliasing of a\nnon-builtin macro) were deferred in #1760 based on an earlier, shallower\npass that concluded neither was needed.\n\nresolveTransformerSpec now returns an already-parsed Transformer instead\nof raw syntax-rules source, since the bare-symbol alias case has no\nsource to hand back -- only a Transformer an earlier step already\nparsed. Aliasing a builtin special form still correctly falls through to\nInvalidSyntax: builtins are recognized structurally, never stored as\nTransformer values in the macro table a bare symbol resolves against.\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-26T16:43:21Z",
          "tree_id": "ed8bbbe59ae47dc0485d217451db18b135a1717a",
          "url": "https://github.com/kaappi/kaappi/commit/845b75622e3d7a4eac3e7d63f6adee32918a3075"
        },
        "date": 1785086432884,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.309789,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.914241,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.930957,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.445399,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006397,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.054384,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.506559,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.06879,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.542347,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.972524,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.607075,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.437158,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.84202,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.676303,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044597,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "826eeb3c9bea60ab1ec55b5584c00d9d624d627c",
          "message": "Persist begin-wrapped SRFI 147 helpers, fix double-finalization leak (#1763)\n\nTracing SRFI 148's actual reference implementation (not just its grammar)\nfound that em-syntax-rules-aux2's own base case expands to\n`(begin (define-syntax o spec) o)`, where the SURROUNDING syntax-rules\nbody also calls `o` directly from within its own rules (not just as the\nbare tail) -- so `o` must keep resolving every time the macro being\ndefined here is later invoked, not just while resolving that one\ntransformer-spec. A helper registered only in resolveTransformerSpec's\ntransient, function-local merged_macros (discarded once that call\nreturns) cannot satisfy this -- confirmed via direct reproduction\nfailing with \"undefined variable '__hyg_N_helper'\" on every subsequent\nuse of the outer macro.\n\nFixed by registering each begin-internal helper into the real,\npersistent-for-this-scope's-lifetime self.macros (and lib_env at library\ntop level), exactly like an ordinary define-syntax at the same nesting\ndepth gets.\n\nThat fix immediately surfaced an adjacent bug under the unit test\nsuite's leak-checking allocator: a begin-wrapped alias can hand the\nexact same Transformer Value to two or more different binding sites, and\ncaptureLocalsOnTransformer/computeBoundFreeRefs both allocate and\nunconditionally overwrite a slice field with no free of what was there\nbefore -- a second finalization pass on an already-finalized object\nleaked the first allocation. Fixed by merging both calls into one\nfinalizeTransformer, guarded by a new Transformer.finalized flag.\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-26T18:22:45Z",
          "tree_id": "ef8cad314bf1b89c43e8502abdd0d41f47ba0583",
          "url": "https://github.com/kaappi/kaappi/commit/826eeb3c9bea60ab1ec55b5584c00d9d624d627c"
        },
        "date": 1785092603121,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.325883,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.01117,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.694687,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.425462,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00687,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.045787,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.395867,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.059723,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.303349,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.517346,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.325476,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.443159,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.472464,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.041009,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.038237,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "26d841123133d7d96a61f4d95ce193a2a924a47c",
          "message": "Fix let_syntax_peer_names/vals leak when siblings share a Transformer (#1764)\n\nCodeRabbit-caught on #1763, after CI had already auto-merged it: the\nsame overwrite-without-free hazard just fixed for captured_locals/\nbound_free_refs (via finalizeTransformer) also applies to\ncompileLetSyntax's own let_syntax_peer_names/vals bookkeeping, which\nlives in a separate code block outside finalizeTransformer's reach.\nReachable as soon as two sibling let-syntax bindings resolve to the same\nTransformer object (a begin-wrapped helper reference for one, a bare\nalias of that same helper for the other).\n\nFixed with a narrower guard than Transformer.finalized: a linear scan of\nthis call's own tx_vals prefix for an identical Value already processed\nearlier in the SAME loop. This can't be a permanent per-object flag like\nfinalized, since a transformer aliased into some OTHER, unrelated\nlet-syntax form later genuinely needs its own peer snapshot computed\nagainst that different form's sibling set.\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-26T19:51:53Z",
          "tree_id": "b0f9bd8023419df813fea7d50f781e9c0410c7a4",
          "url": "https://github.com/kaappi/kaappi/commit/26d841123133d7d96a61f4d95ce193a2a924a47c"
        },
        "date": 1785097600957,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.335232,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.712538,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.894163,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.403217,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006376,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.053978,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.503101,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069153,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.506244,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.960459,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.599976,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.428366,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.806329,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.456877,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043949,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "beaee758678073c163814e3b772586296e066b42",
          "message": "Free let_syntax_peer_names/vals before cross-form recomputation too (#1765)\n\nCodeRabbit-caught follow-up to #1764's own fix (found in that PR's\nreview, after CI had already auto-merged it): the tx_vals-prefix scan\nonly catches the same Transformer reappearing within one let-syntax\nform. It genuinely can't skip recomputation when that transformer is\naliased into a DIFFERENT, unrelated let-syntax form later -- that\nform's own sibling set differs and needs its own snapshot -- but the\nrecomputation itself still unconditionally overwrote whatever an\nearlier form's processing had already set, with no free.\n\nFixed by freeing the previous let_syntax_peer_names/vals pair\nimmediately before every overwrite, regardless of which case (within-\nform repeat vs. cross-form reuse) triggered it. Mutation-tested: a\nsecond reproduction (the same helper aliased into two separate,\nsequential top-level let-syntax forms, each with a distinct sibling of\nthe same name) confirms the recomputation itself still resolves\ncorrectly, and leaks 2 allocations without this fix.\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-26T21:21:54Z",
          "tree_id": "6ee4ec3f51b4725f059bf7f7dcf68245d301b6d8",
          "url": "https://github.com/kaappi/kaappi/commit/beaee758678073c163814e3b772586296e066b42"
        },
        "date": 1785102960674,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.316555,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.250153,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.900124,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.412647,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006392,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.054069,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.507157,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069469,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.52858,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 2.007143,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.591855,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.429864,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.864783,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.66001,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044588,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "4fe15c21592e12c4ca0999662c85931c864a868f",
          "message": "Freeze R7RS 4.3.1 peer snapshot permanently, not per-call (#1766)\n\nCodeRabbit-caught, and more serious than it first looked: the previous\nfix (free the old let_syntax_peer_names/vals pair before every\ncross-form overwrite) treated recomputing the sibling-suppression\nsnapshot against a different let-syntax form's own bindings as\nnecessary and correct. It isn't. R7RS 4.3.1's peer snapshot exists to\nfreeze a template's free references against whatever was in scope at\nthe template's own true point of definition, specifically so that\nlater shadowing at some other use site can't reach in and change what\na name resolves to -- recomputing it against a different form's outer\nbindings is exactly the interference the mechanism exists to prevent.\n\nConfirmed via a properly discriminating reproduction (a plain top-level\nprocedure as the shared free reference can't tell the two designs\napart at all, since procedure bindings were never captured by\nlet_syntax_peer_vals in the first place -- only a macro, redefined\nbetween two forms, exposes it): recomputing silently changed a\npreviously-correct answer from 11 to -10. Nesting the reuse inside the\ndefining form's own body was worse, corrupting the outer binding too\n(500 instead of 6).\n\nFixed by replacing the per-call tx_vals-prefix scan with a permanent,\nonce-per-object Transformer.peers_computed flag, mirroring `finalized`\nbut kept as its own field since peer suppression is\ncompileLetSyntax-specific. Also applies CodeRabbit's suggested\natomic-dupe pattern (dupe both new slices before touching the old ones,\nso a second-dupe OOM can't leave one field freed and the other stale).\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-26T23:08:20Z",
          "tree_id": "b7e150daffa191224dc6bd6bc28487013267b00d",
          "url": "https://github.com/kaappi/kaappi/commit/4fe15c21592e12c4ca0999662c85931c864a868f"
        },
        "date": 1785109579145,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.362588,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.258808,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.904272,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.508168,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006376,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.054694,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.51119,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069472,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.489568,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.999023,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.591191,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.436074,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.866375,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.630811,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044109,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "4b1c584c78db89eac640c54b8e808cfa22b2b5ef",
          "message": "Set peers_computed only after the snapshot is durably stored (#1767)\n\nCodeRabbit-caught: the previous commit set Transformer.peers_computed\ntrue immediately, before the fallible allocations (peer_names_f/\npeer_vals_f appends, both dupe calls) that actually build the\nlet_syntax_peer_names/vals snapshot. An OOM partway through would leave\nthe flag permanently true with both fields still at their default-empty\nvalue -- every later reuse of that transformer would then treat \"no\nsibling suppression needed\" as the final, correct answer instead of\nretrying the computation.\n\nFixed by moving the flag assignment to strictly after both slices are\ndurably stored, immediately before the self.macros.put that was already\nthere.\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-27T00:21:06Z",
          "tree_id": "36ff10ce1f3a4d8689764568c132e67fef36404c",
          "url": "https://github.com/kaappi/kaappi/commit/4b1c584c78db89eac640c54b8e808cfa22b2b5ef"
        },
        "date": 1785113845148,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.3016,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.414037,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.901747,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.400381,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006399,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.054109,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.508896,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069633,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.542661,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.998438,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.584733,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.431699,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.855915,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.632937,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044316,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "76d6012c1338dd8215ff39a595eff82a777b3df7",
          "message": "Fix hygiene rename split between a nested syntax-rules pattern and its own quoted template (#1773)\n\nrenameForHygiene unconditionally treated any quoted identifier as inert\nliteral data, skipping the hygienic rename. That's correct for ordinary\nquoted data, but wrong when the quote sits inside a nested syntax-rules\ntemplate being generated by an outer macro: the corresponding pattern-side\noccurrence of the same identifier (walked without QUOTE_FLAG) already\nclaimed a rename, and the template must match it exactly or the inner\nmacro's own pattern-matcher can never bind the two together -- the\ntemplate's occurrence passed through literally instead of substituting the\ncall's actual argument.\n\nFound while porting SRFI 148's reference implementation, whose CK-machine\ntechnique defines helper macros via nested syntax-rules with quoted\ntemplates throughout -- but the bug is general and predates this session's\nSRFI work entirely.\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-27T02:26:44Z",
          "tree_id": "8ebdf1bbd2d5898b4717580929fe6ac9047fc1f9",
          "url": "https://github.com/kaappi/kaappi/commit/76d6012c1338dd8215ff39a595eff82a777b3df7"
        },
        "date": 1785122065891,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.974829,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.821687,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.914973,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.346275,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006713,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.052673,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.506153,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068082,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.339907,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.943199,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.527337,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.473816,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.720487,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.780091,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044355,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "672db1f109080ba0300b8be4a29eebf4fb7572fa",
          "message": "Promote expt to complex for negative base + non-integer exponent (#1725) (#1769)\n\nexptFn's real-number fallback called std.math.pow unconditionally,\nwhich returns +nan.0 for a negative base combined with a non-integer\nreal exponent (e.g. (expt -8.0 0.5), (expt -8 1/3)) instead of the\nwell-defined complex result — the same input shape sqrt already\npromotes correctly.\n\nFactored the existing z^w = e^(w*ln(z)) formula out of the\nalready-complex branch into a shared complexPowGeneral helper, and\nroute a finite negative base with a finite non-integer exponent\nthrough it before falling back to std.math.pow. Integer exponents\n(even via a flonum, e.g. -8.0^3.0) are left untouched since pow\nalready handles those correctly for a negative base.",
          "timestamp": "2026-07-27T08:05:00+05:30",
          "tree_id": "2c383fac6554457a1284c7c0b6197f216cad3a98",
          "url": "https://github.com/kaappi/kaappi/commit/672db1f109080ba0300b8be4a29eebf4fb7572fa"
        },
        "date": 1785123400646,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.092422,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.545508,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.950123,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.412205,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006846,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.052556,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.507999,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068205,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.318538,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.969588,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.530846,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.48407,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.766816,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.742168,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.04521,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "7fd9417875c9b0dc122d7f8afd5630b3de9f56d2",
          "message": "Detect cycles through record instances in the printer (#1713) (#1768)\n\nwrite/display/write-shared already datum-labeled cycles through pairs\nand vectors, but record instances were invisible to that machinery, so\nprinting fell through to the plain depth-limited recursive printer. A\ndirect self-reference merely recursed to the depth cap, but a record\nfield that's a vector of records which each reference it back (e.g.\ntwo mutually-referencing record types, the SRFI 209 enum/enum-type\nshape that motivated this issue) fans out combinatorially at every\nlevel of that recursion, hanging the process well before the cap.\n\nRecord instances now join pairs and vectors in both cycle-detection\npasses (markCyclesRec, markShared) and in the shared-aware printer, so\na cyclic web of records prints with #N=/#N# datum labels instead of\nlooping forever.\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-27T08:03:58+05:30",
          "tree_id": "5f13324199f5d46f80b9ca86ec5068d189b39932",
          "url": "https://github.com/kaappi/kaappi/commit/7fd9417875c9b0dc122d7f8afd5630b3de9f56d2"
        },
        "date": 1785123421662,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.341017,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.197353,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.895551,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.417431,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006274,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.053498,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.506268,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069531,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.512027,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.94447,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.621699,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.430284,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.805024,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.640263,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044066,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "281e135c480862edf2a01eaf1e36e5cb8b20f10d",
          "message": "Refuse kaappi compile when an import can't resolve at runtime (#1743) (#1770)\n\nThe compiled binary's own runtime starts a fresh VM with no library\nsearch path, and the native backend never bundles .sld sources into\nthe binary the way --compile/-Dbundle-src does. So any import the\ncompiling VM resolves from a file — a third-party package or one of\nthe 159 portable SRFIs, not just kaappi-json — compiled cleanly but\ndied at runtime with \"library not found\" despite kaappi compile\nreporting success and exiting 0.\n\nemitLlvmFile now detects this by reusing the .sbc bundler's own\nfile-collection hook (populated only when a library is resolved from\ndisk, never for built-ins) and refuses to emit anything, naming the\nunresolvable library file(s) and pointing at the interpreter or\nzig build -Dbundle-src as working alternatives. Covers both\nkaappi compile and --emit-llvm, with no false positives for built-in\nlibraries or self-contained define-library files.\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-27T08:05:49+05:30",
          "tree_id": "31727b22fbac02b7bcb61f25c539e58142e355df",
          "url": "https://github.com/kaappi/kaappi/commit/281e135c480862edf2a01eaf1e36e5cb8b20f10d"
        },
        "date": 1785123634432,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.32826,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.386337,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.902162,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.43885,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006334,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.05401,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.508503,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069434,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.536588,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 2.002797,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.574674,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.422828,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.812384,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.617504,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043845,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "4284fadcb52be2f98e5af097943da6dad8b8a33d",
          "message": "Fix let-values/let*-values corruption when list/apply/call-with-values are shadowed (#1771)\n\nBoth forms desugar internally to code that invokes list, apply, and\ncall-with-values by name. Those were ordinary, shadowable identifier\nreferences, so a program redefining any of them at the top level --\nexactly what SRFI 101 does for `list` -- could corrupt the desugaring\ninstead of the compiler always meaning the true (scheme base)\nprocedures. The reported symptom was a spurious \"apply: expected\nproper list, got #<record_instance>\" error: the shadowed `list`\nhanded back something other than a real list, and the\ncorrectly-resolved `apply` then correctly rejected it.\n\nCompiler-synthesized references to these three names now resolve\nthrough a protected path: a __kaappi_base__-prefixed symbol that\nget_global/call_global recognize and resolve against (scheme base)'s\nown pristine export table (captured once at VM startup, never\ntouched again) instead of the live, mutable globals map. The\nreference has to stay a plain symbol rather than a pre-resolved\nvalue, since the .sbc bytecode cache has no serialization tag for\nprocedure constants and would silently corrupt one to nil on a cache\nround-trip.\n\nAlso fixes an adjacent gap: even the \"protected\" call_global fast\npath already used by let*-values only ever guarded against lexical\nshadowing, not a top-level redefinition of call-with-values itself --\nand isContinuationBarrier needed to recognize the new prefixed name\nso call-with-values keeps the standard frame setup its continuation\ncapture semantics depend on.\n\nFixes #1715\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-27T08:23:29+05:30",
          "tree_id": "d05dd7be0867f3efd4b318aaf0b127e4b516af6a",
          "url": "https://github.com/kaappi/kaappi/commit/4284fadcb52be2f98e5af097943da6dad8b8a33d"
        },
        "date": 1785124210361,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.397541,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.597212,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.940857,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.528775,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006426,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.055121,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.515354,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068968,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.510032,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.996336,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.63078,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.44271,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.85868,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.665281,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043974,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "2cad8e5056713db621134718eb456cd51cc7762f",
          "message": "Isolate record-type/define-values desugaring from vm.macros (#1718) (#1774)\n\ndefine-record-type/define-values compiled their generated definitions\nagainst the process-global macro table instead of an isolated one, so\nonce any program imported a macro shadowing a core special form (e.g.\nlambda), every later library's own record types or define-values forms\ncould fail to compile -- or, when the shadowed name was\ndefine-record-type itself, be silently dropped with no error, since\ncompileLibExpr unconditionally returned after deferring to macro-aware\ncompilation without actually performing it.\n\nRecord-type/define-values desugaring now uses a macro table scoped to\nthe current library (or none at all, for record-type's own\ncompiler-synthesized forms, which never contain user subexpressions),\nand the define-record-type shadow check now consults the active\nlibrary's own scope rather than the whole process's. Also make\nrenaming a special form on import (`(rename (only (scheme base) let*)\n(let* my-let*))`) fail with a clear diagnostic at the import\ndeclaration instead of silently producing a binding that resolves to\nnothing.\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-27T08:23:43+05:30",
          "tree_id": "4b130be25f54c65fb611e7e38df0d56f6cd1b85d",
          "url": "https://github.com/kaappi/kaappi/commit/2cad8e5056713db621134718eb456cd51cc7762f"
        },
        "date": 1785125014934,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.330009,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.055987,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 1.008146,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.79278,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006359,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.056234,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.560776,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.07232,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.679658,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 2.215757,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.593543,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.434807,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.84345,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.668139,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043907,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "fb9e93dc6365cfc8765e5b56479eb06753976947",
          "message": "Fix two macro-expansion bugs found while investigating SRFI 148 (#1776)\n\ninstantiateTemplate's (quote ...) fast path triggered for any template\nsub-list whose first element was literally the symbol quote, regardless of\nlength. R7RS quote is strictly unary, so a longer list merely starting with\nquote for an unrelated reason (e.g. passing the bare symbol quote as one\nargument among several to some other macro) was misparsed as a 2-element\nquote form, silently dropping everything after the second element.\n\nparseSyntaxRules's custom-ellipsis-argument detection didn't unwrap a\nusertext-marker-wrapped value -- the protocol nested syntax-rules\ngeneration uses when substituting an outer pattern variable into the\ngenerated macro's own ellipsis-argument position -- so a NESTED_SR_FLAG-\nwrapped ellipsis symbol was silently missed and misparsed as part of the\nliterals list instead.\n\nBoth are general, pre-existing bugs unrelated to any specific SRFI, found\nwhile porting SRFI 148's em-syntax-rules mechanism (issue #1699's final\nslice). SRFI 148 itself remains blocked on a separate, deeper performance\nproblem with generating-macro chains (#1775) not addressed here.\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-27T04:55:52Z",
          "tree_id": "58b9111655f9294c65d58c5bef7656892aa2a390",
          "url": "https://github.com/kaappi/kaappi/commit/fb9e93dc6365cfc8765e5b56479eb06753976947"
        },
        "date": 1785130934384,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.417033,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.02136,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.997704,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.656057,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006364,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.05532,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.558627,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.072557,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.632659,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 2.177721,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.611033,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.435193,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.854334,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.694208,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045073,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "87085096f1b5c93e03f37f6cd58e6e1e46adbc8b",
          "message": "Fix string->number to reject misplaced digit-separator underscores (#1724) (#1777)\n\nstringToNumber's small-integer and rational numerator/denominator parsing\ncalled std.fmt.parseInt directly on unvalidated input, which has its own\nunderscore convenience more permissive than SRFI 169 (it only rejects a\nleading/trailing underscore, not a doubled one), so \"1__2\" silently\ncollapsed to 12 instead of #f. Validate and strip underscores once, up\nfront, using bignum.stripUnderscores -- the same validator the reader and\nthe hex-float/bignum-overflow paths already relied on -- before any\nshape-specific parsing runs.\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-27T11:15:03+05:30",
          "tree_id": "7cfedd6983279e5c466ab0ef3525d70df78b1d74",
          "url": "https://github.com/kaappi/kaappi/commit/87085096f1b5c93e03f37f6cd58e6e1e46adbc8b"
        },
        "date": 1785136406822,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.391552,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.776782,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.963213,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.617471,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006384,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.055219,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.546729,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.071155,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.707694,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 2.100148,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.613748,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.434456,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.840036,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.622388,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043399,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "d5f6c255d676645853700203b45877bcacd02a35",
          "message": "Give kaappi compile binaries real argv via (command-line) (#1744) (#1778)\n\nThe LLVM emitter generated every compiled binary's entry point as\n`define i32 @main()` -- zero parameters -- so argc/argv never reached\nthe runtime and (command-line) always returned () regardless of what\narguments the binary was invoked with.\n\nmain now takes the standard C (argc, argv) pair and hands argv to a\nnew kaappi_set_command_line_args runtime export right after init,\nwhich scans it to its NULL sentinel (every native_backend_supported\ntarget's libc/CRT guarantees argv[argc] == NULL, so argc itself never\nneeds to be threaded further). A compiled binary's (command-line) now\nreturns its own path followed by its real arguments, mirroring how\nthe interpreter reports a script's filename followed by its arguments.\n\nAdded a dedicated e2e phase (test-argv.scm + run-e2e.sh/run-e2e.ps1)\nsince the existing interpreter-vs-native parity loop can't cover this:\nthe leading \"command name\" element legitimately differs between an\ninterpreted and a compiled run of the same program.",
          "timestamp": "2026-07-27T11:36:35+05:30",
          "tree_id": "37feabeaf197d5b2de765a6914829c90152d0754",
          "url": "https://github.com/kaappi/kaappi/commit/d5f6c255d676645853700203b45877bcacd02a35"
        },
        "date": 1785136818600,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.396496,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.633474,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.94693,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.585681,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006505,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.056266,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.514895,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069434,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.661279,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 2.113426,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.598573,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.431568,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 2.029021,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.686757,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044053,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "db38f24a8c494cb5f4c01bad8016fbefa6ac4186",
          "message": "Fix custom-ellipsis recognition in ordinary template expansion; split tests_macros.zig (#1779)\n\ninstantiateTemplate's two ellipsis-detection sites (the \"(... template)\"\nescape check and the \"element followed by ellipsis\" check) required a bare\nsymbol, but a nested syntax-rules template's ordinary (non-quoted) position\ncan receive a custom ellipsis identifier substituted from an outer pattern\nvariable, wrapped by NESTED_SR_FLAG's usertext-marking protocol. Neither\nsite unwrapped it, so the ellipsis was silently unrecognized outside quote\n(where the same substitution happens to skip wrapping entirely) -- the\nelement was emitted literally instead of splicing its repetitions.\n\nCaught by CodeRabbit's review of the previous commit, which fixed the\npattern-matching/parsing-side half of this same class of bug but missed\nthis instantiation-side one.\n\nAlso splits the new nested-syntax-rules-generation regression tests into\ntheir own file (tests_macros_nested_sr.zig), keeping tests_macros.zig under\nthe project's 1500-line file-size policy (also flagged by CodeRabbit).\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-27T06:17:10Z",
          "tree_id": "0ef02e08d53bc4b17aa522cfefaca0cb25518849",
          "url": "https://github.com/kaappi/kaappi/commit/db38f24a8c494cb5f4c01bad8016fbefa6ac4186"
        },
        "date": 1785137317549,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.113651,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.198187,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.95809,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.4621,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006897,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.053776,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.524834,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070402,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.366506,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.986485,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.560591,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.475399,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.743634,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.838953,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045828,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "129c56acf712a8da04b9282385400a8c83f95ba3",
          "message": "Support letrec*-style mutual reference in define-values (#1780)\n\nR7RS draws no distinction between `define` and `define-values` for a\nbody's letrec* scoping (5.3.2/5.3.3): a definition may reference\nanother definition appearing later in the same body, as long as the\nreference isn't evaluated before that binding is initialized. Plain\n`define` already worked this way, but a `define-values` clause could\nnot reference a name bound by a later `define-values` (or `define`)\nclause -- the reference silently compiled as a global lookup instead\nof a local/upvalue (since the name hadn't been declared as a local\nyet), surfacing as a runtime \"undefined variable\" error once the\nenclosing procedure was actually called.\n\nThe root cause is scanBodyDefs, the shared prescan that gives `define`\nits forward visibility by declaring every leading definition's name\nas a boxed local before compiling any of their init expressions -- it\nonly recognized `define` and `define-record-type`. `define-values` now\nparticipates: BodyScan gains an ordered `DefStep` (a `.simple`\nname-to-init step, or a `.values_group` step carrying an\nalready-desugared call-with-values/set! form, since one clause can\nbind 0..N names from a single shared init that doesn't fit the\nexisting one-name-one-init shape).\n\nTwo independent, duplicated \"declare locals then compile inits\" loops\nconsume the scan's output and both needed the identical fix:\ncompiler_lambda.compileBodyForms (let-family bodies and the legacy\nlambda path) and compiler_ir.compileLambdaWithIR (the modern\nIR-pipeline lambda path, reached only via `(define name (lambda\n...))` long-hand or a bare `(lambda ...)` -- the far more common\n`(define (name args) body)` shorthand always routes through the\nformer).\n\nFixes #1719\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-27T11:51:25+05:30",
          "tree_id": "2d23485e7e99d533716dea4339355876a7dc6496",
          "url": "https://github.com/kaappi/kaappi/commit/129c56acf712a8da04b9282385400a8c83f95ba3"
        },
        "date": 1785137684171,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.43366,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.878428,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.968242,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.608393,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00635,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.055141,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.527016,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.071303,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.587695,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 2.035692,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.617809,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.437276,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.90263,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.69979,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045491,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "78744a1727fc64b53344bc6dede4cd3eba755717",
          "message": "Detect colliding import bindings across libraries (#1726) (#1781)\n\n(import (srfi 28) (srfi 29)), which both export format, silently picked\nwhichever library came last in the import-set list with no diagnostic\neither way, reversing the order flipped which binding won. R7RS 5.2 says\nimporting the same identifier from two different libraries with different\nbindings is an error. handleImportInto and the environment procedure now\ntrack which import-set in the same batch first claims each name and reject\na later one that would bind it to a genuinely different value, naming both\nimport-sets and the identifier atomically, per import-set. Re-importing the\nidentical binding through two paths (a diamond dependency) still merges\nsilently, since that is the same binding, not two different ones, and\nshadowing across separate top-level (import ...) forms stays legal.\n\nGetting there surfaced two related, previously-invisible bugs. First, a\nnon-exported helper macro reachable only through an exported macro's\nexpansion (e.g. SRFI 64's test-assert -> %test-comp1body chain) could leak\ninto an importer's globals as a plain, callable value once the resolved\nexport set was routed through a scratch map first -- true for\nonly/except/prefix/rename already, and now also true for a plain,\nunmodified import since it needs the same scratch-map resolution to run the\ncollision check. Fixed by chasing the transitive macro closure only into\nthe real, final target (importBinding's new chase_transitive parameter),\nnever a scratch map that exists purely to answer \"what does this\nimport-set resolve to\". Second, a multi-set (import a b c) form that\nfailed partway through kept processing the rest, letting a later,\nsuccessful library load's own native calls clobber the shared\nerror-detail buffer and reduce a specific message to a bare \"invalid\nsyntax\" by the time it was reported. handleImportInto now stops at the\nfirst failing import-set, matching environment's existing behavior.\n\nA few portable SRFI libraries ((srfi 167), (srfi 146 hash)) had internal\ncollisions between (srfi 69) and (srfi 128) over string-hash/\nstring-ci-hash that previously loaded silently; several SRFI test files\nand two native-compile fixtures likewise combined libraries with\nundiagnosed collisions (square colliding with (scheme base), etc.). All\nnow disambiguate explicitly with only/except/rename.\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-27T13:17:19+05:30",
          "tree_id": "049fb848c8280b0c0a802a32221b0096c91e93f1",
          "url": "https://github.com/kaappi/kaappi/commit/78744a1727fc64b53344bc6dede4cd3eba755717"
        },
        "date": 1785141244839,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.326866,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.581544,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.946035,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.733654,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006314,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.05519,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.513521,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070539,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.579726,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 2.058079,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.603111,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.439936,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.827459,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.674988,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043456,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "c9ce6cffd9a44d50aa2f9bb2bb5871184e5ebafa",
          "message": "Fix literal let/if matching in macro-generated nested syntax-rules (#1720) (#1782)\n\nlet and if are deliberately excluded from well_known_forms so a macro's\nown executable use of them stays hygienic under use-site shadowing, but\nthat exclusion meant a nested syntax-rules's let/if LITERAL (e.g. a\ngenerated dispatch macro's syntax-rules (let) ...) also got hygiene-\nrenamed by the generating macro's expansion. matchPattern's literal\nfallback only stripped a hygiene rename off the input side (for the\nreverse case, e.g. SRFI 257's cm-match), never off the literal side, so\na renamed literal could never match a real, unrenamed token typed at the\ngenerated macro's own use site. Strip both sides before comparing.\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-27T13:39:24+05:30",
          "tree_id": "6bbab6baa07bd8094071a6b07e45cc815011efe0",
          "url": "https://github.com/kaappi/kaappi/commit/c9ce6cffd9a44d50aa2f9bb2bb5871184e5ebafa"
        },
        "date": 1785142078322,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.043022,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.804879,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.931135,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.469486,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006701,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.054179,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.515231,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068757,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.283002,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.973155,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.540703,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.471939,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.706167,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.816634,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045194,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "f990d49a578a5d576c4a10df171762560b2b52b0",
          "message": "Build Linux release binaries against glibc so dynamic loading works (#1783)\n\nZig resolves the bare x86_64-linux / aarch64-linux targets to musl\nstatic, and static musl cannot dlopen — so every released Linux binary\nrejected (kaappi ffi) with 'Dynamic loading not supported', making the\nwhole C-extension ecosystem (net, http, sqlite, pg, redis, crypto)\nunusable from a release install. The docs site's docs-samples CI\ncaught it; the nightly ecosystem tests never could, because they build\nkaappi natively (glibc, dynamic) instead of testing release artifacts.\n\nThe two mainstream Linux targets now compile against glibc with a 2.28\nfloor (RHEL 8 / Debian 10 / Ubuntu 18.10+). A new zig_target matrix\nfield carries the compile triple so artifact names — which install.sh\nmatches (libkaappi_rt-<target>.a) — stay unchanged. Interpreter-tier\narches (riscv64, s390x, ppc64le) stay musl-static: their artifacts\nwere validated on Alpine VMs and gain nothing from a glibc floor.\nTrade-off: glibc binaries don't run on musl distros; Alpine users\nbuild from source until a musl-dynamic variant ships as an extra\nartifact.\n\nA linux-ffi-smoke job now runs the actual x86_64 and aarch64 artifacts\nand proves ffi-open + ffi-fn against libm.so.6 before the release job\npublishes anything, so this class of regression cannot ship again.\n\nVerified locally with zig 0.16.0: x86_64-linux builds 'statically\nlinked' (the bug), x86_64-linux-gnu.2.28 and aarch64-linux-gnu.2.28\nbuild 'dynamically linked' with the correct glibc interpreters, and\n'zig build lib' produces libkaappi_rt.a for the gnu targets.\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-27T13:42:36+05:30",
          "tree_id": "0e204dc687e640088a69ea69b533a17f9cd24391",
          "url": "https://github.com/kaappi/kaappi/commit/f990d49a578a5d576c4a10df171762560b2b52b0"
        },
        "date": 1785142855659,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.099848,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.985262,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.938519,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.467162,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006723,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.053164,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.515844,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.067643,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.3342,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.972837,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.531973,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.473288,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.707538,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.811869,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.045796,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "c878b6983a7fbe64db8036e2d746fcb67cfb9838",
          "message": "Bound the set! pre-scan so macro-generating macros stop compiling exponentially (#1775) (#1784)\n\n* Bound the set! pre-scan so macro-generating macros stop compiling exponentially\n\nCompiling a macro that generates another macro — SRFI 148's em-syntax-rules,\nSRFI 257's CK-machine combinators — cost time exponential in the generated\nmacro's rule count. An 8-rule case took 31s; SRFI 257's own shipped test\nsuite spent 281s of its 289s runtime in the compiler.\n\nThe cost was never in the expander, despite --timings pointing there\n(`expand 2765.8ms`). It was compiler.collectSetTargets, the top-level `set!`\npre-scan. That scan expands macros so it can see a `set!` introduced by a\nmacro template (#1250) — which makes it a speculative evaluator of\ncompile-time macro code, and it explores branches the real compiler never\ntakes. At `(m kt kf)`, where `m` is a helper the enclosing expansion just\ndefined with define-syntax, the scan has no binding for `m`, so it treats\nboth continuations as ordinary sub-forms and expands macros inside each.\nThe real compiler registers `m` and follows exactly one. Every such fork\ndoubles the work.\n\nBound the scan at 4096 expansions per top-level form. Exceeding the bound is\nsafe by construction rather than by luck: it sets Compiler.set_targets_all,\nand both consumers then assume every name is a `set!` target — box every\nlocal, fold nothing. A truncated scan loses optimization, never correctness.\nThe pre-existing `depth > 256` cutoff now feeds the same flag; until now it\nsilently returned a partial answer, which is exactly the under-approximation\n#1168/#1250 are about.\n\n4096 is ~2.5x the highest count any non-pathological top-level form in this\nrepo's Scheme suites reaches (p99.99 = 1649; 87% of forms need none at all)\nand well below the 6299+ the macro-generating cases start at. The headroom\nis deliberate: truncation costs ~2x runtime on compute-heavy code, so\nordinary programs must never reach the limit.\n\nAlso give the pre-scan the fixed-point check expandAndCompileMacroUse\nalready has. SRFI 219 rule 3 is `(define name expr)` -> `(define name expr)`,\nso every plain `define` in a program importing it was re-expanded 257 times\nuntil the depth cap — and, once the depth cap became meaningful, would have\nsent ordinary code down the conservative path.\n\n  8-rule generating macro   31.6s -> 4.6s\n  srfi257-full.scm         280.8s -> 16.2s\n  srfi257-rx-full.scm      102.1s -> 23.5s\n  7/9-rule macro         14.9s/71.9s -> 4.8s/4.9s (flat, was exponential)\n\nNo change to compile time under the budget or to runtime: fib/tak/ack/\nheavy-arith/const-prop are unchanged.\n\ndocs/dev/timings.md gains a section on the trap that cost two earlier\nsessions: --timings names the stage, never the caller. `sample` put 99% of\nsamples under collectSetTargets on the first run.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Address CodeRabbit review on the set! pre-scan bound\n\nTwo of the three findings applied:\n\n- `prescan_expansion_limit` is now `threadlocal`, matching\n  `ir.optimize_enabled`'s documented rationale (an SRFI-18 child thread\n  compiling concurrently keeps the default instead of racing on whatever a\n  test left in a shared global). `prescan_truncations` beside it was already\n  threadlocal.\n- Tagged the timings.md fence `text` so markdownlint passes.\n\nDeclined sharing compiler_macro.MAX_MACRO_EXPANSION_DEPTH as the pre-scan's\ndepth cap, and said why in the code: the two 256s count different things.\nThat one bounds the real expansion of code that will be compiled, and\nexceeding it is a user-visible KP2003 error. This one bounds a speculative\nwalk that also descends into branches the compiler discards, so it is\nreached by programs whose real expansion depth never comes close — every\nSRFI 257 suite trips it several times per run while compiling and passing\nnormally. A shared constant would assert an equivalence the measurements\ncontradict.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-27T10:12:33Z",
          "tree_id": "89dcef06044fc6437283eb360b45d4a83049b153",
          "url": "https://github.com/kaappi/kaappi/commit/c878b6983a7fbe64db8036e2d746fcb67cfb9838"
        },
        "date": 1785149454802,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.357223,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.347647,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.950672,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.615654,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006296,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.05487,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.516252,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.070482,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.513056,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 2.044553,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.592477,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.429877,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.917026,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.632425,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043671,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "71569effd2b3b3da93737f5f2fc004d46825dae2",
          "message": "Stop the reactor timer tests failing on a poll() that returns a tick early (#1785)\n\n`tests_reactor.test.addTimer fires when its deadline passes` failed once on\nwindows-x64-test during CI for #1784 (expected 1, found 0) and passed on\nre-run.\n\nThe test asserted that a single `poll()` would fire a timer 1ms out. It does\nnot have to. `effectiveTimeout` bounds the wait at the nearest deadline, and\nan OS wait requested for an interval near the scheduler's tick can return a\nfraction of a tick early; `clockNs()` then still reads below the deadline, so\n`popExpiredTimers` moves nothing and `poll()` returns empty.\n`WindowsEventBackend.wait` ceils its millisecond conversion so a timer never\nfires *early*, but nothing can stop the underlying wait from returning early\n— which is why only the 1ms deadlines here were exposed, and why the 5s waits\nelsewhere in this file never were.\n\nThat is `poll()`'s documented contract, not a bug in it:\n`FiberScheduler.parkOnReactor` treats an empty return as ordinary and\nre-checks after each capped return. The tests were the only callers assuming\none poll suffices, so they now loop the same way.\n\nTwo neighbours had the same defect latent:\n\n- \"the nearer of an fd timeout and a timer deadline bounds the wait\" polls a\n  1ms timer identically and could fail the same way.\n- \"removeTimer cancels a pending timer so it never fires\" fails in the other\n  direction: a poll() cut short before the deadline let it pass without ever\n  proving the cancellation. It now sleeps past the deadline before looking.\n\nRetrying alone would have *weakened* the first two — the loop would quietly\nwait out a badly late timer — so both keep an explicit upper bound on how\npromptly the timer fired (1s: ~60x the coarsest tick behind the flake, and\nthe bound the notify test in this file already uses). Mutation-tested against\nthree breakages: timers that never expire, a wait bound that ignores timers,\nand a no-op removeTimer are each caught.\n\n40 consecutive runs of the reactor suite, clean.\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-27T16:35:49+05:30",
          "tree_id": "d19869db2df242274fa74227591efd661a9fc2b1",
          "url": "https://github.com/kaappi/kaappi/commit/71569effd2b3b3da93737f5f2fc004d46825dae2"
        },
        "date": 1785153038765,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.052286,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.725277,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.925688,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.65764,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006649,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.053297,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.532912,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068733,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.260215,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.975266,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.537761,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.471671,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.706136,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.778072,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044666,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "370d8e85cac4ca3a532b1c634eabec9f33c6f555",
          "message": "Name the library whose own import declaration collides (#1726 follow-up) (#1786)\n\nThe KP2001 import-collision diagnostic cites the file:line of the\ntop-level form that triggered the library load, so when the colliding\nimport declaration lives inside a library's .sld, the reader is pointed\nat the wrong file entirely: kaappi-mpl's sin.sld collision surfaced as\n\"test-mpl.scm:8: identifier 'sqrt' is imported with different bindings\nfrom both (except (scheme base) ...) and (mpl sqrt)\" -- naming\nimport-sets that appear nowhere near test-mpl.scm line 8. During the\n2026-07-27 nightly triage this masqueraded as a core import-resolution\nregression and cost two wrong root-cause theories before the real one\n(fixed in kaappi-mpl#2).\n\nhandleDefineLibrary now records the library name in a save/restored\nvm.loading_library_name while its declarations are processed (nesting\nvia the call stack), and the collision message names it: \"... imported\nwith different bindings inside library (mpl.sin)'s own import\ndeclaration, from both ...\". The name sits early in the message because\nthe 256-byte detail buffer truncates the tail. Top-level import forms\nkeep the original message.\n\nThe regression test also checks the context is restored after a failed\nload, so a subsequent top-level collision is not misattributed to the\nlibrary that failed before it.\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-27T16:56:33+05:30",
          "tree_id": "346a9da9410e1a828259541a41577d5e83b6e851",
          "url": "https://github.com/kaappi/kaappi/commit/370d8e85cac4ca3a532b1c634eabec9f33c6f555"
        },
        "date": 1785153869757,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.299649,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.266447,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.930896,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.643098,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.00633,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.055136,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.511519,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.06957,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.665713,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 2.201206,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.577296,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.43111,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.81663,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.63555,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044759,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "053f03d0831eb1d2c41dc19e74dd9bf5a94a364c",
          "message": "Re-unwrap usertext markers mid-match in matchListPattern's loop (#1788)\n\nmatchPattern unwraps its own pattern_in/input_in parameters once, at\nentry, but matchListPattern's internal loop advanced pat/inp on every\niteration without re-unwrapping. A usertext marker pair spliced into a\ndotted-tail position (e.g. a generated macro's pattern `(_ head . p)`\nwhere p's substituted value is a list) is only caught by the entry-level\nunwrap when it sits in the very first position; anything preceding it in\nthe pattern forces the marker to surface mid-loop as a bogus extra list\nelement, shifting every subsequent position and failing the match.\n\nFound while resuming SRFI 148 (eager syntax-rules, #1699), whose\ngenerated macro pattern is always exactly this dotted-tail shape. Fixes\none of two remaining blockers for that SRFI; the other (#1787) is a\nseparate, deeper bug in identifier-comparison against compound values.\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-27T17:59:20+05:30",
          "tree_id": "f4f82e850f3b5572ab9826e3829ecadf6130e8c0",
          "url": "https://github.com/kaappi/kaappi/commit/053f03d0831eb1d2c41dc19e74dd9bf5a94a364c"
        },
        "date": 1785157701733,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 2.641222,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 6.625905,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.508683,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 2.682333,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.004981,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.033721,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.285418,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.0411,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.585004,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.138538,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 0.998893,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.318675,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.123621,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.82917,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.028901,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "1792c0e6e53144d6acefffbcbf61ea8f32ee3b00",
          "message": "Add a slowdown-investigation runbook; fix the cache's dirty-build-id claim (#1789)\n\nPerformance material was spread across eight documents, organized by tool\nor subsystem rather than by question. Someone holding \"this compiles too\nslowly, where do I start?\" had no entry point: the answer spanned\ntimings.md (which stage), an undocumented profiler step (which caller),\nand testing.md (is it a regression?). That gap has a measured cost —\n#1775 lost two sessions to plausible theories about expander.zig because\n`--timings` reported `expand 2765.8ms` and nothing said what to do next.\n\ndocs/dev/performance.md is a runbook in the same genre as fuzzing.md and\nporting.md: find the stage then the caller, measure before theorizing,\nA/B without fooling yourself, check the growth shape. It deliberately\ncarries no numbers — current figures belong to the benchmark dashboard,\npast results to lessons-learned.md section 11, campaign data to the KEP\ndocuments — so it has nothing to rot. Everything already documented\nelsewhere is linked, not restated.\n\nWhile checking what content would be genuinely new, found cache.md\nasserting the opposite of the truth on the one thing A/B measurement\ndepends on:\n\n    Rebuild after any edit -> dirty tree -> build id changes -> miss.\n\n`-dirty` is a flag, not a hash of the working tree (gitBuildId appends\nthe literal suffix whenever `git status --porcelain` prints anything), so\nthe id changes on the first clean->dirty transition and then never again.\nVerified by building two different uncommitted edits at the same commit:\nboth produced `370d8e85-dirty`, so they share .sbc cache entries and one\ncan execute bytecode the other produced. That is the original #1516\nfootgun surviving in the case contributors hit most, and it reads exactly\nlike nondeterminism in the code under test.\n\ncache.md now documents the case the build id does not cover and the\n`kaappi cache clear` remedy; bytecode_file.zig's two comments that\noverstated the same guarantee are corrected. compilerHashFor itself is\ncorrect and its test asserts nothing false — the aliasing is upstream in\nbuild.zig — so neither is changed.\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-27T18:07:46+05:30",
          "tree_id": "49d3ef0436bbb047c6f49ef25ea5298fc872963e",
          "url": "https://github.com/kaappi/kaappi/commit/1792c0e6e53144d6acefffbcbf61ea8f32ee3b00"
        },
        "date": 1785159466960,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.643284,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.788782,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 1.082157,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 5.237931,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006279,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.057462,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.583952,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.073966,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.561667,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 2.393289,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.601622,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.431523,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.803349,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.638421,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.043442,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "9f68a1e376316bdfdc4ea11d2b28b59de61de275",
          "message": "Unwrap usertext markers in the two remaining pattern-spine walks (#1787) (#1790)\n\nThe preceding commit fixed matchListPattern's loop. Two more spine walks\nhad the same gap, and together they were the whole of what actually\nblocked SRFI 148 -- not the free-identifier=?/compound-identifier bug\n#1787 was filed for, which does not exist (see below).\n\nA pattern variable substituted into a NESTED syntax-rules template is\nwrapped as (__hyg-usertext . value) so the generated macro's own later\nexpansion inserts it verbatim instead of re-walking it as template text.\nWhen the substitution target is a list POSITION the wrapper gets its own\ncons cell and every consumer sees it; when the target is a SPINE position\n-- a dotted tail, or the whole pattern -- the wrapper becomes the cdr of\nan existing cell, so a naive walk reads the marker as one more ordinary\nelement. instantiateTemplate and stripUsertextWalk already handled that\nshape; three matching-side walks did not.\n\n  - expandMacro drops the pattern's first element to skip the macro\n    keyword. For a whole rule pattern spliced from user text -- a\n    generator taking (pat tmpl) and emitting (syntax-rules () (pat tmpl))\n    -- that dropped the marker instead, so every position sat one slot\n    late and the user's own `_` keyword placeholder swallowed the first\n    argument. The keyword-name extraction above it read the marker symbol\n    as the macro's name for the same reason.\n\n  - matchEllipsis splits the input by counting the elements the pattern\n    after the ellipsis needs. Counting a marker made it reserve one too\n    many, so the ellipsis stopped one element short -- and the trailing\n    pattern still matched, because the marker symbol behaves like an\n    anonymous pattern variable and binds the element the ellipsis should\n    have taken. That one failed SILENTLY, expanding with a short ellipsis\n    binding and no diagnostic. Fixed in countPairs (both callers walk a\n    marker-bearing spine) and in the repetition walk.\n\nWith all three, every em-syntax-rules-defined macro in a full SRFI 148\nport now expands correctly end-to-end -- em-cons, em-cons*, em-car/cdr,\nem-fold, em-map, em-filter, em-append, em-quasiquote, both identifier\ncomparisons, and custom-ellipsis variants -- where before the fix each\none failed with \"bad arguments to macro call\".\n\n#1787's own headline bug is not real. Its repro writes a bare `...` in a\nmacro template to pass the ellipsis identifier through to\nfree-identifier=?, but a template `...` IS the ellipsis; R7RS spells that\n(... ...), which is what SRFI 148's own em-syntax-rules writes. Kaappi\nexpands a driver-less ellipsis to zero copies in silence, so\n`(free-identifier=? ... (quote t) 'yes 'no)` quietly became\n`((quote t) 'yes 'no)` -- the \"not a procedure\" the issue reports, and\nnothing to do with identifier comparison. chibi-scheme rejects that same\nrepro at definition time with \"too many ...'s\". With the ellipsis escaped\ncorrectly, free-identifier=? and bound-identifier=? already answered\nevery compound-vs-symbol case right, before and after this commit. The\nsilent zero-expansion is a real diagnostic gap, filed separately.\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-27T21:07:39+05:30",
          "tree_id": "ce013bed71210ff6a21f8f1e3ff5823e4aacd0a9",
          "url": "https://github.com/kaappi/kaappi/commit/9f68a1e376316bdfdc4ea11d2b28b59de61de275"
        },
        "date": 1785169000502,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.889281,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.567803,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.889946,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.259545,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006452,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.050988,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.511368,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.067799,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.646429,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.815326,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.455769,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.405469,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.669011,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 0.916351,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.041558,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "d04dc522591d8e94e17690febd578f048178e4eb",
          "message": "Iterate head-position macro chains instead of recursing (#1796) (#1797)\n\n* Iterate head-position macro chains instead of recursing (#1796)\n\nAn expansion that is directly another macro use in the same position —\nSRFI 148's CK-machine steps, or a degenerate (loop) → (loop) — used to\ncompile by native recursion, one compileForm → expandAndCompileMacroUse\n→ compileExpr cycle per link, which made MAX_MACRO_EXPANSION_DEPTH an\nimplicit native-stack guard. Raising it to 4096 (what SRFI 148 seemed\nto need) overflowed the stack; the segfault fired inside the Debug test\nallocator's own stack capture while it held the std.debug SelfInfo\nlock, and the segfault handler then deadlocked on that same lock —\nthe unit suite's eternal 0%-CPU \"hang\". The pre-scan hypothesis from\nthe issue was refuted by profiling: collectSetTargets' own caps are\nindependent of this constant.\n\nexpandAndCompileMacroUse now loops over head-position chain links at\nO(1) native stack, bounded by MAX_MACRO_EXPANSION_STEPS (10,000);\nMAX_MACRO_EXPANSION_DEPTH stays 256 and guards only genuinely nested\nexpansions, which are what actually recurses natively. Per-link\nbookkeeping (temp-globals hygiene dance, injected captured-local\naliases, let-syntax peer swaps, lint suppression) accumulates in\nheap-side undo stacks and unwinds LIFO after the final form compiles,\npreserving the exact lifetimes the nested frames provided — an early\nlink's template identifiers can survive into the final form. Chain\nlinks are rooted via extra_roots; the fixed 1024-slot root stack was a\nsecond latent cliff at one pushRoot per nested level.\n\nDeep chains now just work at the shipped constant: em-member and\nem-set-union from the drafted SRFI 148 port run correctly at 256,\nremoving #1699's final blocker without touching the constant. Runaway\nchains still fail with the same deterministic KP2003, via the step\nlimit.\n\nFixes #1796.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n* Address review: flat per-link cost, emit-failure propagation, temp-globals test\n\n- Rebuild the chain's merged macro view only after a link that actually\n  performed a let-syntax peer swap: nothing else can change any macro\n  table between links (no compilation runs inside the loop), and the\n  unconditional per-link rebuild made a runaway chain's failure path\n  O(links x macros in scope) now that links are bounded by the\n  10,000-step budget instead of 256 nesting levels.\n- Propagate failures in the global-alias emit sequence instead of\n  swallowing them: emitOp(.get_global) succeeding and a later emitU16\n  failing left a truncated instruction in the chunk for the VM to\n  decode as garbage. Register exhaustion stays non-fatal (skips the\n  injection), as before.\n- The divergent-chain test now also asserts the temp-globals dance's\n  chain-wide undo: kick's template references a non-procedure global\n  that expansion temporarily marks VOID (#1208), and the failed compile\n  must restore its value.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-27T21:06:58Z",
          "tree_id": "a804da82f3586fbe6324008264aecdebaf18be66",
          "url": "https://github.com/kaappi/kaappi/commit/d04dc522591d8e94e17690febd578f048178e4eb"
        },
        "date": 1785188877188,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.308292,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 9.089748,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.925309,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.452204,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006671,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.052892,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.512063,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068454,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.38422,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 2.076868,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.531838,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.473256,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.8625,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.760718,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.046137,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "99dc2320e7707bf5a4f09b0dd7bebb5b68ceeeec",
          "message": "Stop the native backend evaluating `apply` in the global environment (#1798)\n\n* Stop the native backend evaluating `apply` in the global environment\n\n`kaappi compile` miscompiled `apply` over any local binding — a procedure\nparameter or a `let`-bound name. The binary linked cleanly and then died at\nrun time:\n\n    (define (s xs) (apply + xs))   ; => undefined variable 'xs'\n\n`call/cc`, `call-with-current-continuation`, `call-with-values` and `eval`\ntook the same broken path.\n\nWhy: `apply` lowers to an ir `.passthrough` node, and `emitPassthrough`\nserializes those to source for `kaappi_eval_cached` — an interpreter eval that\nresolves names in the GLOBAL environment. All four native-compilation gates\n(both closure tiers, tryCompileDefineFunction, emitLet) exist to stop a lexical\nscope being split that way (#827); each asks\n`freevars.sexprNeedsEvalFallback`, which matches head keywords against the\ncomptime-derived `ir.eval_fallback_form_names`.\n\n`apply` was missing from that set. The set derives from `llvm_node_table`,\nwhere `.passthrough` carries `.capability = .native` — right for the one shape\nemitPassthrough compiles (a `(define (f ...) ...)` shorthand), wrong for every\nother, which it evals whole. And because `apply` is an `ir.isKnownGlobal`,\nfree-variable analysis passed it too, so the frame compiled natively and the\neval went looking for `xs` among the globals. A same-named global made it worse\nthan an error: `(define x 100) (define (s x) (apply + (list x)))` silently\nreturned 100.\n\n`isRejectedFormHead` (the #1496 cond/case/do gate) is a second copy of the same\nconcept and was already complete, which is why `(cond ... (else (apply + lst)))`\nworked while a plain body did not.\n\n`ir.other_special_forms` now carries a bool payload — \"an evaluated form headed\nby this keyword becomes a passthrough the interpreter runs\" — and\n`eval_fallback_form_names` appends the true entries, so one list feeds both\nviews. `else`, `=>`, `_`, `...` and `unquote` stay false on purpose:\nsexprNeedsEvalFallback recurses blindly into sub-forms, so listing `else` would\nreject every natively lowered cond/case with an else clause. `isSpecialForm`\nignores the payload, leaving vm_library.zig and compiler_macro.zig unchanged.\n\nRepublishing the frame as globals (bindParamsAsGlobals, the #1410 mechanism the\nletrec/let fallbacks use) is not an alternative: it cannot see let-locals,\naliases across activations, and clobbers same-named globals. Declining the frame\nkeeps the interpreter's lexical scope authoritative.\n\nThe cost is that a function using `apply` is no longer natively compiled at all.\nDeliberate, documented in docs/dev/llvm-backend.md, and closable later by\nlowering `apply` natively.\n\nTests: a compile-suite script running ten shapes — parameter, let-bound name,\nbare top-level let, computed operator, fixed-args-plus-list, rest parameter,\nrecursion, closure capture, global-not-clobbered, and a summary-statistics\nprogram — each comparing the compiled binary against the interpreter, so it\nstays valid if `apply` is later lowered natively. Plus six emit-level tests\nincluding a direct assertion on the derived name set and its exclusions.\nMutation-tested: 9/10 shell cases and all 6 unit tests fail without the fix.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Reference issue #1799 in the apply lexical-scope fix\n\nThe regression test, its emit-level counterparts, and the surrounding comments\ncarried no issue number: none was filed when the fix landed. Stamp #1799 in and\nrename the compile-suite script to match the repo's convention of naming a\nregression test after the bug it pins.\n\nNo behavior change.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n* Address review: fail on a nonzero compile, drop future work from the guide\n\nThree findings from CodeRabbit on #1798, all in the new material:\n\n- The regression script ran `kaappi compile` under `|| true` and then judged\n  success by whether an executable existed. A compile that reported an error\n  but still left an executable behind would have passed as a green run, and a\n  genuine compiler rejection was reported as \"did not produce a binary\" with\n  its diagnostics discarded. Capture the status and the output, and fail on\n  either a nonzero exit or a missing binary, with the two spelled differently.\n\n- docs/dev/llvm-backend.md described how a future native `apply` lowering would\n  work. docs/dev/CLAUDE.md says roadmap and future work belong in issues, not\n  guides, because such sections rot. Cut it back to the limitation that exists\n  today; the design sketch lives in the PR discussion.\n\n- A line beginning `#1410` reads as an ATX heading (markdownlint MD018).\n  Reflowed, and spelled `kaappi#1410` to match the rest of the file.\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Opus 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-28T06:35:50+05:30",
          "tree_id": "483d1ceccb31184c5662b7f86542618565d69f7f",
          "url": "https://github.com/kaappi/kaappi/commit/99dc2320e7707bf5a4f09b0dd7bebb5b68ceeeec"
        },
        "date": 1785203048845,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 3.141848,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 7.54666,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.720374,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 3.410146,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.005231,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.040702,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.394673,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.053347,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 2.581524,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.517367,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.197731,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.37123,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.354078,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.500626,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.035783,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "ea71d9a5d04053bd2df83be7fd25b5fd8d5f1303",
          "message": "Stop ReleaseSafe memsetting the expander's 1MB buffers on every expansion (#1802) (#1804)\n\n* Stop ReleaseSafe memsetting the expander's 1MB buffers on every expansion (#1802)\n\nCompiling SRFI 148's 134-definition library took 80 seconds before a\nsingle combinator ran. A sample profile put 96% of it in _memset: Zig\n0.16's ReleaseSafe fills every plain `= undefined` local with 0xAA, and\nthe expander declares three ~1MB [MAX_BINDINGS]Binding scratch buffers\nper call (expandMacro, matchEllipsis, instantiateEllipsis). The\n`b: { @setRuntimeSafety(false); break :b undefined; }` initializer those\nsites used to suppress the fill now does the opposite: it materializes a\nruntime undefined value whose store into the local gets the fill anyway.\nThe only shape that works is @setRuntimeSafety(false) at the scope of\nthe declaration, so each function now declares its buffers under a\nsafety-off function scope and runs its entire body in a\n@setRuntimeSafety(true) block, keeping index/overflow checks intact.\n\nThe remaining cost was the set! pre-scan (#1775) treating transformer\nspecs as runtime code: `(define-syntax em-cadr (em-syntax-rules ...))`\nspeculatively ran the whole CK machine per definition, burning the full\n4096-expansion budget - and with it the truncation fallback that boxes\nevery local - on forms that produce no runtime code at all. A spec only\never resolves to a transformer object, so collectSetTargets now walks\ndefine-syntax/let-syntax/letrec-syntax spec positions without expanding\nmacros (still catching literal set!s in templates); let-syntax bodies\nkeep the budgeted scan. A set! that only materializes when the spec's\nown macros run is caught at the macro's real use site - the same\ncorrect-late Part B path every divergent best-effort expansion already\ntakes.\n\nImport of the drafted (srfi 148): 86.6s -> 0.07s; its full upstream\nreference suite now runs in 0.85s (134 expected passes, 8 known\nxfails), far under run-all.sh's 60s per-file timeout that blocked it.\nBoth prescan regression tests fail without the collectSetTargets change\n(verified by mutation); the buffer-fill half is pinned by disassembly\n(no 0xAA memset in the three functions) and documented in\ndocs/dev/performance.md's new \"profile bottoms out in memset\" entry.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n* Walk let-syntax specs per binding so special-form names can't derail the scan\n\nCodeRabbit review follow-up on #1804: collectSetTargets' let-syntax\nbranch walked the whole bindings list, so a binding pair whose NAME is a\nspecial-form identifier was misread as a form - a binding literally\nnamed `quote` early-returned before its own transformer spec was\nscanned. Iterate the binding pairs and walk only each spec.\n\nVerified end-to-end before committing: the review's predicted\nmiscompilation does not actually reproduce today - its proposed\ntemplate `(set! a b)` holds only pattern variables (nothing literal to\nfind), and with a literal `(set! + -)` template the sibling\n`(+ 5 2)` still isn't folded because a let-syntax body compiles through\nthe passthrough path, while a late-discovered set! target is still\nboxed correctly via the box_local transition. So this is scan hygiene,\nnot a user-visible fix. The new hygiene suite file pins the late-boxing\nself-heal this relies on (it hangs, not fails, if that regresses) plus\nthe quote-named-macro rebinding shape.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-28T10:11:45+05:30",
          "tree_id": "46f30bc26e89b778ba25e1564e4c21b81ce39d5e",
          "url": "https://github.com/kaappi/kaappi/commit/ea71d9a5d04053bd2df83be7fd25b5fd8d5f1303"
        },
        "date": 1785216074884,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.343984,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.460086,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.935018,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.496567,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006335,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.054797,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.521714,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.071824,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.666616,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 2.018021,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.619229,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.431582,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.814259,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.661657,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044358,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "82da81378c730bfd21d68861d6174d3b7ad27c07",
          "message": "Lower apply natively in the LLVM backend (#1803) (#1805)\n\nOne apply anywhere in a body used to send the whole enclosing function to\nthe interpreter (the #1799 fix was correct but all-or-nothing): ~19x on\nthe issue's arithmetic-loop reproducer, hit precisely by idiomatic code\nlike (apply + xs). Only apply itself needs the runtime — the enclosing\nframe can keep its native compilation.\n\nA new C-ABI entry point, kaappi_apply, is primitives.applyFn minus the\nargument shuffling: same procedure validation, same tortoise-and-hare\nproper-list check (a circular list raises instead of hanging), same\ntypeError texts, then callWithArgs on the spliced arguments.\nemitPassthrough routes an (apply …) head inside a lexical scope to\nemitApplyForm, which mirrors the interpreter's dispatch case for case:\ntail + unshadowed + ≥2 operands is structural builtin apply (the\ntail_apply opcode ignores a top-level rebinding of apply, so the fast\npath deliberately does too — an earlier draft that honored the rebinding\neverywhere diverged from the interpreter); tail with too few operands\nabandons native compilation so the interpreter raises its compile-time\nInvalidSyntax; every other resolvable shape is an ordinary indirect call\nthrough whatever apply denotes in scope. Tail sites balance the frame's\nGC roots before the ret, as emitCallNode does.\n\nFlipping apply out of eval_fallback_form_names exposed a latent trap:\nthe free-variable analyses treated every .passthrough node as\ncapture-free, sound only while all passthrough keywords also declined\nthe enclosing scope. Both walks now descend into apply operands, so a\nclosure capturing a variable used inside one gets its upvalue instead\nof a silent global lookup — #1799's failure mode in a new spot.\n\nThe #1799 parity suite passes unchanged, as designed. The new 1803 suite\nadds rebinding/shadowing/error/GC-stress shapes plus the structural\nconvergence check (zero eval fallbacks in the reproducer's IR); the\nissue's heavy pair now times identically (0.12s vs 0.12s, was ~19x).\nThe 1376 callback test's case 8 gets a transparent (letrec ()) wrapper:\napply no longer forces the eval fallback it relied on to exercise\nbytecode tail_apply against a NativeClosure (do stopped forcing it back\nin #1496), so the wrapper restores the documented coverage.\n\nCloses #1803\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-28T10:25:56+05:30",
          "tree_id": "b9c6be37e0c710d8e6a4b000ca9f22c23d9b5322",
          "url": "https://github.com/kaappi/kaappi/commit/82da81378c730bfd21d68861d6174d3b7ad27c07"
        },
        "date": 1785217240742,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.620529,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.602131,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.949782,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.665131,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006392,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.055096,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.547801,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.071313,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.489774,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 2.067353,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.607374,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.436683,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.806248,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.632656,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044128,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "ff6cffd5f9fb375a04e2db435657c7d90b6051a0",
          "message": "Add SRFI 148 (eager syntax-rules), completing issue #1699's portable set (#1806)\n\nlib/srfi/148.sld is a pure portable port of the reference implementation\n(Marc Nieper-Wisskirchen, 2016, MIT): the CK-machine core, the portable\nidentifier-comparison helpers, and ~110 em- combinators combined into one\n134-definition library body. em-syntax-rules and several combinators\nresolve through SRFI 147's begin-wrapped define-syntax mechanism - this\nSRFI is why 147 was implemented. No engine changes ship here; the six\nengine bugs 148 surfaced were fixed separately (#1776/#1779 template\nunwrap gaps, #1787/#1790 usertext-marker spine gaps, #1796/#1797 the\nhead-position chain depth wall, #1802/#1804 the compile-cost cliff that\nmade the bare import cost 87 seconds - it now costs ~0.07s).\n\nThe port fixes 4 real, confirmed bugs in the reference implementation\nitself, none covered by its own test suite (em-append-map's stray `map`\ntoken; em-set-intersection and em-set-difference dropping 'compare in\ntheir 3+-list recursions; em-set= vacuously #t for 3+ arguments) - all\ndocumented with evidence in the library header, alongside the\n:call/:prepare workaround for Kaappi's zero-clause syntax-rules\nrestriction.\n\ntests/scheme/srfi/srfi148.scm is the reference's own test.sld ported\nverbatim (134 expected passes, 0.9s), with 8 test-expect-fail entries\nciting the two remaining general engine bugs #1800 and #1801. The\nfeatures/cond-expand surface needs no listing anywhere: the build-time\nlib/srfi scan and the derived srfi-<n> probe pick the new file up on\nrebuild (verified: `kaappi features` reports portable (160) including\n148, and (cond-expand (srfi-148 ...)) selects it).\n\nRefs #1699 (72, 211, 213 remain tracked there).\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-28T11:05:43+05:30",
          "tree_id": "00c6c043f04ee729ea98c5eb6ed2bea84345141c",
          "url": "https://github.com/kaappi/kaappi/commit/ff6cffd5f9fb375a04e2db435657c7d90b6051a0"
        },
        "date": 1785219482633,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.520862,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.531307,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.933436,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.574719,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006415,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.053633,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.508907,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.07046,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.536592,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.960708,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.605763,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.440773,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.830052,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.680032,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044315,
            "unit": "seconds"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
            "name": "Baiju Muthukadan",
            "username": "baijum"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "1fdb18b46d253cfa4e6bfbad5fb5f0fff13b4202",
          "message": "Add SRFI 211 and 213 on a procedural-macro mechanism, resolving issue #1699 (#1811)\n\n* Add SRFI 211 and 213 on a procedural-macro mechanism, resolving issue #1699\n\nIssue #1699's remaining trio (72, 211, 213) all needed one engine\ncapability the portable slices couldn't provide: macro transformers that\nare Scheme procedures run at expansion time. This adds that mechanism and\nuses it to ship SRFI 211 (as the three sub-libraries this engine can\nprovide whole: explicit-renaming, define-macro, syntax-parameter — the\nSRFI explicitly permits a subset of libraries, each complete) and SRFI 213\n(define-property with the capture-lookup re-entry protocol; capture-lookup\nis the identity, which the spec explicitly sanctions).\n\nSRFI 72 is excluded rather than implemented: the issue table's \"explicit\nrenaming macros\" note was a mislabel — 72 is van Tonder's *replacement*\nmacro system (arbitrary transformer expressions evaluated over a\nsyntax-object type with its own hygiene rule and phase tower), which would\nchange the semantics of every existing define-syntax and conflicts with\nthe structural transformer-spec direction SRFI 147 already established\nhere. The ER facility the issue actually wanted is exactly\n(srfi 211 explicit-renaming). SRFI 150 moves the other way: its exclusion\nrationale (needs SRFI 147+148) went stale when both shipped, so it is now\ntracked in #1810 instead — the excluded count stays 30, implemented goes\n175 -> 177.\n\nMechanism notes (details in CLAUDE.md's new paragraph and the .sld\nheaders): Transformer gains a kind tag + GC-traced proc; transformer-spec\nrecognition is structural with the argument evaluated at definition time\nin the global environment (phase separation); ER rename reuses\nrenameForHygiene under a fresh per-invocation scope, giving procedural\nmacros exactly the hygiene strength syntax-rules templates have (verified\nequivalent, including the shared use-site-redefinition limitation); and\nvm_library's import-time free-reference copying gains a whole-def-env mode\nfor procedural transformers, whose references are computed by running code\n— without it, (rename 'lib-helper) resolved at the definition site but\ndied \"undefined variable\" at the use site.\n\nCONFORMANCE.md's portable table was also reconciled while adding the new\nrows: it had silently drifted six SRFIs behind lib/srfi/ (139, 147, 148,\n149, 231 were missing — four of them this same issue's earlier slices).\n\nCloses #1699.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n* Record the procedural-transformer path in the understanding map\n\nThe expander-hygiene core-tier entry's theory now includes the SRFI\n211/213 mechanism PR #1811 adds — it is new mandatory model for anyone\njudging macro bugs there.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Fable 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-28T13:52:57+05:30",
          "tree_id": "3b9023cda62ff2bb56cad1c1e75c4e4f3240e72f",
          "url": "https://github.com/kaappi/kaappi/commit/1fdb18b46d253cfa4e6bfbad5fb5f0fff13b4202"
        },
        "date": 1785229482993,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.384986,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.68495,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.922153,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.552233,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006357,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.053839,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.519883,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.068995,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.595461,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 2.005348,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.617643,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.435055,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.832394,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.636874,
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
          "id": "4e03b6100c3a0bb0b9a9f119e6fc57c4a94299bd",
          "message": "Keep a macro-expanded body-position define's local alive (#1800) (#1815)\n\nA macro use whose expansion is a bare (define x v) in body position\nraised \"undefined variable\" for later references to x. Root cause:\nexpandAndCompileMacroUse's post-expansion cleanup unconditionally\npopped every compiler local added while compiling the macro's final\nexpanded form, on the assumption that everything added during a\nmacro-use compile is transient chain bookkeeping (hygienic aliases).\ncompileDefine's in_body_scope branch adds a real, sibling-visible\nlocal when the expansion is a definition, and that local needs to\nsurvive the call returning; only the aliases injected earlier in the\nchain (for R7RS 4.3.1 referential transparency) are truly transient.\n\nFixes 6 SRFI 148 assertions previously quarantined behind\ntest-expect-fail and one SRFI 251 \"known gap\" test that turned out to\nbe the same underlying bug reached via a nested lambda scope.\n\nCo-authored-by: Claude Sonnet 5 <noreply@anthropic.com>",
          "timestamp": "2026-07-28T14:52:18+05:30",
          "tree_id": "12b6abd2a056d8136f593b49fa5543d851eb45d0",
          "url": "https://github.com/kaappi/kaappi/commit/4e03b6100c3a0bb0b9a9f119e6fc57c4a94299bd"
        },
        "date": 1785232879334,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "fib",
            "value": 4.357095,
            "unit": "seconds"
          },
          {
            "name": "nqueens",
            "value": 8.318527,
            "unit": "seconds"
          },
          {
            "name": "primes",
            "value": 0.898703,
            "unit": "seconds"
          },
          {
            "name": "tak",
            "value": 4.431105,
            "unit": "seconds"
          },
          {
            "name": "string",
            "value": 0.006332,
            "unit": "seconds"
          },
          {
            "name": "list",
            "value": 0.053826,
            "unit": "seconds"
          },
          {
            "name": "vector",
            "value": 0.505236,
            "unit": "seconds"
          },
          {
            "name": "hashtable",
            "value": 0.069682,
            "unit": "seconds"
          },
          {
            "name": "continuations",
            "value": 3.562518,
            "unit": "seconds"
          },
          {
            "name": "tailcall",
            "value": 1.924202,
            "unit": "seconds"
          },
          {
            "name": "closures",
            "value": 1.612222,
            "unit": "seconds"
          },
          {
            "name": "bignum",
            "value": 0.434651,
            "unit": "seconds"
          },
          {
            "name": "gc-pressure",
            "value": 1.822359,
            "unit": "seconds"
          },
          {
            "name": "call_cc",
            "value": 1.66723,
            "unit": "seconds"
          },
          {
            "name": "call_ec",
            "value": 0.044568,
            "unit": "seconds"
          }
        ]
      }
    ]
  }
}