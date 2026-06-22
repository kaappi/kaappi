# Versioning & Stability Policy

Kaappi follows [Semantic Versioning](https://semver.org/).

## During `0.x`

- The Scheme-facing API (R7RS procedures, library system, SRFI support) is
  stable and will not break without a minor version bump.
- The CLI interface (`kaappi [flags] [file]`) is stable.
- The bytecode format (`.sbc`) may change between minor versions. A version
  mismatch is detected and produces a clean error — stale `.sbc` files are
  simply recompiled from source.
- Build-time options (`-Dmax-frames`, `-Dmax-registers`, `-Dgc-threshold`)
  may be added or adjusted.
- Internal APIs (embedding the VM as a library) are unstable and may change
  without notice.

## Criteria for 1.0

All of the following must be met before tagging `1.0.0`:

1. **Input robustness** — the reader, compiler, and `.sbc` loader handle all
   malformed input gracefully (no panics on any input path).
2. **Concurrency safety** — either cross-thread GC is implemented correctly
   (stop-the-world or per-thread heaps), or OS threads remain gated and
   clearly documented as experimental.
3. **Security** — the `--sandbox` boundary is proven via an escape test suite;
   JIT memory is W^X on all platforms; the threat model is documented.
4. **CI** — formatting, leak detection, multi-mode testing, and the
   conformance suite gate every PR.
5. **No known memory-safety issues** in the interpreter core.

## Release process

1. Update `CHANGELOG.md`: move the `[Unreleased]` section to a new version
   heading.
2. Update `pub const version` in `src/main.zig`.
3. Commit, tag (`git tag v0.2.0`), and push (`git push --tags`).
4. The release workflow builds cross-compiled binaries and creates a GitHub
   Release with checksums.
