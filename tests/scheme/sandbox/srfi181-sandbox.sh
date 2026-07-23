#!/bin/bash
# SRFI 181 (#1729): (srfi 181) sandbox availability.
#
# (srfi 181) used to resolve directly against the vm.libraries registry
# (a pure Zig registration, as privileged as any other built-in). Splitting
# transcoded ports out required moving the public (srfi 181) name to a real
# lib/srfi/181.sld -- but --sandbox blocks every file-backed library load
# outright (vm_library.zig's tryLoadLibraryFromFile), so a plain portable
# .sld would be unimportable there at all. lib/srfi/181.sld stays
# importable under --sandbox because its source is also embedded directly
# into the binary (vm_library.zig's embedded_libraries table), the same
# fix (kaappi parallel) already uses (see parallel-degrades.sh) and SRFI
# 248 already established for the identical registry-shadowing problem.
#
# Unlike (kaappi parallel), nothing in (srfi 181) needs to *degrade* under
# sandbox -- custom ports are pure Scheme callbacks and transcoded ports
# are pure Zig port I/O (no OS syscalls, no threads), so this script
# confirms the full surface works identically to a non-sandboxed run,
# not a reduced one.
#
# Exit 0 = (srfi 181) fully available under --sandbox. Any failure = exit 1.

set -euo pipefail

KAAPPI="${KAAPPI:-zig-out/bin/kaappi}"
PASS=0
FAIL=0

assert_output() {
    local label="$1"
    local expr="$2"
    local expected="$3"
    local output
    output=$(echo "$expr" | "$KAAPPI" --sandbox 2>&1 || true)
    if [ "$output" = "$expected" ]; then
        echo "PASS: $label"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $label — expected '$expected', got: $output"
        FAIL=$((FAIL + 1))
    fi
}

assert_blocked() {
    local label="$1"
    local expr="$2"
    local output
    output=$(echo "$expr" | "$KAAPPI" --sandbox 2>&1 || true)
    if echo "$output" | grep -qi "error"; then
        echo "PASS: $label"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $label — no error produced, output: $output"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== (srfi 181) sandbox availability tests ==="
echo

assert_output "(srfi 181) imports under --sandbox" \
    '(import (srfi 181)) (display (procedure? make-custom-binary-input-port))' \
    "#t"

assert_output "custom port round trip under --sandbox" \
    '(import (scheme base) (srfi 181))
     (define p (make-custom-binary-input-port "s"
                 (lambda (bv start count)
                   (bytevector-u8-set! bv start 42) 1)
                 #f #f #f))
     (display (read-u8 p))' \
    "42"

assert_output "native-transcoder and transcoder? under --sandbox" \
    '(import (srfi 181)) (display (transcoder? (native-transcoder)))' \
    "#t"

assert_output "transcoded-port decode round trip under --sandbox" \
    '(import (scheme base) (srfi 181))
     (define bp (open-input-bytevector (string->utf8 "hi")))
     (define tp (transcoded-port bp (native-transcoder)))
     (display (list (read-char tp) (read-char tp) (eof-object? (read-char tp))))' \
    "(h i #t)"

assert_output "transcoded-port encode round trip under --sandbox" \
    '(import (scheme base) (srfi 181))
     (define bp (open-output-bytevector))
     (define tp (transcoded-port bp (native-transcoder)))
     (write-string "hi" tp)
     (display (utf8->string (get-output-bytevector bp)))' \
    "hi"

assert_output "bytevector->string / string->bytevector under --sandbox" \
    '(import (scheme base) (srfi 181))
     (display (bytevector->string (string->bytevector "café" (native-transcoder)) (native-transcoder)))' \
    "café"

assert_output "make-codec under --sandbox" \
    '(import (srfi 181)) (display (eqv? (make-codec "UTF-8") (utf-8-codec)))' \
    "#t"

assert_blocked "make-codec rejects an unrecognized name under --sandbox" \
    '(import (srfi 181)) (make-codec "shift-jis")'

echo
echo "=== Results ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"

if [ "$FAIL" -gt 0 ]; then
    echo "SRFI 181 SANDBOX AVAILABILITY FAILED"
    exit 1
fi

echo "(srfi 181) is fully available under --sandbox."
exit 0
