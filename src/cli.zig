const std = @import("std");
const platform = @import("platform.zig");
const completions = @import("completions.zig");
const reporting = @import("reporting.zig");

pub const version = @import("build_options").version;

pub const USAGE_ERROR_EXIT: u8 = 2;

const writeStdout = reporting.writeStdout;
const writeStderr = reporting.writeStderr;

// `--diagnostics=<format>` uses GNU `=` syntax (not a space-separated value like
// the other value flags), so it is matched by prefix rather than via the flag
// table. Kept as a named constant so the parse loop and the sandbox pre-scan
// agree on the spelling.
const diagnostics_prefix = "--diagnostics=";

// `--timings[=fmt]` accepts a bare form (`--timings`, text) and the GNU `=`
// value form (`--timings=json`), so — like `--diagnostics=` — it is matched
// outside the value-flag table. Same spelling shared by parse + sandbox pre-scan.
const timings_prefix = "--timings=";

// ── Flag table ─────────────────────────────────────────────────────────

const FlagId = enum {
    help,
    version_flag,
    completions_flag,
    lib_path,
    compile,
    emit_llvm,
    output,
    disassemble,
    no_ir_opt,
    sandbox,
    gc_stats,
    profile,
    profile_json,
    coverage,
    coverage_xml,
    timeout,
    max_memory,
    deny_warnings,
    no_opt,
    check,
};

const FlagDesc = struct {
    long: []const u8,
    short: ?[]const u8,
    takes_value: bool,
    id: FlagId,
    value_name: []const u8,
};

const flags = [_]FlagDesc{
    .{ .long = "--help", .short = "-h", .takes_value = false, .id = .help, .value_name = "" },
    .{ .long = "--version", .short = null, .takes_value = false, .id = .version_flag, .value_name = "" },
    .{ .long = "--completions", .short = null, .takes_value = true, .id = .completions_flag, .value_name = "shell name (bash, zsh, fish)" },
    .{ .long = "--lib-path", .short = null, .takes_value = true, .id = .lib_path, .value_name = "path" },
    .{ .long = "--compile", .short = null, .takes_value = false, .id = .compile, .value_name = "" },
    .{ .long = "--emit-llvm", .short = null, .takes_value = false, .id = .emit_llvm, .value_name = "" },
    .{ .long = "-o", .short = null, .takes_value = true, .id = .output, .value_name = "file path" },
    .{ .long = "--disassemble", .short = null, .takes_value = false, .id = .disassemble, .value_name = "" },
    .{ .long = "--no-ir-opt", .short = null, .takes_value = false, .id = .no_ir_opt, .value_name = "" },
    .{ .long = "--sandbox", .short = null, .takes_value = false, .id = .sandbox, .value_name = "" },
    .{ .long = "--gc-stats", .short = null, .takes_value = false, .id = .gc_stats, .value_name = "" },
    .{ .long = "--profile", .short = null, .takes_value = false, .id = .profile, .value_name = "" },
    .{ .long = "--profile-json", .short = null, .takes_value = true, .id = .profile_json, .value_name = "file path" },
    .{ .long = "--coverage", .short = null, .takes_value = false, .id = .coverage, .value_name = "" },
    .{ .long = "--coverage-xml", .short = null, .takes_value = true, .id = .coverage_xml, .value_name = "file path" },
    .{ .long = "--timeout", .short = null, .takes_value = true, .id = .timeout, .value_name = "milliseconds" },
    .{ .long = "--max-memory", .short = null, .takes_value = true, .id = .max_memory, .value_name = "bytes" },
    .{ .long = "--deny-warnings", .short = null, .takes_value = false, .id = .deny_warnings, .value_name = "" },
    .{ .long = "--no-opt", .short = null, .takes_value = false, .id = .no_opt, .value_name = "" },
    .{ .long = "--check", .short = null, .takes_value = false, .id = .check, .value_name = "" },
};

fn lookupFlag(arg: []const u8) ?FlagDesc {
    inline for (flags) |f| {
        if (std.mem.eql(u8, arg, f.long)) return f;
        if (f.short) |s| {
            if (std.mem.eql(u8, arg, s)) return f;
        }
    }
    return null;
}

