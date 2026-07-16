const std = @import("std");
const platform = @import("platform.zig");
const builtin = @import("builtin");

const dylib_ext = if (builtin.os.tag == .macos)
    ".dylib"
else if (builtin.os.tag == .windows)
    ".dll"
else
    ".so";
const version = @import("build_options").version;

const crash = @import("crash.zig");

/// Custom panic handler (kaappi#1514): the package manager gets the same
/// identity/version/report banner as `kaappi`. thottam runs no Scheme pipeline,
/// so the breadcrumb stays idle and the `while:` line is omitted — the banner
/// still names the build and where to report.
pub const panic = crash.PanicHandler("thottam");

const semver = @import("thottam_semver.zig");
const proc = @import("thottam_proc.zig");
const state = @import("thottam_state.zig");
const tfs = @import("thottam_fs.zig");

const Semver = semver.Semver;
const parseConstraints = semver.parseConstraints;
const matchesAllConstraints = semver.matchesAllConstraints;
const isConstraintSpec = semver.isConstraintSpec;

const runPassthrough = proc.runPassthrough;
const runGit = proc.runGit;
const runGitCapture = proc.runGitCapture;
const checkoutVersion = proc.checkoutVersion;

const PkgSpec = state.PkgSpec;
const PkgManifest = state.PkgManifest;
const parsePkgSpec = state.parsePkgSpec;
const isValidPkgName = state.isValidPkgName;
const parsePkgManifest = state.parsePkgManifest;
const isInstalled = state.isInstalled;
const LockEntry = state.LockEntry;
const getLockedEntry = state.getLockedEntry;
const getLockedSha = state.getLockedSha;
const appendLockEntry = state.appendLockEntry;
const updateLockfile = state.updateLockfile;
const removeFromLockfile = state.removeFromLockfile;
const removeFromInstalled = state.removeFromInstalled;

var use_color: bool = false;

const Color = struct {
    const reset = "\x1b[0m";
    const bold = "\x1b[1m";
    const green = "\x1b[32m";
    const red = "\x1b[31m";
    const yellow = "\x1b[33m";
    const cyan = "\x1b[36m";
    const dim = "\x1b[2m";
};

fn initColor() void {
    use_color = platform.isatty(1);
}

const Config = struct {
    home: []const u8,
    org: []const u8,
    lib_dir: []const u8,
    src_dir: []const u8,
    installed: []const u8,
    lockfile: []const u8,
};

fn writeToFd(fd: platform.fd_t, bytes: []const u8) void {
    var total: usize = 0;
    while (total < bytes.len) {
        const result = platform.write(fd, bytes.ptr + total, bytes.len - total);
        if (result < 0) {
            if (platform.errno(result) == .INTR) continue;
            break;
        }
        if (result == 0) break;
        total += @as(usize, @intCast(result));
    }
}

fn writeStdout(bytes: []const u8) void {
    writeToFd(1, bytes);
}

fn writeStderr(bytes: []const u8) void {
    writeToFd(2, bytes);
}

fn fatal(msg: []const u8) noreturn {
    if (use_color) writeStderr(Color.red ++ Color.bold);
    writeStderr("error: ");
    if (use_color) writeStderr(Color.reset ++ Color.red);
    writeStderr(msg);
    if (use_color) writeStderr(Color.reset);
    writeStderr("\n");
    std.process.exit(1);
}

pub fn readFile(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const path_z = try allocator.dupeZ(u8, path);
    defer allocator.free(path_z);
    const fd = platform.openRead(path_z) catch return error.FileNotFound;
    defer _ = platform.close(fd);
    var buf: std.ArrayList(u8) = .empty;
    var tmp: [4096]u8 = undefined;
    while (true) {
        const raw = platform.read(fd, &tmp, tmp.len);
        if (raw < 0) {
            if (platform.errno(raw) == .INTR) continue;
            buf.deinit(allocator);
            return error.ReadFailed;
        }
        const n: usize = @intCast(raw);
        if (n == 0) break;
        buf.appendSlice(allocator, tmp[0..n]) catch return error.OutOfMemory;
    }
    return buf.toOwnedSlice(allocator);
}

pub fn writeFile(allocator: std.mem.Allocator, path: []const u8, content: []const u8) !void {
    const path_z = try allocator.dupeZ(u8, path);
    defer allocator.free(path_z);
    const fd = platform.openWriteTrunc(path_z, 0o644) catch return error.CannotOpen;
    defer _ = platform.close(fd);
    var total: usize = 0;
    while (total < content.len) {
        const result = platform.write(fd, content.ptr + total, content.len - total);
        if (result <= 0) return error.WriteFailed;
        total += @as(usize, @intCast(result));
    }
}

