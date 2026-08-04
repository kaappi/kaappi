#!/bin/bash
# `kaappi --completions <shell>` / `thottam --completions <shell>` — the
# completions-vs-flag-table drift gate (kaappi audit v2, Phase 6C, #1890).
#
# The scripts are generated at comptime from `src/cli_spec.zig`, the same
# tables the argument parsers dispatch on, so this suite checks the property
# that matters end to end against the *real binary*:
#
#   * soundness — every flag a script offers in a given context is one the
#     binary accepts in that context. Before 6C the zsh and fish scripts
#     offered all 21 global flags inside `explain`/`features`/`test`/`doctor`/
#     `cache`, whose own parsers reject 15 of them with exit 2.
#   * completeness — every flag `kaappi --help` documents is offered.
#     `--no-ir-opt` was in the parser and in none of the three scripts.
#   * the scripts parse as the shell they claim to be, and the bash one
#     actually completes when driven.
#
# The bash function is *executed* (this suite already runs under bash, and the
# Windows legs run it under Git Bash). zsh and fish are syntax-checked only
# when present — neither is installed on every CI leg.

set -uo pipefail

. "$(dirname "$0")/../shell-common.sh"

KAAPPI="${1:-${KAAPPI:-zig-out/bin/kaappi}}"
# Absolute, because the soundness probes below run from inside $TMP: several
# offered flags (-o, --compile, --emit-llvm, --coverage-xml) make the binary
# *write* a file named after its argument, and a probe that does that in the
# repo checkout leaves droppings in the working tree.
KAAPPI="$(cd "$(dirname "$KAAPPI")" && pwd)/$(basename "$KAAPPI")"
THOTTAM="$(sibling_tool "$KAAPPI" thottam)"
PASS=0
FAIL=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Never touch the developer's real cache while probing.
export KAAPPI_HOME="$TMP/home"
mkdir -p "$KAAPPI_HOME"

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1 — $2"; FAIL=$((FAIL + 1)); }

# ── 1. Every shell emits a script, and unknown shells are a usage error ─────
#
# The generated scripts are named after the *tool* (kaappi, thottam), never
# after the binary file: on Windows that file is kaappi.exe, and every reader
# below — `bash -n`, the sourced completion function, the grep assertions —
# wants one stable spelling. Deriving the name from `basename "$bin"` wrote
# kaappi.exe.bash while §3 and §4 went on sourcing kaappi.bash, which is 19
# of this suite's 39 checks failing on Windows for no reason of their own.

bin_for() { # <tool> -> the binary path for that tool
    case "$1" in
        kaappi) printf '%s\n' "$KAAPPI" ;;
        thottam) printf '%s\n' "$THOTTAM" ;;
    esac
}

for shell in bash zsh fish; do
    for tool in kaappi thottam; do
        bin="$(bin_for "$tool")"
        name="$tool --completions $shell"
        out="$TMP/$tool.$shell"
        status=0
        "$bin" --completions "$shell" > "$out" 2> "$TMP/err" || status=$?
        if [[ "$status" -ne 0 ]]; then
            fail "$name exits 0" "exit $status"
        elif [[ ! -s "$out" ]]; then
            fail "$name emits a script" "empty output"
        else
            pass "$name emits a script"
        fi
    done
done

# ── 2. The scripts parse as the shell they claim to be ──────────────────────

for tool in kaappi thottam; do
    if bash -n "$TMP/$tool.bash" 2> "$TMP/err"; then
        pass "$tool bash script parses (bash -n)"
    else
        fail "$tool bash script parses (bash -n)" "$(cat "$TMP/err")"
    fi
done

if command -v zsh > /dev/null 2>&1; then
    for tool in kaappi thottam; do
        if zsh -n "$TMP/$tool.zsh" 2> "$TMP/err"; then
            pass "$tool zsh script parses (zsh -n)"
        else
            fail "$tool zsh script parses (zsh -n)" "$(cat "$TMP/err")"
        fi
    done
else
    echo "SKIP: zsh not installed, skipping zsh -n"
fi

if command -v fish > /dev/null 2>&1; then
    for tool in kaappi thottam; do
        if fish --no-execute "$TMP/$tool.fish" 2> "$TMP/err"; then
            pass "$tool fish script parses (fish --no-execute)"
        else
            fail "$tool fish script parses (fish --no-execute)" "$(cat "$TMP/err")"
        fi
    done
else
    echo "SKIP: fish not installed, skipping fish --no-execute"
fi

# ── 3. Drive the bash completion function ───────────────────────────────────
#
# Sourced in a subshell per query so a stray `return` or variable cannot leak
# into this script's own state.

