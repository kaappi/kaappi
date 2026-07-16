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
    _ = @import("tests_fibers.zig");
    _ = @import("tests_ffi.zig");
    _ = @import("tests_bytecode_cache.zig");
    _ = @import("tests_native.zig");
    _ = @import("tests_native_dispatch.zig");
    _ = @import("tests_native_gate.zig");
    // fd-readiness suites are POSIX-only by design: Windows ports never
    // flip to non-blocking (platform.zig), so the reactor there is
    // timer/notify-only and these suites' pipe plumbing has nothing to
    // exercise.
    if (comptime @import("platform.zig").is_windows == false) {
        _ = @import("tests_reactor.zig");
        _ = @import("tests_scheduler.zig");
        _ = @import("tests_port_io.zig");
    }
    _ = @import("tests_diagnostics.zig");
    _ = @import("tests_spans.zig");
}