fn appendFile(allocator: std.mem.Allocator, path: []const u8, line: []const u8) !void {
    const path_z = try allocator.dupeZ(u8, path);
    defer allocator.free(path_z);
    const fd = platform.openAppend(path_z, 0o644) catch return error.CannotOpen;
    defer _ = platform.close(fd);
    _ = platform.write(fd, line.ptr, line.len);
    _ = platform.write(fd, "\n", 1);
}

pub fn fileExists(allocator: std.mem.Allocator, path: []const u8) bool {
    const path_z = allocator.dupeZ(u8, path) catch return false;
    defer allocator.free(path_z);
    const fd = platform.openRead(path_z) catch return false;
    _ = platform.close(fd);
    return true;
}

fn dirExists(allocator: std.mem.Allocator, path: []const u8) bool {
    const path_z = allocator.dupeZ(u8, path) catch return false;
    defer allocator.free(path_z);
    return platform.isDir(path_z);
}

fn joinPath(allocator: std.mem.Allocator, a: []const u8, b: []const u8) ![]u8 {
    const result = try allocator.alloc(u8, a.len + 1 + b.len);
    @memcpy(result[0..a.len], a);
    result[a.len] = '/';
    @memcpy(result[a.len + 1 ..], b);
    return result;
}

fn joinPath3(allocator: std.mem.Allocator, a: []const u8, b: []const u8, c: []const u8) ![]u8 {
    const result = try allocator.alloc(u8, a.len + 1 + b.len + 1 + c.len);
    var pos: usize = 0;
    @memcpy(result[pos..][0..a.len], a);
    pos += a.len;
    result[pos] = '/';
    pos += 1;
    @memcpy(result[pos..][0..b.len], b);
    pos += b.len;
    result[pos] = '/';
    pos += 1;
    @memcpy(result[pos..][0..c.len], c);
    return result;
}

fn resolveVersion(allocator: std.mem.Allocator, clone_url: []const u8, constraint_str: []const u8) ?[]const u8 {
    const constraints = parseConstraints(constraint_str) orelse return null;

    const output = runGitCapture(allocator, &.{ "ls-remote", "--tags", "--", clone_url }) catch return null;
    defer allocator.free(output);

    var best: ?Semver = null;
    var best_tag: ?[]const u8 = null;

    var lines = std.mem.splitScalar(u8, output, '\n');
    while (lines.next()) |line| {
        const tab_idx = std.mem.indexOfScalar(u8, line, '\t') orelse continue;
        const ref = line[tab_idx + 1 ..];
        const tag = if (std.mem.startsWith(u8, ref, "refs/tags/"))
            ref["refs/tags/".len..]
        else
            continue;
        if (std.mem.endsWith(u8, tag, "^{}")) continue;

        const sv = Semver.parse(tag) orelse continue;
        if (!matchesAllConstraints(sv, constraints)) continue;

        if (best) |b| {
            if (Semver.order(sv, b) == .gt) {
                best = sv;
                best_tag = tag;
            }
        } else {
            best = sv;
            best_tag = tag;
        }
    }

    if (best_tag) |bt| {
        return allocator.dupe(u8, bt) catch return null;
    }
    return null;
}

fn getPkgSha(allocator: std.mem.Allocator, src_dir: []const u8, pkg: []const u8) ?[]const u8 {
    const pkg_dir = joinPath(allocator, src_dir, pkg) catch return null;
    defer allocator.free(pkg_dir);
    const git_dir = joinPath(allocator, pkg_dir, ".git") catch return null;
    defer allocator.free(git_dir);
    if (!dirExists(allocator, git_dir)) return null;
    return runGitCapture(allocator, &.{ "-C", pkg_dir, "rev-parse", "HEAD" }) catch null;
}

fn getPkgManifest(allocator: std.mem.Allocator, src_dir: []const u8, pkg: []const u8) ?PkgManifest {
    const pkg_file = joinPath3(allocator, src_dir, pkg, "kaappi.pkg") catch return null;
    defer allocator.free(pkg_file);
    const content = readFile(allocator, pkg_file) catch return null;
    defer allocator.free(content);
    var m = parsePkgManifest(content);
    m.name = if (m.name) |n| allocator.dupe(u8, n) catch null else null;
    m.depends = if (m.depends) |d| allocator.dupe(u8, d) catch null else null;
    m.build_cmd = if (m.build_cmd) |b| allocator.dupe(u8, b) catch null else null;
    m.source = if (m.source) |s| allocator.dupe(u8, s) catch null else null;
    m.owned = true;
    return m;
}

