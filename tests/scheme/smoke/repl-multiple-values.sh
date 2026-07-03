#!/bin/bash
# Regression test: a multiple-values result at the top level prints every
# value, one per line, matching other Scheme REPLs (Chez, Guile, Racket,
# Chibi). Previously only the first value was printed:
#   (values 3 2)  =>  3        (the 2 was silently dropped)
# Covers piped-stdin mode and file mode (both fresh compile and .sbc cache).

set -e

KAAPPI="${1:-${KAAPPI:-zig-out/bin/kaappi}}"

fail=0

check() {
    local label="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        echo "PASS: $label"
    else
        echo "FAIL: $label"
        echo "  expected: $(printf '%q' "$expected")"
        echo "  actual:   $(printf '%q' "$actual")"
        fail=1
    fi
}

# --- piped stdin mode ---
check "stdin (values 3 2)" "$(printf '3\n2')" "$(echo '(values 3 2)' | $KAAPPI)"
check "stdin (values) prints nothing" "" "$(echo '(values)' | $KAAPPI)"
check "stdin single value unchanged" "3" "$(echo '(+ 1 2)' | $KAAPPI)"
check "stdin procedure returning values" "$(printf '3\n2')" \
    "$(printf '(define (divide a b) (values (quotient a b) (remainder a b)))\n(divide 17 5)\n' | $KAAPPI)"

# --- file mode ---
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
printf '(values 3 2)\n(values)\n(values 42)\n' > "$tmpdir/mv.scm"
check "file mode (fresh compile)" "$(printf '3\n2\n42')" "$($KAAPPI "$tmpdir/mv.scm")"
check "file mode (cached .sbc)" "$(printf '3\n2\n42')" "$($KAAPPI "$tmpdir/mv.scm")"

exit $fail
