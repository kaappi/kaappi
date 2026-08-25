window.BENCHMARK_DATA = {
  "lastUpdate": 1787626542885,
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
      },
      {
        "commit": {
          "author": {
            "email": "baiju.m.mail@gmail.com",
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
      }
    ]
  }
}