pub fn removeDir(allocator: std.mem.Allocator, path: []const u8) !void {
    try tfs.removeTree(allocator, path);
}

fn copyDylibsFromPkg(allocator: std.mem.Allocator, pkg_dir: []const u8, lib_dir: []const u8) !u32 {
    // An unreadable/missing pkg_dir means "no native libraries", but a
    // found library that fails to copy fails the install — recording a
    // package whose FFI half is missing helps nobody.
    var names = tfs.collectFilesWithSuffix(allocator, pkg_dir, dylib_ext, false) catch return 0;
    defer tfs.freePathList(allocator, &names);
    var count: u32 = 0;
    for (names.items) |basename| {
        const src = try joinPath(allocator, pkg_dir, basename);
        defer allocator.free(src);
        const dst = try joinPath(allocator, lib_dir, basename);
        defer allocator.free(dst);
        tfs.copyFile(allocator, src, dst) catch {
            printErrColor(Color.red, "  Failed to install native library\n");
            return error.CopyFailed;
        };
        count += 1;
    }
    return count;
}

fn removeDylibsFromPkg(allocator: std.mem.Allocator, pkg_dir: []const u8, lib_dir: []const u8) !void {
    var names = tfs.collectFilesWithSuffix(allocator, pkg_dir, dylib_ext, false) catch return;
    defer tfs.freePathList(allocator, &names);
    for (names.items) |basename| {
        const target = joinPath(allocator, lib_dir, basename) catch continue;
        defer allocator.free(target);
        const target_z = allocator.dupeZ(u8, target) catch continue;
        defer allocator.free(target_z);
        _ = platform.unlink(target_z);
    }
}

fn removeSldFiles(allocator: std.mem.Allocator, pkg_lib_dir: []const u8, lib_dir: []const u8) !void {
    var rels = tfs.collectFilesWithSuffix(allocator, pkg_lib_dir, ".sld", true) catch return;
    defer tfs.freePathList(allocator, &rels);
    for (rels.items) |rel| {
        const target = joinPath(allocator, lib_dir, rel) catch continue;
        defer allocator.free(target);
        const target_z = allocator.dupeZ(u8, target) catch continue;
        defer allocator.free(target_z);
        _ = platform.unlink(target_z);
    }
}

fn printBuf(buf: []u8, comptime fmt: []const u8, args: anytype) void {
    const msg = std.fmt.bufPrint(buf, fmt, args) catch return;
    writeStdout(msg);
}

/// Run a package's `build:` line from kaappi.pkg. POSIX gets `/bin/sh -c`
/// exactly as before. Windows has no /bin/sh, and every ecosystem `build:`
/// is a Makefile producing POSIX shared libraries — refuse with a clear
/// error rather than half-run something; pure-Scheme packages (no `build:`
/// line, most of the ecosystem) never reach this.
fn runBuildCommand(allocator: std.mem.Allocator, pkg: []const u8, build_cmd: []const u8, pkg_dir: []const u8) !void {
    var buf: [512]u8 = undefined;
    if (comptime platform.is_windows) {
        printErrColor(Color.red, "error: ");
        const msg = std.fmt.bufPrint(&buf, "{s} has a 'build:' command in kaappi.pkg; building native packages is not supported on Windows (pure-Scheme packages install fine)\n", .{pkg}) catch "package 'build:' commands are not supported on Windows\n";
        writeStderr(msg);
        return error.BuildFailed;
    }
    printBuf(&buf, "  Building {s}...\n", .{pkg});
    const exit_code = runPassthrough(allocator, &.{ "/bin/sh", "-c", build_cmd }, pkg_dir) catch 1;
    if (exit_code != 0) {
        printErrColor(Color.red, "  Build failed\n");
        return error.BuildFailed;
    }
}

/// Merge the contents of a package's lib/ into the shared lib dir — the
/// `cp -R lib/. dst/` shape this replaced: existing files are overwritten
/// (updates re-copy), unrelated files in dst survive. Fatal on failure so
/// a partial copy is never recorded as installed (the old pipeline
/// ignored cp's exit code and could).
fn installLibTree(allocator: std.mem.Allocator, lib_src: []const u8, lib_dir: []const u8) !void {
    tfs.copyTree(allocator, lib_src, lib_dir) catch {
        printErrColor(Color.red, "  Failed to install library files\n");
        return error.CopyFailed;
    };
}

