#!/usr/bin/env python3
"""Generate the kaappi-lang.org diagnostic reference page from the registry.

The page can never drift from what the binary emits because it is generated
*from the binary*: this script runs `kaappi explain --all --json` and renders
the resulting entries as Markdown. Run it against a freshly built kaappi and
commit the output into the kaappi.github.io repo (see docs/dev/explain.md).

    zig build                                    # build zig-out/bin/kaappi
    python3 tools/gen_diagnostics_reference.py   # -> stdout
    python3 tools/gen_diagnostics_reference.py \\
        --kaappi zig-out/bin/kaappi \\
        -o ../kaappi.github.io/docs/guide/diagnostics.md

Codes are grouped by pipeline stage, in registry order.
"""

import argparse
import json
import subprocess
import sys

# Human headings for each stage label emitted by `kaappi explain --json`.
STAGE_HEADINGS = {
    "read": "Read / lexical (`KP1xxx`)",
    "compile": "Expand / compile (`KP2xxx`)",
    "runtime": "Runtime (`KP3xxx`)",
    "static-analysis": "Static analysis (`KP4xxx`)",
    "internal": "Internal / resource (`KP9xxx`)",
}
STAGE_ORDER = ["read", "compile", "runtime", "static-analysis", "internal"]

PREAMBLE = """\
# Diagnostic reference

Every diagnostic Kaappi prints carries a stable `KP` code. This page documents
every registered code: what it means, a minimal example that triggers it, and
how to fix it. The same content is available offline from the binary itself with
[`kaappi explain <code>`](../guide/debugging.md) (e.g. `kaappi explain KP3001`).

!!! note "Generated page"

    This page is generated from the compiler's diagnostic registry by
    `tools/gen_diagnostics_reference.py` in the core repo. Do not edit it by
    hand — regenerate it after a release instead.
"""


def fetch_entries(kaappi: str) -> list[dict]:
    proc = subprocess.run(
        [kaappi, "explain", "--all", "--json"],
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        sys.exit(f"error: `{kaappi} explain --all --json` failed:\n{proc.stderr}")
    return json.loads(proc.stdout)


def render(entries: list[dict]) -> str:
    by_stage: dict[str, list[dict]] = {}
    for e in entries:
        by_stage.setdefault(e["stage"], []).append(e)

    out: list[str] = [PREAMBLE]
    # Known stages first in taxonomy order, then any unrecognised stage so a
    # future range can never be silently dropped from the page.
    stages = [s for s in STAGE_ORDER if s in by_stage]
    stages += [s for s in by_stage if s not in STAGE_ORDER]

    for stage in stages:
        out.append(f"\n## {STAGE_HEADINGS.get(stage, stage)}\n")
        for e in by_stage[stage]:
            out.append(f"### `{e['code']}` — {e['name']}\n")
            out.append(f"_{e['message']}_\n")
            out.append(e["explanation"] + "\n")
            out.append("**Example**\n")
            out.append("```scheme\n" + e["example"] + "\n```\n")
    return "\n".join(out)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--kaappi", default="zig-out/bin/kaappi",
                    help="path to the kaappi binary (default: zig-out/bin/kaappi)")
    ap.add_argument("-o", "--output", help="write to this file instead of stdout")
    args = ap.parse_args()

    page = render(fetch_entries(args.kaappi))
    if args.output:
        with open(args.output, "w") as f:
            f.write(page)
        print(f"wrote {args.output}", file=sys.stderr)
    else:
        sys.stdout.write(page)


if __name__ == "__main__":
    main()
