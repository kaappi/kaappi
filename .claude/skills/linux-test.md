---
name: linux-test
description: Run Kaappi build and tests on Linux using podman. Tests both aarch64 (native build + unit tests + R7RS) and x86_64 (cross-compile + JIT tests). Use when the user asks to test on Linux, verify cross-platform build, or check Linux compatibility.
---

# Linux Test

Build and test Kaappi on Linux using podman with the pre-built `kaappi-builder` image.

## Steps

### 1. Ensure builder images exist

If not already built, build them:

```bash
podman image exists kaappi-builder || podman build --platform linux/arm64 -t kaappi-builder /Users/bmuthuka/kaappi/ci-images/builder/
podman image exists kaappi-builder-amd64 || podman build --platform linux/amd64 -t kaappi-builder-amd64 /Users/bmuthuka/kaappi/ci-images/builder/
```

### 2. Test on aarch64 Linux (build + unit tests + R7RS)

```bash
podman run --rm -v /Users/bmuthuka/kaappi/kaappi:/src:ro kaappi-builder \
  bash -c '
mkdir -p /workspace && cp -r /src/* /workspace/ && cd /workspace && rm -rf .zig-cache zig-out
echo "=== Build ==="
zig build 2>&1 && echo "BUILD: OK" || { echo "BUILD: FAIL"; exit 1; }
echo ""
echo "=== Unit Tests ==="
zig build test 2>&1 | tail -5
echo ""
echo "=== R7RS Tests ==="
./zig-out/bin/kaappi tests/scheme/r7rs/r7rs-tests.scm 2>&1 | tail -5
echo "DONE"
'
```

### 3. Test on x86_64 Linux (cross-compile + run JIT tests)

Cross-compile from macOS, then run the binary in the x86_64 container:

```bash
zig build test -Dtarget=x86_64-linux 2>&1 || true
x86_bin=$(find .zig-cache -name "unit-tests" -type f -exec sh -c 'file "{}" | grep -q "x86-64" && echo "{}"' \; | head -1)
cp "$x86_bin" /Users/bmuthuka/kaappi/unit-tests-x86
podman run --rm --platform linux/amd64 -v /Users/bmuthuka/kaappi/unit-tests-x86:/unit-tests:Z kaappi-builder-amd64 \
  bash -c 'chmod +x /unit-tests && /unit-tests 2>&1 | grep -E "passed|failed|skipped"'
```

### 4. Report the results

Report: build status, test pass/fail/skip counts for both architectures, and any errors.

## Notes

- **aarch64**: builds and runs natively via podman's Virtualization.framework. JIT execution tests are skipped (RWX memory doesn't work under VM emulation). ~2 minutes.
- **x86_64**: cross-compiled from macOS ARM, binary runs in x86_64 container via Rosetta. All JIT execution tests run and pass. ~1 minute.
- Builder images have Zig 0.16, GCC, OpenSSL, libpq, redis-tools pre-installed.
- `/src` is mounted read-only — a writable copy is made inside the container.
