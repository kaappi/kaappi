#!/usr/bin/env python3
"""Fuzz `kaappi fmt` against the repo's own Scheme corpus.

`fmt` guards every write with a real-reader `equal?` round-trip, so it can
never change a program. Two things that guard structurally cannot see are what
this fuzzer looks for:

  * **Comments.** The reader discards them, so a comment that moves, is
    duplicated, or is dropped passes the round-trip unnoticed.
  * **Idempotence.** `fmt(fmt(x)) == fmt(x)` is a separate property; a
    formatter can be `equal?`-preserving and still oscillate between layouts.

It is **not** part of `run-all.sh` — a useful run takes minutes, well past that
suite's 60 s per-file budget. The cases it has already found are pinned as fast
regression tests in `tests/scheme/fmt/fmt-adversarial.sh`; run this when
changing `src/fmt.zig` or `src/fmt_print.zig`, or to look for new ones.

    tools/fmt_fuzz.py byte  30000        # random byte mutation
    tools/fmt_fuzz.py ws     4000        # whitespace-run resizing
    tools/fmt_fuzz.py cmt    6000        # comment / blank-line insertion
    tools/fmt_fuzz.py blank                # exhaustive comment x blank grid
    tools/fmt_fuzz.py all                  # a moderate run of each

Modes
  byte   Flip, delete, insert, replace, duplicate and truncate bytes. Most
         mutants are unreadable — that is expected. The interesting outcomes
         are a crash, a hang, non-idempotence, or `fmt` disagreeing with the
         real reader about whether the file is even readable.
  ws     Resize runs of spaces and tabs outside strings and comments, never
         adding or removing a newline. `docs/dev/fmt.md`: "Layout depends only
         on the program's content and its comments, **not** on the input's own
         line breaks". Oracle: `fmt(mutant)` byte-identical to `fmt(original)`.
  cmt    Insert `;`, `#| |#`, `#;` comments and blank lines at token
         boundaries. Oracle: idempotence, every comment marker surviving in
         order, and `fmt`'s own guard. `--glue` additionally inserts them with
         no separating space, which reproduces kaappi#2143 in bulk.
  blank  Not random: every (comment position x blank position) pair over a
         grid of head forms. This is what mapped kaappi#2142's 58 shapes.

Buckets, and what each means

  clean          fmt accepted it and every oracle held
  rejected       fmt refused, and so does the real reader — expected
  crash          fmt died on a signal or printed a panic        -> BUG
  hang           fmt did not finish inside the timeout          -> BUG
  nonidem        the second pass differs from the first         -> BUG
  comment_lost   a comment marker vanished or moved             -> BUG
  ws_drift       whitespace changed the layout                  -> BUG
  reader_split   fmt reported a syntax error the reader does not -> BUG
  guard_trip     fmt's round-trip guard refused a file the reader reads
                 fine — fmt's output would have been a different program

Nothing is ever written over a corpus file: every mutant goes to `fmt` on
stdin, and the copies kept for the reader cross-check live in a `mktemp` dir
that is removed on exit.
"""

import argparse
import os
import random
import re
import shutil
import subprocess
import sys
import tempfile
from concurrent.futures import ProcessPoolExecutor

TIMEOUT = 30
MAX_CORPUS_BYTES = 20000

KAAPPI = os.environ.get("KAAPPI", "zig-out/bin/kaappi")
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Worker processes are spawned (not forked) on macOS and Windows, so the
# scratch directory has to travel in the environment rather than in a global.
SCRATCH_VAR = "KAAPPI_FMT_FUZZ_SCRATCH"


def scratch():
    return os.environ[SCRATCH_VAR]

BUG_BUCKETS = ("crash", "hang", "nonidem", "comment_lost", "ws_drift",
               "reader_split", "guard_trip")

MUTATION_BYTES = bytes(b"()[]{}'`,@#|;\"\\ \n\r\t.0123456789abcdefxu8=e"
                       b"\x00\x7f\xff\xc3\xa9")


