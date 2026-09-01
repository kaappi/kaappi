test {
    _ = @import("testing_helpers.zig");
    _ = @import("tests_core_eval.zig");
    _ = @import("tests_tail_calls.zig");
    _ = @import("tests_derived_forms.zig");
    _ = @import("tests_numeric.zig");
    _ = @import("tests_macros.zig");
    _ = @import("tests_macros_nested_sr.zig");
    _ = @import("tests_macros_procedural.zig");
    _ = @import("tests_ellipsis.zig");
    _ = @import("tests_macro_chains.zig");
    _ = @import("tests_prescan.zig");
    _ = @import("tests_circular_code.zig");
    _ = @import("tests_libraries.zig");
    _ = @import("tests_exceptions.zig");
    _ = @import("tests_records.zig");
    _ = @import("tests_io.zig");
    _ = @import("tests_printer.zig");
    _ = @import("printer_pretty.zig");
    _ = @import("tests_reader_incremental.zig");
    _ = @import("tests_continuations.zig");
    _ = @import("tests_advanced.zig");
    _ = @import("tests_filesystem.zig");
    _ = @import("tests_robustness.zig");
    _ = @import("tests_gc_root_boundary.zig");
    _ = @import("tests_gc_tracing.zig");
    _ = @import("tests_gc_runtime_stress.zig");
    _ = @import("tests_fuzz.zig");
    _ = @import("tests_deepcopy.zig");
    _ = @import("tests_shared_channel.zig");
    _ = @import("tests_shared_channel_rendezvous.zig");
    _ = @import("tests_ir.zig");
    _ = @import("tests_srfi18.zig");
    _ = @import("tests_srfi254.zig");
    _ = @import("tests_srfi258.zig");
    _ = @import("tests_srfi260.zig");
    _ = @import("tests_srfi248.zig");
    _ = @import("tests_srfi181.zig");
    _ = @import("tests_fibers.zig");
    _ = @import("tests_ffi.zig");
    _ = @import("tests_bytecode_cache.zig");
    _ = @import("tests_vm_library_cache.zig");
    _ = @import("tests_native.zig");
    _ = @import("tests_native_dispatch.zig");
    _ = @import("tests_native_gate.zig");
    // The fd-readiness suites run on every hosted target: their fds come
    // from testing_helpers' cross-platform pairs — pipes/socketpairs on
    // POSIX, loopback socket pairs on Windows, where these suites cover
    // the WSAEventSelect socket backend, and their "#1608:" pipe-pair
    // tests cover the polled pipe backend (stage 2). WASI is the one
    // exception — no constructible fd pairs there, the fd tests skip
    // (kaappi#2153) while the timer/scheduler halves still run under
    // wasmtime.
    _ = @import("tests_reactor.zig");
    // Audit v2 Phase 5G: the backend-parity contracts. Same per-OS legs, so
    // the assertions run against whichever of the four backends the target
    // has — that is the differential (see the file's own header).
    _ = @import("tests_reactor_parity.zig");
    _ = @import("tests_scheduler.zig");
    _ = @import("tests_port_io.zig");
    _ = @import("tests_waitforfd.zig");
    _ = @import("tests_random_port.zig");
    _ = @import("tests_diagnostics.zig");
    _ = @import("tests_spans.zig");
    _ = @import("tests_platform.zig");
    // (kaappi process), KEP-0022. One suite per OS backend, each skipping
    // wholesale on the other: the POSIX one spawns through /bin/sh, the
    // Windows one (Phase 3, kaappi#2416) through cmd.exe. Both are gated out
    // of the WASM build, where the specs are not registered at all.
    _ = @import("tests_process.zig");
    _ = @import("tests_process_win.zig");
    // Byte-order pins. The unit suite is one of only three things that runs
    // on the big-endian s390x leg, so this is where an endian assertion
    // actually reaches the canary (src/tests_endian.zig explains the rest).
    _ = @import("tests_endian.zig");
}