// ── Options ────────────────────────────────────────────────────────────

pub const DiagnosticsFormat = enum { text, json };

pub const Options = struct {
    file_path: ?[]const u8 = null,

    diagnostics_format: DiagnosticsFormat = .text,

    compile_mode: bool = false,
    native_compile_mode: bool = false,
    emit_llvm_mode: bool = false,
    disassemble_mode: bool = false,
    check_mode: bool = false,
    deny_warnings: bool = false,

    // Pipeline-stage dumps (kaappi#1512): `kaappi ast|expand|ir <file>`.
    ast_mode: bool = false,
    expand_mode: bool = false,
    ir_mode: bool = false,
    ir_no_opt: bool = false,

    // Canonical formatter (kaappi#1518): `kaappi fmt [--check] files...`.
    fmt_mode: bool = false,
    fmt_check: bool = false,

    compile_output: ?[]const u8 = null,

    gc_stats_mode: bool = false,
    profile_mode: bool = false,
    profile_json_path: ?[]const u8 = null,
    coverage_mode: bool = false,
    coverage_xml_path: ?[]const u8 = null,

    // Per-stage pipeline timings + cache HIT/MISS (kaappi#1515). `--timings`
    // (text) or `--timings=json`; parsed like `--diagnostics=` (GNU `=` syntax)
    // but with a bare form too.
    timings_enabled: bool = false,
    timings_json: bool = false,

    timeout_ms: ?u64 = null,
    max_memory: ?usize = null,

    sandbox_mode: bool = false,
    no_ir_opt: bool = false,

    lib_path_buf: [16][]const u8 = undefined,
    lib_path_count: usize = 0,

    /// The script path plus every argument after it, in argv order — what a
    /// script's `(command-line)` reports and what multi-file subcommands
    /// (`fmt`, `test`) iterate. Allocated from the same immortal c_allocator
    /// argv itself lives in (platform.argsIterate): a fixed cap here
    /// silently dropped every argument past the 64th, so `kaappi fmt` over
    /// the 573-file corpus only ever touched the first 64 files (#1652).
    script_args_slice: []const []const u8 = &.{},

    action: Action = .run,

    pub const Action = enum { run, exit_ok };

    pub fn libPaths(self: *const Options) []const []const u8 {
        return self.lib_path_buf[0..self.lib_path_count];
    }

    pub fn scriptArgs(self: *const Options) []const []const u8 {
        return self.script_args_slice;
    }
};

// ── Public API ─────────────────────────────────────────────────────────

pub fn preScanSandbox(args: std.process.Args) bool {
    var iter = platform.argsIterate(args);
    _ = iter.skip();
    while (iter.next()) |arg| {
        if (std.mem.eql(u8, arg, "--sandbox")) return true;
        if (lookupFlag(arg)) |f| {
            if (f.takes_value) _ = iter.skip();
        } else if (std.mem.eql(u8, arg, "compile") or std.mem.eql(u8, arg, "check") or
            std.mem.eql(u8, arg, "ast") or std.mem.eql(u8, arg, "expand") or
            std.mem.eql(u8, arg, "ir") or std.mem.eql(u8, arg, "fmt"))
        {
            // bare subcommand — keep scanning
        } else if (std.mem.startsWith(u8, arg, diagnostics_prefix)) {
            // `--diagnostics=…` carries its value inline — keep scanning.
        } else if (std.mem.eql(u8, arg, "--timings") or std.mem.startsWith(u8, arg, timings_prefix)) {
            // `--timings` / `--timings=…` — no separate value arg, keep scanning.
        } else {
            break;
        }
    }
    return false;
}

