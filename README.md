# Kaappi

A complete R7RS-small Scheme implementation written in Zig.

Kaappi implements the full [Revised^7 Report on the Algorithmic Language Scheme](https://small.r7rs.org/) — every identifier from Appendix A is supported. The runtime uses a bytecode compiler with a register-based VM, mark-and-sweep garbage collection, and stack-copying continuations.

## Quick start

```
zig build run                        # Launch the REPL
zig build run -- program.scm         # Run a Scheme file
zig build test                       # Run all tests
```

Requires Zig 0.16+.

## REPL

```
$ zig build run
Kaappi Scheme v0.1.0
Type (exit) to quit.

kaappi> (define (fib n)
          (if (< n 2) n
              (+ (fib (- n 1)) (fib (- n 2)))))
kaappi> (fib 20)
6765
kaappi> (map (lambda (x) (* x x)) '(1 2 3 4 5))
(1 4 9 16 25)
kaappi> `(the answer is ,(* 6 7))
(the answer is 42)
```

## Features

### R7RS compliance

All 14 standard libraries are implemented with 313 built-in procedures and 32 syntax forms:

| Library | Status |
|---------|--------|
| `(scheme base)` | Complete |
| `(scheme case-lambda)` | Complete |
| `(scheme char)` | Complete |
| `(scheme complex)` | Complete |
| `(scheme cxr)` | Complete |
| `(scheme eval)` | Complete |
| `(scheme file)` | Complete |
| `(scheme inexact)` | Complete |
| `(scheme lazy)` | Complete |
| `(scheme load)` | Complete |
| `(scheme process-context)` | Complete |
| `(scheme read)` | Complete |
| `(scheme time)` | Complete |
| `(scheme write)` | Complete |

### Language features

- **Proper tail calls** — iterative recursion in constant stack space
- **First-class continuations** — `call/cc` via stack copying, `dynamic-wind`
- **Hygienic macros** — `syntax-rules` with pattern matching and ellipsis
- **Library system** — `define-library`, `import` with modifiers, `.sld` file loading
- **Numeric tower** — fixnum (i64), flonum (f64), complex numbers
- **Exception handling** — `guard`, `raise`, `with-exception-handler`
- **Records** — `define-record-type` with constructors, predicates, accessors, mutators
- **Ports and I/O** — file, string, and bytevector ports
- **Lazy evaluation** — `delay`, `force`, promises
- **Multiple values** — `values`, `call-with-values`, `let-values`
- **Parameter objects** — `make-parameter`, `parameterize`
- **Vectors and bytevectors** — mutable arrays with full operation set

### Data types

| Type | Representation |
|------|---------------|
| Integer | 63-bit signed fixnum (tagged u64) |
| Real | IEEE 754 f64 (heap-allocated) |
| Complex | Pair of f64 (heap-allocated) |
| Boolean | Immediate value |
| Character | 21-bit Unicode codepoint (immediate) |
| String | Byte array (heap-allocated) |
| Symbol | Interned string |
| Pair | Car/cdr cell (heap-allocated) |
| Vector | Array of values (heap-allocated) |
| Bytevector | Byte array (heap-allocated) |
| Port | File descriptor or string buffer |
| Procedure | Closure or native function |
| Continuation | Saved VM state |
| Promise | Lazy thunk wrapper |
| Record | User-defined structured type |

## Architecture

```
Source → Reader → Expander → Compiler → Bytecode → VM
                  (macros)               (register-based)
```

- **Reader** (`reader.zig`) — Tokenizer + recursive descent parser for R7RS lexical syntax
- **Expander** (`expander.zig`) — `syntax-rules` pattern matching and template instantiation
- **Compiler** (`compiler.zig`) — S-expressions to register-based bytecode with tail-call detection
- **VM** (`vm.zig`) — Register-based execution with call frames, exception handler stack, and wind stack
- **GC** (`memory.zig`) — Mark-and-sweep with intrusive object linked list and root tracking

### Value representation

Values are tagged 64-bit words:
- Bit 0 = 1: fixnum (63-bit signed integer, zero allocation)
- Bits 0-2 = 000: pointer to heap object (8-byte aligned)
- Bits 0-1 = 10: immediate (nil, boolean, void, eof, character)

## Building

```bash
zig build              # Build the kaappi executable
zig build run          # Build and run the REPL
zig build test         # Run all unit tests
```

The executable is placed in `zig-out/bin/kaappi`.

## Project structure

```
src/
  main.zig                 Entry point and REPL
  types.zig                Value type, heap objects, opcodes
  memory.zig               GC allocator
  reader.zig               Tokenizer and S-expression parser
  expander.zig             Macro expansion engine
  compiler.zig             Bytecode compiler (core)
  compiler_forms.zig       Re-export hub for derived forms
  compiler_conditionals.zig  and, or, cond, when, unless, cond-expand
  compiler_bindings.zig    let, letrec, do, let-values
  compiler_advanced.zig    case, case-lambda, guard, quasiquote
  vm.zig                   Register VM (core)
  vm_library.zig           Import and define-library handling
  vm_records.zig           define-record-type desugaring
  vm_continuations.zig     call/cc, dynamic-wind, continuation state
  printer.zig              Value display and write
  library.zig              Library registry and standard libraries
  primitives.zig           Core data primitives and registration
  primitives_arithmetic.zig  Numeric procedures
  primitives_string.zig    String and character comparison
  primitives_char.zig      (scheme char) library
  primitives_vector.zig    Vector procedures
  primitives_bytevector.zig  Bytevector procedures
  primitives_io.zig        Port and file I/O
  primitives_control.zig   Exceptions, continuations, values
  primitives_lazy.zig      Promises (delay/force)
  primitives_cxr.zig       Car/cdr compositions
  primitives_r7rs.zig      Time, process-context, eval, load

tests/scheme/             Scheme-level test suites
docs/                     R7RS specification (PDF)
```

## Known limitations

- **No bignum**: Integers are 63-bit. Overflow is silent.
- **No exact rationals**: `/` with non-divisible exact integers returns an inexact result.
- **ASCII strings**: String operations treat strings as byte arrays. Full Unicode support is not implemented.
- **Stack-copying continuations**: `call/cc` copies the entire VM state. This is correct but can be expensive for deep stacks.

## License

MIT
