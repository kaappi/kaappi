//! The single authoritative description of the `kaappi` and `thottam`
//! command-line surfaces.
//!
//! Everything that needs to know what a flag is spelled, whether it takes a
//! value, or what it does reads *this* file:
//!
//!   * `cli.zig` — the global parse loop and `preScanSandbox`
//!   * `cli.printUsage` — the `Options:` block is generated from `global_flags`
//!   * `explain.zig`, `features.zig`, `doctor.zig`, `test_runner.zig`,
//!     `cache.zig` — each drives its own parse loop from its own table here
//!   * `thottam.zig` — same, from `thottam_flags`
//!   * `completions.zig` — generates all six shell scripts at comptime
//!
//! **Why this file exists.** The completion scripts used to be hand-written
//! lists of flags parallel to the parser's own, with nothing keeping them in
//! step — the same shape as `isRejectedFormHead` and the `%`-prefix incident.
//! They had drifted in both directions: `--no-ir-opt` was missing from all
//! three kaappi scripts, `kaappi test` grew five flags none of them offered,
//! and the zsh and fish scripts offered the whole global flag set inside
//! `explain`/`features`/`doctor`/`test`/`cache`, whose own parsers reject 15
//! of them with exit 2 (kaappi audit v2, Phase 6C).
//!
//! **The gate.** A flag cannot reach a parser without passing through a table
//! here, because every parse loop dispatches on an *exhaustive* `switch` over
//! that table's `Id` enum — add a variant and the compiler rejects the parser
//! until it handles it, and the completions pick the flag up for free. The
//! `comptime` block at the bottom additionally requires every `Id` variant to
//! appear exactly once in its table, so a variant cannot be added without a
//! row, and pins the description charset the shell generators assume.
//!
//! Descriptions are reused verbatim inside zsh `'…[desc]'` specs and fish
//! `-d '…'` strings, so `validate()` rejects any character that would need
//! quoting there. Keep them short, plain, and free of `[]:'"$\` and backticks.

const std = @import("std");

// ── Flag description ───────────────────────────────────────────────────

/// How a flag's value is spelled on the command line.
pub const ValueSyntax = enum {
    /// No value at all: `--sandbox`.
    none,
    /// A separate following argument: `--lib-path <path>`.
    separate,
    /// Attached with `=`, mandatory: `--diagnostics=json`. The bare spelling
    /// is *not* a flag (it falls through to "unknown option").
    inline_eq,
    /// Attached with `=`, or omitted: `--timings`, `--timings=json`.
    inline_eq_optional,
};

/// What a shell should offer for this flag's value.
pub const ValueKind = enum {
    /// Nothing to complete (no value, or an opaque one like a byte count).
    none,
    file,
    dir,
    /// One of `choices`.
    choice,
};

/// What a subcommand's positional arguments are, for completion purposes.
pub const Positional = enum {
    none,
    /// `*.scm` source files.
    scm_file,
    /// Any file or directory path.
    path,
    /// An opaque token (a diagnostic code) — nothing to complete.
    opaque_word,
    /// One of the subcommand's own `choices`.
    choice,
};

pub fn Flag(comptime Id: type) type {
    return struct {
        const Self = @This();

        long: []const u8,
        short: ?[]const u8 = null,
        id: Id,
        value: ValueSyntax = .none,
        kind: ValueKind = .none,
        choices: []const []const u8 = &.{},
        /// Placeholder in `--help` and in the "requires a …" usage error.
        value_name: []const u8 = "",
        desc: []const u8,
        /// Whether the flag belongs in the top-level `Options:` block and the
        /// top-level completion list. `--no-opt` and `--check` are accepted by
        /// the same global loop everywhere, but only mean anything under `ir`
        /// and `fmt`, so they are documented and offered there instead.
        top_level: bool = true,

        pub fn takesSeparateValue(self: Self) bool {
            return self.value == .separate;
        }

        /// `--lib-path <path>` / `--diagnostics=<fmt>` / `--timings[=fmt]`.
        pub fn spelling(comptime self: Self) []const u8 {
            const head = if (self.short) |s| s ++ ", " ++ self.long else self.long;
            return switch (self.value) {
                .none => head,
                .separate => head ++ " <" ++ self.value_name ++ ">",
                .inline_eq => head ++ "=<" ++ self.value_name ++ ">",
                .inline_eq_optional => head ++ "[=" ++ self.value_name ++ "]",
            };
        }
    };
}

