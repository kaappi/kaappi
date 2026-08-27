#!/bin/bash
# Audit-campaign v2 Phase 6E: `thottam` install/list/verify/remove/update
# end to end, with **no network**.
#
# The whole fixture is a directory of local bare git repositories pointed at
# by KAAPPI_ORG, which thottam joins as "<org>/<pkg>.git" — git clones a
# plain path as happily as a URL, so every code path that a real install
# takes (clone, `ls-remote --tags` constraint resolution, checkout, lib
# copy, lockfile write) runs unchanged against on-disk repos.
#
# Hermetic: KAAPPI_HOME and KAAPPI_ORG both point at throwaway directories,
# so the real ~/.kaappi is never read, written, or removed. `thottam remove`
# deletes trees, so this isolation is load-bearing, not tidiness.
#
# Usage: bash tests/scheme/thottam/thottam-lifecycle.sh [path-to-kaappi]
#
# run-all.sh passes the *kaappi* binary to every shell suite; thottam is
# built into the same directory, so it is derived from that rather than
# taking a second argument nothing would pass.

set -euo pipefail

. "$(dirname "$0")/../shell-common.sh"

# The fixture builds git repositories at POSIX paths and hands them to
# thottam, which on Windows resolves "git" through PATH while this script
# would be handing it MSYS spellings. The Zig unit suite
# (src/tests_thottam.zig) covers the pure parsing surface on every leg.
skip_on_windows "thottam lifecycle fixture builds local git repos at POSIX paths"

KAAPPI="${1:-zig-out/bin/kaappi}"
THOTTAM="$(dirname "$KAAPPI")/thottam"
if [[ ! -x "$THOTTAM" ]]; then
    echo "SKIP: no thottam binary at $THOTTAM"
    exit 77
fi
if ! command -v git > /dev/null 2>&1; then
    echo "SKIP: git is not on PATH"
    exit 77
fi

# thottam used to invoke git as the absolute path /usr/bin/git
# (thottam_proc.zig:148), not through PATH. That path exists on macOS and on
# CI's Linux images, and on none of the three BSDs -- FreeBSD and OpenBSD put
# git in /usr/local/bin, NetBSD in /usr/pkg/bin -- so every git-backed thottam
# operation failed there (kaappi#2152). Fixed by resolving git through PATH,
# so the only precondition left is the `command -v git` probe above. This
# suite is itself the regression test: on a box without /usr/bin/git it used
# to skip (or fail on the BSD legs), and now it runs.
#
# The original probe created a bare repo and cloned it, on the hypothesis that
# local-bare-clone was unsupported on the BSDs. It PASSED on OpenBSD while the
# suite still failed, because the probe used PATH and thottam did not. That
# falsified hypothesis is what located #2152.

PASS=0
FAIL=0

ORG="$(mktemp -d)"
WORK="$(mktemp -d)"
HOMEROOT="$(mktemp -d)"
trap 'rm -rf "$ORG" "$WORK" "$HOMEROOT"' EXIT
export KAAPPI_ORG="$ORG"

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

check_not() {
    local label="$1" unexpected="$2" actual="$3"
    if [[ "$actual" != *"$unexpected"* ]]; then
        echo "PASS: $label"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $label"
        echo "  expected NOT to contain: $unexpected"
        echo "  actual: $actual"
        FAIL=$((FAIL + 1))
    fi
}

check_exit() {
    local label="$1" expected="$2" actual="$3"
    if [[ "$actual" -eq "$expected" ]]; then
        echo "PASS: $label"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $label — expected exit $expected, got $actual"
        FAIL=$((FAIL + 1))
    fi
}

check_file() {
    local label="$1" path="$2"
    if [[ -f "$path" ]]; then
        echo "PASS: $label"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $label — no such file: $path"
        FAIL=$((FAIL + 1))
    fi
}

check_files_eq() {
    local label="$1" expected="$2" actual="$3"
    if cmp -s "$expected" "$actual"; then
        echo "PASS: $label"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $label"
        echo "  files differ: $expected vs $actual"
        FAIL=$((FAIL + 1))
    fi
}

git_q() { git -c user.email=t@example.com -c user.name=Test -c commit.gpgsign=false "$@"; }

# mkpkg <name> <extra-sld-basename-or-empty> <tag>...
# One commit per tag so every tag names a distinct SHA.
mkpkg() {
    local name="$1" extra="$2"
    shift 2
    local d="$WORK/$name"
    mkdir -p "$d/lib/kaappi"
    (
        cd "$d"
        git init -q .
        printf 'name: %s\n' "$name" > kaappi.pkg
        printf '(define-library (kaappi %s) (export tag) (import (scheme base)) (begin (define tag "base")))\n' \
            "${name#kaappi-}" > "lib/kaappi/${name#kaappi-}.sld"
        if [[ -n "$extra" ]]; then
            printf '(define-library (kaappi %s) (export owner) (import (scheme base)) (begin (define owner "%s")))\n' \
                "$extra" "$name" > "lib/kaappi/$extra.sld"
        fi
        git add -A
        git_q commit -q -m base
        local t
        for t in "$@"; do
            printf '(define-library (kaappi %s) (export tag) (import (scheme base)) (begin (define tag "%s")))\n' \
                "${name#kaappi-}" "$t" > "lib/kaappi/${name#kaappi-}.sld"
            git add -A
            git_q commit -q -m "$t"
            git tag "$t"
        done
    )
    git clone -q --bare "$d" "$ORG/$name.git"
}

# fresh_home: a brand-new KAAPPI_HOME for the next scenario.
fresh_home() {
    KAAPPI_HOME="$(mktemp -d "$HOMEROOT/home-XXXXXX")"
    export KAAPPI_HOME
}

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

