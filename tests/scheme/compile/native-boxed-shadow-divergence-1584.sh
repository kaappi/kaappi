#!/bin/bash
# Regression test for #1584 (fuzz seed 2788): the native backend resolved
# variable names against the frame-level box map BEFORE the lexical locals
# map, so a let-local (or do-var, or internal define) that SHADOWED a boxed
# binding of the same name resolved to the outer box instead of the inner
# binding. A set! on the shadow then leaked into the boxed param that a
# sibling closure had captured, and reads inside the shadowing scope saw the
# box's value — both diverging from the VM.
#
# The fix makes box-ness a per-binding attribute: locals entries carry a
# `boxed` flag, `self.boxes` holds only frame-level boxed params/captures,
# and name resolution checks the innermost lexical binding first.
#
# Usage: bash tests/scheme/compile/native-boxed-shadow-divergence-1584.sh [path-to-kaappi]

set -euo pipefail

# Native-compile regression tests rebuild the runtime archive (zig build lib)
# or the interpreter itself on this machine; Windows ARM64 has no working
# native Zig toolchain until the 0.17.0 bump (kaappi#1613), and CI's
# windows-arm-test job deliberately installs none.
. "$(dirname "$0")/../shell-common.sh"
skip_on_windows "compile suite needs a native Zig toolchain on this machine (kaappi#1613)"

REPO_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
KAAPPI="${1:-$REPO_DIR/zig-out/bin/kaappi}"
KAAPPI_ABS="$(cd "$(dirname "$KAAPPI")" && pwd)/$(basename "$KAAPPI")"

if [[ ! -f "$REPO_DIR/zig-out/lib/libkaappi_rt.a" ]]; then
    (cd "$REPO_DIR" && zig build lib > /dev/null 2>&1)
fi

DIR=$(mktemp -d)
trap 'rm -rf "$DIR"' EXIT

# Every binary run is bounded: case 5 hangs forever on a buggy build, and a
# wedged test job is worse than a failed one. Prefer GNU timeout when
# available (Linux/CI); otherwise (macOS without coreutils) a background
# watchdog kills the process after the same deadline.
RUN_TIMEOUT=""
for c in timeout gtimeout; do
    if command -v "$c" >/dev/null 2>&1; then
        RUN_TIMEOUT="$c 10"
        break
    fi
done

run_bounded() {
    if [[ -n "$RUN_TIMEOUT" ]]; then
        $RUN_TIMEOUT "$@"
        return
    fi
    "$@" &
    local pid=$!
    # Redirect the watchdog's stdio away from the caller's command
    # substitution, or its 10s sleep would hold the capture pipe open.
    ( sleep 10; kill -9 "$pid" 2>/dev/null ) >/dev/null 2>&1 &
    local watchdog=$!
    local status=0
    wait "$pid" || status=$?
    kill "$watchdog" 2>/dev/null || true
    return "$status"
}

fail=0

# Compile natively and check output.  When expect_native is "yes", also
# verify that at least one user-defined native function was emitted; when
# "no", verify that none were (the whole program fell back to eval).
check() {
    local name="$1" src="$2" expect_out="$3" expect_native="${4:-}"

    printf '%s' "$src" > "$DIR/$name.scm"

    if ! (cd "$REPO_DIR" && "$KAAPPI_ABS" compile "$DIR/$name.scm" -o "$DIR/$name" > /dev/null 2>&1); then
        echo "FAIL: $name — native compilation failed" >&2
        fail=1
        return
    fi

    local out
    if ! out=$(run_bounded "$DIR/$name" 2>/dev/null); then
        echo "FAIL: $name — binary exited nonzero or timed out" >&2
        fail=1
        return
    fi

    if [[ "$out" != "$expect_out" ]]; then
        echo "FAIL: $name — expected '$expect_out', got '$out'" >&2
        fail=1
    fi

    if [[ -n "$expect_native" ]]; then
        (cd "$REPO_DIR" && "$KAAPPI_ABS" --emit-llvm -o "$DIR/$name.ll" "$DIR/$name.scm" > /dev/null 2>&1) || true
        local native_def_re='^define ([a-z]+ )*i64 @(lambda_|r[0-9])'
        if [[ "$expect_native" == "yes" ]]; then
            if ! grep -qE "$native_def_re" "$DIR/$name.ll" 2>/dev/null; then
                echo "FAIL: $name — expected native fn definition in LLVM IR" >&2
                fail=1
            fi
        elif [[ "$expect_native" == "no" ]]; then
            if grep -qE "$native_def_re" "$DIR/$name.ll" 2>/dev/null; then
                echo "FAIL: $name — expected NO native fn definition (should fall back)" >&2
                fail=1
            fi
        fi
    fi
}

