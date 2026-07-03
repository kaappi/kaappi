#!/bin/bash
# Regression test for #790 (LLVM native backend): constant folding in
# llvm_emit_lambda.zig must not fold a call to a primitive name that is
# shadowed by a lambda / define-function parameter. The native emitter now
# passes the parameter names to the IR via IR.bound_names so isRedefined
# suppresses the fold.
#
# Without the fix, ((lambda (+) (+ 1 2)) -) compiles to a binary that prints 3.
#
# Usage: bash tests/scheme/compile/native-param-shadow-fold-790.sh [path-to-kaappi]

set -euo pipefail

KAAPPI="${1:-zig-out/bin/kaappi}"
KAAPPI_ABS="$(cd "$(dirname "$KAAPPI")" && pwd)/$(basename "$KAAPPI")"
REPO_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"

# The native backend needs libkaappi_rt.a; build it once.
(cd "$REPO_DIR" && zig build lib > /dev/null 2>&1)

DIR=$(mktemp -d)
trap 'rm -rf "$DIR"' EXIT

# lambda parameter shadows +, bound to - : (+ 1 2) must evaluate as (- 1 2).
cat > "$DIR/lambda.scm" << 'SCHEME'
(display ((lambda (+) (+ 1 2)) -))
(newline)
SCHEME

# define-function parameter shadows *, bound to - : (* 3 4) must be (- 3 4).
cat > "$DIR/define.scm" << 'SCHEME'
(define (f *) (* 3 4))
(display (f -))
(newline)
SCHEME

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

check_native "$DIR/lambda.scm" "-1" "lambda-param-shadow"
check_native "$DIR/define.scm" "-1" "define-param-shadow"

echo "PASS"
