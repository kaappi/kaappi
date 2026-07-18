const std = @import("std");
const platform = @import("platform.zig");
const types = @import("types.zig");
const primitives = @import("primitives.zig");
const vm_mod = @import("vm.zig");
const Value = types.Value;
const PrimitiveError = primitives.PrimitiveError;
const LS = primitives.LibSet;
const memory = @import("memory.zig");
const GC = memory.GC;
const arith = @import("primitives_arithmetic.zig");

extern fn mkstemp(template: [*:0]u8) c_int;

extern "c" fn truncate(path: [*:0]const u8, length: std.c.off_t) c_int;
extern "c" fn mkfifo(path: [*:0]const u8, mode: std.c.mode_t) c_int;
extern "c" fn chown(path: [*:0]const u8, owner: std.c.uid_t, group: std.c.gid_t) c_int;
extern "c" fn getgroups(size: c_int, list: [*]std.c.gid_t) c_int;
extern "c" fn nice(inc: c_int) c_int;
extern "c" fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;
extern "c" fn unsetenv(name: [*:0]const u8) c_int;
// std.c.getgrnam is misdeclared as returning ?*passwd (Zig 0.16 bug)
extern "c" fn getgrnam(name: [*:0]const u8) ?*std.c.group;
const is_linux = @import("builtin").os.tag == .linux;

fn validateMode(gc: *GC, val: Value) PrimitiveError!std.c.mode_t {
    if (!types.isFixnum(val)) return primitives.typeError("set-file-mode", "integer", val);
    const n = types.toFixnum(val);
    // POSIX permission modes use only the low 12 bits (07777). Bounding by
    // maxInt(mode_t) is platform-dependent: mode_t is u16 on macOS but u32
    // on Linux, so out-of-range values were rejected on one and silently
    // passed to chmod on the other.
    if (n < 0 or n > 0o7777) {
        _ = try raiseFileError(gc, "mode value out of range", val);
        unreachable;
    }
    return @truncate(@as(u64, @intCast(n)));
}

fn validateUid(gc: *GC, val: Value) PrimitiveError!std.c.uid_t {
    const n = types.toFixnum(val);
    if (n == -1) return @bitCast(@as(u32, 0xFFFFFFFF));
    if (n < 0 or n > std.math.maxInt(std.c.uid_t)) {
        _ = try raiseFileError(gc, "uid/gid value out of range", val);
        unreachable;
    }
    return @truncate(@as(u64, @intCast(n)));
}

const StatResult = struct {
    mode: u32,
    size: i64,
    mtime_sec: i64,
    atime_sec: i64,
    ctime_sec: i64,
    dev: u64,
    ino: u64,
    nlinks: u64,
    rdev: u64,
    blksize: i64,
    blocks: i64,
    uid: u32,
    gid: u32,
};

fn makedev(major: u64, minor: u64) u64 {
    return ((major & 0xfff) << 8) | (minor & 0xff) |
        ((minor & ~@as(u64, 0xff)) << 12) | ((major & ~@as(u64, 0xfff)) << 32);
}

fn doStat(path: [*:0]const u8, follow: bool) ?StatResult {
    if (comptime platform.is_windows) {
        // _wstat64 always follows reparse points (`follow` has no effect)
        // and Windows has no POSIX uid/gid/blocks; absent concepts report
        // as zero, exactly like SRFI-170 suggests for hosts without them.
        var wbuf: platform.WPathBuf = undefined;
        const wpath = platform.widen(&wbuf, std.mem.sliceTo(path, 0)) orelse return null;
        var st: platform.win.Stat64 = undefined;
        if (platform.win._wstat64(wpath.ptr, &st) != 0) return null;
        return .{
            .mode = @intCast(st.st_mode),
            .size = st.st_size,
            .mtime_sec = st.st_mtime,
            .atime_sec = st.st_atime,
            .ctime_sec = st.st_ctime,
            .dev = @intCast(st.st_dev),
            .ino = @intCast(st.st_ino),
            .nlinks = @intCast(@max(st.st_nlink, 0)),
            .rdev = @intCast(st.st_rdev),
            .blksize = 0,
            .blocks = 0,
            .uid = 0,
            .gid = 0,
        };
    }
    if (is_linux) {
        const linux = std.os.linux;
        var sx: linux.Statx = undefined;
        var flags: u32 = 0x0000;
        if (!follow) flags |= 0x100;
        const rc = linux.statx(@bitCast(@as(i32, std.posix.AT.FDCWD)), path, flags, linux.STATX.BASIC_STATS, &sx);
        if (rc > @as(usize, std.math.maxInt(isize))) return null;
        return .{
            .mode = @intCast(sx.mode),
            .size = @intCast(sx.size),
            .mtime_sec = sx.mtime.sec,
            .atime_sec = sx.atime.sec,
            .ctime_sec = sx.ctime.sec,
            .dev = makedev(sx.dev_major, sx.dev_minor),
            .ino = sx.ino,
            .nlinks = sx.nlink,
            .rdev = makedev(sx.rdev_major, sx.rdev_minor),
            .blksize = @intCast(sx.blksize),
            .blocks = @intCast(sx.blocks),
            .uid = sx.uid,
            .gid = sx.gid,
        };
    } else {
        // NetBSD's plain `lstat` is the pre-6.0 compat symbol filling an
        // old-layout struct stat (32-bit time fields); the modern symbol is
        // `__lstat50` (docs/dev/netbsd.md). Everywhere else the plain name
        // is current.
        const lstat_name = if (@import("builtin").os.tag == .netbsd) "__lstat50" else "lstat";
        const lstat_fn = @extern(*const fn ([*:0]const u8, *std.c.Stat) callconv(.c) c_int, .{ .name = lstat_name });
        var stat_buf: std.c.Stat = undefined;
        const r = if (!follow) lstat_fn(path, &stat_buf) else std.c.fstatat(std.posix.AT.FDCWD, path, &stat_buf, 0);
        if (r != 0) return null;
        return .{
            .mode = @intCast(stat_buf.mode),
            .size = @intCast(stat_buf.size),
            .mtime_sec = stat_buf.mtime().sec,
            .atime_sec = stat_buf.atime().sec,
            .ctime_sec = stat_buf.ctime().sec,
            .dev = @intCast(stat_buf.dev),
            .ino = @intCast(stat_buf.ino),
            .nlinks = @intCast(stat_buf.nlink),
            .rdev = @intCast(stat_buf.rdev),
            .blksize = @intCast(stat_buf.blksize),
            .blocks = @intCast(stat_buf.blocks),
            .uid = stat_buf.uid,
            .gid = stat_buf.gid,
        };
    }
}