pub fn parse(args: std.process.Args) Options {
    var opts: Options = .{};
    var iter = platform.argsIterate(args);
    _ = iter.skip();

    while (iter.next()) |arg| {
        if (std.mem.eql(u8, arg, "compile")) {
            opts.native_compile_mode = true;
            continue;
        }

        if (std.mem.eql(u8, arg, "check")) {
            opts.check_mode = true;
            continue;
        }

        if (std.mem.eql(u8, arg, "ast")) {
            opts.ast_mode = true;
            continue;
        }

        if (std.mem.eql(u8, arg, "expand")) {
            opts.expand_mode = true;
            continue;
        }

        if (std.mem.eql(u8, arg, "ir")) {
            opts.ir_mode = true;
            continue;
        }

        if (std.mem.eql(u8, arg, "fmt")) {
            opts.fmt_mode = true;
            continue;
        }

        if (std.mem.startsWith(u8, arg, diagnostics_prefix)) {
            opts.diagnostics_format = parseDiagnosticsFormat(arg[diagnostics_prefix.len..]);
            continue;
        }

        if (std.mem.eql(u8, arg, "--timings")) {
            opts.timings_enabled = true;
            continue;
        }
        if (std.mem.startsWith(u8, arg, timings_prefix)) {
            opts.timings_enabled = true;
            opts.timings_json = parseTimingsFormat(arg[timings_prefix.len..]);
            continue;
        }

        if (lookupFlag(arg)) |f| {
            const value: ?[]const u8 = if (f.takes_value) blk: {
                break :blk iter.next() orelse {
                    writeStderr(f.long);
                    writeStderr(" requires a ");
                    writeStderr(f.value_name);
                    writeStderr(" argument\n");
                    std.process.exit(USAGE_ERROR_EXIT);
                };
            } else null;

            switch (f.id) {
                .help => {
                    printUsage();
                    opts.action = .exit_ok;
                    return opts;
                },
                .version_flag => {
                    writeStdout("Kaappi Scheme v" ++ version ++ "\n");
                    opts.action = .exit_ok;
                    return opts;
                },
                .completions_flag => {
                    handleCompletions(value.?);
                    opts.action = .exit_ok;
                    return opts;
                },
                .lib_path => {
                    if (opts.lib_path_count < 16) {
                        opts.lib_path_buf[opts.lib_path_count] = value.?;
                        opts.lib_path_count += 1;
                    }
                },
                .compile => opts.compile_mode = true,
                .emit_llvm => opts.emit_llvm_mode = true,
                .output => opts.compile_output = value.?,
                .disassemble => opts.disassemble_mode = true,
                .no_ir_opt => opts.no_ir_opt = true,
                .sandbox => opts.sandbox_mode = true,
                .gc_stats => opts.gc_stats_mode = true,
                .profile => opts.profile_mode = true,
                .profile_json => {
                    opts.profile_mode = true;
                    opts.profile_json_path = value.?;
                },
                .coverage => opts.coverage_mode = true,
                .coverage_xml => {
                    opts.coverage_mode = true;
                    opts.coverage_xml_path = value.?;
                },
                .timeout => opts.timeout_ms = parsePositiveU64(value.?, "--timeout"),
                .max_memory => opts.max_memory = parsePositiveUsize(value.?, "--max-memory"),
                .deny_warnings => opts.deny_warnings = true,
                .no_opt => opts.ir_no_opt = true,
                .check => opts.fmt_check = true,
            }
        } else if (arg.len > 1 and arg[0] == '-') {
            writeStderr("unknown option: ");
            writeStderr(arg);
            writeStderr("\nRun 'kaappi --help' for usage.\n");
            std.process.exit(USAGE_ERROR_EXIT);
        } else {
            opts.file_path = arg;
            break;
        }
    }

    // Collect remaining args after the file path for (command-line).
    // Also check for -o which is valid after the file path for compile modes.
    if (opts.file_path) |fp| {
        var script_args: std.ArrayList([]const u8) = .empty;
        script_args.append(std.heap.c_allocator, fp) catch oomCollectingArgs();
        const consumes_output = opts.compile_mode or opts.native_compile_mode or
            opts.disassemble_mode or opts.emit_llvm_mode;
        while (iter.next()) |extra| {
            if (consumes_output and std.mem.eql(u8, extra, "-o")) {
                if (opts.compile_output == null) opts.compile_output = iter.next();
                continue;
            }
            // Accept `kaappi ir <file> --no-opt` (flag after the file), the
            // natural spelling, in addition to `kaappi ir --no-opt <file>`.
            if (opts.ir_mode and std.mem.eql(u8, extra, "--no-opt")) {
                opts.ir_no_opt = true;
                continue;
            }
            script_args.append(std.heap.c_allocator, extra) catch oomCollectingArgs();
        }
        opts.script_args_slice = script_args.toOwnedSlice(std.heap.c_allocator) catch oomCollectingArgs();
    }

    return opts;
}