# offers [subcommand] -> the flag words offered in that context, one per line.
offers() {
    (
        # shellcheck disable=SC1090
        . "$TMP/kaappi.bash"
        local -a w=(kaappi)
        local a
        for a in "$@"; do w+=("$a"); done
        w+=("-")
        COMP_WORDS=("${w[@]}")
        COMP_CWORD=$((${#w[@]} - 1))
        COMPREPLY=()
        _kaappi
        [[ ${#COMPREPLY[@]} -gt 0 ]] && printf '%s\n' "${COMPREPLY[@]}"
    )
}

# plain_words [subcommand] -> what is offered when the current word is empty.
plain_words() {
    (
        # shellcheck disable=SC1090
        . "$TMP/kaappi.bash"
        local -a w=(kaappi)
        local a
        for a in "$@"; do w+=("$a"); done
        w+=("")
        COMP_WORDS=("${w[@]}")
        COMP_CWORD=$((${#w[@]} - 1))
        COMPREPLY=()
        _kaappi
        [[ ${#COMPREPLY[@]} -gt 0 ]] && printf '%s\n' "${COMPREPLY[@]}"
    )
}

top_flags="$(offers)"
if [[ -n "$top_flags" ]]; then
    pass "bash completes top-level flags"
else
    fail "bash completes top-level flags" "COMPREPLY was empty"
fi

# Every subcommand is offered as a bare word at the top level.
missing_subs=""
for sub in compile check explain features test ast expand ir doctor fmt cache; do
    if ! grep -qxF -- "$sub" <<< "$(plain_words)"; then
        missing_subs="$missing_subs $sub"
    fi
done
if [[ -z "$missing_subs" ]]; then
    pass "bash offers all 11 subcommands"
else
    fail "bash offers all 11 subcommands" "missing:$missing_subs"
fi

# `kaappi cache <TAB>` offers exactly the two actions the parser accepts.
cache_words="$(plain_words cache)"
if grep -qxF -- "status" <<< "$cache_words" && grep -qxF -- "clear" <<< "$cache_words"; then
    pass "bash offers the cache actions"
else
    fail "bash offers the cache actions" "got: $(tr '\n' ' ' <<< "$cache_words")"
fi

# `kaappi --completions <TAB>` offers the shells the binary supports.
shell_words="$(plain_words --completions)"
for s in bash zsh fish; do
    if ! grep -qxF -- "$s" <<< "$shell_words"; then
        fail "bash completes --completions values" "missing $s"
        break
    fi
done
grep -qxF -- "fish" <<< "$shell_words" && pass "bash completes --completions values"

# ── 4. Completeness: --help and the completions agree ───────────────────────
#
# Both are generated from the same table but by different code, so this is a
# real cross-check. Take every `--flag` / `-x` the Options: block names.

"$KAAPPI" --help > "$TMP/help.txt" 2>&1
# ERE, not BRE with `\|`: GNU's alternation escape is not POSIX and matches
# nothing under OpenBSD's grep (kaappi#1862).
help_flags="$(sed -n '/^Options:/,/^$/p' "$TMP/help.txt" |
    grep -oE '^  -[A-Za-z-]+|, --[A-Za-z-]+' |
    tr -d ' ,' | sort -u)"

if [[ -z "$help_flags" ]]; then
    fail "extracted flags from --help" "Options: block matched nothing"
else
    pass "extracted flags from --help"
fi

missing=""
for f in $help_flags; do
    # A `=`-syntax flag is completed as its full `--flag=value` spellings, and
    # deliberately not as the bare word: `--diagnostics` with no attached value
    # is "unknown option" to the parser, so offering it would be unsound.
    if grep -qxF -- "$f" <<< "$top_flags"; then continue; fi
    if grep -qF -- "$f=" <<< "$top_flags"; then continue; fi
    missing="$missing $f"
done
if [[ -z "$missing" ]]; then
    pass "every --help option is completed at the top level"
else
    fail "every --help option is completed at the top level" "missing:$missing"
fi

# The flag whose absence motivated this unit, asserted by name in all three.
for shell in bash zsh fish; do
    if grep -qF -- "no-ir-opt" "$TMP/kaappi.$shell"; then
        pass "$shell script offers --no-ir-opt (#1890 6C)"
    else
        fail "$shell script offers --no-ir-opt (#1890 6C)" "absent"
    fi
done

# `kaappi test`'s selection flags postdate the hand-written scripts.
for shell in bash zsh fish; do
    absent=""
    for f in jobs changed list-affected since seed; do
        grep -qF -- "$f" "$TMP/kaappi.$shell" || absent="$absent --$f"
    done
    if [[ -z "$absent" ]]; then
        pass "$shell script offers kaappi test's selection flags"
    else
        fail "$shell script offers kaappi test's selection flags" "missing:$absent"
    fi
done

# ── 5. Soundness: everything offered is accepted, in context ────────────────
#
# Run the binary with each offered flag and require it not to be named as the
# rejected token. Matching the exact "unknown option '<flag>'" phrasing (rather
# than any nonzero exit) keeps a flag that legitimately errors for another
# reason — "--seed requires an integer" — from reading as a false rejection,
# and keeps the probe arguments below from being mistaken for the flag.
#
# PROBE is a path that cannot exist, so `kaappi test` never runs a suite and
# the pipeline subcommands never compile anything: every probe is a parse-only
# round trip.
PROBE="__kaappi_completions_probe_no_such_path__"

rejected_as() { # <flag> <output-file>
    grep -qF -- "unknown option '$1'" "$2" ||
        grep -qF -- "unexpected argument '$1'" "$2" ||
        grep -qF -- "unknown subcommand '$1'" "$2"
}

check_context() { # <label> [subcommand]
    local label="$1"
    shift
    local flags bad flag
    flags="$(offers "$@")"
    if [[ -z "$flags" ]]; then
        fail "$label offers something" "COMPREPLY was empty"
        return
    fi
    bad=""
    while IFS= read -r flag; do
        [[ -z "$flag" ]] && continue
        # Run from inside $TMP: -o / --compile / --emit-llvm / --coverage-xml
        # all write a file named after the argument that follows them.
        ( cd "$TMP" && "$KAAPPI" "$@" "$flag" "$PROBE" "$PROBE" ) > "$TMP/o" 2> "$TMP/e"
        if rejected_as "$flag" "$TMP/o" || rejected_as "$flag" "$TMP/e"; then
            bad="$bad $flag"
        fi
    done <<< "$flags"
    if [[ -z "$bad" ]]; then
        pass "$label offers only flags the parser accepts ($(wc -w <<< "$flags" | tr -d ' ') probed)"
    else
        fail "$label offers only flags the parser accepts" "rejected:$bad"
    fi
}

check_context "top level"
check_context "kaappi explain" explain
check_context "kaappi features" features
check_context "kaappi test" test
check_context "kaappi ir" ir
check_context "kaappi fmt" fmt
check_context "kaappi cache" cache
# `doctor` runs a native smoke link per invocation, so probe it directly with
# its own (short) list rather than through the generic helper's extra args.
for flag in --json --help -h; do
    ( cd "$TMP" && "$KAAPPI" doctor "$flag" ) > "$TMP/o" 2> "$TMP/e"
    if rejected_as "$flag" "$TMP/o" || rejected_as "$flag" "$TMP/e"; then
        fail "kaappi doctor accepts $flag" "rejected"
    else
        pass "kaappi doctor accepts $flag"
    fi
done

# The control that makes the soundness checks discriminating: a flag the
# subcommand genuinely does not accept must be caught by `rejected_as`. Without
# this, a broken matcher would make every check above pass vacuously.
( cd "$TMP" && "$KAAPPI" features --sandbox ) > "$TMP/o" 2> "$TMP/e"
if rejected_as "--sandbox" "$TMP/o" || rejected_as "--sandbox" "$TMP/e"; then
    pass "control: kaappi features rejects --sandbox and the matcher sees it"
else
    fail "control: kaappi features rejects --sandbox and the matcher sees it" \
        "matcher found no rejection — the soundness checks above prove nothing"
fi
# And the completions must not be offering it there.
if grep -qxF -- "--sandbox" <<< "$(offers features)"; then
    fail "kaappi features does not complete --sandbox" "it is offered"
else
    pass "kaappi features does not complete --sandbox"
fi

# ── 6. thottam ─────────────────────────────────────────────────────────────

for flag in --locked --help -h --version; do
    ( cd "$TMP" && "$THOTTAM" "$flag" list ) > "$TMP/o" 2> "$TMP/e"
    if rejected_as "$flag" "$TMP/o" || rejected_as "$flag" "$TMP/e"; then
        fail "thottam accepts $flag" "rejected"
    else
        pass "thottam accepts $flag"
    fi
done

for shell in bash zsh fish; do
    absent=""
    for w in install remove list update verify locked completions; do
        grep -qF -- "$w" "$TMP/thottam.$shell" || absent="$absent $w"
    done
    if [[ -z "$absent" ]]; then
        pass "thottam $shell script names every flag and subcommand"
    else
        fail "thottam $shell script names every flag and subcommand" "missing:$absent"
    fi
done

# ── Summary ────────────────────────────────────────────────────────────────

echo
echo "completions: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
