# Command-Line Reference

```
zig build run -- [OPTIONS] [FILE]
```

| Option | Description |
|--------|-------------|
| *(no arguments)* | Launch the REPL |
| `FILE` | Run a Scheme source file |
| `--compile FILE` | Compile to bytecode (.sbc) without running |
| `--lib-path DIR` | Add a directory to the library search path (repeatable) |
| `--profile` | Profile execution (per-function timing, call counts, allocations) |
| `--sandbox` | Sandbox mode — blocks FFI, file I/O, `eval`, `load`, env access |
| `--no-jit` | Disable JIT compilation |
| `--no-cache` | Disable bytecode caching |
| `--gc-stats` | Print GC statistics on exit |

**Standalone binaries:**

```bash
zig build -Dbundle-src=program.scm    # compile + embed in one step
zig build -Dbundle=program.sbc        # embed pre-compiled bytecode
```

### Examples

```bash
# REPL
zig build run

# Run a file
zig build run -- program.scm

# Run with additional library paths
zig build run -- --lib-path ./vendor/libs --lib-path ./mylibs program.scm

# Compile only
zig build run -- --compile mylib.scm

# Pipe input
echo '(+ 1 2)' | zig build run

# Build and install
zig build
cp zig-out/bin/kaappi /usr/local/bin/
```

---