pub const specs = [_]primitives.PrimSpec{
    .{ .name = "directory-files", .func = &directoryFiles, .arity = .{ .variadic = 1 }, .libs = LS.initOne(.srfi_170), .sandbox = false, .wasm = false },
    .{ .name = "file-info", .func = &fileInfoFn, .arity = .{ .variadic = 1 }, .libs = LS.initOne(.srfi_170), .sandbox = false, .wasm = false },
    .{ .name = "file-info?", .func = &fileInfoP, .arity = .{ .exact = 1 }, .libs = LS.initOne(.srfi_170), .sandbox = false, .wasm = false },
    .{ .name = "file-info-directory?", .func = &fileInfoDirectoryP, .arity = .{ .exact = 1 }, .libs = LS.initOne(.srfi_170), .sandbox = false, .wasm = false },
    .{ .name = "file-info-regular?", .func = &fileInfoRegularP, .arity = .{ .exact = 1 }, .libs = LS.initOne(.srfi_170), .sandbox = false, .wasm = false },
    .{ .name = "file-info-symlink?", .func = &fileInfoSymlinkP, .arity = .{ .exact = 1 }, .libs = LS.initOne(.srfi_170), .sandbox = false, .wasm = false },
    .{ .name = "file-info:size", .func = &fileInfoSize, .arity = .{ .exact = 1 }, .libs = LS.initOne(.srfi_170), .sandbox = false, .wasm = false },
    .{ .name = "file-info:mtime", .func = &fileInfoMtime, .arity = .{ .exact = 1 }, .libs = LS.initOne(.srfi_170), .sandbox = false, .wasm = false },
    .{ .name = "file-info:mode", .func = &fileInfoMode, .arity = .{ .exact = 1 }, .libs = LS.initOne(.srfi_170), .sandbox = false, .wasm = false },
    .{ .name = "file-info:device", .func = &fileInfoDevice, .arity = .{ .exact = 1 }, .libs = LS.initOne(.srfi_170), .sandbox = false, .wasm = false },
    .{ .name = "file-info:inode", .func = &fileInfoInode, .arity = .{ .exact = 1 }, .libs = LS.initOne(.srfi_170), .sandbox = false, .wasm = false },
    .{ .name = "file-info:nlinks", .func = &fileInfoNlinks, .arity = .{ .exact = 1 }, .libs = LS.initOne(.srfi_170), .sandbox = false, .wasm = false },
    .{ .name = "file-info:uid", .func = &fileInfoUid, .arity = .{ .exact = 1 }, .libs = LS.initOne(.srfi_170), .sandbox = false, .wasm = false },
    .{ .name = "file-info:gid", .func = &fileInfoGid, .arity = .{ .exact = 1 }, .libs = LS.initOne(.srfi_170), .sandbox = false, .wasm = false },
    .{ .name = "file-info:rdev", .func = &fileInfoRdev, .arity = .{ .exact = 1 }, .libs = LS.initOne(.srfi_170), .sandbox = false, .wasm = false },
    .{ .name = "file-info:blksize", .func = &fileInfoBlksize, .arity = .{ .exact = 1 }, .libs = LS.initOne(.srfi_170), .sandbox = false, .wasm = false },
    .{ .name = "file-info:blocks", .func = &fileInfoBlocks, .arity = .{ .exact = 1 }, .libs = LS.initOne(.srfi_170), .sandbox = false, .wasm = false },
    .{ .name = "file-info:atime", .func = &fileInfoAtime, .arity = .{ .exact = 1 }, .libs = LS.initOne(.srfi_170), .sandbox = false, .wasm = false },
    .{ .name = "file-info:ctime", .func = &fileInfoCtime, .arity = .{ .exact = 1 }, .libs = LS.initOne(.srfi_170), .sandbox = false, .wasm = false },
    .{ .name = "file-info-fifo?", .func = &fileInfoFifoP, .arity = .{ .exact = 1 }, .libs = LS.initOne(.srfi_170), .sandbox = false, .wasm = false },
    .{ .name = "file-info-socket?", .func = &fileInfoSocketP, .arity = .{ .exact = 1 }, .libs = LS.initOne(.srfi_170), .sandbox = false, .wasm = false },
    .{ .name = "file-info-device?", .func = &fileInfoDeviceP, .arity = .{ .exact = 1 }, .libs = LS.initOne(.srfi_170), .sandbox = false, .wasm = false },
    .{ .name = "create-directory", .func = &createDirectoryFn, .arity = .{ .variadic = 1 }, .libs = LS.initMany(&.{ .scheme_file, .srfi_170 }), .sandbox = false, .wasm = false },
    .{ .name = "delete-directory", .func = &deleteDirectoryFn, .arity = .{ .exact = 1 }, .libs = LS.initMany(&.{ .scheme_file, .srfi_170 }), .sandbox = false, .wasm = false },
    .{ .name = "rename-file", .func = &renameFileFn, .arity = .{ .exact = 2 }, .libs = LS.initOne(.srfi_170), .sandbox = false, .wasm = false },
    .{ .name = "create-symlink", .func = &createSymlinkFn, .arity = .{ .exact = 2 }, .libs = LS.initOne(.srfi_170), .sandbox = false, .wasm = false },
    .{ .name = "read-symlink", .func = &readSymlinkFn, .arity = .{ .exact = 1 }, .libs = LS.initOne(.srfi_170), .sandbox = false, .wasm = false },
    .{ .name = "create-hard-link", .func = &createHardLinkFn, .arity = .{ .exact = 2 }, .libs = LS.initOne(.srfi_170), .sandbox = false, .wasm = false },
    .{ .name = "real-path", .func = &realPathFn, .arity = .{ .exact = 1 }, .libs = LS.initOne(.srfi_170), .sandbox = false, .wasm = false },
    .{ .name = "set-file-mode", .func = &setFileModeFn, .arity = .{ .exact = 2 }, .libs = LS.initOne(.srfi_170), .sandbox = false, .wasm = false },
    .{ .name = "truncate-file", .func = &truncateFileFn, .arity = .{ .exact = 2 }, .libs = LS.initOne(.srfi_170), .sandbox = false, .wasm = false },
    .{ .name = "create-fifo", .func = &createFifoFn, .arity = .{ .variadic = 1 }, .libs = LS.initOne(.srfi_170), .sandbox = false, .wasm = false },
    .{ .name = "set-file-owner", .func = &setFileOwnerFn, .arity = .{ .exact = 3 }, .libs = LS.initOne(.srfi_170), .sandbox = false, .wasm = false },
    .{ .name = "set-file-times", .func = &setFileTimesFn, .arity = .{ .variadic = 1 }, .libs = LS.initOne(.srfi_170), .sandbox = false, .wasm = false },
    .{ .name = "file-info-type", .func = &fileInfoTypeFn, .arity = .{ .exact = 1 }, .libs = LS.initOne(.srfi_170), .sandbox = false, .wasm = false },
    .{ .name = "temp-file-prefix", .func = &tempFilePrefixFn, .arity = .{ .exact = 0 }, .libs = LS.initOne(.srfi_170), .sandbox = false, .wasm = false },
    .{ .name = "create-temp-file", .func = &createTempFileFn, .arity = .{ .variadic = 0 }, .libs = LS.initOne(.srfi_170), .sandbox = false, .wasm = false },
    .{ .name = "pid", .func = &pidFn, .arity = .{ .exact = 0 }, .libs = LS.initOne(.srfi_170), .sandbox = false, .wasm = false },
    .{ .name = "umask", .func = &umaskFn, .arity = .{ .exact = 0 }, .libs = LS.initOne(.srfi_170), .sandbox = false, .wasm = false },
    .{ .name = "set-umask!", .func = &setUmaskFn, .arity = .{ .exact = 1 }, .libs = LS.initOne(.srfi_170), .sandbox = false, .wasm = false },
    .{ .name = "current-directory", .func = &currentDirectoryFn, .arity = .{ .exact = 0 }, .libs = LS.initOne(.srfi_170), .sandbox = false, .wasm = false },
    .{ .name = "set-current-directory!", .func = &setCurrentDirectoryFn, .arity = .{ .exact = 1 }, .libs = LS.initOne(.srfi_170), .sandbox = false, .wasm = false },
    .{ .name = "user-uid", .func = &userUidFn, .arity = .{ .exact = 0 }, .libs = LS.initOne(.srfi_170), .sandbox = false, .wasm = false },
    .{ .name = "user-gid", .func = &userGidFn, .arity = .{ .exact = 0 }, .libs = LS.initOne(.srfi_170), .sandbox = false, .wasm = false },
    .{ .name = "user-effective-uid", .func = &userEffectiveUidFn, .arity = .{ .exact = 0 }, .libs = LS.initOne(.srfi_170), .sandbox = false, .wasm = false },
    .{ .name = "user-effective-gid", .func = &userEffectiveGidFn, .arity = .{ .exact = 0 }, .libs = LS.initOne(.srfi_170), .sandbox = false, .wasm = false },
    .{ .name = "user-supplementary-gids", .func = &userSupplementaryGidsFn, .arity = .{ .exact = 0 }, .libs = LS.initOne(.srfi_170), .sandbox = false, .wasm = false },
    .{ .name = "nice", .func = &niceFn, .arity = .{ .variadic = 0 }, .libs = LS.initOne(.srfi_170), .sandbox = false, .wasm = false },
    .{ .name = "set-environment-variable!", .func = &setEnvVarFn, .arity = .{ .exact = 2 }, .libs = LS.initOne(.srfi_170), .sandbox = false, .wasm = false },
    .{ .name = "delete-environment-variable!", .func = &deleteEnvVarFn, .arity = .{ .exact = 1 }, .libs = LS.initOne(.srfi_170), .sandbox = false, .wasm = false },
    .{ .name = "terminal?", .func = &terminalP, .arity = .{ .exact = 1 }, .libs = LS.initOne(.srfi_170), .sandbox = false, .wasm = false },
    .{ .name = "user-info", .func = &userInfoFn, .arity = .{ .exact = 1 }, .libs = LS.initOne(.srfi_170), .sandbox = false, .wasm = false },
    .{ .name = "user-info?", .func = &userInfoP, .arity = .{ .exact = 1 }, .libs = LS.initOne(.srfi_170), .sandbox = false, .wasm = false },
    .{ .name = "user-info:name", .func = &userInfoName, .arity = .{ .exact = 1 }, .libs = LS.initOne(.srfi_170), .sandbox = false, .wasm = false },
    .{ .name = "user-info:uid", .func = &userInfoUid, .arity = .{ .exact = 1 }, .libs = LS.initOne(.srfi_170), .sandbox = false, .wasm = false },
    .{ .name = "user-info:gid", .func = &userInfoGidFn, .arity = .{ .exact = 1 }, .libs = LS.initOne(.srfi_170), .sandbox = false, .wasm = false },
    .{ .name = "user-info:home-dir", .func = &userInfoHomeDir, .arity = .{ .exact = 1 }, .libs = LS.initOne(.srfi_170), .sandbox = false, .wasm = false },
    .{ .name = "user-info:shell", .func = &userInfoShell, .arity = .{ .exact = 1 }, .libs = LS.initOne(.srfi_170), .sandbox = false, .wasm = false },
    .{ .name = "user-info:full-name", .func = &userInfoFullName, .arity = .{ .exact = 1 }, .libs = LS.initOne(.srfi_170), .sandbox = false, .wasm = false },
    .{ .name = "group-info", .func = &groupInfoFn, .arity = .{ .exact = 1 }, .libs = LS.initOne(.srfi_170), .sandbox = false, .wasm = false },
    .{ .name = "group-info?", .func = &groupInfoP, .arity = .{ .exact = 1 }, .libs = LS.initOne(.srfi_170), .sandbox = false, .wasm = false },
    .{ .name = "group-info:name", .func = &groupInfoName, .arity = .{ .exact = 1 }, .libs = LS.initOne(.srfi_170), .sandbox = false, .wasm = false },
    .{ .name = "group-info:gid", .func = &groupInfoGidFn, .arity = .{ .exact = 1 }, .libs = LS.initOne(.srfi_170), .sandbox = false, .wasm = false },
    .{ .name = "open-directory", .func = &openDirectoryFn, .arity = .{ .variadic = 1 }, .libs = LS.initOne(.srfi_170), .sandbox = false, .wasm = false },
    .{ .name = "read-directory", .func = &readDirectoryFn, .arity = .{ .exact = 1 }, .libs = LS.initOne(.srfi_170), .sandbox = false, .wasm = false },
    .{ .name = "close-directory", .func = &closeDirectoryFn, .arity = .{ .exact = 1 }, .libs = LS.initOne(.srfi_170), .sandbox = false, .wasm = false },
    .{ .name = "posix-time", .func = &posixTimeFn, .arity = .{ .exact = 0 }, .libs = LS.initOne(.srfi_170), .sandbox = false, .wasm = false },
    .{ .name = "monotonic-time", .func = &monotonicTimeFn, .arity = .{ .exact = 0 }, .libs = LS.initOne(.srfi_170), .sandbox = false, .wasm = false },
};

