#!/bin/bash
# Exit code tests
# Uncaught read/compile/runtime errors in a script (file or stdin) must make
# the process exit non-zero so test runners can't report PASS on errored
# files. Explicit (exit N) always wins. Interactive REPL is unaffected.

set -euo pipefail

KAAPPI="${KAAPPI:-zig-out/bin/kaappi}"
PASS=0
FAIL=0
TMPDIR_TESTS="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TESTS"' EXIT

assert_exit_code() {
    local label="$1"
    local expected="$2"
    shift 2
    local status=0
    "$@" > /dev/null 2>&1 || status=$?
    if [[ "$status" -eq "$expected" ]]; then
        echo "PASS: $label"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $label — expected exit $expected, got $status"
        FAIL=$((FAIL + 1))
    fi
}

assert_stdin_exit_code() {
    local label="$1"
    local expected="$2"
    local input="$3"
    local status=0
    echo "$input" | "$KAAPPI" > /dev/null 2>&1 || status=$?
    if [[ "$status" -eq "$expected" ]]; then
        echo "PASS: $label"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $label — expected exit $expected, got $status"
        FAIL=$((FAIL + 1))
    fi
}

# Clean script exits 0
echo '(display "ok")' > "$TMPDIR_TESTS/ok.scm"
assert_exit_code "clean script exits 0" 0 "$KAAPPI" "$TMPDIR_TESTS/ok.scm"

# Uncaught runtime error exits non-zero
echo '(car 1)' > "$TMPDIR_TESTS/rt-err.scm"
assert_exit_code "uncaught runtime error exits 1" 1 "$KAAPPI" "$TMPDIR_TESTS/rt-err.scm"

# Error mid-file still flips exit code even when later forms succeed
printf '(car 1)\n(display "recovered")\n' > "$TMPDIR_TESTS/mid-err.scm"
assert_exit_code "mid-file error exits 1 despite recovery" 1 "$KAAPPI" "$TMPDIR_TESTS/mid-err.scm"

# Undefined variable exits non-zero
echo '(no-such-procedure-xyz)' > "$TMPDIR_TESTS/undef.scm"
assert_exit_code "undefined variable exits 1" 1 "$KAAPPI" "$TMPDIR_TESTS/undef.scm"

# Read error exits non-zero
echo '(unclosed (list' > "$TMPDIR_TESTS/read-err.scm"
assert_exit_code "read error exits 1" 1 "$KAAPPI" "$TMPDIR_TESTS/read-err.scm"

# Missing file exits non-zero
assert_exit_code "missing file exits 1" 1 "$KAAPPI" "$TMPDIR_TESTS/does-not-exist.scm"

# Explicit (exit 0) wins over earlier uncaught error (R7RS: exit sets the code)
printf '(car 1)\n(exit 0)\n' > "$TMPDIR_TESTS/exit0.scm"
assert_exit_code "explicit (exit 0) after error exits 0" 0 "$KAAPPI" "$TMPDIR_TESTS/exit0.scm"

# Guarded error is caught, exits 0
echo '(import (scheme base)) (guard (e (#t (display "caught"))) (car 1))' > "$TMPDIR_TESTS/guarded.scm"
assert_exit_code "guarded error exits 0" 0 "$KAAPPI" "$TMPDIR_TESTS/guarded.scm"

# Stdin scripts behave the same
assert_stdin_exit_code "clean stdin exits 0" 0 '(display "ok")'
assert_stdin_exit_code "stdin runtime error exits 1" 1 '(car 1)'

# CLI usage errors exit 2 (getopt convention), distinct from script errors.
# A missing argument to a value-taking flag must not silently exit 0.
assert_exit_code "--lib-path without arg exits 2" 2 "$KAAPPI" --lib-path
assert_exit_code "--timeout without arg exits 2" 2 "$KAAPPI" --timeout
assert_exit_code "--max-memory without arg exits 2" 2 "$KAAPPI" --max-memory
assert_exit_code "-o without arg exits 2" 2 "$KAAPPI" -o
assert_exit_code "--coverage-xml without arg exits 2" 2 "$KAAPPI" --coverage-xml
assert_exit_code "--profile-json without arg exits 2" 2 "$KAAPPI" --profile-json
assert_exit_code "--completions without shell exits 2" 2 "$KAAPPI" --completions

