#!/bin/bash
# Native-tier regression for (kaappi process) — KEP-0022 Phase 1, kaappi#2414.
#
# spawn-process and its accessors are ordinary primitives (no LLVM emitter
# work), but a .scm test only ever exercises the interpreter tier, and three
# regressions once passed for years that way while the native tier failed them.
# So a compiled program that spawns a child, reads its stdout through a pipe
# port, and reaps it must be checked through `kaappi compile` too.
#
# Usage: bash tests/scheme/compile/process-spawn-2414.sh [path-to-kaappi]

set -euo pipefail

# (kaappi process) is POSIX-only until Phase 3, and native-compile tests need a
# native Zig toolchain on this machine (kaappi#1613).
. "$(dirname "$0")/../shell-common.sh"
skip_on_windows "(kaappi process) is POSIX-only until Phase 3; compile suite needs a native Zig toolchain (kaappi#1613)"

REPO_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
KAAPPI="${1:-$REPO_DIR/zig-out/bin/kaappi}"
KAAPPI_ABS="$(cd "$(dirname "$KAAPPI")" && pwd)/$(basename "$KAAPPI")"

ensure_runtime_lib "$REPO_DIR"

DIR=$(mktemp -d)
trap 'rm -rf "$DIR"' EXIT

FAILED=0

# Run a program both ways and require identical output; the interpreter is the
# oracle (tests/scheme/CLAUDE.md).
check_both() {
    local label="$1" expected="$2"
    local src="$DIR/${label}.scm" bin="$DIR/${label}.bin"

    local interp_out interp_status=0
    interp_out="$(cd "$REPO_DIR" && "$KAAPPI_ABS" "$src" 2>&1)" || interp_status=$?
    if [[ $interp_status -ne 0 ]]; then
        echo "FAIL: $label — interpreter exited $interp_status (output: '$interp_out')" >&2
        FAILED=1
        return
    fi
    if [[ "$interp_out" != "$expected" ]]; then
        echo "FAIL: $label — interpreter expected '$expected', got '$interp_out'" >&2
        FAILED=1
        return
    fi

    local compile_out compile_status=0
    compile_out="$(cd "$REPO_DIR" && "$KAAPPI_ABS" compile "$src" -o "$bin" 2>&1)" || compile_status=$?
    if [[ $compile_status -ne 0 ]]; then
        echo "FAIL: $label — kaappi compile exited $compile_status: $compile_out" >&2
        FAILED=1
        return
    fi
    if [[ ! -x "$bin" ]]; then
        echo "FAIL: $label — kaappi compile produced no binary" >&2
        FAILED=1
        return
    fi

    local native_out native_status=0
    native_out="$("$bin" 2>&1)" || native_status=$?
    if [[ $native_status -ne 0 ]]; then
        echo "FAIL: $label — compiled binary exited $native_status (output: '$native_out')" >&2
        FAILED=1
        return
    fi
    if [[ "$native_out" != "$interp_out" ]]; then
        echo "FAIL: $label — native '$native_out' != interpreted '$interp_out'" >&2
        FAILED=1
    fi
}

# Spawn a child, capture its stdout through a pipe port, and reap it — the
# whole Phase 1 surface exercised from compiled code.
cat > "$DIR/spawn.scm" << 'SCHEME'
(import (scheme base) (scheme write) (kaappi process))
(define (drain port)
  (let loop ((acc '()))
    (let ((b (read-u8 port)))
      (if (eof-object? b)
          (list->string (map integer->char (reverse acc)))
          (loop (cons b acc))))))
(define p (spawn-process '("sh" "-c" "printf native-ok") 'stdout: 'pipe))
(display (drain (process-stdout p)))
(display " ")
(display (process-wait p))
(newline)
SCHEME
check_both "spawn" "native-ok 0"

if [[ $FAILED -ne 0 ]]; then
    exit 1
fi
echo "PASS"