def run_fmt(data):
    p = subprocess.run([KAAPPI, "fmt"], input=data, capture_output=True,
                       timeout=TIMEOUT)
    return p.returncode, p.stdout, p.stderr


def reader_accepts(data, tag):
    """Does the real reader read this? `kaappi ast` reads and prints datums and
    executes nothing, so it answers exactly that question."""
    path = os.path.join(scratch(), "probe%s.scm" % tag)
    with open(path, "wb") as f:
        f.write(data)
    try:
        p = subprocess.run([KAAPPI, "ast", path], capture_output=True,
                           timeout=TIMEOUT)
    except subprocess.TimeoutExpired:
        return False
    return p.returncode == 0


def crashed(rc, err):
    return rc < 0 or rc >= 128 or b"panic" in err or b"error at address" in err


def corpus():
    out = subprocess.run(["git", "ls-files", "*.scm", "*.sld"], cwd=REPO,
                         capture_output=True, check=True).stdout.decode().split()
    files = []
    for rel in out:
        try:
            data = open(os.path.join(REPO, rel), "rb").read()
        except OSError:
            continue
        if 0 < len(data) <= MAX_CORPUS_BYTES:
            files.append((rel, data))
    return files


# ── where it is legal to insert ─────────────────────────────────────────────

def safe_points(src):
    """Byte offsets outside strings, |symbols|, character literals and
    comments, at a whitespace or paren byte — where inserting whitespace or a
    comment cannot land inside a lexeme."""
    pts = []
    i, n = 0, len(src)
    while i < n:
        c = src[i:i + 1]
        if c in (b'"', b"|"):
            close, i = c, i + 1
            while i < n:
                if src[i:i + 1] == b"\\":
                    i += 2
                    continue
                i += 1
                if src[i - 1:i] == close:
                    break
            continue
        if c == b";":
            while i < n and src[i:i + 1] != b"\n":
                i += 1
            continue
        if src[i:i + 2] == b"#|":
            depth, i = 1, i + 2
            while i + 1 < n and depth:
                if src[i:i + 2] == b"#|":
                    depth, i = depth + 1, i + 2
                elif src[i:i + 2] == b"|#":
                    depth, i = depth - 1, i + 2
                else:
                    i += 1
            continue
        if src[i:i + 2] == b"#\\":
            i += 3
            while i < n and src[i:i + 1].isalnum():
                i += 1
            continue
        if src[i:i + 2] == b'#"':
            i += 2
            while i < n and src[i:i + 1] != b'"':
                i += 1
            i += 1
            continue
        if c in (b" ", b"\t", b"\n", b"(", b")"):
            pts.append(i)
        i += 1
    return pts


# ── mode: byte ──────────────────────────────────────────────────────────────

def mutate_bytes(rng, src):
    b = bytearray(src)
    for _ in range(rng.randint(1, 6)):
        if not b:
            break
        op, i = rng.randrange(7), rng.randrange(len(b))
        if op == 0:
            b[i] ^= 1 << rng.randrange(8)
        elif op == 1:
            del b[i]
        elif op == 2:
            b.insert(i, rng.choice(MUTATION_BYTES))
        elif op == 3:
            b[i] = rng.choice(MUTATION_BYTES)
        elif op == 4:
            b[i:i] = b[i:min(len(b), i + rng.randint(1, 64))]
        elif op == 5:
            del b[i:min(len(b), i + rng.randint(1, 64))]
        else:
            del b[i:]
    return bytes(b)


def job_byte(args):
    idx, seed, rel, src = args
    rng = random.Random((seed << 20) ^ idx)
    mut = mutate_bytes(rng, src)
    return check_mutant(idx, rel, mut, want_markers=False)


# ── mode: ws ────────────────────────────────────────────────────────────────

WS_RUN = re.compile(rb"[ \t]+")


def mutate_ws(rng, src):
    ok = set(safe_points(src))
    out, i, n, changed = bytearray(), 0, len(src), 0
    while i < n:
        m = WS_RUN.match(src, i)
        if m and i in ok and rng.random() < 0.4:
            out += bytes(rng.choice(b" \t") for _ in range(rng.randint(1, 6)))
            changed, i = changed + 1, m.end()
            continue
        out += src[i:i + 1]
        i += 1
    return bytes(out), changed


