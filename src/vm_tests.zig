test {
    _ = @import("testing_helpers.zig");
    _ = @import("tests_core_eval.zig");
    _ = @import("tests_tail_calls.zig");
    _ = @import("tests_derived_forms.zig");
    _ = @import("tests_numeric.zig");
    _ = @import("tests_macros.zig");
    _ = @import("tests_libraries.zig");
    _ = @import("tests_exceptions.zig");
    _ = @import("tests_records.zig");
    _ = @import("tests_io.zig");
    _ = @import("tests_continuations.zig");
    _ = @import("tests_advanced.zig");
    _ = @import("tests_filesystem.zig");
    _ = @import("tests_robustness.zig");
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
    _ = @import("tests_native.zig");
    _ = @import("tests_native_dispatch.zig");
    _ = @import("tests_native_gate.zig");
    // The fd-readiness suites run everywhere: their fds come from
    // testing_helpers' cross-platform pairs — pipes/socketpairs on POSIX,
    // loopback socket pairs on Windows, where these suites cover the
    // WSAEventSelect socket backend, and their "#1608:" pipe-pair tests
    // cover the polled pipe backend (stage 2).
    _ = @import("tests_reactor.zig");
    _ = @import("tests_scheduler.zig");
    _ = @import("tests_port_io.zig");
    _ = @import("tests_random_port.zig");
    _ = @import("tests_diagnostics.zig");
    _ = @import("tests_spans.zig");
    _ = @import("tests_platform.zig");
}
