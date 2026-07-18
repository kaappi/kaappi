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
— 614 built-in procedures, 32 syntax forms, and all 14 standard libraries — plus
73 SRFIs, a C FFI, OS threads and fibers, an LLVM native-code backend, a package
manager, and a stepping debugger. The runtime is a register-based bytecode VM
with generational garbage collection and stack-copying first-class continuations.

The name is Malayalam and Tamil for *coffee* — see the
[FAQ](https://kaappi-lang.org/faq/) for the story.

> **Note:** Kaappi was built with the assistance of AI (Claude by Anthropic).

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
along the way. On the BSDs the script works from the base system alone —
when neither `curl` nor `wget` is installed it falls back to the base
`fetch` (FreeBSD) or `ftp` (OpenBSD, NetBSD) for downloads and `sha256`
for verification.

Prebuilt binaries for every platform are on the
[releases page](https://github.com/kaappi/kaappi/releases/latest). macOS
binaries are Developer ID signed and notarized; all releases ship
`SHA256SUMS` with a GPG signature (`SHA256SUMS.asc`, key at
[keybase.io/baijum](https://keybase.io/baijum)). See the
[download page](https://kaappi-lang.org/download/) for manual install and
verification steps.

### Build from source

Requires **Zig 0.16+** and a C toolchain (for the vendored linenoise library):

```bash
git clone https://github.com/kaappi/kaappi.git
cd kaappi
zig build                            # → zig-out/bin/kaappi
zig build run                        # launch the REPL
zig build run -- program.scm         # run a Scheme file
zig build test                       # run the unit tests
```

### Supported platforms

| OS | Architecture | Build | Tests | Native compilation |
|----|-------------|-------|-------|--------------------|
| macOS | aarch64 (Apple Silicon) | yes | yes | LLVM backend |
| Linux | x86_64 | yes | yes | LLVM backend |
| Linux | aarch64 | yes | yes | LLVM backend |
| Linux | riscv64 | yes | yes | LLVM backend |
| Windows | aarch64 (ARM64) | yes | yes | LLVM backend (needs a C toolchain) |
| FreeBSD | x86_64, aarch64 | yes | yes | LLVM backend (base `cc` suffices) |
| OpenBSD | x86_64, aarch64 | yes | yes | LLVM backend (base `cc` suffices) |
| NetBSD | x86_64, aarch64 | yes | yes | LLVM backend (needs pkgsrc `clang`; base `cc` is GCC) |
| WebAssembly | wasm32-wasi | yes | — | interpreter only |

The WASM build (`zig build wasm`) runs in browsers and WASI runtimes — it
powers the [playground](https://kaappi-lang.org/playground/).

The Windows port (`zig build -Dtarget=aarch64-windows`) covers the full
interpreter — REPL (plain line editing, no history/completion), fibers,
channels, OS threads, FFI (`LoadLibrary`), and the `kaappi test` runner.
thottam installs packages on Windows too (with Git for Windows on PATH);
only manifests with a `build:` command are refused — the C-FFI packages'
Makefiles target POSIX.
Platform differences: fd readiness is socket-only — socket-backed ports
get reactor-driven non-blocking fiber I/O (WSAEventSelect), while pipe
and file ports keep blocking reads (timers and cross-thread wakeups
always work) — and the POSIX-only slice of SRFI-170 (uid/gid, symlinks,
chmod/umask, user/group info) raises a catchable file error.
`cond-expand` distinguishes the platforms: Windows builds expose the
`windows` feature identifier instead of `posix`.

The FreeBSD port (`zig build -Dtarget=x86_64-freebsd` or
`aarch64-freebsd`) is full POSIX with no degradations: kqueue-backed
fiber I/O, OS threads, complete SRFI-170, the full linenoise REPL, and
thottam with `build:` support. `kaappi compile` links native binaries
with the base system's `cc` — no extra toolchain needed.

The OpenBSD port (`zig build -Dtarget=x86_64-openbsd` or
`aarch64-openbsd`) is the same full-POSIX kqueue platform — fiber I/O,
threads, complete SRFI-170, the full REPL, `build:` support, and native
compilation with base `cc`. Two accommodations for OpenBSD's hardening,
both automatic: each binary is marked `PT_OPENBSD_NOBTCFI` at build time
to opt out of BTCFI enforcement (Zig 0.16 emits no BTI landing pads), and
the interpreter raises its own stack limit at startup to clear OpenBSD's
tight 4 MiB default. See [`docs/dev/openbsd.md`](docs/dev/openbsd.md).

The NetBSD port (`zig build -Dtarget=x86_64-netbsd` or `aarch64-netbsd`)
completes the BSD trio — the same full-POSIX kqueue feature set, verified
on NetBSD 10.1. The runtime binds NetBSD's versioned libc symbols
explicitly (`__kevent50`, `__opendir30`, `__getpwnam50` — the plain names
are old-ABI compat symbols that silently misparse modern structs) and
resets the aarch64 FPCR at startup, which NetBSD boots in flush-to-zero
mode that would break IEEE gradual underflow. The native backend
(`kaappi compile`) needs clang from pkgsrc — NetBSD's base `cc` is GCC,
which can't consume LLVM IR. See [`docs/dev/netbsd.md`](docs/dev/netbsd.md).

## A taste of Kaappi

```
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

The REPL has **syntax highlighting**, **line editing**, **persistent history**
(`~/.kaappi/history`), **tab completion** for all built-in and user-defined
symbols, and **multi-line input** with automatic paren balancing.

### Hygienic macros

```scheme
(define-syntax my-when
  (syntax-rules ()
    ((my-when test body ...)
     (if test (begin body ...)))))

(my-when #t
  (display "hello world")
  (newline))
```

### Libraries

```scheme
(define-library (mylib math)
  (export square cube)
  (import (scheme base))
  (begin
    (define (square x) (* x x))
    (define (cube x) (* x x x))))

(import (mylib math))
(cube 5) ;=> 125
```

### First-class continuations

```scheme
(define saved #f)

(+ 1 (call/cc (lambda (k)
                (set! saved k)
                10)))
;=> 11

(saved 42)
;=> 43
```

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

- **73 SRFIs** — 8 built-in, 65 as portable `.sld` libraries (full list in [CONFORMANCE.md](CONFORMANCE.md))
- **Native binaries** — `kaappi compile program.scm -o program` compiles Scheme to a native executable via LLVM, with self-tail-calls compiled as loops ([details](docs/dev/llvm-backend.md))
- **Standalone bundles** — `zig build -Dbundle-src=program.scm` embeds bytecode + libraries in a single executable
- **C FFI** — call shared libraries from Scheme via `(kaappi ffi)`; 18 marshalled types, callbacks for passing Scheme procedures to C
- **Concurrency** — green threads with channels via `(kaappi fibers)`, plus real OS threads via SRFI-18
- **Stepping debugger** — breakpoints (with conditions), watch expressions, step/next/step-out, frame navigation, locals — all from the REPL
- **Profiler** — `kaappi --profile` or `,profile expr`: per-function self/total time, call counts, allocation bytes
- **Sandbox mode** — `kaappi --sandbox` blocks FFI, file I/O, `eval`, `load`, and environment access
- **Bytecode caching** — compiled `.sbc` files are reused when the source is unchanged
- **Machine-legible diagnostics** — every error carries a stable `KP` code (`error[KP3001]`), with `--diagnostics=json` (LSP shape), `kaappi explain <code>`, and a Scheme accessor `(error-object-code e)` in `(kaappi diagnostics)` for dispatching on codes ([details](docs/dev/diagnostics.md))
- **Capability discovery** — `kaappi features [--json]` reports this build's version, target, compiled-in subsystems, SRFIs, and limits from one source of truth ([details](docs/dev/features.md))
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

`thottam install <pkg>` resolves dependencies, supports version constraints
(`thottam install kaappi-net@">=0.2.0"`), and installs to `~/.kaappi/lib/`
where libraries are discovered automatically.

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

Scheduling is cooperative: spawned fibers run when the main program blocks
(`channel-receive` on an empty channel, `fiber-join`) or calls `(yield)`.
A fiber that blocks on an empty channel is parked and woken by the next
`channel-send` on that channel. When the main program ends, fibers that are
still parked (e.g. workers that never received a stop sentinel) are simply
discarded and the process exits — like goroutines in Go. If the main program
blocks on a channel that no runnable or parked-and-wakeable fiber can ever
send to, `channel-receive` raises a deadlock error (an `error` object,
catchable with `guard`); the same applies to `fiber-join` on a fiber that can
never complete.

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

## Architecture

```
Source → Reader → Expander → IR → Bytecode emission → VM
         (UTF-8    (syntax-   (analysis +   (register-    (generational GC,
          lexer)    rules)     optimization   based)        stack-copied
                               passes)                      continuations)
```

| Component | Role |
|-----------|------|
| **Reader** | Tokenizer + recursive descent parser for the full R7RS lexical syntax, including Unicode identifiers and `#\λ` character literals. |
| **Expander** | `syntax-rules` pattern matching and hygienic template instantiation. |
| **IR** | Tree-structured intermediate representation (33 node types) with analysis passes (tail positions, primitives, constants) and optimization passes (constant folding, dead-branch elimination, and more). |
| **Compiler** | IR → register-based bytecode. |
| **VM** | Bytecode interpreter with growable register file and frame stack, exception handler and dynamic-wind stacks, stack-copying continuations, and a stepping debugger. |
| **GC** | Generational collector (young/old) with write barrier for old→young references. |

Values are **NaN-boxed 64-bit words** — flonums, fixnums, booleans, characters,
and nil all fit in a single u64 with zero heap allocation:

```
Flonum:    any f64 that is not a NaN     ← stored directly
Pointer:   0xFFFC | 48-bit pointer       ← heap object
Fixnum:    0xFFFD | 48-bit signed int    ← up to ±2^47, auto-promotes to bignum
Immediate: 0xFFFE | payload              ← nil, bool, void, eof, char
```

The full component map, file layout, and design notes are in
[docs/dev/architecture.md](docs/dev/architecture.md).

## Testing

```bash
zig build test                     # Zig unit tests
bash tests/scheme/run-all.sh       # all Scheme-level suites
```

The Scheme suites include a 1,391-test R7RS conformance suite (via
`(chibi test)`), plus targeted suites for compliance, continuations, macro
hygiene, SRFIs, and the FFI. CI runs on every platform in the support matrix,
and per-commit performance trends are tracked on the
[benchmark dashboard](https://kaappi-lang.org/kaappi/dev/bench/).

## Documentation

| Document | Description |
|----------|-------------|
| [User Guide](https://kaappi-lang.org/guide/) | Installation, REPL, language tutorial, CLI reference |
| [Procedure Reference](https://kaappi-lang.org/procedures/) | Every built-in procedure, organized by domain |
| [Cookbook](https://kaappi-lang.org/cookbook/) | Task-oriented recipes: REST APIs, JSON, CSV, SQLite, testing |
| [Ecosystem](https://kaappi-lang.org/ecosystem/) | thottam and all kaappi-* libraries |
| [R7RS Conformance](CONFORMANCE.md) | Design choices and per-SRFI coverage details |
| [Architecture](docs/dev/architecture.md) | Pipeline, value representation, GC, file organization |
| [Adding Features](docs/dev/adding-features.md) | Step-by-step guides for extending the implementation |
| [Testing Guide](docs/dev/testing.md) | Unit tests, Scheme tests, benchmarks, CI |
| [Developer Docs Index](docs/dev/README.md) | All contributor docs: guides, design decisions, postmortems |

## Known limitations

### Continuations

`call/cc` captures continuations by copying the full VM state (registers, call
frames, exception handlers, dynamic-wind stack). Cost is O(stack depth) per
capture — negligible for most programs, but noticeable if continuations are
captured in tight inner loops. Continuations captured in one top-level REPL
expression cannot re-enter subsequent top-level expressions (standard behavior
shared by Guile, Chibi, Chicken, Chez, and Racket).

### Fibers

Callbacks driven by `map`, `for-each`, `vector-map`, `vector-for-each`,
`string-map`, `string-for-each`, `dynamic-wind`, and `force` run in the
bytecode dispatch loop, so a fiber can park inside them (e.g. block on an
empty channel) and resume later. Other higher-order procedures are still
native drivers — SRFI-1 (`fold`, `filter`, `find`, `any`, `every`, ...),
`sort`, `hash-table-walk`/`hash-table-update!`, `assoc`/`member` with a
custom predicate, `string-index`, `eval`, ... — and a fiber that blocks on
an empty channel inside one of those callbacks cannot be parked: the native
call's state lives on the Zig stack and cannot be suspended. If other fibers
are runnable the scheduler still makes progress, but if the blocked receive
is the only thing left it raises a deadlock error instead of suspending.
Move blocking `channel-receive` calls into plain Scheme loops (named `let`,
`do`) or the bytecode-driven procedures above when a fiber must wait inside
iteration.

Port I/O that would block (a socket or pipe read/write with no data or a
full kernel buffer) parks the fiber on the per-thread reactor instead of
blocking the OS thread, so fibers reading different connections interleave.
The main fiber — or a fiber inside a native-driver callback — cannot be
parked; it instead dispatches sibling fibers in place while it waits, so
progress continues either way. Ports on fds other than 0/1/2 buffer output
until `flush-output-port`, `close-port`, a read on the same port, the
buffer filling (8 KiB), or program exit; stdin/stdout/stderr remain
unbuffered. WASI builds keep blocking single-fiber I/O (the reactor's WASI
backend is timer-only until KEP-0001 Phase 4).

### OS threads (SRFI-18)

Each OS thread gets its own GC with an independent heap. Values are deep-copied
when crossing thread boundaries (at `thread-start!` and `thread-join!`). This
means threads cannot share mutable state directly — use channels or return
values to communicate. Child threads can allocate and GC independently without
affecting the parent.

A `(kaappi fibers)` channel captured by a thread's thunk (or nested inside a
value sent over one) crosses safely: it is promoted to a mutex-protected,
refcounted shared channel outside every GC heap, and every message crosses by
copy (KEP-0002). `(kaappi parallel)` builds worker pools and `parallel-map`/
`parallel-for-each` on top of this — see the [Concurrency
guide](https://kaappi-lang.org/guide/concurrency/) for the higher-level API.
A channel reached through a shared global instead (not captured by a thunk or
message) still raises a descriptive error rather than corrupting memory. Two
narrow correctness issues are open in the cross-thread wakeup path
([#1487](https://github.com/kaappi/kaappi/issues/1487),
[#1489](https://github.com/kaappi/kaappi/issues/1489)) — not yet recommended
for production concurrent workloads. See [Standards
Conformance](https://kaappi-lang.org/conformance/#extensions-beyond-r7rs-smalls-scope)
for current status.

A closure that crosses a `thread-start!` boundary must not, once running on
the other thread, *call* a separately-defined top-level procedure from a
library — doing so hangs
([#1520](https://github.com/kaappi/kaappi/issues/1520)). The identical logic
inlined directly into the closure works correctly; `(kaappi parallel)`'s own
worker loop is written this way for exactly this reason.

`parallel-map`/`parallel-for-each` submit one task per list element, so a
large list means many concurrent `pool-submit`/`task-wait` round trips —
which, given #1487/#1489 above, means an intermittent hang becomes
increasingly likely somewhere past a few hundred concurrent submissions
rather than a hard cutoff. Reliable in testing through list sizes in the
low hundreds. For larger inputs, chunk manually with
`make-pool`/`pool-submit`/`task-wait` (one task per processor, each
covering a slice of the input with an ordinary sequential loop) instead of
one task per element — see `kaappi-examples/parallel-primes` for a worked
example.

### Macros

Only `syntax-rules` is supported. `syntax-case` was intentionally excluded from
R7RS-small and is not implemented.

### SRFI coverage

73 SRFIs are supported. Some built-in SRFIs have minor coverage gaps (e.g.,
linear-update variants in SRFI-1, `string-xcopy!` in SRFI-13). See
[CONFORMANCE.md](CONFORMANCE.md) for per-SRFI details.

## Contributing

Contributions are welcome — bug reports, SRFI implementations, documentation,
and ecosystem libraries alike.

**New here?** Start with
[GitHub Discussions](https://github.com/orgs/kaappi/discussions) — ask
questions, report bugs, propose ideas. Issues and PRs are open to
[org members](https://github.com/kaappi); request an invite in Discussions
when you're ready to contribute directly.

- [CONTRIBUTING.md](CONTRIBUTING.md) — how to get involved, build, test, and submit changes
- [Community](https://kaappi-lang.org/community/) — all the ways to participate
- [Code of Conduct](CODE_OF_CONDUCT.md)

Every bug fix needs a regression test; see the
[testing guide](docs/dev/testing.md).

## License

[MIT](LICENSE)