fn raiseFileError(gc: *GC, msg_text: []const u8, irritant: Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError; // bare-ok: no VM
    var msg = gc.allocString(msg_text) catch return PrimitiveError.OutOfMemory;
    gc.pushRoot(&msg);
    defer gc.popRoot();
    const irritants = gc.allocPair(irritant, types.NIL) catch return PrimitiveError.OutOfMemory;
    var irritants_root = irritants;
    gc.pushRoot(&irritants_root);
    defer gc.popRoot();
    const err_obj = gc.allocErrorObject(msg, irritants_root) catch return PrimitiveError.OutOfMemory;
    types.toObject(err_obj).as(types.ErrorObject).error_type = .file;
    vm.current_exception = err_obj;
    return PrimitiveError.ExceptionRaised;
}

/// POSIX-only operations raise a clean, catchable file error on Windows
/// instead of being silently absent — the name stays bound, so portable
/// code can probe with guard/with-exception-handler.
fn raiseUnsupportedOnWindows(comptime name: []const u8) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    return raiseFileError(gc, name ++ ": not supported on Windows", types.FALSE);
}

fn extractPath(val: Value) ?[]const u8 {
    if (!types.isString(val)) return null;
    const str = types.toObject(val).as(types.SchemeString);
    return str.data[0..str.len];
}

fn validatePathNoNul(path: []const u8, original: Value) PrimitiveError!void {
    if (std.mem.indexOfScalar(u8, path, 0) != null) {
        const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
        _ = try raiseFileError(gc, "path contains embedded NUL byte", original);
    }
}

// -------------------------------------------------------------------------
// (directory-files dir [dotfiles?])
// -------------------------------------------------------------------------

fn directoryFiles(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const path = extractPath(args[0]) orelse return primitives.typeError("directory-files", "string", args[0]);
    try validatePathNoNul(path, args[0]);
    const include_dotfiles = if (args.len > 1) types.isTruthy(args[1]) else false;

    const path_z = gc.allocator.dupeZ(u8, path) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(path_z);

    var dir = platform.DirIter.open(path_z) orelse {
        return raiseFileError(gc, "cannot open directory", args[0]);
    };
    defer dir.close();

    var str_val: Value = types.NIL;
    gc.pushRoot(&str_val);
    defer gc.popRoot();
    var result: Value = types.NIL;
    gc.pushRoot(&result);
    defer gc.popRoot();

    while (dir.next()) |name| {
        if (std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) continue;
        if (!include_dotfiles and name.len > 0 and name[0] == '.') continue;

        str_val = gc.allocString(name) catch return PrimitiveError.OutOfMemory;
        result = gc.allocPair(str_val, result) catch return PrimitiveError.OutOfMemory;
    }

    return result;
}

