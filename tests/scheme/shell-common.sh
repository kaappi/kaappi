# Shared helpers for the shell-based test suites. Sourced, never executed:
#   . "$(dirname "$0")/../shell-common.sh"
#
# On Windows the suites run under Git Bash (MSYS) — see docs/dev/windows.md.
# A script whose premise cannot hold there calls skip_on_windows with a
# reason and exits 77, the conventional SKIP status (automake's) that
# run-all.sh and the Windows CI test drivers recognize. This is the
# shell analogue of the `cond-expand (windows ...)` gate the .scm tests use.

# is_windows: true under Git Bash / MSYS / Cygwin on Windows.
is_windows() {
    case "$(uname -s)" in
        MINGW* | MSYS* | CYGWIN*) return 0 ;;
        *) return 1 ;;
    esac
}

# skip_on_windows <reason>: exit 77 (SKIP) on Windows, no-op elsewhere.
skip_on_windows() {
    if is_windows; then
        echo "SKIP: $1"
        exit 77
    fi
}

# native_path <abs-path>: the spelling of an absolute path as the kaappi
# binary itself sees and prints it. Git Bash hands out MSYS paths
# (/tmp/...), while kaappi records and prints native C:/... paths; cygpath
# -m (mixed: drive letter + forward slashes) converts. Identity elsewhere.
native_path() {
    if is_windows && command -v cygpath > /dev/null 2>&1; then
        cygpath -m "$1"
    else
        printf '%s\n' "$1"
    fi
}

# rt_lib_name: the runtime archive's platform file name — must match
# platform.rt_lib_name in src/platform.zig.
rt_lib_name() {
    if is_windows; then echo "kaappi_rt.lib"; else echo "libkaappi_rt.a"; fi
}

# skip_without_zig <reason>: exit 77 (SKIP) when no Zig toolchain is on
# PATH. For scripts whose test itself rebuilds with zig (e.g. the
# -Dbundle standalone-binary tests). Boxes that run cross-compiled
# binaries with no toolchain installed — the FreeBSD reference machine
# (docs/dev/freebsd.md) — skip these instead of dying at `zig: not
# found`.
skip_without_zig() {
    if ! command -v zig > /dev/null 2>&1; then
        echo "SKIP: $1"
        exit 77
    fi
}

# skip_on_debug_build <kaappi-binary> <reason>: exit 77 (SKIP) when the given
# binary reports build_mode "Debug" in `kaappi features --json`. For tests
# whose regression coverage needs a large iteration/allocation count to be
# meaningful (e.g. a native-compile stack-growth stress loop): a Debug
# build's un-optimized, leak-tracking allocator makes that scale of work
# impractically slow (10-20x, kaappi#1748) without adding any coverage a
# ReleaseSafe/ReleaseFast/other-platform CI leg doesn't already provide at
# full rigor, so skip rather than shrink (which risks silently dropping
# below the iteration count actually needed to reproduce the regression) or
# race a timeout.
skip_on_debug_build() {
    local kaappi="$1" reason="$2"
    if "$kaappi" features --json 2>/dev/null | grep -q '"build_mode":"Debug"'; then
        echo "SKIP: $reason"
        exit 77
    fi
}

# --- build serialisation -------------------------------------------------
#
# Several scripts shell out to `zig build …`, which installs into the repo's
# single zig-out/. run-all.sh runs the shell suites concurrently (kaappi#1926),
# so two of them can reach that install at the same time and one can observe a
# half-written artefact. `zig build` locks its own cache, but the install copy
# happens outside that lock, so the suites take a lock of their own.
#
# mkdir is the portable atomic test-and-set — it fails when the directory
# already exists, on POSIX and under Git Bash alike. flock is Linux-only and
# absent from macOS entirely.
#
# The lock lives under .zig-cache/, which is gitignored: a lock file inside the
# tracked tree would make the worktree dirty, and a dirty tree changes the
# build id baked into every .sbc (docs/dev/cache.md).

build_lock_dir() {
    printf '%s/.zig-cache/kaappi-test-%s.lock\n' "$1" "$2"
}

# build_lock <repo-dir> <name>: block until the named lock is ours.
build_lock() {
    local lock waited holder
    lock=$(build_lock_dir "$1" "$2")
    mkdir -p "$1/.zig-cache" 2> /dev/null || true
    waited=0
    while ! mkdir "$lock" 2> /dev/null; do
        # Steal a lock whose holder is gone. run-all.sh kills a script that
        # overruns SHELL_TIMEOUT, and a dead holder's lock would otherwise
        # stall every later script for the rest of the run.
        holder=$(cat "$lock/pid" 2> /dev/null || true)
        if [ -n "$holder" ] && ! kill -0 "$holder" 2> /dev/null; then
            rm -rf "$lock"
            continue
        fi
        sleep 1
        waited=$((waited + 1))
        # Last resort, for a holder that is alive but wedged: 15 minutes is
        # well past the slowest thing anyone holds this for (a full
        # interpreter rebuild, ~3 minutes on a 4-core runner).
        if [ "$waited" -ge 900 ]; then
            echo "warning: stealing $lock after ${waited}s" >&2
            rm -rf "$lock"
        fi
    done
    echo $$ > "$lock/pid"
}