fn printColor(comptime color: []const u8, text: []const u8) void {
    if (use_color) writeStdout(color);
    writeStdout(text);
    if (use_color) writeStdout(Color.reset);
}

fn printErrColor(comptime color: []const u8, text: []const u8) void {
    if (use_color) writeStderr(color);
    writeStderr(text);
    if (use_color) writeStderr(Color.reset);
}

/// Record `pkg` in the install cycle/dedup guard. Returns true if it was newly
/// inserted, false if already present.
///
/// The key is stored as a private copy because `pkg` often aliases memory the
/// map must outlive: for a transitive dependency it is a sub-slice of the
/// caller's `manifest.depends`, which `manifest.deinit` frees when that
/// caller's install frame unwinds — while this map is still live and probed by
/// later `doInstall` calls. Storing the slice directly leaves dangling keys
/// (use-after-free on every later bucket probe). Keys are freed by
/// `freeVisited` when the map is torn down.
fn markVisited(allocator: std.mem.Allocator, visited: *std.StringHashMap(void), pkg: []const u8) !bool {
    if (visited.get(pkg) != null) return false;
    const key = try allocator.dupe(u8, pkg);
    visited.put(key, {}) catch |err| {
        allocator.free(key);
        return err;
    };
    return true;
}

/// Free the owned keys inserted by `markVisited`, then deinit the map.
fn freeVisited(allocator: std.mem.Allocator, visited: *std.StringHashMap(void)) void {
    var it = visited.keyIterator();
    while (it.next()) |k| allocator.free(k.*);
    visited.deinit();
}

fn doInstall(
    allocator: std.mem.Allocator,
    config: Config,
    spec: []const u8,
    locked_mode: bool,
    visited: *std.StringHashMap(void),
) !void {
    const parsed = parsePkgSpec(spec);
    const pkg = parsed.name;
    var install_version = parsed.ver;

    if (!isValidPkgName(pkg)) {
        printErrColor(Color.red, "error: ");
        writeStderr("invalid package name '");
        writeStderr(pkg);
        writeStderr("' (only alphanumeric, '-', '_' allowed)\n");
        return error.InvalidPackageName;
    }

    if (!try markVisited(allocator, visited, pkg)) return;

    if (isInstalled(allocator, config.installed, pkg)) {
        writeStdout("  ");
        printColor(Color.dim, pkg);
        writeStdout(" already installed\n");
        return;
    }

    if (locked_mode) {
        const locked_sha = getLockedSha(allocator, config.lockfile, pkg);
        if (locked_sha == null) {
            var buf: [256]u8 = undefined;
            printErrColor(Color.red, "error: ");
            const msg = std.fmt.bufPrint(&buf, "{s} is not in the lockfile (running in --locked mode)\n", .{pkg}) catch "package not in lockfile\n";
            writeStderr(msg);
            std.process.exit(1);
        }
        install_version = locked_sha;
    }

    if (install_version) |v| {
        if (isConstraintSpec(v)) {
            const clone_url = parsed.source orelse blk: {
                break :blk std.fmt.allocPrint(allocator, "{s}/{s}.git", .{ config.org, pkg }) catch return error.OutOfMemory;
            };
            if (resolveVersion(allocator, clone_url, v)) |resolved| {
                writeStdout("  Resolved ");
                writeStdout(v);
                writeStdout(" -> ");
                writeStdout(resolved);
                writeStdout("\n");
                install_version = resolved;
            } else {
                var buf: [256]u8 = undefined;
                printErrColor(Color.red, "error: ");
                const msg = std.fmt.bufPrint(&buf, "no version matching {s} for {s}\n", .{ v, pkg }) catch "no matching version\n";
                writeStderr(msg);
                return error.GitFailed;
            }
        }
    }

    var buf: [512]u8 = undefined;
    printColor(Color.bold, "Installing ");
    printColor(Color.bold ++ Color.cyan, pkg);
    if (install_version) |v| {
        writeStdout("@");
        writeStdout(v);
    }
    writeStdout("...\n");

    const pkg_dir = try joinPath(allocator, config.src_dir, pkg);
    defer allocator.free(pkg_dir);

    const clone_url = if (parsed.source) |s| s else blk: {
        break :blk std.fmt.bufPrint(&buf, "{s}/{s}.git", .{ config.org, pkg }) catch return error.OutOfMemory;
    };

    if (!dirExists(allocator, pkg_dir)) {
        writeStdout("  Cloning ");
        writeStdout(clone_url);
        writeStdout("...\n");
        const url_copy = try allocator.dupe(u8, clone_url);
        defer allocator.free(url_copy);
        runGit(allocator, &.{ "clone", "--quiet", "--", url_copy, pkg_dir }) catch {
            printErrColor(Color.red, "  Failed to clone repository\n");
            return error.GitFailed;
        };
    }

    if (install_version) |v| {
        printBuf(&buf, "  Checking out {s}...\n", .{v});
        runGit(allocator, &.{ "-C", pkg_dir, "fetch", "--quiet", "--tags" }) catch {};
        checkoutVersion(allocator, pkg_dir, v) catch {
            printErrColor(Color.red, "  Failed to checkout version\n");
            return error.GitFailed;
        };
    }

    const resolved_sha = getPkgSha(allocator, config.src_dir, pkg) orelse "unknown";
    printBuf(&buf, "  Resolved: {s}\n", .{resolved_sha});

    if (locked_mode) {
        if (getLockedSha(allocator, config.lockfile, pkg)) |locked_sha| {
            defer allocator.free(locked_sha);
            if (!std.mem.eql(u8, resolved_sha, locked_sha)) {
                printErrColor(Color.red, "error: ");
                const msg = std.fmt.bufPrint(&buf, "SHA mismatch for {s} (locked: {s}, got: {s})\n", .{ pkg, locked_sha, resolved_sha }) catch "SHA mismatch\n";
                writeStderr(msg);
                std.process.exit(1);
            }
        }
    }

    if (getPkgManifest(allocator, config.src_dir, pkg)) |manifest| {
        defer manifest.deinit(allocator);
        if (manifest.depends) |deps| {
            var dep_it = std.mem.splitScalar(u8, deps, ' ');
            while (dep_it.next()) |dep| {
                if (dep.len > 0) {
                    try doInstall(allocator, config, dep, locked_mode, visited);
                }
            }
        }

        if (manifest.build_cmd) |build_cmd| {
            try runBuildCommand(allocator, pkg, build_cmd, pkg_dir);
        }
    }

    const lib_src = try joinPath(allocator, pkg_dir, "lib");
    defer allocator.free(lib_src);
    if (dirExists(allocator, lib_src)) {
        writeStdout("  Installing libraries...\n");
        try installLibTree(allocator, lib_src, config.lib_dir);
    }

    const dylib_count = try copyDylibsFromPkg(allocator, pkg_dir, config.lib_dir);
    if (dylib_count > 0) {
        printBuf(&buf, "  Installed {d} native library(s)\n", .{dylib_count});
    }

    try appendFile(allocator, config.installed, pkg);
    try updateLockfile(allocator, config.lockfile, pkg, resolved_sha, parsed.source);
    writeStdout("  ");
    printColor(Color.green, pkg);
    printBuf(&buf, " installed (locked at {s})\n", .{resolved_sha});
}

