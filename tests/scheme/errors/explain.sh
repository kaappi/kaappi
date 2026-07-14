#!/bin/bash
# `kaappi explain <code>` tests (kaappi#1507).
#
# `kaappi explain` turns the diagnostic registry into the binary's own offline
# reference (like `rustc --explain`). These checks assert the text and JSON
# surfaces, and — the load-bearing part — that every runnable example actually
# triggers the code it is documented under, so the docs can never drift from
# what the interpreter emits.

set -euo pipefail

KAAPPI="${KAAPPI:-zig-out/bin/kaappi}"

if ! command -v python3 >/dev/null 2>&1; then
    echo "FAIL: python3 is required to validate kaappi explain output"
    exit 1
fi

KAAPPI="$KAAPPI" python3 - <<'PY'
import json, os, re, subprocess, sys

KAAPPI = os.environ["KAAPPI"]
CODE_RE = re.compile(r'"code":"(KP\d{4})"')

# Codes whose registry `example` is representative (an inline one-liner cannot
# genuinely trigger them) — excluded from the self-consistency run only.
ILLUSTRATIVE = {"KP1009", "KP1010", "KP9000", "KP9001"}

passed = failed = 0

def check(cond, label, detail=""):
    global passed, failed
    if cond:
        print(f"PASS: {label}"); passed += 1
    else:
        print(f"FAIL: {label}  {detail}"); failed += 1

def explain(*args):
    return subprocess.run([KAAPPI, "explain", *args], capture_output=True, text=True)

def emitted_code(src, timeout_ms=None):
    """Run src through the interpreter, return the first KP code it emits."""
    args = [KAAPPI, "--diagnostics=json"]
    if timeout_ms is not None:
        args += ["--timeout", str(timeout_ms)]
    args.append("/dev/stdin")
    p = subprocess.run(args, input=src, capture_output=True, text=True, timeout=30)
    m = CODE_RE.search(p.stderr) or CODE_RE.search(p.stdout)
    return m.group(1) if m else None

# --- Text surface ---------------------------------------------------------

p = explain("KP3001")
check(p.returncode == 0, "explain KP3001 exits 0", p.returncode)
for needle in ("KP3001", "undefined-variable", "runtime", "Example:",
               "(display undefined-name)"):
    check(needle in p.stdout, f"text output contains {needle!r}")

# The code argument is accepted three ways.
check(explain("undefined-variable").stdout == p.stdout, "kebab name == KP number output")
check(explain("3001").stdout == p.stdout, "bare number == KP number output")
check(explain("kp3001").stdout == p.stdout, "lowercase prefix == KP number output")

# --- JSON surface ---------------------------------------------------------

p = explain("--json", "KP3004")
check(p.returncode == 0, "explain --json exits 0", p.returncode)
obj = json.loads(p.stdout)  # raises (and fails the suite) if not valid JSON
check(obj["code"] == "KP3004", "json code", obj.get("code"))
check(obj["name"] == "division-by-zero", "json name", obj.get("name"))
check(obj["stage"] == "runtime", "json stage", obj.get("stage"))
check(obj["severity"] == "error", "json severity", obj.get("severity"))
for field in ("message", "explanation", "example"):
    check(isinstance(obj.get(field), str) and obj[field], f"json has non-empty {field}")

# --- The full reference (--all) ------------------------------------------

entries = json.loads(explain("--all", "--json").stdout)
check(len(entries) >= 26, "explain --all --json lists every code", len(entries))
seen = set()
for e in entries:
    seen.add(e["code"])
    # Registry completeness at the CLI surface: no code may reach a user
    # without prose AND a triggering example.
    check(bool(e.get("explanation")), f"{e['code']} has an explanation")
    check(bool(e.get("example")), f"{e['code']} has an example")
check(len(seen) == len(entries), "every --all entry has a distinct code")

all_text = explain("--all").stdout
check("KP1001" in all_text and "KP9002" in all_text, "explain --all text spans the range")

# --- Error handling -------------------------------------------------------

p = explain("KP9999")
check(p.returncode == 2, "unknown code exits 2", p.returncode)
check(p.stdout == "", "unknown code prints nothing to stdout", p.stdout)
check("KP9999" in p.stderr, "unknown code names it on stderr", p.stderr)

p = explain()
check(p.returncode == 2, "missing argument exits 2", p.returncode)

p = explain("--all", "KP3001")
check(p.returncode == 2, "code + --all is rejected", p.returncode)

# --- Self-consistency: every runnable example triggers its own code -------

inconsistent = []
for e in entries:
    code, ex = e["code"], e["example"]
    if code in ILLUSTRATIVE:
        continue
    got = emitted_code(ex, timeout_ms=300 if code == "KP3009" else None)
    if got != code:
        inconsistent.append((code, got, ex.splitlines()[0]))
check(not inconsistent, "every runnable example triggers its documented code",
      inconsistent)

# --- Summary --------------------------------------------------------------

print()
print(f"Passed: {passed}")
print(f"Failed: {failed}")
sys.exit(1 if failed else 0)
PY

echo "All kaappi explain tests pass."
