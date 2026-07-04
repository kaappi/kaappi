const std = @import("std");
const completions = @import("completions.zig");

pub const version = @import("build_options").version;

pub const USAGE_ERROR_EXIT: u8 = 2;

// ── I/O helpers (private copies — main.zig keeps its own) ──────────────

fn writeToFd(fd: std.posix.fd_t, bytes: []const u8) void {
    var total: usize = 0;
    while (total < bytes.len) {
        const result = std.posix.system.write(fd, bytes.ptr + total, bytes.len - total);
        if (result <= 0) {
            if (result < 0 and std.posix.errno(result) == .INTR) continue;
            break;
        }
        const written: usize = @intCast(result);
        total += written;
    }
}

fn writeStdout(bytes: []const u8) void {
    writeToFd(1, bytes);
}

fn writeStderr(bytes: []const u8) void {
    writeToFd(2, bytes);
}

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
    sandbox,
    gc_stats,
    profile,
    profile_json,
    coverage,
    coverage_xml,
    timeout,
    max_memory,
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
    .{ .long = "--sandbox", .short = null, .takes_value = false, .id = .sandbox, .value_name = "" },
    .{ .long = "--gc-stats", .short = null, .takes_value = false, .id = .gc_stats, .value_name = "" },
    .{ .long = "--profile", .short = null, .takes_value = false, .id = .profile, .value_name = "" },
    .{ .long = "--profile-json", .short = null, .takes_value = true, .id = .profile_json, .value_name = "file path" },
    .{ .long = "--coverage", .short = null, .takes_value = false, .id = .coverage, .value_name = "" },
    .{ .long = "--coverage-xml", .short = null, .takes_value = true, .id = .coverage_xml, .value_name = "file path" },
    .{ .long = "--timeout", .short = null, .takes_value = true, .id = .timeout, .value_name = "milliseconds" },
    .{ .long = "--max-memory", .short = null, .takes_value = true, .id = .max_memory, .value_name = "bytes" },
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

pub const Options = struct {
    file_path: ?[]const u8 = null,

    compile_mode: bool = false,
    native_compile_mode: bool = false,
    emit_llvm_mode: bool = false,
    disassemble_mode: bool = false,

    compile_output: ?[]const u8 = null,

    gc_stats_mode: bool = false,
    profile_mode: bool = false,
    profile_json_path: ?[]const u8 = null,
    coverage_mode: bool = false,
    coverage_xml_path: ?[]const u8 = null,

    timeout_ms: ?u64 = null,
    max_memory: ?usize = null,

    sandbox_mode: bool = false,

    lib_path_buf: [16][]const u8 = undefined,
    lib_path_count: usize = 0,

    script_arg_buf: [64][]const u8 = undefined,
    script_arg_count: usize = 0,

    action: Action = .run,

    pub const Action = enum { run, exit_ok };

    pub fn libPaths(self: *const Options) []const []const u8 {
        return self.lib_path_buf[0..self.lib_path_count];
    }

    pub fn scriptArgs(self: *const Options) []const []const u8 {
        return self.script_arg_buf[0..self.script_arg_count];
    }
};

// ── Public API ─────────────────────────────────────────────────────────

pub fn preScanSandbox(args: std.process.Args) bool {
    var iter = args.iterate();
    _ = iter.skip();
    while (iter.next()) |arg| {
        if (std.mem.eql(u8, arg, "--sandbox")) return true;
        if (lookupFlag(arg)) |f| {
            if (f.takes_value) _ = iter.skip();
        } else if (std.mem.eql(u8, arg, "compile")) {
            // bare subcommand — keep scanning
        } else {
            break;
        }
    }
    return false;
}

pub fn parse(args: std.process.Args) Options {
    var opts: Options = .{};
    var iter = args.iterate();
    _ = iter.skip();

    while (iter.next()) |arg| {
        if (std.mem.eql(u8, arg, "compile")) {
            opts.native_compile_mode = true;
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
        opts.script_arg_buf[0] = fp;
        opts.script_arg_count = 1;
        const consumes_output = opts.compile_mode or opts.native_compile_mode or
            opts.disassemble_mode or opts.emit_llvm_mode;
        while (iter.next()) |extra| {
            if (consumes_output and std.mem.eql(u8, extra, "-o")) {
                if (opts.compile_output == null) opts.compile_output = iter.next();
                continue;
            }
            if (opts.script_arg_count < 64) {
                opts.script_arg_buf[opts.script_arg_count] = extra;
                opts.script_arg_count += 1;
            }
        }
    }

    return opts;
}

pub fn printUsage() void {
    writeStdout(
        "Kaappi Scheme v" ++ version ++ "\n" ++
            "\n" ++
            "Usage: kaappi [options] [file] [script-args...]\n" ++
            "       kaappi compile <file.scm> [-o output]\n" ++
            "\n" ++
            "Commands:\n" ++
            "  compile <file>     Compile to native binary via LLVM\n" ++
            "\n" ++
            "Options:\n" ++
            "  -h, --help         Show this help message\n" ++
            "  --version          Show version\n" ++
            "  --lib-path <path>  Add library search path (up to 16)\n" ++
            "  --compile          Compile file to bytecode (.sbc)\n" ++
            "  --emit-llvm        Emit LLVM IR text (.ll)\n" ++
            "  -o <file>          Output path\n" ++
            "  --disassemble      Disassemble bytecode\n" ++
            "  --sandbox          Restrict filesystem and process access\n" ++
            "  --gc-stats         Print GC statistics on exit\n" ++
            "  --profile          Enable profiling\n" ++
            "  --profile-json <f> Write profile JSON to file\n" ++
            "  --coverage         Report library procedure coverage\n" ++
            "  --coverage-xml <f> Write Cobertura XML coverage to file\n" ++
            "  --timeout <ms>     Execution timeout in milliseconds\n" ++
            "  --max-memory <n>   Maximum heap memory in bytes\n" ++
            "  --completions <sh> Output completion script (bash, zsh, fish)\n" ++
            "\n" ++
            "Environment variables:\n" ++
            "  KAAPPI_LIB_DIR     Directory containing libkaappi_rt.a (for compile)\n" ++
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

fn testArgs(argv: []const [*:0]const u8) std.process.Args {
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
    try std.testing.expectEqual(@as(usize, 3), opts.script_arg_count);
    try std.testing.expectEqualStrings("test.scm", opts.scriptArgs()[0]);
    try std.testing.expectEqualStrings("arg1", opts.scriptArgs()[1]);
    try std.testing.expectEqualStrings("arg2", opts.scriptArgs()[2]);
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
    try std.testing.expectEqual(@as(usize, 3), opts.script_arg_count);
    try std.testing.expectEqualStrings("--gc-stats", opts.scriptArgs()[1]);
}
