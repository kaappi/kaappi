//! Native primitives backing the portable SRFI 59 (Vicinity), SRFI 112
//! (Environment Inquiry), and SRFI 193 (Command line) `.sld` layers. Not
//! itself a SRFI -- just the small system-inquiry surface those three
//! portable libraries share, kept in one place since `%script-path` serves
//! both 59's `program-vicinity` and 193's `script-file`/`script-directory`.

const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");
const types = @import("types.zig");
const primitives = @import("primitives.zig");
const memory = @import("memory.zig");
const vm_mod = @import("vm.zig");
const Value = types.Value;
const PrimitiveError = primitives.PrimitiveError;
const LS = primitives.LibSet;

const SYSINFO = LS.initOne(.kaappi_sysinfo);

pub const specs = [_]primitives.PrimSpec{
    .{ .name = "%script-path", .func = &scriptPath, .arity = .{ .exact = 0 }, .libs = SYSINFO, .sandbox = false },
    .{ .name = "%implementation-version", .func = &implementationVersion, .arity = .{ .exact = 0 }, .libs = SYSINFO },
    .{ .name = "%os-name", .func = &osName, .arity = .{ .exact = 0 }, .libs = SYSINFO },
    .{ .name = "%cpu-architecture", .func = &cpuArchitecture, .arity = .{ .exact = 0 }, .libs = SYSINFO },
};

/// SRFI 59/193: the running script's absolute path (set once in
/// `main.runFile`), or `#f` when not running a script (REPL, stdin, or a
/// `load`ed/imported file).
fn scriptPath(args: []const Value) PrimitiveError!Value {
    _ = args;
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError; // bare-ok: no VM
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const path = vm.script_path orelse return types.FALSE;
    return gc.allocString(path) catch return PrimitiveError.OutOfMemory;
}

/// SRFI 112 `(implementation-version)`.
fn implementationVersion(args: []const Value) PrimitiveError!Value {
    _ = args;
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    return gc.allocString(build_options.version) catch return PrimitiveError.OutOfMemory;
}

/// SRFI 112 `(os-name)`. Reuses the exact comptime source `kaappi features`
/// already exposes (`features.zig`'s `target_triple`) rather than a new
/// uname()-style runtime lookup.
fn osName(args: []const Value) PrimitiveError!Value {
    _ = args;
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    return gc.allocString(@tagName(builtin.os.tag)) catch return PrimitiveError.OutOfMemory;
}

/// SRFI 112 `(cpu-architecture)`.
fn cpuArchitecture(args: []const Value) PrimitiveError!Value {
    _ = args;
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    return gc.allocString(@tagName(builtin.cpu.arch)) catch return PrimitiveError.OutOfMemory;
}
