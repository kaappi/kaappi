#!/bin/bash
# Regression test for #2487: kaappi_set_global — the native tier's set! on a
# top-level global, emitted by the LLVM backend — stored into the shared
# globals map with no lock. A native closure deep-copied into an SRFI-18
# child thread runs with that child's VM (callNativeClosure passes the
# calling VM), so a child-side set! could race a root-side define/import
# rehash: the getPtr'd bucket pointer dangles across the rehash and the
# store lands in freed memory.
#
# The program's shape is chosen so the child's set!s are REAL native stores:
# the assignment target is a procedure-named global (a "known" global, so
# the lambda's set! is not a free variable), the loop is a `do` (lowered
# natively, #1496 — a named let would force the eval fallback), and the
# thread thunk is a defined procedure. The script asserts on the emitted IR
# first (as ten sibling scripts do): `call void @kaappi_set_global` must
# appear inside a lowered function — after the first `define tailcc` and
# before `@main` — so a future emitter change that quietly re-routes the
# body to an eval fallback turns this test red instead of hollow.
#
# The runtime check then runs the interleaving at volume: a child thread
# doing 200k native set!s on a shared global while the root thread evals
# 10k fresh defines (each a structural mutation that rehashes the shared
# map). The interpreter is the oracle: both tiers must print the child's
# last store. Pre-fix, the binary crashes or loses stores under the racing
# rehashes (probabilistically — the deterministic lock-protocol check is
# the Zig unit test in src/tests_srfi18.zig); with the fix, the child's
# getPtr+store+bump sit inside lockGlobalsShared, exactly like the
# interpreter's set_global.
#
# Usage: bash tests/scheme/compile/native-set-global-child-thread-2487.sh [path-to-kaappi]

set -euo pipefail

# Native-compile regression tests rebuild the runtime archive (zig build lib)
# or the interpreter itself on this machine; Windows ARM64 has no working
# native Zig toolchain until the 0.17.0 bump (kaappi#1613), and CI's
# windows-arm-test job deliberately installs none.
. "$(dirname "$0")/../shell-common.sh"
skip_on_windows "compile suite needs a native Zig toolchain on this machine (kaappi#1613)"

KAAPPI="${1:-zig-out/bin/kaappi}"
KAAPPI_ABS="$(cd "$(dirname "$KAAPPI")" && pwd)/$(basename "$KAAPPI")"
REPO_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"

ensure_runtime_lib "$REPO_DIR"

DIR=$(mktemp -d)
trap 'rm -rf "$DIR"' EXIT

# Isolated home: an installed ~/.kaappi/lib would shadow the checkout's
# lib/ for .sld resolution (kaappi#1523).
export KAAPPI_HOME="$DIR/home"
mkdir -p "$KAAPPI_HOME"

name=native-set-global-child-thread-2487
cat > "$DIR/$name.scm" << 'EOF'
(define (x) 0)
(define (child-loop n)
  (do ((i 1 (+ i 1))) ((> i n))
    (set! x i)))
(define (run) (child-loop 200000))
(define t (make-thread run))
;; define (not a bare thread-start!) so the interpreter does not echo the
;; thread object at top level — the native binary never echoes form values.
(define started (thread-start! t))

;; Root-side structural mutations: every eval'd define is a put under the
;; exclusive globals lock, and enough distinct names force the shared map
;; through repeated rehashes while the child's native set!s are in flight.
(let loop ((i 0))
  (when (< i 10000)
    (eval (list 'define
                (string->symbol (string-append "pad-" (number->string i)))
                i))
    (loop (+ i 1))))

(thread-join! t)
(display x)
(newline)
EOF

