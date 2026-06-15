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
        // Type predicates
        "pair?",   "null?",     "number?",   "integer?",  "real?",
        "complex?", "rational?", "symbol?",  "string?",   "boolean?",
        "char?",   "procedure?", "list?",
        // Equivalence
        "eq?",     "eqv?",      "equal?",
        // Boolean
        "not",
        // String operations
        "number->string", "string->number", "string-length",
        "string-append",  "symbol->string",
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
    };

    var base = Library.init(allocator, "scheme.base");
    for (scheme_base_names) |name| {
        if (globals.get(name)) |val| {
            try base.addExport(name, val);
        }
    }
    try registry.register(base);

    // (scheme write) — write/display procedures
    const scheme_write_names = [_][]const u8{ "display", "write", "newline" };
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

    // (scheme read) — placeholder
    const read_lib = Library.init(allocator, "scheme.read");
    try registry.register(read_lib);

    // (scheme char) — placeholder
    const char_lib = Library.init(allocator, "scheme.char");
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

    // (scheme cxr) — caar, cadr, cdar, cddr etc.
    // These are compositions of car/cdr — registered as placeholders for now
    const cxr_lib = Library.init(allocator, "scheme.cxr");
    try registry.register(cxr_lib);
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
