#!/bin/bash
# Regression test for #1586: the native `let`/`let*` emitter duplicated side
# effects when a partially-emitted let abandoned to the interpreter fallback.
#
# emitLet writes binding initializers into the output IR incrementally, but bails
# to a whole-form `kaappi_eval_cached` fallback when a later binding or body form
# cannot be lowered natively (over the 32-binding ceiling, a non-symbol binding
# var, an init/body that needs interpreter eval in this lexical scope). The
# abandon path could not unwind the IR already written, so any side-effecting
# initializer that had already been emitted ran once from the stranded native
# code AND again when the interpreter re-evaluated the whole form.
#
# The fix makes native let lowering transactional: emitLet snapshots the output
# position (and current block) before writing any of its IR, and the abandon path
# truncates back to that snapshot — discarding the partial initializers, their
# side effects, and their GC root pushes — before emitting the interpreter
# fallback. Each side effect then runs exactly once, matching the interpreter.
#
# NOTE: the incremental-emit path is only reached for a BARE top-level `let`
# (a `let` that is a top-level form). A `let` that is a define initializer or a
# function body takes a different route that does not duplicate — so these
# reproducers must be bare top-level lets, exactly as in the issue. The
# interpreter, run in file mode, echoes the value of each bare top-level form;
# the natively-compiled binary does not. We therefore assert the native output
# against the known-correct constant, and cross-check that the interpreter's
# final (non-echo) line agrees.
#
# Usage: bash tests/scheme/compile/native-let-partial-emit-dup-1586.sh [path-to-kaappi]

set -euo pipefail

KAAPPI="${1:-zig-out/bin/kaappi}"
KAAPPI_ABS="$(cd "$(dirname "$KAAPPI")" && pwd)/$(basename "$KAAPPI")"
REPO_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"

if [[ ! -f "$REPO_DIR/zig-out/lib/libkaappi_rt.a" ]]; then
    (cd "$REPO_DIR" && zig build lib > /dev/null 2>&1)
fi

DIR=$(mktemp -d)
trap 'rm -rf "$DIR"' EXIT

fail=0

# Each program ends with an explicit `(display ...)` of the observable side
# effect state on its own final line. `expect` is that final line — the correct
# result when the side effect runs exactly once. Before the fix the native
# binary printed the doubled state; after it, it matches the interpreter.
check() {
    local name="$1" src="$2" expect="$3"

    printf '%s' "$src" > "$DIR/$name.scm"

    # Oracle: the interpreter never had the bug. Its last output line is the
    # explicit display (earlier lines may be the echoed bare-let values).
    local interp_last
    interp_last=$("$KAAPPI_ABS" "$DIR/$name.scm" 2>&1 | tail -1) || {
        echo "FAIL: $name — interpreter run failed" >&2
        fail=1
        return
    }
    if [[ "$interp_last" != "$expect" ]]; then
        echo "FAIL: $name — interpreter final line '$interp_last', expected '$expect'" >&2
        fail=1
        return
    fi

    if ! (cd "$REPO_DIR" && "$KAAPPI_ABS" compile "$DIR/$name.scm" -o "$DIR/$name" > /dev/null 2>&1); then
        echo "FAIL: $name — native compilation failed" >&2
        fail=1
        return
    fi

    local out status
    set +e
    out=$("$DIR/$name" 2>&1)
    status=$?
    set -e
    if [[ $status -ne 0 ]]; then
        echo "FAIL: $name — binary aborted (exit $status): $out" >&2
        fail=1
        return
    fi
    if [[ "$out" != "$expect" ]]; then
        echo "FAIL: $name — native gave '$out', expected '$expect' (side effect duplicated?)" >&2
        fail=1
    fi
}

# 1. Issue reproducer: a 33-binding let exceeds the 32-binding native ceiling, so
#    emission bails after the first 32 inits are already written. The first init
#    has a side effect (bump). It must run once — n=1, not n=2.
check dup-33-bindings \
'(define n 0)
(define (bump) (set! n (+ n 1)) 0)
(let ((b0 (bump)) (b1 0) (b2 0) (b3 0) (b4 0) (b5 0) (b6 0) (b7 0) (b8 0)
      (b9 0) (b10 0) (b11 0) (b12 0) (b13 0) (b14 0) (b15 0) (b16 0) (b17 0)
      (b18 0) (b19 0) (b20 0) (b21 0) (b22 0) (b23 0) (b24 0) (b25 0) (b26 0)
      (b27 0) (b28 0) (b29 0) (b30 0) (b31 0) (b32 0))
  n)
(display "n=") (display n) (newline)' \
'n=1'

# 2. A side-effecting first init that also contains control flow (an `if`),
#    followed by the 33-binding overflow. The `if` splits the current basic block
#    before the abandon; the fix must restore the block so the fallback emits into
#    a live block AND discard the init so the effect runs once.
check dup-init-control-flow \
'(define n 0)
(define (bump) (set! n (+ n 1)) 7)
(let ((b0 (if (> (bump) 0) 1 2)) (b1 0) (b2 0) (b3 0) (b4 0) (b5 0) (b6 0)
      (b7 0) (b8 0) (b9 0) (b10 0) (b11 0) (b12 0) (b13 0) (b14 0) (b15 0)
      (b16 0) (b17 0) (b18 0) (b19 0) (b20 0) (b21 0) (b22 0) (b23 0) (b24 0)
      (b25 0) (b26 0) (b27 0) (b28 0) (b29 0) (b30 0) (b31 0) (b32 0))
  (+ b0 n))
(display "n=") (display n) (newline)' \
'n=1'

# 3. Mid-body abandon: an earlier body expression runs for effect, then a later
#    body form (a `cond` with a `=>` clause, not natively emittable inside a let
#    scope) abandons the whole let. The earlier effect must not be duplicated.
check dup-body-abandon \
'(define log (quote ()))
(define (note x) (set! log (cons x log)) x)
(let ((a 2))
  (if (> a 0) (note (quote pos)) (note (quote neg)))
  (cond ((assv a (quote ((2 . two) (3 . three)))) => cdr)
        (else (quote other))))
(display "log=") (display (reverse log)) (newline)' \
'log=(pos)'

# 4. let* variant: a side-effecting first init, then a second init that is not
#    natively emittable (cond with =>), forcing abandon after the first init.
check dup-letstar \
'(define cnt 0)
(define (tick) (set! cnt (+ cnt 1)) cnt)
(let* ((a (if (> (tick) 0) 10 20))
       (b (cond ((assv a (quote ((10 . ten)))) => cdr) (else (quote no)))))
  (list a b))
(display "cnt=") (display cnt) (newline)' \
'cnt=1'

if [[ "$fail" -ne 0 ]]; then
    exit 1
fi
echo "native-let-partial-emit-dup-1586: all cases passed"