# build_unlock <repo-dir> <name>: release it.
build_unlock() {
    rm -rf "$(build_lock_dir "$1" "$2")"
}

# ensure_runtime_lib <repo-dir>: freshen the native runtime archive via
# `zig build lib` when a toolchain is present. Without one, accept an
# already-built archive (cross-compiled and copied to the box) so the
# `kaappi compile` + C-compiler part of the test still runs; skip-77
# only when neither exists.
ensure_runtime_lib() {
    local lib rt_status
    lib="$1/zig-out/lib/$(rt_lib_name)"

    # run-all.sh builds the archive once, up front, and exports the marker:
    # every call here is then a no-op instead of 18 redundant builds racing
    # each other's install. The marker is an optimisation, never a
    # requirement — a script run standalone (the Windows CI legs invoke each
    # one directly) sees no marker and takes the path below, as before.
    if [ -n "${KAAPPI_RT_LIB_READY:-}" ] && [ -f "$lib" ]; then
        return 0
    fi

    if command -v zig > /dev/null 2>&1; then
        build_lock "$1" rt-lib
        rt_status=0
        (cd "$1" && zig build lib > /dev/null 2>&1) || rt_status=$?
        build_unlock "$1" rt-lib
        return "$rt_status"
    elif [ ! -f "$lib" ]; then
        echo "SKIP: no zig toolchain and no prebuilt zig-out/lib/$(rt_lib_name)"
        exit 77
    fi
}

# bundle_fixture_binary <repo-dir> <kaappi> <dest>: build the standalone binary
# that embeds tests/scheme/compile/fixtures/bundle-replay, and copy it to
# <dest>. Callers must have passed skip_without_zig first.
#
# `zig build -Dbundle=…` recompiles the whole interpreter — the embedded
# bytecode is part of the compiled module graph — which is ~180s on a 4-core
# runner. Two regression tests need such a binary (kaappi#700 and kaappi#703),
# and paying for it twice was 85% of the shell suites' entire wall time
# (kaappi#1926). They share one fixture program instead, so the second caller's
# build is a ~0.2s hit in Zig's own content-addressed cache.
#
# Regenerating the .sbc on every call is what keeps that honest: it is
# deterministic, so unchanged sources give byte-identical bytes and a cache
# hit, while an edit under src/ changes them and forces exactly the rebuild it
# must. A cached .sbc of our own would instead go stale against the rebuilt
# binary's build id and fail with `invalid embedded bytecode` (docs/dev/cache.md).
#
# The binary is copied to the caller's own <dest> before it is ever run: the
# shared install path is written by whichever script holds the lock, and
# exec'ing a path another script may be reinstalling is exactly the race that
# kaappi#1748 fixed.
bundle_fixture_binary() {
    # `rc`, not `status`: this file is sourced, and `status` is read-only in
    # some shells.
    local repo="$1" kaappi="$2" dest="$3" fixture out sbc kaappi_abs log rc
    fixture="$repo/tests/scheme/compile/fixtures/bundle-replay"
    out="$repo/.zig-cache/kaappi-test-fixtures"
    sbc="$out/bundle-replay.sbc"
    kaappi_abs="$(cd "$(dirname "$kaappi")" && pwd)/$(basename "$kaappi")"
    log=$(mktemp)

    build_lock "$repo" bundle-fixture
    rc=0
    (
        mkdir -p "$out"
        # Compile from inside the fixture directory so the paths recorded in
        # the .sbc are relative, and its bytes therefore identical run to run.
        cd "$fixture" &&
            "$kaappi_abs" --lib-path lib --compile -o "$sbc" main.scm &&
            [ -f "$sbc" ] &&
            cd "$repo" &&
            zig build -Dbundle="$sbc" -Doptimize=ReleaseSafe \
                --prefix "$out/prefix" &&
            cp "$out/prefix/bin/kaappi" "$dest"
    ) > "$log" 2>&1 || rc=$?
    build_unlock "$repo" bundle-fixture

    if [ "$rc" -ne 0 ]; then
        echo "FAIL: could not build the bundled fixture binary" >&2
        cat "$log" >&2
    fi
    rm -f "$log"
    return "$rc"
}
