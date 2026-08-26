#!/bin/bash
# Regression test for #1888: the bytecode cache engages for libraries and for
# programs that import.
#
# Before #1888, .sld files were never cached in either direction and any main
# file containing one of the eight top-level declaration heads was refused
# outright — so 92% of the .scm corpus recompiled everything it touched on
# every run. #1888 splits a library load into "structure from source, code
# from cache": the warm load re-parses the .sld and re-processes its
# declarations, but replays compiled body functions and deserialized macro
# transformers instead of compiling; main files replay positional slots
# (compiled function or declaration source span) in top-level order.
#
# The contract under test, per the issue's verification checklist:
#   A. a program that imports reports cache HIT on the second run, and stays
#      MISS after editing the program, any library in its import closure, or
#      an include file a library uses;
#   B. a --lib-path change that re-resolves a dependency is a miss;
#   C. a library whose exports come from include-library-declarations and
#      cond-expand exports exactly the same set warm as cold — the specific
#      regression the old (pre-#1888) cache-read path had, because it
#      re-derived the export table by re-parsing the .sld top level;
#   D. cold and warm runs agree, exit codes included.
#
# Hermetic: KAAPPI_HOME points at a throwaway dir; the fixture libraries live
# in a throwaway --lib-path.
#
# Usage: bash tests/scheme/cache/library-cache-1888.sh [path-to-kaappi]

set -euo pipefail

. "$(dirname "$0")/../shell-common.sh"
skip_on_windows "asserts on POSIX path spellings in --timings output"