// -------------------------------------------------------------------------
// (file-info path [follow?])
// -------------------------------------------------------------------------

fn fileInfoFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const path = extractPath(args[0]) orelse return primitives.typeError("file-info", "string", args[0]);
    try validatePathNoNul(path, args[0]);
    const follow = if (args.len > 1) types.isTruthy(args[1]) else true;

    const path_z = gc.allocator.dupeZ(u8, path) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(path_z);

    const sr = doStat(path_z, follow) orelse {
        return raiseFileError(gc, "cannot stat file", args[0]);
    };

    // std.c.S doesn't exist on Windows; these mode bits are identical
    // across every target we build (the CRT uses the classic values).
    const S = if (platform.is_windows) struct {
        const IFMT: u32 = 0xF000;
        const IFDIR: u32 = 0x4000;
        const IFREG: u32 = 0x8000;
        const IFLNK: u32 = 0xA000;
        const IFIFO: u32 = 0x1000;
        const IFSOCK: u32 = 0xC000;
        const IFCHR: u32 = 0x2000;
        const IFBLK: u32 = 0x6000;
    } else std.c.S;
    const file_type: types.FileInfo.FileType = blk: {
        const masked = sr.mode & S.IFMT;
        if (masked == S.IFDIR) break :blk .directory;
        if (masked == S.IFREG) break :blk .regular;
        if (masked == S.IFLNK) break :blk .symlink;
        if (masked == S.IFIFO) break :blk .fifo;
        if (masked == S.IFSOCK) break :blk .socket;
        if (masked == S.IFCHR) break :blk .char_device;
        if (masked == S.IFBLK) break :blk .block_device;
        break :blk .other;
    };

    return gc.allocFileInfo(.{
        .size = @intCast(sr.size),
        .mtime = sr.mtime_sec,
        .atime = sr.atime_sec,
        .ctime = sr.ctime_sec,
        .dev = @bitCast(sr.dev),
        .ino = @bitCast(sr.ino),
        .nlinks = @bitCast(sr.nlinks),
        .rdev = @bitCast(sr.rdev),
        .blksize = @intCast(sr.blksize),
        .blocks = sr.blocks,
        .mode = sr.mode,
        .uid = sr.uid,
        .gid = sr.gid,
        .file_type = file_type,
    }) catch return PrimitiveError.OutOfMemory;
}

// -------------------------------------------------------------------------
// Predicates
// -------------------------------------------------------------------------

fn fileInfoP(args: []const Value) PrimitiveError!Value {
    return if (types.isFileInfo(args[0])) types.TRUE else types.FALSE;
}

fn fileInfoDirectoryP(args: []const Value) PrimitiveError!Value {
    if (!types.isFileInfo(args[0])) return primitives.typeError("file-info-directory?", "file-info", args[0]);
    return if (types.toFileInfo(args[0]).file_type == .directory) types.TRUE else types.FALSE;
}

fn fileInfoRegularP(args: []const Value) PrimitiveError!Value {
    if (!types.isFileInfo(args[0])) return primitives.typeError("file-info-regular?", "file-info", args[0]);
    return if (types.toFileInfo(args[0]).file_type == .regular) types.TRUE else types.FALSE;
}

fn fileInfoSymlinkP(args: []const Value) PrimitiveError!Value {
    if (!types.isFileInfo(args[0])) return primitives.typeError("file-info-symlink?", "file-info", args[0]);
    return if (types.toFileInfo(args[0]).file_type == .symlink) types.TRUE else types.FALSE;
}

// -------------------------------------------------------------------------
// Accessors
// -------------------------------------------------------------------------

fn fileInfoSize(args: []const Value) PrimitiveError!Value {
    if (!types.isFileInfo(args[0])) return primitives.typeError("file-info:size", "file-info", args[0]);
    return try arith.makeFixnumChecked(types.toFileInfo(args[0]).size);
}

fn fileInfoMtime(args: []const Value) PrimitiveError!Value {
    if (!types.isFileInfo(args[0])) return primitives.typeError("file-info:mtime", "file-info", args[0]);
    return try arith.makeFixnumChecked(types.toFileInfo(args[0]).mtime);
}

fn fileInfoMode(args: []const Value) PrimitiveError!Value {
    if (!types.isFileInfo(args[0])) return primitives.typeError("file-info:mode", "file-info", args[0]);
    return types.makeFixnum(@as(i64, @intCast(types.toFileInfo(args[0]).mode)));
}

fn fileInfoDevice(args: []const Value) PrimitiveError!Value {
    if (!types.isFileInfo(args[0])) return primitives.typeError("file-info:device", "file-info", args[0]);
    return try arith.makeFixnumChecked(types.toFileInfo(args[0]).dev);
}

fn fileInfoInode(args: []const Value) PrimitiveError!Value {
    if (!types.isFileInfo(args[0])) return primitives.typeError("file-info:inode", "file-info", args[0]);
    return try arith.makeFixnumChecked(types.toFileInfo(args[0]).ino);
}

fn fileInfoNlinks(args: []const Value) PrimitiveError!Value {
    if (!types.isFileInfo(args[0])) return primitives.typeError("file-info:nlinks", "file-info", args[0]);
    return try arith.makeFixnumChecked(types.toFileInfo(args[0]).nlinks);
}

fn fileInfoUid(args: []const Value) PrimitiveError!Value {
    if (!types.isFileInfo(args[0])) return primitives.typeError("file-info:uid", "file-info", args[0]);
    return types.makeFixnum(@as(i64, @intCast(types.toFileInfo(args[0]).uid)));
}

fn fileInfoGid(args: []const Value) PrimitiveError!Value {
    if (!types.isFileInfo(args[0])) return primitives.typeError("file-info:gid", "file-info", args[0]);
    return types.makeFixnum(@as(i64, @intCast(types.toFileInfo(args[0]).gid)));
}

fn fileInfoRdev(args: []const Value) PrimitiveError!Value {
    if (!types.isFileInfo(args[0])) return primitives.typeError("file-info:rdev", "file-info", args[0]);
    return try arith.makeFixnumChecked(types.toFileInfo(args[0]).rdev);
}

fn fileInfoBlksize(args: []const Value) PrimitiveError!Value {
    if (!types.isFileInfo(args[0])) return primitives.typeError("file-info:blksize", "file-info", args[0]);
    return try arith.makeFixnumChecked(types.toFileInfo(args[0]).blksize);
}

fn fileInfoBlocks(args: []const Value) PrimitiveError!Value {
    if (!types.isFileInfo(args[0])) return primitives.typeError("file-info:blocks", "file-info", args[0]);
    return try arith.makeFixnumChecked(types.toFileInfo(args[0]).blocks);
}

fn fileInfoAtime(args: []const Value) PrimitiveError!Value {
    if (!types.isFileInfo(args[0])) return primitives.typeError("file-info:atime", "file-info", args[0]);
    return try arith.makeFixnumChecked(types.toFileInfo(args[0]).atime);
}

