# Crash reporting — the panic handler

When a bug is *in Kaappi itself* (not in the user's program), the ReleaseSafe
binary dies with a Zig panic and a stack trace. The trace is the valuable part
and is kept verbatim. What the custom panic handler adds in front of it is the
context that turns an unreproducible report into an actionable one:

```text
kaappi internal error — this is a bug in kaappi, not in your program.
  version: v0.14.1 (aarch64-macos, ReleaseSafe)
  while:   compiling /path/to/file.scm
  report:  https://github.com/kaappi/kaappi/issues/new — include everything below.

thread 12345 panic: <message>
<stack trace>
```

Part of the machine-legibility epic
([#1503](https://github.com/kaappi/kaappi/issues/1503)); tracked in
[#1514](https://github.com/kaappi/kaappi/issues/1514). A raw panic is already
better than a silent segfault, but it gives the user no guidance, no version
context, and lands as a report we often can't reproduce. The banner fixes all
three: it says *whose* bug it is, names the exact build, and says where to send
it — while the trace below it stays intact.

## The four banner lines

| Line | Source | Why |
|------|--------|-----|
| identity | comptime `binary_name` | Distinguishes an interpreter bug from a bug in the user's Scheme, and names which binary (`kaappi` / `thottam`). |
| `version:` | `build_options.version`, `builtin.cpu.arch`/`os.tag`, `builtin.mode` | A report that doesn't name the build wastes a round-trip. All three are comptime — free at runtime. The target is the short `arch-os` form; `kaappi features` prints the full `arch-os-abi` triple. |
| `while:` | the breadcrumb (below) | The single most useful field for reproduction: which pipeline stage, and which file, was in flight. |
| `report:` | constant | Removes the "where do I file this?" step. |

The `while:` line is **omitted** when the breadcrumb is still `idle` — a
pre-pipeline crash, or a binary like `thottam` that runs no Scheme pipeline —
rather than inventing a stage. The other three lines always print.

## The breadcrumb

`src/crash.zig` holds a process-wide breadcrumb: a coarse `Stage`
(`reading` / `expanding` / `compiling` / `executing`) plus the file in flight.
The top-level driver updates it at each stage boundary with a single store:

```zig
crash.noteFile(path);      // once per file/stream
crash.noteStage(.compiling); // per top-level form, at each boundary
```

It is deliberately trivial — a plain enum store and a slice store, no
allocation, no locking — matching the other process-wide flags in this codebase
(`ir.optimize_enabled`, `main.script_had_error`,
`toplevel_driver.diagnostic_format`). The design constraints that make plain
globals safe here:

- **Read only at panic.** Live execution never consults the breadcrumb, so a
  stale value can only mislabel a crash; it can never misdirect a running
  program.
- **Single writer.** Only the main pipeline thread writes it, and only before
  any SRFI-18 worker exists for a given file, so there is no torn write to worry
  about. An SRFI-18 worker that panics reads whatever stage was last set
  (`executing`), which is correct for it anyway.
- **Never dangles.** The stored file slice is always a long-lived path (from
  argv) or a string literal (`<stdin>`, `<repl>`, `<bundled program>`,
  `<panic-test>`), so it is valid when the handler reads it.

### Where it's wired

| Path | File | Stages set |
|------|------|-----------|
| file runner (fresh + cached) | `main.zig` `runFile` | reading → executing (imports) → compiling → executing |
| stdin runner | `main.zig` `runStdin` | reading → executing → compiling → executing |
| standalone (embedded bytecode) | `main.zig` | executing |
| REPL | `repl.zig` `evalInputInner` | reading → executing → compiling → executing, `reset()` on return to prompt |
| `kaappi ast` / `expand` / `ir` | `pipeline.zig` | reading, expanding, compiling |
| `kaappi compile` (native) | `native_compiler.zig` `emitLlvmFile` | compiling |

Macro expansion happens *inside* the compiler on the normal run path, so
`expanding` as a distinct breadcrumb is set by `kaappi expand` (where it is the
literal activity); on a normal run the compiler stage covers expansion.

## Installation

Each user-facing binary's root file sets the Zig root `panic` namespace to a
handler built for its name:

```zig
// src/main.zig
pub const panic = crash.PanicHandler("kaappi");
// src/thottam.zig
pub const panic = crash.PanicHandler("thottam");
```

`PanicHandler(name)` returns a `std.debug.FullPanic` whose `call` prints the
banner and then delegates to `std.debug.defaultPanic`, so **every** safety-check
panic, `unreachable`, and `@panic` funnels through it with the standard message
and full stack trace preserved. The handler writes straight to fd 2 with a raw
syscall — a panic handler must not depend on allocation or any subsystem that may
itself be in the broken state that triggered the panic.

## The deliberate-panic test hook

`crash.maybePanicTest` recognizes `--panic-test[=<stage>]`, sets a
representative breadcrumb, and deliberately `@panic`s. `main` dispatches it
before any setup, so it never touches the VM. It is undocumented (not in
`--help`) and not part of normal option parsing.

It is intentionally **available in every build mode, not Debug-gated**: the whole
point is to verify the banner the *shipped* ReleaseSafe binary prints (the mode
the example names), and the Scheme error suite runs against exactly that build. A
Debug-only hook could never test the path a real user hits.

`tests/scheme/errors/crash-handler.sh` drives it: it asserts the identity line,
the version/target/build-mode line, the breadcrumb (and that it tracks the
`=<stage>` selector), the report URL, that the standard panic message + trace
addresses survive in front of the banner, and that the process dies by signal
(abort) rather than exiting cleanly. `src/crash.zig` also carries unit tests for
the stage verbs, the breadcrumb state machine, and the target-string shape.
