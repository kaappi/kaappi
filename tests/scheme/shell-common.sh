# Shared helpers for the shell-based test suites. Sourced, never executed:
#   . "$(dirname "$0")/../shell-common.sh"
#
# On Windows the suites run under Git Bash (MSYS) — see docs/dev/windows.md.
# A script whose premise cannot hold there calls skip_on_windows with a
# reason and exits 77, the conventional SKIP status (automake's) that
# run-all.sh and the windows-arm-test CI driver both recognize. This is the
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