fn fileInfoCtime(args: []const Value) PrimitiveError!Value {
    if (!types.isFileInfo(args[0])) return primitives.typeError("file-info:ctime", "file-info", args[0]);
    return try arith.makeFixnumChecked(types.toFileInfo(args[0]).ctime);
}

fn fileInfoFifoP(args: []const Value) PrimitiveError!Value {
    if (!types.isFileInfo(args[0])) return primitives.typeError("file-info-fifo?", "file-info", args[0]);
    return if (types.toFileInfo(args[0]).file_type == .fifo) types.TRUE else types.FALSE;
}

fn fileInfoSocketP(args: []const Value) PrimitiveError!Value {
    if (!types.isFileInfo(args[0])) return primitives.typeError("file-info-socket?", "file-info", args[0]);
    return if (types.toFileInfo(args[0]).file_type == .socket) types.TRUE else types.FALSE;
}

fn fileInfoDeviceP(args: []const Value) PrimitiveError!Value {
    if (!types.isFileInfo(args[0])) return primitives.typeError("file-info-device?", "file-info", args[0]);
    const ft = types.toFileInfo(args[0]).file_type;
    return if (ft == .char_device or ft == .block_device) types.TRUE else types.FALSE;
}

// -------------------------------------------------------------------------
// (create-directory path [mode])
// (delete-directory path)
// -------------------------------------------------------------------------

fn createDirectoryFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const path = extractPath(args[0]) orelse return primitives.typeError("create-directory", "string", args[0]);
    try validatePathNoNul(path, args[0]);

    const mode: std.c.mode_t = if (args.len > 1 and types.isFixnum(args[1]))
        try validateMode(gc, args[1])
    else
        0o755;

    const path_z = gc.allocator.dupeZ(u8, path) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(path_z);

    if (platform.mkdir(path_z, @intCast(mode)) != 0) {
        return raiseFileError(gc, "cannot create directory", args[0]);
    }
    return types.VOID;
}

fn deleteDirectoryFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const path = extractPath(args[0]) orelse return primitives.typeError("delete-directory", "string", args[0]);
    try validatePathNoNul(path, args[0]);

    const path_z = gc.allocator.dupeZ(u8, path) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(path_z);

    if (platform.rmdir(path_z) != 0) {
        return raiseFileError(gc, "cannot delete directory", args[0]);
    }
    return types.VOID;
}

// -------------------------------------------------------------------------
// File system operations (SRFI-170 §3.3)
// -------------------------------------------------------------------------

fn renameFileFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const old = extractPath(args[0]) orelse return primitives.typeError("rename-file", "string", args[0]);
    const new = extractPath(args[1]) orelse return primitives.typeError("rename-file", "string", args[1]);
    try validatePathNoNul(old, args[0]);
    try validatePathNoNul(new, args[1]);

    const old_z = gc.allocator.dupeZ(u8, old) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(old_z);
    const new_z = gc.allocator.dupeZ(u8, new) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(new_z);

    if (platform.rename(old_z, new_z) != 0) {
        return raiseFileError(gc, "cannot rename file", args[0]);
    }
    return types.VOID;
}

fn createSymlinkFn(args: []const Value) PrimitiveError!Value {
    if (comptime platform.is_windows) return raiseUnsupportedOnWindows("create-symlink");
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const old = extractPath(args[0]) orelse return primitives.typeError("create-symlink", "string", args[0]);
    const new = extractPath(args[1]) orelse return primitives.typeError("create-symlink", "string", args[1]);
    try validatePathNoNul(old, args[0]);
    try validatePathNoNul(new, args[1]);

    const old_z = gc.allocator.dupeZ(u8, old) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(old_z);
    const new_z = gc.allocator.dupeZ(u8, new) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(new_z);

    if (std.c.symlink(old_z, new_z) != 0) {
        return raiseFileError(gc, "cannot create symlink", args[1]);
    }
    return types.VOID;
}

fn readSymlinkFn(args: []const Value) PrimitiveError!Value {
    if (comptime platform.is_windows) return raiseUnsupportedOnWindows("read-symlink");
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const path = extractPath(args[0]) orelse return primitives.typeError("read-symlink", "string", args[0]);
    try validatePathNoNul(path, args[0]);

    const path_z = gc.allocator.dupeZ(u8, path) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(path_z);

    var buf: [std.posix.PATH_MAX]u8 = undefined;
    const r = std.c.readlink(path_z, &buf, buf.len);
    if (r < 0) {
        return raiseFileError(gc, "cannot read symlink", args[0]);
    }
    if (@as(usize, @intCast(r)) == buf.len) {
        return raiseFileError(gc, "symlink target too long", args[0]);
    }
    return gc.allocString(buf[0..@intCast(r)]) catch return PrimitiveError.OutOfMemory;
}

fn createHardLinkFn(args: []const Value) PrimitiveError!Value {
    if (comptime platform.is_windows) return raiseUnsupportedOnWindows("create-hard-link");
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const old = extractPath(args[0]) orelse return primitives.typeError("create-hard-link", "string", args[0]);
    const new = extractPath(args[1]) orelse return primitives.typeError("create-hard-link", "string", args[1]);
    try validatePathNoNul(old, args[0]);
    try validatePathNoNul(new, args[1]);

    const old_z = gc.allocator.dupeZ(u8, old) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(old_z);
    const new_z = gc.allocator.dupeZ(u8, new) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(new_z);

    if (std.c.link(old_z, new_z) != 0) {
        return raiseFileError(gc, "cannot create hard link", args[1]);
    }
    return types.VOID;
}

fn realPathFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const path = extractPath(args[0]) orelse return primitives.typeError("real-path", "string", args[0]);
    try validatePathNoNul(path, args[0]);

    const path_z = gc.allocator.dupeZ(u8, path) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(path_z);

    var resolved_buf: [platform.PATH_MAX]u8 = undefined;
    const resolved = platform.realPath(path_z, &resolved_buf) orelse {
        return raiseFileError(gc, "cannot resolve path", args[0]);
    };
    return gc.allocString(resolved) catch return PrimitiveError.OutOfMemory;
}

fn setFileModeFn(args: []const Value) PrimitiveError!Value {
    if (comptime platform.is_windows) return raiseUnsupportedOnWindows("set-file-mode");
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const path = extractPath(args[0]) orelse return primitives.typeError("set-file-mode", "string", args[0]);
    try validatePathNoNul(path, args[0]);
    if (!types.isFixnum(args[1])) return primitives.typeError("set-file-mode", "integer", args[1]);

    const path_z = gc.allocator.dupeZ(u8, path) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(path_z);

    const mode = try validateMode(gc, args[1]);
    if (std.c.chmod(path_z, mode) != 0) {
        return raiseFileError(gc, "cannot set file mode", args[0]);
    }
    return types.VOID;
}

fn truncateFileFn(args: []const Value) PrimitiveError!Value {
    if (comptime platform.is_windows) return raiseUnsupportedOnWindows("truncate-file");
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const path = extractPath(args[0]) orelse return primitives.typeError("truncate-file", "string", args[0]);
    try validatePathNoNul(path, args[0]);
    if (!types.isFixnum(args[1])) return primitives.typeError("truncate-file", "integer", args[1]);

    const path_z = gc.allocator.dupeZ(u8, path) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(path_z);

    const len: std.c.off_t = @intCast(types.toFixnum(args[1]));
    if (truncate(path_z, len) != 0) {
        return raiseFileError(gc, "cannot truncate file", args[0]);
    }
    return types.VOID;
}

