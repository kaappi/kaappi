const std = @import("std");
const types = @import("types.zig");
const Value = types.Value;

/// A Scheme library: a named set of exported bindings.
pub const Library = struct {
    name: []const u8, // canonical name like "scheme.base"
    owned_name: ?[]const u8, // if non-null, this is a heap-allocated name to free
    exports: std.StringHashMap(Value),
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
    }

    /// Register a new library (or replace an existing one).
    pub fn register(self: *LibraryRegistry, lib: Library) !void {
        // If a library with this name already exists, deinit it first
        if (self.libraries.getPtr(lib.name)) |existing| {
            existing.deinit();
        }
        try self.libraries.put(lib.name, lib);
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
        "+",       "-",         "*",         "/",
        "quotient", "remainder", "modulo",
        "=",       "<",         ">",         "<=",        ">=",
        "zero?",   "positive?", "negative?", "abs",
        "min",     "max",       "even?",     "odd?",
        "gcd",     "lcm",
        // Rounding
        "floor",   "ceiling",   "truncate",  "round",
        // Exactness
        "exact?",  "inexact?",  "exact-integer?", "exact", "inexact",
        // Powers
        "expt",    "square",    "sqrt",
        // Pairs and lists
        "cons",    "car",       "cdr",       "set-car!",  "set-cdr!",
        "list",    "length",    "append",    "reverse",
        "caar",    "cadr",      "cdar",      "cddr",
        "list-ref", "list-tail", "list-set!", "list-copy", "make-list",
        "member",  "memq",      "memv",
        "assoc",   "assq",      "assv",
        // Higher-order list functions
        "map",     "for-each",
        // Type predicates
        "pair?",   "null?",     "number?",   "integer?",  "real?",
        "complex?", "rational?", "symbol?",  "string?",   "boolean?",
        "char?",   "procedure?", "list?",
        // Equivalence
        "eq?",     "eqv?",      "equal?",
        // Boolean
        "not",     "boolean=?", "symbol=?",
        // String operations
        "number->string", "string->number", "string-length",
        "string-append",  "symbol->string", "string->symbol",
        "string",  "make-string", "string-ref", "string-set!",
        "substring", "string-copy", "string-copy!", "string-fill!",
        "string->list", "list->string",
        "string-for-each", "string-map",
        "string<?", "string<=?", "string=?", "string>=?", "string>?",
        // Char operations (base library subset)
        "char->integer", "integer->char",
        "char<?", "char<=?", "char=?", "char>=?", "char>?",
        // I/O (also in scheme.write)
        "display", "write",     "newline",
        // Misc
        "apply",   "error",
        // Exception system (R7RS 6.11)
        "raise",   "raise-continuable",  "with-exception-handler",
        "error-object?",   "error-object-message",  "error-object-irritants",
        "file-error?",     "read-error?",
        // Record system internal primitives (used by define-record-type)
        "%make-record-type", "%make-record", "%record?", "%record-ref", "%record-set!",
        // Port and I/O (R7RS 6.13)
        "current-input-port", "current-output-port", "current-error-port",
        "port?", "input-port?", "output-port?", "textual-port?", "binary-port?",
        "input-port-open?", "output-port-open?",
        "close-port", "close-input-port", "close-output-port",
        "read-char", "peek-char", "read-line", "char-ready?",
        "write-char", "write-string",
        "eof-object?", "eof-object",
        // Continuations (R7RS 6.10)
        "call-with-current-continuation", "call/cc",
        "dynamic-wind",
        "values", "call-with-values",
        // Complex numbers
        "make-rectangular", "make-polar", "real-part", "imag-part",
        "magnitude", "angle",
        // Vectors (R7RS 6.8)
        "vector", "make-vector", "vector?", "vector-length",
        "vector-ref", "vector-set!", "vector->list", "list->vector",
        "vector-fill!", "vector-copy", "vector-copy!", "vector-append",
        "vector-for-each", "vector-map", "vector->string",
    };

    var base = Library.init(allocator, "scheme.base");
    for (scheme_base_names) |name| {
        if (globals.get(name)) |val| {
            try base.addExport(name, val);
        }
    }
    try registry.register(base);

    // (scheme write) — write/display procedures
    const scheme_write_names = [_][]const u8{ "display", "write", "newline", "write-char", "write-string" };
    var write_lib = Library.init(allocator, "scheme.write");
    for (scheme_write_names) |name| {
        if (globals.get(name)) |val| {
            try write_lib.addExport(name, val);
        }
    }
    try registry.register(write_lib);

    // (scheme inexact) — inexact math procedures
    const scheme_inexact_names = [_][]const u8{
        "sin",  "cos",  "tan",  "asin", "acos", "atan",
        "exp",  "log",  "sqrt",
        "finite?", "infinite?", "nan?",
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
        "char-alphabetic?", "char-numeric?", "char-whitespace?",
        "char-upper-case?", "char-lower-case?",
        "char-upcase", "char-downcase", "char-foldcase",
        "digit-value",
        "char-ci<?", "char-ci<=?", "char-ci=?", "char-ci>=?", "char-ci>?",
        "string-ci<?", "string-ci<=?", "string-ci=?", "string-ci>=?", "string-ci>?",
        "string-upcase", "string-downcase", "string-foldcase",
    };
    var char_lib = Library.init(allocator, "scheme.char");
    for (scheme_char_names) |name| {
        if (globals.get(name)) |val| {
            try char_lib.addExport(name, val);
        }
    }
    try registry.register(char_lib);

    // (scheme lazy) — placeholder
    const lazy_lib = Library.init(allocator, "scheme.lazy");
    try registry.register(lazy_lib);

    // (scheme time) — placeholder
    const time_lib = Library.init(allocator, "scheme.time");
    try registry.register(time_lib);

    // (scheme process-context) — placeholder
    const pc_lib = Library.init(allocator, "scheme.process-context");
    try registry.register(pc_lib);

    // (scheme file) — file I/O procedures
    const scheme_file_names = [_][]const u8{
        "open-input-file", "open-output-file",
        "file-exists?",
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
        "caar", "cadr", "cdar", "cddr",
        // Three-level
        "caaar", "caadr", "cadar", "caddr",
        "cdaar", "cdadr", "cddar", "cdddr",
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
