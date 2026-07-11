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
    _ = @import("tests_ir.zig");
    _ = @import("tests_srfi18.zig");
    _ = @import("tests_fibers.zig");
    _ = @import("tests_ffi.zig");
    _ = @import("tests_bytecode_cache.zig");
    _ = @import("tests_native.zig");
    _ = @import("tests_reactor.zig");
    _ = @import("tests_scheduler.zig");
    _ = @import("tests_port_io.zig");
}
