#!/bin/bash
# Regression test for #1927: --lib-path could not shadow a bundled (srfi N).
#
# resolveLibraryPath probed the cwd-relative "" and "lib/" prefixes BEFORE any
# --lib-path entry, so running from a checkout that ships ./lib/srfi/N.sld, a
# `--lib-path shadow` meant to override (srfi N) lost silently to the bundled
# copy — an A/B comparison then measured the bundled library while looking like
# it ran. `kaappi --help` and CLAUDE.md both promise --lib-path takes
# precedence (auto-added dirs come *after* it), so the loader now searches every
# lib_paths entry before the cwd fallbacks.
#
# Case 1 (the fix): with a synthetic ./lib/srfi/14.sld present in the run cwd —
# exactly what beat --lib-path before — a `--lib-path shadow` entry must win.
# Before the fix this printed the BUNDLED sentinel; after it prints SHADOWED.
#
# Case 2 (no regression): an *unshadowed* bundled SRFI (here the real, shipped
# (srfi 151)) must still load even while --lib-path points at the shadow dir.

set -euo pipefail

KAAPPI="${1:-zig-out/bin/kaappi}"
KAAPPI_ABS="$(cd "$(dirname "$KAAPPI")" && pwd)/$(basename "$KAAPPI")"

PASS=0
FAIL=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# A synthetic "bundled" (srfi 14) reachable via the cwd "lib/" prefix — this is
# the copy that used to beat --lib-path.
mkdir -p "$TMP/lib/srfi"
cat > "$TMP/lib/srfi/14.sld" <<'EOF'
(define-library (srfi 14)
  (export char-set?)
  (import (scheme base))
  (begin (define (char-set? x) 'BUNDLED)))
EOF

# The shadow the user passes with --lib-path, overriding (srfi 14).
mkdir -p "$TMP/shadow/srfi"
cat > "$TMP/shadow/srfi/14.sld" <<'EOF'
(define-library (srfi 14)
  (export char-set?)
  (import (scheme base))
  (begin (define (char-set? x) 'SHADOWED)))
EOF

cat > "$TMP/prog14.scm" <<'EOF'
(import (scheme base) (scheme write) (srfi 14))
(write (char-set? 1))
(newline)
EOF

# An unshadowed, genuinely-shipped portable SRFI. (bitwise-and 12 10) = 8.
cat > "$TMP/prog151.scm" <<'EOF'
(import (scheme base) (scheme write) (srfi 151))
(write (bitwise-and 12 10))
(newline)
EOF

check() { # $1 = label; $2 = expected stdout substring; rest = argv
    local label="$1" want_out="$2"
    shift 2
    local status=0
    # Run from $TMP so its ./lib/srfi/14.sld is the cwd-relative bundled copy.
    (cd "$TMP" && env -u KAAPPI_LIB_DIR "$KAAPPI_ABS" "$@") > "$TMP/out.txt" 2>&1 || status=$?
    if [[ "$status" -ne 0 ]]; then
        echo "FAIL: $label — exited $status"
        cat "$TMP/out.txt"
        FAIL=$((FAIL + 1))
        return
    fi
    if ! grep -q "$want_out" "$TMP/out.txt"; then
        echo "FAIL: $label — output missing '$want_out'"
        cat "$TMP/out.txt"
        FAIL=$((FAIL + 1))
        return
    fi
    echo "PASS: $label"
    PASS=$((PASS + 1))
}

# Case 1: --lib-path shadows the bundled (srfi 14) that ./lib would otherwise
# win. The synthetic ./lib/srfi/14.sld is the trap: before the fix the loader
# probed it before --lib-path and printed BUNDLED; after, --lib-path wins.
check "--lib-path shadows bundled (srfi 14)" "SHADOWED" \
    --lib-path shadow prog14.scm

# Case 2: an unshadowed bundled SRFI still loads with --lib-path in play (the
# reorder must not break normal resolution of names the shadow dir lacks).
check "unshadowed bundled (srfi 151) still loads under --lib-path" "8" \
    --lib-path shadow prog151.scm

echo ""
echo "$PASS pass, $FAIL fail"
[[ $FAIL -eq 0 ]]
