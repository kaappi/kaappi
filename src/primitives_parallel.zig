const std = @import("std");
const is_wasm = @import("builtin").os.tag == .wasi;
const types = @import("types.zig");
const vm_mod = @import("vm.zig");
const primitives = @import("primitives.zig");
const Value = types.Value;
const PrimitiveError = primitives.PrimitiveError;
const LS = primitives.LibSet;

// KEP-0002 Phase 5 (#1470): the sole native primitive backing the portable
// `lib/kaappi/parallel.sld` library. Tagged `.kaappi_fibers` rather than a
// new `.kaappi_parallel` tag: every Lib enum tag also gets a same-named
// builtin Library registered at startup (library.zig registerStandardLibraries),
// and import checks that registry before ever touching disk
// (vm_library.zig processImportSet) -- a builtin "kaappi.parallel" library
// would permanently shadow the .sld and its pure-Scheme definitions would
// never load. `(kaappi fibers)` is already a mandatory import of the .sld
// (for channels/spawn), so `processor-count` rides along for free; the .sld
// re-exports it under `(kaappi parallel)` by naming it in `export` without
// redefining it -- the same trick lib/srfi/27.sld uses for
// random-integer/random-real (tagged .scheme_base there).
pub const specs = [_]primitives.PrimSpec{
    .{ .name = "processor-count", .func = &processorCountFn, .arity = .{ .exact = 0 }, .libs = LS.initOne(.kaappi_fibers) },
};

/// Returns 1 under WASM (no real OS threads) or `--sandbox` (thread
/// creation blocked) so pool-sizing code degrades to a single fiber worker
/// instead of erroring; otherwise the real hardware count via
/// std.Thread.getCpuCount, falling back to 1 if the OS query fails.
fn processorCountFn(args: []const Value) PrimitiveError!Value {
    _ = args;
    if (comptime is_wasm) return types.makeFixnum(1);
    if (vm_mod.vm_instance) |vm| {
        if (vm.sandbox_mode) return types.makeFixnum(1);
    }
    const n = std.Thread.getCpuCount() catch 1;
    return types.makeFixnum(@intCast(n));
}
