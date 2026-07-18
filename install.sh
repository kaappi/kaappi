#!/bin/bash
# Kaappi Scheme installer
# Usage: curl -fsSL https://kaappi.github.io/install.sh | bash
#
# Installs the latest release binary to ~/.local/bin/kaappi (or INSTALL_DIR).

set -euo pipefail

REPO="kaappi/kaappi"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"

# Download URL ($1) to file ($2). Prefers curl (macOS/Linux), then wget, then
# the BSD base tools: fetch (FreeBSD) and ftp (OpenBSD, NetBSD) all fetch
# HTTPS from the base system, where curl is not installed.
download() {
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$2" "$1"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$2" "$1"
    elif command -v fetch >/dev/null 2>&1; then
        fetch -qo "$2" "$1"
    elif command -v ftp >/dev/null 2>&1; then
        ftp -o "$2" "$1"
    else
        echo "error: need curl, wget, fetch, or ftp to download files" >&2
        return 1
    fi
}

detect_platform() {
    local os arch
    os=$(uname -s)
    arch=$(uname -m)

    case "$os" in
        Darwin)  os="macos" ;;
        Linux)   os="linux" ;;
        FreeBSD) os="freebsd" ;;
        OpenBSD) os="openbsd" ;;
        NetBSD)
            os="netbsd"
            # NetBSD's uname -m reports the kernel port (evbarm, amd64),
            # not the CPU; -p gives the machine arch (aarch64, x86_64).
            arch=$(uname -p)
            ;;
        *)
            echo "error: unsupported OS: $os"
            echo "Kaappi supports macOS, Linux, FreeBSD, OpenBSD, and NetBSD. See https://github.com/$REPO"
            exit 1
            ;;
    esac

    case "$arch" in
        arm64|aarch64) arch="aarch64" ;;
        # FreeBSD and OpenBSD report x86_64 as amd64 (uname -m).
        x86_64|amd64)  arch="x86_64" ;;
        riscv64)       arch="riscv64" ;;
        *)
            echo "error: unsupported architecture: $arch"
            exit 1
            ;;
    esac

    echo "${arch}-${os}"
}

get_latest_tag() {
    local tmp
    tmp=$(mktemp)
    download "https://api.github.com/repos/$REPO/releases/latest" "$tmp" || { rm -f "$tmp"; return 1; }
    grep '"tag_name"' "$tmp" | head -1 | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/'
    rm -f "$tmp"
}

main() {
    echo "Kaappi Scheme installer"
    echo

    local platform
    platform=$(detect_platform)
    echo "Platform: $platform"

    echo "Fetching latest release..."
    local tag
    tag=$(get_latest_tag)
    if [ -z "$tag" ]; then
        echo "error: could not determine latest release"
        echo "Check https://github.com/$REPO/releases"
        exit 1
    fi
    echo "Version: $tag"

    local kaappi_artifact="kaappi-${platform}"
    local thottam_artifact="thottam-${platform}"
    local base_url="https://github.com/$REPO/releases/download/${tag}"

    echo "Downloading binaries..."
    local tmpdir
    tmpdir=$(mktemp -d)
    trap "rm -rf '$tmpdir'" EXIT

    download "$base_url/$kaappi_artifact" "$tmpdir/kaappi"
    download "$base_url/$thottam_artifact" "$tmpdir/thottam"
    download "$base_url/kaappi-lib.tar.gz" "$tmpdir/kaappi-lib.tar.gz"
    download "$base_url/SHA256SUMS" "$tmpdir/SHA256SUMS"

    echo "Verifying checksums..."
    cd "$tmpdir"
    # SHA256SUMS references artifact names; remap to local filenames for verification
    grep "$kaappi_artifact" SHA256SUMS | sed "s|$kaappi_artifact|kaappi|" > check.txt
    grep "$thottam_artifact" SHA256SUMS | sed "s|$thottam_artifact|thottam|" >> check.txt
    grep "kaappi-lib.tar.gz" SHA256SUMS >> check.txt
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum -c --quiet check.txt
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 -c --quiet check.txt
    elif command -v sha256 >/dev/null 2>&1; then
        # OpenBSD/FreeBSD/NetBSD base: sha256 has no coreutils-style -c, so
        # recompute each file's hash and confirm it appears in SHA256SUMS.
        for f in kaappi thottam kaappi-lib.tar.gz; do
            grep -q "$(sha256 -q "$f")" SHA256SUMS \
                || { echo "error: checksum verification failed for $f" >&2; exit 1; }
        done
    else
        echo "error: no checksum tool (sha256sum, shasum, or sha256) found;" >&2
        echo "refusing to install unverified binaries" >&2
        exit 1
    fi

    echo "Installing to $INSTALL_DIR/..."
    mkdir -p "$INSTALL_DIR"
    mv "$tmpdir/kaappi" "$INSTALL_DIR/kaappi"
    mv "$tmpdir/thottam" "$INSTALL_DIR/thottam"
    chmod +x "$INSTALL_DIR/kaappi" "$INSTALL_DIR/thottam"

    echo "Installing standard libraries to ~/.kaappi/lib/..."
    mkdir -p "$HOME/.kaappi/lib" "$tmpdir/libextract"
    tar xzf "$tmpdir/kaappi-lib.tar.gz" -C "$tmpdir/libextract"
    cp -r "$tmpdir/libextract/lib/"* "$HOME/.kaappi/lib/"
    cp "$tmpdir/libextract/LICENSE" "$HOME/.kaappi/lib/"

    echo
    echo "Installed kaappi $tag to $INSTALL_DIR/"
    echo "Standard libraries installed to ~/.kaappi/lib/"

    if ! echo "$PATH" | tr ':' '\n' | grep -qx "$INSTALL_DIR"; then
        echo
        echo "Add $INSTALL_DIR to your PATH:"
        echo "  export PATH=\"$INSTALL_DIR:\$PATH\""
    fi
}

main
