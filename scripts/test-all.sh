#!/usr/bin/env bash
#
# Run tests for the core kaappi repo and all ecosystem packages.
# Assumes the workspace layout from the root CLAUDE.md — sibling dirs
# like ../kaappi-json, ../kaappi-net, etc.
#
# Usage:
#   bash scripts/test-all.sh          # run everything
#   bash scripts/test-all.sh --core   # core tests only
#   bash scripts/test-all.sh --eco    # ecosystem tests only

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CORE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKSPACE="$(cd "$CORE_DIR/.." && pwd)"
KAAPPI="$CORE_DIR/zig-out/bin/kaappi"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
RESET='\033[0m'

passed=0
failed=0
skipped=0
failures=""

run_core=true
run_eco=true
if [[ "${1:-}" == "--core" ]]; then run_eco=false; fi
if [[ "${1:-}" == "--eco" ]]; then run_core=false; fi

header() { printf "\n${BOLD}═══ %s ═══${RESET}\n" "$1"; }
pass()   { printf "  ${GREEN}✓${RESET} %s\n" "$1"; passed=$((passed + 1)); }
fail()   { printf "  ${RED}✗${RESET} %s\n" "$1"; failed=$((failed + 1)); failures="$failures\n  - $1"; }
skip()   { printf "  ${YELLOW}–${RESET} %s (skipped: %s)\n" "$1" "$2"; skipped=$((skipped + 1)); }

# Run a Scheme test file and detect failures from both exit code and output.
# Scheme test files sometimes exit 0 despite errors (undefined variables,
# runtime errors, compile errors). We capture output and scan for patterns.
run_scheme_test() {
    local output rc
    output=$("${@}" 2>&1) && rc=0 || rc=$?
    echo "$output"
    if [[ $rc -ne 0 ]]; then return 1; fi
    if echo "$output" | grep -qE '(runtime error|undefined variable|error\.CompileError| FAIL|: error:)'; then
        return 1
    fi
    return 0
}

# ── Build if needed ──────────────────────────────────────────────────
if [[ ! -x "$KAAPPI" ]]; then
    header "Building kaappi"
    (cd "$CORE_DIR" && zig build)
fi

# ── Core tests ───────────────────────────────────────────────────────
if $run_core; then
    header "Core: zig build test"
    if (cd "$CORE_DIR" && zig build test 2>&1); then
        pass "zig unit tests"
    else
        fail "zig unit tests"
    fi

    header "Core: Scheme test suites"
    if (cd "$CORE_DIR" && bash tests/scheme/run-all.sh 2>&1); then
        pass "Scheme test suites"
    else
        fail "Scheme test suites"
    fi
fi