pub fn Matched(comptime Id: type) type {
    return struct {
        flag: Flag(Id),
        /// The `=`-attached value, when the spelling carried one.
        inline_value: ?[]const u8,
    };
}

/// Recognize `arg` against `table`. The single entry point every parse loop
/// uses; there is deliberately no other way to spell a flag test.
pub fn match(comptime Id: type, comptime table: []const Flag(Id), arg: []const u8) ?Matched(Id) {
    inline for (table) |f| {
        switch (f.value) {
            .none, .separate => {
                if (std.mem.eql(u8, arg, f.long)) return .{ .flag = f, .inline_value = null };
                if (f.short) |s| {
                    if (std.mem.eql(u8, arg, s)) return .{ .flag = f, .inline_value = null };
                }
            },
            .inline_eq, .inline_eq_optional => {
                if (f.value == .inline_eq_optional and std.mem.eql(u8, arg, f.long)) {
                    return .{ .flag = f, .inline_value = null };
                }
                if (arg.len > f.long.len and
                    std.mem.startsWith(u8, arg, f.long) and
                    arg[f.long.len] == '=')
                {
                    return .{ .flag = f, .inline_value = arg[f.long.len + 1 ..] };
                }
            },
        }
    }
    return null;
}

// ── Shell-facing view ──────────────────────────────────────────────────

/// A `Flag` with its `Id` erased, so one list can hold flags from tables that
/// use different `Id` enums. Only `completions.zig` and `printUsage` consume
/// this; parsers always use the typed table so their switch stays exhaustive.
pub const ShellFlag = struct {
    long: []const u8,
    short: ?[]const u8,
    value: ValueSyntax,
    kind: ValueKind,
    choices: []const []const u8,
    value_name: []const u8,
    desc: []const u8,
    top_level: bool,

    pub fn spelling(comptime self: ShellFlag) []const u8 {
        const head = if (self.short) |s| s ++ ", " ++ self.long else self.long;
        return switch (self.value) {
            .none => head,
            .separate => head ++ " <" ++ self.value_name ++ ">",
            .inline_eq => head ++ "=<" ++ self.value_name ++ ">",
            .inline_eq_optional => head ++ "[=" ++ self.value_name ++ "]",
        };
    }
};

pub fn erase(comptime Id: type, comptime table: []const Flag(Id)) []const ShellFlag {
    comptime {
        var out: [table.len]ShellFlag = undefined;
        for (table, 0..) |f, i| out[i] = .{
            .long = f.long,
            .short = f.short,
            .value = f.value,
            .kind = f.kind,
            .choices = f.choices,
            .value_name = f.value_name,
            .desc = f.desc,
            .top_level = f.top_level,
        };
        const frozen = out;
        return &frozen;
    }
}

/// The subset of `global_flags` named by `ids`, erased. Used by the
/// subcommands `cli.parse` handles inline (`compile`, `check`, `ast`,
/// `expand`, `ir`, `fmt`): those go through the *same* global loop, so every
/// global flag is accepted there — this picks out the ones worth offering,
/// and referencing them by id means a renamed flag cannot go stale.
pub fn globalSubset(comptime ids: []const GlobalId) []const ShellFlag {
    comptime {
        const all = erase(GlobalId, &global_flags);
        var out: [ids.len]ShellFlag = undefined;
        for (ids, 0..) |want, i| {
            var found = false;
            for (global_flags, 0..) |g, j| {
                if (g.id == want) {
                    out[i] = all[j];
                    found = true;
                    break;
                }
            }
            if (!found) @compileError("globalSubset: no global flag with that id");
        }
        const frozen = out;
        return &frozen;
    }
}

