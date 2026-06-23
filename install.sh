#!/bin/bash
# Kaappi Scheme installer
# Usage: curl -fsSL https://kaappi.github.io/install.sh | bash
#
# Installs the latest release binary to ~/.local/bin/kaappi (or INSTALL_DIR).

set -euo pipefail

REPO="kaappi/kaappi"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"

detect_platform() {
    local os arch
    os=$(uname -s)
    arch=$(uname -m)

    case "$os" in
        Darwin) os="macos" ;;
        Linux)  os="linux" ;;
        *)
            echo "error: unsupported OS: $os"
            echo "Kaappi supports macOS and Linux. See https://github.com/$REPO"
            exit 1
            ;;
    esac

    case "$arch" in
        arm64|aarch64) arch="aarch64" ;;
        x86_64)        arch="x86_64" ;;
        riscv64)       arch="riscv64" ;;
        *)
            echo "error: unsupported architecture: $arch"
            exit 1
            ;;
    esac

    echo "${arch}-${os}"
}

get_latest_tag() {
    curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
        | grep '"tag_name"' \
        | head -1 \
        | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/'
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
    trap 'rm -rf "$tmpdir"' EXIT

    curl -fsSL -o "$tmpdir/kaappi" "$base_url/$kaappi_artifact"
    curl -fsSL -o "$tmpdir/thottam" "$base_url/$thottam_artifact"
    curl -fsSL -o "$tmpdir/SHA256SUMS" "$base_url/SHA256SUMS"

    echo "Verifying checksums..."
    cd "$tmpdir"
    if command -v sha256sum >/dev/null 2>&1; then
        grep -E "$kaappi_artifact|$thottam_artifact" SHA256SUMS | sha256sum -c --quiet -
    elif command -v shasum >/dev/null 2>&1; then
        grep -E "$kaappi_artifact|$thottam_artifact" SHA256SUMS | shasum -a 256 -c --quiet -
    else
        echo "warning: neither sha256sum nor shasum found, skipping verification"
    fi

    echo "Installing to $INSTALL_DIR/..."
    mkdir -p "$INSTALL_DIR"
    mv "$tmpdir/kaappi" "$INSTALL_DIR/kaappi"
    mv "$tmpdir/thottam" "$INSTALL_DIR/thottam"
    chmod +x "$INSTALL_DIR/kaappi" "$INSTALL_DIR/thottam"

    echo
    echo "Installed kaappi $tag and thottam to $INSTALL_DIR/"

    if ! echo "$PATH" | tr ':' '\n' | grep -qx "$INSTALL_DIR"; then
        echo
        echo "Add $INSTALL_DIR to your PATH:"
        echo "  export PATH=\"$INSTALL_DIR:\$PATH\""
    fi
}

main