fn oomCollectingArgs() noreturn {
    usageError("kaappi: out of memory collecting command-line arguments\n");
}

pub fn printUsage() void {
    writeStdout(
        "Kaappi Scheme v" ++ version ++ "\n" ++
            "\n" ++
            "Usage: kaappi [options] [file] [script-args...]\n" ++
            "       kaappi compile <file.scm> [-o output]\n" ++
            "       kaappi check <file.scm>\n" ++
            "       kaappi explain <code>\n" ++
            "       kaappi features [--json]\n" ++
            "       kaappi test [paths...]\n" ++
            "       kaappi ast|expand|ir <file.scm>\n" ++
            "       kaappi doctor [--json]\n" ++
            "       kaappi fmt [--check] [files...]\n" ++
            "       kaappi cache <status|clear>\n" ++
            "\n" ++
            "Commands:\n" ++
            "  compile <file>     Compile to native binary via LLVM\n" ++
            "  check <file>       Compile-only static analysis (no execution); reports\n" ++
            "                     read/compile errors and KP4xxx lint findings.\n" ++
            "                     Honors --diagnostics=json; --deny-warnings\n" ++
            "  explain <code>     Explain a diagnostic code (e.g. KP3001); --json, --all\n" ++
            "  features           Report this build's capabilities (version, target,\n" ++
            "                     subsystems, SRFIs, limits); --json\n" ++
            "  test [paths...]    Run SRFI-64 suites; --json, --seed <n>, --lib-path,\n" ++
            "                     --changed/--list-affected [--since <rev>]\n" ++
            "  ast <file>         Print post-read datums (read + write)\n" ++
            "  expand <file>      Print the program after full macro expansion\n" ++
            "  ir <file> [--no-opt]  Print the IR tree; --no-opt shows it before the\n" ++
            "                     optimization passes (default: after)\n" ++
            "  doctor [--json]    Check the installation and environment; PASS/WARN/FAIL\n" ++
            "                     per check with a fix for each failure\n" ++
            "  fmt [files...]     Canonically format Scheme in place; --check reports\n" ++
            "                     paths needing formatting (exit 1) without writing.\n" ++
            "                     With no files, formats stdin to stdout\n" ++
            "  cache status       Show the bytecode cache location, entries, and sizes\n" ++
            "  cache clear        Remove all bytecode cache entries\n" ++
            "\n" ++
            "Options:\n" ++
            "  -h, --help         Show this help message\n" ++
            "  --version          Show version\n" ++
            "  --lib-path <path>  Add library search path (up to 16)\n" ++
            "  --compile          Compile file to bytecode (.sbc)\n" ++
            "  --emit-llvm        Emit LLVM IR text (.ll)\n" ++
            "  -o <file>          Output path\n" ++
            "  --disassemble      Disassemble bytecode\n" ++
            "  --diagnostics=<fmt> Diagnostic output format: text (default) or json\n" ++
            "  --deny-warnings    (check) Treat lint warnings as errors for the exit code\n" ++
            "  --no-ir-opt        Disable IR optimization passes (skips .sbc cache)\n" ++
            "  --sandbox          Restrict filesystem and process access\n" ++
            "  --gc-stats         Print GC statistics on exit\n" ++
            "  --profile          Enable profiling\n" ++
            "  --profile-json <f> Write profile JSON to file\n" ++
            "  --timings[=fmt]    Report per-stage pipeline timings + cache HIT/MISS\n" ++
            "                     on stderr; fmt is text (default) or json\n" ++
            "  --coverage         Report library procedure coverage\n" ++
            "  --coverage-xml <f> Write Cobertura XML coverage to file\n" ++
            "  --timeout <ms>     Execution timeout in milliseconds\n" ++
            "  --max-memory <n>   Maximum heap memory in bytes\n" ++
            "  --completions <sh> Output completion script (bash, zsh, fish)\n" ++
            "\n" ++
            "Environment variables:\n" ++
            "  KAAPPI_LIB_DIR     Directory containing " ++ platform.rt_lib_name ++ " (for compile)\n" ++
            "\n" ++
            "With no file argument, starts an interactive REPL.\n",
    );
}