pub const SubcommandDesc = struct {
    name: []const u8,
    desc: []const u8,
    flags: []const ShellFlag,
    positional: Positional = .none,
    choices: []const []const u8 = &.{},
    /// True for the subcommands whose arguments `cli.parse` consumes with the
    /// *global* flag table (so every global flag is legal after them). False
    /// for the five that intercept argv in their own module before `cli.parse`
    /// ever runs, and reject anything outside their own table with exit 2 —
    /// which is exactly why offering the global set inside them was a bug.
    global_flags_ok: bool = false,
};

// ── kaappi: global flags ───────────────────────────────────────────────

pub const GlobalId = enum {
    help,
    version_flag,
    completions_flag,
    lib_path,
    compile,
    emit_llvm,
    output,
    disassemble,
    diagnostics,
    deny_warnings,
    no_ir_opt,
    sandbox,
    gc_stats,
    profile,
    profile_json,
    timings,
    coverage,
    coverage_xml,
    timeout,
    max_memory,
    no_opt,
    check,
};

pub const shells = [_][]const u8{ "bash", "zsh", "fish" };
const fmts = [_][]const u8{ "text", "json" };

pub const global_flags = [_]Flag(GlobalId){
    .{ .long = "--help", .short = "-h", .id = .help, .desc = "Show this help message" },
    .{ .long = "--version", .id = .version_flag, .desc = "Show version" },
    .{ .long = "--lib-path", .id = .lib_path, .value = .separate, .kind = .dir, .value_name = "path", .desc = "Add a library search path (repeatable)" },
    .{ .long = "--compile", .id = .compile, .desc = "Compile the file to bytecode (.sbc)" },
    .{ .long = "--emit-llvm", .id = .emit_llvm, .desc = "Emit LLVM IR text (.ll)" },
    .{ .long = "-o", .id = .output, .value = .separate, .kind = .file, .value_name = "file", .desc = "Output path" },
    .{ .long = "--disassemble", .id = .disassemble, .desc = "Disassemble bytecode" },
    .{ .long = "--diagnostics", .id = .diagnostics, .value = .inline_eq, .kind = .choice, .choices = &fmts, .value_name = "fmt", .desc = "Diagnostic output format, text (default) or json" },
    .{ .long = "--deny-warnings", .id = .deny_warnings, .desc = "(check) Treat lint warnings as errors for the exit code" },
    .{ .long = "--no-ir-opt", .id = .no_ir_opt, .desc = "Disable IR optimization passes (skips the .sbc cache)" },
    .{ .long = "--sandbox", .id = .sandbox, .desc = "Restrict filesystem and process access" },
    .{ .long = "--gc-stats", .id = .gc_stats, .desc = "Print GC statistics on exit" },
    .{ .long = "--profile", .id = .profile, .desc = "Enable profiling" },
    .{ .long = "--profile-json", .id = .profile_json, .value = .separate, .kind = .file, .value_name = "file", .desc = "Write profile JSON to a file" },
    .{ .long = "--timings", .id = .timings, .value = .inline_eq_optional, .kind = .choice, .choices = &fmts, .value_name = "fmt", .desc = "Report per-stage timings and cache hits on stderr" },
    .{ .long = "--coverage", .id = .coverage, .desc = "Report library procedure coverage" },
    .{ .long = "--coverage-xml", .id = .coverage_xml, .value = .separate, .kind = .file, .value_name = "file", .desc = "Write Cobertura XML coverage to a file" },
    .{ .long = "--timeout", .id = .timeout, .value = .separate, .value_name = "ms", .desc = "Execution timeout in milliseconds" },
    .{ .long = "--max-memory", .id = .max_memory, .value = .separate, .value_name = "bytes", .desc = "Maximum heap memory in bytes" },
    .{ .long = "--completions", .id = .completions_flag, .value = .separate, .kind = .choice, .choices = &shells, .value_name = "shell", .desc = "Output a shell completion script" },
    // Subcommand-scoped: accepted by the same global loop anywhere, but only
    // meaningful under `ir` / `fmt`, so they are offered and documented there.
    .{ .long = "--no-opt", .id = .no_opt, .top_level = false, .desc = "(ir) Show the IR before the optimization passes" },
    .{ .long = "--check", .id = .check, .top_level = false, .desc = "(fmt) Report files needing formatting without writing" },
};

