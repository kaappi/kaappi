//! Native primitives backing the portable SRFI 59 (Vicinity), SRFI 112
//! (Environment Inquiry), and SRFI 193 (Command line) `.sld` layers. Not
//! itself a SRFI -- just the small system-inquiry surface those three
//! portable libraries share, kept in one place since `%script-path` serves
//! both 59's `program-vicinity` and 193's `script-file`/`script-directory`,
//! and `%current-lib-dir` (also 59's `program-vicinity`) reuses the VM's
//! existing "currently loading file" tracking (`vm.current_lib_dir`).

const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");
const types = @import("types.zig");
const primitives = @import("primitives.zig");
const memory = @import("memory.zig");
const vm_mod = @import("vm.zig");
const vm_library = @import("vm_library.zig");
const kaappi_paths = @import("kaappi_paths.zig");
const Value = types.Value;
const PrimitiveError = primitives.PrimitiveError;
const LS = primitives.LibSet;

const SYSINFO = LS.initOne(.kaappi_sysinfo);

pub const specs = [_]primitives.PrimSpec{
    .{ .name = "%script-path", .func = &scriptPath, .arity = .{ .exact = 0 }, .libs = SYSINFO, .sandbox = false },
    .{ .name = "%current-lib-dir", .func = &currentLibDir, .arity = .{ .exact = 0 }, .libs = SYSINFO, .sandbox = false },
    .{ .name = "%kaappi-lib-dir", .func = &kaappiLibDir, .arity = .{ .exact = 0 }, .libs = SYSINFO, .sandbox = false },
    .{ .name = "%implementation-dir", .func = &implementationDir, .arity = .{ .exact = 0 }, .libs = SYSINFO, .sandbox = false },
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

/// SRFI 59 `program-vicinity`: the directory of whatever file is currently
/// loading -- `vm.current_lib_dir`, already maintained (save/restore around
/// each nested `.sld`/`include`/`load`) as "the currently loading file's
/// directory" for library-path resolution. Already vicinity-shaped (trailing
/// separator or ""), so no `pathname->vicinity` post-processing is needed.
/// `#f` when nothing is currently loading (a plain REPL/stdin session that
/// hasn't called `load`), matching the SRFI's own "undefined" carve-out with
/// this library's established #f-for-inapplicable convention.
fn currentLibDir(args: []const Value) PrimitiveError!Value {
    _ = args;
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError; // bare-ok: no VM
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const dir = vm.current_lib_dir orelse return types.FALSE;
    return gc.allocString(dir) catch return PrimitiveError.OutOfMemory;
}

/// SRFI 59 `library-vicinity`: the shared, cross-project Scheme library
/// directory -- `~/.kaappi/lib` (`$KAAPPI_HOME/lib`), where thottam installs
/// ecosystem packages and which `main.zig` already adds to the library
/// search path regardless of `--lib-path` (see the workspace `CLAUDE.md`'s
/// "Auto-discovery" section). `#f` when no home directory is available
/// (e.g. a daemon-like environment with neither `KAAPPI_HOME`/`HOME` nor,
/// on Windows, `USERPROFILE` set) -- the SRFI reserves exactly this "not
/// applicable on this platform" case for `#f` via `home-vicinity`'s own
/// text, which `getHome` is built on.
fn kaappiLibDir(args: []const Value) PrimitiveError!Value {
    _ = args;
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    var buf: [1024]u8 = undefined;
    const home = kaappi_paths.getHome(&buf) orelse return types.FALSE;
    var out_buf: [1040]u8 = undefined;
    const with_suffix = std.fmt.bufPrint(&out_buf, "{s}/lib/", .{home}) catch return types.FALSE;
    return gc.allocString(with_suffix) catch return PrimitiveError.OutOfMemory;
}

/// SRFI 59 `implementation-vicinity`: the directory containing the running
/// `kaappi` executable itself -- the closest Kaappi analogue to the spec's
/// "will likely contain startup code and messages and a compiler" (kaappi's
/// own compiler is `kaappi compile`, built into this same binary, not a
/// separate installed tool). `#f` when this platform has no self-exe-path
/// lookup (`kaappi_paths.getExePath`, used identically for exe-relative
/// library discovery) rather than a misleading "current directory" guess.
fn implementationDir(args: []const Value) PrimitiveError!Value {
    _ = args;
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    var buf: [1024]u8 = undefined;
    const exe_path = kaappi_paths.getExePath(&buf) orelse return types.FALSE;
    const dir = vm_library.extractDir(exe_path);
    if (dir.len == 0) return types.FALSE;
    return gc.allocString(dir) catch return PrimitiveError.OutOfMemory;
}

/// SRFI 112 `(implementation-version)`.
fn implementationVersion(args: []const Value) PrimitiveError!Value {
    _ = args;
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    return gc.allocString(build_options.version) catch return PrimitiveError.OutOfMemory;
}

/// SRFI 112 `(os-name)`. Returns `builtin.os.tag` directly -- the same
/// comptime source `features.zig`'s `target_triple` is itself built from
/// (`target_triple` concatenates arch-os-abi, which isn't the bare OS name
/// this procedure needs) -- rather than a new uname()-style runtime lookup.
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