fn doRemove(allocator: std.mem.Allocator, config: Config, pkg: []const u8) !void {
    if (!isValidPkgName(pkg)) {
        printErrColor(Color.red, "error: ");
        writeStderr("invalid package name '");
        writeStderr(pkg);
        writeStderr("' (only alphanumeric, '-', '_' allowed)\n");
        return error.InvalidPackageName;
    }

    if (!isInstalled(allocator, config.installed, pkg)) {
        printErrColor(Color.red, pkg);
        writeStderr(" is not installed\n");
        return error.NotInstalled;
    }

    printColor(Color.bold, "Removing ");
    printColor(Color.bold ++ Color.cyan, pkg);
    writeStdout("...\n");

    const pkg_dir = try joinPath(allocator, config.src_dir, pkg);
    defer allocator.free(pkg_dir);
    const pkg_lib = try joinPath(allocator, pkg_dir, "lib");
    defer allocator.free(pkg_lib);

    if (dirExists(allocator, pkg_lib)) {
        try removeSldFiles(allocator, pkg_lib, config.lib_dir);
    }

    try removeDylibsFromPkg(allocator, pkg_dir, config.lib_dir);
    try removeFromInstalled(allocator, config.installed, pkg);
    try removeFromLockfile(allocator, config.lockfile, pkg);
    try removeDir(allocator, pkg_dir);

    writeStdout("  ");
    printColor(Color.green, pkg);
    writeStdout(" removed\n");
}

