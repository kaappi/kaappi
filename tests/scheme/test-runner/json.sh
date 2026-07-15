#!/bin/bash
# `kaappi test --json` structured-output tests (kaappi#1509).
#
# `kaappi test` discovers SRFI-64 suites, runs each in an isolated worker, and
# aggregates results from the runner's own counters. `--json` emits JSON Lines:
# one object per file plus a summary. We validate with a *real* JSON parser
# (python3), not grep — a malformed object or any stray text leaking onto stdout
# fails here.
#
# Fixtures are generated in a temp dir so an intentionally-failing suite never
# pollutes a plain `kaappi test ./tests` run of the repo.

set -euo pipefail

KAAPPI="${KAAPPI:-zig-out/bin/kaappi}"

if ! command -v python3 >/dev/null 2>&1; then
    echo "FAIL: python3 is required to validate kaappi test --json output"
    exit 1
fi

# Absolute path so the worker (spawned with an arbitrary cwd) resolves it.
KAAPPI="$(cd "$(dirname "$KAAPPI")" && pwd)/$(basename "$KAAPPI")"

FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT

cat > "$FIX/a-pass.scm" <<'EOF'
(import (scheme base) (srfi 64))
(test-begin "pass-suite")
(test-equal "one plus one" 2 (+ 1 1))
(test-assert "greater" (> 3 2))
(test-end "pass-suite")
EOF

cat > "$FIX/b-fail.scm" <<'EOF'
(import (scheme base) (scheme process-context) (srfi 64))
(test-begin "fail-suite")
(test-equal "wrong sum" 5 (+ 2 2))
(test-equal "right sum" 4 (+ 2 2))
(let ((r (test-runner-current)))
  (test-end "fail-suite")
  ;; A failure epilogue that exits nonzero — the runner must report this as a
  ;; test failure, not lose the file, and not treat the (exit) as a file error.
  (when (> (test-runner-fail-count r) 0) (exit 1)))
EOF

cat > "$FIX/c-error.scm" <<'EOF'
(import (scheme base) (srfi 64))
(test-begin "error-suite")
(test-equal "before error" 1 1)
(car '())            ; uncaught top-level error
(test-end "error-suite")
EOF

cat > "$FIX/d-skip-xfail.scm" <<'EOF'
(import (scheme base) (srfi 64))
(test-begin "skip-xfail-suite")
(test-skip "skipped")
(test-assert "skipped" #f)
(test-expect-fail "known-broken")
(test-assert "known-broken" #f)
(test-assert "ordinary pass" #t)
(test-end "skip-xfail-suite")
EOF

status=0
OUT="$("$KAAPPI" test --json "$FIX" 2>/dev/null)" || status=$?

KT_OUT="$OUT" KT_STATUS="$status" python3 - <<'PY'
import json, os, sys

out = os.environ["KT_OUT"]
status = int(os.environ["KT_STATUS"])

passed = failed = 0
def check(cond, label, detail=""):
    global passed, failed
    if cond:
        print(f"PASS: {label}"); passed += 1
    else:
        print(f"FAIL: {label}  {detail}"); failed += 1

lines = [l for l in out.splitlines() if l.strip()]

# Every stdout line must be valid JSON — this is how a stray print leaking onto
# stdout (which would corrupt a machine consumer's stream) is caught.
objs = []
ok = True
for l in lines:
    try:
        objs.append(json.loads(l))
    except json.JSONDecodeError as e:
        ok = False
        check(False, "every stdout line is valid JSON", f"{e}: {l!r}")
        break
if ok:
    check(True, "every stdout line is valid JSON")

files = {os.path.basename(o["file"]): o for o in objs if o.get("type") == "file"}
summaries = [o for o in objs if o.get("type") == "summary"]

check(len(files) == 4, "one object per discovered file", f"got {sorted(files)}")
check(len(summaries) == 1, "exactly one summary object", f"got {len(summaries)}")

a = files.get("a-pass.scm", {})
check(a.get("pass") == 2 and a.get("fail") == 0 and a.get("error") is False,
      "passing file: pass=2 fail=0 error=false", str(a))
check(a.get("suite") == "pass-suite", "suite name captured from test-begin", str(a.get("suite")))
check(a.get("tests") == 2, "tests count = pass+fail+...", str(a.get("tests")))
check(isinstance(a.get("duration_ms"), (int, float)), "duration_ms is numeric", str(a.get("duration_ms")))

b = files.get("b-fail.scm", {})
check(b.get("fail") == 1 and b.get("pass") == 1, "failing file: fail=1 pass=1", str(b))
check(b.get("error") is False, "an (exit 1) failure epilogue is NOT a file error", str(b.get("error")))
fl = b.get("failures", [])
check(len(fl) == 1, "one recorded failure", str(fl))
if fl:
    f0 = fl[0]
    check(f0.get("name") == "wrong sum", "failure carries the test name", str(f0.get("name")))
    check(f0.get("expected") == "5" and f0.get("actual") == "4",
          "failure carries expected/actual", str(f0))

c = files.get("c-error.scm", {})
check(c.get("error") is True, "errored file: error=true", str(c.get("error")))
check(bool(c.get("error_message")), "errored file surfaces a diagnostic message", str(c.get("error_message")))
check(c.get("pass") == 1, "counts before the error are still reported", str(c.get("pass")))

d = files.get("d-skip-xfail.scm", {})
check(d.get("skip", 0) >= 1, "skipped test counted as skip", str(d))
check(d.get("xfail", 0) >= 1, "expected-fail counted as xfail", str(d))
check(d.get("pass", 0) >= 1, "ordinary pass still counted", str(d))

if summaries:
    s = summaries[0]
    check(s.get("files") == 4, "summary files=4", str(s.get("files")))
    check(s.get("errors") >= 1, "summary errors>=1", str(s.get("errors")))
    check(s.get("fail") >= 1, "summary fail>=1", str(s.get("fail")))
    check(isinstance(s.get("seed"), int), "summary carries an integer seed", str(s.get("seed")))
    total = s["pass"] + s["fail"] + s["xpass"] + s["xfail"] + s["skip"]
    check(s.get("tests") == total, "summary tests = sum of kinds", str(s))

check(status != 0, "exit status nonzero when a test failed or a file errored", f"status={status}")

print()
print(f"Passed: {passed}")
print(f"Failed: {failed}")
sys.exit(1 if failed else 0)
PY

echo "All kaappi test --json tests pass."
