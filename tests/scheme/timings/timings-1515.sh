#!/bin/bash
# Regression test for #1515: `--timings` / `--timings=json` — per-stage pipeline
# timings + cache HIT/MISS visibility on the run and compile paths.
#
# Hermetic: KAAPPI_HOME points at a throwaway dir so the real user cache is
# never read or written. Timing output goes to stderr (like --diagnostics=json),
# so stdout stays clean for piping — the tests assert both.
#
# Usage: bash tests/scheme/timings/timings-1515.sh [path-to-kaappi]

set -euo pipefail

KAAPPI="${1:-zig-out/bin/kaappi}"
PASS=0
FAIL=0

HOMEDIR="$(mktemp -d)"
PROGDIR="$(mktemp -d)"
trap 'rm -rf "$HOMEDIR" "$PROGDIR"' EXIT
export KAAPPI_HOME="$HOMEDIR"

# Import-free program (the run-cache is, pre-existing, skipped for programs that
# import — see #1516), so HIT/MISS is exercised.
PROG="$PROGDIR/square.scm"
cat > "$PROG" <<'SCM'
(define (square x) (* x x))
(display (square 9))
(newline)
SCM

check() { # label expected-substring actual
    if [[ "$3" == *"$2"* ]]; then
        echo "PASS: $1"; PASS=$((PASS + 1))
    else
        echo "FAIL: $1"; echo "  expected to contain: $2"; echo "  actual: $3"
        FAIL=$((FAIL + 1))
    fi
}

check_absent() { # label unexpected-substring actual
    if [[ "$3" != *"$2"* ]]; then
        echo "PASS: $1"; PASS=$((PASS + 1))
    else
        echo "FAIL: $1"; echo "  expected NOT to contain: $2"; echo "  actual: $3"
        FAIL=$((FAIL + 1))
    fi
}

check_exit() { # label expected actual
    if [[ "$3" -eq "$2" ]]; then
        echo "PASS: $1"; PASS=$((PASS + 1))
    else
        echo "FAIL: $1 — expected exit $2, got $3"; FAIL=$((FAIL + 1))
    fi
}

# Capture only stderr (where timings are written); send stdout to /dev/null.
stderr_of() { "$@" 2>&1 1>/dev/null; }
# Capture only stdout (program output); discard stderr.
stdout_of() { "$@" 2>/dev/null; }

# Validate that a string is well-formed JSON when python3 is available; a no-op
# (recorded as a skip note) otherwise, so the test never hard-depends on python.
check_json_parses() { # label json
    if command -v python3 >/dev/null 2>&1; then
        if printf '%s' "$2" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then
            echo "PASS: $1 (valid JSON)"; PASS=$((PASS + 1))
        else
            echo "FAIL: $1 — not valid JSON"; echo "  actual: $2"; FAIL=$((FAIL + 1))
        fi
    else
        echo "SKIP: $1 (python3 unavailable)"
    fi
}

# ── 1. Run path, text, first run → cache MISS with all stages ───────────────
out="$(stderr_of "$KAAPPI" --timings "$PROG")"
check "run text: has a timings line" "timings:" "$out"
for stage in read expand lower optimize emit execute; do
    check "run text MISS: shows stage '$stage'" "$stage " "$out"
done
check "run text: first run is a MISS that wrote the cache" "cache: MISS (wrote " "$out"
check "run text: MISS names the .sbc path" ".sbc" "$out"

# Program stdout must be exactly its own output — no timing noise leaks in.
prog_out="$(stdout_of "$KAAPPI" --timings "$PROG")"
check "run: stdout carries only program output" "81" "$prog_out"
check_absent "run: timings never pollute stdout" "timings:" "$prog_out"
check_absent "run: cache line never pollutes stdout" "cache:" "$prog_out"

# ── 2. Run path, text, second run → cache HIT (compile stages skipped) ──────
out="$(stderr_of "$KAAPPI" --timings "$PROG")"
check "run text: second run is a HIT" "cache: HIT (" "$out"
check "run text HIT: still reports execute" "execute " "$out"
check_absent "run text HIT: compile stages are hidden" "read " "$out"

# ── 3. Run path, JSON → stable, well-formed shape ──────────────────────────
json="$(stderr_of "$KAAPPI" --timings=json "$PROG")"
check_json_parses "run json" "$json"
check "run json: mode is run" '"mode":"run"' "$json"
check "run json: has stages_ms object" '"stages_ms":{' "$json"
for key in read expand lower optimize emit execute; do
    check "run json: stages_ms has key '$key'" "\"$key\":" "$json"
done
check "run json: cache status present (hit on this run)" '"cache":{"status":"hit"' "$json"
check "run json: cache path present" '"path":"' "$json"
check "run json: cache written flag present" '"written":' "$json"

# ── 4. Cache off: --no-ir-opt and --sandbox never leave the cache blank ─────
out="$(stderr_of "$KAAPPI" --timings --no-ir-opt "$PROG")"
check "run text: --no-ir-opt reports cache off with reason" "cache: off (--no-ir-opt)" "$out"
out="$(stderr_of "$KAAPPI" --timings --sandbox "$PROG")"
check "run text: --sandbox reports cache off with reason" "cache: off (sandbox)" "$out"

# ── 5. Imported programs: a MISS that is honestly not cached ────────────────
IMP="$PROGDIR/imp.scm"
cat > "$IMP" <<'SCM'
(import (scheme base) (scheme write))
(display (+ 1 2))
(newline)
SCM
json="$(stderr_of "$KAAPPI" --timings=json "$IMP")"
check_json_parses "imports json" "$json"
check "imports json: recorded as a miss" '"status":"miss"' "$json"
check "imports json: not written to cache" '"written":false' "$json"
check "imports json: reason names imports" '"reason":"imports"' "$json"

# ── 6. Compile path (--compile): stages + output, no cache/execute ──────────
json="$(stderr_of "$KAAPPI" --timings=json --compile "$PROG" -o "$PROGDIR/square.sbc")"
check_json_parses "compile json" "$json"
check "compile json: mode is compile" '"mode":"compile"' "$json"
check "compile json: reports emit stage" '"emit":' "$json"
check "compile json: names the output artifact" '"output":"' "$json"
check_absent "compile json: no execute stage" '"execute":' "$json"
check_absent "compile json: no cache object" '"cache"' "$json"

# ── 7. No flag → no timing output at all ────────────────────────────────────
out="$(stderr_of "$KAAPPI" "$PROG")"
check_absent "no flag: no timings on stderr" "timings:" "$out"
check_absent "no flag: no cache line on stderr" "cache:" "$out"

# ── 8. Bad format is a usage error ──────────────────────────────────────────
set +e
"$KAAPPI" --timings=bogus "$PROG" >/dev/null 2>&1
check_exit "invalid --timings format exits 2" 2 $?
set -e

echo ""
echo "$PASS pass, $FAIL fail"
[[ $FAIL -eq 0 ]]