fn doList(allocator: std.mem.Allocator, config: Config) !void {
    const content = readFile(allocator, config.installed) catch {
        writeStdout("No packages installed\n");
        return;
    };
    defer allocator.free(content);

    if (std.mem.trim(u8, content, " \t\n\r").len == 0) {
        writeStdout("No packages installed\n");
        return;
    }

    writeStdout("Installed packages:\n");
    var buf: [512]u8 = undefined;
    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |pkg| {
        if (pkg.len == 0) continue;
        const entry = getLockedEntry(allocator, config.lockfile, pkg);
        const sha_short = if (entry) |e| e.sha[0..@min(12, e.sha.len)] else "unknown";
        const source = if (entry) |e| e.source else null;
        defer if (entry) |e| {
            allocator.free(e.sha);
            if (e.source) |s| allocator.free(s);
        };

        writeStdout("  ");
        writeStdout(pkg);
        writeStdout("  ");
        writeStdout(sha_short);

        if (getPkgManifest(allocator, config.src_dir, pkg)) |manifest| {
            defer manifest.deinit(allocator);
            if (manifest.depends) |deps| {
                printBuf(&buf, " (depends: {s})", .{deps});
            }
        }
        if (source) |s| {
            writeStdout(" (from: ");
            writeStdout(s);
            writeStdout(")");
        }
        writeStdout("\n");
    }
}

fn doUpdate(allocator: std.mem.Allocator, config: Config, pkg: ?[]const u8) !void {
    if (pkg) |p| {
        if (!isInstalled(allocator, config.installed, p)) {
            printErrColor(Color.red, p);
            writeStderr(" is not installed\n");
            return error.NotInstalled;
        }

        var buf: [256]u8 = undefined;
        printColor(Color.bold, "Updating ");
        printColor(Color.bold ++ Color.cyan, p);
        writeStdout("...\n");

        const pkg_dir = try joinPath(allocator, config.src_dir, p);
        defer allocator.free(pkg_dir);

        const locked_entry = getLockedEntry(allocator, config.lockfile, p);
        const expected_source = if (locked_entry) |e| e.source else null;
        defer if (locked_entry) |e| {
            allocator.free(e.sha);
            if (e.source) |s| allocator.free(s);
        };

        var url_buf: [512]u8 = undefined;
        const expected_url = expected_source orelse
            (std.fmt.bufPrint(&url_buf, "{s}/{s}.git", .{ config.org, p }) catch p);

        if (runGitCapture(allocator, &.{ "-C", pkg_dir, "config", "remote.origin.url" })) |current_origin| {
            defer allocator.free(current_origin);
            const trimmed = std.mem.trim(u8, current_origin, " \t\r\n");
            if (!std.mem.eql(u8, trimmed, expected_url)) {
                writeStdout("  Updating remote origin...\n");
                runGit(allocator, &.{ "-C", pkg_dir, "remote", "set-url", "origin", expected_url }) catch {};
            }
        } else |_| {}

        runGit(allocator, &.{ "-C", pkg_dir, "pull", "--quiet" }) catch {
            printErrColor(Color.red, "  Failed to pull\n");
            return error.GitFailed;
        };

        if (getPkgManifest(allocator, config.src_dir, p)) |manifest| {
            defer manifest.deinit(allocator);
            if (manifest.build_cmd) |build_cmd| {
                try runBuildCommand(allocator, p, build_cmd, pkg_dir);
            }
        }

        const lib_src = try joinPath(allocator, pkg_dir, "lib");
        defer allocator.free(lib_src);
        if (dirExists(allocator, lib_src)) {
            try installLibTree(allocator, lib_src, config.lib_dir);
        }

        _ = try copyDylibsFromPkg(allocator, pkg_dir, config.lib_dir);

        const new_sha = getPkgSha(allocator, config.src_dir, p) orelse "unknown";
        try updateLockfile(allocator, config.lockfile, p, new_sha, expected_source);
        writeStdout("  ");
        printColor(Color.green, p);
        printBuf(&buf, " updated (now at {s})\n", .{new_sha});
    } else {
        const content = readFile(allocator, config.installed) catch {
            writeStdout("No packages to update\n");
            return;
        };
        defer allocator.free(content);

        if (std.mem.trim(u8, content, " \t\n\r").len == 0) {
            writeStdout("No packages to update\n");
            return;
        }

        var packages: std.ArrayList([]const u8) = .empty;
        defer packages.deinit(allocator);
        var lines = std.mem.splitScalar(u8, content, '\n');
        while (lines.next()) |line| {
            if (line.len > 0) {
                const copy = allocator.dupe(u8, line) catch continue;
                packages.append(allocator, copy) catch continue;
            }
        }

        var any_failed = false;
        for (packages.items) |p| {
            doUpdate(allocator, config, p) catch {
                any_failed = true;
            };
        }
        if (any_failed) {
            printErrColor(Color.red, "Some packages failed to update\n");
            std.process.exit(1);
        }
    }
}