# Invalid (non-numeric, zero) values for --timeout / --max-memory are usage errors (#787)
assert_exit_code "--timeout non-numeric exits 2" 2 "$KAAPPI" --timeout abc "$TMPDIR_TESTS/ok.scm"
assert_exit_code "--timeout trailing text exits 2" 2 "$KAAPPI" --timeout 5s "$TMPDIR_TESTS/ok.scm"
assert_exit_code "--timeout zero exits 2" 2 "$KAAPPI" --timeout 0 "$TMPDIR_TESTS/ok.scm"
assert_exit_code "--timeout negative exits 2" 2 "$KAAPPI" --timeout -1 "$TMPDIR_TESTS/ok.scm"
assert_exit_code "--max-memory non-numeric exits 2" 2 "$KAAPPI" --max-memory lots "$TMPDIR_TESTS/ok.scm"
assert_exit_code "--max-memory zero exits 2" 2 "$KAAPPI" --max-memory 0 "$TMPDIR_TESTS/ok.scm"
assert_exit_code "--max-memory negative exits 2" 2 "$KAAPPI" --max-memory -1 "$TMPDIR_TESTS/ok.scm"

# Unknown completions shell is a usage error
assert_exit_code "--completions unknown shell exits 2" 2 "$KAAPPI" --completions badshell

# A typo'd flag must not be silently swallowed as a filename
assert_exit_code "unknown flag exits 2" 2 "$KAAPPI" --typo-flag "$TMPDIR_TESTS/ok.scm"

# Valid usage must still exit 0
assert_exit_code "--version exits 0" 0 "$KAAPPI" --version
assert_exit_code "--help exits 0" 0 "$KAAPPI" --help
assert_exit_code "--completions bash exits 0" 0 "$KAAPPI" --completions bash

# Compile-mode failures must be visible to CI too
printf '(+ 1\n' > "$TMPDIR_TESTS/unbal.scm"
assert_exit_code "--compile read error exits 1" 1 "$KAAPPI" --compile "$TMPDIR_TESTS/unbal.scm"
assert_exit_code "--compile missing file exits 1" 1 "$KAAPPI" --compile "$TMPDIR_TESTS/nope.scm"
assert_exit_code "--disassemble read error exits 1" 1 "$KAAPPI" --disassemble "$TMPDIR_TESTS/unbal.scm"

# Native-compile subcommand failures must also exit non-zero. A missing
# libkaappi_rt.a used to print an error but exit 0 with no output binary,
# so exit-code-checking harnesses (e.g. tests/fuzz/native-diff.sh) saw
# success. Source-level failures share the --emit-llvm path.
assert_exit_code "compile missing file exits 1" 1 "$KAAPPI" compile "$TMPDIR_TESTS/nope.scm" -o "$TMPDIR_TESTS/nat-out"
assert_exit_code "compile read error exits 1" 1 "$KAAPPI" compile "$TMPDIR_TESTS/unbal.scm" -o "$TMPDIR_TESTS/nat-out"
assert_exit_code "--emit-llvm missing file exits 1" 1 "$KAAPPI" --emit-llvm "$TMPDIR_TESTS/nope.scm"
assert_exit_code "--emit-llvm read error exits 1" 1 "$KAAPPI" --emit-llvm "$TMPDIR_TESTS/unbal.scm"

# Missing runtime library: run an isolated copy of the binary from a bare
# directory so the exe-relative and cwd-relative libkaappi_rt.a lookups all
# miss. Skipped when a system-wide runtime is installed (last fallback).
if [[ -f /usr/local/lib/libkaappi_rt.a ]]; then
    echo "SKIP: compile without libkaappi_rt.a exits 1 (system-wide runtime installed)"
