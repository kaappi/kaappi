//! Custom panic handler for the user-facing binaries (`kaappi`, `thottam`) —
//! kaappi#1514, part of the machine-legibility epic kaappi#1503.
//!
//! In ReleaseSafe (the shipped default) a bug *in the interpreter* dies with a
//! raw Zig panic and stack trace. The trace is the valuable part and is kept
//! verbatim; what this adds in front of it is the context that turns an
//! unreproducible report into an actionable one:
//!
//!   * which binary, and the fact that this is *our* bug, not the user's program;
//!   * version, target triple, and build mode (so a report names the exact build);
//!   * a breadcrumb naming the pipeline stage and file in flight when it died;
//!   * where to report it.
//!
//! Example:
//!
//!   kaappi internal error — this is a bug in kaappi, not in your program.
//!     version: v0.14.1 (aarch64-macos, ReleaseSafe)
//!     while:   compiling /path/to/file.scm
//!     report:  https://github.com/kaappi/kaappi/issues/new — include everything below.
//!
//!   thread 12345 panic: <message>
//!   <stack trace>
//!
//! **Installation.** Each binary's root file sets
//! `pub const panic = crash.PanicHandler("<name>")`. `PanicHandler` returns a
//! `std.debug.FullPanic` namespace whose `call` prints the banner and then
//! delegates to `std.debug.defaultPanic`, so every safety check, `unreachable`,
//! and `@panic` funnels through it with the standard message + trace intact.
//!
//! **The breadcrumb** (`noteStage` / `noteFile`) is updated by the top-level
//! driver at each pipeline stage boundary. It is deliberately trivial — a plain
//! enum store and a slice store, no allocation, no locking — matching the other
//! process-wide flags in this codebase (`ir.optimize_enabled`,
//! `main.script_had_error`, `toplevel_driver.diagnostic_format`). It is only ever
//! *read* from the panic handler, and only written on the single main pipeline
//! thread before any SRFI-18 worker exists for a given file, so a stale value at
//! worst mislabels a crash; it can never misdirect live execution. The stored
//! file slice is always a long-lived path (argv) or a string literal, so it can
//! never dangle at panic time.

const std = @import("std");
const platform = @import("platform.zig");
const builtin = @import("builtin");
const build_options = @import("build_options");

/// Arch and OS of this build, e.g. "aarch64-macos" — no ABI suffix, matching the
/// banner format. (`kaappi features` reports the full `arch-os-abi` triple; this
/// is the shorter human form for the crash line.) Comptime, so free at runtime.
const target = @tagName(builtin.cpu.arch) ++ "-" ++ @tagName(builtin.os.tag);

// ── Breadcrumb ───────────────────────────────────────────────────────────

/// The coarse pipeline stage in flight, updated at stage boundaries by the
/// top-level driver. Read only by the panic handler to render the `while:` line.
pub const Stage = enum {
    idle,
    reading,
    expanding,
    compiling,
    executing,

    /// Present-participle verb for the `while:` line.
    fn verb(self: Stage) []const u8 {
        return switch (self) {
            .idle => "starting up",
            .reading => "reading",
            .expanding => "expanding",
            .compiling => "compiling",
            .executing => "executing",
        };
    }
};

// Process-wide, single-writer (the main pipeline thread), read only at panic.
// Plain globals — no atomics — for the reasons in the module doc comment.
var current_stage: Stage = .idle;
var current_file: []const u8 = "";

/// Record the pipeline stage now in flight. Near-zero cost: a single store.
pub fn noteStage(stage: Stage) void {
    current_stage = stage;
}

/// Record the file (or a `<stdin>` / `<repl>` label) now being processed. The
/// slice must outlive the run; every caller passes a long-lived path or a string
/// literal, so the breadcrumb can never dangle when the panic handler reads it.
pub fn noteFile(path: []const u8) void {
    current_file = path;
}

/// Set stage and file together at a boundary that also names a new file.
pub fn note(stage: Stage, path: []const u8) void {
    current_file = path;
    current_stage = stage;
}

/// Reset to idle — e.g. the REPL returning to the prompt between inputs, so a
/// crash while idle at the prompt is not mislabeled as the last evaluation.
pub fn reset() void {
    current_stage = .idle;
    current_file = "";
}

// ── Panic handler ────────────────────────────────────────────────────────

/// Write straight to stderr with a raw syscall — a panic handler must not depend
/// on allocation or any subsystem that may itself be in the broken state that
/// triggered the panic. Mirrors `reporting.writeToFd` but is self-contained.
fn writeStderr(bytes: []const u8) void {
    var total: usize = 0;
    while (total < bytes.len) {
        const rc = platform.write(2, bytes.ptr + total, bytes.len - total);
        if (rc < 0) {
            if (platform.errno(rc) == .INTR) continue;
            return;
        }
        if (rc == 0) return;
        total += @intCast(rc);
    }
}

