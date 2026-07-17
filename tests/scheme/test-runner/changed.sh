#!/bin/bash
# `kaappi test --changed` / `--list-affected` affected-test selection (kaappi#1510).
#
# R7RS makes the file-level dependency graph derivable from `import`/`include`
# declarations, so `kaappi test` can run only the suites a change touches. This
# test builds a throwaway git repo with a known dependency shape — a diamond
# import, an `include`d file, a `(load …)` escape hatch — and checks that the
# right suites are selected, that untrackable edges force a suite to run, and
# that every "can't be sure" case falls back to a full run loudly.
#
# The fixture is an isolated git repo in a temp dir; nothing here touches the
# kaappi repo's own git state.

set -euo pipefail

KAAPPI="${KAAPPI:-zig-out/bin/kaappi}"

if ! command -v git >/dev/null 2>&1; then
    echo "FAIL: git is required for kaappi test --changed tests"
    exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
    echo "FAIL: python3 is required to validate --json output"
    exit 1
fi

# Absolute path so the runner resolves it regardless of the fixture cwd.
KAAPPI="$(cd "$(dirname "$KAAPPI")" && pwd)/$(basename "$KAAPPI")"

FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT

passed=0
failed=0
check() { # check <condition-exit-code> <label> [detail]
    if [ "$1" -eq 0 ]; then
        echo "PASS: $2"; passed=$((passed + 1))
    else
        echo "FAIL: $2  ${3:-}"; failed=$((failed + 1))
    fi
}
has()  { printf '%s\n' "$1" | grep -qxF "$2"; }  # exact-line match in a list

# ── Build the fixture repo ─────────────────────────────────────────────
mkdir -p "$FIX/lib/mylib" "$FIX/tests"

# Diamond: test-a → (mylib top) → (mylib leaf).
cat > "$FIX/lib/mylib/leaf.sld" <<'EOF'
(define-library (mylib leaf)
  (import (scheme base))
  (export leaf-val)
  (begin (define (leaf-val) 42)))
EOF
cat > "$FIX/lib/mylib/top.sld" <<'EOF'
(define-library (mylib top)
  (import (scheme base) (mylib leaf))
  (export top-val)
  (begin (define (top-val) (leaf-val))))
EOF
cat > "$FIX/tests/test-a.scm" <<'EOF'
(import (scheme base) (srfi 64) (mylib top))
(test-begin "a")
(test-equal "top" 42 (top-val))
(test-end "a")
EOF

# Independent suite — depends on no fixture-local source.
cat > "$FIX/tests/test-b.scm" <<'EOF'
(import (scheme base) (srfi 64))
(test-begin "b")
(test-equal "plain" 1 1)
(test-end "b")
EOF

# `include`d file — tracked, resolved relative to the including file.
cat > "$FIX/tests/inc-helper.scm" <<'EOF'
(define (inc-val) 5)
EOF
cat > "$FIX/tests/test-inc.scm" <<'EOF'
(import (scheme base) (srfi 64))
(include "inc-helper.scm")
(test-begin "inc")
(test-equal "included" 5 (inc-val))
(test-end "inc")
EOF

# `(load …)` — an untrackable edge: the suite must be forced to run.
cat > "$FIX/loaded-helper.scm" <<'EOF'
(define (loaded-val) 7)
EOF
cat > "$FIX/tests/test-load.scm" <<'EOF'
(import (scheme base) (srfi 64) (scheme load))
(load "loaded-helper.scm")
(test-begin "load")
(test-equal "loaded" 7 (loaded-val))
(test-end "load")
EOF

git -C "$FIX" init -q
git -C "$FIX" config user.email test@example.com
git -C "$FIX" config user.name test
# Hermetic line endings: a host git with core.autocrlf=true (the Git for
# Windows default) would rewrite the fixtures on checkout and leave every
# file permanently diff-dirty, breaking the "nothing changed" steps.
git -C "$FIX" config core.autocrlf false
git -C "$FIX" add -A
git -C "$FIX" commit -qm init

run() { (cd "$FIX" && "$KAAPPI" test "$@"); }

# ── 1. Diamond: touching the leaf library affects only its dependents ───
printf '\n;; touched\n' >> "$FIX/lib/mylib/leaf.sld"
AFF="$(run --list-affected --lib-path ./lib 2>/dev/null)"
has "$AFF" "tests/test-a.scm"; check $? "leaf change affects test-a (transitive via top)" "$AFF"
! has "$AFF" "tests/test-b.scm"; check $? "leaf change does not affect independent test-b" "$AFF"
! has "$AFF" "tests/test-inc.scm"; check $? "leaf change does not affect test-inc" "$AFF"
git -C "$FIX" checkout -q -- lib/mylib/leaf.sld

