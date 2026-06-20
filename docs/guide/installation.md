# Installation

### Prerequisites

- **Zig 0.16+** -- the sole build tool (no cmake, make, or cargo)
- **C toolchain** -- needed to compile the vendored linenoise library (line
  editing for the REPL). On macOS this comes with Xcode Command Line Tools; on
  Linux it comes with `gcc` or `clang`.

### macOS

```bash
brew install zig
git clone <repo-url> kaappi
cd kaappi
zig build
```

### Linux

Download Zig 0.16+ from [ziglang.org/download](https://ziglang.org/download/),
extract it, and add it to your `PATH`. Then:

```bash
git clone <repo-url> kaappi
cd kaappi
zig build
```

### Verify the build

The executable is placed at `zig-out/bin/kaappi`:

```bash
./zig-out/bin/kaappi --help
```

Run the test suite to confirm everything works:

```bash
zig build test
```

### Build modes

The default build uses **ReleaseSafe** (fast execution with bounds checking).
For maximum throughput use `-Doptimize=ReleaseFast`. The Debug mode is roughly
500x slower for allocation-heavy workloads -- only use it when debugging the
runtime itself:

```bash
zig build -Doptimize=Debug
```

---

