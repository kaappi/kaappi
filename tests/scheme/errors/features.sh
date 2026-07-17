#!/bin/bash
# `kaappi features [--json]` tests (kaappi#1517).
#
# `kaappi features` is the CLI-boundary analogue of KEP-0004: an agent asks the
# binary what it can do without running a probe program. These checks assert the
# text and JSON surfaces, and — the load-bearing part — that the CLI's feature
# list is the *same table* the language resolves, by comparing it against the
# R7RS `(features)` procedure. If the two ever drift, this fails.

set -euo pipefail

KAAPPI="${KAAPPI:-zig-out/bin/kaappi}"

if ! command -v python3 >/dev/null 2>&1; then
    echo "FAIL: python3 is required to validate kaappi features output"
    exit 1
fi

KAAPPI="$KAAPPI" python3 - <<'PY'
import json, os, subprocess, sys

KAAPPI = os.environ["KAAPPI"]

passed = failed = 0

def check(cond, label, detail=""):
    global passed, failed
    if cond:
        print(f"PASS: {label}"); passed += 1
    else:
        print(f"FAIL: {label}  {detail}"); failed += 1

def features(*args):
    return subprocess.run([KAAPPI, "features", *args], capture_output=True, text=True)

# --- Text surface ---------------------------------------------------------

p = features()
check(p.returncode == 0, "features exits 0", p.returncode)
for needle in ("Kaappi Scheme v", "target", "build mode", "Features",
               "kaappi-fibers", "SRFIs:", "built-in", "portable", "Limits:"):
    check(needle in p.stdout, f"text output contains {needle!r}")

# --- JSON surface ---------------------------------------------------------

p = features("--json")
check(p.returncode == 0, "features --json exits 0", p.returncode)
obj = json.loads(p.stdout)  # raises (and fails the suite) if not valid JSON

check(isinstance(obj.get("version"), str) and obj["version"], "json version")
check(isinstance(obj.get("build_id"), str) and obj["build_id"], "json build_id")
check(isinstance(obj.get("target"), str) and "-" in obj["target"], "json target triple")
check(isinstance(obj.get("build_mode"), str) and obj["build_mode"], "json build_mode")
check(obj.get("sandbox_available") is True, "json sandbox_available (native)")
check(isinstance(obj.get("gc_stress"), bool), "json gc_stress is bool")

feats = obj.get("features")
check(isinstance(feats, list) and all(isinstance(f, str) for f in feats), "json features is a string list")

srfis = obj.get("srfis", {})
builtin = srfis.get("builtin")
portable = srfis.get("portable")
check(isinstance(builtin, list) and all(isinstance(n, int) for n in builtin), "json srfis.builtin is an int list")
check(isinstance(portable, list) and all(isinstance(n, int) for n in portable), "json srfis.portable is an int list")
check(builtin == sorted(builtin), "builtin srfis sorted")
check(portable == sorted(portable), "portable srfis sorted")
check(9 in builtin, "srfi 9 is built-in")           # the syntax-only extra lib
check(1 in builtin and 170 in builtin, "srfi 1 and 170 are built-in")
check(64 in portable and 158 in portable, "srfi 64 and 158 are portable")
check(not (set(builtin) & set(portable)), "no SRFI is both built-in and portable")

limits = obj.get("limits", {})
for k in ("initial_frame_capacity", "initial_register_capacity", "gc_initial_threshold"):
    check(isinstance(limits.get(k), int) and limits[k] > 0, f"json limits.{k}")

# --- The load-bearing property: CLI features == R7RS (features) -----------

prog = ('(import (scheme base)) '
        '(for-each (lambda (f) (display f) (newline)) (features))')
# Program fed on stdin with no file argument (the runStdin path): works on
# every platform, unlike a /dev/stdin pseudo-file argument.
lang = subprocess.run([KAAPPI], input=prog, capture_output=True, text=True)
lang_features = [ln for ln in lang.stdout.splitlines() if ln]
# Same members (cond-expand resolves against this exact set) AND same order
# (both iterate the one `types.platform_features` array).
check(feats == lang_features,
      "CLI features list equals the R7RS (features) table",
      f"cli={feats} lang={lang_features}")

# Every advertised feature is genuinely recognized by cond-expand.
for f in feats:
    src = f'(import (scheme base) (scheme write)) (cond-expand ({f} (display "y")) (else (display "n")))'
    r = subprocess.run([KAAPPI], input=src, capture_output=True, text=True)
    check(r.stdout.strip() == "y", f"cond-expand recognizes {f!r}", r.stdout)

# --- Error handling -------------------------------------------------------

p = features("--bogus")
check(p.returncode == 2, "unknown option exits 2", p.returncode)
check("--bogus" in p.stderr, "unknown option named on stderr", p.stderr)

p = features("--help")
check(p.returncode == 0, "features --help exits 0", p.returncode)
check("Usage: kaappi features" in p.stdout, "help shows usage")

# --- Summary --------------------------------------------------------------

print()
print(f"Passed: {passed}")
print(f"Failed: {failed}")
sys.exit(1 if failed else 0)
PY

echo "All kaappi features tests pass."