# 1. Minimized seed-2788: param a is boxed (set! in body + captured by the
#    lambda). The let binds its own a; the set! must hit the let-local, not
#    the param's box, so the closure still reads -7. Buggy: 102.
check shadow-set-leak \
'(define (f a)
  (- (let ((a 1)) (set! a -3) 99)
     ((lambda (h) a) 0)))
(write (f -7))
(newline)' \
'106' yes

# 2. Reads inside the shadowing let must see the let-local (after its own
#    set!), not the boxed param. Buggy: 66 (both sides read the box).
check shadow-read \
'(define (g a)
  (+ (let ((a 5)) (set! a 6) (* a 10))
     ((lambda (h) a) 0)))
(write (g 2))
(newline)' \
'62' yes

# 3. Reverse nesting: a boxed OUTER let-local shadowed by a plain inner
#    let-local. The inner (+ x 1) must read 10, not the box. Buggy: #(2 3).
check shadow-boxed-let-local \
'(define (h)
  (let ((x 1))
    (vector ((lambda (k) (set! x 2) x) 0)
            (let ((x 10)) (+ x 1)))))
(write (h))
(newline)' \
'#(2 11)' yes

# 4. let* whose later init reads the shadowing binding of a boxed param.
#    Buggy: 7 (init reads the box, set! writes it, closure sees 5).
check shadow-let-star-init \
'(define (fs a)
  (+ (let* ((a 10) (b (* a 2))) (set! a 5) b)
     ((lambda (h) a) 0)))
(write (fs 1))
(newline)' \
'21' yes

# 5. do-loop variable shadowing a boxed param: the test and step expressions
#    must read the loop variable. Buggy: infinite loop (test forever reads
#    the box's 7).
check shadow-do-var \
'(define (fd a)
  (set! a 7)
  (cons (do ((a 0 (+ a 1))) ((= a 3) a))
        ((lambda (h) a) 0)))
(write (fd 1))
(newline)' \
'(3 . 7)' yes

# 6. Internal define in a let body shadowing a boxed param. This shape
#    currently falls back to the interpreter as a whole (tier not pinned);
#    the output must stay correct if a later change compiles it natively.
check shadow-internal-define \
'(define (fi a)
  (+ (let ((unused 0))
       (define a 100)
       (set! a (+ a 1))
       a)
     ((lambda (h) a) 0)))
(write (fi 3))
(newline)' \
'104'

# 7. Full seed-2788 f1 shape: variadic + shadowing let + capturing lambda in
#    one function, exactly as the fuzzer generated it. Buggy: -65.
check seed-2788-f1 \
'(define (f1 v a . rest)
  (if (null? rest)
      (- (let ((a v)) (set! a -3) v)
         ((lambda (h) a) v))
      (+ (car rest) (and (begin -76 v) (min 75 a)))))
(write (f1 -68 -7))
(newline)' \
'-61' yes

# 8. A lambda inside the let captures the PLAIN let-local that shadows the
#    boxed param. There is no capturable slot for a plain let-local, so this
#    must reject to the interpreter — not capture the param box. Buggy: 2
#    (both lambdas read the box). Tier not pinned: correctness is the point.
check shadow-captured-by-lambda \
'(define (f a)
  (set! a 1)
  (+ (let ((a 5)) ((lambda (h) a) 0))
     ((lambda (h) a) 0)))
(write (f 99))
(newline)' \
'6'

if [[ "$fail" -ne 0 ]]; then
    exit 1
fi
echo "native-boxed-shadow-divergence-1584: all cases passed"
