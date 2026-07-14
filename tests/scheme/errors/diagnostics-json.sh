#!/bin/bash
# --diagnostics=json structured output tests (kaappi#1505).
#
# Every diagnostic emitted under --diagnostics=json must be a valid LSP
# Diagnostic object, one per line on stderr, covering all four pipeline stages
# (read, expand, compile, runtime). We validate with a *real* JSON parser
# (python3), not grep, so a malformed object or a leaked text line fails here.

set -euo pipefail

KAAPPI="${KAAPPI:-zig-out/bin/kaappi}"

if ! command -v python3 >/dev/null 2>&1; then
    echo "FAIL: python3 is required to validate JSON diagnostics output"
    exit 1
fi

# The whole suite is a self-contained python driver: it runs the interpreter for
# each case, parses stderr with json.loads, and asserts on the structured
# fields. It prints PASS/FAIL per check and exits non-zero if any check fails.
KAAPPI="$KAAPPI" python3 - <<'PY'
import json, os, re, subprocess, sys

KAAPPI = os.environ["KAAPPI"]
CODE_RE = re.compile(r"^KP\d{4}$")
ZIG_LEAK_RE = re.compile(r"error\.[A-Z][A-Za-z]+")

passed = 0
failed = 0

def check(cond, label, detail=""):
    global passed, failed
    if cond:
        print(f"PASS: {label}")
        passed += 1
    else:
        print(f"FAIL: {label}  {detail}")
        failed += 1

def run(src, json_mode=True):
    args = [KAAPPI]
    if json_mode:
        args.append("--diagnostics=json")
    return subprocess.run(args, input=src.encode(), capture_output=True)

def parse_lines(stderr):
    """Parse every non-empty stderr line as JSON. Raises if any line is not
    valid JSON — that is exactly how a leaked snippet/backtrace line is caught.

    A Debug build's DebugAllocator appends "…leaked:" reports to stderr at
    process teardown, *after* all diagnostics. That is a build-mode artifact,
    not part of the product's stderr contract, so cut everything from the first
    such report onward. Kaappi's own diagnostics are emitted during execution
    (before teardown), so this preserves the strict check for a real text leak."""
    text = stderr.decode()
    for marker in ("error(DebugAllocator)", "error(gpa)"):
        idx = text.find(marker)
        if idx != -1:
            text = text[:idx]
    return [json.loads(l) for l in text.splitlines() if l.strip()]

def assert_valid_diag(d):
    """Structural check of one LSP Diagnostic. Returns True or raises."""
    r = d["range"]
    for pt in (r["start"], r["end"]):
        assert isinstance(pt["line"], int) and pt["line"] >= 0, pt
        assert isinstance(pt["character"], int) and pt["character"] >= 0, pt
    assert d["severity"] == 1, d["severity"]
    assert CODE_RE.match(d["code"]), d["code"]
    assert d["source"] == "kaappi", d["source"]
    assert isinstance(d["message"], str) and d["message"], d
    assert not ZIG_LEAK_RE.search(d["message"]), d["message"]
    return True

def single_diag(label, src, expect_code_prefix, expect_msg_substr=None):
    """Run src, assert exactly one valid diagnostic with the expected code
    prefix (and optional message substring)."""
    p = run(src)
    try:
        diags = parse_lines(p.stderr)
    except Exception as e:
        check(False, f"{label}: stderr is valid JSON Lines", f"{e!r}: {p.stderr!r}")
        return None
    if len(diags) != 1:
        check(False, f"{label}: exactly one diagnostic", diags)
        return None
    d = diags[0]
    try:
        assert_valid_diag(d)
    except AssertionError as e:
        check(False, f"{label}: object is a valid LSP Diagnostic", repr(e))
        return None
    ok = d["code"].startswith(expect_code_prefix)
    check(ok, f"{label}: code is {expect_code_prefix}xxx", d["code"])
    if expect_msg_substr is not None:
        check(expect_msg_substr in d["message"],
              f"{label}: message mentions '{expect_msg_substr}'", d["message"])
    check(p.returncode != 0, f"{label}: exits non-zero", p.returncode)
    return d