def job_ws(args):
    idx, seed, rel, src = args
    rng = random.Random((seed << 20) ^ idx)
    try:
        rc0, base, _ = run_fmt(src)
    except subprocess.TimeoutExpired:
        return ("hang", rel, b"formatting the original", b"")
    if rc0 != 0:
        return ("skipped", rel, b"", b"")
    mut, changed = mutate_ws(rng, base)
    if changed == 0:
        return ("skipped", rel, b"", b"")
    try:
        rc, out, err = run_fmt(mut)
    except subprocess.TimeoutExpired:
        return ("hang", rel, b"", b"")
    if crashed(rc, err):
        return ("crash", rel, err[:400], b"")
    if rc != 0:
        return ("rejected", rel, err[:200], b"")
    if out != base:
        return ("ws_drift", rel, base[:300], out[:300])
    return ("clean", rel, b"", b"")


# ── mode: cmt ───────────────────────────────────────────────────────────────

INSERTS = [b" ; C%d\n", b" #| C%d |#", b" #|\nC%d\n|#", b" #;C%d ",
           b"\n; C%d\n", b"\n\n; C%d\n", b"\n\n", b"  ", b"\n"]

# Same comments with the leading space removed, so they glue to the preceding
# identifier. Off by default (`--glue`): every one of them lands in a bug
# bucket for kaappi#2143, which would drown out anything new.
GLUED = [b"#| C%d |#", b"#;C%d ", b"; C%d\n"]

GLUE_VAR = "KAAPPI_FMT_FUZZ_GLUE"


def mutate_cmt(rng, src, base_id):
    pts = safe_points(src)
    if not pts:
        return src, 0
    table = INSERTS + (GLUED if os.environ.get(GLUE_VAR) else [])
    picks = sorted(rng.sample(pts, min(rng.randint(1, 5), len(pts))), reverse=True)
    out, n = bytearray(src), 0
    for p in picks:
        tmpl = rng.choice(table)
        n += 1
        out[p:p] = tmpl % (base_id + n) if b"%d" in tmpl else tmpl
    return bytes(out), n


def job_cmt(args):
    idx, seed, rel, src = args
    rng = random.Random((seed << 20) ^ idx)
    mut, n = mutate_cmt(rng, src, idx * 100)
    if n == 0:
        return ("skipped", rel, b"", b"")
    return check_mutant(idx, rel, mut, want_markers=True)


# ── shared verdict ──────────────────────────────────────────────────────────

def markers(b):
    return re.findall(rb"\bC\d+\b", b)


def check_mutant(idx, rel, mut, want_markers):
    try:
        rc, out, err = run_fmt(mut)
    except subprocess.TimeoutExpired:
        return ("hang", rel, b"", b"")
    if crashed(rc, err):
        return ("crash", rel, err[:400], b"")
    if rc != 0:
        if not reader_accepts(mut, str(idx % 64)):
            return ("rejected", rel, err[:200], b"")
        keep(rel, idx, mut)
        if b"internal error" in err:
            return ("guard_trip", rel, err[:200], b"")
        return ("reader_split", rel, err[:200], b"")
    try:
        rc2, out2, err2 = run_fmt(out)
    except subprocess.TimeoutExpired:
        return ("hang", rel, b"second pass", b"")
    if crashed(rc2, err2):
        return ("crash", rel, b"second pass: " + err2[:400], b"")
    if rc2 != 0 or out2 != out:
        keep(rel, idx, mut)
        return ("nonidem", rel, out[:400], out2[:400])
    if want_markers and markers(mut) != markers(out):
        keep(rel, idx, mut)
        return ("comment_lost", rel, b" ".join(markers(mut))[:200],
                b" ".join(markers(out))[:200])
    return ("clean", rel, b"", b"")


def keep(rel, idx, mut):
    """Save a mutant worth reducing by hand."""
    name = "%s_%d.scm" % (os.path.basename(rel), idx)
    with open(os.path.join(scratch(), "found", name), "wb") as f:
        f.write(mut)