fn createFifoFn(args: []const Value) PrimitiveError!Value {
    if (comptime platform.is_windows) return raiseUnsupportedOnWindows("create-fifo");
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const path = extractPath(args[0]) orelse return primitives.typeError("create-fifo", "string", args[0]);
    try validatePathNoNul(path, args[0]);

    const mode: std.c.mode_t = if (args.len > 1 and types.isFixnum(args[1]))
        try validateMode(gc, args[1])
    else
        0o664;

    const path_z = gc.allocator.dupeZ(u8, path) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(path_z);

    if (mkfifo(path_z, mode) != 0) {
        return raiseFileError(gc, "cannot create fifo", args[0]);
    }
    return types.VOID;
}

fn setFileOwnerFn(args: []const Value) PrimitiveError!Value {
    if (comptime platform.is_windows) return raiseUnsupportedOnWindows("set-file-owner");
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const path = extractPath(args[0]) orelse return primitives.typeError("set-file-owner", "string", args[0]);
    try validatePathNoNul(path, args[0]);
    if (!types.isFixnum(args[1])) return primitives.typeError("set-file-owner", "integer", args[1]);
    if (!types.isFixnum(args[2])) return primitives.typeError("set-file-owner", "integer", args[2]);

    const path_z = gc.allocator.dupeZ(u8, path) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(path_z);

    const owner: std.c.uid_t = try validateUid(gc, args[1]);
    const group: std.c.gid_t = try validateUid(gc, args[2]);

    if (chown(path_z, owner, group) != 0) {
        return raiseFileError(gc, "cannot set file owner", args[0]);
    }
    return types.VOID;
}

const TIME_NOW: i64 = -1;
const TIME_UNCHANGED: i64 = -2;

fn timeArgToTimespec(args: []const Value, idx: usize) std.c.timespec {
    if (args.len <= idx) return std.c.UTIME.NOW;
    const v = args[idx];
    if (types.isSrfi18Time(v)) {
        const t = types.toSrfi18Time(v);
        return .{ .sec = @intCast(t.seconds), .nsec = @intCast(t.nanoseconds) };
    }
    if (types.isFixnum(v)) {
        const val = types.toFixnum(v);
        if (val == TIME_NOW) return std.c.UTIME.NOW;
        if (val == TIME_UNCHANGED) return std.c.UTIME.OMIT;
        return .{ .sec = @intCast(val), .nsec = 0 };
    }
    return std.c.UTIME.NOW;
}

fn setFileTimesFn(args: []const Value) PrimitiveError!Value {
    if (comptime platform.is_windows) return raiseUnsupportedOnWindows("set-file-times");
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const path = extractPath(args[0]) orelse return primitives.typeError("set-file-times", "string", args[0]);
    try validatePathNoNul(path, args[0]);

    const path_z = gc.allocator.dupeZ(u8, path) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(path_z);

    var times: [2]std.c.timespec = undefined;

    times[0] = timeArgToTimespec(args, 1);
    times[1] = timeArgToTimespec(args, 2);

    if (std.c.utimensat(std.posix.AT.FDCWD, path_z, &times, 0) != 0) {
        return raiseFileError(gc, "cannot set file times", args[0]);
    }
    return types.VOID;
}

// -------------------------------------------------------------------------
// Process state (SRFI-170 §3.5)
// -------------------------------------------------------------------------

fn pidFn(args: []const Value) PrimitiveError!Value {
    _ = args;
    return types.makeFixnum(platform.getPid());
}

fn umaskFn(args: []const Value) PrimitiveError!Value {
    if (comptime platform.is_windows) return raiseUnsupportedOnWindows("umask");
    _ = args;
    const cur = std.c.umask(0);
    _ = std.c.umask(cur);
    return types.makeFixnum(@as(i64, @intCast(cur)));
}

fn setUmaskFn(args: []const Value) PrimitiveError!Value {
    if (comptime platform.is_windows) return raiseUnsupportedOnWindows("set-umask!");
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    if (!types.isFixnum(args[0])) return primitives.typeError("set-umask!", "integer", args[0]);
    const mask = try validateMode(gc, args[0]);
    _ = std.c.umask(mask);
    return types.VOID;
}

fn currentDirectoryFn(args: []const Value) PrimitiveError!Value {
    _ = args;
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    var buf: [platform.PATH_MAX]u8 = undefined;
    const result = platform.getCwd(&buf) orelse {
        return raiseFileError(gc, "cannot get current directory", types.FALSE);
    };
    return gc.allocString(result) catch return PrimitiveError.OutOfMemory;
}

fn setCurrentDirectoryFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const path = extractPath(args[0]) orelse return primitives.typeError("set-current-directory!", "string", args[0]);
    try validatePathNoNul(path, args[0]);

    const path_z = gc.allocator.dupeZ(u8, path) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(path_z);

    if (platform.chdir(path_z) != 0) {
        return raiseFileError(gc, "cannot change directory", args[0]);
    }
    return types.VOID;
}

fn userUidFn(args: []const Value) PrimitiveError!Value {
    if (comptime platform.is_windows) return raiseUnsupportedOnWindows("user-uid");
    _ = args;
    return types.makeFixnum(@as(i64, @intCast(std.c.getuid())));
}

fn userGidFn(args: []const Value) PrimitiveError!Value {
    if (comptime platform.is_windows) return raiseUnsupportedOnWindows("user-gid");
    _ = args;
    return types.makeFixnum(@as(i64, @intCast(std.c.getgid())));
}

fn userEffectiveUidFn(args: []const Value) PrimitiveError!Value {
    if (comptime platform.is_windows) return raiseUnsupportedOnWindows("user-effective-uid");
    _ = args;
    return types.makeFixnum(@as(i64, @intCast(std.c.geteuid())));
}

fn userEffectiveGidFn(args: []const Value) PrimitiveError!Value {
    if (comptime platform.is_windows) return raiseUnsupportedOnWindows("user-effective-gid");
    _ = args;
    return types.makeFixnum(@as(i64, @intCast(std.c.getegid())));
}

fn userSupplementaryGidsFn(args: []const Value) PrimitiveError!Value {
    if (comptime platform.is_windows) return raiseUnsupportedOnWindows("user-supplementary-gids");
    _ = args;
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;

    const count = getgroups(0, undefined);
    if (count < 0) return raiseFileError(gc, "cannot query supplementary groups", types.NIL);
    const gids = gc.allocator.alloc(std.c.gid_t, @intCast(count)) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(gids);
    const n = getgroups(count, gids.ptr);
    if (n < 0) return raiseFileError(gc, "cannot query supplementary groups", types.NIL);

    var result: Value = types.NIL;
    gc.pushRoot(&result);
    defer gc.popRoot();

    var i: usize = @intCast(n);
    while (i > 0) {
        i -= 1;
        const gid_val = types.makeFixnum(@as(i64, @intCast(gids[i])));
        result = gc.allocPair(gid_val, result) catch return PrimitiveError.OutOfMemory;
    }
    return result;
}