// ── kaappi: out-of-line subcommand flags ───────────────────────────────
//
// These five subcommands intercept argv in their own module, before
// `cli.parse` runs, and reject anything outside their own table.

pub const ExplainId = enum { json, all, help };
pub const explain_flags = [_]Flag(ExplainId){
    .{ .long = "--json", .id = .json, .desc = "Machine-readable output" },
    .{ .long = "--all", .id = .all, .desc = "Explain every diagnostic code" },
    .{ .long = "--help", .short = "-h", .id = .help, .desc = "Show this help message" },
};

pub const FeaturesId = enum { json, help };
pub const features_flags = [_]Flag(FeaturesId){
    .{ .long = "--json", .id = .json, .desc = "Machine-readable output" },
    .{ .long = "--help", .short = "-h", .id = .help, .desc = "Show this help message" },
};

pub const DoctorId = enum { json, lib_path, help };
pub const doctor_flags = [_]Flag(DoctorId){
    .{ .long = "--json", .id = .json, .desc = "Machine-readable output" },
    .{ .long = "--lib-path", .id = .lib_path, .value = .separate, .kind = .dir, .value_name = "path", .desc = "Add a library search path (repeatable)" },
    .{ .long = "--help", .short = "-h", .id = .help, .desc = "Show this help message" },
};

pub const TestId = enum { json, seed, lib_path, jobs, changed, list_affected, since, help };
pub const test_flags = [_]Flag(TestId){
    .{ .long = "--json", .id = .json, .desc = "Machine-readable output" },
    .{ .long = "--seed", .id = .seed, .value = .separate, .value_name = "n", .desc = "Pin the run seed for reproducibility" },
    .{ .long = "--lib-path", .id = .lib_path, .value = .separate, .kind = .dir, .value_name = "path", .desc = "Add a library search path (repeatable)" },
    .{ .long = "--jobs", .short = "-j", .id = .jobs, .value = .separate, .value_name = "n", .desc = "Run n files concurrently (default one per CPU)" },
    .{ .long = "--changed", .id = .changed, .desc = "Run only the suites whose import closure changed" },
    .{ .long = "--list-affected", .id = .list_affected, .desc = "Print the affected suites without running them" },
    .{ .long = "--since", .id = .since, .value = .separate, .value_name = "rev", .desc = "Revision the change set is diffed against" },
    .{ .long = "--help", .short = "-h", .id = .help, .desc = "Show this help message" },
};

pub const CacheId = enum { help };
pub const cache_flags = [_]Flag(CacheId){
    .{ .long = "--help", .short = "-h", .id = .help, .desc = "Show this help message" },
};
pub const cache_actions = [_][]const u8{ "status", "clear" };
/// Named so `cache.zig` compares against a spelling rather than a position.
pub const cache_status = cache_actions[0];
pub const cache_clear = cache_actions[1];

// ── kaappi: the subcommand table ───────────────────────────────────────

pub const subcommands = [_]SubcommandDesc{
    .{ .name = "compile", .desc = "Compile to a native binary via LLVM", .global_flags_ok = true, .positional = .scm_file, .flags = globalSubset(&.{ .output, .lib_path }) },
    .{ .name = "check", .desc = "Compile-only static analysis, nothing is executed", .global_flags_ok = true, .positional = .scm_file, .flags = globalSubset(&.{ .diagnostics, .deny_warnings, .lib_path }) },
    .{ .name = "explain", .desc = "Explain a diagnostic code such as KP3001", .positional = .opaque_word, .flags = erase(ExplainId, &explain_flags) },
    .{ .name = "features", .desc = "Report the capabilities of this build", .flags = erase(FeaturesId, &features_flags) },
    .{ .name = "test", .desc = "Run SRFI-64 test suites", .positional = .path, .flags = erase(TestId, &test_flags) },
    .{ .name = "ast", .desc = "Print post-read datums (read plus write)", .global_flags_ok = true, .positional = .scm_file, .flags = globalSubset(&.{.lib_path}) },
    .{ .name = "expand", .desc = "Print the program after full macro expansion", .global_flags_ok = true, .positional = .scm_file, .flags = globalSubset(&.{.lib_path}) },
    .{ .name = "ir", .desc = "Print the IR tree", .global_flags_ok = true, .positional = .scm_file, .flags = globalSubset(&.{ .no_opt, .lib_path }) },
    .{ .name = "doctor", .desc = "Check the installation and environment", .flags = erase(DoctorId, &doctor_flags) },
    .{ .name = "fmt", .desc = "Canonically format Scheme source in place", .global_flags_ok = true, .positional = .path, .flags = globalSubset(&.{.check}) },
    .{ .name = "cache", .desc = "Inspect or clear the bytecode cache", .positional = .choice, .choices = &cache_actions, .flags = erase(CacheId, &cache_flags) },
};