/// Print the crash banner: identity + build, the stage/file breadcrumb, and the
/// report URL. Everything but the breadcrumb is comptime-constant text. The
/// `while:` line is omitted entirely when the breadcrumb is still `idle` (a
/// pre-pipeline crash, or a binary like `thottam` with no Scheme pipeline) —
/// more honest than inventing a stage.
fn printBanner(comptime binary_name: []const u8) void {
    writeStderr("\n" ++ binary_name ++ " internal error — this is a bug in " ++
        binary_name ++ ", not in your program.\n" ++
        "  version: v" ++ build_options.version ++ " (" ++ target ++ ", " ++ @tagName(builtin.mode) ++ ")\n");

    if (current_stage != .idle) {
        writeStderr("  while:   ");
        writeStderr(current_stage.verb());
        if (current_file.len > 0) {
            writeStderr(" ");
            writeStderr(current_file);
        }
        writeStderr("\n");
    }

    writeStderr("  report:  https://github.com/kaappi/kaappi/issues/new — include everything below.\n\n");
}

/// Build the `pub const panic` namespace for a binary. The returned
/// `std.debug.FullPanic` prints our banner, then hands off to the standard panic
/// path so the message and full stack trace are preserved unchanged.
pub fn PanicHandler(comptime binary_name: []const u8) type {
    const Impl = struct {
        fn call(msg: []const u8, first_trace_addr: ?usize) noreturn {
            printBanner(binary_name);
            std.debug.defaultPanic(msg, first_trace_addr);
        }
    };
    return std.debug.FullPanic(Impl.call);
}

// ── Deliberate-panic test hook ───────────────────────────────────────────

/// Internal, undocumented hook that lets CI exercise the panic handler against a
/// real build (kaappi#1514 acceptance criterion). It is intentionally available
/// in *every* build mode — not gated to Debug — because the whole point is to
/// verify the banner the shipped **ReleaseSafe** binary prints (the mode the
/// example names); a Debug-only hook could never test that path. It is kept out
/// of `--help` and normal option parsing, and dispatched before any setup, so it
/// is never a user-facing surface.
///
/// `--panic-test[=<stage>]`: set a representative breadcrumb (the named stage, or
/// `executing` by default, with a synthetic file) and deliberately panic. Does
/// nothing and returns if the argument is absent, so the caller falls through to
/// normal dispatch.
pub fn maybePanicTest(args: std.process.Args) void {
    const flag = "--panic-test";
    var it = platform.argsIterate(args);
    _ = it.skip(); // argv[0]
    while (it.next()) |arg| {
        if (!std.mem.startsWith(u8, arg, flag)) continue;
        // Optional "=<stage>" selector so a test can assert the while: line
        // tracks the breadcrumb the pipeline set.
        const rest = arg[flag.len..];
        const stage: Stage = if (rest.len > 1 and rest[0] == '=')
            stageFromName(rest[1..]) orelse .executing
        else
            .executing;
        note(stage, "<panic-test>");
        @panic("deliberate panic: --panic-test crash-handler hook");
    }
}

/// The `Stage` whose tag is `name`, or null. Used only by the test hook.
fn stageFromName(name: []const u8) ?Stage {
    for (std.enums.values(Stage)) |s| {
        if (std.mem.eql(u8, name, @tagName(s))) return s;
    }
    return null;
}

// ── Tests ──────────────────────────────────────────────────────────────

const testing = std.testing;

test "stage verbs are present-participle and total" {
    try testing.expectEqualStrings("reading", Stage.reading.verb());
    try testing.expectEqualStrings("expanding", Stage.expanding.verb());
    try testing.expectEqualStrings("compiling", Stage.compiling.verb());
    try testing.expectEqualStrings("executing", Stage.executing.verb());
    try testing.expectEqualStrings("starting up", Stage.idle.verb());
}

test "stageFromName round-trips every tag and rejects unknowns" {
    for (std.enums.values(Stage)) |s| {
        try testing.expectEqual(@as(?Stage, s), stageFromName(@tagName(s)));
    }
    try testing.expect(stageFromName("nonsense") == null);
    try testing.expect(stageFromName("") == null);
}

test "breadcrumb note/noteStage/noteFile/reset update the globals" {
    defer reset();

    note(.compiling, "/tmp/foo.scm");
    try testing.expectEqual(Stage.compiling, current_stage);
    try testing.expectEqualStrings("/tmp/foo.scm", current_file);

    noteStage(.executing);
    try testing.expectEqual(Stage.executing, current_stage);
    try testing.expectEqualStrings("/tmp/foo.scm", current_file); // file unchanged

    noteFile("<stdin>");
    try testing.expectEqualStrings("<stdin>", current_file);
    try testing.expectEqual(Stage.executing, current_stage); // stage unchanged

    reset();
    try testing.expectEqual(Stage.idle, current_stage);
    try testing.expectEqualStrings("", current_file);
}

test "target string is arch-os with no abi suffix" {
    // Two components, exactly one '-' separating them (arch names never contain
    // one; "-none"/"-gnu" would add a second). Guards the banner's shorter form.
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, target, "-"));
    try testing.expect(std.mem.startsWith(u8, target, @tagName(builtin.cpu.arch)));
    try testing.expect(std.mem.endsWith(u8, target, @tagName(builtin.os.tag)));
}