fn niceFn(args: []const Value) PrimitiveError!Value {
    if (comptime platform.is_windows) return raiseUnsupportedOnWindows("nice");
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    var delta: c_int = 1;
    if (args.len > 0 and types.isFixnum(args[0])) {
        // Fixnums range up to ±2^47, but nice() takes a C int. An unchecked
        // @intCast panics (SIGABRT) on out-of-range values in ReleaseSafe;
        // reject them as a recoverable Scheme error instead.
        const n = types.toFixnum(args[0]);
        if (n < std.math.minInt(c_int) or n > std.math.maxInt(c_int)) {
            return raiseFileError(gc, "nice value out of range", args[0]);
        }
        delta = @intCast(n);
    }
    const e = std.c._errno();
    e.* = 0;
    const result = nice(delta);
    if (result == -1 and e.* != 0) {
        const irritant = if (args.len > 0) args[0] else types.makeFixnum(1);
        return raiseFileError(gc, "cannot change nice value", irritant);
    }
    return types.makeFixnum(@as(i64, @intCast(result)));
}

// -------------------------------------------------------------------------
// Environment variables (SRFI-170 §3.11)
// -------------------------------------------------------------------------

fn setEnvVarFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const name = extractPath(args[0]) orelse return primitives.typeError("set-environment-variable!", "string", args[0]);
    const value = extractPath(args[1]) orelse return primitives.typeError("set-environment-variable!", "string", args[1]);
    try validatePathNoNul(name, args[0]);
    try validatePathNoNul(value, args[1]);

    platform.setEnv(gc.allocator, name, value) catch {
        return raiseFileError(gc, "cannot set environment variable", args[0]);
    };
    return types.VOID;
}

fn deleteEnvVarFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const name = extractPath(args[0]) orelse return primitives.typeError("delete-environment-variable!", "string", args[0]);
    try validatePathNoNul(name, args[0]);

    platform.unsetEnv(gc.allocator, name) catch return PrimitiveError.OutOfMemory;
    return types.VOID;
}

// -------------------------------------------------------------------------
// Terminal (SRFI-170 §3.12)
// -------------------------------------------------------------------------

fn terminalP(args: []const Value) PrimitiveError!Value {
    if (!types.isPort(args[0])) return primitives.typeError("terminal?", "port", args[0]);
    const port = types.toObject(args[0]).as(types.Port);
    return if (platform.isatty(port.fd)) types.TRUE else types.FALSE;
}

// -------------------------------------------------------------------------
// User/group database (SRFI-170 §3.6)
// -------------------------------------------------------------------------

/// NetBSD renamed the getpw* family when time_t widened in 6.0 (struct
/// passwd carries pw_change/pw_expire): modern code must call
/// `__getpwnam50`/`__getpwuid50`. The plain symbols Zig's std.c binds are
/// the compat pair returning the old layout, which a modern `passwd` read
/// misparses (home dir/shell shifted). getgr* has no time_t and was never
/// renamed.
const netbsd_pw = struct {
    extern "c" fn __getpwnam50(name: [*:0]const u8) ?*std.c.passwd;
    extern "c" fn __getpwuid50(uid: std.c.uid_t) ?*std.c.passwd;
};
const getpwnam_sys = if (@import("builtin").os.tag == .netbsd) netbsd_pw.__getpwnam50 else std.c.getpwnam;
const getpwuid_sys = if (@import("builtin").os.tag == .netbsd) netbsd_pw.__getpwuid50 else std.c.getpwuid;

fn userInfoFn(args: []const Value) PrimitiveError!Value {
    if (comptime platform.is_windows) return raiseUnsupportedOnWindows("user-info");
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;

    const pw = if (types.isFixnum(args[0])) blk: {
        const id_val = types.toFixnum(args[0]);
        if (id_val < 0 or id_val > std.math.maxInt(std.c.uid_t)) return primitives.typeError("user-info", "valid user ID", args[0]);
        const uid: std.c.uid_t = @intCast(@as(u64, @bitCast(id_val)));
        break :blk getpwuid_sys(uid);
    } else if (types.isString(args[0])) blk: {
        const name = extractPath(args[0]) orelse return primitives.typeError("user-info", "string or integer", args[0]);
        try validatePathNoNul(name, args[0]);
        const name_z = gc.allocator.dupeZ(u8, name) catch return PrimitiveError.OutOfMemory;
        defer gc.allocator.free(name_z);
        break :blk getpwnam_sys(name_z);
    } else return primitives.typeError("user-info", "string or integer", args[0]);

    const p = pw orelse return types.FALSE;
    const name_str = std.mem.span(p.name.?);
    const dir_str = std.mem.span(p.dir.?);
    const shell_str = std.mem.span(p.shell.?);
    const gecos_str = if (p.gecos) |g| std.mem.span(g) else "";

    return gc.allocUserInfo(name_str, p.uid, p.gid, dir_str, shell_str, gecos_str) catch return PrimitiveError.OutOfMemory;
}

fn userInfoP(args: []const Value) PrimitiveError!Value {
    return if (types.isUserInfo(args[0])) types.TRUE else types.FALSE;
}

fn userInfoName(args: []const Value) PrimitiveError!Value {
    if (!types.isUserInfo(args[0])) return primitives.typeError("user-info:name", "user-info", args[0]);
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    return gc.allocString(types.toUserInfo(args[0]).name) catch return PrimitiveError.OutOfMemory;
}

fn userInfoUid(args: []const Value) PrimitiveError!Value {
    if (!types.isUserInfo(args[0])) return primitives.typeError("user-info:uid", "user-info", args[0]);
    return types.makeFixnum(@as(i64, @intCast(types.toUserInfo(args[0]).uid)));
}

fn userInfoGidFn(args: []const Value) PrimitiveError!Value {
    if (!types.isUserInfo(args[0])) return primitives.typeError("user-info:gid", "user-info", args[0]);
    return types.makeFixnum(@as(i64, @intCast(types.toUserInfo(args[0]).gid)));
}

fn userInfoHomeDir(args: []const Value) PrimitiveError!Value {
    if (!types.isUserInfo(args[0])) return primitives.typeError("user-info:home-dir", "user-info", args[0]);
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    return gc.allocString(types.toUserInfo(args[0]).home_dir) catch return PrimitiveError.OutOfMemory;
}

fn userInfoShell(args: []const Value) PrimitiveError!Value {
    if (!types.isUserInfo(args[0])) return primitives.typeError("user-info:shell", "user-info", args[0]);
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    return gc.allocString(types.toUserInfo(args[0]).shell) catch return PrimitiveError.OutOfMemory;
}

fn userInfoFullName(args: []const Value) PrimitiveError!Value {
    if (!types.isUserInfo(args[0])) return primitives.typeError("user-info:full-name", "user-info", args[0]);
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    return gc.allocString(types.toUserInfo(args[0]).full_name) catch return PrimitiveError.OutOfMemory;
}

fn groupInfoFn(args: []const Value) PrimitiveError!Value {
    if (comptime platform.is_windows) return raiseUnsupportedOnWindows("group-info");
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;

    if (types.isFixnum(args[0])) {
        const id_val = types.toFixnum(args[0]);
        if (id_val < 0 or id_val > std.math.maxInt(std.c.gid_t)) return primitives.typeError("group-info", "valid group ID", args[0]);
        const gid: std.c.gid_t = @intCast(@as(u64, @bitCast(id_val)));
        const g = std.c.getgrgid(gid) orelse return types.FALSE;
        const name_str = std.mem.span(g.name.?);
        return gc.allocGroupInfo(name_str, g.gid) catch return PrimitiveError.OutOfMemory;
    } else if (types.isString(args[0])) {
        const name = extractPath(args[0]) orelse return primitives.typeError("group-info", "string or integer", args[0]);
        try validatePathNoNul(name, args[0]);
        const name_z = gc.allocator.dupeZ(u8, name) catch return PrimitiveError.OutOfMemory;
        defer gc.allocator.free(name_z);
        const g = getgrnam(name_z) orelse return types.FALSE;
        const name_str = std.mem.span(g.name.?);
        return gc.allocGroupInfo(name_str, g.gid) catch return PrimitiveError.OutOfMemory;
    } else return primitives.typeError("group-info", "string or integer", args[0]);
}

