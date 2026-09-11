<p align="center">
  <img src="https://kaappi-lang.org/assets/logo.svg" alt="Kaappi" width="200">
</p>

<h1 align="center">Kaappi</h1>

<p align="center">
  A complete <strong>R7RS-small</strong> Scheme implementation, written in <strong>Zig</strong>.
</p>

<p align="center">
  <a href="https://github.com/kaappi/kaappi/actions/workflows/ci.yml"><img src="https://github.com/kaappi/kaappi/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/kaappi/kaappi/releases/latest"><img src="https://img.shields.io/github/v/release/kaappi/kaappi" alt="Latest release"></a>
  <a href="https://codecov.io/gh/kaappi/kaappi"><img src="https://codecov.io/gh/kaappi/kaappi/branch/main/graph/badge.svg" alt="Coverage"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT license"></a>
  <a href="https://www.buymeacoffee.com/baiju"><img src="https://img.shields.io/badge/buy%20me%20a%20coffee-support-ffdd00?logo=buy-me-a-coffee&logoColor=black" alt="Buy Me A Coffee"></a>
</p>

<p align="center">
  <a href="https://kaappi-lang.org/">Website</a> ·
  <a href="https://kaappi-lang.org/playground/">Playground</a> ·
  <a href="https://kaappi-lang.org/tour/">Tour</a> ·
  <a href="https://kaappi-lang.org/guide/">Guide</a> ·
  <a href="https://kaappi-lang.org/download/">Download</a>
</p>

---

