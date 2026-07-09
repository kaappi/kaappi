#!/bin/bash
# Regression test for #1376: natively compiled programs calling bootstrapped
# procedures (map, for-each, dynamic-wind, ... — Scheme closures installed by
# src/vm_bootstrap.zig since #1374).
#
# The bootstrapped bytecode closure must be able to invoke the natively
# compiled callback (a NativeClosure) from inside the bytecode dispatch loop:
# the .call/.tail_call/.tail_apply/.tail_call_global opcodes and the
# callValue/callThunk/callHandler helpers all need a native_closure arm.
# Before the fix every case below died with "runtime error in call".
#
# Also covers the improved kaappi_call_scheme error path: failures must
# report vm.last_error_detail instead of a bare "runtime error in call".
#
# Usage: bash tests/scheme/compile/native-bootstrap-callbacks-1376.sh [path-to-kaappi]

set -euo pipefail

KAAPPI="${1:-zig-out/bin/kaappi}"
KAAPPI_ABS="$(cd "$(dirname "$KAAPPI")" && pwd)/$(basename "$KAAPPI")"
REPO_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"

# Build interpreter + runtime library
(cd "$REPO_DIR" && zig build lib > /dev/null 2>&1)

DIR=$(mktemp -d)
trap 'rm -rf "$DIR"' EXIT

check_native() {
    local src="$1" expected="$2" label="$3"
    local bin="$DIR/${label}.bin"
    (cd "$REPO_DIR" && "$KAAPPI_ABS" compile "$src" -o "$bin" > /dev/null 2>&1)
    if [[ ! -x "$bin" ]]; then
        echo "FAIL: $label — native compile did not produce a binary" >&2
        exit 1
    fi
    local out
    out="$("$bin")"
    if [[ "$out" != "$expected" ]]; then
        echo "FAIL: $label — expected '$expected', got '$out'" >&2
        exit 1
    fi
}

# --- Case 1: map with a native callback (the #1376 repro) ---
cat > "$DIR/map-single.scm" << 'SCHEME'
(display (map (lambda (x) x) (list 1 2)))
(newline)
SCHEME

check_native "$DIR/map-single.scm" "(1 2)" "map-single"

# --- Case 2: multi-list map (callback reaches the closure via apply) ---
cat > "$DIR/map-multi.scm" << 'SCHEME'
(display (map (lambda (a b) (+ a b)) (list 1 2 3) (list 10 20 30)))
(newline)
SCHEME

check_native "$DIR/map-multi.scm" "(11 22 33)" "map-multi"

# --- Case 3: for-each with a side-effecting native callback ---
cat > "$DIR/for-each.scm" << 'SCHEME'
(for-each (lambda (x) (display x) (display " ")) (list 7 8 9))
(newline)
SCHEME

check_native "$DIR/for-each.scm" "7 8 9 " "for-each"

# --- Case 4: dynamic-wind with three native thunks ---
cat > "$DIR/dynamic-wind.scm" << 'SCHEME'
(dynamic-wind
  (lambda () (display "before "))
  (lambda () (display "during "))
  (lambda () (display "after")))
(newline)
SCHEME

check_native "$DIR/dynamic-wind.scm" "before during after" "dynamic-wind"

# --- Case 5: map inside a dynamic-wind thunk ---
cat > "$DIR/wind-map.scm" << 'SCHEME'
(dynamic-wind
  (lambda () (display "["))
  (lambda () (display (map (lambda (x) (* x x)) (list 1 2 3))))
  (lambda () (display "]")))
(newline)
SCHEME

check_native "$DIR/wind-map.scm" "[(1 4 9)]" "wind-map"

# --- Case 6: rest of the trampolined family + force still works ---
cat > "$DIR/family.scm" << 'SCHEME'
(display (vector-map (lambda (x) (+ x 1)) (vector 1 2 3)))
(vector-for-each (lambda (x) (display x)) (vector 4 5))
(display (string-map (lambda (c) (if (char=? c #\a) #\A c)) "abc"))
(string-for-each (lambda (c) (display c)) "xy")
(display (force (delay 42)))
(newline)
SCHEME

check_native "$DIR/family.scm" "#(2 3 4)45Abcxy42" "family"

# --- Case 7: callback capturing a local (native closure with upvalues) ---
cat > "$DIR/upvalue.scm" << 'SCHEME'
(define (add-to-all k lst)
  (map (lambda (x) (+ x k)) lst))
(display (add-to-all 10 (list 1 2 3)))
(newline)
SCHEME

check_native "$DIR/upvalue.scm" "(11 12 13)" "upvalue"

# --- Case 8: bytecode tail positions calling a native callback ---
# A do-loop forces the defined procedure onto the interpreter (eval
# fallback), so (f i) / (apply f ...) / (g 14) execute as bytecode
# tail_call / tail_apply / tail_call_global with a NativeClosure callee.
cat > "$DIR/tail-calls.scm" << 'SCHEME'
(define (tail-call-it f)
  (do ((i 0 (+ i 1)))
      ((= i 3) (f i))))
(display (tail-call-it (lambda (x) (* x 100))))
(newline)
(define (tail-apply-it f)
  (do ((i 0 (+ i 1)))
      ((= i 1) (apply f (list 7 8)))))
(display (tail-apply-it (lambda (a b) (+ a b))))
(newline)
(define g #f)
(define (setup!)
  (set! g (lambda (x) (* x 3))))
(setup!)
(define (call-g)
  (do ((i 0 (+ i 1)))
      ((= i 1) (g 14))))
(display (call-g))
(newline)
SCHEME

check_native "$DIR/tail-calls.scm" "300
15
42" "tail-calls"

# --- Case 9: call/cc with a native receiver (callHandler path) ---
cat > "$DIR/callcc.scm" << 'SCHEME'
(display (call-with-current-continuation (lambda (k) (k 99))))
(display (call-with-current-continuation (lambda (k) 55)))
(newline)
SCHEME

check_native "$DIR/callcc.scm" "9955" "callcc"

# --- Case 10: errors escaping to native code report the detail ---
cat > "$DIR/arity-err.scm" << 'SCHEME'
(display (map (lambda (x y) x) (list 1 2)))
SCHEME

bin="$DIR/arity-err.bin"
(cd "$REPO_DIR" && "$KAAPPI_ABS" compile "$DIR/arity-err.scm" -o "$bin" > /dev/null 2>&1)
set +e
err_out="$("$bin" 2>&1)"
status=$?
set -e
if [[ $status -eq 0 ]]; then
    echo "FAIL: arity-err — expected non-zero exit" >&2
    exit 1
fi
if [[ "$err_out" != *"expected 2 arguments, got 1"* ]]; then
    echo "FAIL: arity-err — error detail missing, got '$err_out'" >&2
    exit 1
fi

echo "PASS"
