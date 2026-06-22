#!/bin/bash
# Compare two benchmark JSON files and flag regressions.
# Usage: bash benchmarks/compare-benchmarks.sh baseline.json current.json
#
# Exits non-zero if any benchmark regressed >10% in wall time.

set -euo pipefail

THRESHOLD="${THRESHOLD:-10}"

if [ $# -ne 2 ]; then
    echo "Usage: compare-benchmarks.sh <baseline.json> <current.json>"
    exit 1
fi

BASELINE="$1"
CURRENT="$2"

if ! command -v python3 >/dev/null 2>&1; then
    echo "warning: python3 not available, skipping regression check"
    exit 0
fi

python3 -c "
import json, sys

threshold = float('$THRESHOLD')

with open('$BASELINE') as f:
    baseline = {b['name']: b for b in json.load(f)}
with open('$CURRENT') as f:
    current = {c['name']: c for c in json.load(f)}

regressions = []
print(f'{'Benchmark':<12} {'Baseline':>10} {'Current':>10} {'Delta':>8}  Status')
print(f'{'---------':<12} {'--------':>10} {'-------':>10} {'-----':>8}  ------')

for name in sorted(set(list(baseline.keys()) + list(current.keys()))):
    b = baseline.get(name, {})
    c = current.get(name, {})
    bt = b.get('seconds', 0)
    ct = c.get('seconds', 0)
    if bt > 0:
        delta_pct = ((ct - bt) / bt) * 100
        status = 'REGRESSED' if delta_pct > threshold else 'ok'
        if delta_pct > threshold:
            regressions.append(name)
        print(f'{name:<12} {bt:>9.3f}s {ct:>9.3f}s {delta_pct:>+7.1f}%  {status}')
    else:
        print(f'{name:<12} {\"n/a\":>10} {ct:>9.3f}s {\"n/a\":>8}  new')

if regressions:
    print(f'\nREGRESSION DETECTED (>{threshold}%): {', '.join(regressions)}')
    sys.exit(1)
else:
    print(f'\nNo regressions (threshold: {threshold}%)')
"