/// The subcommand words `cli.parse` and `preScanSandbox` consume themselves.
/// Derived, so a new inline subcommand cannot be added to one and forgotten in
/// the other — which is how `preScanSandbox` would stop seeing a later
/// `--sandbox`.
pub fn isInlineSubcommand(arg: []const u8) bool {
    inline for (subcommands) |s| {
        if (s.global_flags_ok and std.mem.eql(u8, arg, s.name)) return true;
    }
    return false;
}

// ── thottam ────────────────────────────────────────────────────────────

pub const ThottamId = enum { locked, help, version_flag, completions_flag };
pub const thottam_flags = [_]Flag(ThottamId){
    .{ .long = "--locked", .id = .locked, .desc = "Refuse to install packages not in the lockfile" },
    .{ .long = "--help", .short = "-h", .id = .help, .desc = "Show this help message" },
    .{ .long = "--version", .id = .version_flag, .desc = "Show version" },
    .{ .long = "--completions", .id = .completions_flag, .value = .separate, .kind = .choice, .choices = &shells, .value_name = "shell", .desc = "Output a shell completion script" },
};

// thottam parses every flag in one flat loop that keeps scanning past the
// subcommand word, so `thottam install --locked pkg` is as valid as
// `thottam --locked install pkg`: every subcommand accepts the whole flag set.
pub const thottam_subcommands = [_]SubcommandDesc{
    .{ .name = "install", .desc = "Install a package", .positional = .opaque_word, .global_flags_ok = true, .flags = &.{} },
    .{ .name = "remove", .desc = "Remove a package", .positional = .opaque_word, .global_flags_ok = true, .flags = &.{} },
    .{ .name = "list", .desc = "List installed packages", .global_flags_ok = true, .flags = &.{} },
    .{ .name = "update", .desc = "Update one or all packages", .positional = .opaque_word, .global_flags_ok = true, .flags = &.{} },
    .{ .name = "verify", .desc = "Check installs match the lockfile", .global_flags_ok = true, .flags = &.{} },
};

// ── Comptime validation ────────────────────────────────────────────────

fn validateTable(comptime Id: type, comptime table: []const Flag(Id), comptime what: []const u8) void {
    comptime {
        @setEvalBranchQuota(100_000);
        // Every Id variant appears exactly once: a new variant without a row
        // is a compile error, so the table can never lag the enum.
        for (@typeInfo(Id).@"enum".fields) |field| {
            var seen = 0;
            for (table) |f| {
                if (@intFromEnum(f.id) == field.value) seen += 1;
            }
            if (seen != 1) @compileError(what ++ ": " ++ field.name ++ " must appear exactly once in the table");
        }
        for (table, 0..) |f, i| {
            if (f.long.len < 2 or f.long[0] != '-') @compileError(what ++ ": flag spellings must start with '-'");
            if (f.takesSeparateValue() and f.value_name.len == 0) @compileError(what ++ ": " ++ f.long ++ " takes a value but names none");
            if (f.kind == .choice and f.choices.len == 0) @compileError(what ++ ": " ++ f.long ++ " completes a choice but lists none");
            // Descriptions land verbatim inside zsh '…[desc]' specs and fish
            // -d '…' strings; anything needing quoting there would silently
            // produce a broken script.
            for (f.desc) |c| {
                if (c < 0x20 or c > 0x7e) @compileError(what ++ ": " ++ f.long ++ " description must be printable ASCII");
                switch (c) {
                    '[', ']', ':', '\'', '"', '$', '\\', '`' => @compileError(what ++ ": " ++ f.long ++ " description must not need shell or zsh quoting"),
                    else => {},
                }
            }
            for (table[i + 1 ..]) |g| {
                if (std.mem.eql(u8, f.long, g.long)) @compileError(what ++ ": duplicate flag " ++ f.long);
            }
        }
    }
}