fn doVerify(allocator: std.mem.Allocator, config: Config) !void {
    const content = readFile(allocator, config.lockfile) catch {
        writeStdout("No lockfile found\n");
        return error.NoLockfile;
    };
    defer allocator.free(content);

    writeStdout("Verifying installed packages against lockfile...\n");
    var buf: [512]u8 = undefined;
    var ok = true;
    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        const space = std.mem.indexOfScalar(u8, line, ' ') orelse continue;
        const pkg = line[0..space];
        const rest = line[space + 1 ..];
        const locked_sha = if (std.mem.indexOfScalar(u8, rest, ' ')) |sp2| rest[0..sp2] else rest;

        const current_sha = getPkgSha(allocator, config.src_dir, pkg);
        if (current_sha == null) {
            writeStdout("  ");
            printColor(Color.red, "MISSING");
            printBuf(&buf, ": {s} (not cloned)\n", .{pkg});
            ok = false;
        } else if (!std.mem.eql(u8, current_sha.?, locked_sha)) {
            const cur_short = current_sha.?[0..@min(12, current_sha.?.len)];
            const lock_short = locked_sha[0..@min(12, locked_sha.len)];
            writeStdout("  ");
            printColor(Color.yellow, "MISMATCH");
            printBuf(&buf, ": {s} (locked: {s}, actual: {s})\n", .{ pkg, lock_short, cur_short });
            ok = false;
        } else {
            const lock_short = locked_sha[0..@min(12, locked_sha.len)];
            writeStdout("  ");
            printColor(Color.green, "OK");
            printBuf(&buf, ": {s} ({s})\n", .{ pkg, lock_short });
        }
    }

    if (ok) {
        printColor(Color.green, "All packages verified.\n");
    } else {
        printColor(Color.red, "Verification failed.\n");
        return error.VerifyFailed;
    }
}

fn printUsage() void {
    writeStdout(
        "thottam v" ++ version ++ " — package manager for Kaappi Scheme\n" ++
            "\n" ++
            "Usage: thottam [--locked] <command> [args]\n" ++
            "\n" ++
            "Commands:\n" ++
            "  install <pkg>[@<ver>][::url]        Install a package (optionally pinned/sourced)\n" ++
            "  remove <package>                   Remove a package\n" ++
            "  list                               List installed packages with commit SHAs\n" ++
            "  update [package]                   Update one or all packages\n" ++
            "  verify                             Check installs match the lockfile\n" ++
            "\n" ++
            "Flags:\n" ++
            "  --locked     Refuse to install packages not in the lockfile\n" ++
            "  -h, --help   Show this help message\n" ++
            "  --version    Show version\n" ++
            "  --completions <shell> Output completion script (bash, zsh, fish)\n" ++
            "\n" ++
            "Packages are installed to ~/.kaappi/lib/\n" ++
            "Lockfile: ~/.kaappi/thottam.lock\n" ++
            "\n" ++
            "Security: thottam runs the build: command from kaappi.pkg and copies\n" ++
            "native libraries to ~/.kaappi/lib/ (auto-loaded by ffi-open). Review\n" ++
            "package manifests before installing from untrusted sources.\n",
    );
}

pub fn getenv(name: [*:0]const u8) ?[]const u8 {
    const val = platform.getenv(name) orelse return null;
    return std.mem.sliceTo(val, 0);
}

fn buildConfig(allocator: std.mem.Allocator) !Config {
    const home = getenv("KAAPPI_HOME") orelse blk: {
        // Windows shells set USERPROFILE, not HOME (git-bash sets both).
        const user_home = getenv("HOME") orelse
            (if (platform.is_windows) getenv("USERPROFILE") else null) orelse
            fatal(if (platform.is_windows) "neither HOME nor USERPROFILE is set" else "HOME not set");
        break :blk try std.mem.concat(allocator, u8, &.{ user_home, "/.kaappi" });
    };
    const org = getenv("KAAPPI_ORG") orelse "https://github.com/kaappi";

    return .{
        .home = home,
        .org = org,
        .lib_dir = try std.mem.concat(allocator, u8, &.{ home, "/lib" }),
        .src_dir = try std.mem.concat(allocator, u8, &.{ home, "/src" }),
        .installed = try std.mem.concat(allocator, u8, &.{ home, "/installed.txt" }),
        .lockfile = try std.mem.concat(allocator, u8, &.{ home, "/thottam.lock" }),
    };
}

