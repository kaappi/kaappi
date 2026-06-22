# Security Policy

## Supported versions

Only the latest release on `main` is supported with security fixes. There are
no long-term-support branches at this time.

## Reporting a vulnerability

**Do not open a public issue for security vulnerabilities.**

Use [GitHub's private security advisory feature](https://github.com/kaappi/kaappi/security/advisories/new)
to report vulnerabilities. You will receive an acknowledgment within 72 hours
and a substantive response within 14 days.

If you cannot use GitHub advisories, email the maintainer directly (see the
commit log for contact information).

## Security model

### What Kaappi defends against

- **`--sandbox` mode** is designed to contain untrusted Scheme code. It blocks
  FFI (`ffi-open`, `ffi-fn`, `ffi-callback`), file I/O, `eval`, `load`, and
  environment variable access. The goal is that a sandboxed program cannot
  affect the host beyond CPU and memory consumption.

- **Malformed input** (Scheme source, `.sbc` bytecode) should produce a clean
  error or rejection, never a host-process crash. Work toward this goal is
  tracked in [docs/prod/01](docs/prod/01-input-robustness.md).

### What is outside the trust boundary

- **FFI is full trust.** `ffi-open` loads and executes arbitrary native code.
  Any library loaded via FFI has the same privileges as the host process. This
  is by design — FFI exists to call C libraries. The sandbox disables FFI
  entirely.

- **Native libraries installed by `thottam`** (the package manager) land in
  `~/.kaappi/lib/` and are auto-discovered by `ffi-open`. Installing a package
  is equivalent to trusting its native code.

- **`.sbc` bytecode files** are a trusted input format (compiled output from
  the Kaappi compiler). A malicious `.sbc` could in principle cause undefined
  behavior. Do not load `.sbc` files from untrusted sources.

### Known limitations

- **OS threads (SRFI-18):** Cross-thread GC is experimental. See the
  [Known limitations](README.md#known-limitations) section in the README.

- **JIT W^X:** The JIT compiler allocates executable memory. On macOS it uses
  `pthread_jit_write_protect_np` for proper W^X enforcement. The Linux path
  uses `mmap` with appropriate protection flags.
