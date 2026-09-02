#!/usr/bin/env bash
# Run one named chunk of the Zig unit suite, so a hang names its chunk.
#
#     bash tools/run-unit-test-chunk.sh <process|concurrency|rest> [zig build args...]
#     bash tools/run-unit-test-chunk.sh --list <chunk>      # print the filters, run nothing
#
# WHY THIS EXISTS. `riscv64-test` runs the whole unit suite under QEMU
# user-mode as ONE `zig build test` step that prints nothing until it
# finishes. When a test hangs there, the only evidence is a 45-minute log
# with a single line in it and an `unit-tests` orphan at the end (kaappi#2488
# -- roughly one run in four since 2026-09-02). Splitting the suite into a
# few chunks, each its own workflow step with its own `timeout-minutes`,
# makes the next hang say WHICH chunk it was in. Chunking is a diagnostic,
# not a fix; the chunks exist to be narrowed, not to grow.
#
# HOW THE CHUNKS ARE CUT. `-Dtest-filter` is a substring match on a test's
# qualified name, `<file basename>.test.<title>` (build.zig; repeatable).
# Anchoring every filter as `<basename>.test.` selects exactly the tests
# declared in that file: `ffi.test.` also matches `tests_ffi.test.…`, but a
# test is included ONCE however many filters match it (the filter prunes
# `builtin.test_functions` at compile time), so overlap costs nothing and
# every filter is emitted unconditionally. The one consequence across
# chunks: a listed file whose basename ENDS with an unlisted file's basename
# also runs in `rest` (`native_compiler` ends with `compiler`, so its five
# tests run in both `native` and `rest`). That is a few seconds of
# duplicated work, never a dropped test, and the exact per-chunk counts are
# in the PR that introduced each chunk.
#
#   process      the KEP-0022 subprocess tests: every child they spawn is a
#                whole /bin/sh emulated through binfmt on the QEMU legs
#   concurrency  fibers, reactor, scheduler, channels, SRFI-18 threads --
#                the parking and timing paths
#   io           ports and the reactor-driven reads behind them: file and
#                string ports, transcoded ports (SRFI 181), the incremental
#                reader, the filesystem primitives (SRFI 170)
#   fuzz         the fuzz generators and their wall-clock/instruction-bounded
#                harness (#1573 was this family flaking under QEMU)
#   gc           the collector: tracing, runtime stress, root-boundary OOM
#                sweeps, deep copy, and the robustness edge-case suite
#   native       the LLVM native tier (skips almost entirely on the
#                interpreter-tier QEMU legs, so this chunk is cheap there)
#   tooling      the CLI surface and its subcommands (check, fmt, doctor,
#                explain, features, the `kaappi test` runner -- whose worker
#                processes are emulated children on the QEMU legs), the
#                bytecode/library caches, the REPL, and thottam (this is
#                where the `thottam-tests` binary runs its full suite)
#   rest         EVERY OTHER `src/*.zig` file that declares a `test "…"`,
#                derived from the tree, so a new test file lands here
#                automatically and cannot be silently dropped
#
# The first split (process / concurrency / rest) localised kaappi#2488's
# first recurrence to `rest`, which was 1646 tests wide; the io / fuzz / gc /
# native chunks are the second cut, along the seams in that remainder with
# QEMU-sensitive behaviour. Add a chunk by adding a list and a case below;
# `rest` shrinks by itself because it is derived from what is NOT listed.
#
# Two things keep the split honest. A name in the explicit lists that matches
# no file FAILS the run (a list cannot rot into a silent no-op -- the same
# rule `KAAPPI_GC_STRESS_SKIP` follows). And every chunk asserts it ran more
# tests than the unnamed `test { _ = @import(…); }` reference blocks, which
# a filtered build keeps regardless of filter (five of them in the unit
# binary today; they are why N chunk totals sum to the unfiltered total
# plus 5*(N-1), before the duplicate noted above). A chunk whose filters
# matched nothing therefore fails instead of passing vacuously.
#
# The `thottam-tests` binary takes the same filters (build.zig hands both
# test steps the same list): it runs its full 88 in `tooling`, which lists
# the thottam files, and only its own unnamed block in every other chunk.
#
# Works for any target: pass `-Dtarget=riscv64-linux` (or nothing, for the
# host) after the chunk name. Exit status is `zig build test`'s, or 2 for a
# misuse this script detected itself.

set -u
set -o pipefail

