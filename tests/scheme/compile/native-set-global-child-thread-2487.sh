#!/bin/bash
# Regression test for #2487: kaappi_set_global — the native tier's set! on a
# top-level global, emitted by the LLVM backend — stored into the shared
# globals map with no lock. A native closure deep-copied into an SRFI-18
# child thread runs with that child's VM (callNativeClosure passes the
# calling VM), so a child-side set! could race a root-side define/import
# rehash: the getPtr'd bucket pointer dangles across the rehash and the
# store lands in freed memory.
#
# The program below runs that interleaving at volume: a child thread running
# natively compiled code does 200k set!s on a shared global while the root
# thread evals 10k fresh defines (each a structural mutation that rehashes
# the shared map). The interpreter is the oracle: both tiers must finish
# cleanly and print the child's last stored value. Pre-fix, the binary
# crashes or loses stores under the racing rehashes (probabilistically — the
# deterministic lock-protocol check is the Zig unit test in
# src/tests_srfi18.zig); with the fix, the child's getPtr+store+bump sit
# inside lockGlobalsShared, exactly like the interpreter's set_global.
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
(import (scheme base) (srfi 18))

(define x 0)

(define (child-loop n)
  (let loop ((i 1))
    (when (<= i n)
      (set! x i)
      (loop (+ i 1)))))

(define t (make-thread (lambda () (child-loop 200000))))
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

# The oracle: the same program through the interpreter — set_global bumps no
# stale caches, the final value is the child's last store.
interp_status=0
interp_out=$(interp_stdout "$KAAPPI_ABS" "$DIR" "$name.scm") || interp_status=$?
if [[ "$interp_out" != "200000" || "$interp_status" -ne 0 ]]; then
    echo "FAIL: $name — interpreter stdout '$interp_out' exit $interp_status, expected '200000' exit 0" >&2
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