pub fn usageError(msg: []const u8) noreturn {
    writeStderr(msg);
    std.process.exit(USAGE_ERROR_EXIT);
}

// ── Private helpers ────────────────────────────────────────────────────

fn handleCompletions(shell: []const u8) void {
    if (completions.kaappi(shell)) |script| {
        writeStdout(script);
        return;
    }
    writeStderr("unknown shell: ");
    writeStderr(shell);
    writeStderr("\nSupported: bash, zsh, fish\n");
    std.process.exit(USAGE_ERROR_EXIT);
}

fn parseDiagnosticsFormat(value: []const u8) DiagnosticsFormat {
    if (std.mem.eql(u8, value, "text")) return .text;
    if (std.mem.eql(u8, value, "json")) return .json;
    writeStderr("--diagnostics: unknown format '");
    writeStderr(value);
    writeStderr("' (expected 'text' or 'json')\n");
    std.process.exit(USAGE_ERROR_EXIT);
}

/// Returns true for `json`, false for `text`; exits on anything else.
fn parseTimingsFormat(value: []const u8) bool {
    if (std.mem.eql(u8, value, "text")) return false;
    if (std.mem.eql(u8, value, "json")) return true;
    writeStderr("--timings: unknown format '");
    writeStderr(value);
    writeStderr("' (expected 'text' or 'json')\n");
    std.process.exit(USAGE_ERROR_EXIT);
}

fn parsePositiveU64(str: []const u8, flag_name: []const u8) u64 {
    const val = std.fmt.parseInt(u64, str, 10) catch {
        writeStderr(flag_name);
        writeStderr(" requires a positive integer milliseconds value\n");
        std.process.exit(USAGE_ERROR_EXIT);
    };
    if (val == 0) {
        writeStderr(flag_name);
        writeStderr(" requires a positive integer milliseconds value\n");
        std.process.exit(USAGE_ERROR_EXIT);
    }
    return val;
}

fn parsePositiveUsize(str: []const u8, flag_name: []const u8) usize {
    const val = std.fmt.parseInt(usize, str, 10) catch {
        writeStderr(flag_name);
        writeStderr(" requires a positive integer bytes value\n");
        std.process.exit(USAGE_ERROR_EXIT);
    };
    if (val == 0) {
        writeStderr(flag_name);
        writeStderr(" requires a positive integer bytes value\n");
        std.process.exit(USAGE_ERROR_EXIT);
    }
    return val;
}

// ── Tests ──────────────────────────────────────────────────────────────

fn testArgs(comptime argv: []const [*:0]const u8) std.process.Args {
    if (comptime platform.is_windows) {
        // Windows argv is one WTF-16 command line; join the (simple,
        // quote-free) test arguments so the parse tests exercise the real
        // Windows command-line iterator.
        comptime var line: []const u8 = "";
        inline for (argv, 0..) |arg, i| {
            const s = comptime std.mem.span(arg);
            comptime std.debug.assert(std.mem.indexOfAny(u8, s, " \t\"") == null);
            if (i > 0) line = line ++ " ";
            line = line ++ s;
        }
        return .{ .vector = comptime std.unicode.wtf8ToWtf16LeStringLiteral(line) };
    }
    return .{ .vector = argv };
}

test "lookupFlag: known long flags" {
    try std.testing.expect(lookupFlag("--help") != null);
    try std.testing.expect(lookupFlag("--version") != null);
    try std.testing.expect(lookupFlag("--timeout") != null);
    try std.testing.expect(lookupFlag("--lib-path") != null);
    try std.testing.expect(lookupFlag("--compile") != null);
    try std.testing.expect(lookupFlag("--gc-stats") != null);
    try std.testing.expect(lookupFlag("--profile-json") != null);
}

test "lookupFlag: short flags" {
    const h = lookupFlag("-h");
    try std.testing.expect(h != null);
    try std.testing.expect(h.?.id == .help);

    const o = lookupFlag("-o");
    try std.testing.expect(o != null);
    try std.testing.expect(o.?.id == .output);
}

