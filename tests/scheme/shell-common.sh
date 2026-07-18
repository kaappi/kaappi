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

# ensure_runtime_lib <repo-dir>: freshen the native runtime archive via
# `zig build lib` when a toolchain is present. Without one, accept an
# already-built archive (cross-compiled and copied to the box) so the
# `kaappi compile` + C-compiler part of the test still runs; skip-77
# only when neither exists.
ensure_runtime_lib() {
    if command -v zig > /dev/null 2>&1; then
        (cd "$1" && zig build lib > /dev/null 2>&1)
    elif [ ! -f "$1/zig-out/lib/$(rt_lib_name)" ]; then
        echo "SKIP: no zig toolchain and no prebuilt zig-out/lib/$(rt_lib_name)"
        exit 77
    fi
}