fn ensureDirs(allocator: std.mem.Allocator, config: Config) void {
    tfs.makeDirRecursive(allocator, config.lib_dir) catch {};
    tfs.makeDirRecursive(allocator, config.src_dir) catch {};
    if (!fileExists(allocator, config.installed)) {
        tfs.touchFile(allocator, config.installed) catch {};
    }
}

pub fn main(init: std.process.Init.Minimal) !void {
    var da = if (@import("builtin").mode == .Debug) std.heap.DebugAllocator(.{}).init;
    defer if (@import("builtin").mode == .Debug) {
        _ = da.deinit();
    };
    const allocator = if (@import("builtin").mode == .Debug) da.allocator() else std.heap.c_allocator;

    initColor();

    var args = platform.argsIterate(init.args);
    _ = args.skip();

    var locked_mode = false;
    var subcommand: ?[]const u8 = null;
    var sub_arg: ?[]const u8 = null;

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--locked")) {
            locked_mode = true;
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            printUsage();
            return;
        } else if (std.mem.eql(u8, arg, "--version")) {
            writeStdout("thottam v" ++ version ++ "\n");
            return;
        } else if (std.mem.eql(u8, arg, "--completions")) {
            if (args.next()) |shell| {
                if (@import("completions.zig").thottam(shell)) |script| {
                    writeStdout(script);
                } else {
                    writeStderr("unknown shell: ");
                    writeStderr(shell);
                    writeStderr("\nSupported: bash, zsh, fish\n");
                }
            } else {
                writeStderr("--completions requires a shell name (bash, zsh, fish)\n");
            }
            return;
        } else if (subcommand == null) {
            subcommand = arg;
        } else if (sub_arg == null) {
            sub_arg = arg;
        }
    }

    const config = try buildConfig(allocator);
    ensureDirs(allocator, config);

    const cmd = subcommand orelse {
        printUsage();
        return;
    };

    if (std.mem.eql(u8, cmd, "install")) {
        const spec = sub_arg orelse {
            writeStderr("Usage: thottam install <package>[@<version>][::url]\n");
            std.process.exit(1);
        };
        var visited = std.StringHashMap(void).init(allocator);
        defer freeVisited(allocator, &visited);
        doInstall(allocator, config, spec, locked_mode, &visited) catch |err| {
            if (err == error.GitFailed or err == error.BuildFailed or err == error.CopyFailed) std.process.exit(1);
            return err;
        };
    } else if (std.mem.eql(u8, cmd, "remove")) {
        const pkg = sub_arg orelse {
            writeStderr("Usage: thottam remove <package>\n");
            std.process.exit(1);
        };
        doRemove(allocator, config, pkg) catch |err| {
            if (err == error.NotInstalled) std.process.exit(1);
            return err;
        };
    } else if (std.mem.eql(u8, cmd, "list")) {
        try doList(allocator, config);
    } else if (std.mem.eql(u8, cmd, "update")) {
        doUpdate(allocator, config, sub_arg) catch |err| {
            if (err == error.NotInstalled or err == error.GitFailed or err == error.CopyFailed) std.process.exit(1);
            return err;
        };
    } else if (std.mem.eql(u8, cmd, "verify")) {
        doVerify(allocator, config) catch |err| {
            if (err == error.VerifyFailed or err == error.NoLockfile) std.process.exit(1);
            return err;
        };
    } else {
        printUsage();
    }
}

// Pull in the sibling modules' tests: the test binary's root is this file,
// and Zig only collects tests from files referenced by a test block.
test {
    _ = semver;
    _ = proc;
    _ = state;
    _ = tfs;
}

test "markVisited copies keys so freed dependency names stay valid (issue #784)" {
    const allocator = std.testing.allocator;
    var visited = std.StringHashMap(void).init(allocator);
    defer freeVisited(allocator, &visited);

    const dep = try allocator.dupe(u8, "rd");
    try std.testing.expect(try markVisited(allocator, &visited, dep));
    @memset(dep, 0xaa);
    allocator.free(dep);

    try std.testing.expect(!try markVisited(allocator, &visited, "rd"));
    try std.testing.expect(try markVisited(allocator, &visited, "re"));
}

test "dylib_ext is correct for platform" {
    if (builtin.os.tag == .macos) {
        try std.testing.expectEqualStrings(".dylib", dylib_ext);
    } else if (builtin.os.tag == .windows) {
        try std.testing.expectEqualStrings(".dll", dylib_ext);
    } else {
        try std.testing.expectEqualStrings(".so", dylib_ext);
    }
}