test "lookupFlag: unknown flags" {
    try std.testing.expect(lookupFlag("--unknown") == null);
    try std.testing.expect(lookupFlag("-x") == null);
    try std.testing.expect(lookupFlag("compile") == null);
}

test "lookupFlag: value-taking flags" {
    const lp = lookupFlag("--lib-path");
    try std.testing.expect(lp != null);
    try std.testing.expect(lp.?.takes_value);

    const gs = lookupFlag("--gc-stats");
    try std.testing.expect(gs != null);
    try std.testing.expect(!gs.?.takes_value);
}

test "preScanSandbox: detects --sandbox" {
    const argv = [_][*:0]const u8{ "kaappi", "--sandbox", "test.scm" };
    try std.testing.expect(preScanSandbox(testArgs(&argv)));
}

test "preScanSandbox: --sandbox after filename not detected" {
    const argv = [_][*:0]const u8{ "kaappi", "test.scm", "--sandbox" };
    try std.testing.expect(!preScanSandbox(testArgs(&argv)));
}

test "preScanSandbox: skips value-taking flags" {
    const argv = [_][*:0]const u8{ "kaappi", "--lib-path", "--sandbox", "test.scm" };
    try std.testing.expect(!preScanSandbox(testArgs(&argv)));
}

test "preScanSandbox: sandbox with other flags" {
    const argv = [_][*:0]const u8{ "kaappi", "--gc-stats", "--sandbox", "--profile", "test.scm" };
    try std.testing.expect(preScanSandbox(testArgs(&argv)));
}

test "preScanSandbox: no sandbox" {
    const argv = [_][*:0]const u8{ "kaappi", "--gc-stats", "test.scm" };
    try std.testing.expect(!preScanSandbox(testArgs(&argv)));
}

test "preScanSandbox: empty args" {
    const argv = [_][*:0]const u8{"kaappi"};
    try std.testing.expect(!preScanSandbox(testArgs(&argv)));
}

test "parse: boolean flags" {
    const argv = [_][*:0]const u8{ "kaappi", "--gc-stats", "--profile", "--sandbox", "test.scm" };
    const opts = parse(testArgs(&argv));
    try std.testing.expect(opts.gc_stats_mode);
    try std.testing.expect(opts.profile_mode);
    try std.testing.expect(opts.sandbox_mode);
    try std.testing.expectEqualStrings("test.scm", opts.file_path.?);
    try std.testing.expectEqual(Options.Action.run, opts.action);
}

test "parse: value flags" {
    const argv = [_][*:0]const u8{ "kaappi", "--lib-path", "/foo", "--timeout", "5000", "test.scm" };
    const opts = parse(testArgs(&argv));
    try std.testing.expectEqual(@as(usize, 1), opts.lib_path_count);
    try std.testing.expectEqualStrings("/foo", opts.libPaths()[0]);
    try std.testing.expectEqual(@as(u64, 5000), opts.timeout_ms.?);
    try std.testing.expectEqualStrings("test.scm", opts.file_path.?);
}

test "parse: script args after filename" {
    const argv = [_][*:0]const u8{ "kaappi", "test.scm", "arg1", "arg2" };
    const opts = parse(testArgs(&argv));
    try std.testing.expectEqual(@as(usize, 3), opts.scriptArgs().len);
    try std.testing.expectEqualStrings("test.scm", opts.scriptArgs()[0]);
    try std.testing.expectEqualStrings("arg1", opts.scriptArgs()[1]);
    try std.testing.expectEqualStrings("arg2", opts.scriptArgs()[2]);
}

test "parse: script args past the 64th are kept (#1652)" {
    // The old fixed [64] buffer silently dropped everything past it — the
    // fmt corpus (573 files in one xargs invocation) only ever touched the
    // first 64 files. Build 129 args and require every one to survive.
    const argv = comptime blk: {
        @setEvalBranchQuota(200_000);
        var a: [131][*:0]const u8 = undefined;
        a[0] = "kaappi";
        a[1] = "test.scm";
        for (0..129) |i| {
            a[2 + i] = std.fmt.comptimePrint("arg{d}", .{i});
        }
        break :blk a;
    };
    const opts = parse(testArgs(&argv));
    try std.testing.expectEqual(@as(usize, 130), opts.scriptArgs().len);
    try std.testing.expectEqualStrings("test.scm", opts.scriptArgs()[0]);
    try std.testing.expectEqualStrings("arg63", opts.scriptArgs()[64]);
    try std.testing.expectEqualStrings("arg64", opts.scriptArgs()[65]);
    try std.testing.expectEqualStrings("arg128", opts.scriptArgs()[129]);
}

