#!/bin/bash
# Regression test for #1653: --lib-path entries past the 16th were silently
# dropped. Two fixed [16] buffers had the bug — cli.zig's storage and main.zig's
# search-path assembly (which also folds in the auto-discovered dirs: the
# script's directory, ~/.kaappi/lib, and the exe-relative fallback lib). This
# exercises the whole pipeline end-to-end (cli.parse → main assembly →
# vm.lib_paths → resolveLibraryPath), which the cli.zig unit test can't reach.
#
# The two failure shapes the issue calls out:
#   A. a 17th+ explicit --lib-path vanishes (here: library lives in the 20th).
#   B. once 16 explicit paths exist, the auto-discovered dirs vanish too
#      (here: 16 explicit empty paths + the library in the script's own dir).
#
# Isolation mirrors exe-relative-lib-1523.sh: resolveLibraryPath probes the
# cwd-relative "" and "lib/" prefixes before any search path, so the run cwd
# must not contain the library; an empty HOME keeps ~/.kaappi/lib from masking
# a broken fix.

set -euo pipefail

KAAPPI="${1:-zig-out/bin/kaappi}"
KAAPPI_ABS="$(cd "$(dirname "$KAAPPI")" && pwd)/$(basename "$KAAPPI")"

PASS=0
FAIL=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/run" "$TMP/emptyhome" "$TMP/khome"

# A library that is not a real SRFI, so the exe-relative lib/ fallback (which
# ships the portable SRFI sources next to the binary) can never resolve it —
# only an entry we pass can.
make_lib() { # $1 = dir to hold the (mylib greet) library; $2 = greeting text
    mkdir -p "$1/mylib"
    cat > "$1/mylib/greet.sld" <<EOF
(define-library (mylib greet)
  (export greeting)
  (import (scheme base))
  (begin (define greeting "$2")))
EOF
}

write_prog() { # $1 = .scm path
    mkdir -p "$(dirname "$1")"
    cat > "$1" <<'SCM'
(import (scheme base) (scheme write) (mylib greet))
(display greeting)
(newline)
SCM
}

# Runs kaappi from an isolated cwd/HOME with the given argv.
run_isolated() {
    (cd "$TMP/run" && \
        env -u KAAPPI_LIB_DIR KAAPPI_HOME="$TMP/khome" HOME="$TMP/emptyhome" \
        "$KAAPPI_ABS" "$@")
}

check() { # $1 = label; $2 = expected exit; $3 = expected stdout substring (or "")
    local label="$1" want_exit="$2" want_out="$3"
    shift 3
    local status=0
    run_isolated "$@" > "$TMP/out.txt" 2>&1 || status=$?
    if [[ "$status" -ne "$want_exit" ]]; then
        echo "FAIL: $label — expected exit $want_exit, got $status"
        cat "$TMP/out.txt"
        FAIL=$((FAIL + 1))
        return
    fi
    if [[ -n "$want_out" ]] && ! grep -q "$want_out" "$TMP/out.txt"; then
        echo "FAIL: $label — output missing '$want_out'"
        cat "$TMP/out.txt"
        FAIL=$((FAIL + 1))
        return
    fi
    echo "PASS: $label"
    PASS=$((PASS + 1))
}

# ── Shape A: library in the 20th of 20 explicit --lib-path entries ──────────
# 20 > 16, so under the old cap paths 17..20 (including the one that matters)
# were dropped and the import failed.
declare -a A_ARGS=()
for i in $(seq 1 20); do
    mkdir -p "$TMP/pA$i"
    A_ARGS+=(--lib-path "$TMP/pA$i")
done
make_lib "$TMP/pA20" "greet-from-20th-path"
write_prog "$TMP/progA/prog.scm"
check "20 explicit --lib-path: library in the 20th resolves" 0 "greet-from-20th-path" \
    "${A_ARGS[@]}" "$TMP/progA/prog.scm"

# ── Negative control: the same 20 entries, but remove the library ───────────
# Proves shape A actually resolves via the passed search path, not via cwd,
# HOME, or the exe-relative fallback.
rm -rf "$TMP/pA20/mylib"
check "control: same 20 --lib-path but no library anywhere fails" 1 "" \
    "${A_ARGS[@]}" "$TMP/progA/prog.scm"

# ── Shape B: 16 explicit (empty) paths + library in the script's own dir ────
# The auto-discovered script-dir entry is appended after the explicit ones, so
# with 16 explicit paths filling the old [16] buffer it was dropped.
declare -a B_ARGS=()
for i in $(seq 1 16); do
    mkdir -p "$TMP/pB$i"
    B_ARGS+=(--lib-path "$TMP/pB$i")
done
write_prog "$TMP/progB/prog.scm"
make_lib "$TMP/progB" "greet-from-script-dir"   # next to prog.scm
check "16 explicit --lib-path: auto-discovered script dir still resolves" 0 "greet-from-script-dir" \
    "${B_ARGS[@]}" "$TMP/progB/prog.scm"

echo ""
echo "$PASS pass, $FAIL fail"
[[ $FAIL -eq 0 ]]
