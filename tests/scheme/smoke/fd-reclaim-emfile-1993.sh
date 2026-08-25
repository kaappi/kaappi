#!/usr/bin/env bash
# Regression test for kaappi#1993: open-input-file, open-output-file and
# open-directory must force a full GC and retry on EMFILE/ENFILE before
# raising. The fd-holding objects (ports, directory streams) are ordinarily
# unreachable and their finalizers close the descriptor, so a legal program
# that abandons them faster than the GC's allocation-count threshold trips
# should not spuriously fail at a normal `ulimit -n`.
#
# Hermetic trigger: cap the soft descriptor limit low, then open-and-abandon
# far more fd-holders than the cap, one at a time, in a loop. Each open's
# value is discarded, so every object is immediately unreachable.
#
#   * WITHOUT the fix, the fd table fills within ~cap iterations — long before
#     the 8192-object allocation-count threshold trips a collection — so the
#     next open raises EMFILE, the uncaught error aborts the program, and
#     kaappi exits nonzero. This test then FAILS (which is how it was verified
#     to actually exercise the fix).
#   * WITH the fix, the open on a full table forces a full collection that
#     reclaims the abandoned fd-holders' descriptors and the retry succeeds, so
#     the loop runs to completion, prints OK, and kaappi exits 0.
#
# The loop count (4000) is ~30x the 128-fd cap, well beyond anything a single
# object-count-driven collection could paper over, and each of the three
# primitives is exercised in turn.
set -u

. "$(dirname "$0")/../shell-common.sh"
skip_on_windows "ulimit -n / EMFILE retry is POSIX-only; Windows opens use HANDLEs, not the fd table"

KAAPPI="${KAAPPI:-${1:-zig-out/bin/kaappi}}"

# Lower the per-process descriptor cap. 128 clears the handful of fds the
# runtime itself holds (std streams, bytecode cache, history, ...) yet sits far
# below the loop count, so the table fills quickly and the retry path is what
# carries the loop to completion.
if ! ulimit -n 128 2> /dev/null; then
    echo "SKIP: cannot lower ulimit -n on this host"
    exit 77
fi

workdir="$(mktemp -d "${TMPDIR:-/tmp}/kaappi-fd1993.XXXXXX")" || exit 1
trap 'rm -rf "$workdir"' EXIT

seed="$workdir/seed"
: > "$seed"
prog="$workdir/prog.scm"

cat > "$prog" << EOF
(import (scheme base) (scheme write) (scheme file) (srfi 170))

(define dir "$workdir")
(define seed "$seed")

;; Open N fd-holders, discarding each — every value is unreachable the moment
;; the next iteration begins, so only on-demand reclamation can keep the fd
;; table from overflowing under the low cap.
(define (spin n thunk)
  (let loop ((i 0))
    (if (= i n) #t (begin (thunk) (loop (+ i 1))))))

(spin 4000 (lambda () (open-directory dir)))
(spin 4000 (lambda () (open-input-file seed)))
(spin 4000 (lambda () (open-output-file (string-append dir "/out"))))

(display "OK")
(newline)
EOF

out="$("$KAAPPI" "$prog" 2>&1)"
rc=$?

if [ "$rc" -ne 0 ]; then
    echo "FAIL: kaappi exited $rc under ulimit -n 128 (descriptors not reclaimed on EMFILE)"
    echo "$out"
    exit 1
fi

case "$out" in
    *OK*) ;;
    *)
        echo "FAIL: expected OK marker, got:"
        echo "$out"
        exit 1
        ;;
esac

echo "PASS: fd-holders reclaimed and reopened under a low descriptor cap"
exit 0
