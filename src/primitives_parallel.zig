const std = @import("std");
const is_wasm = @import("builtin").os.tag == .wasi;
const build_options = @import("build_options");
const types = @import("types.zig");
const vm_mod = @import("vm.zig");
const primitives = @import("primitives.zig");
const instrument = @import("channel_instrument.zig");
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
const base_specs = [_]primitives.PrimSpec{
    .{ .name = "processor-count", .func = &processorCountFn, .arity = .{ .exact = 0 }, .libs = LS.initOne(.kaappi_fibers) },
};

// KEP-0002 Phase 7 gate-campaign harness hooks (kaappi#1472). Compiled in ONLY
// with `-Dchannel-instrument=true` (see the `specs` concat below), so the
// shipped (kaappi fibers) never carries these `%`-prefixed benchmark
// primitives. Tagged `.kaappi_fibers`, NOT `.internal`: `.internal` specs are
// bootstrap-only helpers that vm_bootstrap.install removes from globals after
// capture (#1375), but the harness calls these at runtime, so they must persist
// as ordinary (kaappi fibers) globals.
const instr_specs = [_]primitives.PrimSpec{
    .{ .name = "%chan-instr-reset!", .func = &chanInstrReset, .arity = .{ .exact = 0 }, .libs = LS.initOne(.kaappi_fibers) },
    .{ .name = "%chan-instr-submit-ns", .func = &chanInstrSubmitNs, .arity = .{ .exact = 0 }, .libs = LS.initOne(.kaappi_fibers) },
    .{ .name = "%chan-instr-result-ns", .func = &chanInstrResultNs, .arity = .{ .exact = 0 }, .libs = LS.initOne(.kaappi_fibers) },
    .{ .name = "%chan-instr-reassembly-begin!", .func = &chanInstrReassemblyBegin, .arity = .{ .exact = 0 }, .libs = LS.initOne(.kaappi_fibers) },
    .{ .name = "%chan-instr-reassembly-end!", .func = &chanInstrReassemblyEnd, .arity = .{ .exact = 0 }, .libs = LS.initOne(.kaappi_fibers) },
    .{ .name = "%chan-instr-reassembly-ns", .func = &chanInstrReassemblyNs, .arity = .{ .exact = 0 }, .libs = LS.initOne(.kaappi_fibers) },
    .{ .name = "%chan-instr-envelope-peak-bytes", .func = &chanInstrEnvelopePeakBytes, .arity = .{ .exact = 0 }, .libs = LS.initOne(.kaappi_fibers) },
    .{ .name = "%elision-lever-set!", .func = &elisionLeverSet, .arity = .{ .exact = 1 }, .libs = LS.initOne(.kaappi_fibers) },
};

pub const specs = base_specs ++ (if (build_options.channel_instrument) instr_specs else [0]primitives.PrimSpec{});

fn chanInstrReset(args: []const Value) PrimitiveError!Value {
    _ = args;
    instrument.reset();
    return types.VOID;
}

fn chanInstrSubmitNs(args: []const Value) PrimitiveError!Value {
    _ = args;
    return types.makeFixnum(@intCast(instrument.t_submit_ns));
}

fn chanInstrResultNs(args: []const Value) PrimitiveError!Value {
    _ = args;
    return types.makeFixnum(@intCast(instrument.t_result_ns));
}

fn chanInstrReassemblyBegin(args: []const Value) PrimitiveError!Value {
    _ = args;
    instrument.reassemblyBegin();
    return types.VOID;
}

fn chanInstrReassemblyEnd(args: []const Value) PrimitiveError!Value {
    _ = args;
    instrument.reassemblyEnd();
    return types.VOID;
}

fn chanInstrReassemblyNs(args: []const Value) PrimitiveError!Value {
    _ = args;
    return types.makeFixnum(@intCast(instrument.t_reassembly_ns));
}

fn chanInstrEnvelopePeakBytes(args: []const Value) PrimitiveError!Value {
    _ = args;
    return types.makeFixnum(@intCast(instrument.peakEnvelopeBytes()));
}

/// `(%elision-lever-set! 'none|'c|'cd)` -- selects the envelope elision lever
/// for subsequent sends/receives (protocol §2). Inert unless instrumented.
fn elisionLeverSet(args: []const Value) PrimitiveError!Value {
    if (!types.isPointer(args[0])) return PrimitiveError.TypeError;
    const obj = types.toObject(args[0]);
    if (obj.tag != .symbol) return PrimitiveError.TypeError;
    const name = obj.as(types.Symbol).name;
    const lever: instrument.Lever = if (std.mem.eql(u8, name, "none"))
        .none
    else if (std.mem.eql(u8, name, "c"))
        .c
    else if (std.mem.eql(u8, name, "cd"))
        .cd
    else
        return PrimitiveError.TypeError;
    instrument.setLever(lever);
    return types.VOID;
}

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