test "parse: compile subcommand" {
    const argv = [_][*:0]const u8{ "kaappi", "compile", "test.scm", "-o", "out" };
    const opts = parse(testArgs(&argv));
    try std.testing.expect(opts.native_compile_mode);
    try std.testing.expectEqualStrings("test.scm", opts.file_path.?);
    try std.testing.expectEqualStrings("out", opts.compile_output.?);
}

test "parse: -o before filename" {
    const argv = [_][*:0]const u8{ "kaappi", "--compile", "-o", "out.sbc", "test.scm" };
    const opts = parse(testArgs(&argv));
    try std.testing.expect(opts.compile_mode);
    try std.testing.expectEqualStrings("out.sbc", opts.compile_output.?);
    try std.testing.expectEqualStrings("test.scm", opts.file_path.?);
}

test "parse: -o after filename in compile mode" {
    const argv = [_][*:0]const u8{ "kaappi", "--compile", "test.scm", "-o", "out.sbc" };
    const opts = parse(testArgs(&argv));
    try std.testing.expect(opts.compile_mode);
    try std.testing.expectEqualStrings("out.sbc", opts.compile_output.?);
}

test "parse: coverage-xml sets coverage_mode" {
    const argv = [_][*:0]const u8{ "kaappi", "--coverage-xml", "cov.xml", "test.scm" };
    const opts = parse(testArgs(&argv));
    try std.testing.expect(opts.coverage_mode);
    try std.testing.expectEqualStrings("cov.xml", opts.coverage_xml_path.?);
}

test "parse: profile-json sets profile_mode" {
    const argv = [_][*:0]const u8{ "kaappi", "--profile-json", "prof.json", "test.scm" };
    const opts = parse(testArgs(&argv));
    try std.testing.expect(opts.profile_mode);
    try std.testing.expectEqualStrings("prof.json", opts.profile_json_path.?);
}

test "parse: max-memory" {
    const argv = [_][*:0]const u8{ "kaappi", "--max-memory", "1000000", "test.scm" };
    const opts = parse(testArgs(&argv));
    try std.testing.expectEqual(@as(usize, 1000000), opts.max_memory.?);
}

test "parse: bare --timings enables text timings" {
    const argv = [_][*:0]const u8{ "kaappi", "--timings", "test.scm" };
    const opts = parse(testArgs(&argv));
    try std.testing.expect(opts.timings_enabled);
    try std.testing.expect(!opts.timings_json);
    try std.testing.expectEqualStrings("test.scm", opts.file_path.?);
}

test "parse: --timings=json enables json timings" {
    const argv = [_][*:0]const u8{ "kaappi", "--timings=json", "test.scm" };
    const opts = parse(testArgs(&argv));
    try std.testing.expect(opts.timings_enabled);
    try std.testing.expect(opts.timings_json);
}

test "parse: --timings=text is the explicit text default" {
    const argv = [_][*:0]const u8{ "kaappi", "--timings=text", "test.scm" };
    const opts = parse(testArgs(&argv));
    try std.testing.expect(opts.timings_enabled);
    try std.testing.expect(!opts.timings_json);
}

test "parse: no --timings leaves it disabled" {
    const argv = [_][*:0]const u8{ "kaappi", "test.scm" };
    const opts = parse(testArgs(&argv));
    try std.testing.expect(!opts.timings_enabled);
}

test "parse: --timings after filename is a script arg, not a flag" {
    const argv = [_][*:0]const u8{ "kaappi", "test.scm", "--timings" };
    const opts = parse(testArgs(&argv));
    try std.testing.expect(!opts.timings_enabled);
    try std.testing.expectEqualStrings("--timings", opts.scriptArgs()[1]);
}

