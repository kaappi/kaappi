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

const primitives_mod = @import("primitives.zig");
const Lib = primitives_mod.Lib;
const LS = primitives_mod.LibSet;

const ExtraExport = struct { name: []const u8, libs: LS };

const extra_exports = [_]ExtraExport{
    .{ .name = "current-input-port", .libs = LS.initMany(&.{ .scheme_base, .scheme_r5rs }) },
    .{ .name = "current-output-port", .libs = LS.initMany(&.{ .scheme_base, .scheme_r5rs }) },
    .{ .name = "current-error-port", .libs = LS.initOne(.scheme_base) },
    .{ .name = "owner/unchanged", .libs = LS.initOne(.srfi_170) },
    .{ .name = "group/unchanged", .libs = LS.initOne(.srfi_170) },
};

fn addExportsForLib(library: *Library, lib: Lib, globals: *std.StringHashMap(Value), sandboxed: bool) !void {
    for (&primitives_mod.all_specs) |spec| {
        if (spec.libs.contains(lib) and (!sandboxed or spec.sandbox)) {
            if (globals.get(spec.name)) |val| {
                try library.addExport(spec.name, val);
            }
        }
    }
    for (&extra_exports) |extra| {
        if (extra.libs.contains(lib)) {
            if (globals.get(extra.name)) |val| {
                try library.addExport(extra.name, val);
            }
        }
    }
}

/// Standard libraries registered by name but with no Zig-primitive exports of
/// their own: their bindings are syntax already present in scheme.base
/// (`define-record-type` for srfi.9, `case-lambda` for scheme.case-lambda), so
/// the library object is just an importable handle. Kept as one list so the
/// normal and sandboxed registrars can't drift, and so `kaappi features` can
/// enumerate the built-in SRFIs (the `srfi.*` entries here plus the `srfi_*`
/// tags of `Lib`) without a second hardcoded list. All entries are pure syntax,
/// hence safe under `--sandbox` and on WASM.
pub const extra_std_libraries = [_][]const u8{ "scheme.case-lambda", "srfi.9" };

/// Register the standard R7RS libraries by deriving exports from spec tables.
pub fn registerStandardLibraries(registry: *LibraryRegistry, globals: *std.StringHashMap(Value)) !void {
    const allocator = registry.allocator;

    for (std.enums.values(Lib)) |lib| {
        if (!lib.isRegisterable()) continue;
        if (!is_wasm or lib.wasmAvailable()) {
            var library = Library.init(allocator, lib.canonicalName());
            try addExportsForLib(&library, lib, globals, false);
            try registry.register(library);
        }
    }

    for (extra_std_libraries) |name| {
        try registry.register(Library.init(allocator, name));
    }
}

pub fn registerSandboxedLibraries(registry: *LibraryRegistry, globals: *std.StringHashMap(Value)) !void {
    const allocator = registry.allocator;

    for (std.enums.values(Lib)) |lib| {
        if (!lib.isRegisterable()) continue;
        if (!lib.sandboxAllowed()) continue;
        if (!is_wasm or lib.wasmAvailable()) {
            var library = Library.init(allocator, lib.canonicalName());
            try addExportsForLib(&library, lib, globals, true);
            try registry.register(library);
        }
    }

    for (extra_std_libraries) |name| {
        try registry.register(Library.init(allocator, name));
    }
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