fn groupInfoP(args: []const Value) PrimitiveError!Value {
    return if (types.isGroupInfo(args[0])) types.TRUE else types.FALSE;
}

fn groupInfoName(args: []const Value) PrimitiveError!Value {
    if (!types.isGroupInfo(args[0])) return primitives.typeError("group-info:name", "group-info", args[0]);
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    return gc.allocString(types.toGroupInfo(args[0]).name) catch return PrimitiveError.OutOfMemory;
}

fn groupInfoGidFn(args: []const Value) PrimitiveError!Value {
    if (!types.isGroupInfo(args[0])) return primitives.typeError("group-info:gid", "group-info", args[0]);
    return types.makeFixnum(@as(i64, @intCast(types.toGroupInfo(args[0]).gid)));
}

// -------------------------------------------------------------------------
// Directory traversal (SRFI-170 §3.3)
// -------------------------------------------------------------------------

fn openDirectoryFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const path = extractPath(args[0]) orelse return primitives.typeError("open-directory", "string", args[0]);
    try validatePathNoNul(path, args[0]);
    const include_dotfiles = if (args.len > 1) types.isTruthy(args[1]) else false;

    const path_z = gc.allocator.dupeZ(u8, path) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(path_z);

    const dir = platform.dirIterCreate(path_z) orelse {
        return raiseFileError(gc, "cannot open directory", args[0]);
    };

    return gc.allocDirectoryObject(@ptrCast(dir), include_dotfiles) catch {
        platform.dirIterDestroy(dir);
        return PrimitiveError.OutOfMemory;
    };
}

fn readDirectoryFn(args: []const Value) PrimitiveError!Value {
    if (!types.isDirectoryObject(args[0])) return primitives.typeError("read-directory", "directory-object", args[0]);
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const d = types.toDirectoryObject(args[0]);

    const dir_ptr = d.dir orelse return types.EOF;
    const dir: *platform.DirIter = @ptrCast(@alignCast(dir_ptr));

    while (dir.next()) |name| {
        if (std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) continue;
        if (!d.include_dotfiles and name.len > 0 and name[0] == '.') continue;
        return gc.allocString(name) catch return PrimitiveError.OutOfMemory;
    }

    platform.dirIterDestroy(dir);
    d.dir = null;
    return types.EOF;
}

fn closeDirectoryFn(args: []const Value) PrimitiveError!Value {
    if (!types.isDirectoryObject(args[0])) return primitives.typeError("close-directory", "directory-object", args[0]);
    const d = types.toDirectoryObject(args[0]);
    if (d.dir) |dir| {
        platform.dirIterDestroy(@ptrCast(@alignCast(dir)));
        d.dir = null;
    }
    return types.VOID;
}

// -------------------------------------------------------------------------
// POSIX time (SRFI-170 §3.10)
// -------------------------------------------------------------------------

fn posixTimeFn(args: []const Value) PrimitiveError!Value {
    _ = args;
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const rt = platform.realTime();
    return gc.allocSrfi18Time(@intCast(rt.sec), @intCast(rt.nsec), .utc) catch return PrimitiveError.OutOfMemory;
}

fn monotonicTimeFn(args: []const Value) PrimitiveError!Value {
    _ = args;
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const mono = platform.monotonicNs();
    return gc.allocSrfi18Time(@intCast(mono / 1_000_000_000), @intCast(mono % 1_000_000_000), .monotonic) catch return PrimitiveError.OutOfMemory;
}

// (file-info-type fi) — return type as symbol
fn fileInfoTypeFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    if (!types.isFileInfo(args[0])) return primitives.typeError("file-info-type", "file-info", args[0]);
    const fi = types.toObject(args[0]).as(types.FileInfo);
    const name: []const u8 = switch (fi.file_type) {
        .regular => "regular",
        .directory => "directory",
        .symlink => "symlink",
        .fifo => "fifo",
        .socket => "socket",
        .char_device => "char-special",
        .block_device => "block-special",
        .other => "unknown",
    };
    return gc.allocSymbol(name) catch return PrimitiveError.OutOfMemory;
}

// (temp-file-prefix) — return tempdir path
fn tempFilePrefixFn(args: []const Value) PrimitiveError!Value {
    _ = args;
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    var buf: [512]u8 = undefined;
    return gc.allocString(platform.tempFilePrefix(&buf)) catch return PrimitiveError.OutOfMemory;
}

// (create-temp-file [prefix]) — create a temp file and return its path
fn createTempFileFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;

    var prefix_buf: [512]u8 = undefined;
    var prefix: []const u8 = platform.tempFilePrefix(&prefix_buf);
    if (args.len > 0 and types.isString(args[0])) {
        const s = types.toObject(args[0]).as(types.SchemeString);
        prefix = s.data[0..s.len];
        try validatePathNoNul(prefix, args[0]);
    }

    // Build template: prefix + XXXXXX + null
    var template_buf: [256]u8 = undefined;
    if (prefix.len + 7 > template_buf.len) return raiseFileError(gc, "temp file prefix too long", if (args.len > 0) args[0] else types.FALSE);
    @memcpy(template_buf[0..prefix.len], prefix);
    @memcpy(template_buf[prefix.len..][0..6], "XXXXXX");
    template_buf[prefix.len + 6] = 0;

    if (comptime platform.is_windows) {
        // No mkstemp in the CRT: fill the template with entropy ourselves
        // and rely on O_EXCL to make creation race-free, retrying on
        // collision exactly as mkstemp does.
        var attempt: u32 = 0;
        while (attempt < 100) : (attempt += 1) {
            var seed = platform.monotonicNs() ^ (@as(u64, @intCast(platform.getPid())) << 32) ^ (@as(u64, attempt) << 56);
            const letters = "abcdefghijklmnopqrstuvwxyz0123456789";
            for (template_buf[prefix.len..][0..6]) |*ch| {
                ch.* = letters[@intCast(seed % letters.len)];
                seed /= letters.len;
            }
            const path_z: [:0]const u8 = template_buf[0 .. prefix.len + 6 :0];
            const wfd = platform.openWriteTruncExcl(path_z, 0o600) catch continue;
            _ = platform.close(wfd);
            return gc.allocString(path_z) catch return PrimitiveError.OutOfMemory;
        }
        return raiseFileError(gc, "cannot create temp file", types.FALSE);
    }

    const fd = mkstemp(@ptrCast(template_buf[0 .. prefix.len + 6 :0]));
    if (fd < 0) return raiseFileError(gc, "cannot create temp file", types.FALSE);
    _ = platform.close(fd);

    // Find actual path length (null-terminated)
    var path_len: usize = 0;
    while (path_len < template_buf.len and template_buf[path_len] != 0) path_len += 1;

    return gc.allocString(template_buf[0..path_len]) catch return PrimitiveError.OutOfMemory;
}