# ── Ecosystem tests ──────────────────────────────────────────────────
if $run_eco; then

    # Pure Scheme libraries (no native build)
    pure_libs=(
        "kaappi-cli:tests/test-cli.scm"
        "kaappi-json:tests/test-json.scm"
        "kaappi-csv:tests/test-csv.scm"
        "kaappi-toml:tests/test-toml.scm"
        "kaappi-yaml:tests/test-yaml.scm"
        "kaappi-log:tests/test-log.scm"
        "kaappi-template:tests/test-template.scm"
        "kaappi-test:tests/test-framework.scm"
        "kaappi-bdd:tests/test-bdd.scm"
    )

    header "Ecosystem: pure Scheme libraries"
    for entry in "${pure_libs[@]}"; do
        repo="${entry%%:*}"
        tests="${entry#*:}"
        repo_dir="$WORKSPACE/$repo"

        if [[ ! -d "$repo_dir" ]]; then
            skip "$repo" "not cloned"
            continue
        fi

        ok=true
        for f in $tests; do
            if ! run_scheme_test "$KAAPPI" --lib-path "$repo_dir/lib" "$repo_dir/$f"; then
                ok=false
            fi
        done
        if $ok; then pass "$repo"; else fail "$repo"; fi
    done

    # Native libraries (need make, no services)
    native_libs=(
        "kaappi-net:tests/test-net.scm"
        "kaappi-crypto:tests/test-crypto.scm"
        "kaappi-math:tests/test-math.scm"
    )

    header "Ecosystem: native libraries"
    for entry in "${native_libs[@]}"; do
        repo="${entry%%:*}"
        tests="${entry#*:}"
        repo_dir="$WORKSPACE/$repo"

        if [[ ! -d "$repo_dir" ]]; then
            skip "$repo" "not cloned"
            continue
        fi
        if [[ -f "$repo_dir/Makefile" ]]; then
            make -C "$repo_dir" -q 2>/dev/null || make -C "$repo_dir" 2>&1
        fi

        ok=true
        for f in $tests; do
            if ! DYLD_LIBRARY_PATH="$repo_dir${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}" \
                 LD_LIBRARY_PATH="$repo_dir${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
                 run_scheme_test "$KAAPPI" --lib-path "$repo_dir/lib" "$repo_dir/$f"; then
                ok=false
            fi
        done
        if $ok; then pass "$repo"; else fail "$repo"; fi
    done

    # Libraries with ecosystem dependencies
    dep_libs=(
        "kaappi-email:kaappi-net:tests/test-mime.scm"
        "kaappi-http:kaappi-net:tests/test-parse.scm"
        "kaappi-web:kaappi-net kaappi-http kaappi-json:tests/test-routing.scm tests/test-session.scm"
    )

    header "Ecosystem: libraries with dependencies"
    for entry in "${dep_libs[@]}"; do
        repo="${entry%%:*}"
        rest="${entry#*:}"
        deps="${rest%%:*}"
        tests="${rest#*:}"
        repo_dir="$WORKSPACE/$repo"

        if [[ ! -d "$repo_dir" ]]; then
            skip "$repo" "not cloned"
            continue
        fi

        lib_flags="--lib-path $repo_dir/lib"
        native_paths=""

        # Build the repo itself if it has a Makefile
        if [[ -f "$repo_dir/Makefile" ]]; then
            make -C "$repo_dir" -q 2>/dev/null || make -C "$repo_dir" 2>&1
            native_paths="$repo_dir"
        fi

        dep_missing=false
        for dep in $deps; do
            dep_dir="$WORKSPACE/$dep"
            if [[ ! -d "$dep_dir" ]]; then
                skip "$repo" "$dep not cloned"
                dep_missing=true
                break
            fi
            lib_flags="$lib_flags --lib-path $dep_dir/lib"
            if [[ -f "$dep_dir/Makefile" ]]; then
                make -C "$dep_dir" -q 2>/dev/null || make -C "$dep_dir" 2>&1
                native_paths="${native_paths:+$native_paths:}$dep_dir"
            fi
        done
        if $dep_missing; then continue; fi

        ok=true
        for f in $tests; do
            if ! DYLD_LIBRARY_PATH="${native_paths}${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}" \
                 LD_LIBRARY_PATH="${native_paths}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
                 run_scheme_test "$KAAPPI" $lib_flags "$repo_dir/$f"; then
                ok=false
            fi
        done
        if $ok; then pass "$repo"; else fail "$repo"; fi
    done

    # Libraries with service dependencies (Redis, PostgreSQL, SQLite)
    service_libs=(
        "kaappi-redis:kaappi-net:redis:tests/test-resp.scm tests/test-commands.scm"
        "kaappi-pg::postgresql:tests/test-types.scm tests/test-dbapi.scm"
        "kaappi-sqlite::sqlite:tests/test-types.scm tests/test-dbapi.scm"
    )

    header "Ecosystem: libraries with services"
    for entry in "${service_libs[@]}"; do
        repo="${entry%%:*}"
        rest="${entry#*:}"
        deps="${rest%%:*}"
        rest2="${rest#*:}"
        service="${rest2%%:*}"
        tests="${rest2#*:}"
        repo_dir="$WORKSPACE/$repo"

        if [[ ! -d "$repo_dir" ]]; then
            skip "$repo" "not cloned"
            continue
        fi

        # Check service availability
        case "$service" in
            redis)
                if ! command -v redis-cli &>/dev/null || ! redis-cli ping &>/dev/null; then
                    skip "$repo" "redis not running"
                    continue
                fi ;;
            postgresql)
                if ! command -v psql &>/dev/null; then
                    skip "$repo" "psql not found"
                    continue
                fi ;;
            sqlite)
                ;; # SQLite is linked, no server needed
        esac

        if [[ -f "$repo_dir/Makefile" ]]; then
            make -C "$repo_dir" -q 2>/dev/null || make -C "$repo_dir" 2>&1
        fi

        lib_flags="--lib-path $repo_dir/lib"
        native_paths="$repo_dir"

        dep_missing=false
        for dep in $deps; do
            [[ -z "$dep" ]] && continue
            dep_dir="$WORKSPACE/$dep"
            if [[ ! -d "$dep_dir" ]]; then
                skip "$repo" "$dep not cloned"
                dep_missing=true
                break
            fi
            lib_flags="$lib_flags --lib-path $dep_dir/lib"
            if [[ -f "$dep_dir/Makefile" ]]; then
                make -C "$dep_dir" -q 2>/dev/null || make -C "$dep_dir" 2>&1
                native_paths="${native_paths}:$dep_dir"
            fi
        done
        if $dep_missing; then continue; fi

        ok=true
        for f in $tests; do
            if ! DYLD_LIBRARY_PATH="${native_paths}${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}" \
                 LD_LIBRARY_PATH="${native_paths}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
                 run_scheme_test "$KAAPPI" $lib_flags "$repo_dir/$f"; then
                ok=false
            fi
        done
        if $ok; then pass "$repo"; else fail "$repo"; fi
    done
fi

# ── Summary ──────────────────────────────────────────────────────────
header "Summary"
printf "  ${GREEN}%d passed${RESET}" "$passed"
if [[ $skipped -gt 0 ]]; then printf ", ${YELLOW}%d skipped${RESET}" "$skipped"; fi
if [[ $failed -gt 0 ]]; then
    printf ", ${RED}%d failed${RESET}" "$failed"
    printf "\n\n  ${RED}Failures:${RESET}%b\n" "$failures"
fi
printf "\n"

exit $failed