# ── 2. include: touching an included file affects the includer ─────────
printf '\n;; touched\n' >> "$FIX/tests/inc-helper.scm"
AFF="$(run --list-affected --lib-path ./lib 2>/dev/null)"
has "$AFF" "tests/test-inc.scm"; check $? "include change affects test-inc" "$AFF"
! has "$AFF" "tests/test-a.scm"; check $? "include change does not affect test-a" "$AFF"
git -C "$FIX" checkout -q -- tests/inc-helper.scm

# ── 3. load: an incomplete graph forces the suite to run, always ───────
AFF="$(run --list-affected --lib-path ./lib 2>/dev/null)"      # nothing changed
NOTE="$(run --list-affected --lib-path ./lib 2>&1 1>/dev/null)"
has "$AFF" "tests/test-load.scm"; check $? "load-using suite runs even with no change (incomplete graph)" "$AFF"
! has "$AFF" "tests/test-a.scm"; check $? "graph-complete suites skipped when nothing changed" "$AFF"
printf '%s' "$NOTE" | grep -q "incomplete"; check $? "stderr names the forced suite as incomplete" "$NOTE"

# ── 4. Clean exit status when the affected set is empty of failures ─────
set +e; run --changed --lib-path ./lib >/dev/null 2>&1; rc=$?; set -e
check "$rc" "clean tree → --changed exits 0" "rc=$rc"

# ── 5. --list-affected --json shape ────────────────────────────────────
printf '\n;; touched\n' >> "$FIX/lib/mylib/leaf.sld"
JSON="$(run --list-affected --json --lib-path ./lib 2>/dev/null)"
KT_JSON="$JSON" python3 - <<'PY'
import json, os, sys
o = json.loads(os.environ["KT_JSON"].strip())
ok = (o.get("type") == "affected" and o.get("full_run") is False
      and "tests/test-a.scm" in o.get("files", [])
      and o.get("count") == len(o.get("files", [])))
sys.exit(0 if ok else 1)
PY
check $? "--list-affected --json: type=affected, full_run=false, includes test-a" "$JSON"

# ── 6. --changed --json runs exactly the affected subset ───────────────
CH="$(run --changed --json --lib-path ./lib 2>/dev/null)"
KT_CH="$CH" python3 - <<'PY'
import json, os, sys
lines = [l for l in os.environ["KT_CH"].splitlines() if l.strip()]
objs = [json.loads(l) for l in lines]
files = [o for o in objs if o.get("type") == "file"]
summ = [o for o in objs if o.get("type") == "summary"]
names = {os.path.basename(o["file"]) for o in files}
# test-a (changed) and test-load (forced) run; test-b and test-inc do not.
ok = (summ and summ[0]["files"] == len(files)
      and "test-a.scm" in names and "test-b.scm" not in names
      and "test-inc.scm" not in names)
sys.exit(0 if ok else 1)
PY
check $? "--changed --json runs only the affected subset (test-a + forced test-load)" "$CH"
git -C "$FIX" checkout -q -- lib/mylib/leaf.sld

# ── 7. Native/FFI artifact change → loud full run ──────────────────────
mkdir -p "$FIX/csrc"; echo 'int x;' > "$FIX/csrc/helper.c"      # untracked
AFF="$(run --list-affected --lib-path ./lib 2>/dev/null)"
NOTE="$(run --list-affected --lib-path ./lib 2>&1 1>/dev/null)"
has "$AFF" "tests/test-b.scm"; check $? "csrc change forces a full run (independent test-b included)" "$AFF"
printf '%s' "$NOTE" | grep -q "native/FFI artifact changed"; check $? "stderr explains the native-artifact full run" "$NOTE"
rm -rf "$FIX/csrc"

# ── 8. Unknown revision → loud full run ────────────────────────────────
AFF="$(run --list-affected --since no-such-rev --lib-path ./lib 2>/dev/null)"
NOTE="$(run --list-affected --since no-such-rev --lib-path ./lib 2>&1 1>/dev/null)"
has "$AFF" "tests/test-b.scm"; check $? "unknown --since revision forces a full run" "$AFF"
printf '%s' "$NOTE" | grep -q "running all"; check $? "stderr explains the unknown-revision full run" "$NOTE"

# ── 9. A brand-new untracked suite counts as changed ───────────────────
cat > "$FIX/tests/test-new.scm" <<'EOF'
(import (scheme base) (srfi 64))
(test-begin "new") (test-assert #t) (test-end "new")
EOF
AFF="$(run --list-affected --lib-path ./lib 2>/dev/null)"
has "$AFF" "tests/test-new.scm"; check $? "untracked new suite is treated as changed" "$AFF"
rm -f "$FIX/tests/test-new.scm"

# ── 10. --since without a selection mode is a usage error ──────────────
set +e; run --since HEAD --lib-path ./lib >/dev/null 2>&1; rc=$?; set -e
check "$([ "$rc" -eq 2 ] && echo 0 || echo 1)" "--since without --changed/--list-affected is a usage error" "rc=$rc"

echo
echo "Passed: $passed"
echo "Failed: $failed"
[ "$failed" -eq 0 ] || exit 1
echo "All kaappi test --changed tests pass."
