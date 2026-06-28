#!/usr/bin/env bash
#
# Run tests for the core kaappi repo and/or ecosystem packages.
# Assumes the workspace layout from the root CLAUDE.md — sibling dirs
# like ../kaappi-json, ../kaappi-net, etc.
#
# Usage:
#   bash scripts/run-tests.sh                   # run everything
#   bash scripts/run-tests.sh --core             # core tests only
#   bash scripts/run-tests.sh --eco              # ecosystem tests only
#   bash scripts/run-tests.sh ../kaappi-json     # single ecosystem repo
#   bash scripts/run-tests.sh ../kaappi-net ../kaappi-http  # multiple repos

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

header() { printf "\n${BOLD}═══ %s ═══${RESET}\n" "$1"; }
pass()   { printf "  ${GREEN}✓${RESET} %s\n" "$1"; passed=$((passed + 1)); }
fail()   { printf "  ${RED}✗${RESET} %s\n" "$1"; failed=$((failed + 1)); failures="$failures\n  - $1"; }
skip()   { printf "  ${YELLOW}–${RESET} %s (skipped: %s)\n" "$1" "$2"; skipped=$((skipped + 1)); }

# Run a Scheme test file and detect failures from both exit code and output.
# Scheme test files sometimes exit 0 despite errors (undefined variables,
# runtime errors). We capture output and scan for error patterns.
run_scheme_test() {
    local output rc
    output=$("${@}" 2>&1) && rc=0 || rc=$?
    echo "$output"
    if [[ $rc -ne 0 ]]; then return 1; fi
    if echo "$output" | grep -v 'ffi-open:' | grep -v 'runtime error: error.CompileError' \
         | grep -qE '(undefined variable| FAIL|: error:)'; then
        return 1
    fi
    return 0
}

# ── Registry: repo → deps:test-files ─────────────────────────────────
declare -A REPO_INFO=(
    [kaappi-cli]="::tests/test-cli.scm"
    [kaappi-json]="::tests/test-json.scm"
    [kaappi-csv]="::tests/test-csv.scm"
    [kaappi-toml]="::tests/test-toml.scm"
    [kaappi-yaml]="::tests/test-yaml.scm"
    [kaappi-log]="::tests/test-log.scm"
    [kaappi-template]="::tests/test-template.scm"
    [kaappi-test]="::tests/test-framework.scm"
    [kaappi-bdd]="::tests/test-bdd.scm"
    [kaappi-net]="::tests/test-net.scm"
    [kaappi-crypto]="::tests/test-crypto.scm"
    [kaappi-math]="::tests/test-math.scm"
    [kaappi-email]="kaappi-net:tests/test-mime.scm"
    [kaappi-http]="kaappi-net:tests/test-parse.scm"
    [kaappi-web]="kaappi-net kaappi-http kaappi-json:tests/test-routing.scm tests/test-session.scm"
    [kaappi-redis]="kaappi-net:tests/test-resp.scm tests/test-commands.scm"
    [kaappi-pg]="::tests/test-types.scm tests/test-dbapi.scm"
    [kaappi-sqlite]="::tests/test-types.scm tests/test-dbapi.scm"
)

declare -A SERVICE_REQ=(
    [kaappi-redis]="redis"
    [kaappi-pg]="postgresql"
)

# ── Build kaappi if needed ───────────────────────────────────────────
ensure_kaappi() {
    if [[ ! -x "$KAAPPI" ]]; then
        header "Building kaappi"
        (cd "$CORE_DIR" && zig build)
    fi
}

# ── Test a single ecosystem repo ─────────────────────────────────────
test_repo() {
    local repo="$1"
    local info="${REPO_INFO[$repo]:-}"

    if [[ -z "$info" ]]; then
        skip "$repo" "unknown repo"
        return
    fi

    local deps="${info%%:*}"
    local tests="${info#*:}"
    local repo_dir="$WORKSPACE/$repo"

    if [[ ! -d "$repo_dir" ]]; then
        skip "$repo" "not cloned"
        return
    fi

    # Check service requirements
    local service="${SERVICE_REQ[$repo]:-}"
    case "$service" in
        redis)
            if ! command -v redis-cli &>/dev/null || ! redis-cli ping &>/dev/null; then
                skip "$repo" "redis not running"; return
            fi ;;
        postgresql)
            if ! command -v psql &>/dev/null; then
                skip "$repo" "psql not found"; return
            fi ;;
    esac

    # Build the repo if it has a Makefile
    if [[ -f "$repo_dir/Makefile" ]]; then
        make -C "$repo_dir" -q 2>/dev/null || make -C "$repo_dir" 2>&1
    fi

    local lib_flags="--lib-path $repo_dir/lib"
    local native_paths=""
    [[ -f "$repo_dir/Makefile" ]] && native_paths="$repo_dir"

    local dep_missing=false
    for dep in $deps; do
        [[ -z "$dep" ]] && continue
        local dep_dir="$WORKSPACE/$dep"
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
    if $dep_missing; then return; fi

    local ok=true
    for f in $tests; do
        if ! DYLD_LIBRARY_PATH="${native_paths}${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}" \
             LD_LIBRARY_PATH="${native_paths}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
             run_scheme_test "$KAAPPI" $lib_flags "$repo_dir/$f"; then
            ok=false
        fi
    done
    if $ok; then pass "$repo"; else fail "$repo"; fi
}

# ── Core tests ───────────────────────────────────────────────────────
run_core_tests() {
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
}

# ── All ecosystem tests ──────────────────────────────────────────────
run_eco_tests() {
    header "Ecosystem: pure Scheme libraries"
    for repo in kaappi-cli kaappi-json kaappi-csv kaappi-toml kaappi-yaml \
                kaappi-log kaappi-template kaappi-test kaappi-bdd; do
        test_repo "$repo"
    done

    header "Ecosystem: native libraries"
    for repo in kaappi-net kaappi-crypto kaappi-math; do
        test_repo "$repo"
    done

    header "Ecosystem: libraries with dependencies"
    for repo in kaappi-email kaappi-http kaappi-web; do
        test_repo "$repo"
    done

    header "Ecosystem: libraries with services"
    for repo in kaappi-redis kaappi-pg kaappi-sqlite; do
        test_repo "$repo"
    done
}

# ── Main ─────────────────────────────────────────────────────────────
if [[ $# -eq 0 ]]; then
    ensure_kaappi
    run_core_tests
    run_eco_tests
elif [[ "$1" == "--core" ]]; then
    ensure_kaappi
    run_core_tests
elif [[ "$1" == "--eco" ]]; then
    ensure_kaappi
    run_eco_tests
else
    ensure_kaappi
    for arg in "$@"; do
        repo="$(basename "$arg")"
        if [[ "$repo" == "kaappi" ]]; then
            run_core_tests
        else
            test_repo "$repo"
        fi
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