test "preScanSandbox: --timings before --sandbox still detected" {
    const argv = [_][*:0]const u8{ "kaappi", "--timings=json", "--sandbox", "test.scm" };
    try std.testing.expect(preScanSandbox(testArgs(&argv)));
}

test "parse: no args → REPL (no file)" {
    const argv = [_][*:0]const u8{"kaappi"};
    const opts = parse(testArgs(&argv));
    try std.testing.expect(opts.file_path == null);
    try std.testing.expectEqual(Options.Action.run, opts.action);
}

test "parse: multiple lib paths" {
    const argv = [_][*:0]const u8{ "kaappi", "--lib-path", "/a", "--lib-path", "/b", "test.scm" };
    const opts = parse(testArgs(&argv));
    try std.testing.expectEqual(@as(usize, 2), opts.lib_path_count);
    try std.testing.expectEqualStrings("/a", opts.libPaths()[0]);
    try std.testing.expectEqualStrings("/b", opts.libPaths()[1]);
}

test "parse: no-ir-opt" {
    const argv = [_][*:0]const u8{ "kaappi", "--no-ir-opt", "test.scm" };
    const opts = parse(testArgs(&argv));
    try std.testing.expect(opts.no_ir_opt);
    try std.testing.expectEqualStrings("test.scm", opts.file_path.?);
}

test "parse: disassemble mode" {
    const argv = [_][*:0]const u8{ "kaappi", "--disassemble", "test.scm" };
    const opts = parse(testArgs(&argv));
    try std.testing.expect(opts.disassemble_mode);
    try std.testing.expectEqualStrings("test.scm", opts.file_path.?);
}

test "parse: emit-llvm mode" {
    const argv = [_][*:0]const u8{ "kaappi", "--emit-llvm", "test.scm" };
    const opts = parse(testArgs(&argv));
    try std.testing.expect(opts.emit_llvm_mode);
}

test "parse: flags after filename are script args" {
    const argv = [_][*:0]const u8{ "kaappi", "test.scm", "--gc-stats", "--profile" };
    const opts = parse(testArgs(&argv));
    try std.testing.expect(!opts.gc_stats_mode);
    try std.testing.expect(!opts.profile_mode);
    try std.testing.expectEqual(@as(usize, 3), opts.scriptArgs().len);
    try std.testing.expectEqualStrings("--gc-stats", opts.scriptArgs()[1]);
}

test "parse: --diagnostics=json sets json format" {
    const argv = [_][*:0]const u8{ "kaappi", "--diagnostics=json", "test.scm" };
    const opts = parse(testArgs(&argv));
    try std.testing.expectEqual(DiagnosticsFormat.json, opts.diagnostics_format);
    try std.testing.expectEqualStrings("test.scm", opts.file_path.?);
}

test "parse: --diagnostics=text is the explicit default" {
    const argv = [_][*:0]const u8{ "kaappi", "--diagnostics=text", "test.scm" };
    const opts = parse(testArgs(&argv));
    try std.testing.expectEqual(DiagnosticsFormat.text, opts.diagnostics_format);
}

test "parse: diagnostics format defaults to text" {
    const argv = [_][*:0]const u8{ "kaappi", "test.scm" };
    const opts = parse(testArgs(&argv));
    try std.testing.expectEqual(DiagnosticsFormat.text, opts.diagnostics_format);
}

test "parse: --diagnostics=json after filename is a script arg, not a format" {
    const argv = [_][*:0]const u8{ "kaappi", "test.scm", "--diagnostics=json" };
    const opts = parse(testArgs(&argv));
    try std.testing.expectEqual(DiagnosticsFormat.text, opts.diagnostics_format);
    try std.testing.expectEqual(@as(usize, 2), opts.scriptArgs().len);
    try std.testing.expectEqualStrings("--diagnostics=json", opts.scriptArgs()[1]);
}

test "preScanSandbox: --diagnostics before --sandbox still detected" {
    const argv = [_][*:0]const u8{ "kaappi", "--diagnostics=json", "--sandbox", "test.scm" };
    try std.testing.expect(preScanSandbox(testArgs(&argv)));
}
