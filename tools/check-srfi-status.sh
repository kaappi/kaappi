#!/usr/bin/env bash
#
# check-srfi-status.sh — fail if Kaappi ships any SRFI that is not yet "final"
# in the canonical SRFI registry.
#
# The set of implemented SRFIs comes from `kaappi features --json` — the derived
# source of truth (built-in Zig SRFIs + the portable lib/srfi/*.sld files, see
# docs/dev/features.md) — plus SRFI 261, a resolver-level naming convention with
# no .sld file. Each number's status is checked against admin/srfi-data.scm from
# the srfi-common repository, which is what https://srfi.schemers.org is built
# from.
#
# Exit codes:
#   0   all implemented SRFIs are final
#   1   an implemented SRFI is non-final (draft/withdrawn) or absent from the
#       registry — the failure this guard exists to catch
#   77  SKIP (no usable kaappi binary, or the registry could not be fetched);
#       the automake SKIP convention the rest of the suite uses. CI treats it as
#       a warning so a network blip never reds an unrelated change.
#
# Usage: bash tools/check-srfi-status.sh [path-to-kaappi]
#        KAAPPI=/path/to/kaappi bash tools/check-srfi-status.sh

set -uo pipefail

KAAPPI="${1:-${KAAPPI:-zig-out/bin/kaappi}}"
DATA_URL="https://raw.githubusercontent.com/scheme-requests-for-implementation/srfi-common/master/admin/srfi-data.scm"

if [ ! -x "$KAAPPI" ]; then
    echo "SKIP: no kaappi binary at '$KAAPPI' (build it, or pass the path as \$1)"
    exit 77
fi

# 1. Implemented SRFI numbers, straight from the binary's own registry. The
#    builtin/portable values are flat integer arrays; flatten newlines first so
#    the array regex matches whether or not the JSON is pretty-printed. SRFI 261
#    has no .sld file (it is a resolver convention), so add it explicitly.
json="$("$KAAPPI" features --json | tr '\n' ' ')" || {
    echo "FAIL: 'kaappi features --json' failed"
    exit 1
}
implemented="$(
    {
        printf '%s\n' "$json" |
            grep -oE '"builtin"[[:space:]]*:[[:space:]]*\[[^]]*\]' | grep -oE '[0-9]+'
        printf '%s\n' "$json" |
            grep -oE '"portable"[[:space:]]*:[[:space:]]*\[[^]]*\]' | grep -oE '[0-9]+'
        echo 261
    } | sort -un
)"
if [ -z "$implemented" ]; then
    echo "FAIL: could not extract SRFI numbers from 'kaappi features --json'"
    exit 1
fi

# 2. Fetch the canonical registry (retry; soft-skip on hard network failure).
data="$(mktemp)"
trap 'rm -f "$data"' EXIT
fetched=
for attempt in 1 2 3; do
    if curl -fsSL --max-time 30 "$DATA_URL" -o "$data" && [ -s "$data" ]; then
        fetched=1
        break
    fi
    sleep $((attempt * 2))
done
if [ -z "$fetched" ]; then
    echo "SKIP: could not fetch srfi-data.scm from $DATA_URL"
    exit 77
fi

# 3. Extract "<number> <status>" pairs. Each registry entry is an alist whose
#    (number N) line precedes its (status X) line, e.g.
#      ((number 1)
#       (status final)
#       (title "List Library") ...)
statuses="$(
    awk '
      /^\(\(number [0-9]+\)/ {
        num = $0; sub(/^\(\(number /, "", num); sub(/\).*/, "", num); have = 1
      }
      have && /^[[:space:]]*\(status [a-z-]+\)/ {
        st = $0; sub(/^[[:space:]]*\(status /, "", st); sub(/\).*/, "", st)
        print num, st; have = 0
      }
    ' "$data"
)"
if [ -z "$statuses" ]; then
    echo "FAIL: could not parse any entries from srfi-data.scm"
    exit 1
fi

# 4. Cross-reference: every implemented SRFI must be present and final.
offenders=0
count=0
while IFS= read -r n; do
    [ -n "$n" ] || continue
    count=$((count + 1))
    st="$(awk -v n="$n" '$1 == n { print $2; exit }' <<< "$statuses")"
    if [ -z "$st" ]; then
        echo "FAIL: SRFI $n is implemented but absent from srfi-data.scm"
        offenders=$((offenders + 1))
    elif [ "$st" != "final" ]; then
        echo "FAIL: SRFI $n is implemented but its status is '$st' (expected 'final')"
        offenders=$((offenders + 1))
    fi
done <<< "$implemented"

if [ "$offenders" -ne 0 ]; then
    echo
    echo "$offenders non-final SRFI(s) implemented — Kaappi ships only final SRFIs."
    echo "See https://srfi.schemers.org/?statuses=final for the authoritative list."
    exit 1
fi

echo "OK: all $count implemented SRFIs are final."
exit 0