mkpkg kaappi-alpha "" v0.1.0 v0.2.0 v0.2.5 v1.0.0 v1.2.3 v1.9.0 v2.0.0
mkpkg kaappi-one shared
mkpkg kaappi-two shared
# Two single-variable fixtures, so the pre-release case and the
# four-component case cannot mask one another: each carries exactly one
# release tag (v1.0.0) plus one odd tag on a later commit.
mkpkg kaappi-odd "" v1.0.0
(
    cd "$WORK/kaappi-odd"
    printf 'rc\n' > rc.txt
    git add -A
    git_q commit -q -m rc
    git tag 'v2.0.0-rc1'
)
rm -rf "$ORG/kaappi-odd.git"
git clone -q --bare "$WORK/kaappi-odd" "$ORG/kaappi-odd.git"

mkpkg kaappi-nightly "" v1.0.0
(
    cd "$WORK/kaappi-nightly"
    printf 'nightly\n' > nightly.txt
    git add -A
    git_q commit -q -m nightly
    git tag 'v2.0.0.nightly-UNRELEASED'
)
rm -rf "$ORG/kaappi-nightly.git"
git clone -q --bare "$WORK/kaappi-nightly" "$ORG/kaappi-nightly.git"

# ---------------------------------------------------------------------------
# 1. A plain install, and what it records
# ---------------------------------------------------------------------------

fresh_home
out="$("$THOTTAM" install kaappi-alpha 2>&1)" && ec=0 || ec=$?
check_exit "plain install succeeds" 0 "$ec"
check "install reports the resolved SHA" "installed (locked at" "$out"
check_file "the package's .sld lands in KAAPPI_HOME/lib" "$KAAPPI_HOME/lib/kaappi/alpha.sld"
check "installed.txt lists the package" "kaappi-alpha" "$(cat "$KAAPPI_HOME/installed.txt")"
check "lockfile records the package and a SHA" "kaappi-alpha " "$(cat "$KAAPPI_HOME/thottam.lock")"
check "list shows the package" "kaappi-alpha" "$("$THOTTAM" list)"
out="$("$THOTTAM" verify 2>&1)" && ec=0 || ec=$?
check_exit "verify passes on a clean install" 0 "$ec"
check "verify reports OK for the package" "OK: kaappi-alpha" "$out"

# ---------------------------------------------------------------------------
# 2. Provenance: an explicit ::url is recorded and shown
# ---------------------------------------------------------------------------

fresh_home
"$THOTTAM" install "kaappi-alpha::$ORG/kaappi-alpha.git" > /dev/null 2>&1
check "lockfile records the source URL it cloned from" \
    "$ORG/kaappi-alpha.git" "$(cat "$KAAPPI_HOME/thottam.lock")"
check "list shows the recorded provenance" \
    "(from: $ORG/kaappi-alpha.git)" "$("$THOTTAM" list)"

# ---------------------------------------------------------------------------
# 3. Constraint resolution against real tags
#    Oracle: node-semver's range grammar (github.com/npm/node-semver).
#    Tags present: v0.1.0 v0.2.0 v0.2.5 v1.0.0 v1.2.3 v1.9.0 v2.0.0
# ---------------------------------------------------------------------------

resolve() { # resolve <pkg> <constraint> -> the tag chosen, or "" on failure
    fresh_home
    "$THOTTAM" install "$1@$2" 2>&1 | sed -n 's/.*Resolved .* -> \(.*\)/\1/p' | head -1
}

check "constraint >=1.0.0 picks the highest tag"        "v2.0.0" "$(resolve kaappi-alpha '>=1.0.0')"
check "constraint <1.0.0 picks the highest below 1.0.0" "v0.2.5" "$(resolve kaappi-alpha '<1.0.0')"
check "constraint <=1.0.0 includes its own version"     "v1.0.0" "$(resolve kaappi-alpha '<=1.0.0')"
check "constraint ^1.2.3 stays inside major 1"          "v1.9.0" "$(resolve kaappi-alpha '^1.2.3')"
check "constraint ^0.2.0 stays inside minor 0.2"        "v0.2.5" "$(resolve kaappi-alpha '^0.2.0')"
check "constraint ~1.2.3 stays inside minor 1.2"        "v1.2.3" "$(resolve kaappi-alpha '~1.2.3')"
check "range >=1.0.0,<2.0.0 excludes the upper bound"   "v1.9.0" "$(resolve kaappi-alpha '>=1.0.0,<2.0.0')"
# node-semver allows whitespace between the operator and its version; the
# space used to make the whole range unparseable and was reported as "no
# version matching" (#2132).
check "constraint '>= 1.0.0' tolerates operator whitespace" "v2.0.0" "$(resolve kaappi-alpha '>= 1.0.0')"

fresh_home
out="$("$THOTTAM" install 'kaappi-alpha@>=9.0.0' 2>&1)" && ec=0 || ec=$?
check_exit "an unsatisfiable constraint fails" 1 "$ec"
check "an unsatisfiable constraint says so" "no version matching" "$out"

# A constraint that does not PARSE is a different failure from one that
# matches nothing: the old single message sent users hunting through the
# remote's tags for a range that was never valid (#2132).
for bad in '>=>1.0.0' '>=1.0.0,' '>=1.0.0-rc1'; do
    fresh_home
    out="$("$THOTTAM" install "kaappi-alpha@$bad" 2>&1)" && ec=0 || ec=$?
    check_exit "a malformed constraint fails [$bad]" 1 "$ec"
    check "a malformed constraint is reported as invalid [$bad]" "invalid version constraint" "$out"
    check_not "a malformed constraint is not called unmatched [$bad]" "no version matching" "$out"
done

# A constraint whose repository cannot be listed (here: it does not exist)
# is a fetch failure, not "no version matching" — the range is never even
# evaluated, and saying otherwise sends the user hunting through tags (#2132).
fresh_home
out="$("$THOTTAM" install 'kaappi-missing@>=1.0.0' 2>&1)" && ec=0 || ec=$?
check_exit "an unavailable repository fails" 1 "$ec"
check "an unavailable repository is reported as a fetch error" "failed to list tags" "$out"
check_not "an unavailable repository is not called unmatched" "no version matching" "$out"