Kaappi implements every identifier from [R7RS Appendix A](https://small.r7rs.org/)
— 719 built-in procedures, 32 syntax forms, and all 16 standard libraries — plus
181 SRFIs, a C FFI, OS threads and fibers, an LLVM native-code backend, a package
manager, and a stepping debugger. The runtime is a register-based bytecode VM
with generational garbage collection and stack-copying first-class continuations.

The name is Malayalam and Tamil for *coffee* — see the
[FAQ](https://kaappi-lang.org/faq/) for the story.

> **Note:** Kaappi was built with the assistance of AI/LLM.

## Try it

No install needed — run Scheme in your browser at the
[**playground**](https://kaappi-lang.org/playground/), or take the guided
12-lesson [**tour**](https://kaappi-lang.org/tour/).

## Installation

### Install script (macOS, Linux, FreeBSD, OpenBSD, NetBSD)

```bash
curl -fsSL https://kaappi-lang.org/install.sh | bash
```

This installs `kaappi` and `thottam` (the package manager) to `~/.local/bin/`
and the standard libraries to `~/.kaappi/lib/`, verifying SHA256 checksums
along the way.

Prebuilt, signed binaries for every platform are on the
[releases page](https://github.com/kaappi/kaappi/releases/latest); the
[download page](https://kaappi-lang.org/download/) covers manual installation
and checksum and signature verification.

### Build from source

Requires **Zig 0.16+** and a C toolchain (for the vendored isocline library):

```bash
git clone https://github.com/kaappi/kaappi.git
cd kaappi
zig build                            # → zig-out/bin/kaappi
zig build run                        # launch the REPL
zig build run -- program.scm         # run a Scheme file
zig build test                       # run the unit tests
```

### Supported platforms

CI builds every target below and runs the unit tests on all of them except
WebAssembly; each non-macOS target cross-compiles from a single host with
`zig build -Dtarget=<arch>-<os>`. The table records only what varies:

| OS | Architecture | Native compilation |
|----|-------------|--------------------|
| macOS | aarch64 (Apple Silicon) | LLVM backend |
| Linux | x86_64, aarch64 | LLVM backend |
| Linux | riscv64, s390x, ppc64le | interpreter only |
| Windows | aarch64, x86_64 | LLVM backend (needs a C toolchain) |
| FreeBSD | x86_64, aarch64 | LLVM backend (base `cc` suffices) |
| OpenBSD | x86_64, aarch64 | LLVM backend (base `cc` suffices) |
| NetBSD | x86_64, aarch64 | LLVM backend (needs pkgsrc `clang`) |
| WebAssembly | wasm32-wasi | interpreter only |

The WASM build (`zig build wasm`) runs in browsers and WASI runtimes — it
powers the [playground](https://kaappi-lang.org/playground/). What each port
touches, and its deliberate degradations, is in the per-platform docs:
[Windows](docs/dev/windows.md), [FreeBSD](docs/dev/freebsd.md),
[OpenBSD](docs/dev/openbsd.md), [NetBSD](docs/dev/netbsd.md).

## A taste of Kaappi

```console
$ kaappi
kaappi> (define (fib n)
  ...     (if (< n 2) n
  ...         (+ (fib (- n 1)) (fib (- n 2)))))
kaappi> (fib 20)
6765
kaappi> (map (lambda (x) (* x x)) '(1 2 3 4 5))
(1 4 9 16 25)
kaappi> `(the answer is ,(* 6 7))
(the answer is 42)
kaappi> (string-length "héllo")
5
kaappi> (char-alphabetic? #\λ)
#t
```

The REPL has syntax highlighting, multi-line editing with paren balancing,
persistent history, and tab completion for built-in and user-defined symbols.

## Features

### Complete R7RS-small

- **Proper tail calls** — `(define (loop n) (loop (+ n 1)))` runs forever without growing the stack
- **First-class continuations** — multi-shot `call/cc` via stack copying, `dynamic-wind` for cleanup
- **Exception handling** — `guard`, `raise`, `with-exception-handler`, typed error objects (`file-error?`, `read-error?`)
- **Hygienic macros** — `syntax-rules` with scope-based renaming; pattern variables, ellipsis, literals, underscore wildcards
- **Library system** — `define-library`, `import` with `only`/`except`/`rename`/`prefix`, `.sld` file loading, `cond-expand`
- **Numeric tower** — fixnum, bignum (arbitrary precision), exact rational, flonum (IEEE 754 f64), complex; automatic promotion on overflow
- **Full Unicode** — UTF-8 strings indexed by codepoint, Unicode character classification and case mapping
- **Records, ports, lazy evaluation, multiple values, parameters** — the whole standard, with no known functional gaps

### Beyond the standard

- **181 SRFIs** — 12 built-in, 165 as portable `.sld` libraries, plus SRFI 261 library names and the sub-library-only SRFIs 160, 211 and 226 (full list in [CONFORMANCE.md](CONFORMANCE.md))
- **Native binaries** — `kaappi compile program.scm -o program` compiles Scheme to a native executable via LLVM, tuned to the portable baseline CPU so it runs on other machines of the same architecture ([details](docs/dev/llvm-backend.md))
- **Standalone bundles** — `zig build -Dbundle-src=program.scm` embeds bytecode and libraries in a single executable
- **C FFI** — call shared libraries from Scheme via `(kaappi ffi)`; 18 marshalled types, callbacks for passing Scheme procedures to C
- **Concurrency** — green threads with channels via `(kaappi fibers)`, plus real OS threads via SRFI-18
- **Stepping debugger** — breakpoints (with conditions), watch expressions, step/next/step-out, frame navigation, locals — all from the REPL
- **Profiler** — `kaappi --profile` or `,profile expr`: per-function self/total time, call counts, allocation bytes
- **Sandbox mode** — `kaappi --sandbox` blocks FFI, file I/O, `eval`, `load`, and environment access
- **Bytecode caching** — compiled `.sbc` files are reused when the source is unchanged
- **Machine-legible diagnostics** — every error carries a stable `KP` code (`error[KP3001]`), with `--diagnostics=json` and `kaappi explain <code>` ([details](docs/dev/diagnostics.md))
- **Capability discovery** — `kaappi features [--json]` reports this build's version, target, subsystems, SRFIs, and limits ([details](docs/dev/features.md))
- **Editor support** — a bundled LSP server (`kaappi-lsp`) and a [VS Code extension](https://github.com/kaappi/vscode-kaappi)

## Ecosystem

Kaappi ships **thottam**, a package manager for its growing library ecosystem:

```bash
# Install the web framework (auto-installs kaappi-http, kaappi-json, kaappi-net)
thottam install kaappi-web

# Now it just works — no --lib-path flags needed
kaappi app.scm
```

| Package | Description |
|---------|-------------|
| [kaappi-net](https://github.com/kaappi/kaappi-net) | TCP/TLS networking |
| [kaappi-http](https://github.com/kaappi/kaappi-http) | HTTP/HTTPS client + server (pre-fork, threaded) |
| [kaappi-web](https://github.com/kaappi/kaappi-web) | Web framework — routing, middleware, JSON helpers |
| [kaappi-json](https://github.com/kaappi/kaappi-json) | JSON parser and serializer |
| [kaappi-pg](https://github.com/kaappi/kaappi-pg) | PostgreSQL client with cursors and type conversion |
| [kaappi-redis](https://github.com/kaappi/kaappi-redis) | Redis client — lists, hashes, pub/sub, pipelining |
| [kaappi-examples](https://github.com/kaappi/kaappi-examples) | REST API, task queue, CRUD app, file server |

More libraries (CSV, TOML, YAML, logging, templates, testing, crypto, SQLite,
email, CLI parsing) are listed in the
[ecosystem docs](https://kaappi-lang.org/ecosystem/).

### A REST API in a few lines

```scheme
(import (kaappi web) (kaappi pg) (kaappi json))

(define db (pg-connect "dbname=myapp"))

(define app
  (routes
    (GET "/users/:id"
      (lambda (req params)
        (let ((rows (pg-query db "SELECT * FROM users WHERE id = $1"
                      (param/number params "id"))))
          (json-response (if (null? rows) '(("error" . "not found"))
                             (car rows))))))
    (POST "/users"
      (lambda (req params)
        (let ((body (request-json req)))
          (pg-exec db "INSERT INTO users (name) VALUES ($1)"
            (cdr (assoc "name" body)))
          (json-response '(("created" . #t)) 201))))))

(serve (wrap app wrap-json-body wrap-logging wrap-errors) 8080)
```

## Concurrency

Green threads (fibers) for cooperative multitasking within one OS thread:

```scheme
(import (kaappi fibers))

(define ch (make-channel))

(spawn (lambda ()
  (channel-send ch "hello from fiber")))

(display (channel-receive ch))  ;=> hello from fiber
```

Scheduling is cooperative: fibers run when the main program blocks or calls
`(yield)`, and a receive that no fiber can ever satisfy raises a catchable
deadlock error instead of hanging.

Real OS threads via SRFI-18 — each thread gets its own VM and GC, enabling
true parallel I/O (e.g., thread-per-connection servers):

```scheme
(import (srfi 18))

(define t (thread-start!
  (make-thread
    (lambda ()
      (display "running on OS thread")
      (newline)))))

(thread-join! t)
```

See the [concurrency guide](https://kaappi-lang.org/guide/concurrency/) for
channels across threads, worker pools, and `parallel-map`.

## Architecture

```text
Source → Reader → Expander → IR → Bytecode emission → VM
         (UTF-8    (syntax-   (analysis +   (register-    (generational GC,
          lexer)    rules)     optimization   based)        stack-copied
                               passes)                      continuations)
```

Values are NaN-boxed 64-bit words, so flonums, fixnums, booleans, characters,
and nil need no heap allocation. The component map, value representation,
GC design, and file layout are in
[docs/dev/architecture.md](docs/dev/architecture.md).

## Testing

```bash
zig build test                     # Zig unit tests
bash tests/scheme/run-all.sh       # all Scheme-level suites
```

The Scheme suites include the 1,395-test R7RS conformance suite. CI runs on
every platform in the support matrix, and per-commit performance trends are
tracked on the [benchmark dashboard](https://kaappi-lang.org/kaappi/dev/bench/).
The [testing guide](docs/dev/testing.md) describes the full layout.

## Documentation

| Document | Description |
|----------|-------------|
| [User Guide](https://kaappi-lang.org/guide/) | Installation, REPL, language tutorial, CLI reference |
| [Procedure Reference](https://kaappi-lang.org/procedures/) | Every built-in procedure, organized by domain |
| [Cookbook](https://kaappi-lang.org/cookbook/) | Task-oriented recipes: REST APIs, JSON, CSV, SQLite, testing |
| [Ecosystem](https://kaappi-lang.org/ecosystem/) | thottam and all kaappi-* libraries |
| [R7RS Conformance](CONFORMANCE.md) | Design choices and per-SRFI coverage details |
| [Developer Docs](docs/dev/README.md) | Architecture, extension guides, testing, design decisions, postmortems |

## Known limitations

- **Continuations** — `call/cc` copies the VM stack, so a capture costs
  O(stack depth). A continuation captured inside the callback of a *native
  driver* (a higher-order primitive implemented in Zig) cannot be resumed
  once that call returns; `apply`, `call-with-values`, `map`, `for-each`,
  SRFI-1 `fold`/`filter`/`any`/`every` and others are exempt, most remaining
  SRFI-1 drivers are not. SRFI 248's delimited continuations are single-shot.
- **Exceptions** — a `with-exception-handler` or `guard` handler runs after
  the stack has unwound to the installing form, not in the dynamic environment
  of the `raise`. `raise-continuable` is unaffected.
- **Fibers** — a fiber cannot park inside a native-driver callback; block in
  plain loops or the bytecode-driven procedures instead.
- **OS threads** — values cross by deep copy, except top-level bindings, which
  are shared by pointer. Share mutexes and condition variables through a
  global; pass channels by lexical capture.
- **Script output** — `kaappi program.scm` echoes every non-void top-level
  value to stdout, as the REPL does.
- **Macros** — `syntax-rules` only; `syntax-case` is not implemented.

The full list, with the exact procedures each restriction affects, is in
[docs/dev/known-limitations.md](docs/dev/known-limitations.md).

## Contributing

Contributions are welcome — bug reports, SRFI implementations, documentation,
and ecosystem libraries alike.

**New here?** Start with
[GitHub Discussions](https://github.com/orgs/kaappi/discussions) — ask
questions, propose ideas, show what you built. Issues and pull requests are
open to everyone.

- [CONTRIBUTING.md](CONTRIBUTING.md) — how to get involved, build, test, and submit changes
- [Community](https://kaappi-lang.org/community/) — all the ways to participate
- [Code of Conduct](CODE_OF_CONDUCT.md)

## Support This Project

If you find Kaappi useful, consider supporting its development:

<p align="center">
  <a href="https://www.buymeacoffee.com/baiju">
    <img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" height="50">
  </a>
</p>

## License

[MIT](LICENSE)
