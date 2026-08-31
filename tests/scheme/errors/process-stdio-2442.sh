#!/bin/bash
# Regression tests for the (kaappi process) stdio-plumbing findings of the
# kaappi#2442 review — behaviors only visible when the PARENT's own standard
# descriptors are arranged by the harness, which a .scm-only suite cannot do:
#
#   1. 'inherit must actually pass the parent's stdio through. Darwin's
#      POSIX_SPAWN_CLOEXEC_DEFAULT closes even fds 0..2 unless a file action
#      names them, so before the addinherit_np actions a plain spawn lost
#      all three streams.
#   2. A stdout/stderr SWAP via caller ports must swap. The file actions run
#      sequentially in the child, so un-staged low-fd sources read whatever
#      an earlier dup2 just installed — both streams landed on the original
#      stderr.
#   3. Spawning with a standard descriptor CLOSED in the parent must still
#      work. pipe(2) then hands back fd 0/1/2, and an un-normalized pipe end
#      in a stdio slot corrupts the dup2/close action pair for that slot.
#
# The whole file is POSIX-only, like the library it tests.

set -euo pipefail

. "$(dirname "$0")/../shell-common.sh"
skip_on_windows "(kaappi process) is POSIX-only until KEP-0022 Phase 3"

KAAPPI="${1:-zig-out/bin/kaappi}"
case "$KAAPPI" in
    /*) ;;
    *) KAAPPI="$PWD/$KAAPPI" ;;
esac
DIR="$(mktemp -d)"
trap 'rm -rf "$DIR"' EXIT
PASS=0
FAIL=0

ok()   { echo "PASS: $1"; PASS=$((PASS + 1)); }
bad()  { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

# The library gate: exit 77 (suite SKIP) only on the DISTINCT status the
# gate program reserves for "library absent" — any other failure (a broken
# binary, a startup error) must fail the suite, not silently skip all three
# regressions (kaappi#2442 review).
printf '(import (scheme base) (scheme process-context))\n(cond-expand ((library (kaappi process)) (exit 0)) (else (exit 9)))\n' > "$DIR/gate.scm"
gate_status=0
"$KAAPPI" "$DIR/gate.scm" >/dev/null 2>&1 || gate_status=$?
if [[ "$gate_status" -eq 9 ]]; then
    echo "SKIP: (kaappi process) not available on this target"
    exit 77
elif [[ "$gate_status" -ne 0 ]]; then
    echo "FAIL: gate program exited $gate_status (neither available nor the absent marker)"
    exit 1
fi

# --- 1. 'inherit passes the parent's stdio through, with real content -------
cat > "$DIR/inherit.scm" <<'SCM'
(import (scheme base) (kaappi process))
(let ((p (spawn-process '("/bin/sh" "-c" "echo CHILD-OUT; echo CHILD-ERR 1>&2"))))
  (exit (if (equal? 0 (process-wait p)) 0 1)))
SCM
if "$KAAPPI" "$DIR/inherit.scm" > "$DIR/inherit.out" 2> "$DIR/inherit.err" \
    && grep -q '^CHILD-OUT$' "$DIR/inherit.out" \
    && grep -q '^CHILD-ERR$' "$DIR/inherit.err"; then
    ok "'inherit delivers the child's stdout and stderr to the parent's streams"
else
    bad "'inherit lost child output (stdout: '$(cat "$DIR/inherit.out")', stderr: '$(cat "$DIR/inherit.err")')"
fi

# --- 2. stdout/stderr swap through the parent's own stdio ports -------------
cat > "$DIR/swap.scm" <<'SCM'
(import (scheme base) (kaappi process))
(let ((p (spawn-process '("/bin/sh" "-c" "echo OUT; echo ERR 1>&2")
                        'stdout: (current-error-port)
                        'stderr: (current-output-port))))
  (exit (if (equal? 0 (process-wait p)) 0 1)))
SCM
if "$KAAPPI" "$DIR/swap.scm" > "$DIR/swap.out" 2> "$DIR/swap.err" \
    && grep -q '^ERR$' "$DIR/swap.out" && ! grep -q '^OUT$' "$DIR/swap.out" \
    && grep -q '^OUT$' "$DIR/swap.err" && ! grep -q '^ERR$' "$DIR/swap.err"; then
    ok "stdout:/stderr: swap through low-fd caller ports actually swaps"
else
    bad "swap did not swap (stdout: '$(cat "$DIR/swap.out")', stderr: '$(cat "$DIR/swap.err")')"
fi

# --- 3. spawn works with the parent's stdin closed (pipe lands on fd 0) -----
cat > "$DIR/closed0.scm" <<'SCM'
(import (scheme base) (kaappi process))
(let* ((p (spawn-process '("/bin/cat") 'stdin: 'pipe 'stdout: 'pipe))
       (in (process-stdin p)))
  (write-string "ping" in)
  (close-output-port in)
  (let ((line (read-line (process-stdout p))))
    (exit (if (and (equal? "ping" line) (equal? 0 (process-wait p))) 0 1))))
SCM
if "$KAAPPI" "$DIR/closed0.scm" 0<&- > "$DIR/closed0.out" 2>&1; then
    ok "pipe round trip survives the parent launching with fd 0 closed"
else
    bad "closed-stdin spawn failed: $(cat "$DIR/closed0.out")"
fi

echo "process-stdio-2442: $PASS pass, $FAIL fail"
[[ $FAIL -eq 0 ]]
