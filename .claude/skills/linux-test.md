---
name: linux-test
description: Run Kaappi build and tests inside a Linux container using podman. Use when the user asks to test on Linux, verify cross-platform build, or check Linux compatibility.
---

# Linux Test

Build and test Kaappi inside a Linux aarch64 container using podman.

## Steps

1. Run the build and test command in a podman container:

```bash
podman run --rm --platform linux/arm64 \
  -v /Users/bmuthuka/kaappi/kaappi:/src:ro \
  docker.io/arm64v8/ubuntu:24.04 bash -c '
apt-get update -qq && apt-get install -y -qq curl xz-utils > /dev/null 2>&1
curl -sL https://ziglang.org/download/0.16.0/zig-aarch64-linux-0.16.0.tar.xz | tar xJ -C /opt
export PATH=/opt/zig-aarch64-linux-0.16.0:$PATH
cp -r /src /build && cd /build && rm -rf .zig-cache zig-out
echo "=== Build ==="
zig build 2>&1
BUILD_RC=$?
if [ $BUILD_RC -ne 0 ]; then echo "BUILD FAILED"; exit 1; fi
echo "BUILD: OK"
echo ""
echo "=== Unit Tests ==="
zig build test 2>&1
echo ""
echo "=== R7RS Tests ==="
./zig-out/bin/kaappi tests/scheme/r7rs/r7rs-tests.scm 2>&1 | tail -5
echo "DONE"
'
```

2. Report the results to the user — build status, test pass/fail/skip counts, and any errors.

## Notes

- The container uses aarch64 Linux (matches macOS ARM host via podman's Virtualization.framework)
- JIT execution tests are skipped on Linux (they need macOS MAP_JIT for RWX memory)
- The `/src` volume is mounted read-only — a writable copy is made inside the container
- Zig cache is cleared to avoid cross-platform cache conflicts
- The container is ephemeral (`--rm`) — no cleanup needed
- Typical runtime: 2-4 minutes (download Zig + build + test)