comptime {
    validateTable(GlobalId, &global_flags, "global_flags");
    validateTable(ExplainId, &explain_flags, "explain_flags");
    validateTable(FeaturesId, &features_flags, "features_flags");
    validateTable(DoctorId, &doctor_flags, "doctor_flags");
    validateTable(TestId, &test_flags, "test_flags");
    validateTable(CacheId, &cache_flags, "cache_flags");
    validateTable(ThottamId, &thottam_flags, "thottam_flags");

    // Every subcommand's own flags must be a *sound* offer: a flag a
    // subcommand's parser would reject must never be completed for it. For the
    // five out-of-line subcommands `flags` IS the parser's table, so soundness
    // is definitional; for the inline ones `globalSubset` can only name ids
    // that exist, and every global flag is legal after them. This pins the one
    // remaining way to get it wrong — a hand-written entry.
    for (subcommands ++ thottam_subcommands) |s| {
        if (s.positional == .choice and s.choices.len == 0) {
            @compileError("subcommand " ++ s.name ++ " completes a choice but lists none");
        }
        for (s.desc) |c| {
            if (c < 0x20 or c > 0x7e) @compileError("subcommand " ++ s.name ++ " description must be printable ASCII");
            switch (c) {
                '[', ']', ':', '\'', '"', '$', '\\', '`' => @compileError("subcommand " ++ s.name ++ " description must not need shell or zsh quoting"),
                else => {},
            }
        }
    }
}

// ── Tests ──────────────────────────────────────────────────────────────

test "match: exact long and short spellings" {
    try std.testing.expect(match(GlobalId, &global_flags, "--sandbox").?.flag.id == .sandbox);
    try std.testing.expect(match(GlobalId, &global_flags, "-h").?.flag.id == .help);
    try std.testing.expect(match(GlobalId, &global_flags, "-o").?.flag.id == .output);
    try std.testing.expect(match(GlobalId, &global_flags, "--nope") == null);
}

test "match: inline_eq requires the =" {
    const d = match(GlobalId, &global_flags, "--diagnostics=json").?;
    try std.testing.expect(d.flag.id == .diagnostics);
    try std.testing.expectEqualStrings("json", d.inline_value.?);
    // Bare `--diagnostics` is not a flag — it must reach "unknown option".
    try std.testing.expect(match(GlobalId, &global_flags, "--diagnostics") == null);
    // An empty value still matches, so the format parser can name it.
    try std.testing.expectEqualStrings("", match(GlobalId, &global_flags, "--diagnostics=").?.inline_value.?);
}

test "match: inline_eq_optional accepts both spellings" {
    try std.testing.expect(match(GlobalId, &global_flags, "--timings").?.inline_value == null);
    try std.testing.expectEqualStrings("json", match(GlobalId, &global_flags, "--timings=json").?.inline_value.?);
}

test "match: --timeout is not a prefix match for --timings" {
    try std.testing.expect(match(GlobalId, &global_flags, "--timeout").?.flag.id == .timeout);
    try std.testing.expect(match(GlobalId, &global_flags, "--timings-x") == null);
}

test "isInlineSubcommand: exactly the ones cli.parse consumes" {
    for ([_][]const u8{ "compile", "check", "ast", "expand", "ir", "fmt" }) |s| {
        try std.testing.expect(isInlineSubcommand(s));
    }
    for ([_][]const u8{ "explain", "features", "test", "doctor", "cache", "nope" }) |s| {
        try std.testing.expect(!isInlineSubcommand(s));
    }
}

test "subcommand table names every subcommand printUsage documents" {
    try std.testing.expectEqual(@as(usize, 11), subcommands.len);
}
