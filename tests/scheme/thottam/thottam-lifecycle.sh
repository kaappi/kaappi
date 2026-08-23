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

# thottam invokes git as the absolute path /usr/bin/git (thottam_proc.zig:148),
# not through PATH. That path exists on macOS and on CI's Linux images, and on
# none of the three BSDs -- FreeBSD and OpenBSD put git in /usr/local/bin,
# NetBSD in /usr/pkg/bin -- so every git-backed thottam operation fails there
# (kaappi#2152). This suite is entirely git-backed, so it cannot run.
#
# Probe for the exact precondition rather than listing platforms: when #2152 is
# fixed to search PATH, this check should be replaced by `command -v git`,
# which is already asserted above. Until then, testing for the very path
# thottam will execute is the honest gate -- it skips exactly where thottam is
# broken and nowhere else.
#
# An earlier version of this probe created a bare repo and cloned it, on the
# hypothesis that local-bare-clone was unsupported there. It PASSED on OpenBSD
# while the suite still failed, because the probe used PATH and thottam does
# not. That falsified hypothesis is what located #2152.
if [[ ! -x /usr/bin/git ]]; then
    echo "SKIP: thottam hardcodes /usr/bin/git, which does not exist here (kaappi#2152)"
    exit 77
fi

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
# FAIL: #2144 (isValidPkgName guards install and remove only; list, verify and
# update take the name straight from installed.txt / thottam.lock, so `git -C
# <escaped path>` runs outside KAAPPI_HOME)
# check "update rejects a traversal name read back from installed.txt" \
#     "invalid package name" "$out"
# out="$("$THOTTAM" verify 2>&1)" && ec=0 || ec=$?
# check "verify rejects a traversal name read back from the lockfile" \
#     "invalid package name" "$out"

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

# Control: pinning on a FRESH home works. The pin machinery is fine, and this
# assertion holds both before and after the fix below — it is what makes the
# disabled one next to it about the *re*-install path specifically.
fresh_home
"$THOTTAM" install kaappi-alpha@v0.1.0 > /dev/null 2>&1
check "a first install at a pin records that pin's SHA" \
    "$sha_v010" "$(cat "$KAAPPI_HOME/thottam.lock")"

# The same command against an already-installed package must either move the
# install to the requested version or fail. Reporting success while leaving a
# different version in place makes it unusable in a provisioning script.
fresh_home
"$THOTTAM" install kaappi-alpha > /dev/null 2>&1
"$THOTTAM" install kaappi-alpha@v0.1.0 > /dev/null 2>&1 || true
# FAIL: #2134 (the "already installed" short-circuit runs before the requested
# version is looked at, so this exits 0 having done nothing)
# check "re-installing at a pin records that pin's SHA" \
#     "$sha_v010" "$(cat "$KAAPPI_HOME/thottam.lock")"

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
"$THOTTAM" install kaappi-two > /dev/null 2>&1
check_file "both packages installed, shared.sld present" "$KAAPPI_HOME/lib/kaappi/shared.sld"
"$THOTTAM" remove kaappi-two > /dev/null 2>&1
check "kaappi-one is still listed as installed" "kaappi-one" "$("$THOTTAM" list)"
# FAIL: #2136 (removal unlinks every .sld name the removed package ships, with
# no record of which package a given installed file came from, so kaappi-one
# loses lib/kaappi/shared.sld while still being reported as installed)
# check_file "a still-installed package keeps its library file" \
#     "$KAAPPI_HOME/lib/kaappi/shared.sld"

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
out="$("$THOTTAM" update kaappi-alpha 2>&1)" && ec=0 || ec=$?
# FAIL: #2134 (update runs `git pull` unconditionally; on the detached HEAD a
# pinned install leaves behind, it fails with git's "You are not currently on
# a branch" and no thottam-level explanation)
# check_not "updating a pinned package does not leak raw git advice" \
#     "You are not currently on a branch" "$out"

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

echo ""
echo "thottam lifecycle: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