PROCESS_FILES="tests_process tests_process_run tests_process_win"
CONCURRENCY_FILES="tests_fibers tests_reactor tests_reactor_parity tests_scheduler
                   tests_shared_channel tests_shared_channel_rendezvous tests_srfi18
                   tests_waitforfd"
IO_FILES="tests_io tests_port_io tests_random_port tests_srfi181
          tests_reader_incremental tests_filesystem primitives_io"
FUZZ_FILES="tests_fuzz fuzz_gen fuzz_gen_native fuzz_gen_portable"
GC_FILES="tests_gc_tracing tests_gc_runtime_stress tests_gc_root_boundary
          tests_deepcopy tests_robustness memory"
NATIVE_FILES="tests_native tests_native_dispatch tests_native_gate
              native_compiler llvm_emit"
TOOLING_FILES="cli cli_spec completions config check_lint tests_check doctor
               explain features fmt tests_fmt kaappi_paths lsp_diagnostic
               test_runner test_selection timings crash repl disassembler
               tests_diagnostics bytecode_file cache tests_bytecode_cache
               tests_vm_library_cache thottam thottam_fs thottam_proc
               thottam_semver thottam_state tests_thottam"
# Every explicitly listed file, for the `rest` derivation and the existence
# check. Extend this when adding a list.
LISTED_FILES="$PROCESS_FILES $CONCURRENCY_FILES $IO_FILES $FUZZ_FILES $GC_FILES $NATIVE_FILES $TOOLING_FILES"
CHUNK_NAMES="process|concurrency|io|fuzz|gc|native|tooling|rest"

usage() {
    echo "usage: $0 [--list] <$CHUNK_NAMES> [zig build args...]" >&2
    exit 2
}

list_only=0
if [ "${1:-}" = "--list" ]; then
    list_only=1
    shift
fi
chunk="${1:-}"
[ -n "$chunk" ] || usage
shift

# Resolve paths against the repo root so the script works from any cwd.
cd "$(dirname "$0")/.." || exit 2

# Every explicitly listed name must be a real test file, or the list has
# rotted and the chunk would quietly shrink.
for name in $LISTED_FILES; do
    if [ ! -f "src/$name.zig" ]; then
        echo "$0: '$name' names no src/$name.zig -- update the chunk lists" >&2
        exit 2
    fi
done

in_list() { # in_list <name> <list...>
    local needle="$1"; shift
    local n
    for n in "$@"; do [ "$n" = "$needle" ] && return 0; done
    return 1
}

case "$chunk" in
    process)     names="$PROCESS_FILES" ;;
    concurrency) names="$CONCURRENCY_FILES" ;;
    io)          names="$IO_FILES" ;;
    fuzz)        names="$FUZZ_FILES" ;;
    gc)          names="$GC_FILES" ;;
    native)      names="$NATIVE_FILES" ;;
    tooling)     names="$TOOLING_FILES" ;;
    rest)
        names=""
        for f in src/*.zig; do
            n="$(basename "$f" .zig)"
            # shellcheck disable=SC2086
            in_list "$n" $LISTED_FILES && continue
            grep -q '^test "' "$f" || continue
            names="$names $n"
        done
        ;;
    *) usage ;;
esac

filters=()
for n in $names; do filters+=("-Dtest-filter=$n.test."); done

if [ "$list_only" = 1 ]; then
    printf '%s\n' "${filters[@]}"
    exit 0
fi

# The floor a chunk must clear: the unnamed reference blocks are in every
# filtered binary, so a chunk that matched nothing still reports that many.
floor="$(grep -l '^test {' src/*.zig | wc -l | tr -d ' ')"

log="$(mktemp)"
trap 'rm -f "$log"' EXIT

echo "== unit-test chunk '$chunk': ${#filters[@]} filter(s), extra args: $*"
zig build test "${filters[@]}" "$@" --summary all 2>&1 | tee "$log"
status=${PIPESTATUS[0]}
[ "$status" = 0 ] || exit "$status"

# `--summary all` prints one line per test binary, e.g.
#   +- run test unit-tests 54 pass, 12 skip (66 total) 15s MaxRSS:1G
total="$(sed -n 's/.*run test unit-tests .*(\([0-9][0-9]*\) total).*/\1/p' "$log" | head -1)"
if [ -z "$total" ]; then
    echo "$0: could not find the unit-tests total in the build summary" >&2
    exit 2
fi
if [ "$total" -le "$floor" ]; then
    echo "$0: chunk '$chunk' ran only $total test(s), no more than the $floor unnamed reference block(s) -- its filters matched nothing" >&2
    exit 2
fi
echo "== unit-test chunk '$chunk': $total tests (floor $floor)"