# IR gate: the child's set! must be a native store — a call inside a
# lowered function body (between the first `define tailcc` and `@main`),
# not merely a declaration or a top-level @main lookup. If this fails, the
# program shape has stopped reaching kaappi_set_global and the runtime
# check below is no longer testing the native store at all.
LL="$DIR/$name.ll"
if (cd "$DIR" && "$KAAPPI_ABS" --emit-llvm -o "$LL" "$name.scm" > /dev/null 2>&1); then
    first_def=$(grep -m1 -n "^define tailcc" "$LL" | cut -d: -f1)
    call_line=$(grep -m1 -n "call void @kaappi_set_global" "$LL" | cut -d: -f1)
    main_line=$(grep -n "^define i32 @main" "$LL" | cut -d: -f1)
    if [[ -z "$call_line" || -z "$first_def" || -z "$main_line" \
          || "$call_line" -le "$first_def" || "$call_line" -ge "$main_line" ]]; then
        echo "FAIL: $name — no kaappi_set_global call inside a lowered function in emitted IR (first_def=$first_def call=$call_line main=$main_line)" >&2
        exit 1
    fi
else
    echo "FAIL: $name — --emit-llvm failed" >&2
    exit 1
fi

# The oracle: the same program through the interpreter — set_global bumps no
# stale caches, the final value is the child's last store. stderr is captured
# so that a recurrence of the one-off abort this script once hit on a Debug
# CI leg (kaappi#2532) shows its panic text instead of dying exit-134-with-
# no-evidence: an aborting process loses its piped stdout to block buffering.
interp_status=0
interp_err="$DIR/$name.interp.err"
interp_out=$(interp_stdout "$KAAPPI_ABS" "$DIR" "$name.scm" "$interp_err") || interp_status=$?
if [[ "$interp_out" != "200000" || "$interp_status" -ne 0 ]]; then
    echo "FAIL: $name — interpreter stdout '$interp_out' exit $interp_status, expected '200000' exit 0" >&2
    show_interp_stderr "$interp_err"
    exit 1
fi

if ! (cd "$DIR" && "$KAAPPI_ABS" compile "$name.scm" -o "$name" > /dev/null 2>&1); then
    echo "FAIL: $name — native compilation failed" >&2
    exit 1
fi

set +e
out=$("$DIR/$name" 2>/dev/null)
status=$?
set -e

assert_tiers_agree "$name" "$interp_out" "$interp_status" "$out" "$status" || exit 1
echo "$name: passed"

# Second case — the #1924 cross-heap guard the store now carries: a child
# thread set!ing its OWN heap's object (the fresh list) into the shared map
# must be refused, not silently stored and later read out of the freed
# child heap (the `(0.0 . 0.0)` the pre-guard binary printed). The tiers
# differ by design on this erroring program — the interpreter raises at the
# store and continues with the next top-level form (so `h` is unchanged and
# gets displayed), while the native binary exits at the store — so each
# tier is checked against its own expectation, never compared via
# assert_tiers_agree (see the error-program note in ../shell-common.sh).
xname=native-set-global-cross-heap-store-2487
cat > "$DIR/$xname.scm" << 'EOF'
(define (h) 1)
(define (worker) (set! h (list 1 2 3)))
(define t (make-thread worker))
(define started (thread-start! t))
(thread-join! t)
(display h) (newline)
EOF

xi_status=0
xi_err="$DIR/$xname.interp.err"
xi_out=$(interp_stdout "$KAAPPI_ABS" "$DIR" "$xname.scm" "$xi_err") || xi_status=$?
if [[ "$xi_out" != "#<procedure h>" || "$xi_status" -ne 1 ]]; then
    echo "FAIL: $xname — interpreter stdout '$xi_out' exit $xi_status, expected '#<procedure h>' exit 1 (refused store, binding unchanged)" >&2
    show_interp_stderr "$xi_err"
    exit 1
fi

if ! (cd "$DIR" && "$KAAPPI_ABS" compile "$xname.scm" -o "$xname" > /dev/null 2>&1); then
    echo "FAIL: $xname — native compilation failed" >&2
    exit 1
fi

set +e
xout=$("$DIR/$xname" 2> "$DIR/$xname.err")
xstatus=$?
set -e
if [[ "$xstatus" -eq 0 || -n "$xout" ]]; then
    echo "FAIL: $xname — native binary exit $xstatus stdout '$xout', expected nonzero exit and empty stdout (store refused)" >&2
    exit 1
fi
if ! grep -q "cannot store an object created on this thread" "$DIR/$xname.err"; then
    echo "FAIL: $xname — native stderr lacks the cross-heap diagnostic" >&2
    exit 1
fi
echo "$xname: passed"