# A tag that is a SemVer pre-release must not satisfy a plain range
# (node-semver: a range with no pre-release of its own excludes them).
check "a -rc1 pre-release tag does not satisfy >=1.0.0" \
    "v1.0.0" "$(resolve kaappi-odd '>=1.0.0')"

# ...but SemVer 2.0.0 s2 says a version is exactly three numeric components,
# so a tag with a fourth is not a version at all and must not be a candidate.
check "a four-component tag is not treated as a release" \
    "v1.0.0" "$(resolve kaappi-nightly '>=1.0.0')"

# Same property, sharper case: v1_0.0.0 used to parse as 10.0.0 via Zig's
# integer-literal grammar ('_' digit separator) and so outranked v2.0.0,
# REORDERING the release history (#2130).
mkpkg kaappi-underscore "" v2.0.0
(
    cd "$WORK/kaappi-underscore"
    git tag 'v1_0.0.0'
)
rm -rf "$ORG/kaappi-underscore.git"
git clone -q --bare "$WORK/kaappi-underscore" "$ORG/kaappi-underscore.git"
check "an underscore tag does not outrank a real release" \
    "v2.0.0" "$(resolve kaappi-underscore '>=2.0.0')"

# ---------------------------------------------------------------------------
# 4. The package-name guard: nothing escapes KAAPPI_HOME
# ---------------------------------------------------------------------------

fresh_home
for bad in '../../evil' 'foo/bar' '..' '.' 'a/../../b' '/tmp/evil' 'a\b' ''; do
    out="$("$THOTTAM" install "$bad" 2>&1)" && ec=0 || ec=$?
    check_exit "install rejects the name [$bad]" 1 "$ec"
    check "install names the rejected package [$bad]" "invalid package name" "$out"
done
out="$("$THOTTAM" remove '../../evil' 2>&1)" && ec=0 || ec=$?
check_exit "remove rejects a traversal name" 1 "$ec"
check "remove names the rejected package" "invalid package name" "$out"

# The same guarantee must hold for a name that arrives from a state file
# rather than from the command line: nothing should build a path out of an
# unvalidated package name.
fresh_home
printf '../../../../../../tmp/kaappi-escape-probe\n' > "$KAAPPI_HOME/installed.txt"
printf '../../../../../../tmp/kaappi-escape-probe deadbeef\n' > "$KAAPPI_HOME/thottam.lock"
out="$("$THOTTAM" update '../../../../../../tmp/kaappi-escape-probe' 2>&1)" && ec=0 || ec=$?
check_exit "update rejects a traversal name from the command line" 1 "$ec"
check "update names the rejected package" "invalid package name" "$out"
out="$("$THOTTAM" verify 2>&1)" && ec=0 || ec=$?
check_exit "verify fails on a traversal name read back from the lockfile" 1 "$ec"
check "verify names the corrupted entry" "MALFORMED" "$out"
# list must not even show a name it cannot act on — and must not touch the
# filesystem for it either (the escaped repo outside KAAPPI_HOME stays intact).
out="$("$THOTTAM" list 2>&1)" && ec=0 || ec=$?
check_exit "list tolerates a corrupted installed.txt" 0 "$ec"
check_not "list does not show the traversal name" "kaappi-escape-probe" "$out"
# The all-packages update form skips the corrupted line instead of running
# git outside KAAPPI_HOME.
out="$("$THOTTAM" update 2>&1)" && ec=0 || ec=$?
check_exit "update-all skips a corrupted installed.txt line" 0 "$ec"
check_not "update-all does not run git on the traversal name" "kaappi-escape-probe" "$out"

# Discriminating control: the destructive command does validate, so the
# escaped path is never a removeTree target.
out="$("$THOTTAM" remove '../../../../../../tmp/kaappi-escape-probe' 2>&1)" && ec=0 || ec=$?
check_exit "remove still rejects that name when it is in installed.txt" 1 "$ec"
check "remove names it as invalid rather than deleting it" "invalid package name" "$out"

# The guard also covers a name arriving from an untrusted manifest, which is
# the case a user never types and so never reviews.
mkdir -p "$WORK/kaappi-evildep/lib/kaappi"
(
    cd "$WORK/kaappi-evildep"
    git init -q .
    printf 'name: kaappi-evildep\ndepends: ../../../../../../tmp/kaappi-ESCAPED\n' > kaappi.pkg
    printf '(define-library (kaappi evildep) (export x) (import (scheme base)) (begin (define x 1)))\n' \
        > lib/kaappi/evildep.sld
    git add -A
    git_q commit -q -m base
)
git clone -q --bare "$WORK/kaappi-evildep" "$ORG/kaappi-evildep.git"
fresh_home
# The traversal target is a fixed absolute path baked into the fixture's
# manifest (it has to be — the escape is expressed relative to
# $KAAPPI_HOME/src), so clear it on both sides: a leftover from a previous
# run, or from a concurrent leg on a shared builder, would otherwise decide
# this assertion instead of the install under test.
rm -rf /tmp/kaappi-ESCAPED
out="$("$THOTTAM" install kaappi-evildep 2>&1)" && ec=0 || ec=$?
check_exit "a traversal name in a manifest depends: fails the install" 1 "$ec"
check "the rejected transitive name is reported" "invalid package name" "$out"
check_not "the traversal target was never created" "yes" \
    "$([[ -e /tmp/kaappi-ESCAPED ]] && echo yes || echo no)"
rm -rf /tmp/kaappi-ESCAPED

# ---------------------------------------------------------------------------
# 5. Re-installing at a different version
# ---------------------------------------------------------------------------

sha_v010="$(git -C "$WORK/kaappi-alpha" rev-parse 'v0.1.0^{commit}')"
sha_v100="$(git -C "$WORK/kaappi-alpha" rev-parse 'v1.0.0^{commit}')"
sha_v200="$(git -C "$WORK/kaappi-alpha" rev-parse 'v2.0.0^{commit}')"

# Control: pinning on a FRESH home works. The pin machinery is fine, and this
# assertion holds both before and after the fix below — it is what makes the
# re-install checks next to it about the *re*-install path specifically.
fresh_home
"$THOTTAM" install kaappi-alpha@v0.1.0 > /dev/null 2>&1
check "a first install at a pin records that pin's SHA" \
    "$sha_v010" "$(cat "$KAAPPI_HOME/thottam.lock")"

