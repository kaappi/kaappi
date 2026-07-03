const std = @import("std");
const is_wasm = @import("builtin").os.tag == .wasi;
const types = @import("types.zig");
const Value = types.Value;

/// A Scheme library: a named set of exported bindings.
pub const Library = struct {
    name: []const u8, // canonical name like "scheme.base"
    owned_name: ?[]const u8, // if non-null, this is a heap-allocated name to free
    exports: std.StringHashMap(Value),
    lib_env: ?*std.StringHashMap(Value) = null, // per-library environment (heap-allocated)
    allocator: std.mem.Allocator,

    /// Create a library with a borrowed name (string literal or other static string).
    pub fn init(allocator: std.mem.Allocator, name: []const u8) Library {
        return .{
            .name = name,
            .owned_name = null,
            .exports = std.StringHashMap(Value).init(allocator),
            .allocator = allocator,
        };
    }

    /// Create a library with an owned (heap-allocated) name.
    pub fn initOwned(allocator: std.mem.Allocator, name: []const u8) Library {
        return .{
            .name = name,
            .owned_name = name,
            .exports = std.StringHashMap(Value).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Library) void {
        self.exports.deinit();
        if (self.lib_env) |env| {
            env.deinit();
            self.allocator.destroy(env);
        }
        if (self.owned_name) |owned| {
            self.allocator.free(owned);
        }
    }

    pub fn addExport(self: *Library, name: []const u8, value: Value) !void {
        try self.exports.put(name, value);
    }
};

/// Registry mapping canonical library name strings to Library instances.
pub const LibraryRegistry = struct {
    allocator: std.mem.Allocator,
    libraries: std.StringHashMap(Library),
    /// Environments of replaced libraries. Closures compiled in a library's
    /// begin block hold `Function.env` pointers to its lib_env and can
    /// outlive the library (escaping via import into vm.globals), so a
    /// replaced env must stay alive until the registry is torn down (#820).
    retired_envs: std.ArrayList(*std.StringHashMap(Value)) = .empty,

    pub fn init(allocator: std.mem.Allocator) LibraryRegistry {
        return .{
            .allocator = allocator,
            .libraries = std.StringHashMap(Library).init(allocator),
        };
    }

    pub fn deinit(self: *LibraryRegistry) void {
        var it = self.libraries.valueIterator();
        while (it.next()) |lib| {
            lib.deinit();
        }
        self.libraries.deinit();
        for (self.retired_envs.items) |env| {
            env.deinit();
            self.allocator.destroy(env);
        }
        self.retired_envs.deinit(self.allocator);
    }

    /// Register a new library (or replace an existing one).
    pub fn register(self: *LibraryRegistry, lib: Library) !void {
        const gop = try self.libraries.getOrPut(lib.name);
        if (gop.found_existing) {
            if (gop.value_ptr.lib_env) |env| {
                try self.retired_envs.append(self.allocator, env);
                gop.value_ptr.lib_env = null;
            }
            gop.value_ptr.deinit();
            gop.key_ptr.* = lib.name;
        }
        gop.value_ptr.* = lib;
    }

    /// Look up a library by canonical name.
    pub fn get(self: *LibraryRegistry, name: []const u8) ?*Library {
        return self.libraries.getPtr(name);
    }

    /// Check if a library with the given name exists.
    pub fn contains(self: *LibraryRegistry, name: []const u8) bool {
        return self.libraries.contains(name);
    }
};

/// Register the standard R7RS libraries from the VM's globals map.
/// This should be called after primitives.registerAll has populated the globals.
pub fn registerStandardLibraries(registry: *LibraryRegistry, globals: *std.StringHashMap(Value)) !void {
    const allocator = registry.allocator;

    // (scheme base) — all standard procedures
    const scheme_base_names = [_][]const u8{
        // Arithmetic
        "+",                      "-",                              "*",                  "/",
        "quotient",               "remainder",                      "modulo",             "=",
        "<",                      ">",                              "<=",                 ">=",
        "zero?",                  "positive?",                      "negative?",          "abs",
        "min",                    "max",                            "even?",              "odd?",
        "gcd",                    "lcm",
        // Rounding
                                   "floor",              "ceiling",
        "truncate",               "round",
        // Exactness
                                 "exact?",             "inexact?",
        "exact-integer?",         "exact",                          "inexact",
        // Powers
                   "expt",
        "square",                 "sqrt",                           "exact-integer-sqrt",
        // Pairs and lists
        "cons",
        "car",                    "cdr",                            "set-car!",           "set-cdr!",
        "list",                   "length",                         "append",             "reverse",
        "caar",                   "cadr",                           "cdar",               "cddr",
        "list-ref",               "list-tail",                      "list-set!",          "list-copy",
        "make-list",              "member",                         "memq",               "memv",
        "assoc",                  "assq",                           "assv",
        // Higher-order list functions
                      "map",
        "for-each",
        // Type predicates
                      "pair?",                          "null?",              "number?",
        "integer?",               "real?",                          "complex?",           "rational?",
        "symbol?",                "string?",                        "boolean?",           "char?",
        "procedure?",             "list?",
        // Equivalence
                                 "eq?",                "eqv?",
        "equal?",
        // Boolean
                        "not",                            "boolean=?",          "symbol=?",
        // String operations
        "number->string",         "string->number",                 "string-length",      "string-append",
        "symbol->string",         "string->symbol",                 "string",             "make-string",
        "string-ref",             "string-set!",                    "substring",          "string-copy",
        "string-copy!",           "string-fill!",                   "string->list",       "list->string",
        "string-for-each",        "string-map",                     "string<?",           "string<=?",
        "string=?",               "string>=?",                      "string>?",
        // Char operations (base library subset)
                  "char->integer",
        "integer->char",          "char<?",                         "char<=?",            "char=?",
        "char>=?",                "char>?",
        // I/O (also in scheme.write)
                                "display",            "write",
        "newline",
        // Misc
                       "apply",                          "error",
        // Exception system (R7RS 6.11)
                     "raise",
        "raise-continuable",      "with-exception-handler",         "error-object?",      "error-object-message",
        "error-object-irritants", "file-error?",                    "read-error?",
        // Record system internal primitives (used by define-record-type)
               "%make-record-type",
        "%make-record",           "%record?",                       "%record-ref",        "%record-set!",
        // Port and I/O (R7RS 6.13)
        "current-input-port",     "current-output-port",            "current-error-port", "port?",
        "input-port?",            "output-port?",                   "textual-port?",      "binary-port?",
        "input-port-open?",       "output-port-open?",              "close-port",         "close-input-port",
        "close-output-port",      "read-char",                      "peek-char",          "read-line",
        "char-ready?",            "write-char",                     "write-string",       "eof-object?",
        "eof-object",
        // Continuations (R7RS 6.10)
                    "call-with-current-continuation", "call/cc",            "call-with-escape-continuation",
        "call/ec",                "dynamic-wind",                   "values",             "call-with-values",
        // Complex numbers
        "make-rectangular",       "make-polar",                     "real-part",          "imag-part",
        "magnitude",              "angle",
        // Vectors (R7RS 6.8)
                                 "vector",             "make-vector",
        "vector?",                "vector-length",                  "vector-ref",         "vector-set!",
        "vector->list",           "list->vector",                   "vector-fill!",       "vector-copy",
        "vector-copy!",           "vector-append",                  "vector-for-each",    "vector-map",
        "vector->string",
        // Bytevectors (R7RS 6.9)
                "bytevector?",                    "make-bytevector",    "bytevector",
        "bytevector-length",      "bytevector-u8-ref",              "bytevector-u8-set!", "bytevector-copy",
        "bytevector-copy!",       "bytevector-append",              "utf8->string",       "string->utf8",
        // String ports
        "open-input-string",      "open-output-string",             "get-output-string",
        // Additional I/O
         "read-string",
        "flush-output-port",
        // Integer division
             "floor-quotient",                 "floor-remainder",    "floor/",
        "truncate-quotient",      "truncate-remainder",             "truncate/",
        // Rational
                 "numerator",
        "denominator",            "rationalize",
        // Aliases
                           "exact->inexact",     "inexact->exact",
        // Misc
        "features",
        // Promises
                      "make-promise",                   "promise?",
        // Parameters
                  "make-parameter",
        // File I/O wrappers
        "call-with-port",
        // Binary I/O
                "read-u8",                        "peek-u8",            "u8-ready?",
        "write-u8",               "read-bytevector",                "write-bytevector",
        // Bytevector ports
          "open-input-bytevector",
        "open-output-bytevector", "get-output-bytevector",          "read-bytevector!",
        // String/vector conversion
          "string->vector",
    };

    var base = Library.init(allocator, "scheme.base");
    for (scheme_base_names) |name| {
        if (globals.get(name)) |val| {
            try base.addExport(name, val);
        }
    }
    try registry.register(base);

    // (scheme write) — write/display procedures
    const scheme_write_names = [_][]const u8{
        "display",      "write",
        "write-shared", "write-simple",
    };
    var write_lib = Library.init(allocator, "scheme.write");
    for (scheme_write_names) |name| {
        if (globals.get(name)) |val| {
            try write_lib.addExport(name, val);
        }
    }
    try registry.register(write_lib);

    // (scheme inexact) — inexact math procedures
    const scheme_inexact_names = [_][]const u8{
        "sin", "cos", "tan",  "asin",    "acos",      "atan",
        "exp", "log", "sqrt", "finite?", "infinite?", "nan?",
    };
    var inexact_lib = Library.init(allocator, "scheme.inexact");
    for (scheme_inexact_names) |name| {
        if (globals.get(name)) |val| {
            try inexact_lib.addExport(name, val);
        }
    }
    try registry.register(inexact_lib);

    // (scheme read)
    const scheme_read_names = [_][]const u8{"read"};
    var read_lib = Library.init(allocator, "scheme.read");
    for (scheme_read_names) |name| {
        if (globals.get(name)) |val| {
            try read_lib.addExport(name, val);
        }
    }
    try registry.register(read_lib);

    // (scheme char) — character classification and case operations
    const scheme_char_names = [_][]const u8{
        "char-alphabetic?", "char-numeric?",    "char-whitespace?",
        "char-upper-case?", "char-lower-case?", "char-upcase",
        "char-downcase",    "char-foldcase",    "digit-value",
        "char-ci<?",        "char-ci<=?",       "char-ci=?",
        "char-ci>=?",       "char-ci>?",        "string-ci<?",
        "string-ci<=?",     "string-ci=?",      "string-ci>=?",
        "string-ci>?",      "string-upcase",    "string-downcase",
        "string-foldcase",
    };
    var char_lib = Library.init(allocator, "scheme.char");
    for (scheme_char_names) |name| {
        if (globals.get(name)) |val| {
            try char_lib.addExport(name, val);
        }
    }
    try registry.register(char_lib);

    // (scheme lazy) — delay/force/promises
    const scheme_lazy_names = [_][]const u8{
        "delay", "delay-force", "force", "make-promise", "promise?",
    };
    var lazy_lib = Library.init(allocator, "scheme.lazy");
    for (scheme_lazy_names) |name| {
        if (globals.get(name)) |val| {
            try lazy_lib.addExport(name, val);
        }
    }
    try registry.register(lazy_lib);

    // (scheme time) — time procedures
    const scheme_time_names = [_][]const u8{
        "current-second", "current-jiffy", "jiffies-per-second",
    };
    var time_lib = Library.init(allocator, "scheme.time");
    for (scheme_time_names) |name| {
        if (globals.get(name)) |val| {
            try time_lib.addExport(name, val);
        }
    }
    try registry.register(time_lib);

    // (scheme process-context) — process procedures
    const scheme_pc_names = [_][]const u8{
        "command-line",             "exit",                      "emergency-exit",
        "get-environment-variable", "get-environment-variables",
    };
    var pc_lib = Library.init(allocator, "scheme.process-context");
    for (scheme_pc_names) |name| {
        if (globals.get(name)) |val| {
            try pc_lib.addExport(name, val);
        }
    }
    try registry.register(pc_lib);

    // (scheme eval) — eval/environment
    const scheme_eval_names = [_][]const u8{ "eval", "environment", "interaction-environment" };
    var eval_lib = Library.init(allocator, "scheme.eval");
    for (scheme_eval_names) |name| {
        if (globals.get(name)) |val| {
            try eval_lib.addExport(name, val);
        }
    }
    try registry.register(eval_lib);

    // (scheme repl) — REPL support (R7RS §6.4)
    const scheme_repl_names = [_][]const u8{"interaction-environment"};
    var repl_lib = Library.init(allocator, "scheme.repl");
    for (scheme_repl_names) |name| {
        if (globals.get(name)) |val| {
            try repl_lib.addExport(name, val);
        }
    }
    try registry.register(repl_lib);

    // (scheme load) — load procedure
    const scheme_load_names = [_][]const u8{"load"};
    var load_lib = Library.init(allocator, "scheme.load");
    for (scheme_load_names) |name| {
        if (globals.get(name)) |val| {
            try load_lib.addExport(name, val);
        }
    }
    try registry.register(load_lib);

    // (scheme r5rs) — R5RS compatibility. Per R7RS Appendix A, this library
    // provides the full R5RS identifier set (except transcript-on/off, which
    // Kaappi does not implement). exact/inexact appear under their R5RS names
    // (exact->inexact, inexact->exact), which are registered as globals, so no
    // renaming is needed. Syntactic keywords (define, lambda, if, cond,
    // syntax-rules, ...) are recognized directly by the compiler rather than
    // stored as runtime values, so the globals.get guard below skips them —
    // the same as (scheme base) above. Listing them keeps this a faithful,
    // auditable transcription of the Appendix A table.
    const scheme_r5rs_names = [_][]const u8{
        "*",                         "+",                              "...",
        "/",                         "<",                              "<=",
        "=",                         "=>",                             ">",
        ">=",                        "abs",                            "acos",
        "and",                       "angle",                          "append",
        "apply",                     "asin",                           "assoc",
        "assq",                      "assv",                           "atan",
        "begin",                     "boolean?",                       "caaaar",
        "caaadr",                    "caaar",                          "caadar",
        "caaddr",                    "caadr",                          "caar",
        "cadaar",                    "cadadr",                         "cadar",
        "caddar",                    "cadddr",                         "caddr",
        "cadr",                      "call-with-current-continuation", "call-with-input-file",
        "call-with-output-file",     "call-with-values",               "car",
        "case",                      "cdaaar",                         "cdaadr",
        "cdaar",                     "cdadar",                         "cdaddr",
        "cdadr",                     "cdar",                           "cddaar",
        "cddadr",                    "cddar",                          "cdddar",
        "cddddr",                    "cdddr",                          "cddr",
        "cdr",                       "ceiling",                        "char->integer",
        "char-alphabetic?",          "char-ci<=?",                     "char-ci<?",
        "char-ci=?",                 "char-ci>=?",                     "char-ci>?",
        "char-downcase",             "char-lower-case?",               "char-numeric?",
        "char-ready?",               "char-upcase",                    "char-upper-case?",
        "char-whitespace?",          "char<=?",                        "char<?",
        "char=?",                    "char>=?",                        "char>?",
        "char?",                     "close-input-port",               "close-output-port",
        "complex?",                  "cond",                           "cons",
        "cos",                       "current-input-port",             "current-output-port",
        "define",                    "define-syntax",                  "delay",
        "denominator",               "display",                        "do",
        "dynamic-wind",              "else",                           "eof-object?",
        "eq?",                       "equal?",                         "eqv?",
        "eval",                      "even?",                          "exact->inexact",
        "exact?",                    "exp",                            "expt",
        "floor",                     "for-each",                       "force",
        "gcd",                       "if",                             "imag-part",
        "inexact->exact",            "inexact?",                       "input-port?",
        "integer->char",             "integer?",                       "interaction-environment",
        "lambda",                    "lcm",                            "length",
        "let",                       "let*",                           "let-syntax",
        "letrec",                    "letrec-syntax",                  "list",
        "list->string",              "list->vector",                   "list-ref",
        "list-tail",                 "list?",                          "load",
        "log",                       "magnitude",                      "make-polar",
        "make-rectangular",          "make-string",                    "make-vector",
        "map",                       "max",                            "member",
        "memq",                      "memv",                           "min",
        "modulo",                    "negative?",                      "newline",
        "not",                       "null-environment",               "null?",
        "number->string",            "number?",                        "numerator",
        "odd?",                      "open-input-file",                "open-output-file",
        "or",                        "output-port?",                   "pair?",
        "peek-char",                 "positive?",                      "procedure?",
        "quasiquote",                "quote",                          "quotient",
        "rational?",                 "rationalize",                    "read",
        "read-char",                 "real-part",                      "real?",
        "remainder",                 "reverse",                        "round",
        "scheme-report-environment", "set!",                           "set-car!",
        "set-cdr!",                  "sin",                            "sqrt",
        "string",                    "string->list",                   "string->number",
        "string->symbol",            "string-append",                  "string-ci<=?",
        "string-ci<?",               "string-ci=?",                    "string-ci>=?",
        "string-ci>?",               "string-copy",                    "string-fill!",
        "string-length",             "string-ref",                     "string-set!",
        "string<=?",                 "string<?",                       "string=?",
        "string>=?",                 "string>?",                       "string?",
        "substring",                 "symbol->string",                 "symbol?",
        "syntax-rules",              "tan",                            "truncate",
        "values",                    "vector",                         "vector->list",
        "vector-fill!",              "vector-length",                  "vector-ref",
        "vector-set!",               "vector?",                        "with-input-from-file",
        "with-output-to-file",       "write",                          "write-char",
        "zero?",
    };
    var r5rs_lib = Library.init(allocator, "scheme.r5rs");
    for (scheme_r5rs_names) |name| {
        if (globals.get(name)) |val| {
            try r5rs_lib.addExport(name, val);
        }
    }
    try registry.register(r5rs_lib);

    // (scheme file) — file I/O procedures
    const scheme_file_names = [_][]const u8{
        "open-input-file",        "open-output-file",
        "open-binary-input-file", "open-binary-output-file",
        "file-exists?",           "delete-file",
        "call-with-input-file",   "call-with-output-file",
        "with-input-from-file",   "with-output-to-file",
        "create-directory",       "delete-directory",
    };
    var file_lib = Library.init(allocator, "scheme.file");
    for (scheme_file_names) |name| {
        if (globals.get(name)) |val| {
            try file_lib.addExport(name, val);
        }
    }
    try registry.register(file_lib);

    // (scheme cxr) — three/four-level car/cdr compositions
    const scheme_cxr_names = [_][]const u8{
        // Two-level (also in base)
        "caar",   "cadr",   "cdar",   "cddr",
        // Three-level
        "caaar",  "caadr",  "cadar",  "caddr",
        "cdaar",  "cdadr",  "cddar",  "cdddr",
        // Four-level
        "caaaar", "caaadr", "caadar", "caaddr",
        "cadaar", "cadadr", "caddar", "cadddr",
        "cdaaar", "cdaadr", "cdadar", "cdaddr",
        "cddaar", "cddadr", "cdddar", "cddddr",
    };
    var cxr_lib = Library.init(allocator, "scheme.cxr");
    for (scheme_cxr_names) |name| {
        if (globals.get(name)) |val| {
            try cxr_lib.addExport(name, val);
        }
    }
    try registry.register(cxr_lib);

    // (scheme complex) — complex number procedures
    const scheme_complex_names = [_][]const u8{
        "make-rectangular", "make-polar",
        "real-part",        "imag-part",
        "magnitude",        "angle",
    };
    var complex_lib = Library.init(allocator, "scheme.complex");
    for (scheme_complex_names) |name| {
        if (globals.get(name)) |val| {
            try complex_lib.addExport(name, val);
        }
    }
    try registry.register(complex_lib);

    // (scheme case-lambda) — case-lambda is a compiler syntax form,
    // so the library just needs to exist for (import (scheme case-lambda)) to work.
    const case_lambda_lib = Library.init(allocator, "scheme.case-lambda");
    try registry.register(case_lambda_lib);

    // (kaappi ffi) — C FFI library (not available in WASM)
    if (!is_wasm) {
        const kaappi_ffi_names = [_][]const u8{
            "ffi-open",           "ffi-fn",       "ffi-close",
            "ffi-bytevector-ptr", "ffi-callback", "ffi-callback-release",
            "ffi-callback?",
        };
        var ffi_lib = Library.init(allocator, "kaappi.ffi");
        for (kaappi_ffi_names) |name| {
            if (globals.get(name)) |val| {
                try ffi_lib.addExport(name, val);
            }
        }
        try registry.register(ffi_lib);
    }

    // (kaappi fibers) — green threads
    const kaappi_fiber_names = [_][]const u8{
        "spawn",        "yield",        "fiber-join",      "fiber?",
        "make-channel", "channel-send", "channel-receive", "channel?",
    };
    var fiber_lib = Library.init(allocator, "kaappi.fibers");
    for (kaappi_fiber_names) |name| {
        if (globals.get(name)) |val| {
            try fiber_lib.addExport(name, val);
        }
    }
    try registry.register(fiber_lib);

    // SRFI-18: Multithreading support (not available in WASM)
    if (!is_wasm) {
        const srfi18_names = [_][]const u8{
            "current-thread",             "thread?",                       "make-thread",
            "thread-name",                "thread-specific",               "thread-specific-set!",
            "thread-start!",              "thread-yield!",                 "thread-sleep!",
            "thread-terminate!",          "thread-join!",                  "mutex?",
            "make-mutex",                 "mutex-name",                    "mutex-specific",
            "mutex-specific-set!",        "mutex-state",                   "mutex-lock!",
            "mutex-unlock!",              "condition-variable?",           "make-condition-variable",
            "condition-variable-name",    "condition-variable-specific",   "condition-variable-specific-set!",
            "condition-variable-signal!", "condition-variable-broadcast!", "current-time",
            "time?",                      "time->seconds",                 "seconds->time",
            "join-timeout-exception?",    "abandoned-mutex-exception?",    "terminated-thread-exception?",
            "uncaught-exception?",        "uncaught-exception-reason",
        };
        var srfi18_lib = Library.init(allocator, "srfi.18");
        for (srfi18_names) |name| {
            if (globals.get(name)) |val| {
                try srfi18_lib.addExport(name, val);
            }
        }
        const base_reexports = [_][]const u8{
            "with-exception-handler",
            "raise",
        };
        for (base_reexports) |name| {
            if (globals.get(name)) |val| {
                try srfi18_lib.addExport(name, val);
            }
        }
        try registry.register(srfi18_lib);
    }

    // SRFI-1: List Library
    const srfi1_names = [_][]const u8{
        "cons",              "car",             "cdr",          "pair?",
        "null?",             "list",            "length",       "append",
        "reverse",           "map",             "for-each",     "member",
        "memq",              "memv",            "assoc",        "assq",
        "assv",              "list-ref",        "set-car!",     "set-cdr!",
        "list-copy",         "make-list",       "caar",         "cadr",
        "cdar",              "cddr",            "fold",         "fold-right",
        "reduce",            "reduce-right",    "filter",       "remove",
        "partition",         "find",            "find-tail",    "any",
        "every",             "count",           "iota",         "zip",
        "concatenate",       "take",            "drop",         "take-while",
        "drop-while",        "filter-map",      "append-map",   "last",
        "last-pair",         "proper-list?",    "dotted-list?", "circular-list?",
        "lset-intersection", "lset-difference", "lset=",        "lset-adjoin",
        "lset-union",        "lset-xor",        "xcons",        "cons*",
        "list-tabulate",     "circular-list",   "not-pair?",    "null-list?",
        "list=",             "first",           "second",       "third",
        "fourth",            "fifth",           "sixth",        "seventh",
        "eighth",            "ninth",           "tenth",        "car+cdr",
        "take-right",        "drop-right",      "split-at",     "list-index",
        "span",              "break",           "delete",       "delete-duplicates",
        "alist-cons",        "alist-copy",      "alist-delete", "unfold",
        "unfold-right",      "append-reverse",  "length+",      "unzip1",
        "unzip2",            "pair-for-each",   "pair-fold",    "pair-fold-right",
        "map-in-order",
    };
    var srfi1_lib = Library.init(allocator, "srfi.1");
    for (srfi1_names) |name| {
        if (globals.get(name)) |val| {
            try srfi1_lib.addExport(name, val);
        }
    }
    try registry.register(srfi1_lib);

    // SRFI-9: define-record-type (alias for existing R7RS record support)
    const srfi9_lib = Library.init(allocator, "srfi.9");
    try registry.register(srfi9_lib);

    // SRFI-13: String Library
    const srfi13_names = [_][]const u8{
        "string-contains",   "string-prefix?",      "string-suffix?",
        "string-trim",       "string-trim-right",   "string-trim-both",
        "string-index",      "string-count",        "string-split",
        "string-join",       "string-concatenate",
        // Also include standard string ops
         "string-length",
        "string-append",     "substring",           "string-copy",
        "string-ref",        "string-set!",         "string<?",
        "string<=?",         "string=?",            "string>=?",
        "string>?",          "string-upcase",       "string-downcase",
        "string-foldcase",   "string-take",         "string-drop",
        "string-take-right", "string-drop-right",   "string-pad",
        "string-pad-right",  "string-reverse",      "string-filter",
        "string-delete",     "string-replace",      "string-titlecase",
        "string-every",      "string-any",          "string-tabulate",
        "string-unfold",     "string-unfold-right", "string-index-right",
        "string-skip",       "string-skip-right",
    };
    var srfi13_lib = Library.init(allocator, "srfi.13");
    for (srfi13_names) |name| {
        if (globals.get(name)) |val| {
            try srfi13_lib.addExport(name, val);
        }
    }
    try registry.register(srfi13_lib);

    // SRFI-27: Random Numbers — now a portable .sld wrapping native globals

    // SRFI-39: Parameter objects (alias for existing make-parameter/parameterize)
    var srfi39_lib = Library.init(allocator, "srfi.39");
    if (globals.get("make-parameter")) |v| try srfi39_lib.addExport("make-parameter", v);
    try registry.register(srfi39_lib);

    // SRFI-69: Hash Tables
    const srfi69_names = [_][]const u8{
        "make-hash-table",          "hash-table?",
        "hash-table-ref",           "hash-table-set!",
        "hash-table-delete!",       "hash-table-exists?",
        "hash-table-size",          "hash-table-keys",
        "hash-table-values",        "hash-table-walk",
        "hash-table->alist",        "alist->hash-table",
        "hash-table-copy",          "hash-table-update!/default",
        "hash",                     "string-hash",
        "string-ci-hash",           "hash-by-identity",
        "hash-table-ref/default",   "hash-table-fold",
        "hash-table-merge!",        "hash-table-equivalence-function",
        "hash-table-hash-function",
    };
    var srfi69_lib = Library.init(allocator, "srfi.69");
    for (srfi69_names) |name| {
        if (globals.get(name)) |val| {
            try srfi69_lib.addExport(name, val);
        }
    }
    try registry.register(srfi69_lib);

    // SRFI-133: Vector Library (alias for existing vector ops)
    const srfi133_names = [_][]const u8{
        "vector",              "make-vector",              "vector?",             "vector-length",
        "vector-ref",          "vector-set!",              "vector->list",        "list->vector",
        "vector->string",      "string->vector",           "vector-fill!",        "vector-copy",
        "vector-copy!",        "vector-append",            "vector-for-each",     "vector-map",
        "vector-empty?",       "vector-count",             "vector-any",          "vector-every",
        "vector-index",        "vector-index-right",       "vector-skip",         "vector-skip-right",
        "vector-swap!",        "vector-reverse!",          "vector-reverse-copy", "vector-unfold",
        "vector-unfold-right", "vector-binary-search",     "vector-concatenate",  "vector-cumulate",
        "vector-partition",    "vector-append-subvectors",
    };
    var srfi133_lib = Library.init(allocator, "srfi.133");
    for (srfi133_names) |name| {
        if (globals.get(name)) |val| {
            try srfi133_lib.addExport(name, val);
        }
    }
    try registry.register(srfi133_lib);

    // SRFI-170: POSIX API (not available in WASM)
    if (!is_wasm) {
        const srfi170_names = [_][]const u8{
            "directory-files",           "file-info",                    "file-info?",
            "file-info-directory?",      "file-info-regular?",           "file-info-symlink?",
            "file-info-fifo?",           "file-info-socket?",            "file-info-device?",
            "file-info:size",            "file-info:mtime",              "file-info:mode",
            "file-info:device",          "file-info:inode",              "file-info:nlinks",
            "file-info:uid",             "file-info:gid",                "file-info:rdev",
            "file-info:blksize",         "file-info:blocks",             "file-info:atime",
            "file-info:ctime",           "create-directory",             "delete-directory",
            "rename-file",               "create-symlink",               "read-symlink",
            "create-hard-link",          "real-path",                    "set-file-mode",
            "truncate-file",             "create-fifo",                  "set-file-owner",
            "set-file-times",            "pid",                          "umask",
            "set-umask!",                "current-directory",            "set-current-directory!",
            "user-uid",                  "user-gid",                     "user-effective-uid",
            "user-effective-gid",        "user-supplementary-gids",      "nice",
            "set-environment-variable!", "delete-environment-variable!", "terminal?",
            "user-info",                 "user-info?",                   "user-info:name",
            "user-info:uid",             "user-info:gid",                "user-info:home-dir",
            "user-info:shell",           "user-info:full-name",          "group-info",
            "group-info?",               "group-info:name",              "group-info:gid",
            "open-directory",            "read-directory",               "close-directory",
            "posix-time",                "monotonic-time",               "file-info-type",
            "temp-file-prefix",          "create-temp-file",
        };
        var srfi170_lib = Library.init(allocator, "srfi.170");
        for (srfi170_names) |name| {
            if (globals.get(name)) |val| {
                try srfi170_lib.addExport(name, val);
            }
        }
        try registry.register(srfi170_lib);
    }
}

const sandbox_blocked_names = [_][]const u8{
    "open-binary-input-file",
    "open-binary-output-file",
    "file-exists?",
    "delete-file",
    "open-input-file",
    "open-output-file",
    "call-with-input-file",
    "call-with-output-file",
    "with-input-from-file",
    "with-output-to-file",
};

fn isSandboxBlocked(name: []const u8) bool {
    for (&sandbox_blocked_names) |blocked| {
        if (std.mem.eql(u8, name, blocked)) return true;
    }
    return false;
}

pub fn registerSandboxedLibraries(registry: *LibraryRegistry, globals: *std.StringHashMap(Value)) !void {
    const allocator = registry.allocator;

    // (scheme base) — filter out file I/O procedures
    const scheme_base_names = [_][]const u8{
        "+",                      "-",                              "*",                  "/",
        "quotient",               "remainder",                      "modulo",             "=",
        "<",                      ">",                              "<=",                 ">=",
        "zero?",                  "positive?",                      "negative?",          "abs",
        "min",                    "max",                            "even?",              "odd?",
        "gcd",                    "lcm",                            "floor",              "ceiling",
        "truncate",               "round",                          "exact?",             "inexact?",
        "exact-integer?",         "exact",                          "inexact",            "expt",
        "square",                 "sqrt",                           "exact-integer-sqrt", "cons",
        "car",                    "cdr",                            "set-car!",           "set-cdr!",
        "list",                   "length",                         "append",             "reverse",
        "caar",                   "cadr",                           "cdar",               "cddr",
        "list-ref",               "list-tail",                      "list-set!",          "list-copy",
        "make-list",              "member",                         "memq",               "memv",
        "assoc",                  "assq",                           "assv",               "map",
        "for-each",               "pair?",                          "null?",              "number?",
        "integer?",               "real?",                          "complex?",           "rational?",
        "symbol?",                "string?",                        "boolean?",           "char?",
        "procedure?",             "list?",                          "eq?",                "eqv?",
        "equal?",                 "not",                            "boolean=?",          "symbol=?",
        "number->string",         "string->number",                 "string-length",      "string-append",
        "symbol->string",         "string->symbol",                 "string",             "make-string",
        "string-ref",             "string-set!",                    "substring",          "string-copy",
        "string-copy!",           "string-fill!",                   "string->list",       "list->string",
        "string-for-each",        "string-map",                     "string<?",           "string<=?",
        "string=?",               "string>=?",                      "string>?",           "char->integer",
        "integer->char",          "char<?",                         "char<=?",            "char=?",
        "char>=?",                "char>?",                         "display",            "write",
        "newline",                "apply",                          "error",              "raise",
        "raise-continuable",      "with-exception-handler",         "error-object?",      "error-object-message",
        "error-object-irritants", "file-error?",                    "read-error?",        "%make-record-type",
        "%make-record",           "%record?",                       "%record-ref",        "%record-set!",
        "current-input-port",     "current-output-port",            "current-error-port", "port?",
        "input-port?",            "output-port?",                   "textual-port?",      "binary-port?",
        "input-port-open?",       "output-port-open?",              "close-port",         "close-input-port",
        "close-output-port",      "read-char",                      "peek-char",          "read-line",
        "char-ready?",            "write-char",                     "write-string",       "eof-object?",
        "eof-object",             "call-with-current-continuation", "call/cc",            "call-with-escape-continuation",
        "call/ec",                "dynamic-wind",                   "values",             "call-with-values",
        "make-rectangular",       "make-polar",                     "real-part",          "imag-part",
        "magnitude",              "angle",                          "vector",             "make-vector",
        "vector?",                "vector-length",                  "vector-ref",         "vector-set!",
        "vector->list",           "list->vector",                   "vector-fill!",       "vector-copy",
        "vector-copy!",           "vector-append",                  "vector-for-each",    "vector-map",
        "vector->string",         "bytevector?",                    "make-bytevector",    "bytevector",
        "bytevector-length",      "bytevector-u8-ref",              "bytevector-u8-set!", "bytevector-copy",
        "bytevector-copy!",       "bytevector-append",              "utf8->string",       "string->utf8",
        "open-input-string",      "open-output-string",             "get-output-string",  "read-string",
        "flush-output-port",      "floor-quotient",                 "floor-remainder",    "floor/",
        "truncate-quotient",      "truncate-remainder",             "truncate/",          "numerator",
        "denominator",            "rationalize",                    "exact->inexact",     "inexact->exact",
        "features",               "make-promise",                   "promise?",           "make-parameter",
        "call-with-port",         "read-u8",                        "peek-u8",            "u8-ready?",
        "write-u8",               "read-bytevector",                "write-bytevector",   "open-input-bytevector",
        "open-output-bytevector", "get-output-bytevector",          "read-bytevector!",   "string->vector",
    };

    var base = Library.init(allocator, "scheme.base");
    for (scheme_base_names) |name| {
        if (!isSandboxBlocked(name)) {
            if (globals.get(name)) |val| {
                try base.addExport(name, val);
            }
        }
    }
    try registry.register(base);

    // (scheme write)
    const scheme_write_names = [_][]const u8{
        "display", "write", "write-shared", "write-simple",
    };
    var write_lib = Library.init(allocator, "scheme.write");
    for (scheme_write_names) |name| {
        if (globals.get(name)) |val| {
            try write_lib.addExport(name, val);
        }
    }
    try registry.register(write_lib);

    // (scheme read)
    const scheme_read_names = [_][]const u8{"read"};
    var read_lib = Library.init(allocator, "scheme.read");
    for (scheme_read_names) |name| {
        if (globals.get(name)) |val| {
            try read_lib.addExport(name, val);
        }
    }
    try registry.register(read_lib);

    // (scheme char)
    const scheme_char_names = [_][]const u8{
        "char-alphabetic?", "char-numeric?",    "char-whitespace?",
        "char-upper-case?", "char-lower-case?", "char-upcase",
        "char-downcase",    "char-foldcase",    "digit-value",
        "char-ci<?",        "char-ci<=?",       "char-ci=?",
        "char-ci>=?",       "char-ci>?",        "string-ci<?",
        "string-ci<=?",     "string-ci=?",      "string-ci>=?",
        "string-ci>?",      "string-upcase",    "string-downcase",
        "string-foldcase",
    };
    var char_lib = Library.init(allocator, "scheme.char");
    for (scheme_char_names) |name| {
        if (globals.get(name)) |val| {
            try char_lib.addExport(name, val);
        }
    }
    try registry.register(char_lib);

    // (scheme inexact)
    const scheme_inexact_names = [_][]const u8{
        "sin", "cos", "tan",  "asin",    "acos",      "atan",
        "exp", "log", "sqrt", "finite?", "infinite?", "nan?",
    };
    var inexact_lib = Library.init(allocator, "scheme.inexact");
    for (scheme_inexact_names) |name| {
        if (globals.get(name)) |val| {
            try inexact_lib.addExport(name, val);
        }
    }
    try registry.register(inexact_lib);

    // (scheme lazy)
    const scheme_lazy_names = [_][]const u8{
        "delay", "delay-force", "force", "make-promise", "promise?",
    };
    var lazy_lib = Library.init(allocator, "scheme.lazy");
    for (scheme_lazy_names) |name| {
        if (globals.get(name)) |val| {
            try lazy_lib.addExport(name, val);
        }
    }
    try registry.register(lazy_lib);

    // (scheme time)
    const scheme_time_names = [_][]const u8{
        "current-second", "current-jiffy", "jiffies-per-second",
    };
    var time_lib = Library.init(allocator, "scheme.time");
    for (scheme_time_names) |name| {
        if (globals.get(name)) |val| {
            try time_lib.addExport(name, val);
        }
    }
    try registry.register(time_lib);

    // (scheme cxr)
    const scheme_cxr_names = [_][]const u8{
        "caar",   "cadr",   "cdar",   "cddr",
        "caaar",  "caadr",  "cadar",  "caddr",
        "cdaar",  "cdadr",  "cddar",  "cdddr",
        "caaaar", "caaadr", "caadar", "caaddr",
        "cadaar", "cadadr", "caddar", "cadddr",
        "cdaaar", "cdaadr", "cdadar", "cdaddr",
        "cddaar", "cddadr", "cdddar", "cddddr",
    };
    var cxr_lib = Library.init(allocator, "scheme.cxr");
    for (scheme_cxr_names) |name| {
        if (globals.get(name)) |val| {
            try cxr_lib.addExport(name, val);
        }
    }
    try registry.register(cxr_lib);

    // (scheme complex)
    const scheme_complex_names = [_][]const u8{
        "make-rectangular", "make-polar",
        "real-part",        "imag-part",
        "magnitude",        "angle",
    };
    var complex_lib = Library.init(allocator, "scheme.complex");
    for (scheme_complex_names) |name| {
        if (globals.get(name)) |val| {
            try complex_lib.addExport(name, val);
        }
    }
    try registry.register(complex_lib);

    // (scheme case-lambda)
    const case_lambda_lib = Library.init(allocator, "scheme.case-lambda");
    try registry.register(case_lambda_lib);

    // SKIP: scheme.file, scheme.load, scheme.eval, scheme.repl, scheme.process-context, kaappi.ffi, srfi.170

    // Safe built-in SRFIs
    // SRFI-1
    const srfi1_names = [_][]const u8{
        "cons",              "car",             "cdr",          "pair?",
        "null?",             "list",            "length",       "append",
        "reverse",           "map",             "for-each",     "member",
        "memq",              "memv",            "assoc",        "assq",
        "assv",              "list-ref",        "set-car!",     "set-cdr!",
        "list-copy",         "make-list",       "caar",         "cadr",
        "cdar",              "cddr",            "fold",         "fold-right",
        "reduce",            "reduce-right",    "filter",       "remove",
        "partition",         "find",            "find-tail",    "any",
        "every",             "count",           "iota",         "zip",
        "concatenate",       "take",            "drop",         "take-while",
        "drop-while",        "filter-map",      "append-map",   "last",
        "last-pair",         "proper-list?",    "dotted-list?", "circular-list?",
        "lset-intersection", "lset-difference", "lset=",        "lset-adjoin",
        "lset-union",        "lset-xor",        "xcons",        "cons*",
        "list-tabulate",     "circular-list",   "not-pair?",    "null-list?",
        "list=",             "first",           "second",       "third",
        "fourth",            "fifth",           "sixth",        "seventh",
        "eighth",            "ninth",           "tenth",        "car+cdr",
        "take-right",        "drop-right",      "split-at",     "list-index",
        "span",              "break",           "delete",       "delete-duplicates",
        "alist-cons",        "alist-copy",      "alist-delete", "unfold",
        "unfold-right",      "append-reverse",  "length+",      "unzip1",
        "unzip2",            "pair-for-each",   "pair-fold",    "pair-fold-right",
        "map-in-order",
    };
    var srfi1_lib = Library.init(allocator, "srfi.1");
    for (srfi1_names) |name| {
        if (globals.get(name)) |val| {
            try srfi1_lib.addExport(name, val);
        }
    }
    try registry.register(srfi1_lib);

    // SRFI-9
    const srfi9_lib = Library.init(allocator, "srfi.9");
    try registry.register(srfi9_lib);

    // SRFI-13
    const srfi13_names = [_][]const u8{
        "string-contains",   "string-prefix?",      "string-suffix?",
        "string-trim",       "string-trim-right",   "string-trim-both",
        "string-index",      "string-count",        "string-split",
        "string-join",       "string-concatenate",  "string-length",
        "string-append",     "substring",           "string-copy",
        "string-ref",        "string-set!",         "string<?",
        "string<=?",         "string=?",            "string>=?",
        "string>?",          "string-upcase",       "string-downcase",
        "string-foldcase",   "string-take",         "string-drop",
        "string-take-right", "string-drop-right",   "string-pad",
        "string-pad-right",  "string-reverse",      "string-filter",
        "string-delete",     "string-replace",      "string-titlecase",
        "string-every",      "string-any",          "string-tabulate",
        "string-unfold",     "string-unfold-right", "string-index-right",
        "string-skip",       "string-skip-right",
    };
    var srfi13_lib = Library.init(allocator, "srfi.13");
    for (srfi13_names) |name| {
        if (globals.get(name)) |val| {
            try srfi13_lib.addExport(name, val);
        }
    }
    try registry.register(srfi13_lib);

    // SRFI-39
    var srfi39_lib = Library.init(allocator, "srfi.39");
    if (globals.get("make-parameter")) |v| try srfi39_lib.addExport("make-parameter", v);
    try registry.register(srfi39_lib);

    // SRFI-69
    const srfi69_names = [_][]const u8{
        "make-hash-table",          "hash-table?",
        "hash-table-ref",           "hash-table-set!",
        "hash-table-delete!",       "hash-table-exists?",
        "hash-table-size",          "hash-table-keys",
        "hash-table-values",        "hash-table-walk",
        "hash-table->alist",        "alist->hash-table",
        "hash-table-copy",          "hash-table-update!/default",
        "hash",                     "string-hash",
        "string-ci-hash",           "hash-by-identity",
        "hash-table-ref/default",   "hash-table-fold",
        "hash-table-merge!",        "hash-table-equivalence-function",
        "hash-table-hash-function",
    };
    var srfi69_lib = Library.init(allocator, "srfi.69");
    for (srfi69_names) |name| {
        if (globals.get(name)) |val| {
            try srfi69_lib.addExport(name, val);
        }
    }
    try registry.register(srfi69_lib);

    // SRFI-133
    const srfi133_names = [_][]const u8{
        "vector",              "make-vector",              "vector?",             "vector-length",
        "vector-ref",          "vector-set!",              "vector->list",        "list->vector",
        "vector->string",      "string->vector",           "vector-fill!",        "vector-copy",
        "vector-copy!",        "vector-append",            "vector-for-each",     "vector-map",
        "vector-empty?",       "vector-count",             "vector-any",          "vector-every",
        "vector-index",        "vector-index-right",       "vector-skip",         "vector-skip-right",
        "vector-swap!",        "vector-reverse!",          "vector-reverse-copy", "vector-unfold",
        "vector-unfold-right", "vector-binary-search",     "vector-concatenate",  "vector-cumulate",
        "vector-partition",    "vector-append-subvectors",
    };
    var srfi133_lib = Library.init(allocator, "srfi.133");
    for (srfi133_names) |name| {
        if (globals.get(name)) |val| {
            try srfi133_lib.addExport(name, val);
        }
    }
    try registry.register(srfi133_lib);

    // SKIP: srfi.18 (OS threads blocked in sandbox to prevent thread bombs)

    // (kaappi fibers) — green threads (safe for sandbox)
    const kaappi_sb_fiber_names = [_][]const u8{
        "spawn",        "yield",        "fiber-join",      "fiber?",
        "make-channel", "channel-send", "channel-receive", "channel?",
    };
    var fiber_sb_lib = Library.init(allocator, "kaappi.fibers");
    for (kaappi_sb_fiber_names) |name| {
        if (globals.get(name)) |val| {
            try fiber_sb_lib.addExport(name, val);
        }
    }
    try registry.register(fiber_sb_lib);
}

/// Convert a library name from an S-expression list like (scheme base) to
/// a canonical dot-separated string like "scheme.base".
///
/// The caller owns the returned slice and must free it with `allocator.free`.
pub fn libraryNameToString(allocator: std.mem.Allocator, name_list: Value) ![]const u8 {
    // First pass: calculate total length
    var total_len: usize = 0;
    var part_count: usize = 0;
    var current = name_list;
    while (current != types.NIL) {
        if (!types.isPair(current)) return error.InvalidSyntax;
        const part = types.car(current);
        if (types.isSymbol(part)) {
            total_len += types.symbolName(part).len;
        } else if (types.isFixnum(part)) {
            // Count digits needed for the number
            var buf: [20]u8 = undefined;
            const s = std.fmt.bufPrint(&buf, "{d}", .{types.toFixnum(part)}) catch return error.InvalidSyntax;
            total_len += s.len;
        } else {
            return error.InvalidSyntax;
        }
        part_count += 1;
        current = types.cdr(current);
    }

    if (part_count == 0) return error.InvalidSyntax;
    total_len += part_count - 1; // dots between parts

    // Second pass: build the string
    var result = try allocator.alloc(u8, total_len);
    var pos: usize = 0;
    var first = true;
    current = name_list;
    while (current != types.NIL) {
        if (!first) {
            result[pos] = '.';
            pos += 1;
        }
        first = false;
        const part = types.car(current);
        if (types.isSymbol(part)) {
            const name = types.symbolName(part);
            @memcpy(result[pos .. pos + name.len], name);
            pos += name.len;
        } else if (types.isFixnum(part)) {
            var buf: [20]u8 = undefined;
            const s = std.fmt.bufPrint(&buf, "{d}", .{types.toFixnum(part)}) catch return error.InvalidSyntax;
            @memcpy(result[pos .. pos + s.len], s);
            pos += s.len;
        }
        current = types.cdr(current);
    }

    return result;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "library name to string" {
    const memory = @import("memory.zig");
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();

    // (scheme base) -> "scheme.base"
    const base_sym = try gc.allocSymbol("base");
    const scheme_sym = try gc.allocSymbol("scheme");
    const name_list = try gc.allocPair(scheme_sym, try gc.allocPair(base_sym, types.NIL));

    const result = try libraryNameToString(std.testing.allocator, name_list);
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("scheme.base", result);
}

test "library registry basic" {
    var reg = LibraryRegistry.init(std.testing.allocator);
    defer reg.deinit();

    var lib = Library.init(std.testing.allocator, "test.lib");
    try lib.addExport("foo", types.makeFixnum(42));
    try reg.register(lib);

    const found = reg.get("test.lib");
    try std.testing.expect(found != null);
    const val = found.?.exports.get("foo");
    try std.testing.expect(val != null);
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(val.?));
}

test "library name with number" {
    const memory = @import("memory.zig");
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();

    // (srfi 1) -> "srfi.1"
    const one_val = types.makeFixnum(1);
    const srfi_sym = try gc.allocSymbol("srfi");
    const name_list = try gc.allocPair(srfi_sym, try gc.allocPair(one_val, types.NIL));

    const result = try libraryNameToString(std.testing.allocator, name_list);
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("srfi.1", result);
}
