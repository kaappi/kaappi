#!/bin/bash
# Kaappi Scheme installer
# Usage: curl -fsSL https://raw.githubusercontent.com/kaappi/kaappi/main/install.sh | bash
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

    local artifact="kaappi-${platform}"
    local url="https://github.com/$REPO/releases/download/${tag}/${artifact}"
    local checksums_url="https://github.com/$REPO/releases/download/${tag}/SHA256SUMS"

    echo "Downloading $artifact..."
    local tmpdir
    tmpdir=$(mktemp -d)
    trap 'rm -rf "$tmpdir"' EXIT

    curl -fsSL -o "$tmpdir/kaappi" "$url"
    curl -fsSL -o "$tmpdir/SHA256SUMS" "$checksums_url"

    echo "Verifying checksum..."
    cd "$tmpdir"
    if command -v sha256sum >/dev/null 2>&1; then
        grep "$artifact" SHA256SUMS | sha256sum -c --quiet -
    elif command -v shasum >/dev/null 2>&1; then
        grep "$artifact" SHA256SUMS | shasum -a 256 -c --quiet -
    else
        echo "warning: neither sha256sum nor shasum found, skipping verification"
    fi

    echo "Installing to $INSTALL_DIR/kaappi..."
    mkdir -p "$INSTALL_DIR"
    mv "$tmpdir/kaappi" "$INSTALL_DIR/kaappi"
    chmod +x "$INSTALL_DIR/kaappi"

    echo
    echo "Installed kaappi $tag to $INSTALL_DIR/kaappi"

    if ! echo "$PATH" | tr ':' '\n' | grep -qx "$INSTALL_DIR"; then
        echo
        echo "Add $INSTALL_DIR to your PATH:"
        echo "  export PATH=\"$INSTALL_DIR:\$PATH\""
    fi
}

main