# ── mode: blank ─────────────────────────────────────────────────────────────

BLANK_HEADS = ["f", "cond", "and", "define", "lambda", "let", "let*", "letrec",
               "when", "unless", "begin", "case", "do", "guard", "syntax-rules",
               "case-lambda", "receive", "define-values", "define-record-type",
               "parameterize"]


def blank_grid():
    """Every (comment position, blank position) pair over a grid of head forms.
    Not random: this is a complete enumeration of one small shape."""
    for head in BLANK_HEADS:
        for nargs in (2, 3, 4):
            items = [head] + ["a", "b", "c", "d"][:nargs]
            for ci in range(1, len(items) + 1):
                toks = items[:ci] + ["#|c|#"] + items[ci:]
                for bi in range(1, len(toks)):
                    parts = [toks[0]]
                    for i, t in enumerate(toks[1:], 1):
                        parts.append(("\n\n  " if i == bi else " ") + t)
                    yield head, "(" + "".join(parts) + ")\n"


def job_blank(args):
    idx, seed, head, src = args
    return check_mutant(idx, head, src.encode(), want_markers=False)


# ── driver ──────────────────────────────────────────────────────────────────

MODES = {"byte": job_byte, "ws": job_ws, "cmt": job_cmt, "blank": job_blank}


def run_mode(mode, n, seed, workers):
    if mode == "blank":
        jobs = [(i, seed, head, src) for i, (head, src) in enumerate(blank_grid())]
    else:
        rng = random.Random(seed)
        files = corpus()
        if not files:
            sys.exit("no corpus files found under %s" % REPO)
        jobs = [(i, seed, *rng.choice(files)) for i in range(n)]

    buckets, found = {}, []
    with ProcessPoolExecutor(max_workers=workers) as ex:
        for kind, rel, a, b in ex.map(MODES[mode], jobs, chunksize=8):
            buckets[kind] = buckets.get(kind, 0) + 1
            if kind in BUG_BUCKETS:
                found.append((kind, rel, a, b))

    print("\n=== %s: %d inputs, seed %d ===" % (mode, len(jobs), seed))
    for k in sorted(buckets):
        mark = "  <-- BUG" if k in BUG_BUCKETS else ""
        print("  %-13s %6d%s" % (k, buckets[k], mark))
    if found:
        print("  kept for reduction: %s/found/" % scratch())
    for kind, rel, a, b in found[:20]:
        print("  %-13s %s\n      %r\n      %r" % (kind, rel, a[:200], b[:200]))
    return len(found)


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("mode", choices=list(MODES) + ["all"])
    ap.add_argument("n", nargs="?", type=int, default=2000,
                    help="mutants to generate (ignored by 'blank')")
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--jobs", type=int, default=os.cpu_count() or 4)
    ap.add_argument("--keep", action="store_true",
                    help="do not delete the scratch dir on exit")
    ap.add_argument("--glue", action="store_true",
                    help="cmt mode: also insert comments with no separating "
                         "space, which reproduces kaappi#2143 and swamps "
                         "everything else")
    args = ap.parse_args()

    if not os.access(KAAPPI, os.X_OK):
        sys.exit("no kaappi binary at %s (set $KAAPPI or run zig build)" % KAAPPI)

    if args.glue:
        os.environ[GLUE_VAR] = "1"
    os.environ[SCRATCH_VAR] = tempfile.mkdtemp(prefix="kaappi-fmt-fuzz-")
    os.makedirs(os.path.join(scratch(), "found"), exist_ok=True)
    try:
        modes = list(MODES) if args.mode == "all" else [args.mode]
        bugs = 0
        for m in modes:
            bugs += run_mode(m, args.n, args.seed, args.jobs)
        print("\n%d input(s) in a bug bucket" % bugs)
        return 1 if bugs else 0
    finally:
        if args.keep:
            print("scratch kept: %s" % scratch())
        else:
            shutil.rmtree(scratch(), ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