KAAPPI="${1:-zig-out/bin/kaappi}"
# Absolute: the runs below point at programs in temp dirs.
case "$KAAPPI" in
    /*) ;;
    *) KAAPPI="$PWD/$KAAPPI" ;;
esac
PASS=0
FAIL=0

HOMEDIR="$(mktemp -d)"
LIBDIR="$(mktemp -d)"
PROGDIR="$(mktemp -d)"
trap 'rm -rf "$HOMEDIR" "$LIBDIR" "$PROGDIR"' EXIT
export KAAPPI_HOME="$HOMEDIR"

check() {
    local label="$1" expected="$2" actual="$3"
    if [[ "$actual" == *"$expected"* ]]; then
        echo "PASS: $label"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $label"
        echo "  expected to contain: $expected"
        echo "  actual: $actual"
        FAIL=$((FAIL + 1))
    fi
}

# --- Fixtures ---------------------------------------------------------------
# dep1888 exports a value and a procedure; user1888 depends on it, includes a
# body file, and adds exports through include-library-declarations and a
# platform-only cond-expand (availability-dependent requirements keep a
# library uncached by design, so the fixture must not use any).

mkdir -p "$LIBDIR/dep1888" "$LIBDIR/user1888"
cat > "$LIBDIR/dep1888/base.sld" <<'SLD'
(define-library (dep1888 base)
  (import (scheme base))
  (export base-val bump)
  (begin
    (define base-val 10)
    (define (bump x) (+ x base-val))))
SLD

cat > "$LIBDIR/user1888/body.scm" <<'SCM'
(define included-val 7)
SCM

cat > "$LIBDIR/user1888/extra-decls.sld" <<'SLD'
(export from-include)
SLD

cat > "$LIBDIR/user1888/u.sld" <<'SLD'
(define-library (user1888 u)
  (import (scheme base) (dep1888 base))
  (export total from-include from-cond-expand twicer)
  (include "body.scm")
  (include-library-declarations "extra-decls.sld")
  (begin
    (define (total x) (bump (+ x included-val)))
    (define (from-include) included-val)
    (define-syntax twicer
      (syntax-rules ()
        ((twicer e) (let ((v e)) (list v v))))))
  (cond-expand
    (r7rs (begin (define (from-cond-expand) 'r7rs-branch)))
    (else (begin (define (from-cond-expand) 'other-branch)))))
SLD

PROG="$PROGDIR/prog.scm"
cat > "$PROG" <<'SCM'
(import (scheme base) (user1888 u))
(display (total 5))
(newline)
(display (twicer (from-include)))
(newline)
(display (from-cond-expand))
(newline)
(display (from-include))
(newline)
SCM

run_timed() { "$KAAPPI" --lib-path "$LIBDIR" --timings=text "$@" 2>&1; }
run_plain() { "$KAAPPI" --lib-path "$LIBDIR" "$@" 2>&1; }

# --- A: cold, then warm -----------------------------------------------------
out1="$(run_timed "$PROG")"
check "cold run output" "22
(7 7)
r7rs-branch
7" "$out1"
check "cold run: main file miss with a write" "cache: MISS (wrote" "$out1"
check "cold run: library misses with writes" "libcache: 0 hits, 2 misses, 2 written" "$out1"

out2="$(run_timed "$PROG")"
check "warm run output identical" "22
(7 7)
r7rs-branch
7" "$out2"
check "warm run: main file HIT" "cache: HIT" "$out2"
check "warm run: library HITs" "libcache: 2 hits, 0 misses" "$out2"

# --- A: editing the program is a miss --------------------------------------
echo ";; touch" >> "$PROG"
out3="$(run_timed "$PROG")"
check "edited program: main MISS" "cache: MISS (wrote" "$out3"
check "edited program: libraries still HIT" "libcache: 2 hits, 0 misses" "$out3"
check "edited program: same output" "22
(7 7)
r7rs-branch
7" "$out3"

# --- A: editing the imported library invalidates its dependents ------------
# user1888's compiled body embeds dep1888's exports transitively, so editing
# dep1888 must stale user1888's entry too (the dependency records).
cat > "$LIBDIR/dep1888/base.sld" <<'SLD'
(define-library (dep1888 base)
  (import (scheme base))
  (export base-val bump)
  (begin
    (define base-val 100)
    (define (bump x) (+ x base-val))))
SLD
out4="$(run_timed "$PROG")"
check "edited dependency: dependents go stale and recompile" "libcache: 0 hits, 1 miss, 2 written, 1 stale" "$out4"
check "edited dependency: new value propagates" "112
(7 7)
r7rs-branch
7" "$out4"

# Warm again: both hit, with the new value.
out5="$(run_timed "$PROG")"
check "after dep rewrite, warm hits again" "libcache: 2 hits, 0 misses" "$out5"
check "after dep rewrite, output stable" "112
(7 7)
r7rs-branch
7" "$out5"

# --- A: editing an include file is a miss ----------------------------------
echo "(define included-val 70)" > "$LIBDIR/user1888/body.scm"
out6="$(run_timed "$PROG")"
check "edited include: library goes stale" "1 stale" "$out6"
check "edited include: new value visible" "175
(70 70)
r7rs-branch
70" "$out6"

# --- B: a --lib-path change that re-resolves a dependency is a miss ---------
OTHER="$(mktemp -d)"
mkdir -p "$OTHER/dep1888"
cat > "$OTHER/dep1888/base.sld" <<'SLD'
(define-library (dep1888 base)
  (import (scheme base))
  (export base-val bump)
  (begin
    (define base-val 100)
    (define (bump x) (+ x base-val))))
SLD
out7="$(KAAPPI_HOME="$HOMEDIR" "$KAAPPI" --lib-path "$OTHER" --lib-path "$LIBDIR" --timings=text "$PROG" 2>&1)"
check "lib-path shadowing the dependency: stale, not a silent wrong hit" "1 stale" "$out7"
check "lib-path shadowing: output unchanged (same source content)" "175
(70 70)
r7rs-branch
70" "$out7"
rm -rf "$OTHER"

# --- C: export-set completeness, warm vs cold --------------------------------
# from-include (via include-library-declarations), from-cond-expand (via
# cond-expand), and the exported macro must all resolve on a WARM run exactly
# as on the cold runs above.
out8="$(run_plain "$PROG")"
check "warm export set complete (include + cond-expand + macro)" "175
(70 70)
r7rs-branch
70" "$out8"

# A define-library at top level of a main file, cold vs warm — guards the
# declaration-slot replay of define-library itself.
INLINE="$PROGDIR/inline-lib.scm"
cat > "$INLINE" <<'SCM'
(define-library (inline1888 l)
  (import (scheme base))
  (export f)
  (begin (define (f x) (* x 3))))
(import (inline1888 l) (scheme base))
(display (f 14))
(newline)
SCM
inl1="$(run_plain "$INLINE")"
inl2="$(run_plain "$INLINE")"
check "inline define-library: cold output" "42" "$inl1"
check "inline define-library: warm output" "42" "$inl2"
tim="$(run_timed "$INLINE")"
check "inline define-library: warm main HIT" "cache: HIT" "$tim"

# --- D: exit-code parity -----------------------------------------------------
ERRP="$PROGDIR/err.scm"
cat > "$ERRP" <<'SCM'
(import (scheme base) (user1888 u))
(display (total 'not-a-number))
(newline)
SCM
if run_plain "$ERRP" > /dev/null 2>&1; then rc1=0; else rc1=$?; fi
if run_plain "$ERRP" > /dev/null 2>&1; then rc2=0; else rc2=$?; fi
if [[ "$rc1" -eq "$rc2" && "$rc1" -ne 0 ]]; then
    echo "PASS: error exit code cold == warm == $rc1"
    PASS=$((PASS + 1))
else
    echo "FAIL: error exit codes differ or are zero (cold=$rc1 warm=$rc2)"
    FAIL=$((FAIL + 1))
fi

# --- E: program-entry staleness (#1888 review) -------------------------------
# A program's compiled slots embed imported-macro expansions: editing the
# library must stale the PROGRAM entry too, not only the library's own.
P2="$PROGDIR/p2.scm"
cat > "$P2" <<'SCM'
(import (user1888 u) (scheme base))
(display (twicer (total 1)))
(newline)
SCM
o1="$(run_timed "$P2")"
check "program over libraries: cold output" "(171 171)" "$o1"
o2="$(run_timed "$P2")"
check "program over libraries: warm HIT" "cache: HIT" "$o2"
python3 - "$LIBDIR/user1888/u.sld" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
open(p, 'w').write(s.replace("(list v v)", "(list v v v)"))
PY
o3="$(run_timed "$P2")"
check "library macro edit stales the program entry" "cache: MISS (wrote" "$o3"
check "library macro edit: new expansion runs" "(171 171 171)" "$o3"
python3 - "$LIBDIR/user1888/u.sld" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
open(p, 'w').write(s.replace("(list v v v)", "(list v v)"))
PY

# --- F: registry-order dependency recording (#1888 review) -------------------
# The main file imports (dep1888 base) FIRST, so user1888's own load finds it
# in the registry and never calls tryLoadLibraryFromFile — its entry must still
# record the dependency (Library.source_path provenance).
P3="$PROGDIR/p3.scm"
cat > "$P3" <<'SCM'
(import (dep1888 base) (user1888 u) (scheme base))
(display (twicer (total 1)))
(newline)
SCM
o1="$(run_timed "$P3")"
check "registry-order program: cold output" "(171 171)" "$o1"
o2="$(run_timed "$P3")"
check "registry-order program: warm HIT" "cache: HIT" "$o2"
cat > "$LIBDIR/dep1888/base.sld" <<'SLD'
(define-library (dep1888 base)
  (import (scheme base))
  (export base-val bump)
  (begin
    (define base-val 1000)
    (define (bump x) (+ x base-val))))
SLD
o3="$(run_timed "$P3")"
check "dep edit stales registry-order dependents" "cache: MISS (wrote" "$o3"
check "dep edit: new value everywhere" "(1071 1071)" "$o3"

# --- G: running a .sld directly must not replay its library entry ------------
# The library entry shares the cache key with `kaappi u.sld`; the direct run
# must interpret the define-library cleanly (cold behavior), not execute the
# body thunks as a program.
d1="$("$KAAPPI" --lib-path "$LIBDIR" "$LIBDIR/user1888/u.sld" 2>&1; echo "rc=$?")"
check "running the .sld directly stays clean" "rc=0" "$d1"

# --- H: fold-case declarations replay (#1888 review) -------------------------
# A #!fold-case directive falls inside an earlier form's span; the declaration
# slot must carry the reader state so a folded (IMPORT ...) is still claimed
# as a declaration on the warm run.
FC="$PROGDIR/fc.scm"
printf '#!fold-case\n(define x 5)\n(IMPORT (SCHEME BASE))\n(display (EXPT x 3))\n(newline)\n' > "$FC"
f1="$(run_plain "$FC")"
check "fold-case program: cold output" "125" "$f1"
f2="$(run_timed "$FC")"
check "fold-case program: warm output" "125" "$f2"
check "fold-case program: warm HIT" "cache: HIT" "$f2"

echo ""
echo "passed: $PASS  failed: $FAIL"
[[ "$FAIL" -eq 0 ]]