# --- All four stages produce a valid, coded diagnostic --------------------

# Read / lexical (KP1xxx): unterminated string.
single_diag("read stage", '(display "abc', "KP1", "unterminated string")

# Expand stage (KP2002): a macro/syntax rejection carries its detail message.
single_diag("expand stage", '(syntax-error "bad usage" 42)', "KP2", "bad usage")

# Compile stage (KP2xxx): an if with no test.
single_diag("compile stage", "(if)", "KP2")

# Runtime stage (KP3xxx): car on a non-pair.
single_diag("runtime stage", "(car 5)", "KP3", "car")

# --- Suggestions map to data.suggestions ----------------------------------

d = single_diag("undefined variable",
                "(define count 1) (display countr)", "KP3", None)
if d is not None:
    check(d["code"] == "KP3001", "undefined variable is KP3001", d["code"])
    # The message is the clean form; the fix is structured, not prose.
    check(d["message"] == "undefined variable 'countr'",
          "undefined-variable message is clean (no 'did you mean' prose)",
          d["message"])
    sugg = d.get("data", {}).get("suggestions")
    check(sugg == [{"kind": "rename", "replacement": "count"}],
          "data.suggestions offers the rename fix", sugg)

# A diagnostic with no fix must omit data entirely.
d = single_diag("no-suggestion diagnostic", "(car 5)", "KP3", None)
if d is not None:
    check("data" not in d, "diagnostic without a fix omits 'data'", d.get("data"))

# --- Stream hygiene -------------------------------------------------------

# A runtime error deep in a call chain must still emit exactly one JSON object;
# the human backtrace/snippet must NOT leak onto stderr (it would break parsing).
p = run("(define (a x) (b x))\n(define (b x) (car x))\n(a 42)\n")
try:
    diags = parse_lines(p.stderr)
    check(len(diags) == 1 and diags[0]["code"] == "KP3002",
          "backtrace suppressed: stderr stays one JSON object", diags)
except Exception as e:
    check(False, "backtrace case: stderr is valid JSON Lines", f"{e!r}: {p.stderr!r}")

# Multiple top-level errors → one object per line, each independently valid.
p = run("(car 5)\n(vector-ref (vector 1) 9)\n")
try:
    diags = parse_lines(p.stderr)
    codes = [d["code"] for d in diags]
    check(len(diags) == 2 and all(assert_valid_diag(d) for d in diags),
          "multiple errors: one valid object per line", diags)
    check(codes == ["KP3002", "KP3006"], "multiple errors keep their codes", codes)
except Exception as e:
    check(False, "multi-error case: stderr is valid JSON Lines", f"{e!r}: {p.stderr!r}")

# Program stdout is not polluted by diagnostics on stderr.
p = run('(display "hi") (newline) (car 5)')
check(p.stdout == b"hi\n", "program stdout is clean in JSON mode", p.stdout)
try:
    diags = parse_lines(p.stderr)
    check(len(diags) == 1 and diags[0]["code"] == "KP3002",
          "stdout/stderr are cleanly separated", diags)
except Exception as e:
    check(False, "stdout-separation case: stderr is valid JSON", f"{e!r}: {p.stderr!r}")

# --- Text mode remains the default ----------------------------------------

p = run("(display countr)", json_mode=False)
err = p.stderr.decode()
check(not err.lstrip().startswith("{"), "default mode is not JSON", err)
check("error[KP3001]" in err, "default mode keeps the human text format", err)

# --- Summary --------------------------------------------------------------

print()
print(f"Passed: {passed}")
print(f"Failed: {failed}")
sys.exit(1 if failed else 0)
PY

echo "All --diagnostics=json tests pass."