else
    mkdir -p "$TMPDIR_TESTS/isobin"
    cp "$KAAPPI" "$TMPDIR_TESTS/isobin/kaappi"
    status=0
    (cd "$TMPDIR_TESTS" && env -u KAAPPI_LIB_DIR ./isobin/kaappi compile ok.scm -o nat-out) > /dev/null 2>&1 || status=$?
    if [[ "$status" -eq 1 ]]; then
        echo "PASS: compile without libkaappi_rt.a exits 1"
        PASS=$((PASS + 1))
    else
        echo "FAIL: compile without libkaappi_rt.a — expected exit 1, got $status"
        FAIL=$((FAIL + 1))
    fi
fi

# Missing C compiler / failing linker: a dummy libkaappi_rt.a satisfies the
# library lookup, and PATH controls what compiler the link step can find.
mkdir -p "$TMPDIR_TESTS/fakelib" "$TMPDIR_TESTS/emptypath" "$TMPDIR_TESTS/fakecc"
touch "$TMPDIR_TESTS/fakelib/libkaappi_rt.a"
printf '#!/bin/sh\nexit 1\n' > "$TMPDIR_TESTS/fakecc/cc"
chmod +x "$TMPDIR_TESTS/fakecc/cc"
assert_exit_code "compile without C compiler exits 1" 1 \
    env KAAPPI_LIB_DIR="$TMPDIR_TESTS/fakelib" PATH="$TMPDIR_TESTS/emptypath" \
    "$KAAPPI" compile "$TMPDIR_TESTS/ok.scm" -o "$TMPDIR_TESTS/nat-out"
assert_exit_code "compile with failing linker exits 1" 1 \
    env KAAPPI_LIB_DIR="$TMPDIR_TESTS/fakelib" PATH="$TMPDIR_TESTS/fakecc" \
    "$KAAPPI" compile "$TMPDIR_TESTS/ok.scm" -o "$TMPDIR_TESTS/nat-out"

# Passing a directory must error, not silently run an empty program (#789)
mkdir -p "$TMPDIR_TESTS/adir"
assert_exit_code "directory as script exits 1" 1 "$KAAPPI" "$TMPDIR_TESTS/adir"
assert_exit_code "--compile directory exits 1" 1 "$KAAPPI" --compile "$TMPDIR_TESTS/adir"
assert_exit_code "--disassemble directory exits 1" 1 "$KAAPPI" --disassemble "$TMPDIR_TESTS/adir"

# A build/inspect mode invoked with no file is a usage error, not exit 0
assert_exit_code "--compile without file exits 2" 2 "$KAAPPI" --compile
assert_exit_code "--disassemble without file exits 2" 2 "$KAAPPI" --disassemble
assert_exit_code "--emit-llvm without file exits 2" 2 "$KAAPPI" --emit-llvm
assert_exit_code "compile subcommand without file exits 2" 2 "$KAAPPI" compile

# SRFI-78 check-report with failure exits 1 and prints first-fail (#1220)
cat > "$TMPDIR_TESTS/srfi78-fail.scm" << 'SRFI78'
(import (scheme base) (srfi 78))
(check-reset!)
(check-set-mode! 'summary)
(check (+ 1 1) => 99)
(check-report)
SRFI78
assert_exit_code "SRFI-78 check-report with failure exits 1" 1 "$KAAPPI" "$TMPDIR_TESTS/srfi78-fail.scm"
# Also verify it prints "First failure:" (not crash on unbound caddr)
output=$("$KAAPPI" "$TMPDIR_TESTS/srfi78-fail.scm" 2>&1 || true)
if echo "$output" | grep -q "First failure:"; then
    echo "PASS: SRFI-78 check-report prints first failure"
    PASS=$((PASS + 1))
else
    echo "FAIL: SRFI-78 check-report missing 'First failure:' output"
    FAIL=$((FAIL + 1))
fi

echo ""
echo "exit-code: $PASS pass, $FAIL fail"
[[ $FAIL -eq 0 ]]