# The same command against an already-installed package must either move the
# install to the requested version or fail. Reporting success while leaving a
# different version in place makes it unusable in a provisioning script.
fresh_home
"$THOTTAM" install kaappi-alpha > /dev/null 2>&1
out="$("$THOTTAM" install kaappi-alpha@v0.1.0 2>&1)" && ec=0 || ec=$?
check_exit "re-installing at a pin succeeds" 0 "$ec"
check "re-installing at a pin records that pin's SHA" \
    "$sha_v010" "$(cat "$KAAPPI_HOME/thottam.lock")"
check "re-installing at a pin copies the pinned lib" \
    "v0.1.0" "$(sed -n 's/.*define tag "\([^"]*\)".*/\1/p' "$KAAPPI_HOME/lib/kaappi/alpha.sld")"

# Installing again at the same version is a clean no-op.
out="$("$THOTTAM" install kaappi-alpha@v0.1.0 2>&1)" && ec=0 || ec=$?
check_exit "re-installing at the same pin is a clean no-op" 0 "$ec"
check "re-installing at the same pin says already installed" "already installed (at v0.1.0)" "$out"

# And installing at yet another version moves the pin again — this is the
# workflow `update` points pinned users at.
out="$("$THOTTAM" install kaappi-alpha@v2.0.0 2>&1)" && ec=0 || ec=$?
check_exit "installing at a new version moves the pin" 0 "$ec"
check "installing at a new version records the new SHA" \
    "$sha_v200" "$(cat "$KAAPPI_HOME/thottam.lock")"

# A versioned re-install must not duplicate the installed.txt line: the
# record stays one line per package.
check "re-installing does not duplicate the installed.txt line" \
    "1" "$(grep -c '^kaappi-alpha$' "$KAAPPI_HOME/installed.txt")"

# ---------------------------------------------------------------------------
# 6. verify's coverage
# ---------------------------------------------------------------------------

fresh_home
"$THOTTAM" install kaappi-alpha > /dev/null 2>&1
"$THOTTAM" install kaappi-one > /dev/null 2>&1

out="$("$THOTTAM" verify 2>&1)" && ec=0 || ec=$?
check_exit "verify passes with both packages locked" 0 "$ec"
check "verify checks the first package" "OK: kaappi-alpha" "$out"
check "verify checks the second package" "OK: kaappi-one" "$out"

# Control: a lockfile entry whose SHA does not match IS caught.
sed 's/^kaappi-one .*/kaappi-one 0000000000000000000000000000000000000000/' \
    "$KAAPPI_HOME/thottam.lock" > "$KAAPPI_HOME/thottam.lock.new"
mv "$KAAPPI_HOME/thottam.lock.new" "$KAAPPI_HOME/thottam.lock"
out="$("$THOTTAM" verify 2>&1)" && ec=0 || ec=$?
check_exit "verify fails on a SHA mismatch" 1 "$ec"
check "verify names the mismatched package" "MISMATCH: kaappi-one" "$out"

# An installed package must be verified whether or not the lockfile happens
# to mention it — otherwise "All packages verified" is a claim about the
# lockfile, not about the installation.
grep -v '^kaappi-one ' "$KAAPPI_HOME/thottam.lock" > "$KAAPPI_HOME/thottam.lock.new"
mv "$KAAPPI_HOME/thottam.lock.new" "$KAAPPI_HOME/thottam.lock"
out="$("$THOTTAM" verify 2>&1)" && ec=0 || ec=$?
check_exit "verify fails when an installed package has no lockfile entry" 1 "$ec"
check "verify names the unlocked package" "UNLOCKED: kaappi-one" "$out"

# An empty lockfile is the degenerate case of the same thing: nothing is
# checked, and the command reports that everything is fine.
: > "$KAAPPI_HOME/thottam.lock"
out="$("$THOTTAM" verify 2>&1)" && ec=0 || ec=$?
check_exit "verify fails on an empty lockfile with packages installed" 1 "$ec"

# A lockfile line whose SHA field is empty is malformed, not an ordinary
# mismatch: verify must name it MALFORMED rather than comparing a SHA it
# never actually had.
fresh_home
"$THOTTAM" install kaappi-alpha > /dev/null 2>&1
printf 'kaappi-alpha  %s/kaappi-alpha.git\n' "$ORG" > "$KAAPPI_HOME/thottam.lock"
out="$("$THOTTAM" verify 2>&1)" && ec=0 || ec=$?
check_exit "verify fails on a lockfile line with an empty SHA" 1 "$ec"
check "verify names the malformed line" "MALFORMED: kaappi-alpha" "$out"
# Discriminating control: an ABSENT lockfile *is* caught, so the blind spot
# is specific to a lockfile that exists and says nothing.
rm -f "$KAAPPI_HOME/thottam.lock"
out="$("$THOTTAM" verify 2>&1)" && ec=0 || ec=$?
check_exit "verify fails when the lockfile is missing entirely" 1 "$ec"
check "verify says the lockfile is missing" "No lockfile found" "$out"

# ---------------------------------------------------------------------------
# 7. remove, and the shared library namespace
# ---------------------------------------------------------------------------

# kaappi-deep ships a nested lib tree, so a full removal must prune the empty
# directories it leaves behind (#2136).
mkpkg kaappi-deep ""
mkdir -p "$WORK/kaappi-deep/lib/kaappi/deep/deeper"
printf '(define-library (kaappi deep) (export tag) (import (scheme base)) (begin (define tag "deep")))\n' \
    > "$WORK/kaappi-deep/lib/kaappi/deep/deeper/x.sld"
(
    cd "$WORK/kaappi-deep"
    git add -A
    git_q commit -q -m deep
)
rm -rf "$ORG/kaappi-deep.git"
git clone -q --bare "$WORK/kaappi-deep" "$ORG/kaappi-deep.git"

fresh_home
"$THOTTAM" install kaappi-one > /dev/null 2>&1
out="$("$THOTTAM" remove kaappi-one 2>&1)" && ec=0 || ec=$?
check_exit "remove succeeds" 0 "$ec"
check "remove reports the package" "kaappi-one" "$out"
check_not "remove deletes the package's own .sld" "yes" \
    "$([[ -f "$KAAPPI_HOME/lib/kaappi/one.sld" ]] && echo yes || echo no)"
check_not "remove drops the package from installed.txt" \
    "kaappi-one" "$(cat "$KAAPPI_HOME/installed.txt")"
out="$("$THOTTAM" remove kaappi-one 2>&1)" && ec=0 || ec=$?
check_exit "removing an absent package fails" 1 "$ec"
check "removing an absent package says so" "is not installed" "$out"

# kaappi-one and kaappi-two both ship lib/kaappi/shared.sld. Removing one
# must not take a file the other is still relying on.
fresh_home
"$THOTTAM" install kaappi-one > /dev/null 2>&1
out="$("$THOTTAM" install kaappi-two 2>&1)" && ec=0 || ec=$?
# Installing kaappi-two overwrites a file kaappi-one's manifest claims; the
# install still succeeds, but it must say so.
check_exit "installing over another package's file still succeeds" 0 "$ec"
check "installing over another package's file warns" "also provided by kaappi-one" "$out"
check_file "both packages installed, shared.sld present" "$KAAPPI_HOME/lib/kaappi/shared.sld"
"$THOTTAM" remove kaappi-two > /dev/null 2>&1
check "kaappi-one is still listed as installed" "kaappi-one" "$("$THOTTAM" list)"
check_file "a still-installed package keeps its library file" \
    "$KAAPPI_HOME/lib/kaappi/shared.sld"
check_file "removing one package keeps the other's .sld" "$KAAPPI_HOME/lib/kaappi/one.sld"
check_not "removing one package deletes its own .sld" "yes" \
    "$([[ -f "$KAAPPI_HOME/lib/kaappi/two.sld" ]] && echo yes || echo no)"
# Removing the last claimant finally deletes the shared file.
"$THOTTAM" remove kaappi-one > /dev/null 2>&1
check_not "removing the last claimant deletes the shared file" "yes" \
    "$([[ -f "$KAAPPI_HOME/lib/kaappi/shared.sld" ]] && echo yes || echo no)"

# A full removal prunes the empty directories the files lived in.
fresh_home
"$THOTTAM" install kaappi-deep > /dev/null 2>&1
check_file "nested library file lands in lib" "$KAAPPI_HOME/lib/kaappi/deep/deeper/x.sld"
"$THOTTAM" remove kaappi-deep > /dev/null 2>&1
check_not "removal prunes empty nested directories" "yes" \
    "$([[ -d "$KAAPPI_HOME/lib/kaappi/deep" ]] && echo yes || echo no)"

# ---------------------------------------------------------------------------
# 8. update
# ---------------------------------------------------------------------------

fresh_home
"$THOTTAM" install kaappi-alpha > /dev/null 2>&1
out="$("$THOTTAM" update kaappi-alpha 2>&1)" && ec=0 || ec=$?
check_exit "update of an unpinned package succeeds" 0 "$ec"
check "update reports the resulting SHA" "updated (now at" "$out"

out="$("$THOTTAM" update kaappi-nosuch 2>&1)" && ec=0 || ec=$?
check_exit "update of an uninstalled package fails" 1 "$ec"
check "update of an uninstalled package says so" "is not installed" "$out"

# A package installed at a pin is on a detached HEAD, which `git pull`
# cannot advance. `thottam update` should say what it can and cannot do
# about a pinned package rather than surfacing git's own advice.
fresh_home
"$THOTTAM" install kaappi-alpha@v1.0.0 > /dev/null 2>&1
check "a first install at the v1.0.0 pin records that pin's SHA" \
    "$sha_v100" "$(cat "$KAAPPI_HOME/thottam.lock")"
out="$("$THOTTAM" update kaappi-alpha 2>&1)" && ec=0 || ec=$?
check_exit "updating a pinned package succeeds as a no-op" 0 "$ec"
check_not "updating a pinned package does not leak raw git advice" \
    "You are not currently on a branch" "$out"
check "updating a pinned package says it is pinned" "pinned at v1.0.0" "$out"
check "updating a pinned package names the way to move the pin" "to move the pin" "$out"

# One pinned package must not fail a whole-tree update: the pin is reported
# and skipped, everything else still updates.
fresh_home
"$THOTTAM" install kaappi-alpha@v1.0.0 > /dev/null 2>&1
"$THOTTAM" install kaappi-one > /dev/null 2>&1
out="$("$THOTTAM" update 2>&1)" && ec=0 || ec=$?
check_exit "updating all packages with one pinned succeeds" 0 "$ec"
check "updating all reports the pinned package" "pinned at" "$out"
check "updating all still updates the unpinned package" "kaappi-one updated" "$out"

# An upstream release that ADDS a file another package owns must record the
# new ownership during `update` — otherwise removing the other claimant
# later unlinks the file out from under the updated package (#2136 via the
# update path). kaappi-grower ships only grower.sld at first; kaappi-two
# already owns lib/kaappi/shared.sld.
mkpkg kaappi-grower ""
fresh_home
"$THOTTAM" install kaappi-grower > /dev/null 2>&1
"$THOTTAM" install kaappi-two > /dev/null 2>&1
check_not "before the update, grower does not claim shared.sld" \
    "kaappi-grower kaappi/shared.sld" "$(cat "$KAAPPI_HOME/thottam.files")"
(
    cd "$WORK/kaappi-grower"
    printf '(define-library (kaappi shared) (export owner) (import (scheme base)) (begin (define owner "grower")))\n' \
        > lib/kaappi/shared.sld
    git add -A
    git_q commit -q -m "add shared"
)
rm -rf "$ORG/kaappi-grower.git"
git clone -q --bare "$WORK/kaappi-grower" "$ORG/kaappi-grower.git"
out="$("$THOTTAM" update kaappi-grower 2>&1)" && ec=0 || ec=$?
check_exit "update pulling a shared file succeeds" 0 "$ec"
check "update warns it overwrites another package's file" "also provided by kaappi-two" "$out"
check "update records the new ownership" \
    "kaappi-grower kaappi/shared.sld" "$(cat "$KAAPPI_HOME/thottam.files")"
"$THOTTAM" remove kaappi-two > /dev/null 2>&1
check_file "removing the other claimant keeps the updated package's file" \
    "$KAAPPI_HOME/lib/kaappi/shared.sld"

# An upstream release that DROPS a file another package owns: update must
# keep the other package's copy and drop the ownership record, so removing
# the updated package cannot delete the file out from under the other one.
mkpkg kaappi-shrinker ""
(
    cd "$WORK/kaappi-shrinker"
    printf '(define-library (kaappi shared) (export owner) (import (scheme base)) (begin (define owner "shrinker")))\n' \
        > lib/kaappi/shared.sld
    git add -A
    git_q commit -q -m "add shared"
)
rm -rf "$ORG/kaappi-shrinker.git"
git clone -q --bare "$WORK/kaappi-shrinker" "$ORG/kaappi-shrinker.git"
fresh_home
"$THOTTAM" install kaappi-shrinker > /dev/null 2>&1
"$THOTTAM" install kaappi-one > /dev/null 2>&1
check "shrinker and one both claim shared.sld" \
    "kaappi-shrinker kaappi/shared.sld" "$(cat "$KAAPPI_HOME/thottam.files")"
(
    cd "$WORK/kaappi-shrinker"
    git rm -q lib/kaappi/shared.sld
    git_q commit -q -m "drop shared"
)
rm -rf "$ORG/kaappi-shrinker.git"
git clone -q --bare "$WORK/kaappi-shrinker" "$ORG/kaappi-shrinker.git"
out="$("$THOTTAM" update kaappi-shrinker 2>&1)" && ec=0 || ec=$?
check_exit "update dropping a shared file succeeds" 0 "$ec"
check_not "update drops the ownership record" \
    "kaappi-shrinker kaappi/shared.sld" "$(cat "$KAAPPI_HOME/thottam.files")"
check_file "the other package's shared file survives the update" \
    "$KAAPPI_HOME/lib/kaappi/shared.sld"
"$THOTTAM" remove kaappi-shrinker > /dev/null 2>&1
check_file "removing the updated package keeps the other's shared file" \
    "$KAAPPI_HOME/lib/kaappi/shared.sld"
"$THOTTAM" remove kaappi-one > /dev/null 2>&1
check_not "removing the last claimant deletes the shared file" "yes" \
    "$([[ -f "$KAAPPI_HOME/lib/kaappi/shared.sld" ]] && echo yes || echo no)"

# ---------------------------------------------------------------------------
# 9. --locked
# ---------------------------------------------------------------------------

fresh_home
"$THOTTAM" install "kaappi-alpha::$ORG/kaappi-alpha.git" > /dev/null 2>&1
saved_lock="$(cat "$KAAPPI_HOME/thottam.lock")"
cp "$KAAPPI_HOME/thottam.lock" "$KAAPPI_HOME/thottam.lock.saved"

out="$("$THOTTAM" --locked install kaappi-nosuch 2>&1)" && ec=0 || ec=$?
check_exit "--locked refuses a package absent from the lockfile" 1 "$ec"
check "--locked says the package is not in the lockfile" "not in the lockfile" "$out"

# Restore-from-lockfile: wipe the installation, keep the lockfile. This is
# the whole point of the flag — reproduce an installation from a committed
# lockfile — so it must be a fixed point: same SHA, same recorded source.
rm -rf "$KAAPPI_HOME/src" "$KAAPPI_HOME/lib"
: > "$KAAPPI_HOME/installed.txt"
out="$("$THOTTAM" --locked install kaappi-alpha 2>&1)" && ec=0 || ec=$?
check_exit "--locked restores a locked package" 0 "$ec"
check "--locked checks out the locked SHA" "Checking out" "$out"
check_files_eq "--locked restore leaves the lockfile byte-for-byte unchanged" \
    "$KAAPPI_HOME/thottam.lock.saved" "$KAAPPI_HOME/thottam.lock"
# Discriminating control: the SHA half of the line does survive the restore.
check "--locked restore preserves the locked SHA" \
    "$(printf '%s' "$saved_lock" | cut -d' ' -f2)" "$(cat "$KAAPPI_HOME/thottam.lock")"

# Control: --locked does enforce the SHA.
fresh_home
printf 'kaappi-alpha 0000000000000000000000000000000000000000 %s/kaappi-alpha.git\n' "$ORG" \
    > "$KAAPPI_HOME/thottam.lock"
out="$("$THOTTAM" --locked install kaappi-alpha 2>&1)" && ec=0 || ec=$?
check_exit "--locked fails when the locked SHA is unreachable" 1 "$ec"

# ...but the source URL recorded next to that SHA is not enforced, and is
# overwritten by whatever URL this invocation was handed. A fork that shares
# history satisfies the SHA check, so the one field that records *where the
# code came from* is both unchecked and destroyed by the check that passes.
git clone -q --bare "$ORG/kaappi-alpha.git" "$ORG/FORK-kaappi-alpha.git"
fresh_home
"$THOTTAM" install "kaappi-alpha::$ORG/kaappi-alpha.git" > /dev/null 2>&1
rm -rf "$KAAPPI_HOME/src" "$KAAPPI_HOME/lib"
: > "$KAAPPI_HOME/installed.txt"
out="$("$THOTTAM" --locked install "kaappi-alpha::$ORG/FORK-kaappi-alpha.git" 2>&1)" && ec=0 || ec=$?
check_exit "--locked refuses a source URL that differs from the lockfile" 1 "$ec"
check "--locked names the source URL mismatch" "source URL mismatch" "$out"
check_not "--locked refuses before cloning the fork" "yes" \
    "$([[ -d "$KAAPPI_HOME/src/kaappi-alpha" ]] && echo yes || echo no)"
check "--locked leaves the recorded provenance intact" \
    "$ORG/kaappi-alpha.git" "$(cat "$KAAPPI_HOME/thottam.lock")"

# Control for the reject path above: a ::url that MATCHES the recorded source
# is accepted, so the enforcement is exact rather than a blanket refusal of
# every explicit ::url.
fresh_home
"$THOTTAM" install "kaappi-alpha::$ORG/kaappi-alpha.git" > /dev/null 2>&1
rm -rf "$KAAPPI_HOME/src" "$KAAPPI_HOME/lib"
: > "$KAAPPI_HOME/installed.txt"
out="$("$THOTTAM" --locked install "kaappi-alpha::$ORG/kaappi-alpha.git" 2>&1)" && ec=0 || ec=$?
check_exit "--locked accepts a source URL that matches the lockfile" 0 "$ec"
check "--locked matching-source restore records the same provenance" \
    "$ORG/kaappi-alpha.git" "$(cat "$KAAPPI_HOME/thottam.lock")"

# ---------------------------------------------------------------------------
# 10. kaappi.pkg's name: and source: fields are wired up (issue #2138)
# ---------------------------------------------------------------------------

# name: is consistency-checked against the package being installed. A manifest
# that names a different package is a packaging error, and the install refuses
# BEFORE recording anything, rather than cloning under the wrong identity.
mkdir -p "$WORK/kaappi-badname/lib/kaappi"
(
    cd "$WORK/kaappi-badname"
    git init -q .
    printf 'name: WRONG-NAME-ENTIRELY\nsource: https://evil.example.com/not-this-repo\nversion: 99.99.99\n' > kaappi.pkg
    printf '(define-library (kaappi badname) (export tag) (import (scheme base)) (begin (define tag "bad")))\n' \
        > lib/kaappi/badname.sld
    git add -A
    git_q commit -q -m base
)
git clone -q --bare "$WORK/kaappi-badname" "$ORG/kaappi-badname.git"
fresh_home
out="$("$THOTTAM" install kaappi-badname 2>&1)" && ec=0 || ec=$?
check_exit "a manifest naming a different package is refused" 1 "$ec"
check "the refusal names both the declared and the requested name" \
    "declares name 'WRONG-NAME-ENTIRELY' but installing 'kaappi-badname'" "$out"
check_not "the refused package is not recorded in the lockfile" \
    "kaappi-badname" "$(cat "$KAAPPI_HOME/thottam.lock" 2>/dev/null || true)"
# The refusal exits cleanly: no raw `error.ManifestNameMismatch` second line
# from Zig's default handler (the #2132 duplicate-message pattern).
check_not "the refusal prints no raw Zig error name" "error.ManifestNameMismatch" "$out"
# And it leaves no unrecorded checkout behind for a later install to reuse.
[[ -d "$KAAPPI_HOME/src/kaappi-badname" ]] && leftover=present || leftover=absent
check "the refused install leaves no checkout behind" "absent" "$leftover"
# version: is not a field — thottam locks by git SHA — so it neither helps nor
# harms; the refusal above came from name:, never from the bogus version.

# In --locked mode the lockfile vouches for the exact SHA, so the manifest is
# not re-litigated: a name: that mismatches does NOT refuse a locked restore
# (the check is scoped to unlocked installs, matching source: being ignored
# under --locked). Seed a lockfile pointing at the badname repo, then restore.
fresh_home
badsha="$(git -C "$ORG/kaappi-badname.git" rev-parse HEAD)"
printf 'kaappi-badname %s\n' "$badsha" > "$KAAPPI_HOME/thottam.lock"
mkdir -p "$KAAPPI_HOME"
out="$("$THOTTAM" install --locked kaappi-badname 2>&1)" && ec=0 || ec=$?
check_exit "--locked does not enforce name: (lockfile vouches for the SHA)" 0 "$ec"
check_not "the locked restore does not raise a name mismatch" \
    "declares name" "$out"

# source: on a bare-name install is recorded as provenance, so `list` shows
# where the package is hosted. The record is surfaced with a note, never
# silent, because the manifest now steers where a later --locked install
# fetches from.
mkdir -p "$WORK/kaappi-declared/lib/kaappi"
(
    cd "$WORK/kaappi-declared"
    git init -q .
    printf 'name: kaappi-declared\nsource: https://forge.example.org/kaappi-declared\n' > kaappi.pkg
    printf '(define-library (kaappi declared) (export tag) (import (scheme base)) (begin (define tag "d")))\n' \
        > lib/kaappi/declared.sld
    git add -A
    git_q commit -q -m base
)
git clone -q --bare "$WORK/kaappi-declared" "$ORG/kaappi-declared.git"
fresh_home
out="$("$THOTTAM" install kaappi-declared 2>&1)" && ec=0 || ec=$?
check_exit "a manifest with a valid name and a source installs" 0 "$ec"
check "the declared source is surfaced with a note at record time" \
    "note: recording declared source https://forge.example.org/kaappi-declared" "$out"
check "the declared source reaches the lockfile as provenance" \
    "https://forge.example.org/kaappi-declared" "$(cat "$KAAPPI_HOME/thottam.lock")"
check "the declared source shows in list" \
    "(from: https://forge.example.org/kaappi-declared)" "$("$THOTTAM" list)"

# A command-line ::url is authoritative for the fetch; a manifest source: that
# disagrees warns (a fork/mirror is legitimate) and the lockfile records the
# URL actually fetched, not the manifest's claim.
fresh_home
out="$("$THOTTAM" install "kaappi-declared::$ORG/kaappi-declared.git" 2>&1)" && ec=0 || ec=$?
check_exit "an install with a ::url that disagrees with source: still succeeds" 0 "$ec"
check "the divergence between ::url and manifest source: is warned, not silent" \
    "declares source 'https://forge.example.org/kaappi-declared' but was fetched from" "$out"
check "the lockfile records the fetched ::url, not the manifest's claim" \
    "$ORG/kaappi-declared.git" "$(cat "$KAAPPI_HOME/thottam.lock")"
check_not "the manifest's claimed source does not override the fetch URL" \
    "forge.example.org" "$(cat "$KAAPPI_HOME/thottam.lock")"

# A ::url that differs from source: only by a trailing slash or a `.git` suffix
# is the same remote, so it must NOT warn — otherwise the warning trains users
# to ignore it. Manifest declares the bare path; install via the `.git` spelling.
mkdir -p "$WORK/kaappi-cosmetic/lib/kaappi"
(
    cd "$WORK/kaappi-cosmetic"
    git init -q .
    printf 'name: kaappi-cosmetic\nsource: %s/kaappi-cosmetic\n' "$ORG" > kaappi.pkg
    printf '(define-library (kaappi cosmetic) (export tag) (import (scheme base)) (begin (define tag "c")))\n' \
        > lib/kaappi/cosmetic.sld
    git add -A
    git_q commit -q -m base
)
git clone -q --bare "$WORK/kaappi-cosmetic" "$ORG/kaappi-cosmetic.git"
fresh_home
out="$("$THOTTAM" install "kaappi-cosmetic::$ORG/kaappi-cosmetic.git" 2>&1)" && ec=0 || ec=$?
check_exit "a cosmetic ::url-vs-source: difference installs" 0 "$ec"
check_not "a trailing-.git-only difference does not warn" "declares source" "$out"

# A later --locked install actually consumes the recorded source: it clones
# from the manifest-declared remote, not the org default. The default's own
# repo declares an alternate remote (a byte-identical bare clone, so the SHA
# matches); a bare-name install records the alternate as provenance; then the
# default is made unavailable and a --locked restore must still succeed —
# proving it fetched from the recorded alternate.
mkdir -p "$WORK/kaappi-mirror/lib/kaappi"
(
    cd "$WORK/kaappi-mirror"
    git init -q .
    printf 'name: kaappi-mirror\nsource: %s/kaappi-mirror-alt.git\n' "$ORG" > kaappi.pkg
    printf '(define-library (kaappi mirror) (export tag) (import (scheme base)) (begin (define tag "m")))\n' \
        > lib/kaappi/mirror.sld
    git add -A
    git_q commit -q -m base
)
git clone -q --bare "$WORK/kaappi-mirror" "$ORG/kaappi-mirror.git"
# The alternate is a byte-identical bare clone, so its HEAD SHA matches.
git clone -q --bare "$ORG/kaappi-mirror.git" "$ORG/kaappi-mirror-alt.git"
fresh_home
"$THOTTAM" install kaappi-mirror > /dev/null 2>&1
check "the recorded provenance is the declared alternate remote" \
    "kaappi-mirror-alt.git" "$(cat "$KAAPPI_HOME/thottam.lock")"
# Wipe the checkout and make the org default unreachable; only the recorded
# alternate can satisfy the restore now.
rm -rf "$KAAPPI_HOME/src/kaappi-mirror" "$KAAPPI_HOME/lib/kaappi/mirror.sld"
: > "$KAAPPI_HOME/installed.txt"
mv "$ORG/kaappi-mirror.git" "$ORG/kaappi-mirror.git.unavailable"
out="$("$THOTTAM" install --locked kaappi-mirror 2>&1)" && ec=0 || ec=$?
check_exit "--locked restore clones from the recorded source (org default gone)" 0 "$ec"
check_file "the locked restore actually fetched the library" \
    "$KAAPPI_HOME/lib/kaappi/mirror.sld"
mv "$ORG/kaappi-mirror.git.unavailable" "$ORG/kaappi-mirror.git"

# A manifest source that is a git remote-helper transport (ext::<cmd> executes
# a command) is refused, never recorded, and never executed — the package still
# installs from where it was actually fetched (kaappi#2138, CWE-78).
evilmarker="$WORK/evil-ran"
mkdir -p "$WORK/kaappi-evilsrc/lib/kaappi"
(
    cd "$WORK/kaappi-evilsrc"
    git init -q .
    printf "name: kaappi-evilsrc\nsource: ext::sh -c 'touch %s'\n" "$evilmarker" > kaappi.pkg
    printf '(define-library (kaappi evilsrc) (export tag) (import (scheme base)) (begin (define tag "e")))\n' \
        > lib/kaappi/evilsrc.sld
    git add -A
    git_q commit -q -m base
)
git clone -q --bare "$WORK/kaappi-evilsrc" "$ORG/kaappi-evilsrc.git"
fresh_home
out="$("$THOTTAM" install kaappi-evilsrc 2>&1)" && ec=0 || ec=$?
check_exit "a manifest with an ext:: source still installs from the fetched remote" 0 "$ec"
check "the unsupported transport is refused with a warning" \
    "unsupported source transport" "$out"
check_not "the ext:: source is not recorded in the lockfile" \
    "ext::" "$(cat "$KAAPPI_HOME/thottam.lock")"
[[ -e "$evilmarker" ]] && evilran=yes || evilran=no
check "the ext:: command is never executed" "no" "$evilran"

# A manifest without a name: still installs — name: is checked when present,
# not required to exist.
mkdir -p "$WORK/kaappi-minimal/lib/kaappi"
(
    cd "$WORK/kaappi-minimal"
    git init -q .
    printf 'depends:\nbuild:\n' > kaappi.pkg
    printf '(define-library (kaappi minimal) (export tag) (import (scheme base)) (begin (define tag "min")))\n' \
        > lib/kaappi/minimal.sld
    git add -A
    git_q commit -q -m base
)
git clone -q --bare "$WORK/kaappi-minimal" "$ORG/kaappi-minimal.git"
fresh_home
out="$("$THOTTAM" install kaappi-minimal 2>&1)" && ec=0 || ec=$?
check_exit "a manifest without name: installs cleanly" 0 "$ec"
check "the manifest-less-name package installs" "installed (locked at" "$out"

# ---------------------------------------------------------------------------

echo ""
echo "thottam lifecycle: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
